#!/usr/bin/env python3
"""Run regression tests in a disposable project without changing editor settings."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

if sys.platform != "linux":
    sys.exit("This headless test runner currently supports Linux only.")

ROOT = Path(__file__).resolve().parents[1]
GODOT = shutil.which(sys.argv[1] if len(sys.argv) > 1 else "godot")
if not GODOT:
    sys.exit("Godot not found; pass its executable path as the first argument.")

with tempfile.TemporaryDirectory(prefix="godot-vim-tests-") as directory:
    work = Path(directory)
    project = work / "project"
    project.mkdir()
    shutil.copytree(ROOT / "addons/godot_vim", project / "addons/godot_vim")
    shutil.copytree(ROOT / "tests", project / "tests")
    shutil.copytree(ROOT / "tests/editor_smoke", project / "addons/editor_smoke")
    config = '''config_version=5
[application]
config/name="Godot Vim Compatibility Tests"
config/features=PackedStringArray("4.3", "GL Compatibility")
[rendering]
renderer/rendering_method="gl_compatibility"
'''
    (project / "project.godot").write_text(config)
    env = os.environ.copy()
    for name, folder in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
        env[name] = str(work / folder)
        Path(env[name]).mkdir()
    # Godot's ObjectDB profiler expects this per-project snapshot directory.
    snapshots = work / "data/godot/app_userdata/Godot Vim Compatibility Tests" / str(project).lstrip("/")
    snapshots.mkdir(parents=True)

    def run(arguments, marker=None):
        result = subprocess.run([GODOT, "--headless", "--path", str(project), *arguments],
                                env=env, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=90)
        print(result.stdout, end="", flush=True)
        if result.returncode or "SCRIPT ERROR:" in result.stdout or "ERROR:" in result.stdout:
            sys.exit(result.returncode or 1)
        if marker and marker not in result.stdout:
            sys.exit(f"Missing completion marker: {marker}")

    run(["--editor", "--import"])
    run(["--script", "res://tests/cursor_regression.gd"], "Cursor regression tests: PASS")
    (project / "project.godot").write_text(config + '''
[editor_plugins]
enabled=PackedStringArray("res://addons/godot_vim/plugin.cfg", "res://addons/editor_smoke/plugin.cfg")
''')
    run(["--editor", "--quit-after", "600"], "EDITOR COMPATIBILITY TESTS PASSED")
