# Changelog

## [1.4.1] — 2026-05-22

### Fixed
- Step 2 no longer uses `xargs` for trimming parsed model/file/image fields; apostrophes in model names and URLs no longer trigger `xargs: unmatched single quote` errors.
- Image URL parsing now preserves quoted/special characters correctly, preventing `curl: (3) URL rejected: Malformed input to a URL function` failures on valid MMF image links.
- Archive base-name parsing now safely handles quoted model names, avoiding false ZIP creation failures tied to broken trim parsing.
- Added URL hardening before every curl request in Step 2: trim CR/LF, remove control characters, encode unsafe URL characters, preserve query params, and reject invalid/empty URLs early.
- Added URL diagnostics for malformed-link failures: logs original URL, sanitized URL, and the exact sanitization adjustments when a URL is changed or curl exits with code 3.
- Hardened `sanitize_filename` and `sanitize_folder_name` to normalize unsafe/special characters, remove control chars, collapse whitespace, and avoid trailing dot/space or underscore-only names.
- ZIP input collection now uses null-delimited reads for safer filename handling, and ZIP failures now log archive path, zip exit code, and the file list used during archive creation.

## [1.4.0] — 2026-05-21

### Added
- **Batch size 10** option in the desktop UI (alongside 25, 50, 100, and all pending).
- **Pipeline progress panel** below Execute Pipeline / Download Next Batch: percentage bar plus phase labels for metadata download and Step 2 packaging.
- Structured **`MMF_PROGRESS`** JSON events from Step 1 and Step 2 (enabled via `MMF_EMIT_PROGRESS=1` from the desktop app) for accurate UI updates instead of parsing colored log text alone.
- **Step 2 batch filter** (`MMF_MODEL_IDS_FILTER`): automatic pipeline passes the current batch IDs so Step 2 can limit processing to that batch when the filter is set.
- Per-model **live “completed” row styling** during a run (ZIP-ready), before the batch is written to persisted progress.
- **Saved download folders**: missing paths are removed from history when Open reports they do not exist.

### Changed
- Model list pagination set to **20 rows per page**; the ID / Model and creator table keeps a **5-row scroll viewport** to save vertical space.
- **Open folder** allowed roots now include every path in `downloadRootHistory`, not only the active Download folder and post-process paths.
- **Remove** on model list rows is disabled while a workflow step or batch pipeline is running.

### Fixed
- Completed models stayed unhighlighted until changing list page; the list now refreshes when batch progress updates and when each model finishes packaging.
- **“Path is outside the allowed download workspace”** when opening a folder from saved history that was not the current Download folder root.

## [1.3.0] — 2026-05-20

### Added
- New **Creator** catalog mode with creator ID filter in the desktop UI and backend catalog resolution.
- Creator metadata propagation end-to-end (`creatorId`, `creatorName`, `creatorUsername`) and rendering in model list rows.
- Category taxonomy support from `gui/categories-taxonomy.json` with category + subcategory multi-select rules.
- Category selection summary in the UI and export of selected categories into compact model JSON.
- Collapsible categories/subcategories section to reduce scroll fatigue.
- Download hardening in Step 1 and Step 2: atomic `.part` writes, proactive free-space checks, and explicit `curl` write-error handling.
- ZIP integrity validation path (when `unzip`/`zip` tools are available) before accepting archives as valid.
- Automatic cleanup of orphan `.part` files at startup in Step 1 and Step 2.
- Windows permission preflight for workflow steps with optional UAC relaunch as Administrator when write access is blocked.
- Compatibility wrapper in `2_mmf_download_stl_files.sh` delegating execution to `mmf_download_stl_files_enhanced.sh`.
- `.gitattributes` policy to keep Bash scripts on LF line endings.

### Changed
- Step 1 now writes runtime `model_ids.txt` into app user data (`workflow-temp`) instead of script root to reduce permission failures.
- Default minimum free-space thresholds were raised:
  - Step 1: `MMF_METADATA_MIN_FREE_MB=512`
  - Step 2: `MMF_MIN_FREE_SPACE_MB=2048`

### Fixed
- Resume behavior now discards invalid/truncated previously downloaded files and re-downloads safely.
- Better handling for low-disk and restricted-folder scenarios that previously caused silent partial outputs.

## [1.2.0] — 2026-05-19

### Added
- **Catalog load modes** (two options, both from `objectPreviews`):
  - **Listing** — models you created (`creatorId` matches your account).
  - **Library** — full data library (creations, purchases, gifts, tribes, downloads).
- Large-library catalog handling: up to 64 MB JSON response, 3-minute timeout, in-memory parsing in 400-entry chunks (UI stays responsive).
- **Resume by assets ZIP**: if a valid model archive ZIP already exists in the output folder, Step 2 skips STL/ZIP re-download for that model.
- **Readable output folders** in Step 2: `{id}_{model_name}` by default (e.g. `228967_Kell_Ombis`); respects GUI `NAMING_FORMAT` / `MAX_NAME_LENGTH`. Legacy `model_<id>` folders still work on resume.
- Card-style **Auto load source** selector in the UI.
- Catalog auto-load after **Capture session** runs silently when the model list is empty (no extra confirm dialogs).

### Fixed
- Step 2 re-downloading files after a prior run: canonical path check before `unique_output_path` (avoids `file_1.zip`, `file_2.zip` duplicates).
- Image downloads now skip existing valid files the same way as STL/ZIP.
- Cross-run idempotency when switching between Listing and Library into the same download folder (metadata JSON skip + file/ZIP skip).

### Changed
- Removed store-API-only “listing” path; Listing and Library both use `objectPreviews` with different filters.
- Step 2 receives `MMF_NAMING_FORMAT` and `MMF_MAX_NAME_LENGTH` from the desktop app (aligned with Step 4 rename settings).

## [1.1.0] — 2026-05-19

### Added
- Embedded MyMiniFactory sign-in window with **Capture session** (cookies + JWT + publishable key).
- **Check session** validation against Medusa API; session badge in the UI.
- Paginated catalog load via store API (25 items per request) with `objectPreviews` merge when applicable.
- Model list with ID + name, UI pagination (25 rows per page), remove per row.
- Auto-load catalog after successful session capture when the list is empty.
- Resume-safe downloads: skip existing metadata JSON and already-downloaded STL/ZIP files.
- Encrypted credential storage (OS keychain when available), password fields, Electron sandbox.
- Zip-slip protection on extraction; restricted “open folder” paths.

### Changed
- Application display name: **Bulk Downloader** (installer, window title, UI).
- Conservative rate limits: 6s metadata, 5s STL/ZIP, 3s images, 1s between catalog pages.
- Electron 33.x (from 31.x).
- Manual model ID input removed; catalog comes from Auto load or saved list.

### Security
- Settings file chmod 600; full session cleared on auth failure during runs.

## [1.0.0]
- Initial desktop app with workflow scripts and dependency bootstrapper.
