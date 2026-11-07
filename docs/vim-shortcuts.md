# Vim shortcut support

This is a source-and-test audit of the default bindings in this fork, not a claim
of complete Vim compatibility. User remaps can change the results. The audit
started from `da1c30e5124d11726e7d3cd3e2030f49699ac944` and adds an explicit
[shortcut inventory test](../tests/shortcut_inventory.gd) alongside the existing
behavior suites. No new commands are implemented by this documentation update.

## How to read the tables

- **Behavior tested:** representative keys were executed against a real Godot
  `CodeEdit`, with buffer/caret/mode assertions. It does not mean all combinations
  or edge cases match Vim.
- **Mapped, limited:** the parser and handler exist, but behavior differs from Vim,
  an important integration check is missing, or a known defect remains.
- **Absent:** there is no default addon command for the listed Vim feature.
  Godot may still handle a native shortcut. Unsupported multi-key sequences are
  not guaranteed to be harmless: after an unknown prefix, later keys can become
  separate commands. Do not rely on counts, macros, or register prefixes.

`Ctrl-x` means Control plus x; `{char}` means one character, not literal braces.
`{motion}` / `{object}` mean a supported motion / text object. `0` is a motion,
not the beginning of a numeric count. Uppercase keys are distinct from lowercase.
The event translator uses Godot's command-or-control modifier, but automated
runs are Linux-only; macOS modifier behavior has not been verified.

## Movement and search

