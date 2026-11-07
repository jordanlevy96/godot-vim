# Regression coverage

Run the suites on Linux with an official Godot editor binary and Python 3:

```sh
python3 tests/run_tests.py /path/to/godot --report results.json
python3 tests/run_tests.py /path/to/godot --suite motion
python3 tests/run_tests.py /path/to/godot --strict-known
```

Each invocation copies the addon and fixtures into a disposable project, imports
resources, isolates editor data/config/cache, and runs the requested suites.
The runner rejects script/runtime errors, nonzero exits, timeouts, or missing
completion markers. JSON output distinguishes executed assertions, known
failures, and skipped scenarios. A suite marked `passed` means no **unexpected**
failures; it does not turn known failures or skipped checks into passes.
`--strict-known` also exits nonzero if a documented defect reproduces.

## What is covered

- **Cursor compatibility:** redraw stability; Normal/Insert/Visual transitions;
  inclusive/exclusive selection conversion; native-selection adoption in both
  directions, including newline and empty-line boundaries.
- **Key parsing/remapping:** every declared mapping and alternate text-object
  key; operator composition and incomplete prefixes; context filtering; Unicode,
  control and special keys; reserved shortcuts; remap insertion/removal and
  context-specific replacement; Insert-mode timeout handling.
- **Motions and text objects:** character, word/WORD, line, file, paragraph and
  section navigation; find/till and forward/reverse repeats; brace matching;
  quoted/bracketed/word/paragraph selections; empty, whitespace, short, Unicode,
  and multiline boundaries.
- **Editing:** insert/append/open-line commands; deletion/change/yank with
  motions and objects; Visual and linewise edits; replacement, joins,
  indentation, comments, case changes, undo/redo, and nonmutation checks.
- **Editor integration:** empty and shader-first startup; multiple script/shader
  tabs; visual-shader safety; actual viewport-dispatched Vim events; command
  line, search, marks and recent files; unsaved-buffer preservation;
  reload/disable/re-enable; single UI nodes and signal connections; shutdown.

Assertions are counted at execution time, per engine version. They are **not**
source-line coverage or proof of complete Vim conformance. Parser/schema checks
and editor-wiring assertions are reported separately from editing/motion checks.
The original upgrade commit `1071f3c` executed 68 assertions: 51 cursor checks and
17 editor checks. The expanded results are recorded in the CI JSON artifacts.
Repeated runs on different Godot versions are not multiplied into this baseline
comparison.

## Verified headless results

Both official Linux binaries, Godot 4.6.3 and 4.7.2, execute the same totals:

| Suite | Executed assertions | Named scenarios |
| --- | ---: | ---: |
| Cursor compatibility | 51 | Original smoke scenarios |
| Key parsing/remapping | 508 | 199 |
| Motions/text objects | 239 | 230 |
| Editing/operators | 255 | 111 |
| Editor integration | 158 | 10 |
| **Total per version** | **1,211** | **550 plus original cursor smoke scenarios** |

Of the 1,211 assertions, **1,209 pass and 2 reproduce the documented upstream
EOF defect**. One clipboard integration scenario is skipped. There are no
unexpected failures. The 68-to-1,211 increase is approximately **17.8 times** as
many executed assertions, with broader behaviors covered rather than repeated
runs counted as extra coverage. Strict-known mode is also verified to exit with
failure while these two defects remain.

## Defects caught and fixed

- Backward find/till at column zero wrapped to the end of the line.
- Repeated till motions could remain stationary.
- Around-WORD selection lost its big-word flag.
- Change-word incorrectly consumed following whitespace on nonblank text.
- Character lookup incorrectly excluded column zero and lacked line bounds.
- Word motions skipped empty lines that Vim treats as words.
- Context-specific remapping could overwrite the Normal binding.
- Removing a nonexistent multi-key binding could remove an operator prefix.
- Repeated script-change notifications duplicated recent-file history.

Expected word/change behavior follows the [Vim word-motion reference](https://vimhelp.org/motion.txt.html#word-motions)
and [change-word reference](https://vimhelp.org/change.txt.html#cw). Internal
linewise selections include a preceding newline; paragraph tests check logical
line bounds as well as that representation.

## Known failures and limits

- **Two known failures:** `o` at the final line inserts above instead of below,
  on single-line and multiline buffers. These reproduce upstream
  [PR #32](https://github.com/bernardo-bruning/godot-vim/pull/32), whose separate
  fix is intentionally not duplicated here. Each check tolerates only the exact
  documented broken buffer; a different wrong result is an unexpected failure.
- **One skipped clipboard scenario:** the headless display has no native
  clipboard. Yank commands are exercised for mode and nonmutation, but clipboard
  contents and paste integration are not validated. An isolated graphical run
  could not start because the local environment disallows the Unix sockets
  required by a virtual display.
- Viewport-dispatched key checks explicitly reacquire focus. Text insertion uses
  the real CodeEdit insertion API. These do not establish physical keyboard,
  mouse dragging, OS focus, IME, platform shortcuts, or detached-window behavior.
- Runs cover Linux Godot 4.6.3 and 4.7.2 only. macOS, Windows, older versions,
  rendering backends, and all possible Vim command combinations are not covered.
- Numeric counts and dot-repeat are not implemented by this addon; rejecting an
  unsupported input is a safety check, not evidence that the feature works.
