<#
.SYNOPSIS
  Copies your own Slay the Spire 2 files to the phone for the Android port.

.DESCRIPTION
  1. Builds overlay.pck (sts2.dll + managed deps + patched startup config) from your game install and
     the built APK, into -OutDir (outside the repo).
  2. Builds textures_astc.pck: phone-format (ASTC) copies of the game's desktop-only textures (build_textures.py).
     Needs Godot 4.5.1 .NET (-Godot, or the GODOT environment variable). Without it this step is skipped with a
     warning: the game still runs, it just uses more memory and loads slower.
  3. With -InstallApk, installs (or updates) the APK on the phone.
  4. Pushes overlay.pck, SlayTheSpire2.pck and textures_astc.pck over adb into the app's data folder on the phone.
     The 1.9 GB SlayTheSpire2.pck is skipped when the phone already has a copy of the same size, and
     textures_astc.pck when its SHA-1 matches.
  The game folder is only read, never modified.

.EXAMPLE
  scripts\push-game.ps1 -GameDir "D:\Steam\steamapps\common\Slay the Spire 2"
.EXAMPLE
  scripts\push-game.ps1 -GameDir "C:\Program Files (x86)\Steam\steamapps\common\Slay the Spire 2" -Apk .\sts2port-0.1.4-arm64.apk -InstallApk
#>
param(
    [Parameter(Mandatory = $true)][string]$GameDir,
    [string]$Apk = "",  # default ..\build\sts2port.apk, set below ($PSScriptRoot can be empty here under -File)
    [string]$OutDir = (Join-Path $env:LOCALAPPDATA "sts2port"),
    [string]$Adb = $(if ($env:ANDROID_HOME) { Join-Path $env:ANDROID_HOME "platform-tools\adb.exe" } else { "adb" }),
    [string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "D:\Tools\Godot\Godot_v4.5.1-stable_mono_win64_console.exe" }),
    [switch]$InstallApk,
    [switch]$ForceBigPck
)
$TestedGameVersion = "v0.113.0"  # keep in step with README and docs/DEVELOPMENT.md "STS2 game version"
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Apk) { $Apk = Join-Path $here "..\build\sts2port.apk" }
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
if (-not (Test-Path $Apk)) { throw "APK not found at '$Apk'. Download it from the GitHub release and pass it with -Apk." }
foreach ($tool in @(
        @("python", "Python 3 is needed (python.org, or 'winget install Python.Python.3.12'), then open a new terminal."),
        @("dotnet", ".NET 9 SDK is needed ('winget install Microsoft.DotNet.SDK.9'), then open a new terminal."))) {
    if (-not (Get-Command $tool[0] -ErrorAction SilentlyContinue)) { throw $tool[1] }
}
if (-not (Get-Command $Adb -ErrorAction SilentlyContinue)) {
    throw "adb not found. Install Android platform-tools ('winget install Google.PlatformTools') or pass -Adb <path to adb.exe>."
}

# The port is checked against one game version; another one may fail to patch or misbehave.
$releaseInfo = Join-Path $GameDir "release_info.json"
if (Test-Path $releaseInfo) {
    $version = (Get-Content $releaseInfo -Raw | ConvertFrom-Json).version
    if ($version -ne $TestedGameVersion) {
        Write-Warning "This game is $version; the port was tested with $TestedGameVersion. It may fail to patch or misbehave."
    }
}

Write-Host "Building overlay.pck..."
& python -I (Join-Path $here "build_overlay.py") --game-dir $GameDir --apk $Apk --out $OutDir
if ($LASTEXITCODE -ne 0) { throw "build_overlay.py failed" }
$textures = Join-Path $OutDir "textures_astc.pck"
$withTextures = Test-Path $Godot
if ($withTextures) {
    Write-Host "Building textures_astc.pck (first run converts ~1,200 textures; later runs use the cache)..."
    & python -I (Join-Path $here "build_textures.py") --game-dir $GameDir --out $OutDir --godot $Godot
    if ($LASTEXITCODE -ne 0) { throw "build_textures.py failed" }
} else {
    Write-Warning ("Godot 4.5.1 .NET not found at '$Godot': skipping the phone texture pack. The game runs without it, " +
        "using more memory. To build it, install Godot 4.5.1 .NET and pass -Godot <path to its console exe>.")
}

$devices = Invoke-Adb devices | Select-String "`tdevice$"
if (-not $devices) { throw "No phone found by adb. Plug it in, enable USB debugging and accept the prompt on the phone." }
if (@($devices).Count -gt 1) { throw "More than one device connected; unplug the others (or close the emulator)." }

if ($InstallApk) {
    Write-Host "Installing $Apk..."
    Invoke-Adb install -r $Apk | Select-Object -Last 1
    if ($LASTEXITCODE -ne 0) { throw "APK install failed. If it says the signatures don't match, uninstall the old app first." }
}

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

# The texture pack is rebuilt from the cache each time; push it only when its content differs from the phone's copy.
if (-not $withTextures) {
    Write-Host "Done (without the texture pack). Files are in $Remote"
    exit 0
}
$localHash = (Get-FileHash $textures -Algorithm SHA1).Hash.ToLowerInvariant()
$remoteHash = "$(Invoke-Adb shell "sha1sum '$Remote/textures_astc.pck' 2>/dev/null")".Split(" ")[0]
if ($remoteHash -ne $localHash) {
    Write-Host "Pushing textures_astc.pck ($([math]::Round((Get-Item $textures).Length / 1MB)) MB)..."
    Invoke-Adb push $textures "$Remote/textures_astc.pck"
    if ($LASTEXITCODE -ne 0) { throw "adb push of textures_astc.pck failed" }
} else {
    Write-Host "textures_astc.pck already on the phone (same content), skipped."
}
Write-Host "Done. Files are in $Remote"
