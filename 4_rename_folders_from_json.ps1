# MyMiniFactory - Intelligent Folder Renaming Script
# Renames model_XXXXXX folders to include actual model names from JSON metadata
# WINDOWS ONLY - Requires PowerShell 5.0+
#
# This is OPTIONAL Step 4 - run after downloading files and optionally extracting
#
# Prerequisites:
# - Completed Steps 1 & 2 (must have JSON metadata files)
# - model_XXXXXX folders exist in stl_files directory
# - Close any Windows Explorer windows viewing these folders
#
# Usage:
# 1. Update $JSON_PATH and $FOLDERS_PATH variables below
# 2. Customize naming format if desired
# 3. Run: .\rename_folders_from_json.ps1

# ============================================================================
# CONFIGURATION - UPDATE THESE PATHS TO YOUR DIRECTORY STRUCTURE
# ============================================================================
# Path to directory containing model_*.json files (usually 'downloads')
# Example: "C:\Users\YourName\Downloads\MyMiniFactory\downloads"
$JSON_PATH = if ($env:MMF_JSON_PATH) { $env:MMF_JSON_PATH } else { "PATH\TO\YOUR\downloads" }

# Path to directory containing model_XXXXXX folders to rename (usually 'downloads\stl_files')
# Example: "C:\Users\YourName\Downloads\MyMiniFactory\downloads\stl_files"
$FOLDERS_PATH = if ($env:MMF_FOLDERS_PATH) { $env:MMF_FOLDERS_PATH } else { "PATH\TO\YOUR\downloads\stl_files" }

# Naming format options:
# Format: How to construct the new folder name
# Options: "ID_NAME" (e.g., 409352_Crystal_Clusters) or "NAME_ONLY" (e.g., Crystal_Clusters)
$NAMING_FORMAT = if ($env:MMF_NAMING_FORMAT) { $env:MMF_NAMING_FORMAT } else { "ID_NAME" }

# Maximum name length (to avoid Windows path limits)
$MAX_NAME_LENGTH = if ($env:MMF_MAX_NAME_LENGTH) {
    [Math]::Max(10, [Math]::Min(160, [int]$env:MMF_MAX_NAME_LENGTH))
} else {
    80
}
# ============================================================================

Write-Host "MyMiniFactory Folder Renaming Tool" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

# Validate paths exist
if (-not (Test-Path -LiteralPath $JSON_PATH)) {
    Write-Host "ERROR: JSON path does not exist: $JSON_PATH" -ForegroundColor Red
    Write-Host "Update `$JSON_PATH to point to your 'downloads' directory containing model_*.json files" -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path -LiteralPath $FOLDERS_PATH)) {
    Write-Host "ERROR: Folders path does not exist: $FOLDERS_PATH" -ForegroundColor Red
    Write-Host "Update `$FOLDERS_PATH to point to your 'stl_files' directory containing model_* folders" -ForegroundColor Yellow
    exit 1
}

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  JSON files location: $JSON_PATH" -ForegroundColor Gray
Write-Host "  Folders location: $FOLDERS_PATH" -ForegroundColor Gray
Write-Host "  Naming format: $NAMING_FORMAT" -ForegroundColor Gray
Write-Host "  Max name length: $MAX_NAME_LENGTH characters" -ForegroundColor Gray
Write-Host ""

$renamed = 0
$failed = 0
$skipped = 0

# Get all JSON files
$jsonFiles = Get-ChildItem -LiteralPath $JSON_PATH -Filter "model_*.json"
$totalFiles = $jsonFiles.Count

if ($totalFiles -eq 0) {
    Write-Host "ERROR: No model_*.json files found in $JSON_PATH" -ForegroundColor Red
    Write-Host "Make sure you've run the metadata downloader (Step 1) first" -ForegroundColor Yellow
    exit 1
}

Write-Host "Found $totalFiles JSON files to process" -ForegroundColor Green
Write-Host ""

$current = 0

