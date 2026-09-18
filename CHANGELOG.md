# Changelog

## [2.0.6] — 2026-09-18

### Changed
- **The dashboard is now three numbered steps: connect, choose, download.**
  The old screen showed everything at once — four stat cards where three were
  the same readiness number, a "Workflow requirement check" panel that opened
  with nine red bullets about cookies and JWTs, a list of bash commands that
  nobody types now the app has buttons, and two sections that were already
  hidden and unreachable. Repair tools, diagnostics and duplicates moved into
  disclosures so they stay reachable without being in the way.
- Labels now say what they do: *Library / Listing / Creator filter* became
  *Everything I own / Only models I made / One creator only*, and
  *Execute Pipeline* became **Start download**.

### Fixed
- Status messages named buttons that no longer existed. One mattered: the model
  loader restored its label from a fallback of "Auto load my IDs", which
  overwrote the new "Load my models" text at runtime.
- The README walkthrough referred to the old button names throughout.

## [2.0.5] — 2026-09-13

### Fixed
- **A finished model could be silently stranded in staging.** Moving a completed
  model into the library can fail transiently on Windows when a virus scanner or
  sync client still holds the multi-GB archive written seconds earlier. The
  single attempt gave up and the run moved on, so the model never appeared in
  the library despite being downloaded, packaged and verified. Seen on a live
  605-model run: five models totalling ~13 GB, all of which moved without
  complaint when retried — and only large ones, consistent with a scanner
  holding the new file. The move now retries five times with doubling backoff
  (`MMF_FINALIZE_ATTEMPTS`, default 5), explains why it is waiting, and if it
  still cannot move the model says plainly that the work is safe in staging and
  the next run will finish it.

## [2.0.4] — 2026-09-11

### Fixed
- **macOS custom folder icons** were surviving expansion as fake entries. A
  zero-byte file named `Icon` plus a carriage return, whose real data lives in
  a resource fork; sanitising strips the CR so several from different folders
  collapsed onto `Icon`, `Icon_1`, `Icon_2`, `Icon_3`. Found by sweeping a
  finished 135-model library for suspiciously small entries — 8 models, 27
  entries. Same class as the `__MACOSX` forks fixed in 2.0.2.
- **A set-aside source is now put back when packing fails.** Moving a colliding
  source to a `__src_` name was not undone on the failure paths, so a run that
  set the file aside and then failed to pack left no file under the declared
  name — and the next run would re-download the model (4.7 GB in the case that
  exposed it). The rename is tracked and reversed by the same routine every
  failure path and the interrupt handler already call.

## [2.0.3] — 2026-09-11

### Fixed
- A model whose name matches its single declared file (e.g. *Nebula Starter
  Set* shipping `Nebula Starter Set.zip`) had its **downloaded source mistaken
  for a finished archive**, so packaging was skipped and the creator's raw zip
  was left in place — nested, names unsanitised, `__MACOSX` junk intact. 2 of
  135 models in a real library were affected. Completion is now decided by the
  archive's structure (flat, sanitised members) rather than its name, and a
  colliding source is moved aside before packing.

## [2.0.2] — 2026-09-11

### Fixed
- Flat archives were picking up **macOS resource forks as fake model files**.
  Creators who zip on macOS ship a parallel `__MACOSX/._filename` tree; the old
  nested layout hid it inside the creator's own `.zip`, but flattening exposed
  it, and sanitising strips the leading `._` so it collided with the real name
  and was saved as `<name>_1.stl`. A 178-byte metadata blob sat next to an 8 MB
  mesh looking like a legitimate file — on a live run, roughly half of every
  archive's entries were junk. Expansion now skips `__MACOSX/`, any `._` file,
  and `.DS_Store` / `Thumbs.db` / `desktop.ini`.

## [2.0.1] — 2026-09-11

