# STS2 Android port

Personal, offline Android port of **Slay the Spire 2** for people who own the game. This repo contains only
original code (a Godot Android shell, stubs, Harmony patches, scripts and docs). It contains **no game files**:
you copy your own `SlayTheSpire2.pck` and `sts2.dll` from your Steam install to your phone with
`scripts/push-game.ps1`.

Status: **playable on a Pixel 9a** (Android 17, Mali-G715): main menu, Spine animations, FMOD audio,
character select, map, combat (drag a card onto an enemy plays it), card rewards, settings and saving across
restarts (Continue resumes the run) and the port's touch layer (tap, drag, long-press = inspect, tap-to-inspect
plus a confirm button on pick screens) all work, through the Act 1 boss into Act 2. ASTC textures reduce memory use,
and Android performance hints are enabled; combat frame-time spikes remain (see Known issues).

## STS2 game version

The current reference game is **v0.111.0**, commit `41cef1ea`, branch `v0.111.0`, verified on
**17 October 2026** from `D:\Steam\steamapps\common\Slay the Spire 2\release_info.json` (the overlay pushed that day
was built from it, and the in-game corner label shows it; also verified 14 October 2026 from `C:\Program Files (x86)\Steam\...` on the second PC).
This is the STS2 game version; the Android port's APK version is tracked separately below.

Whenever work involves inspecting or patching game files, rebuilding or pushing the overlay/texture packs,
testing the game, or updating compatibility documentation, re-read `release_info.json` from the actual
`-GameDir` used. Update the current game version, commit, branch, source and verification date here and in
`CLAUDE.md` in the same change. If the phone uses a different build, record its verified version separately.
Keep the original version labels on historical findings and measurements; only mark a newer version as
tested after checking it. If the version cannot be verified, say so and retain the last verified record.

## Latest device verification (13 October 2026)

The port's **0.1.0 release build** (version code 1, arm64) is installed on the Pixel 9a. It appears in Android as
**Slay the Spire 2**, with original spire artwork for the legacy, adaptive and monochrome launcher icons.
The artwork and its generator live in `shell/icons/` and `tools/icon/make_icon.py`.

Game build used for these device checks: **STS2 v0.111.0**, commit `41cef1ea`.

- Verified the Gradle `monoRelease` output and that the APK is not debuggable.
- Verified the APK's v2 signature and 16 KB ZIP alignment. Release builds use the existing local debug key
  for this personal installation, allowing an in-place update that retains saves.
- Installed with `adb install --no-incremental -r build\sts2port.apk`; checked the installed icon and title
  in Android's App info, and confirmed the game reaches the main menu after a cold restart.
- Reset Profile 1 through the game's profile deletion screen at the owner's request. Profiles 2 and 3 were
  already empty. Selected a fresh Profile 1 and confirmed after a cold restart that the menu offers
  Singleplayer with no Continue/Abandon Run options.
- Fixed a touch offset after changing the aspect ratio: taps could miss the displayed controls and prevent
  changing the ratio back. The touch layer now converts its viewport coordinates back to window coordinates
  before sending mouse events, so Godot applies scaling and letterbox offsets once. Installed the updated
  overlay and verified the dropdown at its visible position in Auto, 4:3, 16:10, 16:9 and 21:9 on the phone.
  Restored Auto and verified it stays selected after a cold restart. Headless regression checks cover taps,
  drags, long presses, mouse-button state and queued events during a transform change; the original code
  fails these checks and the fix passes.

## Emulator verification (13 October 2026): touch fixes for issues #1-#5

