#!/bin/bash

# Bulk Downloader — model metadata (Step 1)
# Downloads JSON metadata for a list of model IDs from MyMiniFactory API
# This is STEP 1 - run this first to get model metadata, then use the STL downloader
#
# Prerequisites:
# 1. Create model_ids.txt with one model ID per line (no commas, no spaces)
# 2. Valid MyMiniFactory session cookie
# 3. Models must be owned/accessible by your account
#
# Usage:
# 1. Update COOKIE variable below with your session cookie
# 2. Ensure model_ids.txt has clean line endings (Unix format)
# 3. Run: bash download_metadata.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

emit_progress_event() {
    if [[ "${MMF_EMIT_PROGRESS:-0}" != "1" ]]; then
        return 0
    fi

    printf 'MMF_PROGRESS %s\n' "$1"
}

# UPDATE THIS: Get your cookie from browser developer tools (F12 -> Network -> Copy Cookie header)
COOKIE="${MMF_COOKIE:-REPLACE_WITH_YOUR_ACTUAL_COOKIE_STRING}"
METADATA_DELAY_SEC="${MMF_METADATA_DELAY_SEC:-6}"
METADATA_MIN_FREE_MB="${MMF_METADATA_MIN_FREE_MB:-512}"
# curl's own --retry treats HTTP 429/500/502/503/504 as transient and retries
# them itself (2s delay by default) before this script ever sees the failure.
# That silently re-hits the server 3x in a few seconds on a Cloudflare cooldown
# -- the exact rapid-retry behavior that extends the cooldown window. The
# script-level Cloudflare cooldown handling (see wait_out_cloudflare_cooldown)
# is the intended retry/backoff for that case now, so curl-level retries
# default to off; override via MMF_METADATA_CURL_RETRIES if you want curl to
# also retry on plain transient network errors.
METADATA_CURL_RETRIES="${MMF_METADATA_CURL_RETRIES:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_IDS_FILE="${MMF_MODEL_IDS_PATH:-${SCRIPT_DIR}/model_ids.txt}"
DOWNLOAD_ROOT="${MMF_DOWNLOAD_ROOT:-${SCRIPT_DIR}/downloads}"

JQ_CMD=""
DOWNLOAD_HTTP_CODE=""
DOWNLOAD_CURL_EXIT=0
DISK_CHECK_WARNED=0
DOWNLOAD_CF_MITIGATED=""

# Two distinct transient conditions get mistaken for a dead cookie if lumped
# together, and only the `cf-mitigated` response header reliably tells them
# apart (see _tools/MMF_DOWNLOADER_FINDINGS.md):
#   - A real Cloudflare edge challenge (`cf-mitigated: challenge`) is a long
#     cooldown; the same cf_clearance works again once it passes.
#   - MyMiniFactory's own app-level throttle (403/429/503 with NO cf-mitigated
#     header) is a separate, shorter-lived condition -- also self-healing, not
#     a credential problem, but retrying it fast is what escalates into a real
#     Cloudflare lockout.
# Both wait it out with an escalating ladder instead of counting as a failure.
CLOUDFLARE_COOLDOWN_STEPS_MIN=(30 45 60)
CLOUDFLARE_COOLDOWN_STAGE=0
APP_THROTTLE_STEPS_MIN=(5 10 15)
APP_THROTTLE_STAGE=0
# Unlike a domain-wide Cloudflare challenge, an app-throttle 403 can also mean
# "you genuinely don't have access to this one model" rather than a rate
# limit. Cap how many times a single model waits it out before falling through
# to the normal failure path, so a permanently-forbidden model can't retry
# forever.
MAX_APP_THROTTLE_ATTEMPTS_PER_ITEM=6

if [[ ! "$METADATA_MIN_FREE_MB" =~ ^[0-9]+$ ]]; then
    METADATA_MIN_FREE_MB=512
fi

if [[ ! "$METADATA_CURL_RETRIES" =~ ^[0-9]+$ ]]; then
    METADATA_CURL_RETRIES=2
fi

