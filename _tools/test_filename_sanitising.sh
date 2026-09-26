#!/usr/bin/env bash
# Filenames MyMiniFactory actually serves, against the sanitiser.
#
# The rule that matters: the output must be pure ASCII. curl on Windows cannot
# write a path containing non-ASCII bytes -- asked for "Бeз_имeни-1.jpg" it
# reports success and silently creates "_e____e__-1.jpg", so the caller cannot
# find the file it just downloaded and the whole run stops. Anything that
# leaks a non-ASCII byte here is that bug coming back.
set -o pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/mmf_download_stl_files_enhanced.sh"
FUNCS="$(mktemp)"
trap 'rm -f "$FUNCS"' EXIT

# Take the function half only; the main body needs a cookie and a catalogue.
head -n "$(($(grep -n 'Bulk Downloader — STL/ZIP (Enhanced Edition)' "$SRC" | head -1 | cut -d: -f1) - 2))" "$SRC" > "$FUNCS"
# shellcheck disable=SC1090
source "$FUNCS" >/dev/null 2>&1

pass=0; fail=0
check() { # input expected
    local got; got="$(sanitize_filename "$1")"
    if [[ "$got" == "$2" ]]; then
        printf '  PASS  %-30s -> %s\n' "$1" "$got"; pass=$((pass+1))
    else
        printf '  FAIL  %-30s -> %s (expected %s)\n' "$1" "$got" "$2"; fail=$((fail+1))
    fi
}

ascii_only() { # input
    local got; got="$(sanitize_filename "$1")"
    case "$got" in
        *[!$'\x01'-$'\x7f']*) printf '  FAIL  non-ASCII survived: %s -> %s\n' "$1" "$got"; fail=$((fail+1)) ;;
        *) printf '  PASS  pure ASCII out: %-22s -> %s\n' "$1" "$got"; pass=$((pass+1)) ;;
    esac
}

echo "=== the case that stopped a 676-model run ==="
check $'Бeз_имeни-1.jpg' 'Bez_imeni-1.jpg'

echo "=== Cyrillic transliterates rather than becoming underscores ==="
check $'Без имени-2.png' 'Bez_imeni-2.png'
check $'Щит и меч.zip'   'Shchit_i_mech.zip'

echo "=== accented Latin keeps its letters ==="
check $'Café.stl'        'Cafe.stl'
check $'Müller Señor.stl' 'Muller_Senor.stl'
check $'Straße.zip'      'Strasse.zip'

echo "=== Greek lookalikes in Roman numerals still fold (pre-existing rule) ==="
check $'Mausoleum ΙΙ.stl' 'Mausoleum_II.stl'

echo "=== ordinary names are untouched ==="
check 'plain_v2.stl'                 'plain_v2.stl'
check 'Monster Hunter Corner.zip'    'Monster_Hunter_Corner.zip'
check 'part-a_v1.1.stl'              'part-a_v1.1.stl'

echo "=== anything else degrades to ASCII rather than breaking the run ==="
ascii_only $'日本語.jpg'
ascii_only $'emoji 🎲 dice.stl'
ascii_only $'Ελληνικά.stl'
ascii_only $'混合 mixed Бeз.zip'

echo
echo "passed: $pass   failed: $fail"
[[ "$fail" -eq 0 ]]
