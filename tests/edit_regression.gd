extends SceneTree
## Command-level editing tests. Import the project before running with --script.
## Native CodeEdit typing supplies Insert text; every Vim command uses register_event.
const Cursor = preload("res://addons/godot_vim/cursor.gd")
const Mode = Cursor.Mode
var cursor: Cursor
var edit: CodeEdit
var failures := 0
var assertions := 0
var scenarios := 0
var known_failures := 0
var skipped_scenarios := 0
var label := ""

func _initialize():
	call_deferred("run")

func expect(actual: Variant, expected: Variant, property: String):
	assertions += 1
	if actual != expected:
		failures += 1
		push_error("%s: %s expected %s, actual %s" % [label, property, var_to_str(expected), var_to_str(actual)])

# Keep the open upstream defect visible without hiding any different failure.
func expect_known(actual: String, expected: String, known_actual: String, issue: String):
	assertions += 1
	if actual == expected:
		print("KNOWN ISSUE FIXED: ", issue, " ", label)
	elif actual == known_actual:
		known_failures += 1
		print("KNOWN FAILURE ", issue, ": ", label, " expected ", var_to_str(expected), " actual ", var_to_str(actual))
	else:
		failures += 1
		push_error("%s: unexpected behavior for %s: %s" % [label, issue, var_to_str(actual)])

func key(value: String):
	var event := InputEventKey.new()
	event.pressed = true
	if value == "<C-r>":
		event.keycode = KEY_R
		event.ctrl_pressed = true
	else:
		event.unicode = value.unicode_at(0)
		event.keycode = value.to_upper().unicode_at(0)
	cursor.draw_cursor()
	var result: Dictionary = cursor.key_map.register_event(event, cursor.mode)
	await process_frame
	cursor.draw_cursor()
	return result

func sequence(keys: String):
	for value in keys:
		await key(value)

func reset(name: String, text: String, column := 0, line := 0):
	label = name
	scenarios += 1
	# Fresh controls also isolate undo history, selections, and operator prefixes.
	if is_instance_valid(cursor):
		cursor.queue_free()
		edit.queue_free()
		await process_frame
	edit = CodeEdit.new()
	edit.indent_size = 4
	root.add_child(edit)
	cursor = Cursor.new()
	cursor.code_edit = edit
	cursor.command_line = Cursor.CommandLine.new()
	cursor.status_bar = Cursor.StatusBar.new()
	cursor.add_child(cursor.command_line)
	cursor.add_child(cursor.status_bar)
	cursor.key_map = KeyMap.new(cursor)
	root.add_child(cursor)
	cursor.set_mode(Mode.INSERT)
	edit.text = text
	edit.clear_undo_history()
	cursor.set_mode(Mode.NORMAL)
	cursor.set_caret_pos(line, column)
	await process_frame
	cursor.draw_cursor()

func editing_case(name: String, initial: String, column: int, line: int, keys: String, expected: String, mode := Mode.NORMAL):
	await reset(name, initial, column, line)
	await sequence(keys)
	expect(edit.text, expected, "buffer")
	expect(cursor.mode, mode, "mode")

