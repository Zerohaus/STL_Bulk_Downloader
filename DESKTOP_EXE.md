# Desktop EXE Guide

This project includes an Electron desktop app that packages the existing scripts and GUI for Windows and macOS.

## What the EXE does on startup

1. Opens a dependency gate before the main dashboard is usable.
2. Checks for required tools:
   - Bash (Git Bash on Windows)
   - curl
   - jq
3. Uses Perl from the Git Bash install for Step 2 filename normalization (no separate Perl install; `usr/bin/perl` ships with Git for Windows).
4. Checks optional tools:
   - PowerShell (Windows)
   - winget (Windows) / Homebrew (macOS)
5. Lets the user choose:
   - Install missing dependencies (via winget on Windows, brew on macOS)
   - Continue without install

## Run workflow steps from the GUI

The desktop dashboard now executes the real scripts with live logs:

1. Execute Pipeline (Step 1 -> Step 2 Test -> Step 2 Full)
1. Run Step 1
2. Run Step 2 Test
3. Run Step 2 Full
4. Run Step 3 (optional)
5. Run Step 4 (optional)
6. Stop active run

Step 3 and Step 4 execution mode:

- Windows: runs `3_extract_all_zips.ps1` and `4_rename_folders_from_json.ps1`
- macOS/Linux: runs `3_extract_all_zips.sh` and `4_rename_folders_from_json.sh`

The run log panel streams stdout and stderr from the process in real time.

## Session (v1.1)

- **Open MyMiniFactory** opens login or your profile if already signed in.
- **Capture session** saves cookie, JWT, and publishable key (encrypted when OS keychain is available).
- **Check session** validates against Medusa `/store/customers/me`.
- On auth failure during Step 1/2, the full session is cleared; re-capture and re-run (downloads resume, skipping existing files).

## Cookie persistence behavior

- Credentials are saved in `desktop-settings.json` under AppData (encrypted secrets when possible).
- Reused between launches until expiry or manual clear.

The app passes configuration to scripts via environment variables:

- `MMF_COOKIE`
- `MMF_BASE_PATH`
- `MMF_EXTRACT_IN_PLACE`
- `MMF_JSON_PATH`
- `MMF_FOLDERS_PATH`
- `MMF_NAMING_FORMAT`
- `MMF_MAX_NAME_LENGTH`

## Local development

From repository root:

```powershell
npm install
npm start
```

## Build Windows installer (.exe)

From repository root:

```powershell
npm run dist:win
```

Output installer path:

- `dist\Bulk Downloader Setup 2.0.4.exe`

## Build macOS packages

From repository root:

```bash
npm run dist:mac
```

Typical outputs in `dist`:

- `*.dmg`
- `*.zip`

Note: macOS artifacts must be built on a macOS machine.

## Branding assets

- App and installer icon: `build/icon.ico`
- Source image: `build/icon.png`

## Notes about dependency installation

- Automatic install requires `winget` on Windows or `brew` on macOS.
- If installer tooling is missing, the app allows continue without install.
- Install commands can trigger UAC prompts depending on package and policy.

## Post-processing scripts

- Windows scripts:
   - `3_extract_all_zips.ps1`
   - `4_rename_folders_from_json.ps1`
- Cross-platform scripts:
   - `3_extract_all_zips.sh`
   - `4_rename_folders_from_json.sh`

## Runtime files

- Electron main process: `electron/main.js`
- Preload bridge: `electron/preload.js`
- UI renderer: `gui/index.html`, `gui/app.js`, `gui/styles.css`

## Building on Windows without Developer Mode

`npm run dist:win` may fail while unpacking electron-builder's code-signing
toolchain:

```
ERROR: Cannot create symbolic link : A required privilege is not held by the
client. : ...\winCodeSign\<id>\darwin\10.12\lib\libcrypto.dylib
```

That archive contains macOS symlinks, and creating a symlink on Windows needs
elevated rights. The two files are macOS libraries and play no part in a
Windows build, but the failed extraction aborts the build.

Two ways round it:

- **Enable Developer Mode** (Settings → Privacy & security → For developers).
  This grants symlink privileges and is the proper fix — `npm run dist:win`
  then works unchanged.
- **Skip executable editing** for a one-off build:

  ```
  npx electron-builder --win nsis portable -c.win.signAndEditExecutable=false
  ```

  The installers build, but the bundled app executable keeps Electron's default
  icon and version metadata, because that step is what stamps them. The NSIS
  installer's own icon comes from `nsis.installerIcon` and is unaffected.

Neither path code-signs anything — there is no certificate in this repo — so
SmartScreen will warn on first run either way.
