# STS2 Android port

Personal, offline Android port of **Slay the Spire 2** for people who own the game. This repo contains only
original code (a Godot Android shell, stubs, Harmony patches, scripts and docs). It contains **no game files**:
you copy your own `SlayTheSpire2.pck` and `sts2.dll` from your Steam install to your phone with
`scripts/push-game.ps1`.

Status: **boots to the main menu on a Pixel 9a** (Android 17, Mali-G715). No Spine animations or audio yet
(plugins not built), no touch mapping yet.

## How it works

```
APK (this repo only)            phone: /sdcard/Android/data/com.howieyhy.sts2port/files/
  Godot 4.5.1 engine              overlay.pck        <- built on your PC by push-game.ps1
  .NET (Mono) runtime                .NET assemblies: Android runtime (from the APK) + your sts2.dll
  launch args:                         (patched copy) + its managed deps
    --main-pack .../overlay.pck      game's startup config, project.binary with our boot autoload first
    --force-steam off                android_boot/boot.gd (mounts SlayTheSpire2.pck, fixes language)
                                  SlayTheSpire2.pck  <- your file, unchanged
```

Godot on Android loads C# assemblies from `res://.godot/mono/publish/arm64/` through its own file system,
so they can live in a pack on the phone instead of inside the APK.

## Usage

```powershell
powershell -ExecutionPolicy Bypass -File scripts\fetch-plugins.ps1   # once: official spine-godot 4.2 build (SHA-256 pinned)
powershell -ExecutionPolicy Bypass -File scripts\build-apk.ps1   # builds build\sts2port.apk (repo code only)
adb install -r build\sts2port.apk
powershell -ExecutionPolicy Bypass -File scripts\push-game.ps1 -GameDir "D:\Steam\steamapps\common\Slay the Spire 2"
```
`push-game.ps1` patches a copy of `sts2.dll` (into `%LOCALAPPDATA%\sts2port`), builds `overlay.pck` and pushes
both packs. The 1.9 GB pack is only re-sent when its size changes.

## Patches to sts2.dll (tools/Sts2Patcher)

Applied to a copy with Mono.Cecil; each one checks the code shape and fails loudly after a game update.
| Patch | Why |
|---|---|
| ModelDb lazy init | Mono runs `beforefieldinit` static initialisers when an instance is created, CoreCLR only on first static field read. Models with static fields that call ModelDb (e.g. `BowlbugsNormal`) then ran mid-`ModelDb.Init` and crashed startup. `Get<T>` now creates missing models on demand. |

## Known issues
- `release_info.json` is only looked for next to the executable, which is read-only on Android: the version
  check for mods is skipped (harmless).
- 1,244 BC textures are decompressed on the CPU (Mali has no BC): first "Common" preload takes ~40 s in the
  background and VRAM reaches ~500 MB at the main menu.


## Feasibility findings (game v0.111.0, Godot 4.5.1 .NET)

**Verdict: feasible, no hard blocker found.** The biggest unknowns are now runtime ones that only the phone can answer
(loading `sts2.dll` from outside the APK, Mono on arm64, memory use).

| Question | Finding | Impact |
|---|---|---|
| Is the `.pck` encrypted? | No. Pack format v3, flags `0x2` (relative file base only), 0 of 15,890 files encrypted. | Stock Godot can mount it. |
| Custom engine? | Exe says `4.5.1.m.14.mono.custom_build`, but its module list matches stock 4.5, every scene type is stock 4.5 (plus Spine/FMOD GDExtensions), and the shipped `GodotSharp.dll` is **byte-identical** to NuGet GodotSharp 4.5.1. | Stock Godot 4.5.1 .NET templates should run it. Any private C++ fixes the studio made are lost (unknown, probably minor). |
| Renderer | Project features include `Mobile`; ETC2/ASTC import is enabled. | Good fit for phones. |
| Textures | 1,244 textures are desktop BC formats (S3TC/BPTC, ~1.2 GB); no ASTC/ETC2 copies. | GPUs without BC support make Godot decompress them on the CPU: works, but costs RAM and load time. Optional later fix: transcode to ASTC on the PC into an overlay pack. |
| FMOD | utopia-rise `fmod-gdextension`, FMOD **2.03.06**; its `.gdextension` already lists Android arm64 paths. Banks are `banks/desktop` (platform-neutral format). | Needs the addon built for Android + FMOD 2.03.06 Android libs (free FMOD account download). |
| Spine | Official `spine_godot` GDExtension, skeleton data **4.2** (editor 4.2.03); `.gdextension` lists Android arm64 paths. | Use spine-godot 4.2 built for Godot 4.5 / Android arm64. |
| Steam | Behind a platform layer with a `Null` implementation. The game has a launch flag **`--force-steam off`** that skips Steam and runs on the Null platform (local saves, no cloud/achievements/leaderboards). | Pass `--force-steam off` via the export's command-line args. Steamworks.NET is still referenced, so its `steam_api` P/Invokes must never be hit (they aren't on the Null path). |
| Sentry | `SentryBootstrap.cs` autoload; Sentry is skipped when the project DSN is empty. No Android native lib. | Override `sentry/config/dsn` to empty. No crash reports leave the phone. |
| DXGI (Vortice) | Used only in `OsDebugInfo` (system-info logging). | Guard or patch out; harmless otherwise. |
| P/Invoke | No `[DllImport]` in `sts2.dll` itself. One `Process.Start` (git helper, editor-only). | Nothing else Windows-native in game logic. |
| Harmony | Only used by the game's own mod loader (`mods/` folder). | We avoid needing Harmony: touch input and fixes can live in our shell's own nodes. Harmony on Mono arm64 is unproven, so it's a fallback, not the plan. |

### Main remaining risks
1. **Loading `sts2.dll` from the phone's storage** instead of compiling it into the APK. Plan: the shell's own
   assembly loads it at startup and registers its script classes with Godot's C# bridge. If that proves impossible,
   fallback is building the APK locally *with* your own `sts2.dll` (never committed or shared).
2. **Mono on Android vs CoreCLR on desktop**: the game runs on CoreCLR; Godot Android uses Mono. Rare API differences
   may surface at runtime.
3. **Memory**: 1.9 GB pack plus CPU-decompressed BC textures on a phone.
4. **Game updates** may need the port re-checked.

## Build machine setup (Windows)

| Tool | Version | Location |
|---|---|---|
| .NET SDK | 9.0.318 | winget `Microsoft.DotNet.SDK.9` |
| JDK | Microsoft OpenJDK 17.0.20.1 (portable zip) | `D:\Tools\JDK17` (`JAVA_HOME`) |
| Android SDK | cmdline-tools, platform-tools, build-tools 35.0.1, android-35, NDK 28.1.13356709, CMake 3.10.2 | `D:\Android\sdk` (`ANDROID_HOME`) |
| Godot | 4.5.1-stable .NET (official, commit f62fdbde1) + export templates, self-contained (`._sc_`) | `D:\Tools\Godot` (templates in `editor_data\export_templates`) |

The MSI build of the JDK ignores winget's `--location`, so use the portable zip to keep it on D:.

## Tools
- `python -I scripts/spikes/pck_list.py <pck> <outdir>` — list a pck's files and header (read-only).
- `python -I scripts/spikes/pck_extract.py <pck> <outdir> <regex>` — extract matching files (read-only).
- `python -I scripts/spikes/project_binary.py <project.binary>` — dump project settings.
