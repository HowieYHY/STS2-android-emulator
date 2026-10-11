<#
.SYNOPSIS
  Downloads the third-party GDExtension plugins the APK needs into shell\addons (gitignored).

.DESCRIPTION
  Spine: Esoteric Software's official spine-godot 4.2 GDExtension build for Godot 4.5.1 (matches the game's
  Spine 4.2 data). Verified against a pinned SHA-256 so a changed upload is noticed, not silently used.
  These binaries are never committed; run this once after cloning, then scripts\build-apk.ps1.
#>
$ErrorActionPreference = "Stop"
$shell = Join-Path $PSScriptRoot "..\shell"

$SpineUrl = "https://spine-godot.s3.eu-central-1.amazonaws.com/4.2/4.5.1-stable/spine-godot-extension-4.2-4.5.1-stable.zip"
$SpineSha256 = "47c823a47373374530443c71e6d827df1dd6d441390d95c7cea31c54bc64ee57"

$tmp = Join-Path ([IO.Path]::GetTempPath()) "sts2port-plugins"
New-Item -ItemType Directory -Force $tmp | Out-Null
$zip = Join-Path $tmp "spine.zip"
Write-Host "Downloading spine-godot 4.2 for Godot 4.5.1..."
Invoke-WebRequest -Uri $SpineUrl -OutFile $zip -UseBasicParsing
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
if ($hash -ne $SpineSha256) { throw "spine zip SHA-256 mismatch: got $hash, expected $SpineSha256" }

# The game's own .gdextension lives at res://addons/spine/ with libraries relative to it (android/..., windows/...),
# so unpack the zip's bin/ folder there.
$dest = Join-Path $shell "addons\spine"
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
$x = Join-Path $tmp "spine"
if (Test-Path $x) { Remove-Item -Recurse -Force $x }
Expand-Archive -Path $zip -DestinationPath $x
New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
Move-Item (Join-Path $x "bin") $dest
Write-Host "Spine plugin ready in $dest"

# FMOD: utopia-rise fmod-gdextension 6.1.0 for Godot 4.5. Its Windows plugin DLL is byte-identical to the one the
# game ships, so this is the game's exact addon version. The release bundles FMOD's own Android libraries
# (libfmod.so, libfmodstudio.so) and the Android plugin .aar that runs FMOD's Java init.
$FmodUrl = "https://github.com/utopia-rise/fmod-gdextension/releases/download/6.1.0-4.5.0/addons.zip"
$FmodSha256 = "8796f6cd1cb38bf7ff4da2648f8af2695244ffdb80a7ac4ab8a171ca44895713"
$zip = Join-Path $tmp "fmod.zip"
Write-Host "Downloading fmod-gdextension 6.1.0 for Godot 4.5..."
Invoke-WebRequest -Uri $FmodUrl -OutFile $zip -UseBasicParsing
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
if ($hash -ne $FmodSha256) { throw "fmod zip SHA-256 mismatch: got $hash, expected $FmodSha256" }
$dest = Join-Path $shell "addons\fmod"
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
$x = Join-Path $tmp "fmod"
if (Test-Path $x) { Remove-Item -Recurse -Force $x }
Expand-Archive -Path $zip -DestinationPath $x
Move-Item (Join-Path $x "fmod") $dest
Write-Host "FMOD plugin ready in $dest"
