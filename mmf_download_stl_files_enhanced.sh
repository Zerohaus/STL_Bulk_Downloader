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
MIN_FREE_SPACE_MB="${MMF_MIN_FREE_SPACE_MB:-2048}"
DISK_MARGIN_MB_PER_FILE="${MMF_DISK_MARGIN_MB_PER_FILE:-512}"
DISK_MARGIN_MB_MODEL="${MMF_DISK_MARGIN_MB_MODEL:-1024}"
ZIP32_LIMIT_BYTES=4294967295
ZIP64_RETRY_BYTES=3500000000
CURL_RETRIES="${MMF_CURL_RETRIES:-2}"
MODEL_IDS_FILTER_RAW="${MMF_MODEL_IDS_FILTER:-}"

DOWNLOAD_LAST_CURL_EXIT=0
DOWNLOAD_LAST_HTTP_CODE=""
DOWNLOAD_LAST_TMP_FILE=""
DOWNLOAD_LAST_ORIGINAL_URL=""
DOWNLOAD_LAST_SANITIZED_URL=""
DOWNLOAD_LAST_URL_SANITIZATION_NOTE=""
DOWNLOAD_LAST_URL_SANITIZATION_CHANGED=0
DISK_CHECK_WARNED=0
MODEL_IDS_FILTER_PADDED=""
MODEL_IDS_FILTER_ACTIVE=0
ASSET_PROGRESS_TOTAL_UNITS=0
ASSET_PROGRESS_DONE_UNITS=0
ASSET_PROGRESS_MODELS_DONE=0

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
                echo -e "  ${CYAN}[DISK] Model $model_id — $unknown_count file(s) without size; using ${MIN_FREE_SPACE_MB} MB minimum each${NC}"
                required_mb=$((required_mb + unknown_count * MIN_FREE_SPACE_MB))
            fi
        fi
    else
        echo -e "  ${YELLOW}[DISK] Model $model_id — no file sizes in metadata; using ${MIN_FREE_SPACE_MB} MB minimum per file ($file_count file(s))${NC}"
        if [[ "$file_count" -gt 0 ]]; then
            required_mb=$((MIN_FREE_SPACE_MB * file_count))
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

abort_no_space() {
    local context="$1"
    echo ""
    log_disk_context "." "$context" ""
    echo -e "${RED}=======================================================${NC}"
    echo -e "${RED}STOPPING: No space left on device${NC}"
    echo -e "${RED}=======================================================${NC}"
    echo -e "${YELLOW}Context: ${context}${NC}"
    echo "Free disk space and run the script again."
    echo "Only validated complete files are kept; partial files are discarded."
    exit 1
}

validate_zip_integrity() {
    local zip_file="$1"

    if command -v unzip >/dev/null 2>&1; then
        unzip -tqq "$zip_file" >/dev/null 2>&1
        return $?
    fi

    if command -v zip >/dev/null 2>&1; then
        zip -T "$zip_file" >/dev/null 2>&1
        return $?
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

download_file_with_guards() {
    local download_url="$1"
    local output_path="$2"
    local accept_header="$3"
    local context_label="$4"
    local logical_name="$5"
    local tmp_path="${output_path}.part"
    local sanitized_download_url=""

    DOWNLOAD_LAST_CURL_EXIT=0
    DOWNLOAD_LAST_HTTP_CODE=""
    DOWNLOAD_LAST_TMP_FILE="$tmp_path"
    DOWNLOAD_LAST_ORIGINAL_URL="$download_url"
    DOWNLOAD_LAST_SANITIZED_URL=""
    DOWNLOAD_LAST_URL_SANITIZATION_NOTE=""
    DOWNLOAD_LAST_URL_SANITIZATION_CHANGED=0

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

    rm -f "$tmp_path"

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
        -w "%{http_code}" \
        "$sanitized_download_url" \
        -o "$tmp_path")"
    DOWNLOAD_LAST_CURL_EXIT=$?

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
        rm -f "$tmp_path"
        DOWNLOAD_LAST_TMP_FILE=""
        return 22
    fi

    if ! is_valid_download_file "$tmp_path" "$logical_name"; then
        return 65
    fi

    if ! mv -f "$tmp_path" "$output_path"; then
        rm -f "$tmp_path"
        DOWNLOAD_LAST_TMP_FILE=""

        if ! ensure_min_free_space "$output_path" "$MIN_FREE_SPACE_MB" "saving ${context_label}"; then
            DOWNLOAD_LAST_CURL_EXIT=23
            return 23
        fi

        return 1
    fi

    DOWNLOAD_LAST_TMP_FILE=""
    return 0
}