resolve_jq_cmd() {
    if command -v jq >/dev/null 2>&1; then
        JQ_CMD="jq"
        return
    fi

    if [[ -f "${SCRIPT_DIR}/jq.exe" ]]; then
        JQ_CMD="${SCRIPT_DIR}/jq.exe"
        return
    fi

    if [[ -f "${SCRIPT_DIR}/jq" ]]; then
        JQ_CMD="${SCRIPT_DIR}/jq"
    fi
}

get_available_kb() {
    local probe_path="$1"
    local check_path="$probe_path"

    if [[ -z "$check_path" ]]; then
        check_path="."
    fi

    if [[ ! -d "$check_path" ]]; then
        check_path="$(dirname "$check_path")"
    fi

    if command -v df >/dev/null 2>&1; then
        df -Pk "$check_path" 2>/dev/null | awk 'NR==2 {print $4}'
        return
    fi

    echo ""
}

ensure_min_free_space() {
    local probe_path="$1"
    local required_mb="$2"
    local context="$3"

    if [[ "$required_mb" -le 0 ]]; then
        return 0
    fi

    local available_kb
    available_kb="$(get_available_kb "$probe_path")"

    if [[ ! "$available_kb" =~ ^[0-9]+$ ]]; then
        if [[ "$DISK_CHECK_WARNED" -eq 0 ]]; then
            echo -e "${YELLOW}! Could not determine free disk space on this system. Continuing without proactive disk check.${NC}"
            DISK_CHECK_WARNED=1
        fi
        return 0
    fi

    local required_kb=$((required_mb * 1024))
    if (( available_kb < required_kb )); then
        local available_mb=$((available_kb / 1024))
        echo -e "${RED}Error: Low disk space (${context}).${NC}"
        echo -e "${RED}Required free space: ${required_mb} MB, available: ${available_mb} MB.${NC}"
        return 1
    fi

    return 0
}

abort_no_space() {
    local context="$1"
    echo ""
    echo -e "${RED}=======================================================${NC}"
    echo -e "${RED}STOPPING: No space left on device${NC}"
    echo -e "${RED}=======================================================${NC}"
    echo -e "${YELLOW}Context: ${context}${NC}"
    echo "Free disk space and run the script again."
    echo "Only fully validated JSON files are kept; partial files are discarded."
    exit 1
}

file_looks_like_html_error() {
    local file="$1"

    if [[ ! -f "$file" ]] || [[ ! -s "$file" ]]; then
        return 1
    fi

    if head -20 "$file" | grep -qi "<!DOCTYPE\|<html\|enable javascript\|cloudflare"; then
        return 0
    fi

    return 1
}

# A Cloudflare interstitial ("Just a moment...", managed/JS challenge) is a timed
# cooldown, not a dead session: the same cf_clearance cookie starts working again
# on its own once the window passes. Distinguish it from a real expired-cookie or
# logged-out page so it can be waited out instead of treated as a fatal failure.
is_cloudflare_cooldown_page() {
    local file="$1"

    if [[ ! -f "$file" ]] || [[ ! -s "$file" ]]; then
        return 1
    fi

    if head -60 "$file" | grep -qiE "just a moment|checking your browser|cf-chl|cf_chl_opt|cf-browser-verification|challenge-platform|__cf_chl_rt_tk|verifying you are human|cf-please-wait"; then
        return 0
    fi

    return 1
}

# True when a metadata download attempt hit a real Cloudflare edge challenge
# rather than an expired cookie. The `cf-mitigated` response header is the
# reliable signal (see _tools/MMF_DOWNLOADER_FINDINGS.md); the interstitial-page
# content check is a fallback for when the header wasn't captured.
is_cloudflare_challenge_failure() {
    local http_code="$1"
    local file="$2"
    local cf_mitigated="$3"

    if [[ "$cf_mitigated" == *[Cc]hallenge* ]]; then
        return 0
    fi

    if [[ -f "$file" ]] && is_cloudflare_cooldown_page "$file"; then
        return 0
    fi

    return 1
}

