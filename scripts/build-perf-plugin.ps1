<#
.SYNOPSIS
  Builds tools\android-perf-plugin into shell\addons\sts2port_android\libs\sts2port-perf.aar (gitignored).

.DESCRIPTION
  The plugin is one Java class, so instead of a Gradle library project it is compiled with javac against the SDK's
  android.jar and Godot's own godot-lib (from the installed Android build template), then packaged by hand:
  an .aar is a zip holding AndroidManifest.xml, classes.jar and R.txt. It also carries assets/sts2port/port.pck
  (the port's own code, scripts\build_port_pack.py), which Gradle merges into the APK's assets.
  Needs the Android build template (run scripts\build-apk.ps1 once).
#>
param(
    [string]$Jdk = $(if ($env:JAVA_HOME) { $env:JAVA_HOME } else { "D:\Tools\JDK17" }),
    [string]$AndroidJar = $(Join-Path $(if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "D:\Android\sdk" }) "platforms\android-35\android.jar")
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $here "..\tools\android-perf-plugin"
$godotAar = Join-Path $here "..\shell\android\build\libs\release\godot-lib.template_release.aar"
$outAar = Join-Path $here "..\shell\addons\sts2port_android\libs\sts2port-perf.aar"
if (-not (Test-Path $godotAar)) { throw "Godot's Android build template is missing: run scripts\build-apk.ps1 once first." }
if (-not (Test-Path $AndroidJar)) { throw "android.jar not found at $AndroidJar" }

$work = Join-Path ([System.IO.Path]::GetTempPath()) "sts2port-perf-build"
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Force "$work\godot", "$work\classes", "$work\aar" | Out-Null

# Godot's classes, to compile against (not packaged).
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $godotAar))
try { [System.IO.Compression.ZipFileExtensions]::ExtractToFile(($zip.Entries | Where-Object FullName -eq "classes.jar"), "$work\godot\classes.jar") }
finally { $zip.Dispose() }

$sources = @(Get-ChildItem -Recurse (Join-Path $src "src") -Filter *.java | ForEach-Object FullName)
& (Join-Path $Jdk "bin\javac.exe") --release 11 -cp "$AndroidJar;$work\godot\classes.jar" -d "$work\classes" @sources
if ($LASTEXITCODE -ne 0) { throw "javac failed" }
& (Join-Path $Jdk "bin\jar.exe") --create --file "$work\aar\classes.jar" -C "$work\classes" .
if ($LASTEXITCODE -ne 0) { throw "jar failed" }
Copy-Item (Join-Path $src "AndroidManifest.xml") "$work\aar\AndroidManifest.xml"
Set-Content -Path "$work\aar\R.txt" -Value "" -NoNewline
& python -I (Join-Path $here "build_port_pack.py") --out "$work\aar\assets\sts2port\port.pck"
if ($LASTEXITCODE -ne 0) { throw "build_port_pack.py failed" }

New-Item -ItemType Directory -Force (Split-Path $outAar) | Out-Null
if (Test-Path $outAar) { Remove-Item $outAar }
[System.IO.Compression.ZipFile]::CreateFromDirectory("$work\aar", (Join-Path (Resolve-Path (Split-Path $outAar)) (Split-Path $outAar -Leaf)))
Remove-Item -Recurse -Force $work
Write-Host "Built $(Resolve-Path $outAar)"
