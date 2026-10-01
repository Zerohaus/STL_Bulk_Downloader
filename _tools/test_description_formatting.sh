#!/usr/bin/env bash
# The jq program that builds model_<id>.json lives inside the downloader as a
# single-quoted shell string, so it is easy to break and never notice until a
# run produces bad metadata. This pulls that exact program out, runs it on
# fixtures, and checks the description keeps the creator's line breaks.
#
# Background: MyMiniFactory serves the blurb twice. "description" is plain text
# with every line break stripped; "description_html" is what the creator wrote.
# Reading the plain field turned formatted listings into a wall of text.
set -o pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/mmf_download_stl_files_enhanced.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0

check() { # name expected actual
    if [[ "$2" == "$3" ]]; then
        echo "  PASS  $1"; pass=$((pass+1))
    else
        echo "  FAIL  $1"; echo "        expected: $(printf '%q' "$2")"; echo "        actual:   $(printf '%q' "$3")"; fail=$((fail+1))
    fi
}

# Pull the jq program out of the script, turning bash's '"'"' escapes back into
# plain single quotes.
python - "$SRC" "$WORK/meta.jq" <<'PY'
import io, re, sys
src = io.open(sys.argv[1], encoding="utf-8").read()
start = src.index('--arg cached_description "$cached_description" ')
start = src.index("'", start) + 1
depth, i = 0, start
# the program ends at the quote that closes the shell string: the first lone
# ' that is not part of a '"'"' sequence
while i < len(src):
    if src[i] == "'":
        if src[i:i+5] == '\'"\'"\'':
            i += 5
            continue
        break
    i += 1
prog = src[start:i].replace('\'"\'"\'', "'")
io.open(sys.argv[2], "w", encoding="utf-8", newline="\n").write(prog)
print("  extracted %d bytes of jq" % len(prog))
PY

run_jq() { # source-json
    jq --argjson selected_categories '[]' \
       --argjson selected_category_tag_names '[]' \
       --arg cached_description "" \
       -f "$WORK/meta.jq" "$1" | tr -d '\r'
}
# jq's stdout on Windows rewrites every \n as \r\n. That is not in the data,
# but it breaks any assertion that looks at runs of newlines, so it is stripped
# above rather than worked around in each check.

# ---- fixture: paragraphs, a list, entities, CRLF endings, inline markup
cat > "$WORK/a.json" <<'JSON'
{"id":1,"name":"Example Model",
 "description":"Flat one-liner with no breaks at all.",
 "description_html":"<p>First paragraph.</p>\r\n<p>Set includes:</p>\r\n<p>Floor</p>\r\n<p>Roof &amp; Door</p>\r\n<p> </p>\r\n<p>Needs <strong>supports</strong>.<br />Second line.</p>",
 "tags":["a"],"price":{"value":"5.00"}}
JSON

out="$(run_jq "$WORK/a.json")" || { echo "  jq failed"; exit 1; }
desc="$(printf '%s' "$out" | jq -r '.description')"

echo "=== the program still compiles and runs ==="
check "produces JSON with a description" "yes" "$([ -n "$desc" ] && echo yes || echo no)"

echo "=== the creator's structure survives ==="
check "paragraphs became blank lines" "yes" \
      "$(printf '%s' "$desc" | grep -q 'First paragraph\.$' && echo yes || echo no)"
check "list items are on their own lines" "Floor" \
      "$(printf '%s' "$desc" | grep -x 'Floor' || true)"
check "<br> became a line break" "Second line." \
      "$(printf '%s' "$desc" | grep -x 'Second line.' || true)"
check "no HTML tags leak through" "0" \
      "$(printf '%s' "$desc" | grep -c '<' || true)"
check "entities are resolved" "Roof & Door" \
      "$(printf '%s' "$desc" | grep -x 'Roof & Door' || true)"
check "no run of 3+ newlines survives" "0" \
      "$(printf '%s' "$desc" | python -c "import sys; print(1 if chr(10)*3 in sys.stdin.read() else 0)")"
check "it is not the flat field" "no" \
      "$([ "$desc" = "Flat one-liner with no breaks at all." ] && echo yes || echo no)"

# ---- fixture: no HTML at all, so the plain field has to be used
cat > "$WORK/b.json" <<'JSON'
{"id":2,"name":"No HTML","description":"Only the plain field here.","description_html":"","tags":[],"price":{"value":"5.00"}}
JSON
desc2="$(run_jq "$WORK/b.json" | jq -r '.description')"
echo "=== falls back when there is no HTML ==="
check "uses the plain description" "Only the plain field here." "$desc2"

# ---- fixture: both empty, must not crash or invent text
cat > "$WORK/c.json" <<'JSON'
{"id":3,"name":"Empty","description":"","description_html":"","tags":[],"price":{"value":"5.00"}}
JSON
desc3="$(run_jq "$WORK/c.json" | jq -r '.description')"
echo "=== empty stays empty ==="
check "no invented description" "" "$desc3"

echo
echo "passed: $pass   failed: $fail"
[[ "$fail" -eq 0 ]]
