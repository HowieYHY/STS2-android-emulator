<#
.SYNOPSIS
  Exports the Android shell APK (repo code only, no game files) to build\sts2port.apk.
#>
param(
    [string]$Godot = "D:\Tools\Godot\Godot_v4.5.1-stable_mono_win64_console.exe",
    [switch]$Release
)
$ErrorActionPreference = "Stop"
$shell = Join-Path $PSScriptRoot "..\shell"
$out = Join-Path $PSScriptRoot "..\build"
New-Item -ItemType Directory -Force $out | Out-Null
$mode = if ($Release) { "--export-release" } else { "--export-debug" }
& $Godot --headless --path $shell $mode "Android" "../build/sts2port.apk"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $out "sts2port.apk"))) { throw "APK export failed" }
Write-Host "Built $(Resolve-Path (Join-Path $out 'sts2port.apk'))"
