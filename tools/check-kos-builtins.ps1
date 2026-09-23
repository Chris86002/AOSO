# Check script declarations against the actual built-in functions in an installed kOS.
# Usage: powershell -NoProfile -File tools/check-kos-builtins.ps1 -KspRoot 'C:\path\to\Kerbal Space Program'
param(
    [string]$KspRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Kerbal Space Program'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$pluginDir = Join-Path $KspRoot 'GameData\kOS\Plugins'
$builtins = @{}

foreach ($dllName in @('kOS.Safe.dll', 'kOS.dll')) {
    $dllPath = Join-Path $pluginDir $dllName
    if (-not (Test-Path -LiteralPath $dllPath)) {
        throw "kOS library missing: $dllPath"
    }
    $assembly = [Reflection.Assembly]::LoadFrom($dllPath)
    try {
        $types = @($assembly.GetTypes())
    } catch [Reflection.ReflectionTypeLoadException] {
        # kOS.dll also refers to Unity/KSP assemblies, which need not load here.
        $types = @($_.Exception.Types | Where-Object { $null -ne $_ })
    }
    foreach ($type in $types) {
        foreach ($attribute in $type.CustomAttributes) {
            if ($attribute.AttributeType.FullName -ne 'kOS.Safe.Function.FunctionAttribute') { continue }
            foreach ($argument in $attribute.ConstructorArguments[0].Value) {
                $builtins[[string]$argument.Value] = $type.FullName
            }
        }
    }
}

$collisions = @()
Get-ChildItem (Join-Path $repoRoot 'AOSO') -Recurse -Filter '*.ks' -File | ForEach-Object {
    $sourcePath = $_.FullName
    $lineNumber = 0
    Get-Content -LiteralPath $sourcePath | ForEach-Object {
        $lineNumber++
        $code = [regex]::Replace($_, '"(?:[^"]|"")*"', '""') -replace '//.*$', ''
        foreach ($match in [regex]::Matches($code, '(?i)\b(?:LOCAL|GLOBAL|PARAMETER|FUNCTION)\s+([a-z_][a-z_0-9]*)')) {
            $name = $match.Groups[1].Value
            if ($builtins.ContainsKey($name)) {
                $collisions += "${sourcePath}:$lineNumber $name conflicts with $($builtins[$name])"
            }
        }
    }
}

if ($collisions.Count -gt 0) {
    $collisions | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host "PASS: no KerboScript declarations shadow $($builtins.Count) kOS built-in functions."
