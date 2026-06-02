# Bundled Windows zip (Info-ZIP 3.0)

Step 2 uses the `zip` command to package downloaded STL/LYS files into a model `.zip`.

On Windows, Git Bash often does **not** include `zip`, and other apps (e.g. MiKTeX) may provide an incompatible `zip.exe`. This folder ships a known-good build so clients do not need `pacman -S zip`.

## Files

| File | Purpose |
|------|---------|
| `zip.exe` | Info-ZIP 3.0 (GnuWin32 build, July 2008) |
| `zip32z64.dll` | Zip64 support |
| `bzip2.dll` | Required dependency |

## License

Copyright (c) 1990-2008 Info-ZIP. See [Info-ZIP license](https://infozip.sourceforge.net/license.html).

Binaries were obtained from the [GnuWin32 zip 3.0 package](https://gnuwin32.sourceforge.net/packages/zip.htm) (binary + dependency zips).

## Refresh binaries

```bash
npm run vendor:zip
```

macOS/Linux builds use the system `/usr/bin/zip` and do not use this folder.

## RAR / 7z from MyMiniFactory

When a model is delivered as `.rar` or `.7z`, Step 2 wraps **each** file in its own `.zip` (e.g. `pack.rar` → `pack.zip` containing the RAR). Two RARs become two ZIPs, not one combined ZIP.