| Keys | Expected purpose | Fork behavior and evidence |
| --- | --- | --- |
| `h j k l` | Left/down/up/right | **Behavior tested.** Logical lines, clamped to buffer bounds. No counts or wrapped-display-line `gj/gk`. Preferred-column restoration across short lines is not established. |
| `0 ^ $` | Start / first nonblank / end of line | **Behavior tested**, including empty, whitespace and Unicode lines. |
| `w b e ge` | Word starts/ends, forward/back | **Behavior tested.** Uses the addon's fixed punctuation/space groups, not configurable Vim `iskeyword`. |
| `W B E gE` | Whitespace-delimited WORD movement | **Behavior tested**, including punctuation and empty lines. |
| `f{char} F{char} t{char} T{char}` | Find/till within current line | **Behavior tested** in both directions, including no-match and column-zero boundaries. |
| `; ,` | Repeat/reverse last find/till | **Behavior tested**, including repeated till and direction changes. |
| `gg G` | First/last buffer line | **Behavior tested.** Goes to column zero, not Vim's usual first nonblank. `5G` and `5gg` are absent; use `:5`. |
| `{ }` | Paragraph movement | **Behavior tested** on blank-line-separated paragraphs; not full Vim paragraph-option semantics. |
| `[[ ]]` | Section movement | **Behavior tested, different definition.** GDScript sections start with `func`, `static func`, `class` or `#region`; shader sections are unindented lines ending in `{`. Targets a header's end, not generic Vim section boundaries. Shader section semantics are source-reviewed, not separately tested. |
| `%` | Matching bracket | **Behavior tested** for `()`, `[]`, `{}`, nesting and multiline pairs. Not full Vim `%` matching or percentage/count navigation. |
| `gm` | Middle of visible screen line in Vim | **Mapped, different:** midpoint of the entire text line. Mapping verified; viewport behavior not tested. |
| `Ctrl-u`, `Ctrl-d` | Half-page movement | **Mapped, limited:** moves the caret by half Godot's visible line count. Does not implement Vim scroll options/counts. Viewport behavior not tested. |
| `zz` | Center caret in viewport | **Mapped:** delegates to Godot's centering API. Visual viewport result not tested. |
| `/pattern` | Forward search | **Behavior tested:** incremental preview, submission and a forward match. Wrapping is tested at the regex-helper level, not for all resulting caret positions; matches at buffer offset zero are defective. Uses Godot `RegEx` (PCRE2), **not Vim regex syntax**. |
| `n N` | Next / previous search result | **Behavior tested with a defect:** `n` moves forward; `N` requests backward. A result at buffer offset zero is converted to the wrong line. See [known defects](#known-defects-and-integration-limits). |
| `?`, `*`, `#`, `g*`, `g#` | Backward prompt / word-under-cursor search | **Absent.** `N` is not a backward-search prompt. |
| `H M L`, `zt zb`, `Ctrl-f`, `Ctrl-e`, `Ctrl-y` | Screen positioning/full-page/line scrolling | **Absent.** `Ctrl-b` is reserved for Godot bookmarks rather than Vim page-up. |
| `gd gD gf gi`, `Ctrl-o`, `Ctrl-i` | Definitions, file/insert jumps, jumplist | **Absent** as Vim commands. Use Godot navigation where available. |

Search state belongs to the current command-line instance and may be lost when
switching or reloading editors. Invalid regex handling and full Vim search
option/offset parity are not established.

## Inserting, changing and editing

| Keys | Fork behavior and evidence |
| --- | --- |
| `i a I A` | **Behavior tested:** insert before/after caret, before first nonblank, or at line end. Insert text is delivered by Godot. |
| `o O` | **Behavior tested with a known defect:** open below/above. `o` at EOF inserts in the wrong place; two regression cases remain known failures. |
| Escape | Return to Normal mode through the cursor's input handler. It is not a KeyMap binding. Mode transitions are tested; physical Escape delivery is not established by headless tests. |
| `d{motion}`, `d{object}`, `dd D x` | **Behavior tested** on representative character/word/line/object deletions. Calls Godot cut, which also affects the system clipboard. |
| `c{motion}`, `c{object}`, `C s` | **Behavior tested.** Includes `cw`, `cW`, `ciw`, `caw`, `ce`, `c0`, deletion and typed replacement. `cw` on nonblank text excludes following whitespace. |
| `cc` | **Mapped:** linewise change, preserving indentation. Parser coverage; no dedicated `cc` buffer assertion. |
| `y{motion}`, `y{object}`, `yy Y` | **Mapped, integration incomplete:** calls Godot copy. `Y` is linewise like `yy`. Tests check mode/nonmutation, not native clipboard contents. |
| `p` | **Mapped, integration incomplete:** system-clipboard paste, with a Visual replacement variant. Native clipboard/paste scenario is skipped headlessly. Do not assume Vim linewise-register or platform parity. |
| `r{char}` | **Behavior tested:** replace current character. Enter/Tab translation exists, but those replacements are not individually behavior-tested. No Replace mode `R`. |
| `J` | **Behavior tested:** joins with a space and removes next-line indentation. Full Vim spacing, final-line and count semantics are not established. `gJ` is absent. |
| `~` | **Behavior tested** in Normal and characterwise Visual. No `g~` operator. |
| `u`, `Ctrl-r` | **Behavior tested:** Godot undo/redo. Whole Insert sessions are not explicitly grouped as one Vim change. In characterwise Visual, `u` lowercases instead. |
| `>{motion}`, `<{motion}`, `>>`, `<<` | **Behavior tested** on representative indentation changes using Godot indentation settings. |
| `gc{motion}`, `gcc` | **Behavior tested** for GDScript `#` comments. Shader `//` handling is source-reviewed only. This is a Vim-plugin-style extension, not a claim about every Vim installation. |
| `P X S R`, `gJ`, `gu`, `gU`, `g~` | **Absent** in Normal mode. Use supported compositions where suitable; there is no uppercase-paste or previous-character-delete alias. |
| Counts, `.`, macros, register prefixes | **Absent:** no `3j`, `2dw`, `d2w`, `3dd`, repeat-last-change `.`, `q{register}`, `@{register}`, `@@`, or `"a`/`"+`/`"_` register selection. |

Delete/change/yank/paste use Godot cut/copy/paste. There is no separate Vim
unnamed, named, numbered, small-delete or black-hole register model. Clipboard
ownership and paste are significant integration gaps, not passing tests.

## Text objects

Use these after an operator (`diw`, `ciw`, `yiw`, etc.) or while in Visual mode
(`viw`, `va(`, etc.). They are not standalone Normal-mode navigation sequences.
Representative selection and edit outcomes are tested; the inventory additionally
checks aliases and operator composition. It does not cover every cross-product.

| Inner | Around | Object |
| --- | --- | --- |
| `iw` | `aw` | word |
| `iW` | `aW` | whitespace-delimited WORD |
| `ip` | `ap` | paragraph |
| `i"` | `a"` | double quotes, current line only |
| `i'` | `a'` | single quotes, current line only |
| ``i` `` | ``a` `` | backticks, current line only |
| `i(`, `i)`, `ib` | `a(`, `a)`, `ab` | parentheses |
| `i[`, `i]` | `a[`, `a]` | square brackets |
| `i{`, `i}`, `iB` | `a{`, `a}`, `aB` | braces |

**`ciw` works:** inside `two` in `one two three`, it removes just `two`, enters
Insert mode, and typing `X` yields `one X three`. This is a buffer-level test,
not merely a mapping lookup.

Sentence objects (`is/as`), tag objects (`it/at`), angle-bracket objects (`i</a<`)
and additional plugin-specific objects are absent. Delimiter scanning is not
syntax-aware; full quote-escape, nesting and boundary parity with Vim is not
claimed.

## Visual modes

| Mode | Enter/switch | Available editing keys |
| --- | --- | --- |
| Characterwise Visual | `v` from Normal; `v` from linewise Visual | `d c y p > < gc`, `x s ~ u U`, `o`; motions and text objects |
| Linewise Visual | `V` from Normal; `V` from characterwise Visual | `d c y p > < gc`, `o`; motions and text objects |

`o` exchanges selection endpoints. Characterwise `u`/`U` lowercase/uppercase.
**`x s ~ u U` are not bound in linewise Visual.** Pressing `v` in characterwise
Visual or `V` in linewise Visual does not toggle back to Normal; use Escape.
Actions such as `J`, replacement `r`, `:`, `/`, marks and redo are not enabled in
Visual mode. `Ctrl-v` blockwise Visual, `gv` reselect, and Visual-block operations
are absent. Tests cover representative inclusive selections, switching and edits,
not physical mouse dragging or all Visual command combinations.

## Marks and recent scripts

- `m{a-zA-Z}` records the active **script** path and exact caret position.
- A backtick followed by the mark name requests a jump to that stored position.
  See the runtime limitation below before relying on exact position restoration.
- Lowercase and uppercase marks are all **global to this plugin session**. They
  are not Vim buffer-local versus file marks, do not follow subsequent edits,
  and are not persisted across plugin disable/editor restart.
- Backtick plus `0` through `9` selects recent scripts tracked by this plugin,
  not Vim's persisted numbered-mark history. Recent-file bookkeeping is tested;
  numbered jump behavior is not separately validated.
- Apostrophe linewise jumps such as `'a` and Vim special marks/jumplists are absent.
- Shader marks are not supported by the verified contract: mark creation reads
  the ScriptEditor current script even when the addon is attached to a shader.
- `:marks` lists stored entries using zero-based line and column numbers. `:delmarks` or `:delm` **clears every mark**,
  including recent-file entries. Arguments are ignored; `:delmarks a` does not
  selectively delete only `a`.

Keyboard mark creation, path/position storage, tab changes and recent-file
deduplication are tested. Marks should not be advertised as missing, but neither
should they be advertised as full Vim mark behavior.

## Command line and customization

The `:` prompt uses a small custom dispatcher, not an Ex interpreter. Supported
handler names are checked explicitly by the shortcut inventory suite.

| Input | Behavior | Verification |
| --- | --- | --- |
| `:{number}`, `:goto {number}` | Jump to a 1-based line, column zero | Numeric shorthand behavior tested; shared handler source-reviewed. |
| `/pattern`, `:find pattern` | Forward Godot regex search | Slash form behavior tested; `:find` dispatch/source reviewed, not a separate end-to-end assertion. |
| `:marks` | List marks | Real editor dispatch/output tested. |
| `:delmarks`, `:delm` | Clear all marks; no selective arguments | Alias and clearing behavior tested. |
| `:moveline {offset}`, `:movecolumn {offset}` | Relative caret movement | Real editor behavior tested. |
| `:w`, `:wa` | Emit hard-coded `Ctrl+Alt+S` / `Shift+Alt+S` editor events | **Mapped only; actual saving is not tested.** These are not file-writing APIs and may depend on editor/platform shortcuts. Use Godot's Save UI when reliability matters. |
| `:reload` | Reinitialize the addon | Reinitialization and dirty-buffer preservation tested through the underlying API; command dispatch exists. |
| `:remap` | Open the GDScript mapping source | Source-reviewed; interactive editor-opening behavior not tested. |

General Ex commands are absent: no `:q`, `:wq`, `:e`, `:b`, `:split`, `:vsplit`,
substitution (`:s`), ranges (`:%...`), `:g`, shell commands or Vimscript. Godot
provides its own files/tabs/windows. Do not assume Vim abbreviations beyond
`:delm` work.

Customize `KeyMap.map()` in [key_map.gd](../addons/godot_vim/key_map.gd) with
`KeyRemap`, then reload. There is no `.vimrc` or Ex `:map` support. The Insert-mode
`jk` and `Ctrl-[` examples in that file are **commented out**, not enabled defaults.
Insert-mode `Ctrl-c/w/u/o/r` are not addon bindings either. Native Godot behavior
may differ. `Ctrl-s` and `Ctrl-b` are intentionally left to Godot.

## Known defects and integration limits

- `o` on the final line has two exact known-failure cases, tracked upstream by
  [PR #32](https://github.com/bernardo-bruning/godot-vim/pull/32).
- **Search at offset zero:** in `tests/fixtures/sample.gd`, `n` on pattern `e`
  moves from `(column 0, line 0)` to `(3, 0)`, but `N` returns `(0, 3)` instead
  of `(0, 0)`. `idx_to_pos()` treats a zero end offset as the end of the string
  when counting newlines. This can affect any search result at the first
  character, including `/` preview/submission, `:find`, and wrapping, not only `N`.
- **Backtick mark position:** a cross-file jump to a mark saved at `(4, 2)`
  returns to the correct script but lands at `(3, 2)`, one column left. The plugin
  adjusts the line, but not the column, for Godot's one-based `edit_script` API.
  Coordinates here are zero-based. Do not rely on exact-column restoration until fixed.
- These two newly exposed defects are exact known-failure assertions in the
  editor suite, separate from the two existing `o` failures. They are documented,
  not fixed, in this audit; strict-known mode fails on them.
- Native clipboard/paste, physical keyboard input, mouse dragging, OS focus,
  IME, platform shortcuts, save operations and detached shader windows are not
  verified by the headless Linux tests. macOS/Windows have not been tested.
- Support is checked on official Godot **4.6.3** and **4.7.2**. Test totals,
  known failures, skipped scenarios and reproduction commands are in
  [tests/README.md](../tests/README.md).

## Evidence and reference baseline

- [Default key map and parsing](../addons/godot_vim/key_map.gd)
- [Command implementations](../addons/godot_vim/cursor.gd)
- [Ex dispatcher](../addons/godot_vim/dispatcher.gd) and [handlers](../addons/godot_vim/commands/)
- [Explicit shortcut inventory](../tests/shortcut_inventory.gd): supported/absent
  commands, operator composition, mode-specific availability and Ex names.
- [Motion behavior](../tests/motion_regression.gd), [editing behavior](../tests/edit_regression.gd),
  [real editor integration](../tests/editor_smoke/plugin.gd), and
  [parser/remap checks](../tests/keymap_regression.gd).
- Expected Vim concepts: [motion/objects](https://vimhelp.org/motion.txt.html),
  [changes/registers/repeat](https://vimhelp.org/change.txt.html),
  [Visual modes](https://vimhelp.org/visual.txt.html),
  [search](https://vimhelp.org/pattern.txt.html), and
  [macro recording](https://vimhelp.org/repeat.txt.html#recording).

This comparison uses documented Vim semantics, source inspection and targeted
Godot assertions. It is not a differential test against a running Vim binary.
