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
See README "Feasibility findings".

## Lessons learnt
- (none yet)
