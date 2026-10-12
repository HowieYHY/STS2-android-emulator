# STS2 Android port

Personal, offline Android port of **Slay the Spire 2** for people who own the game. This repo contains only
original code (a Godot Android shell, stubs, Harmony patches, scripts and docs). It contains **no game files**:
you copy your own `SlayTheSpire2.pck` and `sts2.dll` from your Steam install to your phone with
`scripts/push-game.ps1`.

Status: **playable on a Pixel 9a** (Android 17, Mali-G715): main menu, Spine animations, FMOD audio,
character select, map, combat (drag a card onto an enemy plays it), card rewards, settings and saving across
restarts (Continue resumes the run) and the port's touch layer (tap, drag, long-press = inspect, tap-to-inspect
plus a confirm button on pick screens) all work, through the Act 1 boss into Act 2. Not yet: texture/performance work.

## Android behaviour (tested on device)
| Situation | Behaviour |
|---|---|
| Back button / gesture | Acts as Escape: opens the pause menu, a second Back closes it. The app never quits on Back (`quit_on_go_back = false` in the overlay). |
| Home / app switch | Settings, prefs and progress are flushed on pause (Sts2Patcher "Save on pause"); runs auto-save as usual. Continue resumes after the app is killed. |
| Rotation | Sensor landscape: turns 180° between landscape and reverse landscape with the phone's auto-rotate (no portrait, by choice); touch stays aligned after a flip. The game never sets an orientation, so the overlay sets `display/window/handheld/orientation` = 4; without it Godot's default (fixed landscape) replaced the APK's. |
| Screen shape | New installs default to the **Auto** aspect ratio, which fills a 20:9 screen without stretching. An existing choice in Settings is never overridden. |
| Settings | Tested on device: checkboxes, arrow selectors, sliders (drag), dropdowns, list scrolling (drag), Credits, Back closes screens. Fullscreen is forced and its tickbox hidden (Sts2Patcher "Fullscreen only"); windowed mode put the game under the system bars with touch misaligned. |
| Network | The APK has no INTERNET permission: no metrics, crash reports or multiplayer leave the phone. |
| Touch | Own touch layer in `boot.gd` (Godot's touch-to-mouse emulation is off). Tap = left click, held a few frames so quick taps register; drag = left drag (cards onto enemies, map scrolling); long-press (0.45 s, finger still) = right click, which opens the inspect screen for a card and never picks it up. Works in the pause menu too. Wait for the hand to settle between card plays, otherwise a tap can pick up the wrong card. |
| Picks (tick) | Anything taken the moment it's clicked: card rewards, choose-a-card/relic, shop cards, relics and potions, and event/Ancient options (incl. the next act's relic and Proceed). A tap is the game's own right-click inspect (inspect screen, or the tooltip) and the game's confirm tick slides in at the right edge; the tick replays a real left click on the item. Back or tapping elsewhere cancels. The treasure room's single relic is taken on tap (no tick). The tick moves above the Proceed/Skip arrow if a screen shows both. Screens with their own preview + confirm (deck upgrade/remove/transform, bundles) keep tap = click. |
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

