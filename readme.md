# godot-vim
A practical subset of Vim bindings inside the Godot editor. This is not a full Vim implementation.

## Compatibility and installation

Tested with Godot **4.7.2 stable** and **4.6.3 stable**. The plugin works in the
GDScript editor and the docked text shader editor. Earlier versions and detached
shader windows are not covered by the automated tests.

Copy `addons/godot_vim` into your project, then enable **GodotVim** under
**Project > Project Settings > Plugins**. Start in Normal mode, use `i` to insert,
and press Escape to return to Normal mode.

## Tests

On Linux, with Python 3 and a Godot editor binary installed, run:

```sh
python3 tests/run_tests.py /path/to/godot
```

The runner uses a temporary project and isolated editor settings. Six suites
cover cursor compatibility, key parsing/remapping, an explicit shortcut inventory, motions/text objects,
editing/operators, and editor integration. Both supported versions run in
GitHub Actions, with JSON result reports saved as artifacts.

Run one suite with `--suite motion`, save counts with `--report results.json`,
or use `--strict-known` to fail on documented defects as well.

Four assertions remain explicit known failures: two `o`-at-EOF reproductions
from upstream [PR #32](https://github.com/bernardo-bruning/godot-vim/pull/32), a search result at buffer offset zero landing on the wrong line, and a
cross-file mark jump landing one column left. Headless native clipboard/paste checks are
skipped when the display driver has no clipboard. These are not passing tests.
See [tests/README.md](tests/README.md) for coverage, results, and limitations.

## Shortcut support at a glance

The [full shortcut reference](docs/vim-shortcuts.md) compares expected Vim
commands with the actual default mappings, behavior tests, differences and gaps.
It replaces the old incomplete command list.

| Area | Available defaults |
| --- | --- |
| Movement | `h j k l`, `w b e ge`, `W B E gE`, `0 ^ $`, `gg G`, `{ }`, `[[ ]]`, `%`, `f/F/t/T` plus `;` and `,` |
| Insert | `i a I A o O`; Escape returns to Normal mode |
| Editing | `d c y` plus motions/objects, `dd cc yy`, `D C x s r`, `J ~`, `u`, `Ctrl-r`, `>> <<`, `gcc` |
| Objects | Inner/around word, WORD, paragraph, quotes, backticks, parentheses, brackets and braces. **`ciw` is implemented and behavior-tested.** |
| Selection | `v` characterwise, `V` linewise; Visual operators and `o` to swap endpoints |
| Search | `/pattern`, `n N`, using Godot regex rather than Vim regex |
| Marks | `m{letter}` and backtick jumps; session-global script marks, with limits described in the reference |
| Editor integration | Restricted `:` commands, `zz`, half-screen `Ctrl-u/d`, and customizable GDScript key maps |

**Important gaps:** no numeric counts, dot-repeat `.`, macros, named registers,
Visual block `Ctrl-v`, `P`, `X`, `R`, backward-search prompt `?`, word searches
`*`/`#`, or general Ex commands such as substitutions and `:wq`.

`p` and yank/delete/change use Godot's system clipboard, not Vim registers;
native clipboard/paste integration is not verified headlessly. Search results at
the first character and exact mark-jump columns have documented defects. Marks exist, but
do not provide Vim's local/global distinction, edit tracking or persistence.
Linewise Visual does not support `x s ~ u U`. `Ctrl-[` is an optional commented
remap example, not a default. Use Godot's Save UI rather than assuming the
untested `:w`/`:wa` shortcut injections work on every platform.

See the [reference](docs/vim-shortcuts.md) for known defects and which entries
have semantic tests versus parser/source evidence only.
