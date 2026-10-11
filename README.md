# STS2 Android port

Personal, offline Android port of **Slay the Spire 2** for people who own the game. This repo contains only
original code (a Godot Android shell, stubs, Harmony patches, scripts and docs). It contains **no game files**:
you copy your own `SlayTheSpire2.pck` and `sts2.dll` from your Steam install to your phone with
`scripts/push-game.ps1`.

Status: **feasibility spikes** (nothing playable yet).

## Feasibility findings (game v0.111.0, Godot 4.5.1 .NET)

| Question | Finding | Impact |
|---|---|---|
| Is the `.pck` encrypted? | No. Pack format v3, flags `0x2` (relative file base only), 0 of 15,890 files encrypted. | Stock Godot can mount it. |
| Custom engine modules? | Exe reports `4.5.1.m.14.mono.custom_build`; its module list matches stock 4.5. Every type used in scenes is stock Godot 4.5 apart from Spine and FMOD (GDExtensions). | Stock Godot 4.5.1 .NET should work. GodotSharp API diff still to check. |
| Renderer | Project features include `Mobile`; ETC2/ASTC import is enabled. | Good fit for phones. |
| Textures | 1,244 textures are desktop BC formats (S3TC/BPTC); no ASTC/ETC2 copies in the pck. | Godot decompresses BC on the CPU on GPUs without BC support: works, but uses more RAM and load time. A later optional step can transcode to ASTC on the PC. |
| FMOD | Utopia-rise `fmod-gdextension` (FMOD 2.03, `libfmod.so.14`); its `.gdextension` already lists Android arm64 paths. Banks are `banks/desktop`. | Needs an Android build of the addon plus the FMOD Android SDK (free FMOD account). |
| Spine | Official `spine_godot` GDExtension; `.gdextension` already lists Android arm64 paths. | Official Android binaries exist for matching Spine versions. |
| Sentry | GDExtension with no Android entry; `SentryBootstrap.cs` autoload. | Stub or disable. |
| Steam / DXGI | `sts2.dll` uses `SteamAPI` and `Vortice.DXGI` (`CreateDXGIFactory1`). | Stub Steamworks.NET; patch out DXGI. |

## Tools
- `python -I scripts/spikes/pck_list.py <pck> <outdir>` — list a pck's files and header (read-only).
- `python -I scripts/spikes/pck_extract.py <pck> <outdir> <regex>` — extract matching files (read-only).
- `python -I scripts/spikes/project_binary.py <project.binary>` — dump project settings.
