"""Build overlay.pck for the Android port from the user's own game install and the built APK.

Usage: python -I build_overlay.py --game-dir "<Steam>/Slay the Spire 2" --apk build/sts2port.apk --out <dir>

The overlay is the APK's --main-pack. It holds:
  - .NET assemblies: the Android (Mono) runtime from our APK + the game's managed deps and sts2.dll,
    patched by tools/Sts2Patcher (a copy, in --out) for Mono/Android differences
  - the game's startup files (.godot caches, .gdextension files) and a patched project.binary that
    adds our boot autoload first and blanks the Sentry DSN
  - overlay/android_boot/boot.gd from this repo, which mounts SlayTheSpire2.pck at runtime
Output goes to --out, never into the repo. The game folder is only read.
"""
import argparse
import os
import struct
import subprocess
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pcklib  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUBLISH = ".godot/mono/publish/arm64/"
SHELL_ASSEMBLY = "StsAndroidShell"

# sts2.dll and the third-party managed assemblies it ships with (from sts2.deps.json).
# Framework assemblies come from the APK's Android runtime instead of the game's Windows CoreCLR copies.
GAME_ASSEMBLIES = [
    "sts2.dll", "0Harmony.dll", "JetBrains.Annotations.dll", "MonoMod.Backports.dll", "MonoMod.ILHelpers.dll",
    "Sentry.dll", "Sentry.Godot.dll", "SharpGen.Runtime.dll", "SharpGen.Runtime.COM.dll", "SmartFormat.dll",
    "SmartFormat.ZString.dll", "Steamworks.NET.dll", "System.IO.Hashing.dll", "Vortice.DirectX.dll",
    "Vortice.DXGI.dll", "Vortice.Mathematics.dll",
]
# Startup files read before our boot autoload runs, so they must be in the overlay itself.
GAME_STARTUP_FILES = [
    ".godot/global_script_class_cache.cfg", ".godot/uid_cache.bin",
    "addons/fmod/fmod.gdextension", "addons/spine/spine_godot_extension.gdextension",
]
DROPPED_EXTENSIONS = ["res://addons/sentry/sentry.gdextension"]  # no Android build of Sentry's native lib
BOOT_AUTOLOAD = ("autoload/AndroidBoot", "*res://android_boot/boot.gd")
# Runs first and mounts the newer boot.gd shipped in the APK, if any (port_loader.gd); the overlay's copy is the fallback.
LOADER_AUTOLOAD = ("autoload/AndroidPortLoader", "*res://android_boot/port_loader.gd")
# Project settings the PC game never needed. quit_on_go_back defaults to true, so Android's Back button/gesture
# closed the game instantly (losing progress since the last room); with it off, Back reaches the game's input map.
# Swappy (Android frame pacing) is restarted when the game switches V-Sync mode at startup, and about one launch
# in three then froze before the first frame. A card game doesn't need it; plain FIFO present is used instead.
EXTRA_SETTINGS = {
    "application/config/quit_on_go_back": pcklib.variant_bool(False),
    "display/window/frame_pacing/android/enable_frame_pacing": pcklib.variant_bool(False),
    # The game never sets an orientation, so Godot's default (fixed landscape) replaced the APK's and the screen
    # wouldn't turn 180°. 4 = SCREEN_SENSOR_LANDSCAPE: both landscape directions, following the phone's auto-rotate.
    "display/window/handheld/orientation": pcklib.variant_int(4),
    # Godot keeps file logging off on phones, so a crash left nothing behind (issue #6: SIGABRT in the foreground,
    # no tombstone). Log to the app's external files folder, where adb (scripts/crash-report.ps1) can read it.
    "debug/file_logging/enable_file_logging": pcklib.variant_bool(True),
    "debug/file_logging/log_path": pcklib.variant_string(
        "/storage/emulated/0/Android/data/com.howieyhy.sts2port/files/logs/godot.log"),
}
PATCHER_PROJECT = os.path.join(REPO, "tools", "Sts2Patcher", "Sts2Patcher.csproj")
PATCHER_DLL = os.path.join(REPO, "tools", "Sts2Patcher", "bin", "Release", "net9.0", "Sts2Patcher.dll")
PROBE_PROJECT = os.path.join(REPO, "tools", "Sts2Probe", "Sts2Probe.csproj")
PROBE_DLL = os.path.join(REPO, "tools", "Sts2Probe", "bin", "Release", "net9.0", "Sts2Probe.dll")


