"""Run the touch-coordinate regression checks in an isolated Godot project (no game files)."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=r"D:\Tools\Godot\Godot_v4.5.1-stable_mono_win64_console.exe")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="sts2port-touch-tests-") as work:
        project = Path(work)
        (project / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="Touch tests"\n'
            '[display]\nwindow/size/viewport_width=2424\nwindow/size/viewport_height=1080\n',
            encoding="utf-8",
        )
        shutil.copyfile(repo / "overlay/android_boot/boot.gd", project / "boot.gd")
        shutil.copyfile(repo / "tools/tests/touch_coordinates.gd", project / "test.gd")
        subprocess.run([args.godot, "--headless", "--path", work, "--check-only", "--script", "boot.gd"], check=True)
        subprocess.run([args.godot, "--headless", "--path", work, "--script", "test.gd"], check=True, timeout=60)


if __name__ == "__main__":
    main()
