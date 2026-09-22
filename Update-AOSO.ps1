# AOSO Updater
# Syncs the local kOS AOSO folder with the latest commit on GitHub.
# Repository: https://github.com/Chris86002/AOSO
#
# Usage:
#   Double-click Update-AOSO.bat          (one-time update)
#   Double-click Watch-AOSO.bat           (leave running; auto-updates)
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\Update-AOSO.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\Update-AOSO.ps1 -Watch
#
# If KSP is not in the default Steam folder, create kos-root.txt next to this
# script and put the full path to your kOS Script folder on the first line.

param(
    [switch]$Watch,
    [int]$IntervalMinutes = 10
)

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
$NativePluginMinVersion = [version]"0.2.0.0"

$UserAgent = "AOSO-Updater"
$GitHubHeaders = @{
    "User-Agent"           = $UserAgent
    "Accept"               = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

$UpdaterFileNames = @(
    "Update-AOSO.ps1",
    "Update-AOSO.bat",
    "Watch-AOSO.bat"
)

function Write-Stamp {
    param(
        [string]$Message,
        [string]$Color = "Gray"
    )
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$stamp] $Message" -ForegroundColor $Color
}

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

function Get-KspRootFromKosScriptFolder {
    param([string]$KosScriptFolder)

    $scriptDir = [IO.Path]::GetFullPath($KosScriptFolder).TrimEnd('\')
    $shipsDir = Split-Path -Parent $scriptDir
    if (-not $shipsDir) { return "" }
    return (Split-Path -Parent $shipsDir)
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

function Get-InstalledCommit {
    param([string]$VersionFile)

    if (Test-Path -LiteralPath $VersionFile) {
        return (Get-Content -LiteralPath $VersionFile -Raw).Trim()
    }
    return ""
}

function Get-NativeAddonState {
    param([string]$KspRoot)

    if (-not $KspRoot) {
        return @{ Ready = $false; Version = $null; Message = "KSP root unknown" }
    }

    $dll = Join-Path $KspRoot "GameData\AOSO\Plugins\kOS.AddOns.AOSO.dll"
    if (-not (Test-Path -LiteralPath $dll)) {
        return @{ Ready = $false; Version = $null; Message = "DLL missing" }
    }

    try {
        $version = [Reflection.AssemblyName]::GetAssemblyName($dll).Version
        if ($version -ge $NativePluginMinVersion) {
            return @{ Ready = $true; Version = $version; Message = "v$version" }
        }
        return @{ Ready = $false; Version = $version; Message = "stale v$version" }
    } catch {
        return @{ Ready = $false; Version = $null; Message = "DLL version unreadable" }
    }
}

function Invoke-AosoUpdate {
    param(
        [switch]$Auto
    )

    $KOS_ROOT = Get-KosScriptFolder
    $AOSO_ROOT = Join-Path $KOS_ROOT "AOSO"
    $KSP_ROOT = Get-KspRootFromKosScriptFolder -KosScriptFolder $KOS_ROOT
    $VERSION_FILE = Join-Path $AOSO_ROOT ".aoso-version"
    $tempRoot = $null

    if (-not (Test-Path -LiteralPath $KOS_ROOT)) {
        throw @"
kOS Script folder was not found:
  $KOS_ROOT

Create kos-root.txt next to Watch-AOSO.bat and put the full path to
your Kerbal Space Program\Ships\Script folder on the first line.
"@
    }

    if (-not (Test-WritableDirectory -Path $KOS_ROOT)) {
        throw @"
Cannot write to:
  $KOS_ROOT

Right-click the .bat and choose Run as administrator.
Steam installs KSP under Program Files, which Windows protects.
"@
    }

    $apiBase = "https://api.github.com/repos/$RepoOwner/$RepoName"
    if (-not $Auto) {
        Write-Host "Checking GitHub..." -ForegroundColor Gray
    }

    $commitInfo = Get-GitHubJson "$apiBase/commits/$Branch"
    $latestCommit = [string]$commitInfo.sha
    $latestMessage = ([string]$commitInfo.commit.message -split "`r?`n")[0]
    $short = $latestCommit.Substring(0, 7)
    $installedCommit = Get-InstalledCommit -VersionFile $VERSION_FILE

    $nativeState = Get-NativeAddonState -KspRoot $KSP_ROOT
    if ($installedCommit -and ($installedCommit -eq $latestCommit) -and $nativeState.Ready) {
        return @{
            Status  = "Current"
            Message = "AOSO is current ($short); native $($nativeState.Message)."
            Commit  = $latestCommit
        }
    }

    if ($installedCommit -and ($installedCommit -eq $latestCommit) -and -not $nativeState.Ready) {
        if (-not $Auto) {
            Write-Host "Scripts are current, but native addon is $($nativeState.Message); retrying native install." -ForegroundColor Yellow
            Write-Host ""
        } else {
            Write-Stamp "Scripts current; native addon $($nativeState.Message) - retrying install." "Yellow"
        }
    }

    if (-not $Auto) {
        Write-Host "Latest commit : $latestCommit" -ForegroundColor Green
        Write-Host "Commit message: $latestMessage" -ForegroundColor Gray
        Write-Host ""
        if ($installedCommit) {
            Write-Host "Local commit  : $installedCommit" -ForegroundColor Gray
        } else {
            Write-Host "Local commit  : (none - first install)" -ForegroundColor Gray
        }
        Write-Host "New commit    : $latestCommit" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Stamp "New commit $short - $latestMessage" "Cyan"
    }

    try {
        if (Test-Path -LiteralPath $AOSO_ROOT) {
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $backupRoot = Join-Path $KOS_ROOT "_AOSO_Backups"
            $backupPath = Join-Path $backupRoot "AOSO-$timestamp"

            Write-Host "Creating backup..." -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
            Copy-Item -LiteralPath $AOSO_ROOT -Destination $backupPath -Recurse -Force
            Write-Host "Backup: $backupPath" -ForegroundColor Gray
            Write-Host ""

            $oldBackups = @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
            if ($oldBackups.Count -gt 8) {
                $oldBackups | Select-Object -Skip 8 | ForEach-Object {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
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
            Write-Host "Downloading AOSO $Branch ($short)..." -ForegroundColor Cyan
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

        Write-Host "Installing $($sourceFiles.Count) files..." -ForegroundColor Cyan

        foreach ($file in $sourceFiles) {
            $relative = Get-RelativePath -Root $sourceAoso -FullName $file.FullName
            $expectedRelative[$relative] = $true
            $destination = Join-Path $AOSO_ROOT $relative
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            if (Test-Path -LiteralPath $destination) {
                try {
                    $existing = Get-Item -LiteralPath $destination
                    if ($existing.IsReadOnly) { $existing.IsReadOnly = $false }
                } catch {
                }
            }
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
            $updated++
            if (-not $Auto) {
                Write-Host "  $relative" -ForegroundColor White
            }
        }

        $removed = 0
        $localKsFiles = @()
        if (Test-Path -LiteralPath $AOSO_ROOT) {
            $localKsFiles = @(Get-ChildItem -LiteralPath $AOSO_ROOT -Filter "*.ks" -File -Recurse)
        }

        foreach ($localFile in $localKsFiles) {
            $relative = Get-RelativePath -Root $AOSO_ROOT -FullName $localFile.FullName
            if ($expectedRelative.ContainsKey($relative)) { continue }

            Write-Host "Removing obsolete: $relative" -ForegroundColor Yellow
            Remove-Item -LiteralPath $localFile.FullName -Force
            $removed++
        }

        $latestCommit | Set-Content -LiteralPath $VERSION_FILE -Encoding ASCII

        $zipRoot = Get-ChildItem -LiteralPath $extractRoot -Directory | Select-Object -First 1
        $nativePluginStatus = "not attempted"
        if ($zipRoot) {
            foreach ($name in $UpdaterFileNames) {
                $src = Join-Path $zipRoot.FullName $name
                if (Test-Path -LiteralPath $src) {
                    Copy-Item -LiteralPath $src -Destination (Join-Path $PSScriptRoot $name) -Force
                }
            }

            $nativeInstaller = Join-Path $zipRoot.FullName "plugin\kOS.AddOns.AOSO\Build-And-Install.ps1"
            if (Test-Path -LiteralPath $nativeInstaller) {
                try {
                    if (-not $KSP_ROOT -or -not (Test-Path -LiteralPath $KSP_ROOT)) {
                        throw "Could not derive KSP root from $KOS_ROOT"
                    }

                    Write-Host "Building/installing native AOSO addon..." -ForegroundColor Cyan
                    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $nativeInstaller -KspRoot $KSP_ROOT -Configuration Release
                    if ($LASTEXITCODE -ne 0) {
                        throw "native addon installer exited with code $LASTEXITCODE"
                    }

                    $nativeDll = Join-Path $KSP_ROOT "GameData\AOSO\Plugins\kOS.AddOns.AOSO.dll"
                    $postState = Get-NativeAddonState -KspRoot $KSP_ROOT
                    if (-not (Test-Path -LiteralPath $nativeDll) -or -not $postState.Ready) {
                        throw "native addon DLL missing or stale after build"
                    }

                    $nativePluginStatus = "installed $($postState.Message)"
                    Write-Host "Native addon      : $nativePluginStatus (restart KSP to load it)" -ForegroundColor Green
                } catch {
                    $nativePluginStatus = "fallback-only: " + $_.Exception.Message
                    Write-Host "Native addon      : NOT updated - $($_.Exception.Message)" -ForegroundColor Yellow
                    Write-Host "AOSO scripts remain valid and will use the KerboScript fallback." -ForegroundColor Yellow
                    Write-Host "Install .NET build tools and rerun the updater to enable native math." -ForegroundColor DarkYellow
                }
            }
        }

        $summary = "Installed $updated files (removed $removed) at $short; native=$nativePluginStatus."
        if (-not $Auto) {
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Green
            Write-Host "        AOSO UPDATE COMPLETE" -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Green
            Write-Host ""
            Write-Host "Files installed  : $updated" -ForegroundColor Green
            Write-Host "Files removed    : $removed" -ForegroundColor Yellow
            Write-Host "Installed commit : $latestCommit" -ForegroundColor Gray
            Write-Host "Install location : $AOSO_ROOT" -ForegroundColor Gray
            Write-Host "Native addon     : $nativePluginStatus" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Every AOSO file from GitHub was written, including mission_plan.ks if it is in the repo." -ForegroundColor Gray
            Write-Host ""
        }

        return @{
            Status  = "Updated"
            Message = $summary
            Commit  = $latestCommit
        }
    }
    finally {
        if ($tempRoot -and (Test-Path -LiteralPath $tempRoot)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Show-Banner {
    param([string]$Title)

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

$KOS_ROOT = Get-KosScriptFolder
Write-Host "kOS Script folder: $KOS_ROOT" -ForegroundColor Gray
Write-Host ""

if ($Watch) {
    try {
        $Host.UI.RawUI.WindowTitle = "AOSO Watcher"
    } catch {
    }

    Show-Banner "          AOSO WATCHER"
    Write-Host "Leave this window open. AOSO will update itself from GitHub." -ForegroundColor Green
    Write-Host "Checks every $IntervalMinutes minute(s). Close the window to stop." -ForegroundColor Gray
    Write-Host "Script updates can run with KSP open; replacing the native DLL may require KSP to be closed." -ForegroundColor Gray
    Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray
    Write-Host ""

    while ($true) {
        try {
            $result = Invoke-AosoUpdate -Auto
            switch ($result.Status) {
                "Current" {
                    Write-Stamp $result.Message "Green"
                    $sleepSeconds = $IntervalMinutes * 60
                }
                "Updated" {
                    Write-Stamp $result.Message "Green"
                    $sleepSeconds = $IntervalMinutes * 60
                }
                default {
                    Write-Stamp $result.Message "Gray"
                    $sleepSeconds = $IntervalMinutes * 60
                }
            }
        } catch {
            Write-Stamp ("Check failed: " + $_.Exception.Message) "Red"
            $sleepSeconds = $IntervalMinutes * 60
        }

        $next = (Get-Date).AddSeconds($sleepSeconds).ToString("HH:mm:ss")
        Write-Host "               Next check at $next" -ForegroundColor DarkGray
        Start-Sleep -Seconds $sleepSeconds
    }
}

Show-Banner "             AOSO UPDATER"

$exitCode = 0
try {
    $result = Invoke-AosoUpdate
    switch ($result.Status) {
        "Current" {
            Write-Host $result.Message -ForegroundColor Green
            Write-Host ""
        }
        "Cancelled" {
            Write-Host $result.Message
            Write-Host ""
        }
        "Updated" { }
        default {
            Write-Host $result.Message
            Write-Host ""
        }
    }
} catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "          AOSO UPDATE FAILED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "A backup was created before files were changed, if one already existed." -ForegroundColor Gray
    Write-Host ""
    $exitCode = 1
}

Read-Host "Press Enter to exit"
exit $exitCode