def patch_sts2(data_dir: str, out_dir: str) -> str:
    """Run tools/Sts2Patcher on the game's sts2.dll; returns the patched copy's path (in out_dir).
    Also builds tools/Sts2Probe, whose Install() call the patcher adds (inert unless perf_log is on the phone)."""
    for project in (PATCHER_PROJECT, PROBE_PROJECT):
        subprocess.run(["dotnet", "build", project, "-c", "Release", "-v", "q", "-nologo"], check=True)
    patched = os.path.join(out_dir, "patched", "sts2.dll")
    subprocess.run(["dotnet", PATCHER_DLL, os.path.join(data_dir, "sts2.dll"), data_dir, patched, PROBE_DLL],
                   check=True)
    return patched


def is_managed(data: bytes) -> bool:
    """True if a PE file has a CLI (.NET) header."""
    try:
        pe = struct.unpack_from("<I", data, 0x3C)[0]
        magic = struct.unpack_from("<H", data, pe + 24)[0]
        dd = pe + 24 + (96 if magic == 0x10B else 112)
        return struct.unpack_from("<I", data, dd + 14 * 8)[0] != 0
    except struct.error:
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game-dir", required=True)
    ap.add_argument("--apk", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    data_dir = os.path.join(a.game_dir, "data_sts2_windows_x86_64")
    game_pck = os.path.join(a.game_dir, "SlayTheSpire2.pck")
    out_abs = os.path.abspath(a.out)
    if out_abs.lower().startswith(REPO.lower() + os.sep):
        sys.exit("--out must be outside the repo (game-derived files are never written into it)")
    os.makedirs(out_abs, exist_ok=True)

    files: dict[str, bytes] = {}

    # 1. Android .NET runtime assemblies from our APK (minus the shell's own assembly).
    with zipfile.ZipFile(a.apk) as z:
        for n in z.namelist():
            if n.startswith("assets/" + PUBLISH) and not os.path.basename(n).startswith(SHELL_ASSEMBLY + "."):
                files[n[len("assets/"):]] = z.read(n)
    if not any(p.endswith("/System.Runtime.dll") for p in files):
        sys.exit(f"{a.apk} has no .NET runtime under assets/{PUBLISH}; export the shell first")

    # 2. The game's managed assemblies (sts2.dll with the port's patches applied to a copy).
    patched_sts2 = patch_sts2(data_dir, out_abs)
    for name in GAME_ASSEMBLIES:
        src = patched_sts2 if name == "sts2.dll" else os.path.join(data_dir, name)
        with open(src, "rb") as f:
            files[PUBLISH + name] = f.read()
    with open(PROBE_DLL, "rb") as f:
        files[PUBLISH + "Sts2Probe.dll"] = f.read()
    known ={n.lower() for n in GAME_ASSEMBLIES} | {"godotsharp.dll"}
    for name in sorted(os.listdir(data_dir)):
        low = name.lower()
        if not low.endswith(".dll") or low in known or low.startswith(("system.", "microsoft.")) \
                or low in ("mscorlib.dll", "netstandard.dll", "windowsbase.dll"):
            continue
        with open(os.path.join(data_dir, name), "rb") as f:
            if is_managed(f.read()):
                print(f"WARNING: unlisted managed assembly in game folder, not included: {name}")

    # 3. Startup files and patched settings from the game's pck.
    pck = pcklib.PckReader(game_pck)
    print(f"game pck: Godot {pck.major}.{pck.minor}.{pck.patch}, {len(pck.entries)} files")
    for p in GAME_STARTUP_FILES:
        files[p] = pck.read(p)
    ext_list = pck.read(".godot/extension_list.cfg").decode("utf-8").splitlines()
    files[".godot/extension_list.cfg"] = ("\n".join(l for l in ext_list if l.strip() not in DROPPED_EXTENSIONS) + "\n").encode()

    items = [(k, v) for k, v in pcklib.read_ecfg(pck.read("project.binary"))
             if k not in (BOOT_AUTOLOAD[0], LOADER_AUTOLOAD[0])]
    patched = []
    for k, v in items:
        if k == "sentry/config/dsn":
            v = pcklib.variant_string("")  # Sentry stays off: no crash reports leave the phone
        patched.append((k, v))
    patched = [(k, v) for k, v in patched if k not in EXTRA_SETTINGS] + list(EXTRA_SETTINGS.items())
    patched.insert(0, (BOOT_AUTOLOAD[0], pcklib.variant_string(BOOT_AUTOLOAD[1])))
    patched.insert(0, (LOADER_AUTOLOAD[0], pcklib.variant_string(LOADER_AUTOLOAD[1])))
    files["project.binary"] = pcklib.write_ecfg(patched)
    pck.close()

    # 4. Our own overlay files.
    for name in ("boot.gd", "port_loader.gd"):
        with open(os.path.join(REPO, "overlay", "android_boot", name), "rb") as f:
            files["android_boot/" + name] = f.read()

    out_pck = os.path.join(out_abs, "overlay.pck")
    pcklib.write_pck(out_pck, files)
    total = sum(len(v) for v in files.values())
    print(f"wrote {out_pck}: {len(files)} files, {total / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
