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

$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
$msbuild = Get-Command msbuild -ErrorAction SilentlyContinue

Write-Host "Building kOS.AddOns.AOSO against $KspRoot"
if ($dotnet) {
    & $dotnet.Source build $project -c $Configuration "-p:KSP_ROOT=$KspRoot"
} elseif ($msbuild) {
    & $msbuild.Source $project "/p:Configuration=$Configuration" "/p:KSP_ROOT=$KspRoot"
} else {
    throw "Neither dotnet nor msbuild was found. Install .NET build tools with the .NET Framework 4.6.1 targeting pack."
}
if ($LASTEXITCODE -ne 0) { throw "Native addon build failed with exit code $LASTEXITCODE" }

$built = Join-Path $PSScriptRoot "bin\$Configuration\net461\kOS.AddOns.AOSO.dll"
if (-not (Test-Path $built)) { throw "Built DLL not found: $built" }

$destDir = Join-Path $KspRoot "GameData\AOSO\Plugins"
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
$dest = Join-Path $destDir "kOS.AddOns.AOSO.dll"
Copy-Item -Force $built $dest

Write-Host "Installed: $dest"
Write-Host "Restart KSP. AOSO selftest should report native phase2 suffixes current."