### Fixed
- The pre-download scan that sizes the progress bar ran **silently for
  minutes** and looked like a freeze — over two and a half minutes on a
  135-model library with 10 already downloaded, growing worse as the library
  grows. It now announces itself, reports every 25 models, and is **7×
  faster** (153.4 s → 21.9 s), producing an identical work estimate.
  - The scan made roughly five `jq` calls per model, and `jq` costs ~88 ms to
    start on Windows. It now makes **one** pass over every metadata file
    (282 ms) and threads the results through.
  - It ran a full CRC verification of every archive already on disk purely to
    estimate work — 1,073 MiB of reads, 16.9 s. It now checks the ZIP
    signature instead (56 ms). The main loop still verifies properly before
    skipping any model, so an optimistic estimate can never skip a download.
  - Dropped a redundant HTML-error sniff (two process spawns per archive) and a
    subshell per model that only trimmed whitespace.
- The leftover-file sweep now removes `.headers` files as well as `.part`
  files. A hard kill (Stop in the desktop app) skips the cleanup handler and
  leaves both behind.

## [2.0.0] — 2026-09-11

Applies the findings from two full-library pulls (413 models, 175 GB, zero failed
downloads) recorded in `_tools/MMF_DOWNLOADER_FINDINGS.md`. **The on-disk archive
layout changes** — see *Breaking* below.

### Added
- **Whole-model download route.** Step 2 now tries `GET /download/<id>` first,
  which returns an entire model in **one request**, and only falls back to
  walking `files.items[]` when no generated archive exists. Request count — not
  delay — is what trips MyMiniFactory's limiter: one library tripped a Cloudflare
  challenge at model 52 on per-file fetches, then ran 102 models straight through
  on this route. Per-file fetching costs 3–4× the requests against the only
  endpoint that throttles. Disable with `MMF_WHOLE_MODEL_ROUTE=0`.
- The fetched whole-model archive is **verified against the API's file list**
  before it is trusted; a missing entry falls back to per-file downloads rather
  than shipping an incomplete model. (66 pre-existing archives were found to be
  missing a file or two versus the current API.)
- **Adaptive pacing.** `MMF_STL_FILE_DELAY_SEC` is now a floor, not a fixed rate.
  The live gap widens ×1.8 (capped, default 120 s) on every app-level throttle or
  Cloudflare cooldown, and narrows again only after a run of clean downloads. The
  limiter is not a published quota — one run needed ~68 s between requests while
  another did 233 models at a flat 12 s with zero throttles, so no hard-coded
  rate survives both. Tunable via `MMF_ADAPTIVE_DELAY_MAX_SEC`,
  `MMF_ADAPTIVE_WIDEN_PCT`, `MMF_ADAPTIVE_NARROW_PCT`,
  `MMF_ADAPTIVE_RECOVERY_STREAK`; disable with `MMF_ADAPTIVE_PACING=0`.
  The pipeline progress panel shows the current gap as it changes.
- **Stage, then move.** Each model is assembled under `.mmf_staging/` and renamed
  into the library only once its archive exists, so nothing walking the library
  ever sees a half-built model folder. Interrupted work stays in `.mmf_staging/`
  and is adopted by the next run, so resume remains free.
- **Interrupt cleanup.** Ctrl+C now runs a handler that puts staged files back
  and removes `.part` files instead of leaving them behind. A long run gets
  killed at least once.

### Breaking
- **Archive layout.** A model is now packaged as a single flat `<Slug>.zip`
  containing every file in `files.items`, with **nested `.zip` members expanded
  rather than nested** (expansion recurses; observed nesting runs two deep) and
  every member name sanitised. This replaces the previous layout, which left
  MMF-delivered `.zip` files standalone and wrapped each `.rar`/`.7z` in its own
  `.zip`. Existing folders are not rewritten — only newly downloaded models use
  the new layout.
- **Compression is now per-entry, not uniform.** Plain files are `STORED` so
  entry sizes still match the API's declared sizes exactly; anything expanded out
  of a `.zip` is `DEFLATED`, because storing already-compressed content raw
  inflated one 1,041 MB model to 1,852 MB.
- **Name sanitising deletes rather than substitutes.** `< > : " / \ | ? *` and
  the apostrophe are removed instead of becoming `_`; `& [ ] ( ) ! - .` are kept
  and whitespace runs still collapse to a single `_`. This matches the convention
  verified against 1,545 pre-existing folders. `4_rename_folders_from_json.sh`
  and `.ps1` were aligned to the same rule. Folders created by earlier versions
  are still found (a model id is matched against existing directories before a
  new name is minted), so an existing library is not duplicated.

