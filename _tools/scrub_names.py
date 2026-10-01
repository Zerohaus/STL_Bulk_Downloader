"""Replace real creator, model and folder names with generic stand-ins.

This repository is public. Creator names are business relationships and the
specific models they sell are theirs, so nothing published here should carry
them -- not in docs, not in comments, not as test fixtures.

Run before publishing, and after any change that might have reintroduced one:

    python _tools/scrub_names.py            # report only
    python _tools/scrub_names.py --apply

Add new names to REPLACEMENTS as creators are onboarded. Longer keys are
applied first so "Dark Platypus Studio" is handled before "Dark Platypus".
"""
import argparse, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# real -> generic. Order does not matter; longest is applied first.
REPLACEMENTS = {
    # creators
    "Dark Platypus Studio": "Creator One",
    "Dark-Platypus Studio": "Creator One",
    "Dark Platypus": "Creator One",
    "DarkPlatypus": "CreatorOne",
    "darkplatypus": "creatorone",
    "Brander Roullett": "Creator Two",
    "TinyFurniture": "CreatorThree",
    "CobraMode": "CreatorFour",
    "CreepyHero": "CreatorFive",
    "Imp3dsion": "CreatorSix",
    "Adamant Arsenal": "Creator Seven",
    "ProxyRealms": "CreatorEight",
    # models and their files
    "The Last Hearth Inn": "a multi-storey building set",
    "Last Hearth Inn": "multi-storey building set",
    "LHI_INN": "BUILDING",
    "Nightmare Horse (Pre-Supported)": "Example Model B",
    "Nightmare_Horse": "Example_Model_B",
    "Nightmare Horse": "Example Model B",
    "Gaslands - Roadside Billboards": "Example Model C",
    "Gaslands": "Example Set",
    "Magna-Build": "Modular-Build",
    "Mausoleum": "Example Crypt",
    "The Grand Bridge": "a large bridge model",
    "Grand Bridge": "large bridge model",
}

# Checked for leaks but never rewritten: these are the user's own, not a
# creator's, and the repo already belongs to that account.
ALLOWED = {"Zerohaus", "zerohaus"}

SKIP_DIRS = {".git", "node_modules", "dist", "build", "tools"}
SKIP_EXT = {".exe", ".dll", ".zip", ".png", ".ico", ".icns", ".svg", ".blockmap", ".7z"}


def target_files():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if os.path.splitext(name)[1].lower() in SKIP_EXT:
                continue
            if name == os.path.basename(__file__):
                continue
            yield os.path.join(dirpath, name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    keys = sorted(REPLACEMENTS, key=len, reverse=True)
    pattern = re.compile("|".join(re.escape(k) for k in keys))
    total_hits = 0
    touched = []

    for path in target_files():
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except (UnicodeDecodeError, OSError):
            continue

        hits = pattern.findall(text)
        if not hits:
            continue

        total_hits += len(hits)
        rel = os.path.relpath(path, ROOT)
        counts = {}
        for h in hits:
            counts[h] = counts.get(h, 0) + 1
        print("  %-44s %s" % (rel, ", ".join("%s x%d" % kv for kv in sorted(counts.items()))))

        if args.apply:
            with open(path, "w", encoding="utf-8", newline="") as fh:
                fh.write(pattern.sub(lambda m: REPLACEMENTS[m.group(0)], text))
            touched.append(rel)

    print("-" * 78)
    if total_hits == 0:
        print("clean: no real creator or model names found")
        return 0
    if args.apply:
        print("rewrote %d name(s) across %d file(s)" % (total_hits, len(touched)))
    else:
        print("%d name(s) found. Re-run with --apply to replace them." % total_hits)
    return 1 if not args.apply else 0


if __name__ == "__main__":
    sys.exit(main())