cleanup_orphan_part_files() {
    local removed_count=0

    while IFS= read -r -d '' part_file; do
        rm -f "$part_file"
        removed_count=$((removed_count + 1))
    done < <(find . -type f -name "*.part" -print0 2>/dev/null)

    if [[ "$removed_count" -gt 0 ]]; then
        echo -e "${YELLOW}! Removed ${removed_count} orphan .part file(s) from previous interrupted runs.${NC}"
    fi
}

sanitize_filename() {
    local original_name="$1"
    local sanitized_name
    local base_name
    local extension=""

    sanitized_name=$(printf "%s" "$original_name" | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177')
    sanitized_name="$(trim_field "$sanitized_name")"
    sanitized_name=$(printf "%s" "$sanitized_name" | sed -E "s/[<>:\"/\\|?*]/_/g; s/'//g; s/[[:space:]]+/ /g")
    sanitized_name="${sanitized_name// /_}"
    sanitized_name=$(printf "%s" "$sanitized_name" | sed -E 's/_+/_/g')

    if [[ "$sanitized_name" == *.* ]] && [[ "$sanitized_name" != .* ]]; then
        base_name="${sanitized_name%.*}"
        extension=".${sanitized_name##*.}"
    else
        base_name="$sanitized_name"
    fi

    base_name=$(printf "%s" "$base_name" | sed -E 's/[. ]+$//; s/^[_.]+//; s/[_.]+$//; s/_+/_/g')
    extension=$(printf "%s" "$extension" | sed -E 's/[. ]+$//')

    if [[ -z "$base_name" ]]; then
        if [[ -n "$extension" ]]; then
            sanitized_name="unnamed_file${extension}"
        else
            sanitized_name="unnamed_file"
        fi
    else
        sanitized_name="${base_name}${extension}"
    fi

    sanitized_name=$(printf "%s" "$sanitized_name" | sed -E 's/[. ]+$//')

    if [[ "$sanitized_name" =~ ^_+$ ]]; then
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
    local name="$1"
    local cleaned=""

    cleaned="$(printf "%s" "$name" | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177')"
    cleaned="$(trim_field "$cleaned")"
    cleaned="$(printf "%s" "$cleaned" | sed -E "s/[<>:\"/\\|?*]/_/g; s/'//g; s/[[:space:]]+/ /g")"
    cleaned="${cleaned// /_}"
    cleaned="$(printf "%s" "$cleaned" | sed -E 's/_+/_/g; s/[. ]+$//; s/^[_.]+//; s/[_.]+$//')"

    if [[ -z "$cleaned" ]]; then
        cleaned="unnamed_model"
    fi

    if [[ ${#cleaned} -gt $MAX_FOLDER_NAME_LENGTH ]]; then
        cleaned="${cleaned:0:$MAX_FOLDER_NAME_LENGTH}"
        cleaned="$(printf "%s" "$cleaned" | sed -E 's/_+$//')"
    fi

    if [[ -z "$cleaned" ]]; then
        cleaned="unnamed_model"
    fi

    if [[ "$cleaned" =~ ^_+$ ]]; then
        cleaned="unnamed_model"
    fi

    printf "%s" "$cleaned"
}

build_model_folder_name() {
    local source_json="$1"
    local model_id="$2"
    local model_name=""
    local clean_name=""

    model_name="$(trim_field "$($JQ_CMD -r '.name // ""' "$source_json" 2>/dev/null)")"
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

resolve_model_dir() {
    local model_id="$1"
    local json_file="$2"
    local preferred=""
    local legacy="model_${model_id}"

    preferred=$(build_model_folder_name "$json_file" "$model_id")

    if [[ -d "$preferred" ]]; then
        printf '%s' "$preferred"
        return
    fi

    if [[ -d "$legacy" ]]; then
        printf '%s' "$legacy"
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

get_model_archive_basename() {
    local source_json="$1"
    local model_id="$2"
    local model_name=""
    local archive_base=""

    model_name="$(trim_field "$($JQ_CMD -r '.name // ""' "$source_json" 2>/dev/null)")"
    archive_base=$(sanitize_filename "$model_name")

    if [[ -z "$archive_base" || "$archive_base" == "null" ]]; then
        archive_base="model_${model_id}_assets"
    fi

    printf "%s" "$archive_base"
}

is_valid_archive_file() {
    local file_path="$1"
    is_valid_download_file "$file_path" "$(basename "$file_path")"
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

model_root_assets_are_standalone_zips() {
    local model_dir="$1"
    local exclude_name="$2"
    local found_any=0
    local file_path base_name lower_name

    while IFS= read -r -d '' file_path; do
        found_any=1
        base_name=$(basename "$file_path")
        lower_name=$(printf '%s' "$base_name" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower_name" != *.zip ]]; then
            return 1
        fi
        if ! is_valid_archive_file "$file_path"; then
            return 1
        fi
    done < <(find "$model_dir" -maxdepth 1 -type f ! -name "*.json" ! -name "$exclude_name" -print0 2>/dev/null)

    [[ "$found_any" -eq 1 ]]
}

print_zip_compress_stderr() {
    local zip_stderr="$1"

    if [[ ! -s "$zip_stderr" ]]; then
        return
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -n "$line" ]]; then
            echo -e "  ${RED}[ZIP-DEBUG] zip: ${line}${NC}"
        fi
    done < "$zip_stderr"
}

print_zip_failure_debug() {
    local archive_path="$1"
    local compression_exit="$2"
    local failure_reason="$3"
    shift 3
    local -a files_to_zip=("$@")

    echo -e "  ${RED}[ZIP-DEBUG] Archive path: $archive_path${NC}"
    echo -e "  ${RED}[ZIP-DEBUG] zip exit code: $compression_exit${NC}"
    if [[ -n "$failure_reason" ]]; then
        echo -e "  ${RED}[ZIP-DEBUG] ${failure_reason}${NC}"
    fi
    echo -e "  ${RED}[ZIP-DEBUG] Files considered for archive: ${#files_to_zip[@]}${NC}"
    for file_name in "${files_to_zip[@]}"; do
        echo "    $file_name"
    done
}

run_zip_compress() {
    local model_dir="$1"
    local archive_name="$2"
    local expected_bytes="${3:-0}"
    shift 3
    local -a files_to_zip=("$@")
    local zip_stderr=""
    local zip_list=""
    local compression_exit=1
    local batch_size=20
    local index=0
    local batch_end=0
    local -a batch_files=()
    local grow_mode=0
    local zip_store_flags=(-q -0)
    local zip_grow_flags=(-q -0 -g)
    local tried_zip64=0

    if [[ ${#files_to_zip[@]} -eq 0 ]]; then
        return 1
    fi

    if [[ "$expected_bytes" =~ ^[0-9]+$ ]] && (( expected_bytes > ZIP64_RETRY_BYTES )); then
        zip_store_flags=(-q -fz -0)
        zip_grow_flags=(-q -fz -0 -g)
        echo -e "  ${CYAN}[ZIP] Using Zip64 mode (-fz) for $(format_bytes_human "$expected_bytes") payload${NC}"
    fi

    zip_stderr="$(mktemp "${TMPDIR:-/tmp}/mmf-zip-err.XXXXXX" 2>/dev/null || mktemp /tmp/mmf-zip-err.XXXXXX)"
    zip_list="$(mktemp "${TMPDIR:-/tmp}/mmf-zip-list.XXXXXX" 2>/dev/null || mktemp /tmp/mmf-zip-list.XXXXXX)"

    {
        for file_name in "${files_to_zip[@]}"; do
            printf '%s\n' "$file_name"
        done
    } > "$zip_list"

    if command -v zip >/dev/null 2>&1; then
        rm -f "${model_dir}/${archive_name}"
        : > "$zip_stderr"
        (cd "$model_dir" && zip "${zip_store_flags[@]}" "$archive_name" -@) < "$zip_list" 2>"$zip_stderr"
        compression_exit=$?

        if [[ "$compression_exit" -ne 0 ]]; then
            rm -f "${model_dir}/${archive_name}"
            : > "$zip_stderr"
            grow_mode=0
            index=0
            while [[ "$index" -lt "${#files_to_zip[@]}" ]]; do
                batch_end=$((index + batch_size))
                batch_files=("${files_to_zip[@]:index:batch_size}")
                if [[ "$grow_mode" -eq 0 ]]; then
                    (cd "$model_dir" && zip "${zip_store_flags[@]}" "$archive_name" "${batch_files[@]}") 2>>"$zip_stderr"
                    compression_exit=$?
                    grow_mode=1
                else
                    (cd "$model_dir" && zip "${zip_grow_flags[@]}" "$archive_name" "${batch_files[@]}") 2>>"$zip_stderr"
                    compression_exit=$?
                fi

                if [[ "$compression_exit" -ne 0 ]]; then
                    break
                fi

                index=$batch_end
            done
        fi

        if [[ "$compression_exit" -ne 0 ]] && [[ "$tried_zip64" -eq 0 ]] && [[ "${zip_store_flags[1]}" != "-fz" ]] \
            && [[ "$expected_bytes" =~ ^[0-9]+$ ]] && (( expected_bytes > ZIP64_RETRY_BYTES )); then
            tried_zip64=1
            echo -e "  ${YELLOW}[ZIP] Retrying archive creation with Zip64 (-fz)...${NC}"
            rm -f "${model_dir}/${archive_name}"
            : > "$zip_stderr"
            (cd "$model_dir" && zip -q -fz -0 "$archive_name" -@) < "$zip_list" 2>"$zip_stderr"
            compression_exit=$?
        fi
    fi

    if [[ "$compression_exit" -ne 0 ]] && command -v tar >/dev/null 2>&1; then
        echo -e "  ${YELLOW}[ZIP] zip failed; trying tar fallback...${NC}"
        rm -f "${model_dir}/${archive_name}"
        : > "$zip_stderr"
        (cd "$model_dir" && tar -a -cf "$archive_name" -T "$zip_list") 2>"$zip_stderr"
        compression_exit=$?
    fi

    if [[ "$compression_exit" -ne 0 ]]; then
        echo -e "  ${RED}[ZIP-DEBUG] zip/tar command failed — see zip stderr lines above${NC}"
        if [[ "$expected_bytes" =~ ^[0-9]+$ ]] && (( expected_bytes > ZIP32_LIMIT_BYTES )); then
            echo -e "  ${RED}[ZIP-DEBUG] Payload is over 4 GiB; ensure Git Bash zip supports Zip64 (-fz) and the drive has $(format_bytes_human "$expected_bytes")+ free${NC}"
        fi
    fi

    print_zip_compress_stderr "$zip_stderr"
    rm -f "$zip_stderr" "$zip_list"
    return "$compression_exit"
}

model_assets_already_archived() {
    local model_dir="$1"
    local source_json="$2"
    local model_id="$3"
    local archive_base=""

    archive_base=$(get_model_archive_basename "$source_json" "$model_id")

    if find_existing_assets_archive "$model_dir" "$archive_base" >/dev/null; then
        return 0
    fi

    if model_root_assets_are_standalone_zips "$model_dir" "${archive_base}.zip"; then
        return 0
    fi

    return 1
}

count_model_progress_units() {
    local source_json="$1"
    local model_id="$2"
    local model_dir
    local downloadable_count
    local image_count

    downloadable_count=$($JQ_CMD -r '[.files.items[]? | .download_url | select(. != null and . != "")] | length' "$source_json" 2>/dev/null)
    if [[ ! "$downloadable_count" =~ ^[0-9]+$ ]]; then
        downloadable_count=0
    fi

    if [[ "$downloadable_count" -eq 0 ]]; then
        echo 1
        return
    fi

    image_count=$($JQ_CMD -r '[.images[]? | .original.url | select(. != null and . != "")] | length' "$source_json" 2>/dev/null)
    if [[ ! "$image_count" =~ ^[0-9]+$ ]]; then
        image_count=0
    fi

    model_dir=$(resolve_model_dir "$model_id" "$source_json")
    if model_assets_already_archived "$model_dir" "$source_json" "$model_id"; then
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

    rm -f "$output_tmp"

    if ! ensure_min_free_space "$output_json" "$MIN_FREE_SPACE_MB" "writing compact JSON for model $model_id"; then
        abort_no_space "writing compact JSON for model $model_id"
    fi

    if ! printf '%s' "$selected_categories_json" | $JQ_CMD -e '. | type == "array"' >/dev/null 2>&1; then
        selected_categories_json='[]'
    fi

    if ! printf '%s' "$selected_category_tag_names_json" | $JQ_CMD -e '. | type == "array"' >/dev/null 2>&1; then
        selected_category_tag_names_json='[]'
    fi

    if $JQ_CMD --argjson selected_categories "$selected_categories_json" --argjson selected_category_tag_names "$selected_category_tag_names_json" '{
        name: (.name // ""),
        description: (.description // ""),
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

    if ! printf '{"name":"","description":"","tags":[],"price":5,"categories":[]}\n' > "$output_tmp"; then
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

        if download_file_with_guards "$image_url" "$output_path" "image/*,*/*;q=0.8" "downloading image $(basename "$output_path")" "$(basename "$output_path")"; then
            local image_size
            image_size=$(get_file_size "$output_path")
            echo -e "  ${GREEN}[OK] Downloaded image $(basename "$output_path") (${image_size} bytes)${NC}"
            successful_downloads=$((successful_downloads + 1))
            emit_asset_progress_unit "$model_id" "image" "downloaded"
        else
            if [[ "$DOWNLOAD_LAST_CURL_EXIT" -eq 23 ]]; then
                rm -f "$output_path" "${output_path}.part"
                emit_asset_progress_unit "$model_id" "image" "failed"
                abort_no_space "downloading image $(basename "$output_path")"
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
        fi

        sleep "$IMAGE_DELAY_SEC"
    done <<< "$image_data"
}

compress_non_json_assets() {
    local model_dir="$1"
    local source_json="$2"
    local model_id="$3"
    local archive_base=""
    local existing_archive=""
    local archive_name=""
    local archive_path=""
    local -a files_to_zip=()
    local input_bytes=0
    local compression_exit=0

    archive_base=$(get_model_archive_basename "$source_json" "$model_id")
    existing_archive=$(find_existing_assets_archive "$model_dir" "$archive_base" || true)

    if [[ -n "$existing_archive" ]]; then
        local existing_size
        existing_size=$(get_file_size "$existing_archive")
        echo -e "  ${GREEN}[SKIP] Assets archive already exists: $(basename "$existing_archive") (${existing_size} bytes)${NC}"
        return 0
    fi

    archive_name="${archive_base}.zip"
    archive_path=$(unique_output_path "$model_dir" "$archive_name")
    archive_name=$(basename "$archive_path")

    collect_model_root_asset_files "$model_dir" "$archive_name" files_to_zip

    if [[ ${#files_to_zip[@]} -eq 0 ]]; then
        echo -e "  ${YELLOW}! No non-JSON files to compress${NC}"
        return 0
    fi

    if model_root_assets_are_standalone_zips "$model_dir" "$archive_name"; then
        echo -e "  ${GREEN}[OK] Assets already delivered as standalone ZIP file(s); skipping outer archive wrap${NC}"
        return 0
    fi

    input_bytes=$(sum_compress_input_bytes "$model_dir" "${files_to_zip[@]}")
    if ! ensure_compress_free_space "$model_dir" "creating ZIP archive for model $model_id" "$input_bytes"; then
        abort_no_space "creating ZIP archive for model $model_id"
    fi

    rm -f "$archive_path"

    if command -v zip >/dev/null 2>&1 || command -v tar >/dev/null 2>&1; then
        run_zip_compress "$model_dir" "$archive_name" "$input_bytes" "${files_to_zip[@]}"
        compression_exit=$?
    else
        echo -e "  ${RED}[FAIL] Could not compress files: zip/tar not found${NC}"
        return 1
    fi

    if [[ "$compression_exit" -ne 0 ]]; then
        print_zip_failure_debug "$archive_path" "$compression_exit" "" "${files_to_zip[@]}"
        rm -f "$archive_path"
        echo -e "  ${RED}[FAIL] Failed to create $(basename "$archive_path")${NC}"
        return 1
    fi

    if is_valid_archive_file "$archive_path"; then
        for file_name in "${files_to_zip[@]}"; do
            rm -f "${model_dir}/${file_name}"
        done
        local zip_size
        zip_size=$(get_file_size "$archive_path")
        echo -e "  ${GREEN}[OK] Created $(basename "$archive_path") (${zip_size} bytes)${NC}"
        return 0
    fi

    rm -f "$archive_path"
    print_zip_failure_debug "$archive_path" "$compression_exit" "Archive failed integrity validation after creation" "${files_to_zip[@]}"
    echo -e "  ${RED}[FAIL] Failed to create $(basename "$archive_path")${NC}"
    return 1
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
                abort_no_space "running test mode download"
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
        else
            is_bought=$($JQ_CMD -r '.is_bought // "unknown"' "$json_file" 2>/dev/null)
            if [[ "$is_bought" == "false" ]]; then
                echo -e "${YELLOW}! Skipping model $model_id in test mode: object is not in your library (is_bought=false).${NC}"
            fi
        fi
    done
    
    echo -e "${RED}No downloadable files found for testing${NC}"
    echo -e "${YELLOW}If the listed models are not owned, this is expected. Use owned models for --test.${NC}"
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
not_owned_skipped=0
models_without_file_downloads=0

ASSET_PROGRESS_TOTAL_UNITS=0
ASSET_PROGRESS_DONE_UNITS=0
ASSET_PROGRESS_MODELS_DONE=0
for json_file in "${model_json_files[@]}"; do
    model_id_for_count=$(basename "$json_file" | sed 's/model_//; s/.json//')
    model_units=$(count_model_progress_units "$json_file" "$model_id_for_count")
    if [[ "$model_units" =~ ^[0-9]+$ ]]; then
        ASSET_PROGRESS_TOTAL_UNITS=$((ASSET_PROGRESS_TOTAL_UNITS + model_units))
    fi
done
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

    is_bought=$($JQ_CMD -r '.is_bought // "unknown"' "$json_file" 2>/dev/null)
    downloadable_file_count=$($JQ_CMD -r '[.files.items[]? | .download_url | select(. != null and . != "")] | length' "$json_file" 2>/dev/null)
    if [[ ! "$downloadable_file_count" =~ ^[0-9]+$ ]]; then
        downloadable_file_count=0
    fi

    # Copyright and ownership guard: if no downloadable STL/ZIP URLs exist,
    # do not create any output for this model (no metadata, no images).
    if [[ "$downloadable_file_count" -eq 0 ]]; then
        if [[ "$is_bought" == "false" ]]; then
            not_owned_skipped=$((not_owned_skipped + 1))
            models_without_file_downloads=$((models_without_file_downloads + 1))
            echo -e "${YELLOW}  ! Object is not in your library (is_bought=false). Skipping model output for model $model_id.${NC}"
        else
            models_without_file_downloads=$((models_without_file_downloads + 1))
            echo -e "${YELLOW}  ! No downloadable STL/ZIP URLs found in metadata. Skipping model output.${NC}"
        fi
        emit_asset_progress_unit "$model_id" "model" "skipped"
        emit_asset_progress_model_done "$model_id"
        echo ""
        continue
    fi

    # Create directory for this model (readable name; falls back to legacy model_<id> if present)
    model_dir=$(resolve_model_dir "$model_id" "$json_file")
    mkdir -p "$model_dir"
    if [[ "$model_dir" != "model_${model_id}" ]]; then
        echo -e "  ${CYAN}Using folder: ${model_dir}/${NC}"
    fi
    model_file_successful_downloads=0
    model_assets_complete=0
    existing_assets_archive=""

    if model_assets_already_archived "$model_dir" "$json_file" "$model_id"; then
        existing_assets_archive=$(find_existing_assets_archive "$model_dir" "$(get_model_archive_basename "$json_file" "$model_id")")
        existing_archive_size=$(get_file_size "$existing_assets_archive")
        echo -e "  ${GREEN}[SKIP] Model assets already archived in $(basename "$existing_assets_archive") (${existing_archive_size} bytes) — skipping STL/ZIP re-download.${NC}"
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
        if ! ensure_model_download_plan "$json_file" "$model_id" "$model_dir"; then
            abort_no_space "before downloading files for model $model_id"
        fi

        while IFS='|' read -r filename download_url file_size_meta; do
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

            if ! ensure_file_download_space "$model_dir" "$filename" "$file_size_meta"; then
                abort_no_space "before downloading $filename for model $model_id"
            fi

            canonical_output="${model_dir}/${filename}"

            if [[ -f "$canonical_output" ]] && is_valid_download_file "$canonical_output" "$filename"; then
                file_size=$(get_file_size "$canonical_output")
                echo -e "  ${GREEN}[SKIP] Already downloaded: $(basename "$canonical_output") (${file_size} bytes)${NC}"
                successful_downloads=$((successful_downloads + 1))
                model_file_successful_downloads=$((model_file_successful_downloads + 1))
                consecutive_failures=0
                emit_asset_progress_unit "$model_id" "file" "skipped"
                continue
            fi

            if [[ -e "$canonical_output" ]]; then
                echo -e "  ${YELLOW}! Removing invalid existing file: $(basename "$canonical_output")${NC}"
                rm -f "$canonical_output"
            fi

            output_file="$(unique_output_path "$model_dir" "$filename")"

            total_downloads=$((total_downloads + 1))

            echo -e "  ${YELLOW}Downloading file: $(basename "$output_file")${NC}"

            if download_file_with_guards "$download_url" "$output_file" "application/octet-stream" "downloading file $(basename "$output_file")" "$(basename "$output_file")"; then
                file_size=$(get_file_size "$output_file")
                echo -e "  ${GREEN}[OK] Downloaded $(basename "$output_file") (${file_size} bytes)${NC}"
                successful_downloads=$((successful_downloads + 1))
                model_file_successful_downloads=$((model_file_successful_downloads + 1))
                consecutive_failures=0
                emit_asset_progress_unit "$model_id" "file" "downloaded"
            else
                if [[ "$DOWNLOAD_LAST_CURL_EXIT" -eq 23 ]]; then
                    rm -f "$output_file" "${output_file}.part" "$DOWNLOAD_LAST_TMP_FILE"
                    emit_asset_progress_unit "$model_id" "file" "failed"
                    abort_no_space "downloading file $(basename "$output_file")"
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
            fi

            sleep "$STL_FILE_DELAY_SEC"
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

    emit_asset_progress_unit "$model_id" "model" "completed"
    emit_asset_progress_model_done "$model_id"
    echo ""
done

emit_progress_event "{\"step\":\"assets\",\"event\":\"done\",\"totalModels\":$json_count,\"workTotal\":$ASSET_PROGRESS_TOTAL_UNITS,\"workDone\":$ASSET_PROGRESS_TOTAL_UNITS,\"modelsDone\":$ASSET_PROGRESS_MODELS_DONE}"

echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}   Download Complete!${NC}"
echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}Successful downloads: $successful_downloads/$total_downloads files and images${NC}"
if [[ $((total_downloads - successful_downloads)) -gt 0 ]]; then
    echo -e "${YELLOW}Failed downloads: $((total_downloads - successful_downloads))${NC}"
fi
if [[ "$not_owned_skipped" -gt 0 ]]; then
    echo -e "${YELLOW}Skipped models not owned: $not_owned_skipped${NC}"
fi
if [[ "$models_without_file_downloads" -gt 0 ]]; then
    echo -e "${YELLOW}Skipped model outputs with zero downloaded files: $models_without_file_downloads${NC}"
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