Deployed to the Pixel 9a the same day: APK 0.1.1 (the v0.1.1 release) and the overlay with `port_loader.gd`, from
STS2 v0.111.0 (`41cef1ea`). It loads the port code from the APK and reaches the menu with the saved run intact. Then
retested #1-#5 on the phone with the dev console (on Profile 2, so the owner's run was untouched): three 13-tap
shop bursts bought nothing; the tick sits at the normal confirm spot and bought exactly the inspected card; tick to
"obtained" 114 ms; hand-card taps don't pick cards up, dragging plays them; event and Ancient options are chosen on
tap and a long-press only highlights. Tested first on an Android emulator: an API 34 x86_64 Google APIs image (runs the arm64 APK
through Android's ARM translation) with the Pixel 9a's 1080x2424 screen, the 0.1.0 APK, and packs built from
**STS2 v0.111.0**, commit `41cef1ea`. Each change was A/B-tested against the previous overlay on the same screen.

- **#2 Fast taps in the shop bought items.** Three timing holes in the touch layer: a second tap judged by the first
  tap's hover; a tap decided before the previous tap's inspect screen had opened (the tick then bought a different
  item from the one on display); and a tap on an inspect screen's popup while it faded out, delivered after it hid
  (a plain click on the shop item underneath). Taps are now decided only after earlier clicks have landed and hover
  has settled. A closing inspect screen lets taps through at once, and a tap whose hover can't be trusted hovers
  again (or does nothing). Three 13-tap bursts across shop items: old overlay spent 306 gold, new overlay none.
- **#3 Tick too high.** The tick lifted itself above Proceed/Skip arrows that were disabled and slid off screen.
  It now sits at the game's own confirm position unless an enabled arrow is on screen there.
- **#5 Tick slow.** The tick waited for the inspect screen's 0.25 s fade before clicking. It now clicks through
  it straight away: 498 ms -> 230 ms from tick to "obtained" on the emulator.
- **#4 Tapping a hand card picked it up.** That was the game's PC click-to-play. In combat a tap on a hand card now
  only hovers it while the finger is down; cards are played by dragging. The hand's own selection modes (choose a
  card to upgrade, discard...) still take taps as clicks (tested with Armaments).
- **#1 Event options** no longer use the tick (owner's choice): a tap chooses, a long-press highlights the option
  and shows its tooltip.
- #6 (a crash after the Act 1 boss) didn't reproduce on the emulator through the boss, rewards, act change and
  Ancient. `scripts\crash-report.ps1` collects Android's records of the crash from the phone.
- `python -I scripts/test_touch.py` covers all of the above with headless checks that mimic Android's input
  buffering; the old code fails them and the new code passes.

