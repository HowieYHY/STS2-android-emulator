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
- Commit locally in small steps. **Do not push** unless asked.
- When there's a choice, give a recommendation, not a list. Be honest about blockers.

## Layout
- `scripts/spikes/` — read-only analysis tools (pck lister/extractor, project.binary decoder).
- `scripts/` — setup, build, `push-game.ps1 -GameDir "<path>"` (copies the user's pck + dll to the phone via adb).
- `shell/` — Godot 4.5.1 .NET Android project that loads the user's pck + sts2.dll at runtime.
- `stubs/` — Steamworks.NET / Sentry / Vortice replacements.
- `patches/` — Harmony patches (incl. touch input).

## Touch spec (user's)
- Touch = mouse: tap = left click, drag = drag, long-press = right-click (inspect).
- On card and relic selection screens a tap is always right-click (inspect); a side button confirms the pick
  (like mobile StS1).

- **Every** selection (anything where a tap commits a choice: rewards, shop cards/relics/potions, event picks)
  gets tap = inspect + a confirm tick. Don't narrow this to a few screens.

## Known facts about the game (v0.111.0)
See README "Feasibility findings". Decompiled source lives only in the scratchpad (re-create with
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
- Verify a push by its effect (file timestamp on the phone), never by a filtered command's silence: a
  `push-game.ps1` call from Git Bash failed quietly and the phone kept the old overlay.

