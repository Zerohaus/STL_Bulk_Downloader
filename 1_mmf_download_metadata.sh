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
METADATA_429_BACKOFF_SEC="${MMF_METADATA_429_BACKOFF_SEC:-45}"
METADATA_MIN_FREE_MB="${MMF_METADATA_MIN_FREE_MB:-512}"
METADATA_CURL_RETRIES="${MMF_METADATA_CURL_RETRIES:-2}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_IDS_FILE="${MMF_MODEL_IDS_PATH:-${SCRIPT_DIR}/model_ids.txt}"
DOWNLOAD_ROOT="${MMF_DOWNLOAD_ROOT:-${SCRIPT_DIR}/downloads}"

JQ_CMD=""
DOWNLOAD_HTTP_CODE=""
DOWNLOAD_CURL_EXIT=0
DISK_CHECK_WARNED=0

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

    rm -f "$tmp_file"
    DOWNLOAD_HTTP_CODE=""
    DOWNLOAD_CURL_EXIT=0

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
        -w "%{http_code}" \
        "https://www.myminifactory.com/api/v2/objects/$model_id" \
        -o "$tmp_file")"
    DOWNLOAD_CURL_EXIT=$?
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

    attempt=1
    max_attempts=2

    while true; do
        download_metadata_once "$id" "$final_file"
        curl_exit="$DOWNLOAD_CURL_EXIT"
        http_code="$DOWNLOAD_HTTP_CODE"

        if [[ "$http_code" == "429" ]] && [[ "$attempt" -lt "$max_attempts" ]]; then
            echo -e "${YELLOW}Rate limited (HTTP 429). Backing off ${METADATA_429_BACKOFF_SEC}s and retrying once...${NC}"
            rm -f "$tmp_file"
            sleep "$METADATA_429_BACKOFF_SEC"
            attempt=$((attempt + 1))
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
