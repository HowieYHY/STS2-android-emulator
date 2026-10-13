"""Build port.pck: the port's own code that ships inside the APK (see overlay/android_boot/port_loader.gd).

Usage: python -I build_port_pack.py --out <file>

Holds overlay/android_boot/boot.gd and android_boot/version.txt (APK version from shell/export_presets.cfg and the
git commit). Repo code only, no game files, so it can go into the APK and its GitHub releases.
"""
import argparse
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pcklib  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def apk_version() -> str:
    with open(os.path.join(REPO, "shell", "export_presets.cfg"), encoding="utf-8") as f:
        presets = f.read()
    name = re.search(r'^version/name="([^"]*)"', presets, re.M)
    code = re.search(r"^version/code=(\d+)", presets, re.M)
    return f"{name.group(1) if name else '?'} ({code.group(1) if code else '?'})"


def git_commit() -> str:
    try:
        sha = subprocess.run(["git", "-C", REPO, "rev-parse", "--short", "HEAD"], capture_output=True, text=True,
                             check=True).stdout.strip()
        dirty = subprocess.run(["git", "-C", REPO, "status", "--porcelain", "--", "overlay"], capture_output=True,
                               text=True, check=True).stdout.strip()
        return sha + ("+local changes" if dirty else "")
    except (OSError, subprocess.CalledProcessError):
        return "unknown commit"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    with open(os.path.join(REPO, "overlay", "android_boot", "boot.gd"), "rb") as f:
        boot = f.read()
    version = f"APK {apk_version()}, commit {git_commit()}"
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    pcklib.write_pck(a.out, {"android_boot/boot.gd": boot, "android_boot/version.txt": version.encode() + b"\n"})
    print(f"wrote {a.out}: {version}")


if __name__ == "__main__":
    main()
