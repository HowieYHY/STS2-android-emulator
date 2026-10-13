<#
.SYNOPSIS
  Publishes a new APK release on GitHub, which the phone installs as an in-place update (e.g. with Obtainium).

.DESCRIPTION
  The APK carries the port's own code (boot.gd, in port.pck; see overlay\android_boot\port_loader.gd), so a release
  ships touch/UI fixes to the phone without the PC. Changes to sts2.dll patches or a new STS2 version still need
  push-game.ps1, because those packs are built from the user's own game files and are never published.

  1. Refuses to run with uncommitted changes (a release is built from a commit).
  2. Bumps version/code by 1 and the patch number of version/name in shell\export_presets.cfg (or -Version), commits.
  3. Builds the signed release APK (build-apk.ps1 -Release; same key as before, so it updates in place).
  4. Checks the APK: its version, the port pack inside it, and that no game files are in it.
  5. Pushes the commit, tags v<version> and creates the GitHub release with the APK and SHA256SUMS.

.EXAMPLE
  scripts\release.ps1 -Notes "Fix the shop tick"
#>
param(
    [Parameter(Mandatory = $true)][string]$Notes,
    [string]$Version = "",  # default: patch + 1, e.g. 0.1.1 -> 0.1.2
    [string]$BuildTools = (Join-Path $(if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "D:\Android\sdk" }) "build-tools\35.0.1")
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Resolve-Path (Join-Path $here "..")
$presets = Join-Path $repo "shell\export_presets.cfg"
$apk = Join-Path $repo "build\sts2port.apk"

# Native tools write progress to stderr; Windows PowerShell 5.1 turns that into an error under "Stop".
function Invoke-Native {
    param([string]$Exe)
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { & $Exe @args 2>&1 | ForEach-Object { "$_" } } finally { $ErrorActionPreference = $prev }
    if ($LASTEXITCODE -ne 0) { throw "$Exe $args failed (exit $LASTEXITCODE)" }
}

if (Invoke-Native git -C $repo status --porcelain) { throw "Uncommitted changes: commit them first, a release is built from a commit." }

# 2. Version bump: edit only the two lines, then read them back.
$text = [System.IO.File]::ReadAllText($presets)
$code = [int]([regex]::Match($text, '(?m)^version/code=(\d+)').Groups[1].Value)
$name = [regex]::Match($text, '(?m)^version/name="([^"]+)"').Groups[1].Value
if (-not $Version) {
    $parts = $name.Split(".")
    $parts[-1] = [string]([int]$parts[-1] + 1)
    $Version = $parts -join "."
}
$text = [regex]::Replace($text, '(?m)^version/code=\d+', "version/code=$($code + 1)")
$text = [regex]::Replace($text, '(?m)^version/name="[^"]+"', "version/name=`"$Version`"")
[System.IO.File]::WriteAllText($presets, $text)
$check = [System.IO.File]::ReadAllText($presets)
if ($check -notmatch "(?m)^version/code=$($code + 1)\r?$" -or $check -notmatch "(?m)^version/name=`"$([regex]::Escape($Version))`"\r?$") {
    throw "Version bump didn't land in $presets"
}
Invoke-Native git -C $repo commit -q -m "Release $Version" -m "APK version $Version (code $($code + 1))." -- shell/export_presets.cfg | Out-Null
Write-Host "Version $name ($code) -> $Version ($($code + 1))"

# 3. Build. port.pck inside the APK stamps this commit.
& powershell -ExecutionPolicy Bypass -File (Join-Path $here "build-apk.ps1") -Release
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $apk)) { throw "APK build failed" }

# 4. Checks.
$badging = Invoke-Native (Join-Path $BuildTools "aapt2.exe") dump badging $apk | Select-Object -First 1
if ($badging -notmatch "versionCode='$($code + 1)'" -or $badging -notmatch "versionName='$([regex]::Escape($Version))'") {
    throw "APK reports '$badging', expected $Version ($($code + 1))"
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($apk)
try { $entries = @($zip.Entries | ForEach-Object FullName) } finally { $zip.Dispose() }
if ($entries -notcontains "assets/sts2port/port.pck") { throw "The APK has no assets/sts2port/port.pck" }
$game = $entries | Where-Object { $_ -match '(^|/)(sts2\.dll|SlayTheSpire2\.pck|overlay\.pck|textures_astc\.pck)$' }
if ($game) { throw "Game files in the APK, not publishing: $($game -join ', ')" }
Invoke-Native (Join-Path $BuildTools "apksigner.bat") verify $apk | Out-Null

# 5. Publish.
$tag = "v$Version"
$dist = Join-Path ([System.IO.Path]::GetTempPath()) "sts2port-release"
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory $dist | Out-Null
$asset = Join-Path $dist "sts2port-$Version-arm64.apk"
Copy-Item $apk $asset
$sha = (Get-FileHash $asset -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText((Join-Path $dist "SHA256SUMS"), "$sha  $(Split-Path $asset -Leaf)`n")
$body = @"
$Notes

APK version $Version (code $($code + 1)), arm64, signed with the same key as earlier builds: it updates the installed
app in place and keeps saves. It carries the port's own code; the game packs on the phone stay as they are.
Needs an overlay.pck from push-game.ps1 at or after the release that added port_loader.gd, otherwise the overlay's
older copy of the port code runs.
"@
Invoke-Native git -C $repo tag -a $tag -m "Android $Version" | Out-Null
Invoke-Native git -C $repo push -q origin HEAD $tag | Out-Null
Invoke-Native gh release create $tag $asset (Join-Path $dist "SHA256SUMS") --repo HowieYHY/STS2-android-emulator `
    --title "Android $Version" --notes $body --verify-tag
Remove-Item -Recurse -Force $dist
Write-Host "Released $tag"