| Intro logo tickbox | `NIntroLogoTickbox._Ready` never called `SetFromSettings()` (the game's other tickboxes do), so "Skip Intro Logo" always looked ticked while the logo still played. It now shows the saved value; the setting itself is untouched. |
| Fullscreen only | The Null platform reported `SupportedWindowMode.Any`; unticking Fullscreen on a phone left the game windowed under the system bars with touch offset (taps hit the wrong control, so it couldn't be ticked again). `NullPlatformUtilStrategy.GetSupportedWindowMode()` now returns `FullscreenOnly`, the game's own console mode: fullscreen is forced and the tickbox hidden. |

## Known issues
- Settings → Language: the two Chinese entries (中文, 繁體中文) are drawn with white blocks over them in the
  list (Japanese and Korean are fine). Not investigated yet; check whether Chinese text in-game is affected.
- Rooms entered with the dev console (`room treasure`...) aren't part of the saved map: after a restart the run
  resumes at the last real map node and anything gained there is gone. Expected; only matters for testing.
- Once, tapping a potion's Drink right after opening its menu didn't drink it; the same taps worked on the next
  try. Not reproduced in 3 later tries (including right after a card play).
- Debug builds show Android's "not 16 KB-aligned" notice for some third-party native libs (Mono runtime,
  Spine). Harmless on this phone (4 KB pages); revisit for release builds.
- Debug builds use FMOD's logging libraries; time to main menu is ~19 s (10 s without FMOD).
- `release_info.json` is only looked for next to the executable, which is read-only on Android: the version
  check for mods is skipped (harmless).
- Combat: while cards animate, frames drop to 50-75 ms (about 38 fps on average over those seconds; 60 fps when
  idle), and the first use of an effect in a session adds two ~140 ms frames. What's been measured (Pixel 9a,
  warm phone, thermal status "light"):
  - GPU 11-14 ms and render setup ~2 ms per frame: not a rendering problem.
  - Mono GC: no collections during any slow frame (Sts2Probe).
  - Mono JIT: 30-55 ms of the first-use frames is compiling the game's C# on first use (JitInfo). A background
    pre-compile of all 50k methods (`jit_warmup` flag) removed that JIT time but the slow frames stayed at
    120-145 ms, at a cost of ~36 s of CPU per launch and +110 MB, so it's off (experiment kept behind the flag).
  - Main thread CPU: ~70% busy, in Godot (39%), libc locks/allocator (19%) and Mono runtime (16%), running on
    the mid cores mostly at 650-1,300 MHz of 2,600. Godot's published Android symbols don't match the .NET
    template we use, so the hot functions can't be named without building that template with symbols.
- Startup ~16 s to the menu, 9.6 s of it the Mega Crit intro logo ("Skip Intro Logo" in Settings, off by choice).

## Performance (Pixel 9a, same scene before/after the ASTC texture pack)
| | Before | With `textures_astc.pck` |
|---|---|---|
| Textures converted on the CPU at load | 161 at boot, more on first use (each a hitch) | 0 |
| Video memory at the menu (after background loading) | 1,164 MB (textures 899 MB) | 679 MB (textures 415 MB) |
| App memory (PSS) in a run | 2.12 GB (graphics 1.52 GB) | 1.61 GB (graphics 1.00 GB) |
| Phone memory still available | ~0.43 GB | ~1.3 GB |
| Combat fps / spikes | ~38 fps animating, ~146 ms spikes | unchanged (not texture-bound, see Known issues) |

How it works: `scripts/build_textures.py` converts the 1,244 BC1/BC3/BC7 textures to ASTC 4x4 with
`tools/astc/transcode.gd` (Godot headless; padded to whole blocks and stored at the original size, because
Godot's encoder stretches odd sizes, which would shift atlas sprites), 57-63 dB PSNR against the originals, 94 s,
cached by content hash. Each texture's `.import` gets a `path.astc=` line, so Godot picks ASTC on phones that
support it. The 885 MB pack is pushed only when its SHA-1 changes; the game runs without it, just heavier.
Measure with an empty `perf_log` file next to the packs: boot.gd then logs fps/memory every 5 s and every frame
over 50 ms with its CPU/GPU split, and `tools/Sts2Probe` (called from NGame._Ready by Sts2Patcher; inert without
the flag) logs the GC and JIT activity in each slow frame. CPU profiling works with
`adb shell simpleperf record --app com.howieyhy.sts2port ...` (the APK is profileable).


## Feasibility findings (game v0.111.0, Godot 4.5.1 .NET)

**Verdict: feasible, no hard blocker found.** The biggest unknowns are now runtime ones that only the phone can answer
(loading `sts2.dll` from outside the APK, Mono on arm64, memory use).

| Question | Finding | Impact |
|---|---|---|
| Is the `.pck` encrypted? | No. Pack format v3, flags `0x2` (relative file base only), 0 of 15,890 files encrypted. | Stock Godot can mount it. |
| Custom engine? | Exe says `4.5.1.m.14.mono.custom_build`, but its module list matches stock 4.5, every scene type is stock 4.5 (plus Spine/FMOD GDExtensions), and the shipped `GodotSharp.dll` is **byte-identical** to NuGet GodotSharp 4.5.1. | Stock Godot 4.5.1 .NET templates should run it. Any private C++ fixes the studio made are lost (unknown, probably minor). |
| Renderer | Project features include `Mobile`; ETC2/ASTC import is enabled. | Good fit for phones. |
| Textures | 1,244 textures are desktop BC formats (S3TC/BPTC, ~0.9 GB); no ASTC/ETC2 copies. Another 2,284 are WebP (decoded to RGBA8 on every platform). | Done: `textures_astc.pck` (see Performance). |
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
