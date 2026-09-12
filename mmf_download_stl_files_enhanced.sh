#!/bin/bash

# Bulk Downloader — STL/ZIP files, enhanced (Step 2)
# Downloads actual 3D printable files from a list of model IDs
# This is STEP 2 - run AFTER the metadata downloader creates JSON files
# 
# NEW in Enhanced Edition:
# - Cookie validation before starting
# - Automatic HTML error page detection
# - Test mode to verify setup before bulk download
# - Better error messages with troubleshooting steps
# - Stops on systematic errors (e.g., all downloads failing)
# 
# Prerequisites:
# 1. JSON metadata files from Step 1 (model_*.json files)
# 2. Valid MyMiniFactory session cookie
# 3. jq installed (JSON parser) - download from https://github.com/stedolan/jq/releases
#
# Usage:
# 1. Run metadata downloader first (Step 1)
# 2. Update COOKIE variable below with your session cookie
# 3. Place jq or jq.exe in same directory
# 4. Run in test mode first: bash download_stl_files.sh --test
# 5. If test passes, run full: bash download_stl_files.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# CONFIGURATION
# ============================================================================
# UPDATE THIS: Get your cookie from browser developer tools
# 
# HOW TO GET YOUR COOKIE (IMPORTANT - READ CAREFULLY):
# 1. Open MyMiniFactory in your browser and log in
# 2. Navigate to any model you own
# 3. Click download button for any file (Resin, FDM, etc.)
# 4. Open Developer Tools (F12)
# 5. Go to Network tab
# 6. Find the request to "myminifactory.com/download/XXXXX?archive_id=XXXXX"
# 7. Click on that request
# 8. Scroll to "Request Headers" section
# 9. Find the "Cookie:" header
# 10. Copy ONLY the value (everything after "Cookie: ")
# 11. Paste below between the single quotes
#
# Your cookie MUST include these parts:
# - PHPSESSID=...
# - cf_clearance=... (Cloudflare token - CRITICAL)
# - Various _ga and _pk tracking cookies
#
# If you're missing cf_clearance, you'll get "enable Javascript" errors
COOKIE="${MMF_COOKIE:-REPLACE_WITH_YOUR_ACTUAL_COOKIE_STRING}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ============================================================================

# Configuration
TEST_MODE=false
MAX_CONSECUTIVE_FAILURES=3  # Stop if this many downloads fail in a row
STL_FILE_DELAY_SEC="${MMF_STL_FILE_DELAY_SEC:-5}"
IMAGE_DELAY_SEC="${MMF_IMAGE_DELAY_SEC:-3}"

# --- Adaptive pacing -------------------------------------------------------
# Two full-library pulls proved the limiter is not a published quota: one run
# needed ~68s between requests, another did 233 models at a flat 12s with zero
# throttles. A hard-coded rate cannot survive both, so STL_FILE_DELAY_SEC is
# only the *floor*. The live gap widens on every app-level throttle and creeps
# back down after a run of clean responses.
ADAPTIVE_PACING="${MMF_ADAPTIVE_PACING:-1}"
ADAPTIVE_DELAY_MAX_SEC="${MMF_ADAPTIVE_DELAY_MAX_SEC:-120}"
# Widen multiplier (x1.8) and recovery divisor (/1.3), expressed as integer
# percentages so the arithmetic stays inside bash.
ADAPTIVE_WIDEN_PCT="${MMF_ADAPTIVE_WIDEN_PCT:-180}"
ADAPTIVE_NARROW_PCT="${MMF_ADAPTIVE_NARROW_PCT:-77}"
# Clean downloads required before the gap is allowed to narrow one step.
ADAPTIVE_RECOVERY_STREAK="${MMF_ADAPTIVE_RECOVERY_STREAK:-10}"
ADAPTIVE_DELAY_SEC="$STL_FILE_DELAY_SEC"
ADAPTIVE_CLEAN_STREAK=0

# --- Whole-model archive route --------------------------------------------
# /download/<id> returns an entire model in a single request; fetching each
# file from files.items[] separately costs 3-4x the requests against the only
# endpoint that throttles. Prefer the one-request route and fall back to
# per-file only when it is unavailable or incomplete.
WHOLE_MODEL_ROUTE="${MMF_WHOLE_MODEL_ROUTE:-1}"
MMF_BASE_URL="${MMF_BASE_URL:-https://www.myminifactory.com}"
MIN_FREE_SPACE_MB="${MMF_MIN_FREE_SPACE_MB:-2048}"
DISK_MARGIN_MB_PER_FILE="${MMF_DISK_MARGIN_MB_PER_FILE:-512}"
DISK_MARGIN_MB_MODEL="${MMF_DISK_MARGIN_MB_MODEL:-1024}"
# Pre-flight estimate for a file whose metadata declares no size. Only used to
# sanity-check free space before a model starts; ensure_file_download_space
# re-checks against the real figure before every individual file.
UNKNOWN_FILE_ESTIMATE_MB="${MMF_UNKNOWN_FILE_ESTIMATE_MB:-64}"
ZIP32_LIMIT_BYTES=4294967295
ZIP64_RETRY_BYTES=3500000000
# curl's own --retry treats HTTP 429/500/502/503/504 as transient and retries
# them itself (2s delay by default) before this script ever sees the failure.
# That silently re-hits the server 3x in a few seconds on a Cloudflare cooldown
# -- the exact rapid-retry behavior that extends the cooldown window. The
# script-level Cloudflare cooldown handling (see wait_out_cloudflare_cooldown)
# is the intended retry/backoff for that case now, so curl-level retries
# default to off; override via MMF_CURL_RETRIES if you want curl to also
# retry on plain transient network errors.
CURL_RETRIES="${MMF_CURL_RETRIES:-0}"
MODEL_IDS_FILTER_RAW="${MMF_MODEL_IDS_FILTER:-}"

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
# "you genuinely don't have access to this one file" rather than a rate limit.
# Cap how many times a single item waits it out before falling through to the
# normal failure path, so a permanently-forbidden item can't retry forever.
MAX_APP_THROTTLE_ATTEMPTS_PER_ITEM=6

DOWNLOAD_LAST_CURL_EXIT=0
DOWNLOAD_LAST_HTTP_CODE=""
DOWNLOAD_LAST_TMP_FILE=""
DOWNLOAD_LAST_FAILURE_REASON=""
DOWNLOAD_LAST_ORIGINAL_URL=""
DOWNLOAD_LAST_SANITIZED_URL=""
DOWNLOAD_LAST_URL_SANITIZATION_NOTE=""
DOWNLOAD_LAST_URL_SANITIZATION_CHANGED=0
DOWNLOAD_LAST_CF_MITIGATED=""
DISK_CHECK_WARNED=0
MODEL_IDS_FILTER_PADDED=""
MODEL_IDS_FILTER_ACTIVE=0
ASSET_PROGRESS_TOTAL_UNITS=0
ASSET_PROGRESS_DONE_UNITS=0
ASSET_PROGRESS_MODELS_DONE=0
ZIP_VALIDATE_REASON=""
ZIP_COMPRESS_TOOL=""
ZIP_COMPRESS_PHASE=""
ZIP_COMPRESS_FAILURE=""
ZIP_COMPRESS_STDERR=""

emit_progress_event() {
    if [[ "${MMF_EMIT_PROGRESS:-0}" != "1" ]]; then
        return 0
    fi

    printf 'MMF_PROGRESS %s\n' "$1"
}

trim_field() {
    local value="$1"

    value="${value//$'\r'/}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    printf "%s" "$value"
}

