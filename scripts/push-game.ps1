<#
.SYNOPSIS
  Copies your own Slay the Spire 2 files to the phone for the Android port.

.DESCRIPTION
  1. Builds overlay.pck (sts2.dll + managed deps + patched startup config) from your game install and
     the built APK, into -OutDir (outside the repo).
  2. Pushes overlay.pck and SlayTheSpire2.pck over adb into the app's data folder on the phone.
     The 1.9 GB SlayTheSpire2.pck is skipped when the phone already has a copy of the same size.
  The game folder is only read, never modified.

.EXAMPLE
  scripts\push-game.ps1 -GameDir "D:\Steam\steamapps\common\Slay the Spire 2"
#>
param(
    [Parameter(Mandatory = $true)][string]$GameDir,
    [string]$Apk = (Join-Path $PSScriptRoot "..\build\sts2port.apk"),
    [string]$OutDir = (Join-Path $env:LOCALAPPDATA "sts2port"),
    [string]$Adb = $(if ($env:ANDROID_HOME) { Join-Path $env:ANDROID_HOME "platform-tools\adb.exe" } else { "adb" }),
    [switch]$ForceBigPck
)
$ErrorActionPreference = "Stop"
$Package = "com.howieyhy.sts2port"
$Remote = "/storage/emulated/0/Android/data/$Package/files"

# adb writes progress to stderr; Windows PowerShell 5.1 turns that into an error under "Stop",
# so run it with "Continue" and judge success by the exit code only.
function Invoke-Adb {
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { & $Adb @args 2>&1 | ForEach-Object { "$_" } } finally { $ErrorActionPreference = $prev }
}

$pck = Join-Path $GameDir "SlayTheSpire2.pck"
if (-not (Test-Path $pck)) { throw "SlayTheSpire2.pck not found in '$GameDir'. Pass the folder that contains it." }
if (-not (Test-Path $Apk)) { throw "APK not found at '$Apk'. Build it first (scripts\build-apk.ps1)." }

Write-Host "Building overlay.pck..."
& python -I (Join-Path $PSScriptRoot "build_overlay.py") --game-dir $GameDir --apk $Apk --out $OutDir
if ($LASTEXITCODE -ne 0) { throw "build_overlay.py failed" }

$devices = Invoke-Adb devices | Select-String "`tdevice$"
if (-not $devices) { throw "No phone found by adb. Plug it in, enable USB debugging and accept the prompt on the phone." }

Invoke-Adb shell mkdir -p $Remote | Out-Null
Write-Host "Pushing overlay.pck..."
Invoke-Adb push (Join-Path $OutDir "overlay.pck") "$Remote/overlay.pck"
if ($LASTEXITCODE -ne 0) { throw "adb push of overlay.pck failed" }

$localSize = (Get-Item $pck).Length
$remoteSize = (Invoke-Adb shell "stat -c %s '$Remote/SlayTheSpire2.pck' 2>/dev/null") -as [long]
if ($ForceBigPck -or $remoteSize -ne $localSize) {
    Write-Host "Pushing SlayTheSpire2.pck ($([math]::Round($localSize / 1GB, 2)) GB, this takes a few minutes)..."
    Invoke-Adb push $pck "$Remote/SlayTheSpire2.pck"
    if ($LASTEXITCODE -ne 0) { throw "adb push of SlayTheSpire2.pck failed" }
} else {
    Write-Host "SlayTheSpire2.pck already on the phone (same size), skipped. Use -ForceBigPck to push it anyway."
}
Write-Host "Done. Files are in $Remote"
