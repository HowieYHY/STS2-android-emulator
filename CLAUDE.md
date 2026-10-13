# CLAUDE.md — STS2 Android port

Native Android port of Slay the Spire 2 (not an emulator) so the owner can play their own copy offline on a phone.
Plan: `C:\Users\Admin\.claude\plans\i-want-to-make-atomic-glacier.md` (riskiest work first).

## Hard rules
- **Never commit or copy game files into this repo**: `.pck`, `sts2.dll` or any game DLL, extracted assets,
  decompiled source, APKs. `.gitignore` enforces most of it; check `git status` before every commit.
- Reference game folder is **read-only**: `d:\Steam\steamapps\common\Slay the Spire 2`. Never modify it.
- Anything that reads the game takes the game path as an argument and writes output **outside** the repo
  (scratchpad or a user-chosen folder).
- Tell the user before each tool install and get confirmation; prefer winget.
- **Always verify and update the actual STS2 game version in both README.md and CLAUDE.md when applicable**:
  game-file inspection/patching, overlay or texture builds/pushes, game testing, and compatibility documentation.
  Follow "Game version verification" below; the port's APK version and Godot version are separate.
- Commit locally in small steps. **Do not push** unless asked.
- **Releases** (user, 13 Oct 2026): fixes to the port's own code (`boot.gd`) reach the phone as GitHub releases of the
  APK, installed by Obtainium. When the user wants fixes on the phone, run `scripts\release.ps1 -Notes "..."`;
  it pushes the commit and tag (that push is part of the release). The APK and releases must never contain game
  files (the script checks). Game-derived changes (sts2.dll patches, build_overlay.py settings, STS2 updates) still
  need `push-game.ps1`; say so when a change needs it.
- When there's a choice, give a recommendation, not a list. Be honest about blockers.

