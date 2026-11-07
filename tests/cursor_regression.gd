extends SceneTree
## Run after importing: godot --headless --path . --script tests/cursor_regression.gd

const Cursor = preload("res://addons/godot_vim/cursor.gd")
const Mode = Cursor.Mode
var cursor: Cursor
var edit: CodeEdit
var failures: int = 0
var assertions: int = 0


func _initialize():
	call_deferred("run")


func check(condition: bool, description: String):
	assertions += 1
	if !condition:
		failures += 1
		push_error(description)


func key(value: String):
	var event := InputEventKey.new()
	event.pressed = true
	event.unicode = value.unicode_at(0)
	event.keycode = value.to_upper().unicode_at(0)
	cursor.draw_cursor()
	cursor.key_map.register_event(event, cursor.mode)
	await process_frame
	cursor.draw_cursor()


func reset(text: String = "abcdef\nghijkl\n\nmnopqr", column: int = 2):
	cursor.set_mode(Mode.INSERT)
	edit.text = text
	cursor.set_mode(Mode.NORMAL)
	cursor.set_caret_pos(0, column)
	await process_frame
	cursor.draw_cursor()


func run():
	edit = CodeEdit.new()
	root.add_child(edit)
	cursor = Cursor.new()
	cursor.code_edit = edit
	cursor.command_line = Cursor.CommandLine.new()
	root.add_child(cursor.command_line)
	cursor.status_bar = Cursor.StatusBar.new()
	root.add_child(cursor.status_bar)
	cursor.key_map = KeyMap.new(cursor)
	root.add_child(cursor)
	await process_frame

	await reset()
	for i in range(3):
		cursor.draw_cursor()
		check(cursor.get_column() == 2, "Redrawing must not advance the caret")
	check(edit.get_selected_text() == "c", "Normal mode highlights the current character")
	for motion in ["h", "l", "j", "k"]:
		await key(motion)
		check(cursor.mode == Mode.NORMAL, "Motion %s must not enter Visual mode" % motion)
		check(edit.get_selected_text().length() == 1, "Motion %s must keep a one-character highlight" % motion)
		if motion == "h":
			check(cursor.get_caret_pos() == Vector2i(1, 0), "h moves left by one")
		elif motion == "l":
			check(cursor.get_caret_pos() == Vector2i(2, 0), "l moves right by one")
		elif motion == "j":
			check(cursor.get_caret_pos() == Vector2i(2, 1), "j moves down by one")
		else:
			check(cursor.get_caret_pos() == Vector2i(2, 0), "k moves up by one")

	for insertion in ["i", "a"]:
		await reset()
		await key(insertion)
		check(cursor.mode == Mode.INSERT, "%s enters Insert mode" % insertion)
		check(!edit.has_selection(), "Insert mode must clear the block selection immediately")
		edit.insert_text_at_caret("X")
		check(edit.get_line(0) == ("abXcdef" if insertion == "i" else "abcXdef"), "%s inserts at the expected position without replacing text" % insertion)
		cursor.reset_normal()
		await process_frame
		check(cursor.get_column() == (2 if insertion == "i" else 3), "Escape leaves the caret on the inserted character")

	await reset()
	await key("v")
	check(edit.get_selected_text() == "c", "Visual mode initially selects one character")
	await key("l")
	check(edit.get_selected_text() == "cd", "Forward Visual motion includes both endpoints")
	check(cursor.get_column() == 3, "Visual caret tracks the inclusive endpoint")
	await key("h")
	await key("h")
	check(edit.get_selected_text() == "bc", "Backward Visual motion includes both endpoints")
	await key("o")
	check(cursor.get_column() == 2, "Visual o swaps the logical endpoints")
	cursor.reset_normal()
	await process_frame
	check(cursor.get_column() == 2, "Leaving Visual mode preserves the logical caret")

	await reset()
	await key("v")
	await key("l")
	await key("x")
	check(edit.get_line(0) == "abef", "Visual delete removes exactly the selected characters")
	check(cursor.mode == Mode.NORMAL, "Visual delete returns to Normal mode")

	await reset()
	await key("V")
	check(edit.get_selected_text() == "abcdef", "Visual-line mode includes the whole first line")
	await key("j")
	check(edit.get_selected_text() == "abcdef\nghijkl", "Visual-line j extends by one line")
	check(cursor.get_caret_pos() == Vector2i(2, 1), "Visual-line mode keeps the logical caret column")
	await key("k")
	check(edit.get_selected_text() == "abcdef", "Visual-line k contracts by one line")
	cursor.reset_normal()
	await process_frame
	check(cursor.get_caret_pos() == Vector2i(2, 0), "Leaving Visual-line mode restores the logical caret")

	await reset()
	edit.select(0, 1, 0, 4)
	cursor.adopt_mouse_selection()
	check(cursor.mode == Mode.VISUAL, "Mouse selection enters Visual mode")
	check(edit.get_selected_text() == "bcd", "Entering Visual preserves the native mouse selection")
	check(edit.get_caret_column() == 4 and edit.get_selection_origin_column() == 1, "Entering Visual preserves the native drag endpoint and anchor")
	cursor.adopt_mouse_selection()
	check(cursor.selection_from == Vector2i(1, 0) and cursor.selection_to == Vector2i(3, 0), "Repeated mouse synchronization keeps the original anchor")
	await key("x")
	check(edit.get_line(0) == "aef", "Deleting an adopted mouse selection removes the originally selected text")
	await reset()
	edit.select(0, 1, 1, 0)
	cursor.adopt_mouse_selection()
	check(cursor.selection_to == Vector2i(6, 0), "A forward drag ending at column zero includes the previous newline")
	cursor.update_visual_selection()
	check(edit.get_selected_text() == "bcdef\n", "Rebuilding a forward newline selection preserves its text")
	edit.select(1, 0, 0, 2)
	cursor.adopt_mouse_selection()
	check(cursor.selection_from == Vector2i(6, 0) and cursor.selection_to == Vector2i(2, 0), "A backward drag converts the exclusive anchor across lines")
	cursor.update_visual_selection()
	check(edit.get_selected_text() == "cdef\n", "Rebuilding a backward newline selection preserves its text")
	edit.select(2, 0, 3, 0)
	cursor.adopt_mouse_selection()
	check(cursor.selection_to == Vector2i(0, 2), "A drag across an empty line selects its newline")
	cursor.update_visual_selection()
	check(edit.get_selected_text() == "\n", "Rebuilding an empty-line selection preserves its newline")

	await reset()
	await key("x")
	check(edit.get_line(0) == "abdef", "x deletes only the current character")
	await reset("", 0)
	await key("h")
	await key("j")
	check(cursor.get_caret_pos() == Vector2i.ZERO, "Empty-buffer motions remain at column zero")
	await key("a")
	edit.insert_text_at_caret("X")
	check(edit.text == "X", "Append works in an empty buffer")

	print("Cursor regression tests: %s (%d assertions)" % ["PASS" if failures == 0 else "%d failures" % failures, assertions])
	quit(0 if failures == 0 else 1)