func run():
	# Insert/append at start, middle, end, whitespace, empty, and Unicode.
	for row in [
		["i", "abcd", 0, "Xabcd"], ["i", "abcd", 2, "abXcd"],
		["a", "abcd", 0, "aXbcd"], ["a", "abcd", 3, "abcdX"],
		["I", "  abc", 4, "  Xabc"], ["I", "abc", 2, "Xabc"],
		["A", "abc", 0, "abcX"], ["A", "abc  ", 1, "abc  X"],
		["i", "", 0, "X"], ["a", "", 0, "X"],
		["I", "", 0, "X"], ["A", "", 0, "X"],
		["i", "α🙂β", 1, "αX🙂β"], ["a", "α🙂β", 1, "α🙂Xβ"],
	]:
		await reset("Insert %s in %s at %d" % [row[0], var_to_str(row[1]), row[2]], row[1], row[2])
		await key(row[0])
		expect(cursor.mode, Mode.INSERT, "mode before typing")
		expect(edit.has_selection(), false, "selection before typing")
		edit.insert_text_at_caret("X")
		expect(edit.text, row[3], "buffer after typing")

	for row in [
		["o", "abc\ndef", 0, "abc\nX\ndef"],
		["O", "abc\ndef", 0, "X\nabc\ndef"],
		["O", "abc\ndef", 1, "abc\nX\ndef"],
		["O", "", 0, "X\n"],
		# Known upstream #32: o at EOF must append, never insert above.
		["o", "abc", 0, "abc\nX", "\nXabc"],
		["o", "abc\ndef", 1, "abc\ndef\nX", "abc\n\nXdef"],
	]:
		await reset("Open %s line %d in %s" % [row[0], row[2], var_to_str(row[1])], row[1], 0, row[2])
		await key(row[0])
		expect(cursor.mode, Mode.INSERT, "mode")
		edit.insert_text_at_caret("X")
		if row.size() > 4:
			expect_known(edit.text, row[3], row[4], "upstream#32")
		else:
			expect(edit.text, row[3], "buffer")

	for row in [
		["x", "abcd", 0, "bcd"], ["x", "abcd", 2, "abd"],
		["x", "abcd", 3, "abc"], ["x", "a", 0, ""],
		["x", "", 0, ""], ["x", "α🙂β", 1, "αβ"],
		["dl", "abcd", 1, "acd"], ["dh", "abcd", 2, "acd"],
		["d0", "abcd", 2, "cd"], ["d$", "abcd", 1, "a"],
		["D", "abcd", 1, "a"], ["dw", "one two three", 0, "two three"],
		["de", "one two", 0, " two"], ["db", "one two", 4, "two"],
		["dW", "one.two three", 0, "three"], ["dE", "one.two three", 0, " three"],
		["df,", "ab,cd,ef", 0, "cd,ef"], ["dt,", "ab,cd,ef", 0, ",cd,ef"],
		["diw", "one two three", 5, "one  three"], ["daw", "one two three", 5, "one three"],
		["diW", "one a.b three", 5, "one  three"],
		["rZ", "abcd", 1, "aZcd"], ["rλ", "α🙂β", 1, "αλβ"],
		["rZ", "a", 0, "Z"], ["~", "aBc", 0, "ABc"],
		["~", "aBc", 1, "abc"], ["~", "123", 1, "123"],
	]:
		await editing_case("Normal %s in %s at %d" % [row[0], var_to_str(row[1]), row[2]], row[1], row[2], 0, row[0], row[3])

	for row in [
		["s", "abcd", 1, "acd", "aXcd"],
		["s", "a", 0, "", "X"],
		["cw", "one two", 0, " two", "X two"],
		["cw", "one two", 2, "on two", "onX two"],
		["cw", "one  two", 3, "onetwo", "oneXtwo"],
		["cw", "one.two next", 0, ".two next", "X.two next"],
		["cW", "one.two next", 0, " next", "X next"],
		["cw", "one.two next", 3, "onetwo next", "oneXtwo next"],
		["cW", "one.two next", 3, "one next", "oneX next"],
		["ce", "one two", 0, " two", "X two"],
		["ciw", "one two three", 5, "one  three", "one X three"],
		["caw", "one two three", 5, "one three", "one Xthree"],
		["C", "abcd", 1, "a", "aX"],
		["c0", "abcd", 2, "cd", "Xcd"],
	]:
		await editing_case("Change %s" % row[0], row[1], row[2], 0, row[0], row[3], Mode.INSERT)
		edit.insert_text_at_caret("X")
		expect(edit.text, row[4], "typed replacement")

	for delimiters in [["(", ")"], ["[", "]"], ["{", "}"], ['"', '"'], ["'", "'"], ["`", "`"]]:
		var text: String = "a" + delimiters[0] + "inside" + delimiters[1] + "z"
		for scope in ["i", "a"]:
			var expected: String = "a" + delimiters[0] + delimiters[1] + "z" if scope == "i" else "az"
			await editing_case("Text object d%s%s" % [scope, delimiters[0]], text, 4, 0, "d" + scope + delimiters[0], expected)

	for row in [
		["vlx", "abcd", 1, "ad", Mode.NORMAL],
		["vhd", "abcd", 2, "ad", Mode.NORMAL],
		["vls", "abcd", 1, "ad", Mode.INSERT],
		["vlc", "abcd", 1, "ad", Mode.INSERT],
		["vlU", "aBcD", 1, "aBCD", Mode.NORMAL],
		["vlu", "aBCD", 1, "abcD", Mode.NORMAL],
		["vl~", "aBcD", 1, "abCD", Mode.NORMAL],
		["viwx", "one two three", 5, "one  three", Mode.NORMAL],
		["vllhx", "abcde", 1, "ade", Mode.NORMAL],
		["vlx", "α🙂βδ", 1, "αδ", Mode.NORMAL],
	]:
		await editing_case("Visual %s in %s" % [row[0], row[1]], row[1], row[2], 0, row[0], row[3], row[4])

	for row in [
		["dd", "one\ntwo\nthree", 1, "one\nthree"],
		["dd", "one\ntwo\nthree", 2, "one\ntwo"],
		["dj", "one\ntwo\nthree\nfour", 1, "one\nfour"],
		["dk", "one\ntwo\nthree\nfour", 2, "one\nfour"],
		["Vd", "one\ntwo\nthree", 1, "one\nthree"],
		["Vjd", "one\ntwo\nthree\nfour", 1, "one\nfour"],
		["J", "one\n  two\nthree", 0, "one two\nthree"],
		["J", "α\n\tβ", 0, "α β"],
		[">>", "one\ntwo", 0, "\tone\ntwo"],
		["<<", "\tone\ntwo", 0, "one\ntwo"],
		["Vj>", "one\ntwo\nthree", 0, "\tone\n\ttwo\nthree"],
		["Vj<", "\tone\n\ttwo\nthree", 0, "one\ntwo\nthree"],
		["gcc", "one\ntwo", 0, "# one\ntwo"],
		["gcc", "# one\ntwo", 0, "one\ntwo"],
		["Vjgc", "one\ntwo\nthree", 0, "# one\n# two\nthree"],
		["gcc", "\nnext", 0, "\nnext"],
	]:
		await editing_case("Lines %s on line %d" % [row[0], row[2]], row[1], 0, row[2], row[0], row[3])

	for row in [["x", "abcd", "bcd"], ["rZ", "abcd", "Zbcd"], ["J", "ab\ncd", "ab cd"], ["gcc", "abc", "# abc"], [">>", "abc", "\tabc"]]:
		await reset("Undo/redo " + row[0], row[1])
		await sequence(row[0])
		expect(edit.text, row[2], "edited buffer")
		await key("u")
		expect(edit.text, row[1], "undo buffer")
		await key("<C-r>")
		expect(edit.text, row[2], "redo buffer")

	# Headless DisplayServer has no native clipboard. Still execute yank commands
	# and verify nonmutation/mode; only inspect clipboard/paste on supported drivers.
	var has_clipboard := DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
	for keys in ["yw", "yiw", "yy", "Y", "vly", "Vjy"]:
		await editing_case("Yank " + keys, "one two\nthree", 0, 0, keys, "one two\nthree")
	if has_clipboard:
		await reset("Clipboard character yank/paste", "abcd")
		await sequence("vly")
		expect(DisplayServer.clipboard_get(), "ab", "yanked text")
		await sequence("0p")
		expect(edit.text, "aabbcd", "pasted buffer")
	else:
		skipped_scenarios += 1
		print("LIMITATION: native clipboard unsupported; yank command/nonmutation checks executed, clipboard content and paste integration skipped (no production seam).")
	# Counts are intentionally not implemented: assert rejection without mutation.
	await reset("Unsupported numeric count", "abcdef")
	var result: Dictionary = await key("3")
	expect(result.get("type"), KeyMap.NotFound, "numeric prefix rejected")
	expect(edit.text, "abcdef", "unsupported count preserves buffer")
	print("Edit regression tests: %s; %d assertions executed in %d scenarios; %d known failures; %d skipped scenarios" % ["PASS" if failures == 0 else "%d failures" % failures, assertions, scenarios, known_failures, skipped_scenarios])
	quit(0 if failures == 0 else 1)