### Fixed
- **`is_bought` is no longer described as an ownership test.** It is `false` for
  models the account can freely download — subscription and gift access never set
  it — so reporting "not in your library" was wrong. It is now reported as
  metadata only, and never gates a download.
- `is_bought` was also being read as `"unknown"` whenever it was genuinely
  `false`: jq's `//` operator treats `false` as absent, so `.is_bought // "unknown"`
  can never return `false` and the branch handling it was unreachable. Read with
  an explicit `has()` test instead.
- **Listings with zero files are no longer counted as failures.** Objects with
  images and a price but no downloadable files are ordinary (marketing renders,
  commercial licences, the occasional plain miniature — seven across two
  libraries); they get their own line in the summary instead of being pooled with
  models whose downloads actually failed.
- **A partial folder no longer masquerades as done.** Completion is decided by
  the presence of a valid archive, not by the directory having files in it — a
  folder of loose `.stl` files with no archive previously read as complete and
  kept a model out of the missing list.
- **A description is no longer overwritten with an empty one.** Metadata fetched
  without a live session returns `description: null`, and that degraded copy used
  to replace good text on the next run; the previous value is now kept when the
  incoming one is empty.
- `3_extract_all_zips.ps1` and `4_rename_folders_from_json.ps1` now use
  `-LiteralPath` throughout. PowerShell's `-Path` treats the value as a wildcard,
  so a library path containing `[PHASES]` or `[Modular]` matched nothing and the
  scripts reported success while silently skipping everything. (The Bash scripts
  were already safe — their globs quote the variable, which makes the brackets
  literal.)
- The whole-model route's fallback message deliberately avoids the phrase
  "HTTP 403", which the desktop app's session-expiry detector reads as proof the
  cookie died.

## [1.5.2] — 2026-09-09

### Fixed
- A Cloudflare **timed cooldown** (a rate-limit challenge page, HTTP 429/503, or a JS interstitial like "Just a moment...") was being misdiagnosed as a dead `cf_clearance` cookie: Step 1 and Step 2 would stop after a few failures and the desktop app would clear the saved session and ask you to sign in again — even though the same cookie worked again on its own minutes later, and hammering it with retries during the window only extended the cooldown.
- Steps 1 and 2 now distinguish **two** transient conditions that both look like a dead cookie but aren't, using the `cf-mitigated` response header as the authoritative signal (body-content sniffing as a fallback):
  - A real **Cloudflare edge challenge** (`cf-mitigated: challenge`) — waited out with an escalating 30 → 45 → 60 minute ladder.
  - MyMiniFactory's own **app-level throttle** (403/429/503 with no `cf-mitigated` header) — a separate, shorter condition, waited out with a 5 → 10 → 15 minute ladder. Retrying it quickly is what was escalating runs into a real Cloudflare lockout.
  Both reset their ladder after the next successful download. An app-throttle wait is capped at 6 attempts per item so a *genuinely* forbidden file (not a rate limit) still fails normally instead of retrying forever.
- The desktop app's "session expired" detector no longer treats the word "Cloudflare" in run output as proof the session died — it only fires on unambiguous signals (missing `cf_clearance`, logged out, HTTP 401/403, etc.), so a cooldown wait is no longer mistaken for an expired session and no longer clears your saved cookie mid-run.
- The pipeline progress panel now shows which kind of cooldown is being waited out ("Waiting out Cloudflare cooldown" vs. "Waiting out app-level throttle") with the remaining wait, so an unattended run doesn't look stuck.
- `curl`'s own `--retry` (default 2, ~2s apart) was silently re-hitting the server on HTTP 429/503 before the cooldown handling above ever saw the failure — itself the kind of rapid retry that extends a cooldown. `MMF_CURL_RETRIES` / `MMF_METADATA_CURL_RETRIES` now default to 0 so the cooldown wait is what actually runs; override those env vars if you want `curl` to also retry plain transient network errors.

See `_tools/MMF_DOWNLOADER_FINDINGS.md` for the real-world run that informed this design.

