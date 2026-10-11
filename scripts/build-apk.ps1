<#
.SYNOPSIS
  Exports the Android shell APK (repo code only, no game files) to build\sts2port.apk.

.DESCRIPTION
  Uses Godot's Gradle build (needed for the FMOD addon's Android plugin). The first run installs Godot's Android
  build template into shell\android (gitignored) and lets Gradle download its dependencies into
  D:\Tools\gradle-home, so nothing lands in the user profile on C:.
  Run scripts\fetch-plugins.ps1 once before this.
#>
param(
    [string]$Godot = "D:\Tools\Godot\Godot_v4.5.1-stable_mono_win64_console.exe",
    [string]$GradleHome = "D:\Tools\gradle-home",
    [switch]$Release
)
$ErrorActionPreference = "Stop"
$shell = Join-Path $PSScriptRoot "..\shell"
$out = Join-Path $PSScriptRoot "..\build"
if (-not (Test-Path (Join-Path $shell "addons\fmod\fmod.gdextension"))) { throw "Plugins missing: run scripts\fetch-plugins.ps1 first." }
New-Item -ItemType Directory -Force $out, $GradleHome | Out-Null
$env:GRADLE_USER_HOME = $GradleHome

$mode = if ($Release) { "--export-release" } else { "--export-debug" }
# --install-android-build-template only works together with an export; skip it once installed.
$template = @()
if (-not (Test-Path (Join-Path $shell "android\build\build.gradle"))) {
    Write-Host "First Gradle build: installing Godot's Android build template into shell\android..."
    $template = @("--install-android-build-template")
}
$apk = Join-Path $out "sts2port.apk"
if (Test-Path $apk) { Remove-Item $apk }
& $Godot --headless --path $shell @template $mode "Android" "../build/sts2port.apk"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $apk)) { throw "APK export failed" }
Write-Host "Built $(Resolve-Path $apk)"