## Android behaviour (tested on device)
| Situation | Behaviour |
|---|---|
| Back button / gesture | Acts as Escape: opens the pause menu, a second Back closes it. The app never quits on Back (`quit_on_go_back = false` in the overlay). |
| Home / app switch | Settings, prefs and progress are flushed on pause (Sts2Patcher "Save on pause"); runs auto-save as usual. Continue resumes after the app is killed. |
| Rotation | Sensor landscape: turns 180° between landscape and reverse landscape with the phone's auto-rotate (no portrait, by choice); touch stays aligned after a flip. The game never sets an orientation, so the overlay sets `display/window/handheld/orientation` = 4; without it Godot's default (fixed landscape) replaced the APK's. |
| Screen shape | New installs default to the **Auto** aspect ratio, which fills a 20:9 screen without stretching. An existing choice in Settings is never overridden. Changing aspect ratios keeps touch aligned, including black bars; tested the dropdown in Auto, 4:3, 16:10, 16:9 and 21:9. |
| Settings | Tested on device: checkboxes, arrow selectors, sliders (drag), dropdowns, list scrolling (drag), Credits, Back closes screens. Fullscreen is forced and its tickbox hidden (Sts2Patcher "Fullscreen only"); windowed mode put the game under the system bars with touch misaligned. Settings that do nothing on a phone are greyed out, disabled and labelled "(not on Android)": Keyboard-Only Mode, Display Selection, Windowed Resolution, Window Resizing, Limit FPS in Background, Upload Gameplay Data, Send Feedback, VSync (the driver only has FIFO: Off and Adaptive log "not available, falling back to Enabled") and Long Press Confirmations (End Turn then needs a held left button, which touch never sends; it is also forced off). Measured on the phone, 13 Oct 2026: FPS Limit 30/59/60 give 30.0/59.0/60.0 fps, but values above 60 do nothing (Android holds the app to 60 Hz, `frameRateOverride`); MSAA 4x/8x add 40/80 MB of video memory (8x drops the menu to 43-48 fps); the four volume sliders reach FMOD exactly (slider² on `bus:/master`, `/music`, `/sfx`, `/ambience`). Not measurable: Mute in Background (no output metering), controller remapping (no controller). Controller remapping stays (Bluetooth controllers work). |
| Network | The APK has no INTERNET permission: no metrics, crash reports or multiplayer leave the phone. |
| Touch | Own touch layer in `boot.gd` (Godot's touch-to-mouse emulation is off). Tap = left click, held a few frames so quick taps register; drag = left drag (cards onto enemies, map scrolling); long-press (0.45 s, finger still) = right click, which opens the inspect screen for a card and never picks it up. Works in the pause menu too. In combat a tap on a hand card only hovers it while the finger is down (no click-to-play); in the hand's selection modes a tap selects. A tap is decided once earlier taps have landed and hover has settled, so fast taps can't act on the wrong control (emulator-tested). |
| Picks (tick) | Anything taken the moment it's clicked: card rewards, choose-a-card/relic, shop cards, relics and potions. A tap is the game's own right-click inspect (inspect screen, or the tooltip) and the game's confirm tick slides in at the right edge; the tick replays a real left click on the item, straight through the closing inspect screen. Back or tapping elsewhere cancels. The treasure room's single relic is taken on tap, and event/Ancient options are chosen on tap (long-press shows their tooltip): no tick. The tick moves above the Proceed/Skip arrow only if that arrow is enabled and on screen. Screens with their own preview + confirm (deck upgrade/remove/transform, bundles) keep tap = click. |
| Dev console | `scripts\dev-console.ps1 -On -Restart` turns on the game's full console (it creates a `dev_console` file next to the packs; the boot script then sets `full_console` in settings.save, and removes it again once the file is gone). `-Run "gold 200; room shop"` types commands into it; `-Off` turns it off. Used for testing instead of playing to a screen. |
| Frame pacing | Swappy is turned off in the overlay: with it on, about one launch in three froze before the first frame. |
| Version label | The game's small grey label in the top-right corner shows the game version and build date and the app's version, e.g. `v0.111.0` / `2026.08.13` / `Android 0.1.7` on the main menu, and `[v0.111.0] (2026.08.13) · Android 0.1.7` in a run. The game said `NONE` / `???` there on Android because it can't find its `release_info.json`; `build_overlay.py` copies it from the install the packs came from, so the label names the game build actually on the phone (a new STS2 version shows after the next `push-game.ps1`). Checked on the phone, 17 Oct 2026. |
| Language list | 中文 and 繁體中文 drew with white wedges over 文 and 繁. The Latin UI fonts (Kreon...) have no CJK glyphs, so Godot fell back to Android's `NotoSansCJK-Regular.ttc` and drew it with Kreon's MSDF setting, which can't handle that font's overlapping outlines (reproduced on the PC with the phone's font; the game's own CJK fonts are fine). boot.gd gives the list's fonts that system font as an explicit fallback with MSDF off. Checked on the phone, 17 Oct 2026. With Chinese as the game language the game switches to its own CJK fonts (FontManager), which draw cleanly on the PC; not tried on the phone. |

## How it works

```
APK (this repo only)            phone: /sdcard/Android/data/com.howieyhy.sts2port/files/
  Godot 4.5.1 engine              overlay.pck        <- built on your PC by push-game.ps1
  .NET (Mono) runtime                .NET assemblies: Android runtime (from the APK) + your sts2.dll
  launch args:                         (patched copy) + its managed deps
    --main-pack .../overlay.pck      game's startup config, project.binary with our autoloads first
    --force-steam off                android_boot/port_loader.gd, android_boot/boot.gd (fallback copy)
  port.pck (boot.gd) ------------> port.pck           <- copied out of the APK on every launch
                                  SlayTheSpire2.pck  <- your file, unchanged
                                  textures_astc.pck <- phone-format textures built on your PC (optional)
```

`port_loader.gd` runs first and mounts `port.pck` over the overlay, so `boot.gd` (touch, ticks, settings fixes:
the port's own code) comes from the installed APK. That's what lets an APK release update the port without the
PC. If the APK has no `port.pck`, the overlay's own copy of `boot.gd` runs.

Godot on Android loads C# assemblies from `res://.godot/mono/publish/arm64/` through its own file system,
so they can live in a pack on the phone instead of inside the APK.

## Setting it up on another phone (minimal)

Needs: your own STS2 on Steam (Windows; tested with v0.111.0, others warn and may fail), a 64-bit Android phone
(Android 7+, ~3 GB free), and on the PC Python 3, the .NET 9 SDK and Android platform-tools:
`winget install Python.Python.3.12 Microsoft.DotNet.SDK.9 Google.PlatformTools`. Godot is optional.

1. Phone: Settings → About phone → tap Build number 7 times; then Developer options → USB debugging on.
2. Download the source (Code → Download ZIP, or `git clone`) and the newest release's `sts2port-…-arm64.apk`.
3. Plug the phone in, accept "Allow USB debugging", and in the source folder run:
   `powershell -ExecutionPolicy Bypass -File scripts\push-game.ps1 -GameDir "<Steam>\steamapps\common\Slay the Spire 2" -Apk <downloaded apk> -InstallApk`
4. Open "Slay the Spire 2" on the phone (the first start takes ~20 s).

Without Godot 4.5.1 .NET the phone texture pack is skipped (a warning says so): the game runs but uses more memory
(tested on the Pixel 9a: menu reached normally, 2.1 GB). Updates then come through releases (see below).

No cable (Android 11+, PC and phone on the same Wi-Fi, or the phone on the PC's mobile hotspot): Developer options →
Wireless debugging → "Pair device with pairing code", then `adb pair <ip:port> <code>` and
`adb connect <ip:port shown at the top>` on the PC, and run step 3 as above. Tested 14 October 2026 on the PC's
mobile hotspot: a campus Wi-Fi blocked the PC from reaching the phone (pairing failed with "protocol fault"; adb's
log showed the connection timing out). The pairing port only listens while the pairing pop-up is open, and the
connect port changes when wireless debugging restarts (`adb mdns services` lists both). If adb lists the phone
twice (mDNS name and IP), `adb disconnect <ip:port>` or set `ANDROID_SERIAL`, or pushes fail half-way.

**Port code from the overlay** (no APK release): an empty file `port_code_overlay` next to the packs makes
`port_loader.gd` keep the overlay's own `boot.gd` instead of the APK's. Use it to test a `boot.gd` change on the phone,
or to ship one from a PC that doesn't have the release signing key: build the overlay (`build_overlay.py`, or
`push-game.ps1`), push it, then `adb shell touch .../files/port_code_overlay`. Delete the file to go back to the APK's
code (do that once a later APK release contains the fix). Used on 14 October 2026 for issue #7.

## Possible future changes

- **In-app setup, no PC tools (APK + copy two things).** A single APK with the game in it isn't an option: it would
  redistribute the game, which this project never does. Instead the APK could do `push-game.ps1`'s work on the phone:
  the user installs the release APK, copies `SlayTheSpire2.pck` and the game's `data_sts2_windows_x86_64` DLLs to
  the phone by any means (Drive, Quick Share, USB file transfer), and the app asks for them on first launch
  (Android file picker), checks the game version, patches `sts2.dll` and builds the overlay into its own folder.
  No Python, .NET, adb or developer mode. Work: run Sts2Patcher (C#, Mono.Cecil) inside the app's .NET runtime,
  port `build_overlay.py` to C#, add the picker; skip the ASTC texture pack (needs Godot's encoder). About a day
  plus phone testing. Risks: patching on the phone is untested, the 1.9 GB copy is still needed once, and an STS2
  update still needs a re-import. Deferred by the owner (13 Oct 2026); the Wi-Fi setup above covers "no cable".

## Updating the phone without the PC

Fixes to the port's own code ship as GitHub releases of the APK (`scripts\release.ps1`). The repo is private, so
the phone installs them with [Obtainium](https://github.com/ImranR98/Obtainium) and a read-only GitHub token:

1. On GitHub: Settings → Developer settings → Fine-grained tokens → Generate. Repository access: only
   `HowieYHY/STS2-android-emulator`; permissions: Contents **read-only**. Copy the token.
2. Install Obtainium on the phone (from its GitHub releases or F-Droid). In Obtainium's Settings, paste the token
   under the GitHub source's "Personal access token".
3. Add App → `https://github.com/HowieYHY/STS2-android-emulator`. Obtainium finds the latest release's APK and
   offers to install it over the existing app (same signing key: saves are kept).
4. From then on Obtainium checks for new releases and installs them (one tap, or in the background on Android 12+
   once it has installed the app itself).

The game app itself stays offline (no INTERNET permission); only Obtainium downloads.

Still done from the PC with `push-game.ps1`: a new STS2 version, changes to the sts2.dll patches
(`tools/Sts2Patcher`), or overlay settings (`build_overlay.py`). Those packs come from your own game files and are
never published. The first time, an overlay from `push-game.ps1` at or after the release that added
`port_loader.gd` is needed, or the overlay's older copy of `boot.gd` keeps running.

## Android APK prerelease

Download the signed arm64 APK from [v0.1.0-alpha.1](https://github.com/HowieYHY/STS2-android-emulator/releases/tag/v0.1.0-alpha.1).
The release includes `sts2port-0.1.0-alpha.1-arm64.apk` and `SHA256SUMS`; its APK version is `0.1.0`
(version code 1). Tested with **STS2 v0.111.0** (commit `41cef1ea`) on a Pixel 9a running Android 17.

The APK contains the Android shell, runtime and plugins. Build the game packs from your own Steam copy
using the source at the release tag and the setup below. To use the downloaded APK, pass its path to
`push-game.ps1` with `-Apk`; rebuilding the APK is optional. Existing installations also need the rebuilt
overlay to receive the aspect-ratio touch fix. The release notes include the exact commands.

## Usage

```powershell
powershell -ExecutionPolicy Bypass -File scripts\fetch-plugins.ps1   # once: official spine-godot 4.2 build (SHA-256 pinned)
powershell -ExecutionPolicy Bypass -File scripts\build-apk.ps1 -Release   # build\sts2port.apk (repo code only; builds the perf plugin first)
adb install --no-incremental -r build\sts2port.apk
powershell -ExecutionPolicy Bypass -File scripts\push-game.ps1 -GameDir "D:\Steam\steamapps\common\Slay the Spire 2"
```
`push-game.ps1` patches a copy of `sts2.dll` (into `%LOCALAPPDATA%\sts2port`), builds `overlay.pck` and
`textures_astc.pck`, and pushes all three packs. The 1.9 GB game pack is only re-sent when its size changes;
the texture pack is only re-sent when its SHA-1 changes. For an APK-only update, rebuild and install the APK;
the packs already on the phone can stay in place.

Changes to `overlay/android_boot/boot.gd`, including the aspect-ratio touch fix, require running
`push-game.ps1` again to rebuild and install `overlay.pck`; installing the APK alone does not update the overlay.

### Reset progress

From the main menu, tap the profile badge at the top left, tap the trash button under the populated profile,
and confirm **Delete**. This clears that profile's runs, histories, unlocks and local achievements while
retaining the installed game packs and global settings. Repeat for any other populated profiles, then select
an empty profile to start fresh. Press Home before stopping or restarting the app so the save-on-pause
patch flushes the new state.

## Patches to sts2.dll (tools/Sts2Patcher)

Applied to a copy with Mono.Cecil; each one checks the code shape and fails loudly after a game update.
| Patch | Why |
|---|---|
| ModelDb lazy init | Mono runs `beforefieldinit` static initialisers when an instance is created, CoreCLR only on first static field read. Models with static fields that call ModelDb (e.g. `BowlbugsNormal`) then ran mid-`ModelDb.Init` and crashed startup. `Get<T>` now creates missing models on demand. |
| Save on pause | The game writes settings/prefs/progress/profile only in `NGame.Quit()` (window close). Android kills background apps without that, so in-memory changes were lost (the Early Access disclaimer reappeared every launch). `_Notification` now also flushes those saves on `NOTIFICATION_APPLICATION_PAUSED` (2015). |

| Intro logo tickbox | `NIntroLogoTickbox._Ready` never called `SetFromSettings()` (the game's other tickboxes do), so "Skip Intro Logo" always looked ticked while the logo still played. It now shows the saved value; the setting itself is untouched. |
| Fullscreen only | The Null platform reported `SupportedWindowMode.Any`; unticking Fullscreen on a phone left the game windowed under the system bars with touch offset (taps hit the wrong control, so it couldn't be ticked again). `NullPlatformUtilStrategy.GetSupportedWindowMode()` now returns `FullscreenOnly`, the game's own console mode: fullscreen is forced and the tickbox hidden. |

## Known issues
- A crash after beating the Act 1 boss (issue #6, 13 Oct 02:19, on the 0.1.0 overlay): Android recorded it as
  SIGABRT in the foreground at 2.8 GB RSS, with no tombstone or dump, and the game had no log file (Godot keeps file
  logging off on phones). Not reproduced on the emulator or on the phone with 0.1.1 (boss, rewards, Act 2 map,
  Ancient, an Act 2 fight). The overlay now logs to `files/logs/godot.log` on the phone (newest five sessions), so
  after another crash `scripts\crash-report.ps1` collects the game's own log of that session. The two LOW_MEMORY
  exits in the same record were Android reclaiming the game while it was in the background (normal).
- A second SIGABRT (16 Oct 01:14, APK 0.1.4 with the overlay's issue #7 boot.gd, 2.0 GB RSS), on the game-over
  screen after losing to the Phrog Parasite elite; progress, run history and the unlock were saved first. From the
  moment that fight loaded, Godot logged `Cannot allocate descriptor sets, error -12` (`VK_ERROR_FRAGMENTED_POOL`;
  Godot 4.5.1 doesn't retry, it skips the draw), 56 times; no earlier session has any. The log then ends in Godot's
  shutdown messages, so something started an exit and it aborted; the reason wasn't kept: logd prunes the chattiest
  app first and the phone's main buffer holds about 4 minutes. From APK 0.1.5 the app captures its own logcat to
  `files/logs/logcat.txt` (see Tools), so the next one will show the abort message. Not reproduced: on 0.1.5, a
  fresh launch straight into `fight PHROG_PARASITE_ELITE` (Profile 2, three turns) logged no descriptor errors, so
  they likely build up over a session (the crashed one had run 9 minutes and several fights).
  The same session logged an `ObjectDisposedException` on every card play: the issue #7 code read the hand's freed
  card play. Fixed in 0.1.5.
- A third SIGABRT (16 Oct 14:11, APK 0.1.5, 2.8 GB RSS), caught by the APK's own logcat: the first
  `Cannot allocate descriptor sets, error -12` came 16 minutes into the session as the Mytes fight loaded, then 26 in
  under two minutes, the last burst as the card reward screen opened; then Godot's state broke
  (`BUG: Unreferenced static string`) and the process ended on `libc++abi: terminating`. The run was saved just before.
  So the descriptor errors cause these crashes. Godot hands out descriptor sets from pools of
  `rendering/rendering_device/vulkan/max_descriptors_per_pool` (default 64) and gives up when the driver refuses one.
  The overlay now sets it to 1024 (pushed 16 Oct, overlay SHA-1 `7e3deee6`; reaches the menu, port code from the
  APK). Soak test, 17 Oct (Profile 2, dev console): 34 different fights (normals, elites incl. Mytes and Phrog
  Parasite, two bosses) with card rewards opened, 20 minutes in one session: no `error -12`, no crash, RSS steady at
  ~1.7 GB. `win` ends fights without card plays, and the soak wasn't run on the old setting (64), so it doesn't prove
  it would have failed there: a long real session is the final check (count `error -12` in the captured logcat).
- Rooms entered with the dev console (`room treasure`...) aren't part of the saved map: after a restart the run
  resumes at the last real map node and anything gained there is gone. Expected; only matters for testing.
- Once, tapping a potion's Drink right after opening its menu didn't drink it; the same taps worked on the next
  try. Not reproduced in 3 later tries (including right after a card play).
- Debug builds show Android's "not 16 KB-aligned" notice for some third-party native libs (Mono runtime,
  Spine). Harmless on this phone (4 KB pages). The release APK passes the 16 KB ZIP-alignment check;
  native ELF compatibility on a device with 16 KB pages is still unverified.
- Debug builds use FMOD's logging libraries; time to main menu is ~19 s (10 s without FMOD).
- `release_info.json` is only looked for next to the executable, which is read-only on Android: the version
  check for mods is skipped (harmless). The corner build label no longer suffers from it (see Android behaviour).
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
  - Android performance hints (ADPF, on since this build): the APK's Sts2PortPerf plugin opens a hint session
    for the game thread (60 fps target) and boot.gd reports every frame. A/B, two rounds each way: first-use
    slow frames 11 -> 8 and time in them -30% (JIT compile time -37%), steady slow frames 3-4 -> 2. The worst
    first-use frames (~140-170 ms) didn't change. A `no_perf_hint` file next to the packs turns it off.
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

**Verdict: feasible, no hard blocker found.** This was the initial analysis; loading `sts2.dll` from outside
the APK and running it on Mono arm64 have since been verified on the Pixel 9a. See the device behaviour,
performance measurements and remaining risks for the current state.

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
1. **Mono on Android vs CoreCLR on desktop**: the game runs on CoreCLR; Godot Android uses Mono. Rare API differences
   may surface at runtime.
2. **Memory and performance**: ASTC reduces memory use, but combat hitches remain and devices other than
   the Pixel 9a have not been tested.
3. **Game updates** may need the port re-checked.
4. **16 KB page-size devices** need native library compatibility testing.

## Build machine setup (Windows)

| Tool | Version | Location |
|---|---|---|
| .NET SDK | 9.0.318 | winget `Microsoft.DotNet.SDK.9` |
| JDK | Microsoft OpenJDK 17.0.20.1 (portable zip) | `D:\Tools\JDK17` (`JAVA_HOME`) |
| Android SDK | cmdline-tools, platform-tools, build-tools 35.0.1, android-35, NDK 28.1.13356709, CMake 3.10.2 | `D:\Android\sdk` (`ANDROID_HOME`) |
| Android emulator (removed to save ~18 GB; reinstall when needed) | emulator + system image `android-34;google_apis;x86_64`, AVD `sts2test` (1080x2424, 8 GB, host GPU) | `D:\Android\sdk`, AVD in `D:\Android\avd` (`ANDROID_AVD_HOME`) |
| Godot | 4.5.1-stable .NET (official, commit f62fdbde1) + export templates, self-contained (`._sc_`) | `D:\Tools\Godot` (templates in `editor_data\export_templates`) |

The MSI build of the JDK ignores winget's `--location`, so use the portable zip to keep it on D:.

## Tools
- `python -I scripts/test_touch.py` — parse-check the boot script and run the touch checks (coordinates, and
  picks/tick/hand-card timing against stand-ins for the game's nodes) in an isolated headless Godot project,
  without game files or saves. `--godot <path>` overrides the default engine path.
- `scripts\release.ps1 -Notes "..."` — bump the APK version, build and check the signed APK (no game files,
  carries `port.pck`), push the commit and tag, and publish the GitHub release that Obtainium installs.
- `python -I scripts/build_port_pack.py --out <file>` — build `port.pck` (boot.gd + version stamp); run by
  `build-perf-plugin.ps1`, which puts it into the plugin's `.aar` and so into the APK's assets.
- `scripts\crash-report.ps1` — after a crash, save Android's records of it (exit reasons, crash/tombstone
  records, logcat) from the phone to `%LOCALAPPDATA%\sts2port\crash-<time>`. Read-only on the phone. It also pulls
  `files/logs`: the game's own logs and (APK 0.1.5+) `logcat*.txt`, the app's whole logcat output per session,
  captured live by the APK's plugin from launch (newest five kept), and lists any fatal lines in them.
- Emulator (not installed; ~18 GB with the game packs). To set it up again: `sdkmanager --sdk_root=D:\Android\sdk
  "emulator" "system-images;android-34;google_apis;x86_64"`, then with `ANDROID_AVD_HOME=D:\Android\avd`:
  `avdmanager create avd -n sts2test -k "system-images;android-34;google_apis;x86_64" -d pixel_7` and set
  `hw.lcd.width=1080`, `hw.lcd.height=2424`, `hw.lcd.density=420`, `hw.ramSize=8192`, `disk.dataPartition.size=24G`,
  `hw.gpu.mode=host` in its config.ini. Start with `emulator -avd sts2test -no-snapshot-save -gpu host`, install the
  APK with `adb install -r` and run `push-game.ps1` as for the phone. The game reaches the menu in ~34 s (ARM
  translation). Good for touch and UI logic, not for performance.
- `python -I tools/icon/make_icon.py` — regenerate the original launcher icon PNGs in `shell/icons/` (requires Pillow).
- `scripts\dev-console.ps1 [-On|-Off] [-Restart] [-Run "cmd; cmd"]` — the game's dev console on the phone, for testing.
- `python -I scripts/spikes/pck_list.py <pck> <outdir>` — list a pck's files and header (read-only).
- `python -I scripts/spikes/pck_extract.py <pck> <outdir> <regex>` — extract matching files (read-only).
- `python -I scripts/spikes/project_binary.py <project.binary>` — dump project settings.
