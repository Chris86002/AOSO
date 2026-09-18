# AOSO Updater
# Syncs the local kOS AOSO folder with the latest commit on GitHub.
# Repository: https://github.com/Chris86002/AOSO
#
# Usage:
#   Double-click Update-AOSO.bat
#   or: powershell -NoProfile -ExecutionPolicy Bypass -File .\Update-AOSO.ps1
#
# If KSP is not in the default Steam folder, create kos-root.txt next to this
# script and put the full path to your kOS Script folder on the first line.
# Example:
#   C:\Program Files (x86)\Steam\steamapps\common\Kerbal Space Program\Ships\Script

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# GitHub requires TLS 1.2. Windows PowerShell 5.1 may still default to older TLS.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
}

$RepoOwner = "Chris86002"
$RepoName  = "AOSO"
$Branch    = "main"

$UserAgent = "AOSO-Updater"
$GitHubHeaders = @{
    "User-Agent"           = $UserAgent
    "Accept"               = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

# Files the player may keep next to AOSO that the repo does not ship.
$PreserveNames = @(
    "mission_plan.ks",
    ".aoso-version"
)

function Get-GitHubJson {
    param(
        [Parameter(Mandatory = $true)][string]$Url
    )

    Invoke-RestMethod -Uri $Url -Headers $GitHubHeaders -Method Get
}

function Get-KosScriptFolder {
    $overrideFile = Join-Path $PSScriptRoot "kos-root.txt"
    if (Test-Path -LiteralPath $overrideFile) {
        $fromFile = (Get-Content -LiteralPath $overrideFile -TotalCount 1).Trim().Trim('"')
        if ($fromFile) { return $fromFile }
    }

    if ($env:AOSO_KOS_ROOT) {
        return $env:AOSO_KOS_ROOT.Trim()
    }

    $candidates = New-Object System.Collections.Generic.List[string]

    $steamRoots = New-Object System.Collections.Generic.List[string]
    foreach ($root in @(
            "${env:ProgramFiles(x86)}\Steam",
            "$env:ProgramFiles\Steam"
        )) {
        if ($root -and (Test-Path -LiteralPath $root)) {
            $steamRoots.Add($root)
        }
    }

    try {
        $reg = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction Stop
        if ($reg.SteamPath) { $steamRoots.Add($reg.SteamPath) }
    } catch {
    }

    $extraLibraries = New-Object System.Collections.Generic.List[string]
    foreach ($steamRoot in $steamRoots) {
        $vdf = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $vdf) {
            Get-Content -LiteralPath $vdf | ForEach-Object {
                if ($_ -match '"path"\s+"([^"]+)"') {
                    $extraLibraries.Add(($Matches[1] -replace '\\\\', '\'))
                }
            }
        }
    }
    foreach ($lib in $extraLibraries) {
        $steamRoots.Add($lib)
    }

    $uniqueSteam = $steamRoots | Where-Object { $_ } | ForEach-Object {
        $_.TrimEnd('\')
    } | Select-Object -Unique

    foreach ($steamRoot in $uniqueSteam) {
        $candidates.Add((Join-Path $steamRoot "steamapps\common\Kerbal Space Program\Ships\Script"))
    }

    $candidates.Add("C:\Program Files (x86)\Steam\steamapps\common\Kerbal Space Program\Ships\Script")

    foreach ($path in ($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $path) { return $path }
    }

    return $candidates[0]
}

function Test-WritableDirectory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    $probe = Join-Path $Path (".aoso-write-test-" + [guid]::NewGuid().ToString("N"))
    try {
        [IO.File]::WriteAllText($probe, "ok")
        return $true
    } catch {
        return $false
    } finally {
        if (Test-Path -LiteralPath $probe) {
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-RelativePath {
    param(
        [string]$Root,
        [string]$FullName
    )

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $itemFull = [IO.Path]::GetFullPath($FullName)
    if ($itemFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        return $itemFull.Substring($rootFull.Length)
    }
    return $itemFull
}

try {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "             AOSO UPDATER" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    $KOS_ROOT = Get-KosScriptFolder
    $AOSO_ROOT = Join-Path $KOS_ROOT "AOSO"
    $VERSION_FILE = Join-Path $AOSO_ROOT ".aoso-version"

    Write-Host "kOS Script folder: $KOS_ROOT" -ForegroundColor Gray

    if (-not (Test-Path -LiteralPath $KOS_ROOT)) {
        throw @"
kOS Script folder was not found:
  $KOS_ROOT

Create kos-root.txt next to Update-AOSO.bat and put the full path to
your Kerbal Space Program\Ships\Script folder on the first line.
"@
    }

    if (-not (Test-WritableDirectory -Path $KOS_ROOT)) {
        throw @"
Cannot write to:
  $KOS_ROOT

Right-click Update-AOSO.bat and choose Run as administrator.
Steam installs KSP under Program Files, which Windows protects.
"@
    }

    $ksp = Get-Process -Name "KSP_x64", "KSP" -ErrorAction SilentlyContinue
    if ($ksp) {
        Write-Host "WARNING: Kerbal Space Program appears to be running." -ForegroundColor Yellow
        Write-Host "Close KSP before updating AOSO so kOS is not using the files." -ForegroundColor Yellow
        Write-Host ""
        $answer = Read-Host "Continue anyway? (Y/N)"
        if ($answer -notmatch '^[Yy]$') {
            Write-Host "Update cancelled."
            Read-Host "Press Enter to exit"
            exit 0
        }
    }

    $apiBase = "https://api.github.com/repos/$RepoOwner/$RepoName"

    Write-Host "Checking GitHub..." -ForegroundColor Gray

    $commitInfo = Get-GitHubJson "$apiBase/commits/$Branch"
    $latestCommit = [string]$commitInfo.sha
    $latestMessage = ([string]$commitInfo.commit.message -split "`r?`n")[0]

    Write-Host "Latest commit : $latestCommit" -ForegroundColor Green
    Write-Host "Commit message: $latestMessage" -ForegroundColor Gray
    Write-Host ""

    $installedCommit = ""
    if (Test-Path -LiteralPath $VERSION_FILE) {
        $installedCommit = (Get-Content -LiteralPath $VERSION_FILE -Raw).Trim()
    }

    if ($installedCommit -and ($installedCommit -eq $latestCommit)) {
        Write-Host "AOSO is already up to date." -ForegroundColor Green
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 0
    }

    if ($installedCommit) {
        Write-Host "Local commit  : $installedCommit" -ForegroundColor Gray
    } else {
        Write-Host "Local commit  : (none - first install)" -ForegroundColor Gray
    }
    Write-Host "New commit    : $latestCommit" -ForegroundColor Green
    Write-Host ""

    if (Test-Path -LiteralPath $AOSO_ROOT) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupRoot = Join-Path $KOS_ROOT "_AOSO_Backups"
        $backupPath = Join-Path $backupRoot "AOSO-$timestamp"

        Write-Host "Creating backup..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        Copy-Item -LiteralPath $AOSO_ROOT -Destination $backupPath -Recurse -Force
        Write-Host "Backup: $backupPath" -ForegroundColor Gray
        Write-Host ""
    }

    $tempRoot = Join-Path $env:TEMP ("AOSO-update-" + [guid]::NewGuid().ToString("N"))
    $zipPath = Join-Path $tempRoot "aoso.zip"
    $extractRoot = Join-Path $tempRoot "extract"
    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null

    $zipUrls = @(
        "https://codeload.github.com/$RepoOwner/$RepoName/zip/$latestCommit",
        "https://github.com/$RepoOwner/$RepoName/archive/$latestCommit.zip"
    )

    $downloaded = $false
    foreach ($zipUrl in $zipUrls) {
        Write-Host "Downloading AOSO $Branch ($($latestCommit.Substring(0, 7)))..." -ForegroundColor Cyan
        try {
            Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -Headers @{ "User-Agent" = $UserAgent }
            if ((Test-Path -LiteralPath $zipPath) -and (Get-Item -LiteralPath $zipPath).Length -ge 100) {
                $downloaded = $true
                break
            }
        } catch {
            Write-Host "  Download from $zipUrl failed, trying a fallback..." -ForegroundColor Yellow
        }
    }

    if (-not $downloaded) {
        throw "Could not download the AOSO zip from GitHub."
    }

    Write-Host "Extracting..." -ForegroundColor Gray
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force

    $sourceAoso = Get-ChildItem -LiteralPath $extractRoot -Directory |
        ForEach-Object { Join-Path $_.FullName "AOSO" } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1

    if (-not $sourceAoso) {
        throw "The GitHub zip did not contain an AOSO folder."
    }

    $sourceFiles = @(Get-ChildItem -LiteralPath $sourceAoso -Recurse -File)
    if ($sourceFiles.Count -eq 0) {
        throw "No files were found under AOSO/ in the GitHub zip."
    }

    New-Item -ItemType Directory -Path $AOSO_ROOT -Force | Out-Null

    $expectedRelative = @{}
    $updated = 0

    Write-Host ""
    Write-Host "Installing $($sourceFiles.Count) files..." -ForegroundColor Cyan
    Write-Host ""

    foreach ($file in $sourceFiles) {
        $relative = Get-RelativePath -Root $sourceAoso -FullName $file.FullName
        $expectedRelative[$relative] = $true
        $destination = Join-Path $AOSO_ROOT $relative
        $parent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
        $updated++
        Write-Host "  $relative" -ForegroundColor White
    }

    $removed = 0
    $localKsFiles = @()
    if (Test-Path -LiteralPath $AOSO_ROOT) {
        $localKsFiles = @(Get-ChildItem -LiteralPath $AOSO_ROOT -Filter "*.ks" -File -Recurse)
    }

    foreach ($localFile in $localKsFiles) {
        $relative = Get-RelativePath -Root $AOSO_ROOT -FullName $localFile.FullName
        $baseName = [IO.Path]::GetFileName($relative)
        if ($expectedRelative.ContainsKey($relative)) { continue }
        if ($PreserveNames -contains $baseName) { continue }

        Write-Host "Removing obsolete: $relative" -ForegroundColor Yellow
        Remove-Item -LiteralPath $localFile.FullName -Force
        $removed++
    }

    $latestCommit | Set-Content -LiteralPath $VERSION_FILE -Encoding ASCII

    # Refresh the updater itself from this same commit, if the zip includes it.
    $zipRoot = Get-ChildItem -LiteralPath $extractRoot -Directory | Select-Object -First 1
    if ($zipRoot) {
        foreach ($name in @("Update-AOSO.ps1", "Update-AOSO.bat")) {
            $src = Join-Path $zipRoot.FullName $name
            if (Test-Path -LiteralPath $src) {
                Copy-Item -LiteralPath $src -Destination (Join-Path $PSScriptRoot $name) -Force
            }
        }
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "        AOSO UPDATE COMPLETE" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Files installed  : $updated" -ForegroundColor Green
    Write-Host "Files removed    : $removed" -ForegroundColor Yellow
    Write-Host "Installed commit : $latestCommit" -ForegroundColor Gray
    Write-Host "Install location : $AOSO_ROOT" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Custom files such as mission_plan.ks are left in place." -ForegroundColor Gray
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "          AOSO UPDATE FAILED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    if ($_.Exception.Response) {
        try {
            $status = [int]$_.Exception.Response.StatusCode
            Write-Host "HTTP status: $status" -ForegroundColor DarkGray
        } catch {
        }
    }
    Write-Host "A backup was created before files were changed, if one already existed." -ForegroundColor Gray
    Write-Host ""
    exit 1
}
finally {
    if ($tempRoot -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Read-Host "Press Enter to exit"
