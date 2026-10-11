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
  Under `$ErrorActionPreference = "Stop"`, PowerShell 5.1 turns adb's stderr progress into an error:
  run native tools through a helper and check `$LASTEXITCODE`.
- Git Bash rewrites `/data/...` and `/sdcard/...` adb arguments into Windows paths: `export MSYS_NO_PATHCONV=1`.
- Long extraction paths fail in the scratchpad (MAX_PATH); extract SDK zips to a short path on D:.

