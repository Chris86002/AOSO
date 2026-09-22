param(
    [string]$KspRoot = $env:KSP_ROOT,
    [ValidateSet("Release","Debug")]
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($KspRoot)) {
    $KspRoot = "C:\Program Files (x86)\Steam\steamapps\common\Kerbal Space Program"
}

$project = Join-Path $PSScriptRoot "kOS.AddOns.AOSO.csproj"
$kosDll = Join-Path $KspRoot "GameData\kOS\Plugins\kOS.dll"
$assemblyCSharp = Join-Path $KspRoot "KSP_x64_Data\Managed\Assembly-CSharp.dll"

if (-not (Test-Path $project)) { throw "Project not found: $project" }
if (-not (Test-Path $kosDll)) { throw "kOS.dll not found: $kosDll" }
if (-not (Test-Path $assemblyCSharp)) { throw "Assembly-CSharp.dll not found: $assemblyCSharp" }

function Find-MSBuild {
    $fromPath = Get-Command msbuild -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }

    $pf86 = [Environment]::GetFolderPath("ProgramFilesX86")
    $pf64 = [Environment]::GetFolderPath("ProgramFiles")
    $vswhereCandidates = @(
        (Join-Path $pf86 "Microsoft Visual Studio\Installer\vswhere.exe"),
        (Join-Path $pf64 "Microsoft Visual Studio\Installer\vswhere.exe")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    foreach ($vswhere in $vswhereCandidates) {
        try {
            $found = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
            if ($found -and (Test-Path -LiteralPath $found)) { return $found }
        } catch {
        }
    }

    $fallbacks = @(
        (Join-Path $pf86 "Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe"),
        (Join-Path $pf86 "Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"),
        (Join-Path $pf86 "Microsoft Visual Studio\2026\BuildTools\MSBuild\Current\Bin\MSBuild.exe"),
        (Join-Path $pf86 "Microsoft Visual Studio\2026\Community\MSBuild\Current\Bin\MSBuild.exe"),
        (Join-Path $pf64 "Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe"),
        (Join-Path $pf64 "Microsoft Visual Studio\2026\BuildTools\MSBuild\Current\Bin\MSBuild.exe")
    )

    foreach ($candidate in $fallbacks) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }

    return $null
}

$msbuild = Find-MSBuild
$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue

$logDir = Join-Path $KspRoot "GameData\AOSO"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$buildLog = Join-Path $logDir "AOSO-native-build.log"
if (Test-Path -LiteralPath $buildLog) {
    Remove-Item -LiteralPath $buildLog -Force -ErrorAction SilentlyContinue
}

Write-Host "Building kOS.AddOns.AOSO against $KspRoot"
if ($msbuild) {
    Write-Host "Build tool: MSBuild"
    Write-Host "MSBuild path: $msbuild"
    & $msbuild $project "/t:Restore;Build" "/p:Configuration=$Configuration" "/p:KSP_ROOT=$KspRoot" "/verbosity:minimal" 2>&1 | Tee-Object -FilePath $buildLog
    $buildExit = $LASTEXITCODE
} elseif ($dotnet) {
    Write-Host "Build tool: dotnet (MSBuild was not found)"
    Write-Host "dotnet path: $($dotnet.Source)"
    & $dotnet.Source build $project -c $Configuration "-p:KSP_ROOT=$KspRoot" 2>&1 | Tee-Object -FilePath $buildLog
    $buildExit = $LASTEXITCODE
} else {
    throw "Neither Visual Studio MSBuild nor dotnet was found. Install Visual Studio Build Tools with MSBuild and the .NET Framework 4.8 targeting pack."
}

if ($buildExit -ne 0) {
    Write-Host ""
    Write-Host "Native build failed. Full compiler log:" -ForegroundColor Red
    Write-Host "  $buildLog" -ForegroundColor Yellow
    Write-Host ""
    if (Test-Path -LiteralPath $buildLog) {
        Write-Host "Last 80 lines:" -ForegroundColor Yellow
        Get-Content -LiteralPath $buildLog -Tail 80 | ForEach-Object { Write-Host $_ }
    }
    throw "Native addon build failed with exit code $buildExit. See $buildLog"
}

$built = Join-Path $PSScriptRoot "bin\$Configuration\net48\kOS.AddOns.AOSO.dll"
if (-not (Test-Path $built)) { throw "Built DLL not found: $built" }

$destDir = Join-Path $KspRoot "GameData\AOSO\Plugins"
$dest = Join-Path $destDir "kOS.AddOns.AOSO.dll"

try {
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    $probe = Join-Path $destDir (".aoso-native-write-test-" + [guid]::NewGuid().ToString("N"))
    try {
        [IO.File]::WriteAllText($probe, "ok")
    } finally {
        if (Test-Path -LiteralPath $probe) {
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        }
    }

    $copyError = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Copy-Item -LiteralPath $built -Destination $dest -Force -ErrorAction Stop
            $copyError = $null
            break
        } catch {
            $copyError = $_.Exception
            if ($attempt -lt 3) { Start-Sleep -Milliseconds 600 }
        }
    }
    if ($copyError) { throw $copyError }

    if (-not (Test-Path -LiteralPath $dest)) {
        throw "DLL copy reported success, but destination does not exist: $dest"
    }

    $installedVersion = [Reflection.AssemblyName]::GetAssemblyName($dest).Version
    $sourceVersion = [Reflection.AssemblyName]::GetAssemblyName($built).Version
    if ($installedVersion -ne $sourceVersion) {
        throw "Installed DLL version $installedVersion does not match built DLL version $sourceVersion"
    }

    "INSTALL OK: $dest (v$installedVersion)" | Add-Content -LiteralPath $buildLog -Encoding UTF8
    Write-Host "Installed: $dest"
    Write-Host "Installed version: $installedVersion"
    Write-Host "Build/install log: $buildLog"
    Write-Host "Restart KSP. AOSO selftest should report native phase2 suffixes current."
} catch {
    $installMessage = $_.Exception.Message
    "INSTALL FAILED: $installMessage" | Add-Content -LiteralPath $buildLog -Encoding UTF8
    Write-Host ""
    Write-Host "Native compile SUCCEEDED, but DLL installation failed:" -ForegroundColor Red
    Write-Host "  $installMessage" -ForegroundColor Red
    Write-Host ""
    Write-Host "Destination:" -ForegroundColor Yellow
    Write-Host "  $dest" -ForegroundColor Yellow
    Write-Host "Full build/install log:" -ForegroundColor Yellow
    Write-Host "  $buildLog" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "If you see Access Denied, run Update-AOSO.bat as Administrator." -ForegroundColor Yellow
    Write-Host "If the DLL is in use, close KSP completely and run the updater again." -ForegroundColor Yellow
    throw "Native addon compiled successfully but installation failed: $installMessage"
}
