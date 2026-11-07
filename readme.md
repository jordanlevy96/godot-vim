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

The runner uses a temporary project and isolated editor settings. It checks
cursor movement, Normal/Insert/Visual mode transitions, inclusive selections,
shader-first startup, switching to GDScript, plugin reload, and disable/re-enable.
Both tested Godot versions also run in GitHub Actions. These headless checks do
not replace interactive testing of mouse selection, platform shortcuts, or
detached editor windows.

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