## [1.5.1] — 2026-06-08

### Fixed
- Step 2 no longer reports **“No space left on device”** when `df` shows plenty of free space. `curl` exit 23 and save/rename failures are now labeled **“Could not write download to disk”** with troubleshooting hints (antivirus, synced folders, permissions, long paths).
- Step 2 normalizes **Greek/Cyrillic homoglyphs** in file and folder names (e.g. MMF Roman numerals like `XXIΙ` → `XXII`) so Windows/Git Bash writes succeed more reliably.
- Step 2 keeps sanitized filename collisions as separate downloads (e.g. `XXII.rar` and homoglyph `XXIΙ.rar`) instead of incorrectly skipping the later file.
- Clearer log when a file downloads (HTTP 200) but **cannot be saved** to the final path (rename/move failure).

### Notes
- Steps 1–2 run as Bash scripts. On Windows, install **Git for Windows** (Git Bash). Perl is included with Git Bash (`usr/bin/perl`) and is used for filename homoglyph normalization; no separate Perl install is required.

## [1.5.0] — 2026-05-28

### Added
- **Bundled Info-ZIP for Windows** (`tools/zip.exe`): Step 2 packaging works without MiKTeX, Explorer, or `pacman -S zip`. Included in `npm run dist:win` via `npm run vendor:zip`.
- **Optional categories for download:** no category selection required; compact model JSON uses `categories: []` when empty. Categorize per model in your upload tool instead of one global batch label.
- **Per-file RAR/7z ZIP wrappers:** each `.rar`/`.7z` becomes its own `.zip` (`pack.rar` → `pack.zip`); multiple archives yield multiple ZIPs, not one combined archive.

### Changed
- Step 2 ZIP failures emit **`[ZIP-DIAG]`** logs (tool paths, stderr, validation). Removed misleading `tar`→`.zip` fallback; prefers bundled/Git `zip` over MiKTeX in PATH.

## [1.4.1] — 2026-05-22

### Added
- **Manual retry IDs** in the desktop UI (below Auto load source): paste failed model IDs, click **Load manual IDs** (enabled only when at least one valid ID is present). Replaces the visible list for a targeted batch run, unmarks those IDs from batch completed progress, and keeps cached catalog names from prior auto-loads. Step 2 still skips files already on disk in the same download folder.

### Fixed
- Step 2 no longer uses `xargs` for trimming parsed model/file/image fields; apostrophes in model names and URLs no longer trigger `xargs: unmatched single quote` errors.
- Image URL parsing now preserves quoted/special characters correctly, preventing `curl: (3) URL rejected: Malformed input to a URL function` failures on valid MMF image links.
- Archive base-name parsing now safely handles quoted model names, avoiding false ZIP creation failures tied to broken trim parsing.
- Added URL hardening before every curl request in Step 2: trim CR/LF, remove control characters, encode unsafe URL characters, preserve query params, and reject invalid/empty URLs early.
- Added URL diagnostics for malformed-link failures: logs original URL, sanitized URL, and the exact sanitization adjustments when a URL is changed or curl exits with code 3.
- Hardened `sanitize_filename` and `sanitize_folder_name` to normalize unsafe/special characters, remove control chars, collapse whitespace, and avoid trailing dot/space or underscore-only names.
- ZIP input collection now uses null-delimited reads for safer filename handling, and ZIP failures now log archive path, zip exit code, and the file list used during archive creation.
- Step 2 ZIP packaging hardening: skip outer wrap when MMF already delivered valid standalone ZIP(s) (e.g. Supports + Unsupported packs); require free disk space based on payload size; compress via `zip -@` and batched `zip -g` fallback; store-only mode (`-0`) for large STL sets; capture zip stderr in logs; fall back to `tar` when `zip` fails.
- Step 2 disk planning from MMF metadata `files.items[].size` (bytes or string): per-model and per-file free-space checks with `[DISK]` logs; unknown sizes estimated from known file averages (Kraken-style metadata); `[ZIP-WARN]` when payload exceeds 4 GiB; automatic Zip64 (`zip -fz`) for payloads over ~3.3 GiB when supported (no extra dependency).

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
