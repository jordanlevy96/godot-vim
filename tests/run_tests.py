#!/usr/bin/env python3
"""Run Linux regression suites in a disposable project and isolated settings."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

SUITES = {
    "cursor": ("cursor_regression.gd", "Cursor regression tests: PASS"),
    "keymap": ("keymap_regression.gd", "Keymap regression tests: PASS"),
    "shortcuts": ("shortcut_inventory.gd", "Shortcut inventory tests: PASS"),
    "motion": ("motion_regression.gd", "Motion regression tests: PASS"),
    "edit": ("edit_regression.gd", "Edit regression tests: PASS"),
    "editor": (None, "EDITOR COMPATIBILITY TESTS PASSED"),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("godot", nargs="?", default="godot", help="Godot editor executable")
parser.add_argument("--suite", action="append", choices=SUITES, help="Run only selected suites")
parser.add_argument("--strict-known", action="store_true", help="Fail when documented upstream defects reproduce")
parser.add_argument("--report", type=Path, help="Write a machine-readable result report")
args = parser.parse_args()
if sys.platform != "linux":
    sys.exit("This headless test runner currently supports Linux only.")
ROOT = Path(__file__).resolve().parents[1]
GODOT = shutil.which(args.godot)
if not GODOT:
    sys.exit("Godot not found; pass its executable path as the first argument.")
GODOT = str(Path(GODOT).resolve())
selected = args.suite or list(SUITES)
results = []

with tempfile.TemporaryDirectory(prefix="godot-vim-tests-") as directory:
    work = Path(directory)
    project = work / "project"
    project.mkdir()
    ignore = shutil.ignore_patterns("__pycache__", "*.pyc", "*.uid")
    shutil.copytree(ROOT / "addons/godot_vim", project / "addons/godot_vim", ignore=ignore)
    shutil.copytree(ROOT / "tests", project / "tests", ignore=ignore)
    shutil.copytree(ROOT / "tests/editor_smoke", project / "addons/editor_smoke", ignore=ignore)
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
    version = subprocess.check_output([GODOT, "--version"], env=env, text=True).strip()
    print("Testing Godot", version, flush=True)

    def run(name, arguments, marker=None):
        try:
            result = subprocess.run([GODOT, "--headless", "--path", str(project), *arguments],
                                    env=env, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=120)
            output = result.stdout
            code = result.returncode
        except subprocess.TimeoutExpired as error:
            output = error.stdout or b""
            if isinstance(output, bytes):
                output = output.decode(errors="replace")
            code = 124
        print(output, end="", flush=True)
        passed = code == 0 and "ERROR:" not in output and (marker is None or marker in output)
        # Parse explicit suite totals. These are assertions, not source coverage.
        totals = re.findall(r"(\d+) assertions", output)
        scenarios = re.findall(r"(\d+) scenarios", output)
        known = re.findall(r"(\d+) known failures", output)
        skipped = re.findall(r"(\d+) skipped scenarios", output)
        results.append({"suite": name, "passed": passed, "exit_code": code,
                        "assertions": int(totals[-1]) if totals else None,
                        "scenarios": int(scenarios[0]) if scenarios else None,
                        "known_failures": int(known[-1]) if known else 0,
                        "skipped_scenarios": int(skipped[-1]) if skipped else 0})
        if not passed:
            print(f"FAILED SUITE: {name} (exit {code}; required marker: {marker})", flush=True)
        return passed

    if run("import", ["--editor", "--import"]):
        for name in selected:
            script, marker = SUITES[name]
            if script:
                run(name, ["--script", "res://tests/" + script], marker)
            else:
                (project / "project.godot").write_text(config + '''
[editor_plugins]
enabled=PackedStringArray("res://addons/godot_vim/plugin.cfg", "res://addons/editor_smoke/plugin.cfg")
''')
                run(name, ["--editor", "--quit-after", "6000"], marker)
    report = {"godot": version, "results": results,
              "passed": all(result["passed"] for result in results),
              "assertions": sum(result["assertions"] or 0 for result in results),
              "known_failures": sum(result["known_failures"] for result in results),
              "skipped_scenarios": sum(result["skipped_scenarios"] for result in results)}
    if args.strict_known and report["known_failures"]:
        report["passed"] = False
    print("TEST SUMMARY: " + json.dumps(report), flush=True)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    sys.exit(0 if report["passed"] else 1)