## Layout
- `scripts/spikes/` — read-only analysis tools (pck lister/extractor, project.binary decoder).
- `scripts/` — setup, build, `push-game.ps1 -GameDir "<path>"` (copies the user's pck + dll to the phone via adb),
  `release.ps1` (APK release for Obtainium).
- `overlay/android_boot/` — `port_loader.gd` (first autoload; mounts the APK's port.pck) and `boot.gd` (the port's
  code; ships in the APK via `build_port_pack.py` → the plugin `.aar`, with a fallback copy in overlay.pck).
- `shell/` — Godot 4.5.1 .NET Android project that loads the user's pck + sts2.dll at runtime.
- `stubs/` — Steamworks.NET / Sentry / Vortice replacements.
- `patches/` — Harmony patches (incl. touch input).

## Touch spec (user's)
- Touch = mouse: tap = left click, drag = drag, long-press = right-click (inspect).
- On card and relic selection screens a tap is always right-click (inspect); a side button confirms the pick
  (like mobile StS1).

- **Every** selection (anything where a tap commits a choice: rewards, shop cards/relics/potions, event picks)
  gets tap = inspect + a confirm tick. Don't narrow this to a few screens. Exceptions (user): the treasure room
  chest relic is taken on tap, no tick (there's only one relic, nothing to choose between); event and Ancient
  options are chosen on tap, no tick, and a long-press shows their info (issue #1).
- In combat, tapping a hand card must not pick it up (the game's PC click-to-play): it only highlights while the
  finger is down and goes back to normal on release. Cards are played by dragging (issue #4).

## Testing on the emulator (user: when the phone isn't available, test on our own emulator first)
- The emulator was removed on 13 Oct 2026 at the user's request (~18 GB); reinstall it when needed (user: "you can
  download it the next time you need it") with the steps in README → Tools. It's an AVD `sts2test` (API 34 x86_64
  Google APIs, 1080x2424 like the Pixel 9a); the arm64 APK runs through Android's ARM translation and the phone's
  dev-console workflow below works unchanged against it.
- Emulator results are emulator results: say so, and don't record them as phone-tested. Native crashes inside
  `libndk_translation` are the emulator's, not the game's. Don't judge performance on it.
- A/B on the emulator by building the overlay from the old boot.gd. Write it with `cmd /c "git show ... > file"`:
  PowerShell's `Set-Content -Encoding utf8` adds a BOM, and a BOM'd boot.gd gives a black screen.

## Testing on the phone (user's rule: use the dev console, don't play whole runs)
- Get to the screen under test with the game's console instead of playing to it:
  `scripts\dev-console.ps1 -On -Restart`, wait for the menu, Continue/start a run, then
  `scripts\dev-console.ps1 -Run "gold 200; room shop"`. Turn it off afterwards with `-Off`.
- Useful commands (from the decompiled `ConsoleCommands`): `room <monster|elite|boss|treasure|shop|event|restsite>`,
  `fight <ENCOUNTER_ID>`, `event <ID>`, `act <n>`, `travel` (jump to any map node), `gold/heal/energy/draw <n>`,
  `relic add|remove <ID>`, `potion <ID>`, `card <ID> [pile]`, `upgrade <hand-index>`, `win` (win the combat),
  `kill all`, `godmode`, `instant`. IDs are SCREAMING_SNAKE_CASE (e.g. `VANTOM_BOSS`, `SLIMES_WEAK`).
- Never run `cloud delete`, `sentry crash`, `die`, `leaderboard`, `achievement` (the script refuses them).
- The console opens with the backtick key; on the phone `adb shell input keyevent KEYCODE_GRAVE` works and Android
  shows its keyboard (window shrinks to 2424x1017 while it's up, harmless). `input text` needs `%s` for spaces.
- Before blaming new code for a hang, A/B it over several launches against the last good build (see lessons).
- Long-press and hold-to-preview in adb: `input swipe x y x y 900` (long-press), `input motionevent DOWN/MOVE/UP`
  (hold a drag to read the game's damage preview before releasing).
- Logcat: poll with `adb logcat -d`; the game logs plays (`playing card X (targeting Y)`), rewards
  (`obtained CARD.X`), room loads, and the port logs `[sts2port] Pick: inspecting/taking <item>`.

## Game version verification

Current reference game: **v0.111.0**, commit `41cef1ea`, branch `v0.111.0`.
Source: `D:\Steam\steamapps\common\Slay the Spire 2\release_info.json`; verified **13 October 2026**.
Last phone-tested game build: **v0.111.0**, commit `41cef1ea`, on **13 October 2026**; the deployed overlay
matches the pack rebuilt from the reference installation.
Last emulator-tested game build: **v0.111.0**, commit `41cef1ea`, on **13 October 2026** (touch fixes for
issues #1-#5).
Phone deployment, 13 October 2026: APK **0.1.1** (code 2, hash matches the v0.1.1 release) and an overlay with
`port_loader.gd` built from the v0.111.0 reference installation; the game loads the port code from the APK and
reaches the menu with the saved run intact. #1-#5 retested on the phone with the dev console the same day (Profile 2).

- Re-read `<GameDir>/release_info.json` from the actual game installation used for applicable work; use its
  `version`, `commit` and `branch` fields. Read the game folder only; never modify it or copy game files into the repo.
- Update this record and README's "STS2 game version" section together, including the source and verification
  date, before committing relevant work. Do not infer the game version from the APK's `version/name`, the Godot
  engine version, file timestamps, or an old documentation heading.
- When reporting phone compatibility, verify which game build its packs/assemblies came from using matching
  deployment records, hashes or runtime metadata. A local Steam update does not establish the phone's version.
  Record a different verified phone version separately; never claim an untested update is supported.
- Preserve version labels on historical analysis and performance measurements. After a game update, re-check
  relevant patch shape guards and behaviour before updating compatibility claims.
- If release metadata is unavailable or inconsistent with the files under test, mark the current version as
  unverified and retain the last verified version/source/date. Use runtime metadata or assembly inspection to
  resolve it; never guess or silently carry an old version forward as current.

## Known facts about the game
See README "Feasibility findings" for the version-labelled analysis. Decompiled source lives only in the
scratchpad (re-create with
`ilspycmd -p -o <outside-repo> -r <game data dir> <game data dir>/sts2.dll`).

## Lessons learnt
- Latest `ilspycmd` (11.x) won't install on the .NET 9 SDK ("DotnetToolSettings.xml not found"). Pin
  `--version 9.1.0.7988` and run with `DOTNET_ROLL_FORWARD=Major`.
- Prefer the game's own switches over patches: `--force-steam off` (Null platform), empty Sentry DSN, `nomods`.
  Check the decompiled source for a built-in flag before writing a Harmony patch.
- Godot's `JSON.parse_string` turns every number into a float; re-saving the game's `settings.save` wrote
  `"schema_version": 8.0` and the game discarded the file as corrupt. **Never re-serialise the game's saves;
  edit only the bytes you mean to change** (regex on the text).
- Android `OS.get_locale()` is Java's `Locale.toString()` and can carry extensions
  (`en_SG_#u-fw-sun-ms-metric-mu-celsius`); the game's `new CultureInfo(...)` throws on it. The boot script
  saves a language first so the game skips that path.
- Mono vs CoreCLR: `beforefieldinit` static initialisers run earlier on Mono (on instance creation). Expect
  more ordering bugs like ModelDb's; fix them in `tools/Sts2Patcher` with a shape check.
- `.gitignore` is matched case-insensitively on Windows: `sts2*` silently ignored `tools/Sts2Patcher`. Use
  narrow patterns (`sts2.*`) and check `git status` lists every new folder before committing.
- Running `push-game.ps1` via `powershell.exe` hits the execution policy; use `-ExecutionPolicy Bypass -File`.
  Under `-File`, `$PSScriptRoot` was empty in the `param()` defaults; scripts resolve their folder in the body
  from `$MyInvocation.MyCommand.Path`.
  Under `$ErrorActionPreference = "Stop"`, PowerShell 5.1 turns adb's stderr progress into an error:
  run native tools through a helper and check `$LASTEXITCODE`.
- Git Bash rewrites `/data/...` and `/sdcard/...` adb arguments into Windows paths: `export MSYS_NO_PATHCONV=1`.
- Long extraction paths fail in the scratchpad (MAX_PATH); extract SDK zips to a short path on D:.
- Godot's `--install-android-build-template` does nothing on its own; it only works together with
  `--export-debug/--export-release`. The FMOD addon's `.aar` (FMOD Java init) needs the Gradle build.
- Before asking the user for a manual download, check whether the needed files already ship in a public
  release: the fmod-gdextension 6.1.0 release bundles FMOD 2.03.06's Android libs (verified byte-identical
  to the official SDK the user downloaded).
- When adb lists nothing but Windows shows the phone's `MI_01` WinUSB interface, the PC side is fine:
  replug the cable and accept the on-phone prompt.
- Godot notification numbers: take them from the engine source, not memory. `NOTIFICATION_APPLICATION_PAUSED`
  is 2015 (MainLoop), not 1015; the first save-on-pause patch silently never fired.
- Android never "quits" a game normally: anything the game saves only on quit must also be saved on
  `NOTIFICATION_APPLICATION_PAUSED`.
- Release builds are signed with the same local debug key on purpose: changing the signing key forces an
  uninstall, which deletes the saves in the app's private storage.
- Commit b7a3341's message claimed an Auto-aspect default and README notes that never landed: the scripted
  edit failed ("pattern not found") and the commit went ahead in the same command. **Never chain a commit after
  a scripted edit; check `git diff --stat` matches the message before committing.**
- A startup freeze first looked like the new touch code's fault; the unchanged build froze too. **Before blaming
  a change, A/B it against the last good build over several launches** (one launch proves nothing). The cause
  was Swappy frame pacing racing with the game's V-Sync switch (~1 in 3 launches); it's off in the overlay now.
  A 9-day-old phone with full swap made it far worse (3 of 4), so restart the phone before judging flakiness.
- Don't stream `adb logcat` under `timeout` in a loop: killing it wedged the adb server and the phone "vanished".
  Poll `adb logcat -d` instead; if adb loses the phone, `adb kill-server` before asking the user to replug.
- Godot's built-in Android long-press (`enable_long_press_as_right_click`) cancels the touch first, which Godot
  turns into a left *release*, and the game's card holders pick the card on that release. Hence our own layer.
- A GDScript type error in `boot.gd` only shows on the phone as "autoload does not inherit from Node" and a black
  screen (the pck never mounts). **Parse-check before pushing**: copy it into a scratch project with
  `config_version=5` and run `Godot_v4.5.1-stable_mono_win64_console.exe --headless --path . --check-only --script boot.gd`.
- Inserting a key into settings.save with `text.replace("{\n", ...)` hit **every** nested object too; the game
  discarded the file as corrupt and recreated default settings (user's settings lost, the run was unaffected).
  **Edit the game's JSON at one exact position (first brace / a regex on the key), test every layout headlessly
  on the PC first** (`--headless --script` test with first/middle/last/absent cases), and check the next boot
  log for "First time setup" or a rejected-save warning.
- The game creates screens lazily (e.g. `NInspectCardScreen` under `/root/Game/InspectionContainer` only after
  the first inspect). Caching a lookup done before that kept "nothing found" forever, and the tick vanished on the
  first tap inside the inspect screen. Look such nodes up when needed.
- A screen that closes with a fade (`NInspectCardScreen.Close()`) still covers the item until its tween ends; a
  click sent right away hit the overlay and did nothing. Wait until it's actually hidden.
- `powershell -File script.ps1 -Arg "a","b"` passes ONE string "a,b" (no arrays through -File). Split it yourself.
- Godot test harness (`--headless --script t.gd` extending SceneTree): build nodes on the first `process_frame`,
  not in `_init`/`_initialize`; before that `get_tree()` is null.
- Windowed mode (Settings → Fullscreen off) on Android misaligned touch and couldn't be undone by touch. The game
  already had the fix: its `SupportedWindowMode.FullscreenOnly` platform mode. Before inventing a fix, look for
  the game's own console/Steam Deck switches (`PlatformUtil`, `SupportedWindowMode`, launch args).
- `dev-console.ps1 -Restart` must press Home before force-stop, or the save-on-pause doesn't run and in-memory
  changes are lost (the Early Access pop-up came back).
- A tap and a drag shorter than the slop (~22 px) are the same thing: tiny slider nudges are taps. Use a two-step
  drag (away, then back to the exact spot).
- Godot's ASTC encoder (`Image.compress`) **stretches** images whose size isn't a multiple of 4 (5377 -> 5380 wide).
  A PSNR of 9.6 dB exposed it; atlas sprites would have shifted. Pad to whole blocks yourself and keep the original
  size in the .ctex. Always check a converter's output numerically (PSNR per texture), not by eye on one sample.
- GST2 (.ctex) layout: 36-byte header, then u32 data format, u16 w, u16 h, u32 mipmaps, u32 Image::Format, data.
  Two scripts were written with the offsets 4 bytes off; read a known file's fields back before trusting a parser.
- A suspected cause must be confirmed by A/B before keeping the fix: the Vulkan pipeline-cache chunk setting
  changed nothing measurable (first-use spikes stayed), so it was reverted instead of shipped.
- Measure GPU vs CPU before guessing at rendering fixes: `RenderingServer.viewport_set_measure_render_time` +
  `viewport_get_measured_render_time_gpu` (perf_log does this). Combat: GPU 11-14 ms, so it isn't fill/draws.
- Mono's `RuntimeHelpers.PrepareMethod` compiles nothing (50k methods "done" in 0.3 s, JitInfo unchanged);
  `MethodHandle.GetFunctionPointer()` really JITs. Check a warm-up/cache trick with a counter, not by its speed.
- Removing a measured cost doesn't prove it was the bottleneck: JIT warm-up removed the 30-55 ms of JIT from the
  slow frames, yet they stayed 120-145 ms. Judge a fix by frame times, not by the counter it targets.
- simpleperf on a profileable (non-debuggable) app needs `--app <package>`; `-p <pid>` gets "Permission denied".
  Godot's published Android debug symbols are for the standard template only (build ID differs from the .NET one).
- Check `dumpsys thermalservice` before trusting absolute timings: after an hour of testing on the charger the
  phone was at thermal status 1 with CPUs at 63-67 °C. Compare before/after in the same thermal state.
- The APK's project.godot settings don't apply in game: the overlay runs the game's project.binary. The APK said
  sensor landscape, the game said nothing, so Godot's fixed-landscape default won and the screen never turned 180°
  (README even claimed it did, from the APK manifest alone). Check the running activity
  (`dumpsys activity activities | grep requestedOrientation`), and set such settings in build_overlay EXTRA_SETTINGS.
- Godot's Gradle export writes the APK in ~4 min, then `Godot ... --export-release` can sit idle for 20+ min
  (waiting on the Gradle daemon). `build-apk.ps1` now stops Godot itself once the APK has been unchanged for a
  minute (a release build takes ~90 s that way); check the result with `aapt2 dump badging`.
- A small Android plugin doesn't need a Gradle library project: javac against android.jar + the template's
  godot-lib classes.jar, then zip AndroidManifest.xml + classes.jar + R.txt as the .aar (build-perf-plugin.ps1).
  PowerShell 5.1: wrap a file list in @(...) before splatting, or a single file splats as characters.
- Verify a push by its effect (file timestamp on the phone), never by a filtered command's silence: a
  `push-game.ps1` call from Git Bash failed quietly and the phone kept the old overlay.
- Fast taps in the shop bought items (issue #2): the touch layer decided a tap from `gui_get_hovered_control()` while
  the game hadn't yet processed earlier events. Android buffers parsed input until the next frame, so hover lags,
  and the headless tests (which handle input at once) passed anyway. **Decide a tap only after everything sent has
  been processed and hover has settled; never act on a hover that may predate a screen opening or closing.**
  Headless tests must buffer input like Android (see `tools/tests/touch_picks.gd`) or they can't see these races.
- Each emulator run found a hole the previous fix missed (stale hover, then a pick decided before the inspect
  screen opened, then a fading popup). Keep logging every decision on the device until a burst test shows
  zero purchases over several runs, and A/B it against the old overlay before claiming it's fixed.
- Issue #6's crash left nothing to diagnose: SIGABRT with no tombstone, and Godot keeps file logging off on phones.
  `dumpsys activity exit-info` still had its time, reason and importance (100 = foreground; LOW_MEMORY at 400 is
  just a background kill). The overlay now logs to the external files folder; read `crash-report.ps1`'s output first.
- Test on the phone in an empty profile (Profile 2), never the owner's run: dev-console rooms and gold stick to the save.
  `event <ID>` from the console before leaving a room left that room's Proceed layer catching taps; open events from
  the map (then Back, Resume, close the map) or the result looks like a touch bug.
- Game screens that "hide" by sliding off screen stay `visible` (NProceedButton). Checking `is_visible_in_tree()`
  alone lifted the tick above an invisible arrow (issue #3). Check the game's own enabled state and the on-screen rect.