sanitize_url() {
    local raw_url="$1"
    local sanitized_url=""
    local transformed_url=""
    local -a note_parts=()

    DOWNLOAD_LAST_URL_SANITIZATION_NOTE=""
    DOWNLOAD_LAST_URL_SANITIZATION_CHANGED=0

    sanitized_url="$(trim_field "$raw_url")"
    if [[ "$sanitized_url" != "$raw_url" ]]; then
        note_parts+=("trimmed leading/trailing whitespace or CR/LF")
    fi

    transformed_url="$(printf "%s" "$sanitized_url" | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177')"
    if [[ "$transformed_url" != "$sanitized_url" ]]; then
        note_parts+=("removed invisible control characters")
        sanitized_url="$transformed_url"
    fi

    if [[ -n "$sanitized_url" && "$sanitized_url" != "null" ]]; then
        transformed_url="$sanitized_url"
        transformed_url="${transformed_url// /%20}"
        transformed_url="${transformed_url//\'/%27}"
        transformed_url="${transformed_url//\"/%22}"
        transformed_url="${transformed_url//</%3C}"
        transformed_url="${transformed_url//>/%3E}"
        transformed_url="${transformed_url//\\/%5C}"
        transformed_url="${transformed_url//\`/%60}"
        transformed_url="${transformed_url//\{/%7B}"
        transformed_url="${transformed_url//\}/%7D}"
        transformed_url="${transformed_url//|/%7C}"
        transformed_url="${transformed_url//\^/%5E}"
        transformed_url="${transformed_url//\[/%5B}"
        transformed_url="${transformed_url//\]/%5D}"
        transformed_url="${transformed_url//\(/%28}"
        transformed_url="${transformed_url//\)/%29}"

        if [[ "$transformed_url" != "$sanitized_url" ]]; then
            note_parts+=("encoded unsafe URL characters")
            sanitized_url="$transformed_url"
        fi
    fi

    if [[ -z "$sanitized_url" || "$sanitized_url" == "null" ]]; then
        note_parts+=("empty URL after sanitization")
    fi

    if [[ "$sanitized_url" =~ [[:space:]] ]]; then
        note_parts+=("contains whitespace after sanitization")
    fi

    if [[ ! "$sanitized_url" =~ ^https?://[^/?#[:space:]]+ ]]; then
        note_parts+=("URL must start with http(s):// and include a host")
    fi

    if [[ ${#note_parts[@]} -gt 0 ]]; then
        local joined_notes="${note_parts[0]}"
        local note_index=1
        while [[ "$note_index" -lt "${#note_parts[@]}" ]]; do
            joined_notes="${joined_notes}; ${note_parts[$note_index]}"
            note_index=$((note_index + 1))
        done
        DOWNLOAD_LAST_URL_SANITIZATION_NOTE="$joined_notes"
    fi

    if [[ "$sanitized_url" != "$raw_url" ]]; then
        DOWNLOAD_LAST_URL_SANITIZATION_CHANGED=1
    fi

    if [[ -z "$sanitized_url" || "$sanitized_url" == "null" ]]; then
        return 1
    fi

    if [[ ! "$sanitized_url" =~ ^https?://[^/?#[:space:]]+ ]]; then
        return 1
    fi

    if [[ "$sanitized_url" =~ [[:space:]] ]]; then
        return 1
    fi

    printf "%s" "$sanitized_url"
}

print_url_debug() {
    local context_label="$1"

    echo -e "  ${CYAN}[URL-DEBUG] ${context_label}${NC}"
    echo "    Original URL: ${DOWNLOAD_LAST_ORIGINAL_URL:-<empty>}"
    echo "    Sanitized URL: ${DOWNLOAD_LAST_SANITIZED_URL:-<empty>}"
    if [[ -n "$DOWNLOAD_LAST_URL_SANITIZATION_NOTE" ]]; then
        echo "    URL adjustments: $DOWNLOAD_LAST_URL_SANITIZATION_NOTE"
    fi
}

load_model_ids_filter() {
    local token
    local normalized_filter
    MODEL_IDS_FILTER_PADDED=""
    MODEL_IDS_FILTER_ACTIVE=0

    normalized_filter="${MODEL_IDS_FILTER_RAW//$'\r'/ }"
    normalized_filter="${normalized_filter//,/ }"
    normalized_filter="${normalized_filter//;/ }"

    for token in $normalized_filter; do
        token="$(trim_field "$token")"
        if [[ "$token" =~ ^[0-9]+$ ]] && [[ "$MODEL_IDS_FILTER_PADDED" != *" $token "* ]]; then
            MODEL_IDS_FILTER_PADDED="${MODEL_IDS_FILTER_PADDED} ${token}"
        fi
    done

    if [[ -n "$MODEL_IDS_FILTER_PADDED" ]]; then
        MODEL_IDS_FILTER_PADDED="${MODEL_IDS_FILTER_PADDED} "
        MODEL_IDS_FILTER_ACTIVE=1
    fi
}

is_model_id_selected() {
    local model_id="$1"
    [[ "$MODEL_IDS_FILTER_ACTIVE" -eq 0 || "$MODEL_IDS_FILTER_PADDED" == *" $model_id "* ]]
}

emit_asset_progress_start() {
    emit_progress_event "{\"step\":\"assets\",\"event\":\"start\",\"totalModels\":$1,\"workTotal\":$2,\"workDone\":0,\"modelsDone\":0}"
}

emit_asset_progress_model_start() {
    emit_progress_event "{\"step\":\"assets\",\"event\":\"model-start\",\"modelId\":\"$1\",\"currentModel\":$2,\"totalModels\":$3,\"workTotal\":$ASSET_PROGRESS_TOTAL_UNITS,\"workDone\":$ASSET_PROGRESS_DONE_UNITS,\"modelsDone\":$ASSET_PROGRESS_MODELS_DONE}"
}

emit_asset_progress_unit() {
    local model_id="$1"
    local kind="$2"
    local status="$3"

    ASSET_PROGRESS_DONE_UNITS=$((ASSET_PROGRESS_DONE_UNITS + 1))
    if [[ "$ASSET_PROGRESS_TOTAL_UNITS" -gt 0 && "$ASSET_PROGRESS_DONE_UNITS" -gt "$ASSET_PROGRESS_TOTAL_UNITS" ]]; then
        ASSET_PROGRESS_DONE_UNITS="$ASSET_PROGRESS_TOTAL_UNITS"
    fi

    emit_progress_event "{\"step\":\"assets\",\"event\":\"unit\",\"modelId\":\"$model_id\",\"kind\":\"$kind\",\"status\":\"$status\",\"workTotal\":$ASSET_PROGRESS_TOTAL_UNITS,\"workDone\":$ASSET_PROGRESS_DONE_UNITS,\"modelsDone\":$ASSET_PROGRESS_MODELS_DONE}"
}

emit_asset_progress_model_done() {
    local model_id="$1"
    ASSET_PROGRESS_MODELS_DONE=$((ASSET_PROGRESS_MODELS_DONE + 1))
    emit_progress_event "{\"step\":\"assets\",\"event\":\"model-done\",\"modelId\":\"$model_id\",\"workTotal\":$ASSET_PROGRESS_TOTAL_UNITS,\"workDone\":$ASSET_PROGRESS_DONE_UNITS,\"modelsDone\":$ASSET_PROGRESS_MODELS_DONE}"
}

if [[ ! "$MIN_FREE_SPACE_MB" =~ ^[0-9]+$ ]]; then
    MIN_FREE_SPACE_MB=2048
fi

if [[ ! "$DISK_MARGIN_MB_PER_FILE" =~ ^[0-9]+$ ]]; then
    DISK_MARGIN_MB_PER_FILE=512
fi

if [[ ! "$DISK_MARGIN_MB_MODEL" =~ ^[0-9]+$ ]]; then
    DISK_MARGIN_MB_MODEL=1024
fi

if [[ ! "$UNKNOWN_FILE_ESTIMATE_MB" =~ ^[0-9]+$ ]] || [[ "$UNKNOWN_FILE_ESTIMATE_MB" -eq 0 ]]; then
    UNKNOWN_FILE_ESTIMATE_MB=64
fi

if [[ ! "$CURL_RETRIES" =~ ^[0-9]+$ ]]; then
    CURL_RETRIES=2
fi

# Parse command line arguments
if [[ "$1" == "--test" ]]; then
    TEST_MODE=true
fi

# Function to validate cookie format
validate_cookie() {
    if [[ "$COOKIE" == "REPLACE_WITH_YOUR_ACTUAL_COOKIE_STRING" ]]; then
        echo -e "${RED}ERROR: Cookie not configured!${NC}"
        echo "Please update the COOKIE variable in this script with your actual session cookie."
        echo "See the HOW TO GET YOUR COOKIE instructions in the script."
        return 1
    fi
    
    if [[ ! "$COOKIE" =~ PHPSESSID ]]; then
        echo -e "${YELLOW}WARNING: Cookie missing PHPSESSID - this may not work${NC}"
    fi
    
    if [[ ! "$COOKIE" =~ cf_clearance ]]; then
        echo -e "${YELLOW}WARNING: Cookie missing cf_clearance (Cloudflare token)${NC}"
        echo "This is the most common cause of 'enable Javascript' errors."
        echo "Make sure you copied the cookie from a DOWNLOAD request, not a page view."
        return 1
    fi
    
    echo -e "${GREEN}[OK] Cookie format looks valid${NC}"
    return 0
}

# Function to check if downloaded file is an HTML error page
is_html_error() {
    local file="$1"
    
    if [[ ! -f "$file" ]] || [[ ! -s "$file" ]]; then
        return 1
    fi
    
    # Check if file starts with HTML tags or common error messages
    if head -20 "$file" | grep -qi "<!DOCTYPE\|<html\|enable javascript\|cloudflare"; then
        return 0
    fi
    
    return 1
}

# Function to display error page content
show_error_content() {
    local file="$1"
    echo -e "${CYAN}Error page content (first 20 lines):${NC}"
    head -20 "$file" | sed 's/^/  /'
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

# True when the most recent download_file_with_guards call hit a real Cloudflare
# edge challenge rather than an expired cookie. The `cf-mitigated` response
# header is the reliable signal (see _tools/MMF_DOWNLOADER_FINDINGS.md); the
# interstitial-page content check is a fallback for when headers weren't
# captured for some reason.
is_cloudflare_challenge_failure() {
    if [[ "$DOWNLOAD_LAST_CF_MITIGATED" == *[Cc]hallenge* ]]; then
        return 0
    fi

    if [[ -n "$DOWNLOAD_LAST_TMP_FILE" ]] && [[ -f "$DOWNLOAD_LAST_TMP_FILE" ]] && is_cloudflare_cooldown_page "$DOWNLOAD_LAST_TMP_FILE"; then
        return 0
    fi

    return 1
}

# True when the most recent download_file_with_guards call hit MyMiniFactory's
# own app-level throttle: HTTP 403/429/503 with NO cf-mitigated header (so it's
# not Cloudflare stepping in). Also transient/self-healing, not a credential
# problem, but it wants a shorter quiet period than a real Cloudflare challenge.
is_app_throttle_failure() {
    case "$DOWNLOAD_LAST_HTTP_CODE" in
        403|429|503) ;;
        *) return 1 ;;
    esac

    if is_cloudflare_challenge_failure; then
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

    widen_adaptive_delay

    echo -e "${CYAN}Resuming after Cloudflare challenge cooldown wait.${NC}"
    emit_progress_event "{\"step\":\"cloudflare_cooldown\",\"event\":\"resumed\",\"kind\":\"cloudflare\"}"
}

# Waits out MyMiniFactory's own app-level throttle (no Cloudflare challenge
# involved). Escalates 5 -> 10 -> 15 minutes, then holds at 15; resets the next
# time a download actually succeeds.
# --- Adaptive pacing -------------------------------------------------------
# A 403 without a cf-mitigated header is the limiter saying "too fast *now*".
# Treat it as permanent information about the pace rather than a one-off: widen
# the inter-request gap and only creep back down after a sustained clean run.
widen_adaptive_delay() {
    local previous="$ADAPTIVE_DELAY_SEC"
    local widened

    ADAPTIVE_CLEAN_STREAK=0

    if [[ "$ADAPTIVE_PACING" != "1" ]]; then
        return 0
    fi

    widened=$(( (ADAPTIVE_DELAY_SEC * ADAPTIVE_WIDEN_PCT + 99) / 100 ))
    if [[ "$widened" -le "$ADAPTIVE_DELAY_SEC" ]]; then
        widened=$((ADAPTIVE_DELAY_SEC + 1))
    fi
    if [[ "$widened" -gt "$ADAPTIVE_DELAY_MAX_SEC" ]]; then
        widened="$ADAPTIVE_DELAY_MAX_SEC"
    fi

    ADAPTIVE_DELAY_SEC="$widened"

    if [[ "$ADAPTIVE_DELAY_SEC" -ne "$previous" ]]; then
        echo -e "  ${YELLOW}[PACE] Widening request gap ${previous}s -> ${ADAPTIVE_DELAY_SEC}s after throttle${NC}"
        emit_progress_event "{\"step\":\"pacing\",\"event\":\"widened\",\"delaySec\":${ADAPTIVE_DELAY_SEC}}"
    fi
}

# Called after each clean download. Narrowing is deliberately slower than
# widening -- a pace that was punished once is more likely to be punished again.
note_adaptive_success() {
    local previous="$ADAPTIVE_DELAY_SEC"
    local narrowed

    if [[ "$ADAPTIVE_PACING" != "1" ]]; then
        return 0
    fi

    if [[ "$ADAPTIVE_DELAY_SEC" -le "$STL_FILE_DELAY_SEC" ]]; then
        ADAPTIVE_CLEAN_STREAK=0
        return 0
    fi

    ADAPTIVE_CLEAN_STREAK=$((ADAPTIVE_CLEAN_STREAK + 1))
    if [[ "$ADAPTIVE_CLEAN_STREAK" -lt "$ADAPTIVE_RECOVERY_STREAK" ]]; then
        return 0
    fi

    ADAPTIVE_CLEAN_STREAK=0
    narrowed=$(( (ADAPTIVE_DELAY_SEC * ADAPTIVE_NARROW_PCT) / 100 ))
    if [[ "$narrowed" -ge "$ADAPTIVE_DELAY_SEC" ]]; then
        narrowed=$((ADAPTIVE_DELAY_SEC - 1))
    fi
    if [[ "$narrowed" -lt "$STL_FILE_DELAY_SEC" ]]; then
        narrowed="$STL_FILE_DELAY_SEC"
    fi

    ADAPTIVE_DELAY_SEC="$narrowed"

    if [[ "$ADAPTIVE_DELAY_SEC" -ne "$previous" ]]; then
        echo -e "  ${CYAN}[PACE] Narrowing request gap ${previous}s -> ${ADAPTIVE_DELAY_SEC}s after ${ADAPTIVE_RECOVERY_STREAK} clean downloads${NC}"
        emit_progress_event "{\"step\":\"pacing\",\"event\":\"narrowed\",\"delaySec\":${ADAPTIVE_DELAY_SEC}}"
    fi
}

adaptive_sleep() {
    local delay="$ADAPTIVE_DELAY_SEC"

    if [[ "$ADAPTIVE_PACING" != "1" ]]; then
        delay="$STL_FILE_DELAY_SEC"
    fi

    if [[ "$delay" -gt 0 ]]; then
        sleep "$delay"
    fi
}

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

    widen_adaptive_delay

    echo -e "${CYAN}Resuming after app-level throttle wait.${NC}"
    emit_progress_event "{\"step\":\"cloudflare_cooldown\",\"event\":\"resumed\",\"kind\":\"app_throttle\"}"
}

get_file_size() {
    local file="$1"
    stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "unknown"
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

format_bytes_human() {
    local bytes="$1"

    if [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
        printf "unknown"
        return
    fi

    if (( bytes >= 1073741824 )); then
        printf "%d.%02d GiB" $((bytes / 1073741824)) $(((bytes % 1073741824) * 100 / 1073741824))
        return
    fi

    if (( bytes >= 1048576 )); then
        printf "%d.%02d MiB" $((bytes / 1048576)) $(((bytes % 1048576) * 100 / 1048576))
        return
    fi

    if (( bytes >= 1024 )); then
        printf "%d KiB" $((bytes / 1024))
        return
    fi

    printf "%d B" "$bytes"
}

log_disk_context() {
    local probe_path="$1"
    local context_label="$2"
    local required_mb="${3:-}"
    local available_kb=""

    available_kb="$(get_available_kb "$probe_path")"
    if [[ "$available_kb" =~ ^[0-9]+$ ]]; then
        echo -e "  ${CYAN}[DISK] ${context_label} — free: $(format_bytes_human $((available_kb * 1024)))${NC}"
    else
        echo -e "  ${CYAN}[DISK] ${context_label} — free: unknown on this system${NC}"
    fi

    if [[ "$required_mb" =~ ^[0-9]+$ ]] && [[ "$required_mb" -gt 0 ]]; then
        echo -e "  ${CYAN}[DISK] ${context_label} — need at least: ${required_mb} MB ($(format_bytes_human $((required_mb * 1024 * 1024))))${NC}"
    fi
}

metadata_size_to_bytes() {
    local raw_size="$1"

    if [[ -z "$raw_size" || "$raw_size" == "null" ]]; then
        printf "0"
        return
    fi

    if [[ "$raw_size" =~ ^[0-9]+$ ]]; then
        printf "%s" "$raw_size"
        return
    fi

    if [[ "$raw_size" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        printf "%.0f" "$raw_size" 2>/dev/null || printf "0"
        return
    fi

    printf "0"
}

required_mb_for_file_download() {
    local file_bytes="$1"
    local required_mb="$MIN_FREE_SPACE_MB"

    if [[ "$file_bytes" =~ ^[0-9]+$ ]] && [[ "$file_bytes" -gt 0 ]]; then
        required_mb=$(( (file_bytes + 1024 * 1024 - 1) / 1024 / 1024 + DISK_MARGIN_MB_PER_FILE ))
        if (( required_mb < MIN_FREE_SPACE_MB )); then
            required_mb=$MIN_FREE_SPACE_MB
        fi
    fi

    printf "%s" "$required_mb"
}

get_model_download_size_stats() {
    local json_file="$1"
    local stats_line=""

    stats_line="$($JQ_CMD -r '
        def to_bytes:
            if . == null then 0
            elif type == "number" then (if . < 0 then 0 else . end)
            elif type == "string" then
                if test("^[0-9]+$") then tonumber
                elif test("^[0-9]+(\\.[0-9]+)?$") then (tonumber | floor)
                else 0
                end
            else 0 end;
        [.files.items[]?
            | select(.download_url != null and .download_url != "" and .download_url != "null")
        ] as $items
        | ($items | map(.size | to_bytes) | add // 0) as $sum
        | ($items | map(select((.size | to_bytes) == 0)) | length) as $unknown
        | ($items | length) as $total
        | "\($sum)|\($unknown)|\($total)"
    ' "$json_file" 2>/dev/null)"

    if [[ ! "$stats_line" =~ ^[0-9]+\|[0-9]+\|[0-9]+$ ]]; then
        printf "0|0|0"
        return
    fi

    printf "%s" "$stats_line"
}

ensure_model_download_plan() {
    local json_file="$1"
    local model_id="$2"
    local probe_path="$3"
    local stats_line=""
    local known_bytes=0
    local unknown_count=0
    local file_count=0
    local required_mb="$MIN_FREE_SPACE_MB"

    stats_line="$(get_model_download_size_stats "$json_file")"
    IFS='|' read -r known_bytes unknown_count file_count <<< "$stats_line"

    if [[ ! "$known_bytes" =~ ^[0-9]+$ ]]; then
        known_bytes=0
    fi
    if [[ ! "$unknown_count" =~ ^[0-9]+$ ]]; then
        unknown_count=0
    fi
    if [[ ! "$file_count" =~ ^[0-9]+$ ]]; then
        file_count=0
    fi

    if [[ "$known_bytes" -gt 0 ]]; then
        local known_file_count=$((file_count - unknown_count))
        local estimated_total_bytes="$known_bytes"

        required_mb=$(( (known_bytes + 1024 * 1024 - 1) / 1024 / 1024 + DISK_MARGIN_MB_MODEL ))
        if (( required_mb < MIN_FREE_SPACE_MB )); then
            required_mb=$MIN_FREE_SPACE_MB
        fi
        echo -e "  ${CYAN}[DISK] Model $model_id — metadata reports $(format_bytes_human "$known_bytes") for $known_file_count file(s) with known size (of $file_count total)${NC}"
        if [[ "$unknown_count" -gt 0 ]]; then
            if [[ "$known_file_count" -gt 0 ]]; then
                local estimated_unknown_bytes=$(( (known_bytes / known_file_count) * unknown_count ))
                estimated_total_bytes=$((known_bytes + estimated_unknown_bytes))
                required_mb=$(( (estimated_total_bytes + 1024 * 1024 - 1) / 1024 / 1024 + DISK_MARGIN_MB_MODEL ))
                echo -e "  ${CYAN}[DISK] Model $model_id — $unknown_count file(s) without size; estimated +$(format_bytes_human "$estimated_unknown_bytes") from average of known sizes${NC}"
            else
                echo -e "  ${CYAN}[DISK] Model $model_id — $unknown_count file(s) without size; estimating ${UNKNOWN_FILE_ESTIMATE_MB} MB each${NC}"
                required_mb=$((required_mb + unknown_count * UNKNOWN_FILE_ESTIMATE_MB))
            fi
        fi
    else
        echo -e "  ${YELLOW}[DISK] Model $model_id — no file sizes in metadata; estimating ${UNKNOWN_FILE_ESTIMATE_MB} MB per file ($file_count file(s))${NC}"
        if [[ "$file_count" -gt 0 ]]; then
            required_mb=$((UNKNOWN_FILE_ESTIMATE_MB * file_count + DISK_MARGIN_MB_MODEL))
            if (( required_mb < MIN_FREE_SPACE_MB )); then
                required_mb=$MIN_FREE_SPACE_MB
            fi
        fi
    fi

    log_disk_context "$probe_path" "before downloading model $model_id" "$required_mb"
    ensure_min_free_space "$probe_path" "$required_mb" "before downloading model $model_id"
}

ensure_file_download_space() {
    local probe_path="$1"
    local filename="$2"
    local file_bytes="$3"

    local required_mb
    required_mb="$(required_mb_for_file_download "$file_bytes")"

    if [[ "$file_bytes" =~ ^[0-9]+$ ]] && [[ "$file_bytes" -gt 0 ]]; then
        log_disk_context "$probe_path" "before downloading $filename (~$(format_bytes_human "$file_bytes") from metadata)" "$required_mb"
    else
        log_disk_context "$probe_path" "before downloading $filename (size unknown in metadata)" "$required_mb"
    fi

    ensure_min_free_space "$probe_path" "$required_mb" "before downloading $filename"
}

disk_space_is_low() {
    local probe_path="$1"
    local available_kb

    available_kb="$(get_available_kb "$probe_path")"
    if [[ ! "$available_kb" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    (( available_kb < MIN_FREE_SPACE_MB * 1024 ))
}

print_write_failure_hints() {
    echo -e "${CYAN}Free disk space looks sufficient; this is usually not a full-disk issue.${NC}"
    echo ""
    echo -e "${CYAN}Common causes on Windows:${NC}"
    echo "  1. Antivirus or cloud sync (OneDrive, etc.) locking files during download"
    echo "  2. Special characters in filenames — MyMiniFactory often uses Greek lookalike letters in Roman numerals"
    echo "  3. Output folder permissions or a read-only drive"
    echo "  4. Path too long — try a shorter downloads folder path (e.g. D:\\MMF)"
    echo ""
    echo -e "${CYAN}Try:${NC}"
    echo "  - Exclude the downloads folder from real-time antivirus scanning"
    echo "  - Use a short local path (not a synced folder) and re-run Step 2"
}

abort_no_space() {
    local context="$1"
    local probe_path="${2:-.}"

    echo ""
    log_disk_context "$probe_path" "$context" ""
    echo -e "${RED}=======================================================${NC}"
    echo -e "${RED}STOPPING: No space left on device${NC}"
    echo -e "${RED}=======================================================${NC}"
    echo -e "${YELLOW}Context: ${context}${NC}"
    echo "Free disk space and run the script again."
    echo "Only validated complete files are kept; partial files are discarded."
    exit 1
}

abort_write_failure() {
    local context="$1"
    local probe_path="${2:-.}"

    echo ""
    log_disk_context "$probe_path" "$context" ""
    echo -e "${RED}=======================================================${NC}"
    if disk_space_is_low "$probe_path"; then
        echo -e "${RED}STOPPING: No space left on device${NC}"
        echo -e "${RED}=======================================================${NC}"
        echo -e "${YELLOW}Context: ${context}${NC}"
        echo "Free disk space and run the script again."
    else
        echo -e "${RED}STOPPING: Could not write download to disk${NC}"
        echo -e "${RED}=======================================================${NC}"
        echo -e "${YELLOW}Context: ${context}${NC}"
        print_write_failure_hints
    fi
    echo "Only validated complete files are kept; partial files are discarded."
    exit 1
}

resolve_unzip_executable() {
    if command -v unzip >/dev/null 2>&1; then
        command -v unzip
        return 0
    fi
    return 1
}

resolve_bundled_zip_executable() {
    local candidate=""
    local -a bundled_candidates=()

    bundled_candidates+=(
        "${SCRIPT_DIR}/tools/zip.exe"
        "${SCRIPT_DIR}/zip.exe"
    )

    for candidate in "${bundled_candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    return 1
}

resolve_zip_executable() {
    local candidate=""
    local bash_bin=""
    local path_zip=""
    local -a prefer_candidates=()

    if candidate="$(resolve_bundled_zip_executable 2>/dev/null)"; then
        printf '%s' "$candidate"
        return 0
    fi

    prefer_candidates+=("/usr/bin/zip")

    bash_bin="$(command -v bash 2>/dev/null || true)"
    if [[ -n "$bash_bin" ]]; then
        if [[ "$bash_bin" == */bin/bash.exe ]]; then
            prefer_candidates+=("${bash_bin%/bin/bash.exe}/usr/bin/zip")
        elif [[ "$bash_bin" == */bin/bash ]]; then
            prefer_candidates+=("${bash_bin%/bin/bash}/usr/bin/zip")
        fi
    fi

    for candidate in "${prefer_candidates[@]}"; do
        if [[ -n "$candidate" && -f "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    if path_zip="$(command -v zip 2>/dev/null)"; then
        if is_nonstandard_zip_executable "$path_zip"; then
            return 1
        fi
        printf '%s' "$path_zip"
        return 0
    fi

    return 1
}

is_nonstandard_zip_executable() {
    local zip_exe="$1"
    local lower_path=""

    lower_path="$(printf '%s' "$zip_exe" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lower_path" == *miktex* ]]; then
        return 0
    fi

    return 1
}

describe_archive_tool() {
    local label="$1"
    local exe_path="$2"
    local version_line=""

    if [[ -z "$exe_path" ]]; then
        echo -e "  ${RED}[ZIP-DIAG] ${label}: not found${NC}"
        return 1
    fi

    if [[ ! -f "$exe_path" ]]; then
        echo -e "  ${RED}[ZIP-DIAG] ${label}: file missing (${exe_path})${NC}"
        return 1
    fi

    version_line="$("$exe_path" -v 2>&1 | head -n 1 || true)"
    echo -e "  ${CYAN}[ZIP-DIAG] ${label}: ${exe_path}${NC}"
    if [[ -n "$version_line" ]]; then
        echo -e "  ${CYAN}[ZIP-DIAG]   ${version_line}${NC}"
    fi
    return 0
}

print_archive_toolchain_hint() {
    if resolve_bundled_zip_executable >/dev/null 2>&1; then
        echo -e "  ${YELLOW}[ZIP-DIAG] Bundled tools/zip.exe exists but was not used — reinstall or update the desktop app.${NC}"
        return
    fi

    echo -e "  ${YELLOW}[ZIP-DIAG] Windows \"Compress to ZIP\" in Explorer is NOT the same as the zip command.${NC}"
    echo -e "  ${YELLOW}[ZIP-DIAG] Install Info-ZIP in Git Bash: pacman -S zip — or use a desktop build that includes tools/zip.exe.${NC}"
    echo -e "  ${YELLOW}[ZIP-DIAG] Then restart the app and re-run Step 2 (downloads are skipped; only packaging retries).${NC}"
}

print_archive_failure_report() {
    local archive_path="$1"
    local failure_kind="$2"
    shift 2
    local -a files_to_zip=("$@")
    local zip_exe=""
    local unzip_exe=""
    local archive_size="unknown"

    if [[ -f "$archive_path" ]]; then
        archive_size="$(get_file_size "$archive_path") bytes"
    elif [[ -e "$archive_path" ]]; then
        archive_size="exists but not a regular file"
    else
        archive_size="missing"
    fi

    echo -e "  ${RED}[ZIP-DIAG] Archive packaging failed (${failure_kind})${NC}"
    echo -e "  ${RED}[ZIP-DIAG] Target archive: ${archive_path} (${archive_size})${NC}"

    zip_exe="$(resolve_zip_executable 2>/dev/null || true)"
    unzip_exe="$(resolve_unzip_executable 2>/dev/null || true)"
    describe_archive_tool "zip" "${zip_exe:-}"
    describe_archive_tool "unzip" "${unzip_exe:-}"

    if [[ -n "$ZIP_COMPRESS_TOOL" ]]; then
        echo -e "  ${CYAN}[ZIP-DIAG] zip used for this attempt: ${ZIP_COMPRESS_TOOL}${NC}"
    fi
    if [[ -n "$ZIP_COMPRESS_PHASE" ]]; then
        echo -e "  ${CYAN}[ZIP-DIAG] Last zip phase: ${ZIP_COMPRESS_PHASE}${NC}"
    fi
    if [[ -n "$ZIP_COMPRESS_FAILURE" ]]; then
        echo -e "  ${RED}[ZIP-DIAG] Compress error: ${ZIP_COMPRESS_FAILURE}${NC}"
    fi
    if [[ -n "$ZIP_VALIDATE_REASON" ]]; then
        echo -e "  ${RED}[ZIP-DIAG] Validation: ${ZIP_VALIDATE_REASON}${NC}"
    fi
    if [[ -n "$ZIP_COMPRESS_STDERR" ]]; then
        echo -e "  ${RED}[ZIP-DIAG] zip stderr:${NC}"
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ -n "$line" ]]; then
                echo -e "  ${RED}[ZIP-DIAG]   ${line}${NC}"
            fi
        done <<< "$ZIP_COMPRESS_STDERR"
    fi

    echo -e "  ${RED}[ZIP-DIAG] Files to package (${#files_to_zip[@]}):${NC}"
    for file_name in "${files_to_zip[@]}"; do
        echo "    ${file_name}"
    done

    if [[ -n "$zip_exe" ]] && is_nonstandard_zip_executable "$zip_exe"; then
        echo -e "  ${YELLOW}[ZIP-DIAG] The zip in PATH looks like MiKTeX, not Git/Info-ZIP — common cause of packaging failures on Windows.${NC}"
    elif [[ -z "$zip_exe" ]]; then
        echo -e "  ${YELLOW}[ZIP-DIAG] zip was not found in PATH when this report was generated.${NC}"
    fi

    print_archive_toolchain_hint
}

validate_zip_integrity() {
    local zip_file="$1"
    local unzip_exe=""
    local zip_exe=""
    local validate_output=""
    local magic=""

    ZIP_VALIDATE_REASON=""

    if [[ ! -f "$zip_file" ]]; then
        ZIP_VALIDATE_REASON="archive file is missing"
        return 1
    fi

    if [[ ! -s "$zip_file" ]]; then
        ZIP_VALIDATE_REASON="archive file is empty"
        return 1
    fi

    # Estimating work, not deciding whether to trust an archive: check the
    # signature rather than every CRC in it. Uses the read builtin so this
    # costs no process spawn.
    if [[ "${ZIP_VALIDATION_QUICK:-0}" == "1" ]]; then
        IFS= read -r -n 2 magic < "$zip_file" 2>/dev/null
        if [[ "$magic" != "PK" ]]; then
            ZIP_VALIDATE_REASON="archive does not start with the ZIP signature"
            return 1
        fi
        return 0
    fi

    if unzip_exe="$(resolve_unzip_executable 2>/dev/null)"; then
        validate_output="$(unzip -tqq "$zip_file" 2>&1)"
        if [[ "$?" -eq 0 ]]; then
            return 0
        fi

        ZIP_VALIDATE_REASON="unzip -t failed"
        if [[ -n "$validate_output" ]]; then
            ZIP_VALIDATE_REASON="${ZIP_VALIDATE_REASON}: ${validate_output}"
        fi
        return 1
    fi

    if zip_exe="$(resolve_zip_executable 2>/dev/null)"; then
        validate_output="$("$zip_exe" -T "$zip_file" 2>&1)"
        if [[ "$?" -eq 0 ]]; then
            return 0
        fi

        ZIP_VALIDATE_REASON="zip -T failed"
        if [[ -n "$validate_output" ]]; then
            ZIP_VALIDATE_REASON="${ZIP_VALIDATE_REASON}: ${validate_output}"
        fi
        return 1
    fi

    # If we cannot validate archive internals, keep prior behavior.
    return 0
}

is_valid_download_file() {
    local file_path="$1"
    local logical_name="$2"
    local normalized_name=""

    if [[ ! -f "$file_path" ]] || [[ ! -s "$file_path" ]]; then
        return 1
    fi

    if is_html_error "$file_path"; then
        return 1
    fi

    normalized_name="$(printf '%s' "$logical_name" | tr '[:upper:]' '[:lower:]')"
    if [[ "$normalized_name" == *.zip ]]; then
        validate_zip_integrity "$file_path" || return 1
    fi

    return 0
}

# Same test, ordered for the scan: check the ZIP signature first so an archive
# never pays for the HTML sniff, which costs a head and a grep.
is_valid_download_file_quick() {
    local file_path="$1"
    local logical_name="$2"
    local normalized_name=""

    if [[ ! -f "$file_path" ]] || [[ ! -s "$file_path" ]]; then
        return 1
    fi

    normalized_name="${logical_name,,}"
    if [[ "$normalized_name" == *.zip ]]; then
        # A signature match rules out an HTML error page on its own.
        validate_zip_integrity "$file_path"
        return $?
    fi

    is_html_error "$file_path" && return 1
    return 0
}

is_reusable_download_file() {
    local file_path="$1"
    local logical_name="$2"
    local expected_bytes="${3:-}"
    local actual_bytes=""

    is_valid_download_file "$file_path" "$logical_name" || return 1

    if [[ "$expected_bytes" =~ ^[0-9]+$ ]] && [[ "$expected_bytes" -gt 0 ]]; then
        actual_bytes="$(get_file_size "$file_path")"
        [[ "$actual_bytes" =~ ^[0-9]+$ ]] || return 1
        [[ "$actual_bytes" -eq "$expected_bytes" ]] || return 1
    fi

    return 0
}

download_file_with_guards() {
    local download_url="$1"
    local output_path="$2"
    local accept_header="$3"
    local context_label="$4"
    local logical_name="$5"
    local tmp_path="${output_path}.part"
    local headers_path="${output_path}.headers"
    local sanitized_download_url=""

    DOWNLOAD_LAST_CURL_EXIT=0
    DOWNLOAD_LAST_HTTP_CODE=""
    DOWNLOAD_LAST_TMP_FILE="$tmp_path"
    DOWNLOAD_LAST_FAILURE_REASON=""
    DOWNLOAD_LAST_ORIGINAL_URL="$download_url"
    DOWNLOAD_LAST_SANITIZED_URL=""
    DOWNLOAD_LAST_URL_SANITIZATION_NOTE=""
    DOWNLOAD_LAST_URL_SANITIZATION_CHANGED=0
    DOWNLOAD_LAST_CF_MITIGATED=""

    if ! sanitized_download_url="$(sanitize_url "$download_url")"; then
        DOWNLOAD_LAST_CURL_EXIT=3
        DOWNLOAD_LAST_HTTP_CODE="000"
        DOWNLOAD_LAST_TMP_FILE=""
        rm -f "$tmp_path"
        echo -e "  ${RED}[URL-ERROR] Invalid URL for ${context_label}${NC}"
        print_url_debug "Rejected before curl"
        return 3
    fi

    DOWNLOAD_LAST_SANITIZED_URL="$sanitized_download_url"
    if [[ "$DOWNLOAD_LAST_URL_SANITIZATION_CHANGED" -eq 1 ]]; then
        print_url_debug "Sanitized before curl"
    fi

    rm -f "$tmp_path" "$headers_path"

    if ! ensure_min_free_space "$output_path" "$MIN_FREE_SPACE_MB" "$context_label"; then
        DOWNLOAD_LAST_CURL_EXIT=23
        return 23
    fi

    DOWNLOAD_LAST_HTTP_CODE="$(curl --silent --show-error -L \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:142.0) Gecko/20100101 Firefox/142.0" \
        -H "Accept: $accept_header" \
        -H "Cookie: $COOKIE" \
        --compressed \
        --retry "$CURL_RETRIES" \
        --retry-delay 2 \
        -D "$headers_path" \
        -w "%{http_code}" \
        "$sanitized_download_url" \
        -o "$tmp_path")"
    DOWNLOAD_LAST_CURL_EXIT=$?

    # cf-mitigated is the only reliable signal that Cloudflare (not MyMiniFactory's
    # own app-level throttle) issued this response. -L means the header dump can
    # contain one block per redirect hop; the LAST cf-mitigated line reflects the
    # final response actually being evaluated below.
    if [[ -f "$headers_path" ]]; then
        DOWNLOAD_LAST_CF_MITIGATED="$(grep -i '^cf-mitigated:' "$headers_path" | tail -1 | cut -d':' -f2- | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        rm -f "$headers_path"
    fi

    if [[ "$DOWNLOAD_LAST_CURL_EXIT" -ne 0 ]]; then
        if [[ "$DOWNLOAD_LAST_CURL_EXIT" -eq 3 ]]; then
            print_url_debug "curl exit 3 while ${context_label}"
        fi
        if [[ "$DOWNLOAD_LAST_CURL_EXIT" -eq 23 ]]; then
            log_disk_context "$(dirname "$output_path")" "curl exit 23 (often disk full) while ${context_label}" ""
        fi
        if [[ "$DOWNLOAD_LAST_CURL_EXIT" -ne 23 ]]; then
            rm -f "$tmp_path"
            DOWNLOAD_LAST_TMP_FILE=""
        fi
        return "$DOWNLOAD_LAST_CURL_EXIT"
    fi

    if [[ ! "$DOWNLOAD_LAST_HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
        # Keep the response body for 429/503/403: those are the codes Cloudflare's
        # timed cooldown/challenge can use, and the caller needs the body to tell
        # a cooldown apart from a genuinely dead cookie instead of treating it as
        # fatal outright. A 403 without cooldown markers still falls through to
        # the normal failure handling further up the call chain.
        if [[ "$DOWNLOAD_LAST_HTTP_CODE" != "429" ]] && [[ "$DOWNLOAD_LAST_HTTP_CODE" != "503" ]] && [[ "$DOWNLOAD_LAST_HTTP_CODE" != "403" ]]; then
            rm -f "$tmp_path"
            DOWNLOAD_LAST_TMP_FILE=""
        fi
        return 22
    fi

    if ! is_valid_download_file "$tmp_path" "$logical_name"; then
        return 65
    fi

    if ! mv -f "$tmp_path" "$output_path"; then
        rm -f "$tmp_path"
        DOWNLOAD_LAST_TMP_FILE=""
        DOWNLOAD_LAST_FAILURE_REASON="rename"

        if ! ensure_min_free_space "$output_path" "$MIN_FREE_SPACE_MB" "saving ${context_label}"; then
            DOWNLOAD_LAST_CURL_EXIT=23
            return 23
        fi

        echo -e "  ${RED}[FAIL] Downloaded file but could not save as $(basename "$output_path") (rename/move failed)${NC}"
        return 1
    fi

    DOWNLOAD_LAST_TMP_FILE=""
    CLOUDFLARE_COOLDOWN_STAGE=0
    APP_THROTTLE_STAGE=0
    return 0
}

STAGING_ROOT="${MMF_STAGING_ROOT:-.mmf_staging}"
ACTIVE_STAGING_DIR=""
ACTIVE_PAYLOAD_DIR=""
ACTIVE_PAYLOAD_MODEL_DIR=""
PAYLOAD_MOVED_ORIGINALS=()

# Hands back a directory to build this model in. Any work a previous run left
# behind -- whether it was interrupted in staging or had already been moved
# into place -- is adopted so resume stays free.

prepare_model_staging_dir() {
    local model_id="$1"
    local final_dir="$2"
    local staging="${STAGING_ROOT}/${model_id}"

    mkdir -p "$STAGING_ROOT" 2>/dev/null || true

    if [[ -d "$final_dir" ]]; then
        rm -rf "$staging"
        if ! mv "$final_dir" "$staging" 2>/dev/null; then
            # Could not adopt it (locked by Explorer, cross-device, ...) --
            # build in place rather than losing the existing work.
            printf '%s' "$final_dir"
            return 0
        fi
    elif [[ ! -d "$staging" ]]; then
        if ! mkdir -p "$staging" 2>/dev/null; then
            printf '%s' "$final_dir"
            return 0
        fi
    fi

    printf '%s' "$staging"
}

# Moves a finished model into the library. Only called once the archive exists.
finalize_model_staging_dir() {
    local staging="$1"
    local final_dir="$2"

    if [[ "$staging" == "$final_dir" ]]; then
        return 0
    fi

    if [[ ! -d "$staging" ]]; then
        return 1
    fi

    rm -rf "$final_dir"
    if ! mv "$staging" "$final_dir" 2>/dev/null; then
        echo -e "  ${RED}[FAIL] Could not move finished model into place: ${final_dir}${NC}"
        return 1
    fi

    return 0
}

# A 140 GB run gets killed at least once. Leave nothing half-written behind.
cleanup_on_interrupt() {
    trap - INT TERM
    echo ""
    echo -e "${YELLOW}Interrupted — cleaning up partial downloads...${NC}"

    if [[ -n "$ACTIVE_PAYLOAD_DIR" ]] && [[ -d "$ACTIVE_PAYLOAD_DIR" ]]; then
        restore_payload_originals "$ACTIVE_PAYLOAD_MODEL_DIR" "$ACTIVE_PAYLOAD_DIR" "${PAYLOAD_MOVED_ORIGINALS[@]}"
    fi

    cleanup_orphan_part_files
    echo -e "${CYAN}Partial work is left in ${STAGING_ROOT}/ and will be resumed on the next run.${NC}"
    exit 130
}

cleanup_orphan_part_files() {
    local removed_count=0

    while IFS= read -r -d '' part_file; do
        rm -f "$part_file"
        removed_count=$((removed_count + 1))
    done < <(find . -type f \( -name "*.part" -o -name "*.headers" \) -print0 2>/dev/null)

    if [[ "$removed_count" -gt 0 ]]; then
        echo -e "${YELLOW}! Removed ${removed_count} leftover temp file(s) from previous interrupted runs.${NC}"
    fi
}

# Map Greek/Cyrillic lookalike letters to Latin (common in MMF Roman-numeral filenames).
# Requires perl (bundled with Git for Windows at usr/bin/perl; usually present on macOS/Linux too).

# Map Greek/Cyrillic lookalike letters to Latin (common in MMF Roman-numeral
# filenames). Pure parameter expansion: this used to shell out to perl, but it
# sits on a path that now runs once per archive member and a single subshell
# costs ~24 ms on Windows.
normalize_unicode_homoglyphs() {
    local out=""
    _fold_homoglyphs "$1" out
    printf '%s' "$out"
}

_fold_homoglyphs() {
    local __h="$1"

    __h="${__h//$'Ι'/I}"; __h="${__h//$'ι'/i}"
    __h="${__h//$'І'/I}"; __h="${__h//$'і'/i}"
    __h="${__h//$'А'/A}"; __h="${__h//$'а'/a}"
    __h="${__h//$'В'/V}"; __h="${__h//$'в'/v}"
    __h="${__h//$'Е'/E}"; __h="${__h//$'е'/e}"
    __h="${__h//$'О'/O}"; __h="${__h//$'о'/o}"
    __h="${__h//$'Р'/R}"; __h="${__h//$'р'/r}"
    __h="${__h//$'С'/S}"; __h="${__h//$'с'/s}"
    __h="${__h//$'Т'/T}"; __h="${__h//$'т'/t}"
    __h="${__h//$'У'/U}"; __h="${__h//$'у'/u}"
    __h="${__h//$'Х'/X}"; __h="${__h//$'х'/x}"

    printf -v "$2" '%s' "$__h"
}

# Shared front half of both sanitisers: strip control characters, fold
# homoglyphs, DELETE the Windows-reserved set and the apostrophe, collapse
# whitespace runs into single underscores.
#
# Writes to the caller's variable instead of printing so no subshell is forked.
# The internal name is deliberately obscure: bash is dynamically scoped, so a
# plain "local s" here would shadow a caller that passed "s" as the out-param
# and silently hand back an empty string.
_sanitize_core() {
    local __san="$1"

    # Tabs/newlines/CRs become spaces at the whitespace-collapse step below;
    # every other control character is removed outright.
    __san="${__san//$'\t'/ }"; __san="${__san//$'\n'/ }"; __san="${__san//$'\r'/ }"
    __san="${__san//[[:cntrl:]]/}"

    while [[ "$__san" == [[:space:]]* ]]; do __san="${__san#?}"; done
    while [[ "$__san" == *[[:space:]] ]]; do __san="${__san%?}"; done

    _fold_homoglyphs "$__san" __san

    # The backslash is handled separately and deliberately: inside a bash
    # bracket expression "\" is the escape character, not a member of the set,
    # so '[<>:"/\|?*]' silently means "... or an escaped pipe" and leaves every
    # backslash in the name untouched. sed's bracket expressions treat it as a
    # literal, which is why the old pipeline did strip it.
    local reserved='[<>:"/|?*]'
    __san="${__san//$reserved/}"
    __san="${__san//\\/}"
    __san="${__san//\'/}"

    while [[ "$__san" == *"  "* ]]; do __san="${__san//  / }"; done
    __san="${__san// /_}"
    while [[ "$__san" == *"__"* ]]; do __san="${__san//__/_}"; done

    printf -v "$2" '%s' "$__san"
}


sanitize_filename() {
    local sanitized_name="" base_name="" extension=""

    _sanitize_core "$1" sanitized_name

    if [[ "$sanitized_name" == *.* ]] && [[ "$sanitized_name" != .* ]]; then
        base_name="${sanitized_name%.*}"
        extension=".${sanitized_name##*.}"
    else
        base_name="$sanitized_name"
    fi

    while [[ "$base_name" == *[.\ ] ]]; do base_name="${base_name%?}"; done
    while [[ "$base_name" == [_.]* ]]; do base_name="${base_name#?}"; done
    while [[ "$base_name" == *[_.] ]]; do base_name="${base_name%?}"; done
    while [[ "$base_name" == *"__"* ]]; do base_name="${base_name//__/_}"; done
    while [[ "$extension" == *[.\ ] ]]; do extension="${extension%?}"; done

    if [[ -z "$base_name" ]]; then
        if [[ -n "$extension" ]]; then
            sanitized_name="unnamed_file${extension}"
        else
            sanitized_name="unnamed_file"
        fi
    else
        sanitized_name="${base_name}${extension}"
    fi

    while [[ "$sanitized_name" == *[.\ ] ]]; do sanitized_name="${sanitized_name%?}"; done

    if [[ -n "$sanitized_name" ]] && [[ -z "${sanitized_name//_/}" ]]; then
        sanitized_name="unnamed_file"
    fi

    if [[ -z "$sanitized_name" ]]; then
        sanitized_name="unnamed_file"
    fi

    printf "%s" "$sanitized_name"
}

FOLDER_NAMING_FORMAT="${MMF_NAMING_FORMAT:-ID_NAME}"
MAX_FOLDER_NAME_LENGTH="${MMF_MAX_NAME_LENGTH:-80}"

if [[ "$FOLDER_NAMING_FORMAT" != "NAME_ONLY" ]]; then
    FOLDER_NAMING_FORMAT="ID_NAME"
fi

if [[ ! "$MAX_FOLDER_NAME_LENGTH" =~ ^[0-9]+$ ]]; then
    MAX_FOLDER_NAME_LENGTH=80
fi

if [[ "$MAX_FOLDER_NAME_LENGTH" -lt 10 ]]; then
    MAX_FOLDER_NAME_LENGTH=10
elif [[ "$MAX_FOLDER_NAME_LENGTH" -gt 160 ]]; then
    MAX_FOLDER_NAME_LENGTH=160
fi


sanitize_folder_name() {
    local cleaned=""

    _sanitize_core "$1" cleaned

    while [[ "$cleaned" == *[.\ ] ]]; do cleaned="${cleaned%?}"; done
    while [[ "$cleaned" == [_.]* ]]; do cleaned="${cleaned#?}"; done
    while [[ "$cleaned" == *[_.] ]]; do cleaned="${cleaned%?}"; done

    if [[ -z "$cleaned" ]]; then
        cleaned="unnamed_model"
    fi

    if [[ ${#cleaned} -gt $MAX_FOLDER_NAME_LENGTH ]]; then
        cleaned="${cleaned:0:$MAX_FOLDER_NAME_LENGTH}"
        while [[ "$cleaned" == *_ ]]; do cleaned="${cleaned%?}"; done
    fi

    if [[ -z "$cleaned" ]]; then
        cleaned="unnamed_model"
    fi

    if [[ -n "$cleaned" ]] && [[ -z "${cleaned//_/}" ]]; then
        cleaned="unnamed_model"
    fi

    printf "%s" "$cleaned"
}

build_model_folder_name() {
    local source_json="$1"
    local model_id="$2"
    local name_hint="${3:-}"
    local model_name=""
    local clean_name=""

    if [[ -n "$name_hint" ]]; then
        model_name="$name_hint"
        while [[ "$model_name" == [[:space:]]* ]]; do model_name="${model_name#?}"; done
        while [[ "$model_name" == *[[:space:]] ]]; do model_name="${model_name%?}"; done
    else
        model_name="$(trim_field "$($JQ_CMD -r '.name // ""' "$source_json" 2>/dev/null)")"
    fi
    clean_name=$(sanitize_folder_name "$model_name")

    if [[ "$FOLDER_NAMING_FORMAT" == "NAME_ONLY" ]]; then
        printf '%s' "$clean_name"
        return
    fi

    printf '%s_%s' "$model_id" "$clean_name"
}

unique_model_dir_name() {
    local desired_name="$1"
    local model_id="$2"
    local candidate="$desired_name"

    if [[ ! -e "$candidate" ]]; then
        printf '%s' "$candidate"
        return
    fi

    local suffix=1
    while [[ -e "${desired_name}_${suffix}" ]]; do
        suffix=$((suffix + 1))
    done

    printf '%s' "${desired_name}_${suffix}"
}

# Releases before the sanitiser switched to *deleting* Windows-reserved
# characters wrote them as underscores ("Ork_Warboss" where the convention is
# "OrkWarboss"). Adopting the verified rule must not orphan a library built by
# an older version, so look for any directory already claiming this model id
# before minting a new name.
find_existing_model_dir_by_id() {
    local model_id="$1"
    local candidate=""

    shopt -s nullglob
    for candidate in "${model_id}_"*; do
        if [[ -d "$candidate" ]]; then
            shopt -u nullglob
            printf '%s' "$candidate"
            return 0
        fi
    done
    shopt -u nullglob

    return 1
}

resolve_model_dir() {
    local model_id="$1"
    local json_file="$2"
    local name_hint="${3:-}"
    local preferred=""
    local legacy="model_${model_id}"
    local existing=""

    preferred=$(build_model_folder_name "$json_file" "$model_id" "$name_hint")

    if [[ -d "$preferred" ]]; then
        printf '%s' "$preferred"
        return
    fi

    if [[ -d "$legacy" ]]; then
        printf '%s' "$legacy"
        return
    fi

    if [[ "$FOLDER_NAMING_FORMAT" != "NAME_ONLY" ]] && existing=$(find_existing_model_dir_by_id "$model_id"); then
        printf '%s' "$existing"
        return
    fi

    preferred=$(unique_model_dir_name "$preferred" "$model_id")
    printf '%s' "$preferred"
}

unique_output_path() {
    local base_dir="$1"
    local target_name="$2"
    local candidate_path="${base_dir}/${target_name}"

    if [[ ! -e "$candidate_path" ]]; then
        printf "%s" "$candidate_path"
        return
    fi

    local suffix=1
    local name_without_ext="$target_name"
    local extension=""

    if [[ "$target_name" == *.* ]]; then
        name_without_ext="${target_name%.*}"
        extension=".${target_name##*.}"
    fi

    while true; do
        candidate_path="${base_dir}/${name_without_ext}_${suffix}${extension}"
        if [[ ! -e "$candidate_path" ]]; then
            printf "%s" "$candidate_path"
            return
        fi
        suffix=$((suffix + 1))
    done
}

filename_with_suffix() {
    local target_name="$1"
    local suffix="$2"
    local name_without_ext="$target_name"
    local extension=""

    if [[ "$target_name" == *.* ]] && [[ "$target_name" != .* ]]; then
        name_without_ext="${target_name%.*}"
        extension=".${target_name##*.}"
    fi

    printf "%s_%s%s" "$name_without_ext" "$suffix" "$extension"
}

reserved_output_name_exists() {
    local reserved_names="$1"
    local target_name="$2"
    local reserved_name=""

    while IFS= read -r reserved_name; do
        if [[ -n "$reserved_name" && "$reserved_name" == "$target_name" ]]; then
            return 0
        fi
    done <<< "$reserved_names"

    return 1
}

reserve_model_output_name() {
    local target_name="$1"
    local reserved_names="$2"
    local candidate_name="$target_name"
    local suffix=1

    while reserved_output_name_exists "$reserved_names" "$candidate_name"; do
        candidate_name="$(filename_with_suffix "$target_name" "$suffix")"
        suffix=$((suffix + 1))
    done

    printf "%s" "$candidate_name"
}

model_has_sanitized_filename_collisions() {
    local download_data="$1"
    local raw_filename=""
    local sanitized_name=""
    local sanitized_names=""
    local duplicate_name=""

    while IFS='|' read -r raw_filename _ _; do
        if [[ -z "$raw_filename" ]]; then
            continue
        fi

        sanitized_name="$(sanitize_filename "$(trim_field "$raw_filename")")"
        if [[ -z "$sanitized_name" ]]; then
            continue
        fi

        sanitized_names="${sanitized_names}${sanitized_name}"$'\n'
    done <<< "$download_data"

    if [[ -z "$sanitized_names" ]]; then
        return 1
    fi

    duplicate_name="$(printf '%s' "$sanitized_names" | sort | uniq -d | head -1)"
    if [[ -n "$duplicate_name" ]]; then
        return 0
    fi

    return 1
}

get_model_archive_basename() {
    local source_json="$1"
    local model_id="$2"
    local name_hint="${3:-}"
    local model_name=""
    local archive_base=""

    if [[ -n "$name_hint" ]]; then
        model_name="$name_hint"
        while [[ "$model_name" == [[:space:]]* ]]; do model_name="${model_name#?}"; done
        while [[ "$model_name" == *[[:space:]] ]]; do model_name="${model_name%?}"; done
    else
        model_name="$(trim_field "$($JQ_CMD -r '.name // ""' "$source_json" 2>/dev/null)")"
    fi
    archive_base=$(sanitize_filename "$model_name")

    if [[ -z "$archive_base" || "$archive_base" == "null" ]]; then
        archive_base="model_${model_id}_assets"
    fi

    printf "%s" "$archive_base"
}

is_valid_archive_file() {
    local file_path="$1"
    local base_name="${file_path##*/}"

    if [[ "${ZIP_VALIDATION_QUICK:-0}" == "1" ]]; then
        is_valid_download_file_quick "$file_path" "$base_name"
        return $?
    fi

    is_valid_download_file "$file_path" "$base_name"
}


# Cheap structural test for "this archive is one we built". Our archives are
# flat and their member names are already sanitised, so a single directory
# separator, an embedded space or an AppleDouble prefix means it is still the
# creator's own file. Reads only the central directory, never the payload.
#
# Both directions of a wrong answer are survivable: a creator archive that is
# already flat and clean repacks to an identical result, and treating one as
# finished leaves an archive that was acceptable anyway.
archive_looks_repacked() {
    local archive_path="$1"
    local names=""
    local entry=""

    names="$(unzip -Z1 "$archive_path" 2>/dev/null)" || return 1
    [[ -z "$names" ]] && return 1

    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        case "$entry" in
            */*|*" "*|._*) return 1 ;;
        esac
    done <<< "$names"

    return 0
}

# True when the named archive is really one of the model's declared source
# files rather than something this script packaged. Only consulted when an
# archive appears to already exist, so the jq cost is paid once per model at
# most, and never on the common path.
archive_is_declared_source() {
    local source_json="$1"
    local archive_name="$2"
    local declared=""

    [[ -z "$archive_name" ]] && return 1

    while IFS= read -r declared; do
        [[ -z "$declared" ]] && continue
        if [[ "$(sanitize_filename "$declared")" == "$archive_name" ]]; then
            return 0
        fi
    done < <($JQ_CMD -r '.files.items[]? | .filename // empty' "$source_json" 2>/dev/null)

    return 1
}

find_existing_assets_archive() {
    local model_dir="$1"
    local archive_base="$2"
    local candidate=""

    if [[ ! -d "$model_dir" ]]; then
        return 1
    fi

    candidate="${model_dir}/${archive_base}.zip"
    if is_valid_archive_file "$candidate"; then
        printf "%s" "$candidate"
        return 0
    fi

    shopt -s nullglob
    for candidate in "${model_dir}/${archive_base}"*.zip; do
        if is_valid_archive_file "$candidate"; then
            shopt -u nullglob
            printf "%s" "$candidate"
            return 0
        fi
    done
    shopt -u nullglob

    return 1
}

collect_model_root_asset_files() {
    local model_dir="$1"
    local exclude_name="$2"
    local -n _out_array=$3

    _out_array=()
    while IFS= read -r -d '' file_path; do
        _out_array+=("$(basename "$file_path")")
    done < <(find "$model_dir" -maxdepth 1 -type f ! -name "*.json" ! -name "$exclude_name" -print0 2>/dev/null)
}

sum_compress_input_bytes() {
    local model_dir="$1"
    shift
    local file_name file_path file_size total_bytes=0

    for file_name in "$@"; do
        file_path="${model_dir}/${file_name}"
        if [[ ! -f "$file_path" ]]; then
            continue
        fi

        file_size=$(get_file_size "$file_path")
        if [[ "$file_size" =~ ^[0-9]+$ ]]; then
            total_bytes=$((total_bytes + file_size))
        fi
    done

    printf "%s" "$total_bytes"
}

ensure_compress_free_space() {
    local model_dir="$1"
    local context="$2"
    local total_bytes="$3"
    local required_mb="$MIN_FREE_SPACE_MB"
    local payload_mb=0

    if [[ "$total_bytes" =~ ^[0-9]+$ ]] && [[ "$total_bytes" -gt 0 ]]; then
        payload_mb=$(( (total_bytes + 1024 * 1024 - 1) / 1024 / 1024 ))
        required_mb=$((payload_mb + DISK_MARGIN_MB_MODEL))
        if (( required_mb < MIN_FREE_SPACE_MB )); then
            required_mb=$MIN_FREE_SPACE_MB
        fi
        echo -e "  ${CYAN}[DISK] ${context} — on-disk payload $(format_bytes_human "$total_bytes")${NC}"
        if (( total_bytes > ZIP32_LIMIT_BYTES )); then
            echo -e "  ${YELLOW}[ZIP-WARN] Payload exceeds 4 GiB classic ZIP limit; Zip64 will be used if your zip supports -fz${NC}"
        elif (( total_bytes > ZIP64_RETRY_BYTES )); then
            echo -e "  ${YELLOW}[ZIP-WARN] Large payload (~$(format_bytes_human "$total_bytes")); compression may require Zip64 or extra disk space${NC}"
        fi
    fi

    log_disk_context "$model_dir" "$context" "$required_mb"
    ensure_min_free_space "$model_dir" "$required_mb" "$context"
}

# Expands one .zip into dest_dir, sanitising every member name on the way out
# and recursing into members that are themselves .zip archives. Observed
# nesting runs two deep, so a single pass is not enough; the depth cap is a
# guard against a maliciously or accidentally self-nesting archive.
MAX_NESTED_ZIP_DEPTH="${MMF_MAX_NESTED_ZIP_DEPTH:-4}"
EXPANDED_FROM_ZIP_COUNT=0
# Entries destined for the flat archive, split by how they should be stored.
# Plain files keep their bytes verbatim (STORED) so entry sizes still match the
# API's declared sizes; anything unpacked out of a .zip goes back in DEFLATED.
PAYLOAD_STORE_NAMES=()
PAYLOAD_DEFLATE_NAMES=()
ZIP_COMPRESS_LEVEL="-0"
ZIP_COMPRESS_APPEND=0

expand_zip_into_payload() {
    local zip_path="$1"
    local dest_dir="$2"
    local depth="${3:-1}"
    local work_dir=""
    local member_path=""
    local member_name=""
    local sanitized=""
    local lower_name=""
    local target=""
    local macos_icon=""

    # macOS custom folder icon: a zero-byte file named "Icon" followed by a
    # carriage return. Built with printf so no bare CR sits in this source
    # file, where a line-ending conversion could quietly eat it.
    printf -v macos_icon 'Icon\r'

    if [[ "$depth" -gt "$MAX_NESTED_ZIP_DEPTH" ]]; then
        echo -e "  ${YELLOW}[ZIP-WARN] Nested archive depth limit (${MAX_NESTED_ZIP_DEPTH}) reached; storing $(basename "$zip_path") as-is${NC}"
        sanitized=$(sanitize_filename "$(basename "$zip_path")")
        target="$(reserve_payload_name "$sanitized" "$dest_dir")"
        cp -f "$zip_path" "${dest_dir}/${target}" || return 1
        PAYLOAD_STORE_NAMES+=("$target")
        return 0
    fi

    if ! command -v unzip >/dev/null 2>&1; then
        echo -e "  ${YELLOW}[ZIP-WARN] unzip not available; cannot expand nested archive $(basename "$zip_path")${NC}"
        return 1
    fi

    work_dir="${dest_dir}/.expand.$$.${depth}"
    rm -rf "$work_dir"
    mkdir -p "$work_dir" || return 1

    if ! unzip -qq -o "$zip_path" -d "$work_dir" >/dev/null 2>&1; then
        echo -e "  ${YELLOW}[ZIP-WARN] Could not expand $(basename "$zip_path"); keeping it as a stored member${NC}"
        rm -rf "$work_dir"
        sanitized=$(sanitize_filename "$(basename "$zip_path")")
        target="$(reserve_payload_name "$sanitized" "$dest_dir")"
        cp -f "$zip_path" "${dest_dir}/${target}" || return 1
        PAYLOAD_STORE_NAMES+=("$target")
        return 0
    fi

    # The target layout is flat, so nested directory structure is discarded and
    # only the leaf names survive (sanitised, and de-duplicated on collision).
    while IFS= read -r -d '' member_path; do
        member_name="${member_path##*/}"
        lower_name="${member_name,,}"

        # Creators who zip on macOS ship a parallel __MACOSX tree of AppleDouble
        # resource forks alongside the real files. Flattening strips the leading
        # "._", which then collides with the real name, so a 178-byte metadata
        # blob gets stored next to the model as <name>_1.stl and looks like a
        # legitimate file. Nested structure used to hide this; a flat archive
        # cannot, so drop the junk instead.
        if [[ "$member_path" == *"/__MACOSX/"* ]] || [[ "$member_name" == ._* ]]; then
            continue
        fi
        # macOS custom folder icons are a zero-byte file literally named
        # "Icon" followed by a carriage return; the real data lives in the
        # resource fork. Sanitising strips the CR, so several of them from
        # different folders collapse to Icon, Icon_1, Icon_2 ...
        if [[ "$member_name" == "$macos_icon" ]] || [[ "$member_name" == "Icon" && ! -s "$member_path" ]]; then
            continue
        fi
        case "$lower_name" in
            .ds_store|thumbs.db|desktop.ini) continue ;;
        esac

        if [[ "$lower_name" == *.zip ]]; then
            expand_zip_into_payload "$member_path" "$dest_dir" "$((depth + 1))" || {
                rm -rf "$work_dir"
                return 1
            }
            continue
        fi

        sanitized=$(sanitize_filename "$member_name")
        target="$(reserve_payload_name "$sanitized" "$dest_dir")"
        mv -f "$member_path" "${dest_dir}/${target}" || {
            rm -rf "$work_dir"
            return 1
        }
        PAYLOAD_DEFLATE_NAMES+=("$target")
        EXPANDED_FROM_ZIP_COUNT=$((EXPANDED_FROM_ZIP_COUNT + 1))
    done < <(find "$work_dir" -type f -print0 2>/dev/null)

    rm -rf "$work_dir"
    return 0
}

# Flat archives cannot express two members with the same leaf name, which
# nested archives routinely produce. Keep both by suffixing the later one.
# Total on-disk size of a staged payload, used for the Zip64 decision.
sum_payload_bytes() {
    local payload_dir="$1"
    local total_bytes=0
    local file_size=""
    local file_path=""

    while IFS= read -r -d '' file_path; do
        file_size=$(get_file_size "$file_path")
        if [[ "$file_size" =~ ^[0-9]+$ ]]; then
            total_bytes=$((total_bytes + file_size))
        fi
    done < <(find "$payload_dir" -maxdepth 1 -type f -print0 2>/dev/null)

    printf '%s' "$total_bytes"
}

# Packaging failed, so put the staged originals back where the resume logic
# expects to find them. Files expanded out of a .zip need no restoring: the
# source .zip was only read, never moved.
restore_payload_originals() {
    local model_dir="$1"
    local payload_dir="$2"
    shift 2
    local entry=""
    local staged_name=""
    local original_name=""

    for entry in "$@"; do
        staged_name="${entry%%|*}"
        original_name="${entry#*|}"
        if [[ -f "${payload_dir}/${staged_name}" ]]; then
            mv -f "${payload_dir}/${staged_name}" "${model_dir}/${original_name}" 2>/dev/null || true
        fi
    done

    rm -rf "$payload_dir"
    ACTIVE_PAYLOAD_DIR=""
    PAYLOAD_MOVED_ORIGINALS=()
}

reserve_payload_name() {
    local desired="$1"
    local dest_dir="$2"
    local base="$desired"
    local ext=""
    local suffix=1

    if [[ ! -e "${dest_dir}/${desired}" ]]; then
        printf '%s' "$desired"
        return
    fi

    if [[ "$desired" == *.* ]] && [[ "$desired" != .* ]]; then
        base="${desired%.*}"
        ext=".${desired##*.}"
    fi

    while [[ -e "${dest_dir}/${base}_${suffix}${ext}" ]]; do
        suffix=$((suffix + 1))
    done

    printf '%s' "${base}_${suffix}${ext}"
}

is_rar_or_7z_name() {
    local lower_name="$1"

    case "$lower_name" in
        *.rar|*.7z)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}


model_assets_already_archived() {
    local model_dir="$1"
    local source_json="$2"
    local model_id="$3"
    local name_hint="${4:-}"
    local archive_base=""

    archive_base=$(get_model_archive_basename "$source_json" "$model_id" "$name_hint")

    # Deliberately not "does the directory have files in it" -- a folder of
    # loose .stl files with no archive is a half-built model, not a finished
    # one, and treating it as done is how a model silently goes missing.
    local found=""
    found="$(find_existing_assets_archive "$model_dir" "$archive_base")" || return 1

    # ...and not a downloaded source file that merely shares the archive's
    # name. Once repacked the finished archive keeps that name legitimately,
    # so the structure decides, not the name.
    if archive_is_declared_source "$source_json" "${found##*/}" && ! archive_looks_repacked "$found"; then
        return 1
    fi

    return 0
}

append_zip_compress_stderr() {
    local zip_stderr="$1"

    if [[ ! -s "$zip_stderr" ]]; then
        return
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -n "$line" ]]; then
            if [[ -n "$ZIP_COMPRESS_STDERR" ]]; then
                ZIP_COMPRESS_STDERR+=$'\n'
            fi
            ZIP_COMPRESS_STDERR+="$line"
        fi
    done < "$zip_stderr"
}

run_zip_compress() {
    local model_dir="$1"
    local archive_name="$2"
    local expected_bytes="${3:-0}"
    shift 3
    local -a files_to_zip=("$@")
    local zip_stderr=""
    local zip_exe=""
    local compression_exit=1
    local batch_size=20
    local index=0
    local batch_end=0
    local -a batch_files=()
    local grow_mode=0
    local level_flag="${ZIP_COMPRESS_LEVEL:--0}"
    local append_mode="${ZIP_COMPRESS_APPEND:-0}"
    local zip_store_flags=(-q "$level_flag")
    local zip_grow_flags=(-q "$level_flag" -g)
    local tried_zip64=0

    ZIP_COMPRESS_TOOL=""
    ZIP_COMPRESS_PHASE=""
    ZIP_COMPRESS_FAILURE=""
    ZIP_COMPRESS_STDERR=""

    if [[ ${#files_to_zip[@]} -eq 0 ]]; then
        ZIP_COMPRESS_FAILURE="no files to package"
        return 1
    fi

    if [[ "$expected_bytes" =~ ^[0-9]+$ ]] && (( expected_bytes > ZIP64_RETRY_BYTES )); then
        zip_store_flags=(-q -fz "$level_flag")
        zip_grow_flags=(-q -fz "$level_flag" -g)
        echo -e "  ${CYAN}[ZIP] Using Zip64 mode (-fz) for $(format_bytes_human "$expected_bytes") payload${NC}"
    fi

    if ! zip_exe="$(resolve_zip_executable 2>/dev/null)"; then
        ZIP_COMPRESS_FAILURE="zip executable not found (expected bundled tools/zip.exe or system zip in PATH)"
        return 127
    fi

    ZIP_COMPRESS_TOOL="$zip_exe"
    if is_nonstandard_zip_executable "$zip_exe"; then
        echo -e "  ${YELLOW}[ZIP-WARN] Using non-standard zip: ${zip_exe} (MiKTeX is a common cause — prefer Git /usr/bin/zip)${NC}"
    fi

    zip_stderr="$(mktemp "${TMPDIR:-/tmp}/mmf-zip-err.XXXXXX" 2>/dev/null || mktemp /tmp/mmf-zip-err.XXXXXX)"

    if [[ "$append_mode" -eq 1 ]]; then
        ZIP_COMPRESS_PHASE="batch append (${#files_to_zip[@]} file(s), ${level_flag})"
        grow_mode=1
    else
        rm -f "${model_dir}/${archive_name}"
        ZIP_COMPRESS_PHASE="batch create (${#files_to_zip[@]} file(s), ${level_flag})"
        grow_mode=0
    fi
    : > "$zip_stderr"
    index=0
    while [[ "$index" -lt "${#files_to_zip[@]}" ]]; do
        batch_end=$((index + batch_size))
        batch_files=("${files_to_zip[@]:index:batch_size}")
        if [[ "$grow_mode" -eq 0 ]]; then
            (cd "$model_dir" && "$zip_exe" "${zip_store_flags[@]}" "$archive_name" "${batch_files[@]}") 2>>"$zip_stderr"
            compression_exit=$?
            grow_mode=1
        else
            (cd "$model_dir" && "$zip_exe" "${zip_grow_flags[@]}" "$archive_name" "${batch_files[@]}") 2>>"$zip_stderr"
            compression_exit=$?
        fi

        if [[ "$compression_exit" -ne 0 ]]; then
            ZIP_COMPRESS_FAILURE="zip exited ${compression_exit} during ${ZIP_COMPRESS_PHASE}"
            append_zip_compress_stderr "$zip_stderr"
            rm -f "$zip_stderr"
            return "$compression_exit"
        fi

        index=$batch_end
    done

    if [[ "$compression_exit" -ne 0 ]] && [[ "$tried_zip64" -eq 0 ]] && [[ "${zip_store_flags[1]}" != "-fz" ]] \
        && [[ "$expected_bytes" =~ ^[0-9]+$ ]] && (( expected_bytes > ZIP64_RETRY_BYTES )); then
        tried_zip64=1
        echo -e "  ${YELLOW}[ZIP] Retrying archive creation with Zip64 (-fz)...${NC}"
        if [[ "$append_mode" -eq 1 ]]; then
            grow_mode=1
        else
            rm -f "${model_dir}/${archive_name}"
            grow_mode=0
        fi
        : > "$zip_stderr"
        ZIP_COMPRESS_PHASE="Zip64 batch retry"
        index=0
        zip_store_flags=(-q -fz "$level_flag")
        zip_grow_flags=(-q -fz "$level_flag" -g)
        while [[ "$index" -lt "${#files_to_zip[@]}" ]]; do
            batch_end=$((index + batch_size))
            batch_files=("${files_to_zip[@]:index:batch_size}")
            if [[ "$grow_mode" -eq 0 ]]; then
                (cd "$model_dir" && "$zip_exe" "${zip_store_flags[@]}" "$archive_name" "${batch_files[@]}") 2>>"$zip_stderr"
                compression_exit=$?
                grow_mode=1
            else
                (cd "$model_dir" && "$zip_exe" "${zip_grow_flags[@]}" "$archive_name" "${batch_files[@]}") 2>>"$zip_stderr"
                compression_exit=$?
            fi

            if [[ "$compression_exit" -ne 0 ]]; then
                ZIP_COMPRESS_FAILURE="zip exited ${compression_exit} during ${ZIP_COMPRESS_PHASE}"
                append_zip_compress_stderr "$zip_stderr"
                rm -f "$zip_stderr"
                return "$compression_exit"
            fi

            index=$batch_end
        done
    fi

    if [[ "$compression_exit" -ne 0 ]]; then
        ZIP_COMPRESS_FAILURE="zip exited ${compression_exit} during ${ZIP_COMPRESS_PHASE}"
        if [[ "$expected_bytes" =~ ^[0-9]+$ ]] && (( expected_bytes > ZIP32_LIMIT_BYTES )); then
            ZIP_COMPRESS_FAILURE="${ZIP_COMPRESS_FAILURE}; payload exceeds 4 GiB — need zip with Zip64 (-fz)"
        fi
    fi

    append_zip_compress_stderr "$zip_stderr"
    rm -f "$zip_stderr"
    return "$compression_exit"
}


count_model_progress_units() {
    local source_json="$1"
    local model_id="$2"
    local downloadable_count="${3:-}"
    local image_count="${4:-}"
    local name_hint="${5:-}"
    local model_dir

    # Counts and name are normally supplied by the single bulk jq pass in the
    # scan; the per-file fallbacks below keep this callable on its own.
    if [[ ! "$downloadable_count" =~ ^[0-9]+$ ]]; then
        downloadable_count=$($JQ_CMD -r '[.files.items[]? | .download_url | select(. != null and . != "")] | length' "$source_json" 2>/dev/null)
    fi
    if [[ ! "$downloadable_count" =~ ^[0-9]+$ ]]; then
        downloadable_count=0
    fi

    if [[ "$downloadable_count" -eq 0 ]]; then
        echo 1
        return
    fi

    if [[ ! "$image_count" =~ ^[0-9]+$ ]]; then
        image_count=$($JQ_CMD -r '[.images[]? | .original.url | select(. != null and . != "")] | length' "$source_json" 2>/dev/null)
    fi
    if [[ ! "$image_count" =~ ^[0-9]+$ ]]; then
        image_count=0
    fi

    model_dir=$(resolve_model_dir "$model_id" "$source_json" "$name_hint")
    if model_assets_already_archived "$model_dir" "$source_json" "$model_id" "$name_hint"; then
        echo $((image_count + 3))
        return
    fi

    echo $((downloadable_count + image_count + 3))
}

write_compact_model_json() {
    local source_json="$1"
    local model_dir="$2"
    local model_id="$3"
    local output_json="${model_dir}/model_${model_id}.json"
    local output_tmp="${output_json}.part"
    local selected_categories_json="${MMF_CATEGORY_SELECTION_JSON:-[]}"
    local selected_category_tag_names_json="${MMF_CATEGORY_SELECTION_TAG_NAMES_JSON:-[]}"
    local cached_description=""
    local live_description=""

    rm -f "$output_tmp"

    # A description is only ever replaced by a non-empty one. An unauthenticated
    # or partially-valid session silently nulls this field, and losing a
    # description that way is invisible until much later.
    live_description="$($JQ_CMD -r '.description // ""' "$source_json" 2>/dev/null)"
    if [[ -z "$live_description" ]] && [[ -f "$output_json" ]]; then
        cached_description="$($JQ_CMD -r '.description // ""' "$output_json" 2>/dev/null)"
        if [[ -n "$cached_description" ]]; then
            echo -e "  ${YELLOW}[META] Live metadata has no description; keeping the one already on disk.${NC}"
        fi
    fi

    if ! ensure_min_free_space "$output_json" "$MIN_FREE_SPACE_MB" "writing compact JSON for model $model_id"; then
        abort_no_space "writing compact JSON for model $model_id"
    fi

    if ! printf '%s' "$selected_categories_json" | $JQ_CMD -e '. | type == "array"' >/dev/null 2>&1; then
        selected_categories_json='[]'
    fi

    if ! printf '%s' "$selected_category_tag_names_json" | $JQ_CMD -e '. | type == "array"' >/dev/null 2>&1; then
        selected_category_tag_names_json='[]'
    fi

    if $JQ_CMD --argjson selected_categories "$selected_categories_json" --argjson selected_category_tag_names "$selected_category_tag_names_json" --arg cached_description "$cached_description" '{
        name: (.name // ""),
        description: (if ((.description // "") | length) > 0 then .description else $cached_description end),
        tags: (
            (
                if .tags == null then []
                elif (.tags | type) == "array" then .tags
                elif (.tags | type) == "string" then
                    if (.tags | length) == 0 then [] else [ .tags ] end
                else
                    [ .tags ]
                end
            )
            | map(
                if type == "string" then .
                elif . == null then ""
                else tostring
                end
            )
            | map(gsub("^\\s+|\\s+$"; ""))
            | map(select(length > 0))
            | if length > 0 then
                .
              else
                (
                    if ($selected_category_tag_names | type) == "array" then
                        $selected_category_tag_names
                        | map(
                            if type == "string" then .
                            elif . == null then ""
                            else tostring
                            end
                        )
                        | map(gsub("^\\s+|\\s+$"; ""))
                        | map(select(length > 0))
                        | unique
                    else
                        []
                    end
                )
              end
        ),
        price: (
            if .price == null or .price == "" then 5
            elif (.price | type) == "number" then .price
            elif (.price | type) == "string" then ((.price | tonumber?) // 5)
            elif (.price | type) == "object" then (
                if .price.value == null or .price.value == "" then 5
                elif (.price.value | type) == "number" then .price.value
                elif (.price.value | type) == "string" then ((.price.value | tonumber?) // 5)
                else 5
                end
            )
            else 5
            end
        ),
        categories: (
            if ($selected_categories | type) == "array" then
                $selected_categories
                | map(
                    if type == "object" then
                        {
                            id: (.id // "" | tostring),
                            subcategories: (
                                if (.subcategoryIds | type) == "array" then .subcategoryIds
                                elif (.subcategories | type) == "array" then .subcategories
                                else []
                                end
                                | map(tostring)
                                | map(select(length > 0))
                                | unique
                            )
                        }
                    else
                        empty
                    end
                )
                | map(select(.id | length > 0))
                | map(select(.subcategories | length > 0))
            else
                []
            end
        )
    }' "$source_json" > "$output_tmp"; then
        if ! mv -f "$output_tmp" "$output_json"; then
            rm -f "$output_tmp"
            abort_no_space "saving compact JSON for model $model_id"
        fi
        echo -e "  ${GREEN}[OK] Wrote compact JSON: model_${model_id}.json${NC}"
        return 0
    fi

    echo -e "  ${RED}[FAIL] Failed to build compact JSON for model $model_id${NC}"
    rm -f "$output_tmp"

    if ! $JQ_CMD -n --arg description "$cached_description" '{name:"",description:$description,tags:[],price:5,categories:[]}' > "$output_tmp"; then
        abort_no_space "writing fallback compact JSON for model $model_id"
    fi

    if ! mv -f "$output_tmp" "$output_json"; then
        rm -f "$output_tmp"
        abort_no_space "saving fallback compact JSON for model $model_id"
    fi

    return 1
}

download_model_images() {
    local source_json="$1"
    local model_dir="$2"
    local model_id="$3"

    local image_data
    image_data=$($JQ_CMD -r '.images[]? | "\((.is_primary // false) | tostring)|\(.original.url // "")"' "$source_json" 2>/dev/null)

    if [[ -z "$image_data" ]]; then
        echo -e "  ${YELLOW}! No images with original URL found${NC}"
        return 0
    fi

    local images_dir="${model_dir}/images"
    mkdir -p "$images_dir"

    local image_index=0

    while IFS='|' read -r is_primary image_url; do
        if [[ -z "$image_url" ]]; then
            continue
        fi

        image_index=$((image_index + 1))
        total_downloads=$((total_downloads + 1))

        image_url="$(trim_field "$image_url")"
        local url_without_query="${image_url%%\?*}"
        local original_name
        original_name=$(basename "$url_without_query")

        if [[ -z "$original_name" ]]; then
            original_name="image_${image_index}.bin"
        fi

        local target_name
        if [[ "$is_primary" == "true" ]]; then
            local extension=""
            if [[ "$original_name" == *.* ]]; then
                extension=".${original_name##*.}"
            fi
            target_name="thumbnail_image${extension}"
        else
            target_name="$original_name"
        fi

        target_name=$(sanitize_filename "$target_name")
        local canonical_image_path="${images_dir}/${target_name}"

        if [[ -f "$canonical_image_path" ]] && is_valid_download_file "$canonical_image_path" "$target_name"; then
            local existing_image_size
            existing_image_size=$(get_file_size "$canonical_image_path")
            echo -e "  ${GREEN}[SKIP] Image already downloaded: $(basename "$canonical_image_path") (${existing_image_size} bytes)${NC}"
            successful_downloads=$((successful_downloads + 1))
            emit_asset_progress_unit "$model_id" "image" "skipped"
            continue
        fi

        if [[ -e "$canonical_image_path" ]]; then
            echo -e "  ${YELLOW}! Removing invalid existing image file: $(basename "$canonical_image_path")${NC}"
            rm -f "$canonical_image_path"
        fi

        local output_path
        output_path=$(unique_output_path "$images_dir" "$target_name")

        echo -e "  ${YELLOW}Downloading image: $(basename "$output_path")${NC}"

        local app_throttle_attempts=0
        while true; do
            if download_file_with_guards "$image_url" "$output_path" "image/*,*/*;q=0.8" "downloading image $(basename "$output_path")" "$(basename "$output_path")"; then
                local image_size
                image_size=$(get_file_size "$output_path")
                echo -e "  ${GREEN}[OK] Downloaded image $(basename "$output_path") (${image_size} bytes)${NC}"
                successful_downloads=$((successful_downloads + 1))
                emit_asset_progress_unit "$model_id" "image" "downloaded"
                break
            fi

            if [[ "$DOWNLOAD_LAST_CURL_EXIT" -eq 23 ]]; then
                rm -f "$output_path" "${output_path}.part"
                emit_asset_progress_unit "$model_id" "image" "failed"
                abort_write_failure "downloading image $(basename "$output_path")" "$(dirname "$output_path")"
            fi

            if [[ "$DOWNLOAD_LAST_FAILURE_REASON" == "rename" ]]; then
                consecutive_failures=$((consecutive_failures + 1))
                rm -f "$output_path" "${output_path}.part"
                emit_asset_progress_unit "$model_id" "image" "failed"
                continue 2
            fi

            if is_cloudflare_challenge_failure; then
                rm -f "$DOWNLOAD_LAST_TMP_FILE"
                wait_out_cloudflare_cooldown "downloading image $(basename "$output_path")"
                continue
            fi

            if is_app_throttle_failure && [[ $app_throttle_attempts -lt $MAX_APP_THROTTLE_ATTEMPTS_PER_ITEM ]]; then
                app_throttle_attempts=$((app_throttle_attempts + 1))
                rm -f "$DOWNLOAD_LAST_TMP_FILE"
                wait_out_app_throttle "downloading image $(basename "$output_path")"
                continue
            fi

            if [[ -n "$DOWNLOAD_LAST_TMP_FILE" ]] && [[ -f "$DOWNLOAD_LAST_TMP_FILE" ]]; then
                if is_html_error "$DOWNLOAD_LAST_TMP_FILE"; then
                    echo -e "  ${RED}[FAIL] Failed image download: received HTML error page${NC}"
                else
                    echo -e "  ${RED}[FAIL] Failed image validation for $(basename "$output_path")${NC}"
                fi
                rm -f "$DOWNLOAD_LAST_TMP_FILE"
            else
                echo -e "  ${RED}[FAIL] Failed to download image $(basename "$output_path") (curl exit ${DOWNLOAD_LAST_CURL_EXIT}, HTTP ${DOWNLOAD_LAST_HTTP_CODE:-unknown})${NC}"
            fi

            rm -f "$output_path"
            emit_asset_progress_unit "$model_id" "image" "failed"
            break
        done

        sleep "$IMAGE_DELAY_SEC"
    done <<< "$image_data"
}


# ---------------------------------------------------------------------------
# Whole-model route
#
# /download/<id> hands back the entire model in ONE request. Walking
# files.items[] instead costs 3-4x the requests against the only endpoint that
# throttles, and request count -- not delay -- is what actually trips the
# limiter: one library tripped a Cloudflare challenge at model 52 on per-file
# fetches and then ran 102 models straight through on this route.
#
# Returns 0 when a complete archive is sitting at the model root ready for
# packaging, 1 when the caller should fall back to per-file downloads.
# ---------------------------------------------------------------------------
whole_model_archive_path() {
    printf '%s/__whole_model_%s.zip' "$1" "$2"
}

# Confirms the fetched archive actually contains every file the API declares.
# 66 pre-existing archives were missing a file or two versus the current API,
# so "it downloaded" is not the same as "it is complete".
whole_model_archive_is_complete() {
    local archive_path="$1"
    local source_json="$2"
    local members=""
    local expected=""
    local sanitized=""
    local missing=0

    if ! command -v unzip >/dev/null 2>&1; then
        # Without unzip the entry set cannot be read; the archive still
        # validated, so trust it rather than forcing 3-4x the requests.
        return 0
    fi

    members="$(unzip -Z1 "$archive_path" 2>/dev/null)"
    if [[ -z "$members" ]]; then
        return 1
    fi

    # Compare on sanitised leaf names: the archive may carry directory
    # structure the flat layout will discard later anyway.
    members="$(printf '%s\n' "$members" | while IFS= read -r member; do
        [[ -z "$member" ]] && continue
        [[ "$member" == */ ]] && continue
        printf '%s\n' "$(sanitize_filename "$(basename "$member")" | tr '[:upper:]' '[:lower:]')"
    done)"

    while IFS= read -r expected; do
        [[ -z "$expected" ]] && continue
        sanitized="$(sanitize_filename "$(trim_field "$expected")" | tr '[:upper:]' '[:lower:]')"
        [[ -z "$sanitized" ]] && continue
        if ! printf '%s\n' "$members" | grep -qxF "$sanitized"; then
            echo -e "  ${YELLOW}[WHOLE] Archive is missing ${expected}; falling back to per-file downloads${NC}"
            missing=1
            break
        fi
    done < <($JQ_CMD -r '.files.items[]? | .filename // empty' "$source_json" 2>/dev/null)

    [[ "$missing" -eq 0 ]]
}

try_whole_model_archive() {
    local model_dir="$1"
    local model_id="$2"
    local source_json="$3"
    local archive_path=""
    local archive_url=""
    local app_throttle_attempts=0
    local archive_size=""

    archive_path="$(whole_model_archive_path "$model_dir" "$model_id")"
    archive_url="${MMF_BASE_URL}/download/${model_id}"

    rm -f "$archive_path" "${archive_path}.part"

    echo -e "  ${YELLOW}Trying whole-model archive (1 request)...${NC}"

    while true; do
        if download_file_with_guards "$archive_url" "$archive_path" "application/zip" "fetching whole-model archive for model $model_id" "$(basename "$archive_path")"; then
            break
        fi

        # An HTML body here means MMF has no generated archive for this model
        # -- an ordinary, expected outcome, not a failure worth retrying.
        if [[ -n "$DOWNLOAD_LAST_TMP_FILE" ]] && [[ -f "$DOWNLOAD_LAST_TMP_FILE" ]] && is_html_error "$DOWNLOAD_LAST_TMP_FILE"; then
            if ! is_cloudflare_challenge_failure; then
                echo -e "  ${CYAN}[WHOLE] No whole-model archive available; using per-file downloads${NC}"
                rm -f "$archive_path" "${archive_path}.part" "$DOWNLOAD_LAST_TMP_FILE"
                return 1
            fi
        fi

        if is_cloudflare_challenge_failure; then
            rm -f "$archive_path" "${archive_path}.part" "$DOWNLOAD_LAST_TMP_FILE"
            wait_out_cloudflare_cooldown "fetching whole-model archive for model $model_id"
            continue
        fi

        if is_app_throttle_failure && [[ $app_throttle_attempts -lt $MAX_APP_THROTTLE_ATTEMPTS_PER_ITEM ]]; then
            app_throttle_attempts=$((app_throttle_attempts + 1))
            rm -f "$archive_path" "${archive_path}.part" "$DOWNLOAD_LAST_TMP_FILE"
            wait_out_app_throttle "fetching whole-model archive for model $model_id"
            continue
        fi

        # Anything else: say so quietly and let the per-file path try, since it
        # may still succeed for the individual files. Deliberately NOT phrased
        # as "HTTP 403" -- the desktop app reads that as proof the session died
        # and would clear a perfectly good saved cookie mid-run.
        echo -e "  ${CYAN}[WHOLE] No whole-model archive for this model (curl exit ${DOWNLOAD_LAST_CURL_EXIT}, status ${DOWNLOAD_LAST_HTTP_CODE:-unknown}); using per-file downloads${NC}"
        rm -f "$archive_path" "${archive_path}.part" "$DOWNLOAD_LAST_TMP_FILE"
        return 1
    done

    if ! whole_model_archive_is_complete "$archive_path" "$source_json"; then
        rm -f "$archive_path"
        return 1
    fi

    note_adaptive_success
    archive_size=$(get_file_size "$archive_path")
    echo -e "  ${GREEN}[WHOLE] Fetched entire model in one request (${archive_size} bytes)${NC}"
    return 0
}

compress_non_json_assets() {
    local model_dir="$1"
    local source_json="$2"
    local model_id="$3"
    local archive_base=""
    local existing_archive=""
    local archive_name=""
    local archive_path=""
    local payload_dir=""
    local -a all_files=()
    local -a moved_originals=()
    local file_name=""
    local lower_name=""
    local sanitized=""
    local target=""
    local input_bytes=0
    local payload_bytes=0
    local compression_exit=0
    local existing_size=""
    local zip_size=""

    archive_base=$(get_model_archive_basename "$source_json" "$model_id")
    existing_archive=$(find_existing_assets_archive "$model_dir" "$archive_base" || true)

    if [[ -n "$existing_archive" ]] && archive_is_declared_source "$source_json" "${existing_archive##*/}"         && ! archive_looks_repacked "$existing_archive"; then
        # Same name as the archive we build, but it is the creator's own file
        # and still needs expanding and repacking. Move it aside first: the
        # source collector excludes anything matching the archive name, so
        # leaving it where it is would hide the only file we have to pack.
        # The "__src_" prefix also keeps it clear of the archive-name glob.
        echo -e "  ${CYAN}[ZIP] Declared file shares the archive name; repacking it${NC}"
        if ! mv -f "$existing_archive" "${model_dir}/__src_${existing_archive##*/}"; then
            echo -e "  ${RED}[FAIL] Could not set aside $(basename "$existing_archive") for repacking${NC}"
            return 1
        fi
        existing_archive=""
    fi

    if [[ -n "$existing_archive" ]]; then
        existing_size=$(get_file_size "$existing_archive")
        echo -e "  ${GREEN}[SKIP] Assets archive already exists: $(basename "$existing_archive") (${existing_size} bytes)${NC}"
        return 0
    fi

    archive_name="${archive_base}.zip"

    collect_model_root_asset_files "$model_dir" "$archive_name" all_files

    if [[ ${#all_files[@]} -eq 0 ]]; then
        echo -e "  ${YELLOW}! No non-JSON files to compress${NC}"
        return 0
    fi

    input_bytes=$(sum_compress_input_bytes "$model_dir" "${all_files[@]}")

    # Expansion stages the payload alongside the sources before the archive is
    # written, so budget for roughly twice the raw payload.
    if ! ensure_compress_free_space "$model_dir" "creating ZIP archive for model $model_id" "$((input_bytes * 2))"; then
        abort_no_space "creating ZIP archive for model $model_id"
    fi

    payload_dir="${model_dir}/.p"
    ACTIVE_PAYLOAD_DIR="$payload_dir"
    ACTIVE_PAYLOAD_MODEL_DIR="$model_dir"
    PAYLOAD_MOVED_ORIGINALS=()
    rm -rf "$payload_dir"
    if ! mkdir -p "$payload_dir"; then
        echo -e "  ${RED}[FAIL] Could not create staging directory for model $model_id${NC}"
        return 1
    fi

    PAYLOAD_STORE_NAMES=()
    PAYLOAD_DEFLATE_NAMES=()
    EXPANDED_FROM_ZIP_COUNT=0

    for file_name in "${all_files[@]}"; do
        lower_name=$(printf '%s' "$file_name" | tr '[:upper:]' '[:lower:]')

        if [[ "$lower_name" == *.zip ]]; then
            # Left in place until the new archive validates -- unzip only reads
            # it, so there is nothing to roll back if packaging fails.
            if ! expand_zip_into_payload "${model_dir}/${file_name}" "$payload_dir" 1; then
                echo -e "  ${RED}[FAIL] Could not expand ${file_name} for model $model_id${NC}"
                restore_payload_originals "$model_dir" "$payload_dir" "${moved_originals[@]}"
                return 1
            fi
            continue
        fi

        sanitized=$(sanitize_filename "$file_name")
        target="$(reserve_payload_name "$sanitized" "$payload_dir")"
        if ! mv -f "${model_dir}/${file_name}" "${payload_dir}/${target}"; then
            echo -e "  ${RED}[FAIL] Could not stage ${file_name} for model $model_id${NC}"
            restore_payload_originals "$model_dir" "$payload_dir" "${moved_originals[@]}"
            return 1
        fi
        moved_originals+=("${target}|${file_name}")
        PAYLOAD_MOVED_ORIGINALS=("${moved_originals[@]}")
        PAYLOAD_STORE_NAMES+=("$target")
    done

    if [[ ${#PAYLOAD_STORE_NAMES[@]} -eq 0 ]] && [[ ${#PAYLOAD_DEFLATE_NAMES[@]} -eq 0 ]]; then
        echo -e "  ${YELLOW}! Nothing to package for model $model_id after expansion${NC}"
        rm -rf "$payload_dir"
        return 1
    fi

    if [[ "$EXPANDED_FROM_ZIP_COUNT" -gt 0 ]]; then
        echo -e "  ${CYAN}[ZIP] Expanded ${EXPANDED_FROM_ZIP_COUNT} member(s) out of nested archive(s)${NC}"
    fi

    payload_bytes=$(sum_payload_bytes "$payload_dir")
    rm -f "$archive_path"

    if ! resolve_zip_executable >/dev/null 2>&1; then
        ZIP_COMPRESS_FAILURE="zip executable not found (expected bundled tools/zip.exe or system zip in PATH)"
        print_archive_failure_report "$archive_path" "zip command failed (exit 127)" "${all_files[@]}"
        restore_payload_originals "$model_dir" "$payload_dir" "${moved_originals[@]}"
        return 1
    fi

    # Pass 1: plain files, stored. Entry sizes then match the declared API
    # sizes exactly, which is what makes the byte-total check meaningful.
    if [[ ${#PAYLOAD_STORE_NAMES[@]} -gt 0 ]]; then
        ZIP_COMPRESS_LEVEL="-0"
        ZIP_COMPRESS_APPEND=0
        run_zip_compress "$payload_dir" "$archive_name" "$payload_bytes" "${PAYLOAD_STORE_NAMES[@]}"
        compression_exit=$?
    fi

    # Pass 2: anything expanded out of a .zip, deflated back down.
    if [[ "$compression_exit" -eq 0 ]] && [[ ${#PAYLOAD_DEFLATE_NAMES[@]} -gt 0 ]]; then
        ZIP_COMPRESS_LEVEL="-6"
        if [[ ${#PAYLOAD_STORE_NAMES[@]} -gt 0 ]]; then
            ZIP_COMPRESS_APPEND=1
        else
            ZIP_COMPRESS_APPEND=0
        fi
        run_zip_compress "$payload_dir" "$archive_name" "$payload_bytes" "${PAYLOAD_DEFLATE_NAMES[@]}"
        compression_exit=$?
    fi

    ZIP_COMPRESS_LEVEL="-0"
    ZIP_COMPRESS_APPEND=0

    if [[ "$compression_exit" -ne 0 ]]; then
        print_archive_failure_report "${payload_dir}/${archive_name}" "zip command failed (exit ${compression_exit})" "${all_files[@]}"
        rm -f "${payload_dir}/${archive_name}"
        restore_payload_originals "$model_dir" "$payload_dir" "${moved_originals[@]}"
        echo -e "  ${RED}[FAIL] Failed to create ${archive_name}${NC}"
        return 1
    fi

    # Validate before anything is deleted, while the sources can still be put
    # back.
    if ! is_valid_archive_file "${payload_dir}/${archive_name}"; then
        print_archive_failure_report "${payload_dir}/${archive_name}" "archive failed integrity check after zip reported success" "${all_files[@]}"
        rm -f "${payload_dir}/${archive_name}"
        restore_payload_originals "$model_dir" "$payload_dir" "${moved_originals[@]}"
        echo -e "  ${RED}[FAIL] Created archive failed validation for model $model_id${NC}"
        return 1
    fi

    # Sources go first so the archive can take its proper name even when a
    # declared file was spelled identically.
    for file_name in "${all_files[@]}"; do
        rm -f "${model_dir}/${file_name}"
    done

    archive_path="${model_dir}/${archive_name}"
    if ! mv -f "${payload_dir}/${archive_name}" "$archive_path"; then
        echo -e "  ${RED}[FAIL] Could not move finished archive into ${model_dir}${NC}"
        rm -f "${payload_dir}/${archive_name}"
        restore_payload_originals "$model_dir" "$payload_dir" "${moved_originals[@]}"
        return 1
    fi

    rm -rf "$payload_dir"
    ACTIVE_PAYLOAD_DIR=""
    PAYLOAD_MOVED_ORIGINALS=()
    zip_size=$(get_file_size "$archive_path")
    echo -e "  ${GREEN}[OK] Created $(basename "$archive_path") (${zip_size} bytes)${NC}"
    return 0
}

echo -e "${CYAN}========================================================${NC}"
echo -e "${CYAN}   Bulk Downloader — STL/ZIP (Enhanced Edition)        ${NC}"
echo -e "${CYAN}========================================================${NC}"
echo ""

# Validate cookie before doing anything else
echo -e "${BLUE}Validating cookie configuration...${NC}"
if ! validate_cookie; then
    exit 1
fi
echo ""

# Check if we're in the correct directory (should contain JSON files)
if ! ls model_*.json 1> /dev/null 2>&1; then
    echo -e "${RED}Error: No model JSON files found. Run the metadata downloader first (Step 1).${NC}"
    exit 1
fi

# Check if jq is available
JQ_CMD="jq"
if ! command -v jq &> /dev/null; then
    if [[ -f "${SCRIPT_DIR}/jq.exe" ]]; then
        JQ_CMD="${SCRIPT_DIR}/jq.exe"
    elif [[ -f "${SCRIPT_DIR}/jq" ]]; then
        JQ_CMD="${SCRIPT_DIR}/jq"
    elif [[ -f "../jq.exe" ]]; then
        JQ_CMD="../jq.exe"
    elif [[ -f "../jq" ]]; then
        JQ_CMD="../jq"
    elif [[ -f "./jq.exe" ]]; then
        JQ_CMD="./jq.exe"
    elif [[ -f "./jq" ]]; then
        JQ_CMD="./jq"
    else
        echo -e "${RED}Error: jq not found. Download from https://github.com/stedolan/jq/releases${NC}"
        echo "Place jq or jq.exe in the same directory as this script"
        exit 1
    fi
fi

# Create STL downloads directory
mkdir -p stl_files
cd stl_files || exit
# From here on the run owns partial files on disk; make sure Ctrl+C does not
# leave them behind.
trap cleanup_on_interrupt INT TERM

cleanup_orphan_part_files

load_model_ids_filter

# Count JSON files selected for this run.
shopt -s nullglob
model_json_files=()
for json_candidate in ../model_*.json; do
    json_model_id=$(basename "$json_candidate" | sed 's/model_//; s/.json//')
    if is_model_id_selected "$json_model_id"; then
        model_json_files+=("$json_candidate")
    fi
done
shopt -u nullglob

json_count=${#model_json_files[@]}

if [[ $json_count -eq 0 ]]; then
    if [[ "$MODEL_IDS_FILTER_ACTIVE" -eq 1 ]]; then
        echo -e "${RED}Error: No model JSON files matched the selected batch. Run Step 1 for this batch first.${NC}"
    else
        echo -e "${RED}Error: No JSON files found${NC}"
    fi
    exit 1
fi

echo -e "${BLUE}Found $json_count JSON files to process${NC}"
if [[ "$MODEL_IDS_FILTER_ACTIVE" -eq 1 ]]; then
    echo -e "${BLUE}Batch filter active: processing only the selected model IDs${NC}"
fi
echo -e "${BLUE}Output folders: $FOLDER_NAMING_FORMAT (readable names; legacy model_<id> still supported)${NC}"
echo -e "${CYAN}Disk checks: ${MIN_FREE_SPACE_MB} MB minimum; uses MMF metadata file sizes when available${NC}"

zip_startup_exe=""
if zip_startup_exe="$(resolve_zip_executable 2>/dev/null)"; then
    if [[ "$zip_startup_exe" == *"/tools/zip.exe" ]] || [[ "$zip_startup_exe" == *"\\tools\\zip.exe" ]]; then
        echo -e "${CYAN}[ZIP] Using bundled Info-ZIP: ${zip_startup_exe}${NC}"
    elif is_nonstandard_zip_executable "$zip_startup_exe"; then
        echo -e "${YELLOW}[ZIP-WARN] zip in PATH may be MiKTeX (${zip_startup_exe}) — install Git zip or use the desktop build with tools/zip.exe${NC}"
    fi
else
    echo -e "${YELLOW}[ZIP-WARN] zip command not found — STL multi-file models need tools/zip.exe (desktop build) or Git Bash: pacman -S zip${NC}"
fi
if ! resolve_unzip_executable >/dev/null 2>&1; then
    echo -e "${YELLOW}[ZIP-WARN] unzip not found — archive validation will be limited${NC}"
fi

if ! ensure_min_free_space "." "$MIN_FREE_SPACE_MB" "before starting download loop"; then
    abort_no_space "before starting download loop"
fi

# TEST MODE - Download just one file to verify everything works
if [[ "$TEST_MODE" == true ]]; then
    echo -e "${YELLOW}=======================================${NC}"
    echo -e "${YELLOW}   RUNNING IN TEST MODE${NC}"
    echo -e "${YELLOW}=======================================${NC}"
    echo "Testing with first available model to verify cookie and setup..."
    emit_progress_event "{\"step\":\"test\",\"event\":\"start\"}"
    echo ""
    
    # Find first JSON file with download URLs
    for json_file in "${model_json_files[@]}"; do
        model_id=$(basename "$json_file" | sed 's/model_//; s/.json//')
        test_line=$($JQ_CMD -r '.files.items[]? | select(.download_url != null and .download_url != "") | "\(.filename // "")|\(.download_url // "")|\(.size // "")"' "$json_file" 2>/dev/null | head -1)

        if [[ -n "$test_line" ]]; then
            echo -e "${BLUE}Testing with model $model_id${NC}"
            
            # Get first file from this model
            filename="$(trim_field "$(echo "$test_line" | cut -d'|' -f1)")"
            download_url="$(trim_field "$(echo "$test_line" | cut -d'|' -f2)")"
            test_file_size_meta="$(metadata_size_to_bytes "$(trim_field "$(echo "$test_line" | cut -d'|' -f3)")")"

            if ! ensure_model_download_plan "$json_file" "$model_id" "."; then
                abort_no_space "running test mode download for model $model_id"
            fi
            if ! ensure_file_download_space "." "$filename" "$test_file_size_meta"; then
                abort_no_space "running test mode download for $filename"
            fi

            if [[ -z "$download_url" || "$download_url" == "null" ]]; then
                continue
            fi
            
            echo -e "  Downloading: ${CYAN}$filename${NC}"
            
            test_file="test_download_${model_id}.tmp"

            echo ""

            app_throttle_attempts=0
            while true; do
                if download_file_with_guards "$download_url" "$test_file" "application/octet-stream" "running test mode download" "$(basename "$test_file")"; then
                    file_size=$(get_file_size "$test_file")
                    echo -e "${GREEN}[OK] TEST PASSED${NC}"
                    echo -e "  Successfully downloaded ${CYAN}$filename${NC} (${file_size} bytes)"
                    echo "  File appears to be valid (not an error page)"
                    echo ""
                    echo -e "${GREEN}Cookie is working! You can now run the full download:${NC}"
                    echo "  bash $(basename "$0")"
                    rm -f "$test_file"
                    emit_progress_event "{\"step\":\"test\",\"event\":\"done\"}"
                    exit 0
                fi

                if [[ "$DOWNLOAD_LAST_CURL_EXIT" -eq 23 ]]; then
                    rm -f "$test_file" "${test_file}.part"
                    emit_progress_event "{\"step\":\"test\",\"event\":\"failed\"}"
                    abort_write_failure "running test mode download" "$(dirname "$test_file")"
                fi

                if is_cloudflare_challenge_failure; then
                    rm -f "$test_file" "${test_file}.part" "$DOWNLOAD_LAST_TMP_FILE"
                    wait_out_cloudflare_cooldown "running test mode download"
                    continue
                fi

                if is_app_throttle_failure && [[ $app_throttle_attempts -lt $MAX_APP_THROTTLE_ATTEMPTS_PER_ITEM ]]; then
                    app_throttle_attempts=$((app_throttle_attempts + 1))
                    rm -f "$test_file" "${test_file}.part" "$DOWNLOAD_LAST_TMP_FILE"
                    wait_out_app_throttle "running test mode download"
                    continue
                fi

                if [[ -n "$DOWNLOAD_LAST_TMP_FILE" ]] && [[ -f "$DOWNLOAD_LAST_TMP_FILE" ]] && is_html_error "$DOWNLOAD_LAST_TMP_FILE"; then
                    echo -e "${RED}[FAIL] TEST FAILED${NC}"
                    echo -e "${RED}Downloaded file is an HTML error page, not the actual file${NC}"
                    echo ""
                    show_error_content "$DOWNLOAD_LAST_TMP_FILE"
                    echo ""
                    echo -e "${YELLOW}Common causes:${NC}"
                    echo "  1. Cookie expired - get a fresh cookie from browser"
                    echo "  2. Missing cf_clearance token - copy cookie from download request, not page view"
                    echo "  3. Not logged in - make sure you're logged into MyMiniFactory in browser"
                    echo "  4. Cookie formatting error - check for extra quotes or special characters"
                    echo ""
                    echo -e "${CYAN}How to get a fresh cookie:${NC}"
                    echo "  1. Open MyMiniFactory in browser, log in"
                    echo "  2. Download any file from any model"
                    echo "  3. F12 -> Network -> Find 'download' request"
                    echo "  4. Copy the Cookie header value"
                    echo "  5. Paste into script (no extra quotes)"
                else
                    echo -e "${RED}[FAIL] TEST FAILED${NC}"
                    echo -e "${RED}Download failed (curl exit ${DOWNLOAD_LAST_CURL_EXIT}, HTTP ${DOWNLOAD_LAST_HTTP_CODE:-unknown})${NC}"
                    echo "Check cookie validity and your network connection."
                fi

                rm -f "$test_file" "${test_file}.part" "$DOWNLOAD_LAST_TMP_FILE"
                emit_progress_event "{\"step\":\"test\",\"event\":\"failed\"}"
                exit 1
            done
        else
            is_bought=$($JQ_CMD -r 'if has("is_bought") and .is_bought != null then (.is_bought | tostring) else "unknown" end' "$json_file" 2>/dev/null)
            if [[ "$is_bought" == "false" ]]; then
                echo -e "${YELLOW}! Model $model_id lists no downloadable files (is_bought=false, which is not an ownership test).${NC}"
            fi
        fi
    done
    
    echo -e "${RED}No downloadable files found for testing${NC}"
    echo -e "${YELLOW}If the listed models genuinely ship no files, this is expected. Pick a model with files for --test.${NC}"
    emit_progress_event "{\"step\":\"test\",\"event\":\"failed\"}"
    exit 1
fi

# FULL DOWNLOAD MODE
echo -e "${BLUE}Extracting download URLs, images, and creating per-model ZIP files...${NC}"
echo -e "${YELLOW}This will take a while - respecting rate limits${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop at any time${NC}"
echo ""

current_file=0
total_downloads=0
successful_downloads=0
consecutive_failures=0
compact_json_written=0
zip_created=0
models_zip_skipped=0
models_with_zero_files=0
models_without_file_downloads=0

ASSET_PROGRESS_TOTAL_UNITS=0
ASSET_PROGRESS_DONE_UNITS=0
ASSET_PROGRESS_MODELS_DONE=0
scan_index=0
echo -e "${CYAN}Checking which of the $json_count model(s) are already complete...${NC}"
emit_progress_event "{\"step\":\"scan\",\"event\":\"start\",\"totalModels\":$json_count}"
ZIP_VALIDATION_QUICK=1

# One jq invocation for every metadata file. Called per model it costs ~88 ms
# each on Windows and the scan needed about five per model -- around a minute
# of process startup before the first download on a 135-model library.
scan_facts=$($JQ_CMD -r '
    (input_filename | split("model_") | last | split(".json") | first) as $id
    | ([.files.items[]? | .download_url | select(. != null and . != "")] | length) as $dl
    | ([.images[]? | .original.url | select(. != null and . != "")] | length) as $img
    | "\($id)\u0001\($dl)\u0001\($img)\u0001\(.name // "")"
' "${model_json_files[@]}" 2>/dev/null)

while IFS=$'\001' read -r scan_id scan_dl scan_img scan_name; do
    [[ -z "$scan_id" ]] && continue
    scan_index=$((scan_index + 1))
    model_units=$(count_model_progress_units "model_${scan_id}.json" "$scan_id" "$scan_dl" "$scan_img" "$scan_name")
    if [[ "$model_units" =~ ^[0-9]+$ ]]; then
        ASSET_PROGRESS_TOTAL_UNITS=$((ASSET_PROGRESS_TOTAL_UNITS + model_units))
    fi
    # Keep an unattended run visibly alive without one line per model.
    if [[ $((scan_index % 25)) -eq 0 ]] || [[ "$scan_index" -eq "$json_count" ]]; then
        echo -e "  ${CYAN}Checked ${scan_index}/${json_count}${NC}"
        emit_progress_event "{\"step\":\"scan\",\"event\":\"progress\",\"done\":${scan_index},\"totalModels\":$json_count}"
    fi
done <<< "$scan_facts"

# If the bulk pass produced nothing usable (unreadable metadata, an unexpected
# jq), fall back to the original per-file walk rather than a bogus total.
if [[ "$scan_index" -eq 0 ]]; then
    for json_file in "${model_json_files[@]}"; do
        model_id_for_count=$(basename "$json_file" | sed 's/model_//; s/.json//')
        model_units=$(count_model_progress_units "$json_file" "$model_id_for_count")
        if [[ "$model_units" =~ ^[0-9]+$ ]]; then
            ASSET_PROGRESS_TOTAL_UNITS=$((ASSET_PROGRESS_TOTAL_UNITS + model_units))
        fi
    done
fi
ZIP_VALIDATION_QUICK=0
emit_progress_event "{\"step\":\"scan\",\"event\":\"done\",\"totalModels\":$json_count}"
if [[ "$ASSET_PROGRESS_TOTAL_UNITS" -eq 0 ]]; then
    ASSET_PROGRESS_TOTAL_UNITS="$json_count"
fi
emit_asset_progress_start "$json_count" "$ASSET_PROGRESS_TOTAL_UNITS"

# Process each JSON file
for json_file in "${model_json_files[@]}"; do
    current_file=$((current_file + 1))
    model_id=$(basename "$json_file" | sed 's/model_//; s/.json//')

    emit_asset_progress_model_start "$model_id" "$current_file" "$json_count"
    echo -e "${BLUE}[$current_file/$json_count] Processing model $model_id...${NC}"

    is_bought=$($JQ_CMD -r 'if has("is_bought") and .is_bought != null then (.is_bought | tostring) else "unknown" end' "$json_file" 2>/dev/null)
    downloadable_file_count=$($JQ_CMD -r '[.files.items[]? | .download_url | select(. != null and . != "")] | length' "$json_file" 2>/dev/null)
    if [[ ! "$downloadable_file_count" =~ ^[0-9]+$ ]]; then
        downloadable_file_count=0
    fi

    # Copyright and ownership guard: if no downloadable STL/ZIP URLs exist,
    # do not create any output for this model (no metadata, no images).
    if [[ "$downloadable_file_count" -eq 0 ]]; then
        models_with_zero_files=$((models_with_zero_files + 1))
        if [[ "$is_bought" == "false" ]]; then
            echo -e "${YELLOW}  ! Model $model_id lists no downloadable files. (is_bought=false does not mean you lack access — subscription and gifted models report false too.)${NC}"
        else
            echo -e "${YELLOW}  ! Model $model_id lists no downloadable files. Nothing to download.${NC}"
        fi
        emit_asset_progress_unit "$model_id" "model" "skipped"
        emit_asset_progress_model_done "$model_id"
        echo ""
        continue
    fi

    # Create directory for this model (readable name; falls back to legacy model_<id> if present)
    final_model_dir=$(resolve_model_dir "$model_id" "$json_file")
    model_dir=$(prepare_model_staging_dir "$model_id" "$final_model_dir")
    ACTIVE_STAGING_DIR="$model_dir"
    mkdir -p "$model_dir"
    if [[ "$final_model_dir" != "model_${model_id}" ]]; then
        echo -e "  ${CYAN}Using folder: ${final_model_dir}/${NC}"
    fi
    model_file_successful_downloads=0
    model_assets_complete=0
    whole_model_ok=0
    existing_assets_archive=""

    if model_assets_already_archived "$model_dir" "$json_file" "$model_id"; then
        existing_assets_archive=$(find_existing_assets_archive "$model_dir" "$(get_model_archive_basename "$json_file" "$model_id")" || true)
        if [[ -n "$existing_assets_archive" ]]; then
            existing_archive_size=$(get_file_size "$existing_assets_archive")
            echo -e "  ${GREEN}[SKIP] Model assets already archived in $(basename "$existing_assets_archive") (${existing_archive_size} bytes) — skipping STL/ZIP re-download.${NC}"
        else
            echo -e "  ${GREEN}[SKIP] Model assets already archived (per-file ZIP wrapper(s)) — skipping STL/ZIP re-download.${NC}"
        fi
        model_file_successful_downloads=$downloadable_file_count
        model_assets_complete=1
        models_zip_skipped=$((models_zip_skipped + 1))
        successful_downloads=$((successful_downloads + downloadable_file_count))
    fi

    # Extract downloadable files from metadata
    download_data=$($JQ_CMD -r '.files.items[]? | "\(.filename // "")|\(.download_url // "")|\(.size // "")"' "$json_file" 2>/dev/null)

    if [[ -z "$download_data" ]]; then
        echo -e "${YELLOW}  ! No STL/ZIP file URLs found in metadata. Skipping model output.${NC}"
        rm -rf "$model_dir"
        models_without_file_downloads=$((models_without_file_downloads + 1))
        emit_asset_progress_unit "$model_id" "model" "skipped"
        emit_asset_progress_model_done "$model_id"
        echo ""
        continue
    elif [[ "$model_assets_complete" -eq 0 ]]; then
        whole_model_ok=0
        if [[ "$WHOLE_MODEL_ROUTE" == "1" ]] && try_whole_model_archive "$model_dir" "$model_id" "$json_file"; then
            whole_model_ok=1
            total_downloads=$((total_downloads + 1))
            successful_downloads=$((successful_downloads + 1))
            model_file_successful_downloads=$downloadable_file_count
            consecutive_failures=0
            whole_model_unit=0
            while [[ "$whole_model_unit" -lt "$downloadable_file_count" ]]; do
                emit_asset_progress_unit "$model_id" "file" "downloaded"
                whole_model_unit=$((whole_model_unit + 1))
            done
            adaptive_sleep
        fi

        # Only budget for per-file downloads if that is actually what we are
        # about to do. The plan assumes a 2 GB minimum for every file with no
        # declared size, which a model with many null sizes turns into a
        # demand for hundreds of GB that the whole-model route never needs.
        if [[ "$whole_model_ok" -eq 0 ]] && ! ensure_model_download_plan "$json_file" "$model_id" "$model_dir"; then
            abort_no_space "before downloading files for model $model_id"
        fi

        reserved_model_output_names=""
        model_sanitized_name_collisions=0
        if model_has_sanitized_filename_collisions "$download_data"; then
            model_sanitized_name_collisions=1
        fi

        while IFS='|' read -r filename download_url file_size_meta; do
            if [[ "$whole_model_ok" -eq 1 ]]; then
                break
            fi

            if [[ -z "$filename" ]]; then
                continue
            fi

            filename="$(trim_field "$filename")"
            filename=$(sanitize_filename "$filename")
            download_url="$(trim_field "$download_url")"
            file_size_meta="$(metadata_size_to_bytes "$(trim_field "$file_size_meta")")"

            if [[ -z "$download_url" || "$download_url" == "null" ]]; then
                echo -e "  ${YELLOW}! Skipping $filename: no download URL (likely not owned or unavailable).${NC}"
                continue
            fi

            reserved_filename="$(reserve_model_output_name "$filename" "$reserved_model_output_names")"
            reserved_model_output_names="${reserved_model_output_names}${reserved_filename}"$'\n'
            if [[ "$reserved_filename" != "$filename" ]]; then
                echo -e "  ${CYAN}[NAME] Sanitized filename collision: ${filename} -> ${reserved_filename}${NC}"
                filename="$reserved_filename"
            fi

            if ! ensure_file_download_space "$model_dir" "$filename" "$file_size_meta"; then
                abort_no_space "before downloading $filename for model $model_id"
            fi

            canonical_output="${model_dir}/${filename}"
            can_skip_existing=0
            has_known_size=0
            if [[ "$file_size_meta" =~ ^[0-9]+$ ]] && [[ "$file_size_meta" -gt 0 ]]; then
                has_known_size=1
            fi

            if [[ -f "$canonical_output" ]] && is_reusable_download_file "$canonical_output" "$filename" "$file_size_meta"; then
                if [[ "$model_sanitized_name_collisions" -eq 1 ]] && [[ "$has_known_size" -eq 0 ]]; then
                    echo -e "  ${YELLOW}! Not skipping $(basename "$canonical_output"): multiple metadata files map to the same sanitized name and size is unknown.${NC}"
                else
                    can_skip_existing=1
                fi
            elif [[ -f "$canonical_output" ]] && is_valid_download_file "$canonical_output" "$filename"; then
                if [[ "$has_known_size" -eq 1 ]]; then
                    echo -e "  ${YELLOW}! Existing file size differs from metadata for $(basename "$canonical_output"); re-downloading.${NC}"
                fi
            fi

            if [[ "$can_skip_existing" -eq 1 ]]; then
                file_size=$(get_file_size "$canonical_output")
                echo -e "  ${GREEN}[SKIP] Already downloaded: $(basename "$canonical_output") (${file_size} bytes)${NC}"
                successful_downloads=$((successful_downloads + 1))
                model_file_successful_downloads=$((model_file_successful_downloads + 1))
                consecutive_failures=0
                emit_asset_progress_unit "$model_id" "file" "skipped"
                continue
            fi

            if [[ -e "$canonical_output" ]]; then
                echo -e "  ${YELLOW}! Removing invalid or mismatched existing file: $(basename "$canonical_output")${NC}"
                rm -f "$canonical_output"
            fi

            output_file="$(unique_output_path "$model_dir" "$filename")"

            total_downloads=$((total_downloads + 1))

            echo -e "  ${YELLOW}Downloading file: $(basename "$output_file")${NC}"

            app_throttle_attempts=0
            while true; do
                if download_file_with_guards "$download_url" "$output_file" "application/octet-stream" "downloading file $(basename "$output_file")" "$(basename "$output_file")"; then
                    file_size=$(get_file_size "$output_file")
                    echo -e "  ${GREEN}[OK] Downloaded $(basename "$output_file") (${file_size} bytes)${NC}"
                    successful_downloads=$((successful_downloads + 1))
                    model_file_successful_downloads=$((model_file_successful_downloads + 1))
                    consecutive_failures=0
                    note_adaptive_success
                    emit_asset_progress_unit "$model_id" "file" "downloaded"
                    break
                fi

                if [[ "$DOWNLOAD_LAST_CURL_EXIT" -eq 23 ]]; then
                    rm -f "$output_file" "${output_file}.part" "$DOWNLOAD_LAST_TMP_FILE"
                    emit_asset_progress_unit "$model_id" "file" "failed"
                    abort_write_failure "downloading file $(basename "$output_file")" "$model_dir"
                fi

                if [[ "$DOWNLOAD_LAST_FAILURE_REASON" == "rename" ]]; then
                    consecutive_failures=$((consecutive_failures + 1))
                    rm -f "$output_file" "${output_file}.part"
                    emit_asset_progress_unit "$model_id" "file" "failed"

                    if [[ $consecutive_failures -ge $MAX_CONSECUTIVE_FAILURES ]]; then
                        echo ""
                        echo -e "${RED}=======================================================${NC}"
                        echo -e "${RED}STOPPING: $MAX_CONSECUTIVE_FAILURES consecutive save failures${NC}"
                        echo -e "${RED}=======================================================${NC}"
                        print_write_failure_hints
                        exit 1
                    fi

                    adaptive_sleep
                    continue 2
                fi

                if is_cloudflare_challenge_failure; then
                    rm -f "$output_file" "${output_file}.part" "$DOWNLOAD_LAST_TMP_FILE"
                    wait_out_cloudflare_cooldown "downloading file $(basename "$output_file")"
                    continue
                fi

                if is_app_throttle_failure && [[ $app_throttle_attempts -lt $MAX_APP_THROTTLE_ATTEMPTS_PER_ITEM ]]; then
                    app_throttle_attempts=$((app_throttle_attempts + 1))
                    rm -f "$output_file" "${output_file}.part" "$DOWNLOAD_LAST_TMP_FILE"
                    wait_out_app_throttle "downloading file $(basename "$output_file")"
                    continue
                fi

                if [[ -n "$DOWNLOAD_LAST_TMP_FILE" ]] && [[ -f "$DOWNLOAD_LAST_TMP_FILE" ]]; then
                    if is_html_error "$DOWNLOAD_LAST_TMP_FILE"; then
                        echo -e "  ${RED}[FAIL] Failed: Downloaded HTML error page instead of file${NC}"

                        if [[ $consecutive_failures -eq 0 ]]; then
                            show_error_content "$DOWNLOAD_LAST_TMP_FILE"
                        fi
                    else
                        echo -e "  ${RED}[FAIL] Failed validation for $(basename "$output_file")${NC}"
                    fi

                    rm -f "$DOWNLOAD_LAST_TMP_FILE"
                else
                    echo -e "  ${RED}[FAIL] Failed to download $(basename "$output_file") (curl exit ${DOWNLOAD_LAST_CURL_EXIT}, HTTP ${DOWNLOAD_LAST_HTTP_CODE:-unknown})${NC}"
                fi

                consecutive_failures=$((consecutive_failures + 1))
                rm -f "$output_file" "${output_file}.part"
                emit_asset_progress_unit "$model_id" "file" "failed"

                if [[ $consecutive_failures -ge $MAX_CONSECUTIVE_FAILURES ]]; then
                    echo ""
                    echo -e "${RED}=======================================================${NC}"
                    echo -e "${RED}STOPPING: $MAX_CONSECUTIVE_FAILURES consecutive failures detected${NC}"
                    echo -e "${RED}=======================================================${NC}"
                    echo ""
                    echo -e "${YELLOW}This indicates a systematic problem (not random failures)${NC}"
                    echo ""
                    echo -e "${CYAN}Most likely causes:${NC}"
                    echo "  1. Cookie expired - get fresh cookie from browser"
                    echo "  2. Missing cf_clearance token in cookie"
                    echo "  3. Session logged out - log back into MyMiniFactory"
                    echo "  4. Account permissions issue"
                    echo ""
                    echo -e "${CYAN}To fix:${NC}"
                    echo "  1. Log into MyMiniFactory in your browser"
                    echo "  2. Download a file manually to verify access"
                    echo "  3. Copy fresh cookie from that download request (F12 -> Network)"
                    echo "  4. Update COOKIE variable in script"
                    echo "  5. Run in test mode first: bash $(basename "$0") --test"
                    exit 1
                fi

                break
            done

            adaptive_sleep
        done <<< "$download_data"
    fi

    if [[ "$model_file_successful_downloads" -eq 0 ]]; then
        echo -e "${YELLOW}  ! No files could be downloaded for model $model_id. Removing metadata/images output for copyright compliance.${NC}"
        rm -rf "$model_dir"
        models_without_file_downloads=$((models_without_file_downloads + 1))
        emit_asset_progress_unit "$model_id" "model" "failed"
        emit_asset_progress_model_done "$model_id"
        echo ""
        continue
    fi

    # Build compact JSON only when at least one STL/ZIP file was downloaded.
    if write_compact_model_json "$json_file" "$model_dir" "$model_id"; then
        compact_json_written=$((compact_json_written + 1))
        emit_asset_progress_unit "$model_id" "json" "written"
    else
        emit_asset_progress_unit "$model_id" "json" "failed"
    fi

    # Download images only when the model has at least one successfully downloaded file.
    download_model_images "$json_file" "$model_dir" "$model_id"

    # Compress only model root files to a zip archive; images stay in model_<id>/images
    if [[ "$model_assets_complete" -eq 1 ]]; then
        zip_created=$((zip_created + 1))
        emit_asset_progress_unit "$model_id" "zip" "skipped"
    elif compress_non_json_assets "$model_dir" "$json_file" "$model_id"; then
        zip_created=$((zip_created + 1))
        emit_asset_progress_unit "$model_id" "zip" "created"
    else
        emit_asset_progress_unit "$model_id" "zip" "failed"
    fi

    # Only now does the model become visible to anything walking the library.
    if ! finalize_model_staging_dir "$model_dir" "$final_model_dir"; then
        emit_asset_progress_unit "$model_id" "model" "failed"
        emit_asset_progress_model_done "$model_id"
        echo ""
        continue
    fi
    ACTIVE_STAGING_DIR=""

    emit_asset_progress_unit "$model_id" "model" "completed"
    emit_asset_progress_model_done "$model_id"
    echo ""
done

rmdir "$STAGING_ROOT" 2>/dev/null || true

emit_progress_event "{\"step\":\"assets\",\"event\":\"done\",\"totalModels\":$json_count,\"workTotal\":$ASSET_PROGRESS_TOTAL_UNITS,\"workDone\":$ASSET_PROGRESS_TOTAL_UNITS,\"modelsDone\":$ASSET_PROGRESS_MODELS_DONE}"

echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}   Download Complete!${NC}"
echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}Successful downloads: $successful_downloads/$total_downloads files and images${NC}"
if [[ $((total_downloads - successful_downloads)) -gt 0 ]]; then
    echo -e "${YELLOW}Failed downloads: $((total_downloads - successful_downloads))${NC}"
fi
if [[ "$models_with_zero_files" -gt 0 ]]; then
    echo -e "${CYAN}Models listing no downloadable files (normal — renders/licences): $models_with_zero_files${NC}"
fi
if [[ "$models_without_file_downloads" -gt 0 ]]; then
    echo -e "${YELLOW}Models whose files could not be downloaded: $models_without_file_downloads${NC}"
fi
if [[ "$models_zip_skipped" -gt 0 ]]; then
    echo -e "${GREEN}Models skipped (assets ZIP already present): $models_zip_skipped${NC}"
fi
echo -e "${GREEN}Compact JSON files written: $compact_json_written${NC}"
echo -e "${GREEN}ZIP archives created: $zip_created${NC}"
echo -e "${BLUE}Output structure: stl_files/<id>_<model_name>/model_<id>.json + <model_name>.zip + images/${NC}"
echo ""

echo "Sample of generated directories:"
find . -name "model_*" -type d 2>/dev/null | head -5 | while read -r dir; do
    file_count=$(find "$dir" -maxdepth 1 -type f | wc -l)
    echo "  $dir: $file_count files"
done
