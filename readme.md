# godot-vim
Basic vim bindings inside of the godot IDE

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

The runner uses a temporary project and isolated editor settings. Five suites
cover cursor compatibility, key parsing/remapping, motions/text objects,
editing/operators, and editor integration. Both supported versions run in
GitHub Actions, with JSON result reports saved as artifacts.

Run one suite with `--suite motion`, save counts with `--report results.json`,
or use `--strict-known` to fail on documented upstream defects as well.

The two `o`-at-EOF reproductions from upstream [PR #32](https://github.com/bernardo-bruning/godot-vim/pull/32)
remain explicit known failures. Headless native clipboard/paste checks are
skipped when the display driver has no clipboard. These are not passing tests.
See [tests/README.md](tests/README.md) for coverage, results, and limitations.

# vim commands implemented
TO understand what each of the commands do, simply fire up a real instance of vim and run `:help <command>`

## motion

```
  h, j, k, l
  w, e, ge, b
  f, t, F, T
  ;
  ,
  $
  ^
  0
  gg
  G
  }
  {
  (Marks not yet implemented, please use Godot bookmarks)
```

## insert

```
  i I
  a A
  o O
```

## visual

```
  v
  V
```

## undo

```
  u
```

## cmdline
```
  <C-r>
```

## repeat
```
  .
  :
```

## pattern
```
  /
  n
  N
```

## scroll
```
  zz
```

## change

```
  J
  d dd D
  p
  x
  s
  r
  y yy
  c cc C
  > >>
  < <<
```
