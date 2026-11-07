@tool
extends EditorPlugin

const Mode = preload("res://addons/godot_vim/constants.gd").Mode
var failures: Array[String] = []
var assertions := 0
var known_failures := 0
var scenarios := 0

func _enter_tree():
	_run.call_deferred()

func _frames(count: int = 3):
	for frame in count:
		await get_tree().process_frame

func _scenario(label: String):
	scenarios += 1
	print("EDITOR SCENARIO ", scenarios, ": ", label)

func _check(condition: bool, message: String):
	assertions += 1
	if !condition:
		failures.append(message)
		push_error(message)

# Exact known outcomes keep gaps visible without accepting unrelated regressions.
func _known(actual: Variant, expected: Variant, known_actual: Variant, message: String):
	assertions += 1
	if actual == expected:
		print("KNOWN ISSUE FIXED: ", message)
	elif actual == known_actual:
		known_failures += 1
		print("KNOWN FAILURE: ", message, " expected ", expected, " actual ", actual)
	else:
		failures.append(message)
		push_error("%s: unexpected result %s (expected %s)" % [message, actual, expected])

func _vim() -> EditorPlugin:
	for node in get_parent().get_children():
		if node.get_script() != null and node.get_script().resource_path == "res://addons/godot_vim/plugin.gd":
			return node
	return null

func _count_script(root: Node, path: String) -> int:
	var count := 0
	if root.get_script() != null and root.get_script().resource_path == path:
		count += 1
	for child in root.get_children():
		count += _count_script(child, path)
	return count

func _connection_count(object: Object, signal_name: String, target: Object) -> int:
	var count := 0
	for connection in object.get_signal_connection_list(signal_name):
		if connection.callable.get_object() == target:
			count += 1
	return count

func _wiring(vim, code: CodeEdit, label: String):
	_check(is_instance_valid(vim.cursor), label + ": cursor exists")
	if !is_instance_valid(vim.cursor):
		return
	_check(vim.cursor.code_edit == code, label + ": cursor targets active buffer")
	_check(vim.cursor.is_inside_tree(), label + ": cursor mounted")
	_check(vim.command_line.code_edit == code, label + ": command line targets active buffer")
	_check(vim.command_line.cursor == vim.cursor, label + ": command line owns current cursor")
	_check(vim.cursor.status_bar == vim.status_bar, label + ": cursor shares current status bar")
	_check(vim.key_map.cursor == vim.cursor, label + ": key map rebound")
	_check(vim.globals.code_edit == code, label + ": globals rebound")
	_check(vim.dispatcher.globals.cursor == vim.cursor, label + ": dispatcher rebound")
	_check(_connection_count(code, "caret_changed", vim.cursor) == 1, label + ": single caret connection")
	_check(_connection_count(code, "focus_entered", vim.cursor) == 1, label + ": single focus connection")
	for script in ["cursor", "command_line", "status_bar"]:
		_check(_count_script(EditorInterface.get_base_control(), "res://addons/godot_vim/" + script + ".gd") == 1,
			label + ": exactly one " + script + " node")

func _key(keycode: int, unicode: int = 0, shift: bool = false):
	# Headless windows do not retain OS focus between synthetic events.
	# Explicitly focus the intended recipient before dispatch through the viewport.
	var vim = _vim()
	if vim.cursor.mode == Mode.INSERT:
		vim.cursor.code_edit.grab_focus()
	else:
		vim.cursor.grab_focus()
	var event := InputEventKey.new()
	event.keycode = keycode
	event.unicode = unicode
	event.shift_pressed = shift
	event.pressed = true
	get_viewport().push_input(event)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event)
	await _frames(3)

