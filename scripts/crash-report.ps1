<#
.SYNOPSIS
  Collects what Android kept about the game's recent crashes or kills into a folder on the PC (outside the repo).

.DESCRIPTION
  Run it after a crash, with the phone plugged in. Android keeps these for days, so it doesn't have to be right away,
  but the logcat buffers roll over quickly, so sooner is better.
    exit-info.txt   why each recent run of the app ended (crash, native crash, killed for low memory, ANR...)
    dropbox.txt     Android's crash records: Java crashes, native crashes and tombstones, ANRs
    crash-log.txt   logcat's crash buffer
    log.txt         the last 20,000 lines of logcat (the game logs everything there)
    game-logs\      the game's own log files, one per session (the newest five), including the session that crashed,
                    and logcat-*.txt: everything the app's process wrote to logcat (Godot, the .NET runtime, Android's
                    "Fatal signal" line), captured live by the APK from 0.1.5 on. Read the crashed session's one first.
  Nothing on the phone is changed.

.EXAMPLE
  scripts\crash-report.ps1
#>
param(
    [string]$OutDir = (Join-Path $env:LOCALAPPDATA ("sts2port\crash-" + (Get-Date -Format "yyyyMMdd-HHmmss"))),
    [string]$Adb = $(if ($env:ANDROID_HOME) { Join-Path $env:ANDROID_HOME "platform-tools\adb.exe" } else { "adb" })
)
$ErrorActionPreference = "Stop"
$Package = "com.howieyhy.sts2port"

# adb writes progress to stderr; Windows PowerShell 5.1 turns that into an error under "Stop".
function Invoke-Adb {
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { & $Adb @args 2>&1 | ForEach-Object { "$_" } } finally { $ErrorActionPreference = $prev }
}

$devices = Invoke-Adb devices | Select-String "`tdevice$"
if (-not $devices) { throw "No phone found by adb. Plug it in, enable USB debugging and accept the prompt on the phone." }
New-Item -ItemType Directory -Force $OutDir | Out-Null

# -Value (not the pipeline) so an empty result still writes its file.
Set-Content (Join-Path $OutDir "exit-info.txt") -Encoding utf8 -Value (Invoke-Adb shell dumpsys activity exit-info $Package)
$dropbox = foreach ($tag in "data_app_crash", "data_app_native_crash", "SYSTEM_TOMBSTONE", "data_app_anr") {
    "===== $tag ====="
    Invoke-Adb shell dumpsys dropbox --print $tag
}
Set-Content (Join-Path $OutDir "dropbox.txt") -Encoding utf8 -Value $dropbox
Set-Content (Join-Path $OutDir "crash-log.txt") -Encoding utf8 -Value (Invoke-Adb logcat -b crash -d)
Set-Content (Join-Path $OutDir "log.txt") -Encoding utf8 -Value (Invoke-Adb logcat -d -t 20000)
Invoke-Adb pull "/storage/emulated/0/Android/data/$Package/files/logs" (Join-Path $OutDir "game-logs") | Out-Null

$reasons = Select-String -Path (Join-Path $OutDir "exit-info.txt") -Pattern "reason=" | Select-Object -First 5
Write-Host "Saved to $OutDir"
if ($reasons) { Write-Host "Most recent app exits:"; $reasons | ForEach-Object { Write-Host "  $($_.Line.Trim())" } }
$fatal = Get-ChildItem (Join-Path $OutDir "game-logs") -Filter "logcat*.txt" -ErrorAction SilentlyContinue |
    Select-String -Pattern "Fatal signal|Abort message| F (libc|DEBUG|mono)|Assertion|Unhandled Exception|FATAL"
if ($fatal) { Write-Host "Fatal lines in the captured logcat:"; $fatal | Select-Object -Last 15 | ForEach-Object { Write-Host "  $($_.Filename): $($_.Line.Trim())" } }
