# STS2 Android port

Personal, offline Android port of **Slay the Spire 2** for people who own the game. This repo contains only
original code (a Godot Android shell, stubs, Harmony patches, scripts and docs). It contains **no game files**:
you copy your own `SlayTheSpire2.pck` and `sts2.dll` from your Steam install to your phone with
`scripts/push-game.ps1`.

Status: **playable on a Pixel 9a** (Android 17, Mali-G715): main menu, Spine animations, FMOD audio,
character select, map, combat (drag a card onto an enemy plays it), card rewards, settings and saving across
restarts (Continue resumes the run) and the port's touch layer (tap, drag, long-press = inspect, tap-to-inspect
plus a confirm button on pick screens) all work. Not yet: texture/performance work.

## Android behaviour (tested on device)
| Situation | Behaviour |
|---|---|
| Back button / gesture | Acts as Escape: opens the pause menu, a second Back closes it. The app never quits on Back (`quit_on_go_back = false` in the overlay). |
| Home / app switch | Settings, prefs and progress are flushed on pause (Sts2Patcher "Save on pause"); runs auto-save as usual. Continue resumes after the app is killed. |
| Rotation | Landscape and reverse landscape both work; touch stays aligned after a flip. |
| Screen shape | New installs default to the **Auto** aspect ratio, which fills a 20:9 screen without stretching. An existing choice in Settings is never overridden. |
| Network | The APK has no INTERNET permission: no metrics, crash reports or multiplayer leave the phone. |
| Touch | Own touch layer in `boot.gd` (Godot's touch-to-mouse emulation is off). Tap = left click, held a few frames so quick taps register; drag = left drag (cards onto enemies, map scrolling); long-press (0.45 s, finger still) = right click, which opens the inspect screen for a card and never picks it up. Works in the pause menu too. Wait for the hand to settle between card plays, otherwise a tap can pick up the wrong card. |
| Picks (tick) | Anything taken the moment it's clicked: card rewards, choose-a-card/relic, treasure relics, shop cards, relics and potions. A tap is the game's own right-click inspect (inspect screen, or the tooltip) and the game's confirm tick slides in at the right edge; the tick replays a real left click on the item. Back or tapping elsewhere cancels. Screens with their own preview + confirm (deck upgrade/remove/transform, bundles) keep tap = click. |
| Dev console | `scripts\dev-console.ps1 -On -Restart` turns on the game's full console (it creates a `dev_console` file next to the packs; the boot script then sets `full_console` in settings.save, and removes it again once the file is gone). `-Run "gold 200; room shop"` types commands into it; `-Off` turns it off. Used for testing instead of playing to a screen. |
| Frame pacing | Swappy is turned off in the overlay: with it on, about one launch in three froze before the first frame. |

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
| Save on pause | The game writes settings/prefs/progress/profile only in `NGame.Quit()` (window close). Android kills background apps without that, so in-memory changes were lost (the Early Access disclaimer reappeared every launch). `_Notification` now also flushes those saves on `NOTIFICATION_APPLICATION_PAUSED` (2015). |

## Known issues
- Treasure room: the tick overlapped the tip of the Proceed/Skip arrow. It is now lifted above any visible arrow
  (unit-tested on the PC with the game's real positions; not yet seen on the phone).
- Once, tapping a potion's Drink right after opening its menu didn't drink it; the same taps worked on the next
  try. Not reproduced yet.
- Debug builds show Android's "not 16 KB-aligned" notice for some third-party native libs (Mono runtime,
  Spine). Harmless on this phone (4 KB pages); revisit for release builds.
- Debug builds use FMOD's logging libraries; time to main menu is ~19 s (10 s without FMOD).
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
- `scripts\dev-console.ps1 [-On|-Off] [-Restart] [-Run "cmd; cmd"]` — the game's dev console on the phone, for testing.
- `python -I scripts/spikes/pck_list.py <pck> <outdir>` — list a pck's files and header (read-only).
- `python -I scripts/spikes/pck_extract.py <pck> <outdir> <regex>` — extract matching files (read-only).
- `python -I scripts/spikes/project_binary.py <project.binary>` — dump project settings.