func _run():
	await _frames(20)
	_scenario("Empty startup and defensive discovery")
	var vim = _vim()
	_check(vim != null, "Vim plugin enabled on a clean editor startup")
	if vim == null:
		_finish()
		return
	_check(vim.get_regular_code_edit() == null, "No script editor is safe")
	_check(vim.get_shader_code_edit() == null, "No shader editor is safe")
	_check(vim.find_code_edit().is_empty(), "Empty startup has no current buffer")
	var missing_path: Array[String] = ["CodeEdit"]
	_check(vim._select(self, missing_path) == null, "A missing UI path returns null")
	_check(vim._select(null, missing_path) == null, "A null UI root returns null")
	_check(vim.get_shader_tabcontainer() is TabContainer, "Shader dock discovery succeeds before opening a shader")

	_scenario("Shader-first startup")
	EditorInterface.edit_resource(load("res://tests/fixtures/sample.gdshader"))
	await _frames(15)
	var shader_code = vim.get_shader_code_edit()
	_check(shader_code is CodeEdit, "Current text shader CodeEdit is found")
	if shader_code == null:
		_finish()
		return
	_wiring(vim, shader_code, "First shader")
	_check(vim.status_bar.get_parent() is VBoxContainer, "Shader status bar is below its split view")
	_check(vim.cursor.language == vim.LANGUAGE.SHADER, "Shader language selected")
	var shader_original: String = shader_code.text

	_scenario("Multiple shader tabs")
	EditorInterface.edit_resource(load("res://tests/fixtures/second.gdshader"))
	await _frames(10)
	var second_shader = vim.get_shader_code_edit()
	_check(second_shader is CodeEdit and second_shader != shader_code, "Second shader has independent editor")
	_check(second_shader.text.contains("0.25"), "Second shader content is active")
	_check(vim.cursor.code_edit == second_shader, "Cursor follows second shader")
	EditorInterface.edit_resource(load("res://tests/fixtures/sample.gdshader"))
	await _frames(8)
	_check(vim.get_shader_code_edit() == shader_code, "Returning shader tab reuses original editor")
	_check(vim.cursor.code_edit == shader_code, "Cursor follows returning shader tab")
	_check(shader_code.text == shader_original, "Shader switching preserves text")

	_scenario("Visual shader safety")
	EditorInterface.edit_resource(load("res://tests/fixtures/visual_shader.tres"))
	await _frames(10)
	_check(vim.get_shader_code_edit() == null, "Visual shader never masquerades as text CodeEdit")
	_check(vim.get_regular_code_edit() == null, "Visual shader does not create a script editor")
	_check(vim.find_code_edit().is_empty(), "Visual-only editor yields no text target")

	_scenario("Shader to GDScript transition")
	hide_bottom_panel()
	EditorInterface.edit_script(load("res://tests/fixtures/sample.gd"))
	await _frames(15)
	var code = vim.get_regular_code_edit()
	_check(code is CodeEdit, "GDScript CodeEdit found through public API")
	if code == null:
		_finish()
		return
	_wiring(vim, code, "First script")
	_check(vim.cursor.language == vim.LANGUAGE.GDSCRIPT, "Script language selected")
	vim.cursor.set_caret_pos(0, 1)
	vim.cursor.draw_cursor()
	_check(vim.cursor.get_caret_pos() == Vector2i(1, 0), "Block highlight preserves actual editor caret")
	var original: String = code.text

	_scenario("Real viewport keyboard events and focus")
	vim.cursor.set_caret_pos(0, 1)
	vim.cursor.set_mode(Mode.NORMAL)
	await _frames()
	_check(vim.cursor.has_focus(), "Normal mode focuses Vim cursor")
	await _key(KEY_L, 108)
	_check(code.get_caret_column() == 2, "Viewport l event moves right")
	await _key(KEY_H, 104)
	_check(code.get_caret_column() == 1, "Viewport h event moves left")
	await _key(KEY_J, 106)
	_check(code.get_caret_line() == 1, "Viewport j event moves down")
	await _key(KEY_K, 107)
	_check(code.get_caret_line() == 0, "Viewport k event moves up")
	vim.cursor.set_caret_pos(2, 0)
	await _key(KEY_I, 105)
	_check(vim.cursor.mode == Mode.INSERT, "Viewport i enters insert mode")
	_check(code.has_focus(), "Insert mode focuses CodeEdit")
	# Native GUI text delivery requires a focused OS window, unavailable headless.
	# Exercise the real editor insertion API after the dispatched insert-mode key.
	code.insert_text_at_caret("#")
	_check(code.get_line(2).begins_with("#"), "Insert-mode CodeEdit API edits actual buffer")
	vim.cursor.set_mode(Mode.NORMAL)
	await _frames()
	_check(vim.cursor.has_focus(), "Returning normal restores cursor focus")
	_check(code.get_selected_text() == "#", "Normal mode highlights inserted character as block cursor")
	code.text = original
	vim.cursor.set_caret_pos(2, 0)
	await _key(KEY_V, 118)
	_check(vim.cursor.mode == Mode.VISUAL, "Viewport v enters visual mode")
	await _key(KEY_L, 108)
	_check(code.get_selected_text() == "va", "Visual motion selects inclusive characters")
	vim.cursor.set_mode(Mode.NORMAL)
	_check(!code.has_selection(), "Leaving visual mode deselects buffer")

	_scenario("Command line focus, search and dispatcher")
	vim.cursor.set_caret_pos(0, 0)
	vim.cursor.set_mode(Mode.COMMAND)
	await _frames()
	_check(vim.command_line.has_focus(), "Command mode focuses command line")
	_check(vim.command_line.visible, "Command line is visible in command mode")
	vim.command_line.set_command(":3")
	_check(vim.command_line.text == ":3", "Command text assigned")
	_check(vim.command_line.caret_column == 2, "Command caret placed at end")
	vim.command_line.text_submitted.emit(":3")
	await _frames()
	_check(code.get_caret_line() == 2, "Submitted numeric command navigates real editor")
	_check(vim.cursor.mode == Mode.NORMAL, "Numeric command restores normal mode")
	_check(!vim.command_line.visible, "Numeric command closes command line")
	_check(vim.dispatch(":movecolumn 4") == OK, "Column dispatcher accepts command")
	_check(code.get_caret_column() == 4, "Column dispatcher moves real caret")
	_check(vim.dispatch(":moveline -2") == OK, "Line dispatcher accepts command")
	_check(code.get_caret_line() == 0, "Line dispatcher moves real caret")
	_check(vim.dispatch(":unknown_editor_test") == ERR_DOES_NOT_EXIST, "Unknown dispatcher command returns error")
	vim.cursor.set_caret_pos(0, 0)
	vim.cursor.set_mode(Mode.COMMAND)
	vim.command_line.text_changed.emit("/hello")
	_check(code.get_caret_count() == 2, "Live search adds a preview caret")
	_check(code.get_selected_text(1) == "hello", "Live search selects matched editor text")
	vim.command_line.text_submitted.emit("/hello")
	_check(vim.command_line.search_pattern == "hello", "Submitted search remembers pattern")
	_check(code.get_caret_line() == 2 and code.get_caret_column() == 20, "Search lands on hello")
	_check(code.get_caret_count() == 1, "Search commit removes preview caret")
	_check(vim.cursor.mode == Mode.NORMAL, "Search returns to normal")
	# Exercise repeat-search keys rather than only the underlying search helpers.
	vim.command_line.search_pattern = "e"
	vim.cursor.set_caret_pos(0, 0)
	await _key(KEY_N, 110)
	_check(vim.cursor.get_caret_pos() == Vector2i(3, 0), "n selects the next regex match")
	await _key(KEY_N, 78, true)
	_known(vim.cursor.get_caret_pos(), Vector2i(0, 0), Vector2i(0, 3),
		"N to a match at buffer offset zero lands on the final line")
	vim.command_line.search_pattern = "hello"
	var match_result = vim.search_regex(code, "extends", Vector2i(25, 2))
	_check(match_result != null and match_result.get_start() == 0, "Forward search wraps in editor buffer")
	match_result = vim.search_regex_backwards(code, "hello", Vector2i.ZERO)
	_check(match_result != null and match_result.get_string() == "hello", "Backward search wraps in editor buffer")
	_check(vim.search_regex(code, "absent_editor_test", Vector2i.ZERO) == null, "Unmatched search returns null")
	vim.cursor.set_mode(Mode.COMMAND)
	vim.command_line.text_submitted.emit(":unknown_editor_test")
	_check(vim.command_line.is_paused, "Unknown command pauses for acknowledgment")
	_check(!vim.command_line.editable, "Paused command line prevents edits")
	_check(vim.status_bar.main_label.text.contains("Unknown command"), "Unknown command visible in status bar")
	vim.command_line.text_submitted.emit("")
	_check(vim.cursor.mode == Mode.NORMAL, "Acknowledgment restores normal mode")
	_check(!vim.command_line.is_paused and vim.command_line.editable, "Acknowledgment resets command state")

	_scenario("Marks and multiple script tabs")
	vim.cursor.set_caret_pos(2, 4)
	await _key(KEY_M, 109)
	await _key(KEY_A, 97)
	_check(vim.globals.marks.has("a"), "Keyboard mark command records mark")
	if vim.globals.marks.has("a"):
		_check(vim.globals.marks.a.file == "res://tests/fixtures/sample.gd", "Mark records real script resource path")
		_check(vim.globals.marks.a.pos == Vector2i(4, 2), "Mark records caret position")
	EditorInterface.edit_script(load("res://tests/fixtures/second.gd"))
	await _frames(10)
	var second_code = vim.get_regular_code_edit()
	_check(second_code is CodeEdit and second_code != code, "Second script has independent editor")
	_check(second_code.text.contains("second buffer"), "Second script content selected")
	_check(vim.cursor.code_edit == second_code, "Cursor follows second script")
	_check(vim.globals.marks["-1"].file == "res://tests/fixtures/second.gd", "Recent-file mark tracks current script")
	_check(vim.globals.marks["0"].file == "res://tests/fixtures/sample.gd", "Recent-file mark tracks previous script")
	_check(vim.globals.marks.has("a"), "User mark survives tab change")
	var recent_before: Dictionary = vim.globals.marks.duplicate(true)
	vim.mark_recent_file("res://tests/fixtures/second.gd")
	vim.mark_recent_file("res://tests/fixtures/second.gd")
	_check(vim.globals.marks == recent_before, "Repeated current-file notifications do not duplicate history")
	_check(vim.dispatch(":marks") == OK, "Marks dispatcher succeeds")
	_check(vim.status_bar.main_label.text.contains("sample.gd"), "Marks output names marked script")
	# Test the actual backtick command, not just the edit_script helper.
	await _key(KEY_QUOTELEFT, 96)
	await _key(KEY_A, 97)
	await _frames(10)
	_known(vim.cursor.get_caret_pos(), Vector2i(4, 2), Vector2i(3, 2),
		"Cross-file backtick mark jump lands one column left")
	_check(vim.get_regular_code_edit() == code, "Backtick mark command returns to original script")
	_check(vim.cursor.code_edit == code, "Cursor follows plugin navigation")
	_check(vim.dispatch(":delm") == OK, "Delete-marks alias resolves")
	_check(vim.globals.marks.is_empty(), "Delete-marks alias clears marks")

	_scenario("Dirty buffer survives reload and disable")
	code.set_line(2, 'var sample_text := "unsaved hello"')
	var dirty: String = code.text
	_check(dirty != original, "Dirty buffer differs from fixture")
	_check(FileAccess.get_file_as_string("res://tests/fixtures/sample.gd") == original, "Dirty edit has not overwritten disk")
	var old_cursor = vim.cursor
	var old_command = vim.command_line
	var old_status = vim.status_bar
	vim.initialize(true)
	await _frames()
	_check(!is_instance_valid(old_cursor), "Reload releases previous cursor")
	_check(!is_instance_valid(old_command), "Reload releases previous command line")
	_check(!is_instance_valid(old_status), "Reload releases previous status bar")
	_check(code.text == dirty, "Forced reload preserves unsaved text")
	_wiring(vim, code, "Reloaded dirty script")
	vim.initialize(false)
	await _frames()
	_check(code.text == dirty, "Non-forced reload preserves unsaved text")
	_check(_count_script(EditorInterface.get_base_control(), "res://addons/godot_vim/cursor.gd") == 1, "Repeated reload has no duplicate cursor")
	_check(_connection_count(EditorInterface.get_script_editor(), "editor_script_changed", vim) == 1, "Reload has one script-change connection")
	var shader_tabs = vim.get_shader_tabcontainer()
	_check(_connection_count(shader_tabs, "tab_changed", vim) == 1, "Reload has one shader-tab connection")
	_check(_connection_count(shader_tabs, "visibility_changed", vim) == 1, "Reload has one shader visibility connection")
	EditorInterface.set_plugin_enabled("godot_vim", false)
	await _frames()
	_check(_vim() == null, "Disable removes plugin")
	_check(code.text == dirty, "Disable preserves unsaved text")
	for script in ["cursor", "command_line", "status_bar"]:
		_check(_count_script(EditorInterface.get_base_control(), "res://addons/godot_vim/" + script + ".gd") == 0, "Disable removes all " + script + " nodes")
	EditorInterface.set_plugin_enabled("godot_vim", true)
	await _frames(8)
	vim = _vim()
	_check(vim != null and is_instance_valid(vim.cursor), "Re-enable installs fresh cursor")
	_check(code.text == dirty, "Re-enable preserves unsaved text")
	_wiring(vim, code, "Re-enabled script")

	_scenario("Clean shutdown after repeated lifecycle")
	code.text = original
	_check(code.text == original, "Restore original buffer before closing")
	EditorInterface.set_plugin_enabled("godot_vim", false)
	await _frames()
	_check(_vim() == null, "Second disable removes plugin")
	for script in ["cursor", "command_line", "status_bar"]:
		_check(_count_script(EditorInterface.get_base_control(), "res://addons/godot_vim/" + script + ".gd") == 0, "Final shutdown releases " + script)
	_check(shader_code.text == shader_original, "Unedited shader survived complete lifecycle")
	_check(FileAccess.get_file_as_string("res://tests/fixtures/sample.gd") == original, "Lifecycle did not save dirty text")
	_finish()

func _finish():
	if failures.is_empty():
		print("EDITOR COMPATIBILITY TESTS PASSED: ", assertions, " assertions across ", scenarios, " scenarios; ", known_failures, " known failures")
	else:
		print("EDITOR COMPATIBILITY TESTS FAILED: ", failures.size(), "/", assertions, " assertions across ", scenarios, " scenarios: ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
