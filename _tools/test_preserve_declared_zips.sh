#!/usr/bin/env bash
# Exercises compress_non_json_assets against the three shapes a model can take,
# using real zip files on disk rather than mocks.
set -o pipefail

FUNCS="/tmp/mmf_funcs.sh"
JQ_CMD="jq"
# shellcheck disable=SC1090
source "$FUNCS" >/dev/null 2>&1
# the sourced file sets SCRIPT_DIR from its own path, so point it at the repo
# afterwards or the bundled tools/zip.exe is never found
SCRIPT_DIR="C:/Users/rewal/Downloads/MMF Downloader Claude/MMF_DOWNLOADER"

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
pass=0; fail=0

check() { # name expected actual
    if [[ "$2" == "$3" ]]; then
        echo "  PASS  $1"; pass=$((pass+1))
    else
        echo "  FAIL  $1"; echo "        expected: $2"; echo "        actual:   $3"; fail=$((fail+1))
    fi
}

# The machine has no system `zip` (the repo bundles tools/zip.exe), so the
# fixtures are built with python's zipfile.
make_zip() { # path file1 contents1 ...
    python -c '
import sys, zipfile
out = sys.argv[1]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    args = sys.argv[2:]
    for i in range(0, len(args), 2):
        z.writestr(args[i], args[i + 1])
' "$@"
}

# ---------------------------------------------------------------- scenario 1
# A creator who grouped their model into several archives (a multi-storey building set).
scenario_grouped() {
    local dir="${ROOT}/grouped"; mkdir -p "$dir"
    make_zip "${dir}/BUILDING_LV1.zip" floor1.stl "level one mesh"
    make_zip "${dir}/BUILDING_LV2.zip" floor2.stl "level two mesh"
    make_zip "${dir}/BUILDING_XTRAS.zip" extra.stl "extras mesh"
    cat > "${dir}/src.json" <<'JSON'
{"id":176982,"name":"a multi-storey building set","files":{"items":[
 {"filename":"BUILDING_LV1.zip","size":1},
 {"filename":"BUILDING_LV2.zip","size":1},
 {"filename":"BUILDING_XTRAS.zip","size":1}]}}
JSON
    compress_non_json_assets "$dir" "${dir}/src.json" 176982 >/dev/null 2>&1
    local got; got="$(cd "$dir" && ls *.zip 2>/dev/null | sort | tr '\n' ' ')"
    check "grouped: all three creator archives kept separate" \
          "BUILDING_LV1.zip BUILDING_LV2.zip BUILDING_XTRAS.zip " "$got"
    check "grouped: no merged model archive created" \
          "0" "$(cd "$dir" && ls The_Last_Hearth_Inn.zip 2>/dev/null | wc -l | tr -d ' ')"
    check "grouped: contents intact inside a kept archive" \
          "floor1.stl" "$(unzip -Z1 "${dir}/BUILDING_LV1.zip" 2>/dev/null | tr -d '\r')"
}

# ---------------------------------------------------------------- scenario 2
# The common case: loose meshes, which must still be packed into one archive.
scenario_loose() {
    local dir="${ROOT}/loose"; mkdir -p "$dir"
    printf 'mesh a' > "${dir}/part-a.stl"
    printf 'mesh b' > "${dir}/part-b.stl"
    cat > "${dir}/src.json" <<'JSON'
{"id":105546,"name":"Junk Barricades","files":{"items":[
 {"filename":"part-a.stl","size":6},
 {"filename":"part-b.stl","size":6}]}}
JSON
    compress_non_json_assets "$dir" "${dir}/src.json" 105546 >/dev/null 2>&1
    check "loose: packed into one model archive" \
          "Junk_Barricades.zip" "$(cd "$dir" && ls *.zip 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
    check "loose: both meshes inside it" \
          "part-a.stl part-b.stl" \
          "$(unzip -Z1 "${dir}/Junk_Barricades.zip" 2>/dev/null | tr -d '\r' | sort | tr '\n' ' ' | sed 's/ $//')"
}

# ---------------------------------------------------------------- scenario 3
# Mixed: creator archives plus loose extras. Archives kept, extras packed.
scenario_mixed() {
    local dir="${ROOT}/mixed"; mkdir -p "$dir"
    make_zip "${dir}/Bases.zip" base.stl "a base"
    printf 'readme' > "${dir}/notes.pdf"
    cat > "${dir}/src.json" <<'JSON'
{"id":96892,"name":"Example Model B","files":{"items":[
 {"filename":"Bases.zip","size":1},
 {"filename":"notes.pdf","size":6}]}}
JSON
    compress_non_json_assets "$dir" "${dir}/src.json" 96892 >/dev/null 2>&1
    local got; got="$(cd "$dir" && ls *.zip 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')"
    check "mixed: creator archive kept AND extras packed" \
          "Bases.zip Example_Model_B.zip" "$got"
    check "mixed: kept archive still holds its own file" \
          "base.stl" "$(unzip -Z1 "${dir}/Bases.zip" 2>/dev/null | tr -d '\r')"
}

# ---------------------------------------------------------------- scenario 4
# The opt-out must restore the old single-archive behaviour exactly.
scenario_optout() {
    local dir="${ROOT}/optout"; mkdir -p "$dir"
    make_zip "${dir}/LV1.zip" floor1.stl "level one"
    make_zip "${dir}/LV2.zip" floor2.stl "level two"
    cat > "${dir}/src.json" <<'JSON'
{"id":1,"name":"Old Behaviour","files":{"items":[
 {"filename":"LV1.zip","size":1},{"filename":"LV2.zip","size":1}]}}
JSON
    PRESERVE_DECLARED_ZIPS=0 compress_non_json_assets "$dir" "${dir}/src.json" 1 >/dev/null 2>&1
    check "opt-out: merged back into a single archive" \
          "Old_Behaviour.zip" "$(cd "$dir" && ls *.zip 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
    check "opt-out: both meshes merged in" \
          "floor1.stl floor2.stl" \
          "$(unzip -Z1 "${dir}/Old_Behaviour.zip" 2>/dev/null | tr -d '\r' | sort | tr '\n' ' ' | sed 's/ $//')"
}

# ---------------------------------------------------------------- scenario 5
# Re-running must not redo a finished grouped model.
scenario_resume() {
    local dir="${ROOT}/resume"; mkdir -p "$dir"
    make_zip "${dir}/A.zip" a.stl "a"
    make_zip "${dir}/B.zip" b.stl "b"
    cat > "${dir}/src.json" <<'JSON'
{"id":7,"name":"Resume Test","files":{"items":[
 {"filename":"A.zip","size":1},{"filename":"B.zip","size":1}]}}
JSON
    if model_assets_already_archived "$dir" "${dir}/src.json" 7 "Resume Test"; then
        check "resume: grouped model recognised as finished" "done" "done"
    else
        check "resume: grouped model recognised as finished" "done" "re-download"
    fi
    rm -f "${dir}/B.zip"
    if model_assets_already_archived "$dir" "${dir}/src.json" 7 "Resume Test"; then
        check "resume: missing archive still counts as unfinished" "unfinished" "done"
    else
        check "resume: missing archive still counts as unfinished" "unfinished" "unfinished"
    fi
}

echo "=== preserve-declared-zips behaviour ==="
scenario_grouped
scenario_loose
scenario_mixed
scenario_optout
scenario_resume
echo
echo "passed: $pass   failed: $fail"
[[ "$fail" -eq 0 ]]
