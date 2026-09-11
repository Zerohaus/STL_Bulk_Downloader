#!/bin/bash

# MyMiniFactory - Folder Renaming Script (Cross-platform)
# Renames model_<id> folders using model_<id>.json metadata names.
# Works on macOS and Linux. On Windows, use 4_rename_folders_from_json.ps1.

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

JSON_PATH="${MMF_JSON_PATH:-PATH/TO/YOUR/downloads}"
FOLDERS_PATH="${MMF_FOLDERS_PATH:-PATH/TO/YOUR/downloads/stl_files}"
NAMING_FORMAT="${MMF_NAMING_FORMAT:-ID_NAME}"
MAX_NAME_LENGTH_RAW="${MMF_MAX_NAME_LENGTH:-80}"

if [[ "$NAMING_FORMAT" != "NAME_ONLY" ]]; then
    NAMING_FORMAT="ID_NAME"
fi

if [[ "$MAX_NAME_LENGTH_RAW" =~ ^[0-9]+$ ]]; then
    MAX_NAME_LENGTH="$MAX_NAME_LENGTH_RAW"
else
    MAX_NAME_LENGTH=80
fi

if [[ "$MAX_NAME_LENGTH" -lt 10 ]]; then
    MAX_NAME_LENGTH=10
fi

if [[ "$MAX_NAME_LENGTH" -gt 160 ]]; then
    MAX_NAME_LENGTH=160
fi

sanitize_folder_name() {
    local name="$1"
    local cleaned=""

    cleaned="$(printf "%s" "$name" | tr -d '\r\n')"
    # Reserved characters and the apostrophe are DELETED, not replaced with an
    # underscore: that is the convention verified against 1,545 existing
    # folders, which keeps & [ ] ( ) ! - . and collapses only whitespace.
    cleaned="$(printf "%s" "$cleaned" | tr -d "'" | sed -E 's/[<>:"/\\|?*]//g; s/[[:space:]]+/ /g; s/ /_/g; s/_+/_/g; s/^_+//; s/_+$//')"

    if [[ -z "$cleaned" ]]; then
        cleaned="unnamed_model"
    fi

    if [[ ${#cleaned} -gt $MAX_NAME_LENGTH ]]; then
        cleaned="${cleaned:0:$MAX_NAME_LENGTH}"
        cleaned="$(printf "%s" "$cleaned" | sed -E 's/_+$//')"
    fi

    if [[ -z "$cleaned" ]]; then
        cleaned="unnamed_model"
    fi

    printf "%s" "$cleaned"
}

echo -e "${BLUE}MyMiniFactory Folder Renaming Tool (Cross-platform)${NC}"
echo -e "${BLUE}===================================================${NC}"
echo ""

if [[ ! -d "$JSON_PATH" ]]; then
    echo -e "${RED}ERROR: JSON path does not exist: $JSON_PATH${NC}"
    exit 1
fi

if [[ ! -d "$FOLDERS_PATH" ]]; then
    echo -e "${RED}ERROR: Folders path does not exist: $FOLDERS_PATH${NC}"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}ERROR: jq not found in PATH. Install jq and try again.${NC}"
    exit 1
fi

shopt -s nullglob
json_files=("$JSON_PATH"/model_*.json)
total_files=${#json_files[@]}

if [[ "$total_files" -eq 0 ]]; then
    echo -e "${RED}ERROR: No model_*.json files found in $JSON_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}Found $total_files JSON files${NC}"
echo -e "${BLUE}Naming format: $NAMING_FORMAT | Max length: $MAX_NAME_LENGTH${NC}"
echo ""

renamed=0
failed=0
skipped=0
current=0

for json_file in "${json_files[@]}"; do
    current=$((current + 1))

    model_file_name="$(basename "$json_file")"
    model_id="${model_file_name#model_}"
    model_id="${model_id%.json}"

    model_name="$(jq -r '.name // empty' "$json_file" 2>/dev/null | head -n 1 | tr -d '\r')"
    if [[ -z "$model_name" ]]; then
        echo -e "${YELLOW}[$current/$total_files] Model $model_id - no name found, skipping${NC}"
        skipped=$((skipped + 1))
        continue
    fi

    clean_name="$(sanitize_folder_name "$model_name")"

    if [[ "$NAMING_FORMAT" == "ID_NAME" ]]; then
        new_folder_name="${model_id}_${clean_name}"
    else
        new_folder_name="$clean_name"
    fi

    old_folder="$FOLDERS_PATH/model_$model_id"
    new_folder="$FOLDERS_PATH/$new_folder_name"

    if [[ ! -d "$old_folder" ]]; then
        echo -e "${YELLOW}[$current/$total_files] Model $model_id - source folder missing, skipping${NC}"
        skipped=$((skipped + 1))
        continue
    fi

    if [[ -e "$new_folder" ]]; then
        echo -e "${YELLOW}[$current/$total_files] Model $model_id - target exists ($new_folder_name), skipping${NC}"
        skipped=$((skipped + 1))
        continue
    fi

    echo -e "${BLUE}[$current/$total_files] Renaming model_$model_id -> $new_folder_name${NC}"

    if mv "$old_folder" "$new_folder"; then
        echo -e "  ${GREEN}[OK] Renamed${NC}"
        renamed=$((renamed + 1))
    else
        echo -e "  ${RED}[FAIL] Rename failed${NC}"
        failed=$((failed + 1))
    fi
done

echo ""
echo -e "${GREEN}Renaming Complete${NC}"
echo -e "${GREEN}=================${NC}"
echo -e "${GREEN}Renamed: $renamed${NC}"
if [[ "$skipped" -gt 0 ]]; then
    echo -e "${YELLOW}Skipped: $skipped${NC}"
fi
if [[ "$failed" -gt 0 ]]; then
    echo -e "${RED}Failed: $failed${NC}"
fi
