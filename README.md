# Bulk Downloader

**Desktop v1.5.1** — see [README-DESKTOP.md](README-DESKTOP.md) for the current GUI workflow, [CHANGELOG.md](CHANGELOG.md) for release notes, [DESKTOP_EXE.md](DESKTOP_EXE.md) to build the installer.

---

Legacy script-focused notes below (CLI). Desktop app is the recommended path.

Desktop EXE build and startup dependency flow: see DESKTOP_EXE.md

README.md - Full workflow explanation
1_mmf_download_metadata.sh - Get JSON metadata
2_mmf_download_stl_files.sh - Get actual files

Key features both scripts have:

✅ Windows line ending fixes (automatic)
✅ Cookie authentication handling
✅ Rate limiting to be respectful to servers
✅ Clear error messages and progress tracking
✅ Comprehensive troubleshooting documentation

Script 2 specifically includes:

✅ Redirect following with -L flag (critical fix)
✅ URL cleaning to handle Windows corruption
✅ jq path detection for cross-platform compatibility

BONUS EXTRACTION AND RENAMING SCRIPTS (CROSS-PLATFORM)

Windows versions:
3_extract_all_zips.ps1 - [BONUS] Windows mass extraction
4_rename_folders_from_json.ps1 - [BONUS] Intelligent renaming

macOS/Linux versions:
3_extract_all_zips.sh - [BONUS] Cross-platform mass extraction
4_rename_folders_from_json.sh - [BONUS] Cross-platform intelligent renaming

	What Users Need to Update:
	Extract Script (extract_all_zips.ps1):

	$BASE_PATH - Path to their stl_files directory
	$EXTRACT_IN_PLACE - Choose extraction mode (true/false)

	Rename Script (rename_folders_from_json.ps1):

	$JSON_PATH - Path to directory with JSON files (usually downloads)
	$FOLDERS_PATH - Path to stl_files directory with model folders
	$NAMING_FORMAT - Choose "ID_NAME" or "NAME_ONLY" style
	$MAX_NAME_LENGTH - Customize if needed

Both scripts include:
✅ Clear "UPDATE THIS" sections at the top with example paths
✅ Path validation with helpful error messages if wrong
✅ All the fixes we discovered (Explorer locks, filename cleaning, etc.)
✅ Progress tracking and summary statistics
✅ Comprehensive troubleshooting sections based on our debugging
✅ Safe operation - won't overwrite or damage existing data