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
if ($Release) {
    # Sign release builds with the same local key as debug builds so the app updates in place:
    # a different key forces an uninstall, which deletes the game's saves on the phone.
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = "D:\Tools\Godot\editor_data\keystores\debug.keystore"
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = "androiddebugkey"
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = "android"
}
# --install-android-build-template only works together with an export; skip it once installed.
$template = @()
if (-not (Test-Path (Join-Path $shell "android\build\build.gradle"))) {
    Write-Host "First Gradle build: installing Godot's Android build template into shell\android..."
    $template = @("--install-android-build-template")
}
if (-not $template) {
    # The perf plugin compiles against the template's godot-lib, so it can only be built once that's installed.
    & (Join-Path $PSScriptRoot "build-perf-plugin.ps1")
} else {
    Write-Host "Run build-apk.ps1 again after this first build: the perf plugin needs the installed template."
}
$apk = Join-Path $out "sts2port.apk"
if (Test-Path $apk) { Remove-Item $apk }
# Godot can sit idle for 20+ minutes after Gradle has written the APK (waiting on the Gradle daemon). Stop it once the
# APK has been unchanged for a minute; the APK is complete by then (Gradle signs before it copies it out).
$godotArgs = @("--headless", "--path", "`"$((Resolve-Path $shell).Path)`"") + $template + @($mode, "Android", "../build/sts2port.apk")
$proc = Start-Process -FilePath $Godot -ArgumentList $godotArgs -NoNewWindow -PassThru
$null = $proc.Handle  # keeps the handle, so ExitCode is readable after it exits
$stableSince = $null; $lastWrite = $null
while (-not $proc.HasExited) {
    Start-Sleep 5
    if (Test-Path $apk) {
        $write = (Get-Item $apk).LastWriteTimeUtc
        if ($write -ne $lastWrite) { $lastWrite = $write; $stableSince = Get-Date }
        elseif (((Get-Date) - $stableSince).TotalSeconds -ge 60) {
            Write-Host "APK written; stopping the idle Godot export."
            Stop-Process -Id $proc.Id -Force
            break
        }
    }
}
if (-not (Test-Path $apk) -or ($proc.HasExited -and $proc.ExitCode -ne 0 -and $null -eq $stableSince)) { throw "APK export failed" }
Write-Host "Built $(Resolve-Path $apk)"
