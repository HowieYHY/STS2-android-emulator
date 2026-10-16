<#
.SYNOPSIS
  Turns the game's full dev console on or off on the phone, and types console commands into it, for testing.

.DESCRIPTION
  The game only registers its debug commands (room, fight, gold, relic...) when settings.save has
  "full_console": true. The port's boot script sets that when a file named "dev_console" sits next to the packs,
  and removes it again when the file is gone, so cheats are never left on by accident.

  -On / -Off   create or delete that flag file. Takes effect at the next app launch (-Restart does that).
  -Run         opens the console (backtick key), types each command, presses Enter, then closes the console.
               The game must be running, in the foreground, with the full console on.

  Commands that touch saves or crash the game (cloud, sentry, die, leaderboard, achievement) are refused.

.EXAMPLE
  scripts\dev-console.ps1 -On -Restart
  scripts\dev-console.ps1 -Run "gold 200; room shop"
  scripts\dev-console.ps1 -Off
#>
param(
    [switch]$On,
    [switch]$Off,
    [switch]$Restart,
    [string[]]$Run = @(),
    [string]$Adb = $(if ($env:ANDROID_HOME) { Join-Path $env:ANDROID_HOME "platform-tools\adb.exe" } else { "adb" })
)
$ErrorActionPreference = "Stop"
$Package = "com.howieyhy.sts2port"
$Flag = "/storage/emulated/0/Android/data/$Package/files/dev_console"
$Refused = @("cloud", "sentry", "die", "leaderboard", "achievement")

# adb writes progress to stderr; Windows PowerShell 5.1 turns that into an error under "Stop",
# so run it with "Continue" and judge success by the exit code only.
function Invoke-Adb {
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { & $Adb @args 2>&1 | ForEach-Object { "$_" } } finally { $ErrorActionPreference = $prev }
    if ($LASTEXITCODE -ne 0) { throw "adb $($args -join ' ') failed (exit $LASTEXITCODE)" }
}

# Every key and text goes through here: it's sent only while the game is the focused window. A soak script once kept
# typing while the game was closed for an install, and the keys reached the home screen and another app.
function Send-GameInput {
    $focus = "$(Invoke-Adb shell dumpsys window | Select-String 'mCurrentFocus' | Select-Object -First 1)".Trim()
    if ($focus -notmatch [regex]::Escape("$Package/")) { throw "Stopped: the game isn't the focused app ($focus). Nothing was sent." }
    Invoke-Adb shell input @args | Out-Null
}

if ($On -and $Off) { throw "Use -On or -Off, not both." }
# "powershell -File" passes a list as one comma-joined string, so split on ',' and ';' ourselves.
$Run = @($Run | ForEach-Object { $_ -split '[,;]' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($cmd in $Run) {
    $name = ($cmd.Trim() -split '\s+')[0].ToLowerInvariant()
    if ($Refused -contains $name) { throw "Refusing '$cmd': '$name' can delete saves or crash the game." }
    if ($cmd -notmatch '^[A-Za-z0-9_ .\-]+$') { throw "Refusing '$cmd': only letters, digits, '_', '-', '.' and spaces are typed." }
}

if ($On) { Invoke-Adb shell touch $Flag | Out-Null; Write-Host "Full dev console flag set." }
if ($Off) { Invoke-Adb shell rm -f $Flag | Out-Null; Write-Host "Full dev console flag removed." }
if ($Restart) {
    # Home first: the game only saves settings/progress on pause (Sts2Patcher "Save on pause"); force-stop alone
    # kills it without pausing and in-memory changes (e.g. a dismissed pop-up) are lost.
    $focus = "$(Invoke-Adb shell dumpsys window | Select-String 'mCurrentFocus' | Select-Object -First 1)"
    if ($focus -match [regex]::Escape("$Package/")) { Send-GameInput keyevent KEYCODE_HOME; Start-Sleep -Seconds 2 }
    Invoke-Adb shell am force-stop $Package | Out-Null
    Invoke-Adb shell am start -n "$Package/com.godot.game.GodotApp" | Out-Null
    Write-Host "Restarted the app; wait for the main menu (~16 s) before -Run."
}

if ($Run.Count -gt 0) {
    Send-GameInput keyevent KEYCODE_GRAVE  # backtick opens the console
    Start-Sleep -Milliseconds 800
    foreach ($cmd in $Run) {
        Send-GameInput text ($cmd.Trim() -replace ' ', '%s')  # "input text" takes %s for spaces
        Send-GameInput keyevent KEYCODE_ENTER
        Write-Host "> $cmd"
        Start-Sleep -Milliseconds 800
    }
    Send-GameInput keyevent KEYCODE_GRAVE  # close it again
}
