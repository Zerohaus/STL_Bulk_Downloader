# English Dashboard

This folder contains the renderer UI used by the desktop app.

## Desktop behavior

When launched as the Electron app, the UI starts with a dependency gate:

1. Runs dependency checks for Bash, curl, jq, PowerShell, and winget.
2. Shows missing dependencies.
3. Lets the user choose:
	- Install missing dependencies
	- Continue without install
4. Re-checks after installation.

Auto-install uses:

- `winget` on Windows
- `brew` on macOS

After dependency checks, the dashboard can execute workflow steps directly:

- Start download (Step 1 -> Step 2 Test -> Step 2 Full)
- Run Step 1
- Run Step 2 Test
- Run Step 2 Full
- Run Step 3 (optional)
- Run Step 4 (optional)
- Stop active run

The run log view shows live stdout/stderr output from each script process.

Cookie input is persisted locally and reused until an expiration/authentication error is detected.

## Browser mode

You can still open `gui/index.html` directly in a browser for preview. In that mode:

- Startup dependency installation is disabled.
- Workflow validation (cookie + IDs) still works.

## Workflow checks in the UI

- Cookie exists
- Cookie includes `PHPSESSID`
- Cookie includes `cf_clearance`
- At least one model ID is present
- All non-empty lines are numeric IDs
- Duplicate IDs warning
- Test-mode acknowledgment for enhanced Step 2

## Script workflow reflected in the UI

From repository root:

```bash
bash 1_mmf_download_metadata.sh
```

Then from `downloads`:

```bash
bash ../mmf_download_stl_files_enhanced.sh --test
bash ../mmf_download_stl_files_enhanced.sh
```

Optional Windows scripts:

```powershell
powershell -ExecutionPolicy Bypass -File .\3_extract_all_zips.ps1
powershell -ExecutionPolicy Bypass -File .\4_rename_folders_from_json.ps1
```