# True when a metadata download attempt hit MyMiniFactory's own app-level
# throttle: HTTP 403/429/503 with NO cf-mitigated header (so it's not
# Cloudflare stepping in). Also transient/self-healing, not a credential
# problem, but it wants a shorter quiet period than a real Cloudflare challenge.
is_app_throttle_failure() {
    local http_code="$1"
    local file="$2"
    local cf_mitigated="$3"

    case "$http_code" in
        403|429|503) ;;
        *) return 1 ;;
    esac

    if is_cloudflare_challenge_failure "$http_code" "$file" "$cf_mitigated"; then
        return 1
    fi

    return 0
}

# Waits out a real Cloudflare edge challenge. Escalates 30 -> 45 -> 60 minutes
# across consecutive hits within a run, then holds at 60; resets the next time
# a download actually succeeds.
wait_out_cloudflare_cooldown() {
    local context="$1"
    local max_index=$((${#CLOUDFLARE_COOLDOWN_STEPS_MIN[@]} - 1))
    local stage_index=$CLOUDFLARE_COOLDOWN_STAGE

    if [[ $stage_index -gt $max_index ]]; then
        stage_index=$max_index
    fi

    local wait_min="${CLOUDFLARE_COOLDOWN_STEPS_MIN[$stage_index]}"
    local wait_sec=$((wait_min * 60))

    echo ""
    echo -e "${YELLOW}=======================================================${NC}"
    echo -e "${YELLOW}Cloudflare challenge cooldown detected while ${context}${NC}"
    echo -e "${YELLOW}This is a timed rate limit, not an expired cookie — the${NC}"
    echo -e "${YELLOW}same cookie should work again once the wait is over.${NC}"
    echo -e "${YELLOW}Retrying immediately would only extend the cooldown, so${NC}"
    echo -e "${YELLOW}waiting ${wait_min} minute(s) before trying again...${NC}"
    echo -e "${YELLOW}=======================================================${NC}"
    emit_progress_event "{\"step\":\"cloudflare_cooldown\",\"event\":\"waiting\",\"minutes\":${wait_min},\"kind\":\"cloudflare\"}"

    sleep "$wait_sec"

    if [[ $CLOUDFLARE_COOLDOWN_STAGE -lt $max_index ]]; then
        CLOUDFLARE_COOLDOWN_STAGE=$((CLOUDFLARE_COOLDOWN_STAGE + 1))
    fi

    echo -e "${CYAN}Resuming after Cloudflare challenge cooldown wait.${NC}"
    emit_progress_event "{\"step\":\"cloudflare_cooldown\",\"event\":\"resumed\",\"kind\":\"cloudflare\"}"
}

# Waits out MyMiniFactory's own app-level throttle (no Cloudflare challenge
# involved). Escalates 5 -> 10 -> 15 minutes, then holds at 15; resets the next
# time a download actually succeeds.
wait_out_app_throttle() {
    local context="$1"
    local max_index=$((${#APP_THROTTLE_STEPS_MIN[@]} - 1))
    local stage_index=$APP_THROTTLE_STAGE

    if [[ $stage_index -gt $max_index ]]; then
        stage_index=$max_index
    fi

    local wait_min="${APP_THROTTLE_STEPS_MIN[$stage_index]}"
    local wait_sec=$((wait_min * 60))

    echo ""
    echo -e "${YELLOW}=======================================================${NC}"
    echo -e "${YELLOW}App-level throttle detected while ${context}${NC}"
    echo -e "${YELLOW}This is a timed rate limit, not an expired cookie — the${NC}"
    echo -e "${YELLOW}same cookie should work again once the wait is over.${NC}"
    echo -e "${YELLOW}Retrying immediately would only extend the cooldown, so${NC}"
    echo -e "${YELLOW}waiting ${wait_min} minute(s) before trying again...${NC}"
    echo -e "${YELLOW}=======================================================${NC}"
    emit_progress_event "{\"step\":\"cloudflare_cooldown\",\"event\":\"waiting\",\"minutes\":${wait_min},\"kind\":\"app_throttle\"}"

    sleep "$wait_sec"

    if [[ $APP_THROTTLE_STAGE -lt $max_index ]]; then
        APP_THROTTLE_STAGE=$((APP_THROTTLE_STAGE + 1))
    fi

    echo -e "${CYAN}Resuming after app-level throttle wait.${NC}"
    emit_progress_event "{\"step\":\"cloudflare_cooldown\",\"event\":\"resumed\",\"kind\":\"app_throttle\"}"
}

is_valid_metadata_json() {
    local file="$1"
    local expected_id="$2"

    if [[ ! -f "$file" ]] || [[ ! -s "$file" ]]; then
        return 1
    fi

    if file_looks_like_html_error "$file"; then
        return 1
    fi

    if [[ -n "$JQ_CMD" ]]; then
        "$JQ_CMD" -e --arg expected_id "$expected_id" '
            (type == "object")
            and (.id != null)
            and ((.id | tostring) == $expected_id)
            and (.name != null)
        ' "$file" >/dev/null 2>&1
        return $?
    fi

    grep -Eq "\"id\"[[:space:]]*:[[:space:]]*\"?${expected_id}\"?" "$file" 2>/dev/null && grep -q '"name"' "$file" 2>/dev/null
}

download_metadata_once() {
    local model_id="$1"
    local output_file="$2"
    local tmp_file="${output_file}.part"
    local headers_file="${output_file}.headers"

    rm -f "$tmp_file" "$headers_file"
    DOWNLOAD_HTTP_CODE=""
    DOWNLOAD_CURL_EXIT=0
    DOWNLOAD_CF_MITIGATED=""

    DOWNLOAD_HTTP_CODE="$(curl --silent --show-error \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:142.0) Gecko/20100101 Firefox/142.0" \
        -H "Accept: application/json" \
        -H "Accept-Language: en-US,en;q=0.5" \
        -H "Accept-Encoding: gzip, deflate, br, zstd" \
        -H "Referer: https://www.myminifactory.com/api-doc/index.html" \
        -H "Connection: keep-alive" \
        -H "Cookie: $COOKIE" \
        -H "Sec-Fetch-Dest: empty" \
        -H "Sec-Fetch-Mode: cors" \
        -H "Sec-Fetch-Site: same-origin" \
        -H "Priority: u=0" \
        --compressed \
        --retry "$METADATA_CURL_RETRIES" \
        --retry-delay 2 \
        -D "$headers_file" \
        -w "%{http_code}" \
        "https://www.myminifactory.com/api/v2/objects/$model_id" \
        -o "$tmp_file")"
    DOWNLOAD_CURL_EXIT=$?

    # cf-mitigated is the only reliable signal that Cloudflare (not MyMiniFactory's
    # own app-level throttle) issued this response. -L is not used here, so the
    # header dump is just the one response's headers.
    if [[ -f "$headers_file" ]]; then
        DOWNLOAD_CF_MITIGATED="$(grep -i '^cf-mitigated:' "$headers_file" | tail -1 | cut -d':' -f2- | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        rm -f "$headers_file"
    fi
}

cleanup_orphan_metadata_parts() {
    shopt -s nullglob
    local part_files=(model_*.json.part)
    local removed_count=${#part_files[@]}

    if [[ "$removed_count" -gt 0 ]]; then
        rm -f "${part_files[@]}"
        echo -e "${YELLOW}! Removed ${removed_count} orphan .part metadata file(s) from previous interrupted runs.${NC}"
    fi

    shopt -u nullglob
}

resolve_jq_cmd

# Check if model_ids.txt exists
if [[ ! -f "$MODEL_IDS_FILE" ]]; then
    echo -e "${RED}Error: model_ids.txt not found!${NC}"
    echo "Create a file with one model ID per line, like:"
    echo "409352"
    echo "409348" 
    echo "496377"
    exit 1
fi

# Create downloads directory
mkdir -p "$DOWNLOAD_ROOT"
cd "$DOWNLOAD_ROOT" || exit
cleanup_orphan_metadata_parts

# Fix Windows line endings if present (common issue)
if grep -q $'\r' "$MODEL_IDS_FILE"; then
    echo -e "${BLUE}Fixing Windows line endings in model_ids.txt...${NC}"
    temp_ids_file="$(mktemp "${TMPDIR:-/tmp}/model_ids.XXXXXX")"
    tr -d '\r' < "$MODEL_IDS_FILE" > "$temp_ids_file"
    mv "$temp_ids_file" "$MODEL_IDS_FILE"
fi

# Count total models
total=$(grep -cve '^[[:space:]]*$' "$MODEL_IDS_FILE")
if [[ "$total" -eq 0 ]]; then
    echo -e "${RED}Error: model_ids.txt is empty.${NC}"
    exit 1
fi

current=0

echo -e "${BLUE}Starting download of $total model metadata files...${NC}"
emit_progress_event "{\"step\":\"metadata\",\"event\":\"start\",\"total\":$total}"
echo "JSON files will be saved in: $DOWNLOAD_ROOT"
echo "Rate limited (~10 requests/min, ${METADATA_DELAY_SEC}s delay between requests)"
echo -e "${CYAN}Minimum free space required before each download: ${METADATA_MIN_FREE_MB} MB${NC}"
if [[ -z "$JQ_CMD" ]]; then
    echo -e "${YELLOW}! jq not found: using basic metadata validation only. Install jq for stronger JSON validation.${NC}"
fi
echo ""

# Read each ID and download metadata
while read -r id; do
    # Skip empty lines
    id="$(printf "%s" "$id" | tr -d '\r' | xargs)"
    [[ -z "$id" ]] && continue

    if [[ ! "$id" =~ ^[0-9]+$ ]]; then
        echo -e "${YELLOW}[SKIP] Invalid model ID entry: '$id'${NC}"
        continue
    fi
    
    current=$((current + 1))
    emit_progress_event "{\"step\":\"metadata\",\"event\":\"item\",\"status\":\"started\",\"modelId\":\"$id\",\"current\":$current,\"total\":$total}"

    final_file="model_${id}.json"
    tmp_file="${final_file}.part"

    if [[ -f "$final_file" ]] && [[ -s "$final_file" ]]; then
        if is_valid_metadata_json "$final_file" "$id"; then
            emit_progress_event "{\"step\":\"metadata\",\"event\":\"item\",\"status\":\"skipped\",\"modelId\":\"$id\",\"current\":$current,\"total\":$total}"
            echo -e "${GREEN}[$current/$total] Skipping model $id (metadata already exists — resume safe)${NC}"
            continue
        else
            echo -e "${YELLOW}[$current/$total] Found invalid existing metadata for model $id. Re-downloading.${NC}"
            rm -f "$final_file"
        fi
    fi

    if ! ensure_min_free_space "$DOWNLOAD_ROOT" "$METADATA_MIN_FREE_MB" "before downloading model $id"; then
        abort_no_space "before downloading model $id"
    fi

    echo -e "${BLUE}[$current/$total] Downloading metadata for model $id...${NC}"

    app_throttle_attempts=0
    while true; do
        download_metadata_once "$id" "$final_file"
        curl_exit="$DOWNLOAD_CURL_EXIT"
        http_code="$DOWNLOAD_HTTP_CODE"

        if [[ "$curl_exit" -eq 0 ]] && is_cloudflare_challenge_failure "$http_code" "$tmp_file" "$DOWNLOAD_CF_MITIGATED"; then
            rm -f "$tmp_file"
            wait_out_cloudflare_cooldown "downloading metadata for model $id"
            continue
        fi

        if [[ "$curl_exit" -eq 0 ]] && [[ $app_throttle_attempts -lt $MAX_APP_THROTTLE_ATTEMPTS_PER_ITEM ]] && is_app_throttle_failure "$http_code" "$tmp_file" "$DOWNLOAD_CF_MITIGATED"; then
            app_throttle_attempts=$((app_throttle_attempts + 1))
            rm -f "$tmp_file"
            wait_out_app_throttle "downloading metadata for model $id"
            continue
        fi

        break
    done

    # Check if download was successful
    if [[ "$curl_exit" -eq 23 ]]; then
        rm -f "$tmp_file" "$final_file"
        emit_progress_event "{\"step\":\"metadata\",\"event\":\"item\",\"status\":\"failed\",\"modelId\":\"$id\",\"current\":$current,\"total\":$total}"
        abort_no_space "downloading metadata for model $id"
    elif [[ "$curl_exit" -ne 0 ]]; then
        echo -e "${RED}Failed to download metadata for model $id (curl exit $curl_exit, HTTP ${http_code:-unknown})${NC}"
        rm -f "$tmp_file" "$final_file"
        emit_progress_event "{\"step\":\"metadata\",\"event\":\"item\",\"status\":\"failed\",\"modelId\":\"$id\",\"current\":$current,\"total\":$total}"
    elif [[ "$http_code" != "200" ]]; then
        echo -e "${RED}Failed to download metadata for model $id (HTTP ${http_code:-unknown})${NC}"
        rm -f "$tmp_file" "$final_file"
        emit_progress_event "{\"step\":\"metadata\",\"event\":\"item\",\"status\":\"failed\",\"modelId\":\"$id\",\"current\":$current,\"total\":$total}"
    elif ! is_valid_metadata_json "$tmp_file" "$id"; then
        echo -e "${RED}Failed metadata validation for model $id (truncated/invalid JSON or unexpected content)${NC}"
        rm -f "$tmp_file" "$final_file"
        emit_progress_event "{\"step\":\"metadata\",\"event\":\"item\",\"status\":\"failed\",\"modelId\":\"$id\",\"current\":$current,\"total\":$total}"
    elif ! mv -f "$tmp_file" "$final_file"; then
        rm -f "$tmp_file" "$final_file"
        emit_progress_event "{\"step\":\"metadata\",\"event\":\"item\",\"status\":\"failed\",\"modelId\":\"$id\",\"current\":$current,\"total\":$total}"
        abort_no_space "saving metadata file for model $id"
    else
        echo -e "${GREEN}Successfully downloaded metadata for model $id${NC}"
        CLOUDFLARE_COOLDOWN_STAGE=0
        APP_THROTTLE_STAGE=0
        emit_progress_event "{\"step\":\"metadata\",\"event\":\"item\",\"status\":\"downloaded\",\"modelId\":\"$id\",\"current\":$current,\"total\":$total}"
    fi
    
    # Rate limiting between requests
    if [[ $current -lt $total ]]; then
        sleep "$METADATA_DELAY_SEC"
    fi
    
done < "$MODEL_IDS_FILE"

emit_progress_event "{\"step\":\"metadata\",\"event\":\"done\",\"total\":$total}"

echo ""
echo -e "${GREEN}Metadata download complete!${NC}"
echo "Downloaded files are in: $DOWNLOAD_ROOT"
echo "Total JSON files: $(ls -1 model_*.json 2>/dev/null | wc -l)"
echo ""
echo -e "${BLUE}Next step: Use the STL downloader script to get actual 3D files${NC}"

# Common Issues and Solutions:
#
# 1. "Failed to download" - Check cookie expiration, get fresh cookie from browser
# 2. All downloads fail - Cookie expired or malformed, copy fresh cookie from developer tools
# 3. Some models fail - Model might be private, deleted, or require different permissions
# 4. "model_ids.txt not found" - Create file with one model ID per line
# 5. Windows line ending issues - Script automatically fixes these
#
# Tips:
# - Copy cookie from browser: F12 -> Network tab -> find any request -> Copy Cookie header
# - Cookies expire frequently (30-60 minutes), refresh as needed
# - Model IDs are numbers like 409352, not full URLs
# - One ID per line in model_ids.txt, no commas or extra formatting
# - This downloads metadata only, use STL downloader script for actual files