foreach ($jsonFile in $jsonFiles) {
    $current++
    $modelId = $jsonFile.BaseName -replace "model_", ""
    
    try {
        # Read and parse JSON
        $json = Get-Content -LiteralPath $jsonFile.FullName -Raw | ConvertFrom-Json
        $modelName = $json.name
        
        if (-not $modelName) {
            Write-Host "[$current/$totalFiles] Model $modelId - No name found in JSON, skipping" -ForegroundColor Yellow
            $skipped++
            continue
        }
        
        # Clean up the name for use as folder name
        # Remove invalid Windows filename characters: < > : " / \ | ? *
        # Reserved characters and the apostrophe are DELETED, not replaced --
        # the convention verified against 1,545 existing folders keeps
        # & [ ] ( ) ! - . and collapses only whitespace into underscores.
        $cleanName = $modelName -replace '[<>:"/\\|?*]', '' -replace "'", ''
        # Replace multiple spaces with single space, then spaces with underscores
        $cleanName = $cleanName -replace '\s+', ' ' -replace ' ', '_'
        # Replace multiple underscores with single underscore
        $cleanName = $cleanName -replace '_+', '_'
        # Remove leading/trailing underscores
        $cleanName = $cleanName.Trim('_')
        
        # Limit length to avoid Windows path issues
        if ($cleanName.Length -gt $MAX_NAME_LENGTH) {
            $cleanName = $cleanName.Substring(0, $MAX_NAME_LENGTH).Trim('_')
        }
        
        # Construct new folder name based on format preference
        if ($NAMING_FORMAT -eq "ID_NAME") {
            $newFolderName = "${modelId}_${cleanName}"
        } else {
            $newFolderName = $cleanName
        }
        
        $oldFolder = Join-Path $FOLDERS_PATH "model_$modelId"
        $newFolder = Join-Path $FOLDERS_PATH $newFolderName
        
        # Check if source folder exists
        if (-not (Test-Path -LiteralPath $oldFolder)) {
            Write-Host "[$current/$totalFiles] Model $modelId - Folder not found, skipping" -ForegroundColor Yellow
            $skipped++
            continue
        }
        
        # Check if target already exists (avoid conflicts)
        if (Test-Path -LiteralPath $newFolder) {
            Write-Host "[$current/$totalFiles] Model $modelId - Target folder already exists: $newFolderName" -ForegroundColor Yellow
            $skipped++
            continue
        }
        
        # Attempt rename
        Write-Host "[$current/$totalFiles] Renaming: model_$modelId -> $newFolderName" -ForegroundColor Cyan
        Rename-Item -LiteralPath $oldFolder -NewName $newFolderName -ErrorAction Stop
        Write-Host "  [OK] Success" -ForegroundColor Green
        $renamed++
        
    } catch {
        Write-Host "[$current/$totalFiles] Model $modelId - ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $failed++
        
        # Provide specific help for common errors
        if ($_.Exception.Message -like "*path or device name*") {
            Write-Host "  -> TIP: Close any Windows Explorer windows viewing this folder and try again" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "Renaming Complete!" -ForegroundColor Green
Write-Host "==================" -ForegroundColor Green
Write-Host "Successfully renamed: $renamed folders" -ForegroundColor Green
if ($skipped -gt 0) {
    Write-Host "Skipped: $skipped folders (missing, no name, or conflicts)" -ForegroundColor Yellow
}
if ($failed -gt 0) {
    Write-Host "Failed: $failed folders (see errors above)" -ForegroundColor Red
}
Write-Host ""

# Show sample of renamed folders
Write-Host "Sample of renamed folders:" -ForegroundColor Cyan
Get-ChildItem -LiteralPath $FOLDERS_PATH -Directory | 
    Where-Object { $_.Name -notlike "model_*" } |
    Select-Object -First 10 | 
    ForEach-Object {
        Write-Host "  $($_.Name)" -ForegroundColor Gray
    }

# Common Issues and Solutions:
#
# 1. "JSON path does not exist" - Update $JSON_PATH to your 'downloads' directory path
# 2. "Folders path does not exist" - Update $FOLDERS_PATH to your 'stl_files' directory path
# 3. "Cannot rename... path or device name" - Close Windows Explorer windows, wait a moment, try again
# 4. "Target folder already exists" - Another folder has the same name, script skips to avoid conflicts
# 5. "No JSON files found" - Make sure you ran the metadata downloader (Step 1) first
# 6. All folders skipped - Check that JSON files and model folders are in the correct paths
#
# Tips:
# - Close ALL Windows Explorer windows before running to avoid lock issues
# - Use ID_NAME format (default) to keep unique identifiers and avoid name conflicts
# - NAME_ONLY format is cleaner but may have duplicates if model names aren't unique
# - Script is safe - it never overwrites existing folders
# - You can run multiple times; already-renamed folders will be skipped
# - Names are cleaned automatically: special characters -> underscores, length limited
# - Useful for browsing your library without needing to look up model IDs