<#
.SYNOPSIS
  One-step setup of the STS2 Android port: installs the tools, finds your Slay the Spire 2 install,
  downloads the latest APK and puts everything on the phone. Run it via install.cmd (double-click).
  Re-run it after a new Slay the Spire 2 version. No game files leave your PC and none are downloaded.
#>
param(
    [string]$GameDir = "",
    [string]$Repo = "HowieYHY/STS2-android-emulator",
    [switch]$CheckOnly   # test run: do everything except copying to the phone
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Step($m) { Write-Host ""; Write-Host "== $m" -ForegroundColor Cyan }
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}
function Test-Python {
    $c = Get-Command python -ErrorAction SilentlyContinue
    if (-not $c) { return $false }
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { $out = & python --version 2>&1 | Out-String } finally { $ErrorActionPreference = $prev }
    return ($out -match "Python 3")   # the Windows Store stub prints something else
}
function Test-Dotnet9 {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { return $false }
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { $sdks = & dotnet --list-sdks 2>&1 | Out-String } finally { $ErrorActionPreference = $prev }
    return ($sdks -match "(?m)^(9|1\d)\.")
}
function Find-Adb {
    $c = Get-Command adb -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    if ($env:ANDROID_HOME) {
        $e = Join-Path (Join-Path $env:ANDROID_HOME "platform-tools") "adb.exe"
        if (Test-Path $e) { return $e }
    }
    $pkgs = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path $pkgs) {
        $f = Get-ChildItem $pkgs -Recurse -Filter adb.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    return $null
}
function Install-Tool($id, $name) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Windows Package Manager (winget) was not found, so $name can't be installed automatically. Install it by hand ($id), then run this again."
    }
    Write-Host "Installing $name (a Windows prompt may ask for permission)..."
    & winget install -e --id $id --accept-package-agreements --accept-source-agreements
    Refresh-Path
}
function Find-GameDir {
    $roots = @()
    foreach ($k in @("HKCU:\Software\Valve\Steam", "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam", "HKLM:\SOFTWARE\Valve\Steam")) {
        try {
            $p = Get-ItemProperty $k -ErrorAction Stop
            foreach ($n in @("SteamPath", "InstallPath")) { if ($p.$n) { $roots += ($p.$n -replace "/", "\") } }
        } catch {}
    }
    $libs = @()
    foreach ($r in $roots) {
        $libs += $r
        $vdf = Join-Path $r "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $libs += ($m.Groups[1].Value -replace "\\\\", "\")
            }
        }
    }
    foreach ($l in ($libs | Select-Object -Unique)) {
        $g = Join-Path $l "steamapps\common\Slay the Spire 2"
        if (Test-Path (Join-Path $g "SlayTheSpire2.pck")) { return $g }
    }
    return $null
}

Write-Host "STS2 Android port: setup" -ForegroundColor Green
Write-Host "Needs: your own Slay the Spire 2 on Steam, and your phone with USB debugging on (cable plugged in)."

# 1. Tools
Step "1/4 Tools"
if (-not (Test-Python)) { Install-Tool "Python.Python.3.12" "Python 3" }
if (-not (Test-Python)) { throw "Python 3 is installed but not found yet. Close this window and run install.cmd again." }
if (-not (Test-Dotnet9)) { Install-Tool "Microsoft.DotNet.SDK.9" ".NET 9 SDK" }
if (-not (Test-Dotnet9)) { throw ".NET 9 is installed but not found yet. Close this window and run install.cmd again." }
$adb = Find-Adb
if (-not $adb) { Install-Tool "Google.PlatformTools" "Android platform-tools"; $adb = Find-Adb }
if (-not $adb) { throw "adb (Android platform-tools) is installed but not found yet. Close this window and run install.cmd again." }
Write-Host "Python, .NET 9 and adb are ready."

# 2. Game
Step "2/4 Slay the Spire 2"
if (-not $GameDir) { $GameDir = Find-GameDir }
if (-not $GameDir) {
    Write-Host "Couldn't find it in Steam automatically."
    $GameDir = (Read-Host "Paste the folder that contains SlayTheSpire2.pck").Trim('"', ' ')
}
if (-not (Test-Path (Join-Path $GameDir "SlayTheSpire2.pck"))) { throw "SlayTheSpire2.pck is not in '$GameDir'." }
Write-Host "Found: $GameDir"

# 3. Phone
Step "3/4 Phone"
$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
& $adb start-server 2>&1 | Out-Null
$ErrorActionPreference = $prev
$deadline = (Get-Date).AddMinutes(3)
while ($true) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $lines = (& $adb devices 2>&1 | ForEach-Object { "$_" })
    $ErrorActionPreference = $prev
    $ok = @($lines | Where-Object { $_ -match "`tdevice$" })
    $unauth = @($lines | Where-Object { $_ -match "`tunauthorized$" })
    if ($ok.Count -eq 1) { break }
    if ($ok.Count -gt 1) { throw "More than one phone/emulator is connected. Unplug the others and run this again." }
    if ((Get-Date) -gt $deadline) { throw "No phone found. Turn on USB debugging (Settings > Developer options), plug the cable in and accept the prompt on the phone." }
    if ($unauth.Count) { Write-Host "Look at the phone and tap 'Allow USB debugging'..." } else { Write-Host "Waiting for the phone (USB debugging on, cable plugged in)..." }
    Start-Sleep -Seconds 4
}
Write-Host "Phone connected."

# 4. APK + push
Step "4/4 Installing"
$apkFile = Get-ChildItem $here -Filter "sts2port-*-arm64.apk" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($apkFile) {
    $apk = $apkFile.FullName
    Write-Host "Using the APK already in this folder: $apk"
} else {
    Write-Host "Downloading the latest APK from GitHub..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ "User-Agent" = "sts2port-install" }
    $asset = $rel.assets | Where-Object { $_.name -like "*-arm64.apk" } | Select-Object -First 1
    if (-not $asset) { throw "No APK found in the latest release." }
    $dest = Join-Path $env:LOCALAPPDATA "sts2port\download"
    New-Item -ItemType Directory -Force $dest | Out-Null
    $apk = Join-Path $dest $asset.name
    Invoke-WebRequest $asset.browser_download_url -OutFile $apk -UseBasicParsing
    Write-Host "Downloaded $($asset.name)"
}

if ($CheckOnly) { Write-Host ""; Write-Host "Check only: stopped before copying to the phone. APK: $apk" -ForegroundColor Yellow; return }
Write-Host "Copying to the phone (the first time this takes several minutes: the game is about 2 GB)..."
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here "scripts\push-game.ps1") -GameDir $GameDir -Apk $apk -Adb $adb -InstallApk
if ($LASTEXITCODE -ne 0) { throw "Copying failed (see the message above)." }

Write-Host ""
Write-Host "Done. Open 'Slay the Spire 2' on your phone (the first start takes about 20 seconds)." -ForegroundColor Green
