# MyMiniFactory - Mass ZIP Extraction Script
# Extracts all ZIP files in all model subdirectories
# WINDOWS ONLY - Requires PowerShell 5.0+
#
# This is OPTIONAL Step 3 - run after downloading STL/ZIP files
#
# Prerequisites:
# - Completed Steps 1 & 2 (metadata and STL downloads)
# - PowerShell execution policy allows scripts
# - Close any Windows Explorer windows viewing the files
#
# Usage:
# 1. Update $BASE_PATH variable below to point to your stl_files directory
# 2. Choose extraction mode (in-place or separate folders)
# 3. Run: .\extract_all_zips.ps1

# ============================================================================
# CONFIGURATION - UPDATE THIS PATH TO YOUR stl_files DIRECTORY
# ============================================================================
# Example Windows paths:
# $BASE_PATH = "C:\Users\YourName\Downloads\MyMiniFactory\downloads\stl_files"
# $BASE_PATH = "D:\3D Printing\MMF Downloads\downloads\stl_files"
$BASE_PATH = if ($env:MMF_BASE_PATH) { $env:MMF_BASE_PATH } else { "PATH\TO\YOUR\downloads\stl_files" }

# Choose extraction mode:
# $EXTRACT_IN_PLACE = $true   -> Extract directly into model folders alongside zips
# $EXTRACT_IN_PLACE = $false  -> Create separate "_extracted" subdirectories
$EXTRACT_IN_PLACE = if ($env:MMF_EXTRACT_IN_PLACE) {
    $env:MMF_EXTRACT_IN_PLACE -match '^(?i:true|1|yes)$'
} else {
    $true
}
# ============================================================================

Write-Host "MyMiniFactory ZIP Extraction Tool" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan
Write-Host ""

# Validate base path exists
if (-not (Test-Path -LiteralPath $BASE_PATH)) {
    Write-Host "ERROR: Base path does not exist: $BASE_PATH" -ForegroundColor Red
    Write-Host "Please update the `$BASE_PATH variable in this script to point to your stl_files directory" -ForegroundColor Yellow
    exit 1
}

# Navigate to base directory
Set-Location -LiteralPath $BASE_PATH

# Find all ZIP files recursively
$zipFiles = Get-ChildItem -Recurse -Filter "*.zip"
$totalFiles = $zipFiles.Count

if ($totalFiles -eq 0) {
    Write-Host "No ZIP files found in $BASE_PATH" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $totalFiles ZIP files to extract" -ForegroundColor Green
Write-Host "Extraction mode: $(if ($EXTRACT_IN_PLACE) { 'In-place' } else { 'Separate folders' })" -ForegroundColor Cyan
Write-Host ""

function Test-ZipEntrySafe {
    param(
        [string]$EntryName,
        [string]$DestinationRoot
    )

    if ([string]::IsNullOrWhiteSpace($EntryName)) {
        return $false
    }

    if ($EntryName -match '\.\.' -or $EntryName -match '^[/\\]' -or $EntryName -match '^[a-zA-Z]:') {
        return $false
    }

    $normalizedEntry = $EntryName -replace '\\', '/'
    $destinationFile = Join-Path $DestinationRoot $normalizedEntry
    $resolvedDestination = [System.IO.Path]::GetFullPath($destinationFile)
    $resolvedRoot = [System.IO.Path]::GetFullPath($DestinationRoot)

    return $resolvedDestination.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)
}

function Expand-ZipSafely {
    param(
        [string]$ZipPath,
        [string]$Destination
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)

    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName.EndsWith('/')) {
                continue
            }

            if (-not (Test-ZipEntrySafe -EntryName $entry.FullName -DestinationRoot $Destination)) {
                throw "Unsafe zip entry blocked: $($entry.FullName)"
            }

            $destinationFile = Join-Path $Destination ($entry.FullName -replace '\\', '/')
            $destinationDir = Split-Path $destinationFile -Parent
            if (-not (Test-Path -LiteralPath $destinationDir)) {
                New-Item -ItemType Directory -LiteralPath $destinationDir -Force | Out-Null
            }

            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destinationFile, $true)
        }
    } finally {
        $archive.Dispose()
    }
}

$current = 0
$successful = 0
$failed = 0

foreach ($zip in $zipFiles) {
    $current++
    $percentComplete = [math]::Round(($current / $totalFiles) * 100, 1)
    
    Write-Host "[$current/$totalFiles - $percentComplete%] Extracting: $($zip.Name)" -ForegroundColor Cyan
    
    try {
        if ($EXTRACT_IN_PLACE) {
            # Extract directly into the same directory as the ZIP
            $destination = $zip.DirectoryName
        } else {
            # Create a separate extraction folder
            $extractFolderName = $zip.BaseName + "_extracted"
            $destination = Join-Path $zip.DirectoryName $extractFolderName
            
            # Create extraction directory if it doesn't exist
            if (-not (Test-Path -LiteralPath $destination)) {
                New-Item -ItemType Directory -LiteralPath $destination -Force | Out-Null
            }
        }
        
        Expand-ZipSafely -ZipPath $zip.FullName -Destination $destination
        
        Write-Host "  [OK] Extracted to: $destination" -ForegroundColor Green
        $successful++
        
    } catch {
        Write-Host "  [FAIL] Failed: $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "Extraction Complete!" -ForegroundColor Green
Write-Host "===================" -ForegroundColor Green
Write-Host "Successfully extracted: $successful files" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "Failed: $failed files" -ForegroundColor Red
}
Write-Host ""

# Optionally show summary of what was extracted
Write-Host "Sample of extracted directories:" -ForegroundColor Cyan
Get-ChildItem -Directory | Select-Object -First 5 | ForEach-Object {
    $fileCount = (Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Measure-Object).Count
    Write-Host "  $($_.Name): $fileCount files" -ForegroundColor Gray
}

# Common Issues and Solutions:
#
# 1. "Base path does not exist" - Update $BASE_PATH to your actual stl_files directory path
# 2. "Access denied" or extraction fails - Close Windows Explorer windows viewing those folders
# 3. Script won't run - Run: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
# 4. Slow extraction - Large files (100MB+) take time, this is normal
# 5. Out of disk space - Check free space, each model can be 200MB+ extracted
#
# Tips:
# - Use in-place extraction ($EXTRACT_IN_PLACE = $true) to keep things organized
# - Close all Explorer windows before running to avoid file lock issues
# - Extraction can take 10-30 minutes depending on file count and sizes
# - You can delete the ZIP files after successful extraction to save space
# - STL files are typically in the extracted folders, ready for slicing software