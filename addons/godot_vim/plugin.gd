@tool
extends EditorPlugin

const StatusBar = preload("res://addons/godot_vim/status_bar.gd")
const CommandLine = preload("res://addons/godot_vim/command_line.gd")
const Cursor = preload("res://addons/godot_vim/cursor.gd")
const Dispatcher = preload("res://addons/godot_vim/dispatcher.gd")

const Constants = preload("res://addons/godot_vim/constants.gd")
const DIGITS = Constants.DIGITS
const LANGUAGE = Constants.Language

var cursor: Cursor
var key_map: KeyMap
var command_line: CommandLine
var status_bar: StatusBar
var globals: Dictionary = {}
var dispatcher: Dispatcher


func _enter_tree():
	EditorInterface.get_script_editor().connect("editor_script_changed", _on_script_changed)

	var shader_tabcontainer = get_shader_tabcontainer() as TabContainer
	if shader_tabcontainer != null:
		shader_tabcontainer.tab_changed.connect(_on_shader_tab_changed)
		shader_tabcontainer.visibility_changed.connect(_on_shader_tab_visibility_changed)
	else:
		push_error(
			"[Godot VIM] Failed to get shader editor's TabContainer. Vim will be disabled in the shader editor"
		)

	globals = {}
	initialize(true)


func initialize(forced: bool = false):
	_load(forced)

	print("[Godot VIM] Initialized.")
	print("    If you wish to set keybindings, please run :remap in the command line")


func _on_script_changed(script: Script):
	if !script:
		return

	mark_recent_file(script.resource_path)

	_load()


func _on_shader_tab_changed(_tab: int):
	call_deferred(&"_load")


func _on_shader_tab_visibility_changed():
	call_deferred(&"_load")


func mark_recent_file(path: String):
	if !globals.has("marks"):
		globals.marks = {}
	var marks: Dictionary = globals.marks
	# The editor can emit repeated changes for the same script.
	if marks.has("-1") and marks["-1"].file == path:
		return

	# Check if path is already in the recent files (stored in start_index)
	# This is to avoid flooding the recent files list with the same files
	var start_index: int = 0
	while start_index <= 9:
		var m: String = str(start_index)
		if !marks.has(m) or marks[m].file == path:  # Found
			break
		start_index += 1

	# Shift all files from start_index down one
	for i in range(start_index, -1, -1):
		var m: String = str(i)
		var prev_m: String = str(i - 1)
		if !marks.has(prev_m):
			continue
		marks[m] = marks[prev_m]

	# Mark "-1" won't be accessible to the user
	# It's just the current file, and will be indexed next time the
	# loop above ^^^ is called
	marks["-1"] = {"file": path, "pos": Vector2i(-1, 0)}


func edit_script(path: String, pos: Vector2i):
	var script = load(path)
	if script == null:
		status_bar.display_error('Could not open file "%s"' % path)
		return ""
	EditorInterface.edit_script(script, pos.y, pos.x)


#region LOAD


func _init_cursor(code_edit: CodeEdit, language: LANGUAGE):
	if cursor != null:
		cursor.queue_free()

	cursor = Cursor.new()
	cursor.code_edit = code_edit
	cursor.language = language
	cursor.globals = globals


func _init_command_line(code_edit: CodeEdit):
	if command_line != null:
		command_line.queue_free()
	command_line = CommandLine.new()

	command_line.code_edit = code_edit
	cursor.command_line = command_line
	command_line.cursor = cursor
	command_line.globals = globals
	command_line.hide()


func _init_status_bar():
	if status_bar != null:
		status_bar.queue_free()
	status_bar = StatusBar.new()
	cursor.status_bar = status_bar
	command_line.status_bar = status_bar


func _load(forced: bool = false):
	if globals == null:
		globals = {}

	var result: Dictionary = find_code_edit()
	if result.is_empty():
		return
	var code_edit: CodeEdit = result.code_edit
	var language: LANGUAGE = result.language

	_init_cursor(code_edit, language)
	_init_command_line(code_edit)
	_init_status_bar()

	# KeyMap
	if key_map == null or forced:
		key_map = KeyMap.new(cursor)
	else:
		key_map.cursor = cursor
	cursor.key_map = key_map

	var script_editor = EditorInterface.get_script_editor()
	if script_editor == null:
		return
	var script_editor_base = script_editor.get_current_editor()
	if language != LANGUAGE.SHADER and script_editor_base == null:
		return

	globals.command_line = command_line
	globals.status_bar = status_bar
	globals.code_edit = code_edit
	globals.cursor = cursor
	globals.script_editor = script_editor
	globals.vim_plugin = self
	globals.key_map = key_map

	dispatcher = Dispatcher.new()
	dispatcher.globals = globals

	# Add nodes
	if language != LANGUAGE.SHADER:
		script_editor_base.add_child(cursor)
		script_editor_base.add_child(status_bar)
		script_editor_base.add_child(command_line)
		return

	# Attach below the shader editor's split view, independent of nested panes.
	var shader_tab = get_shader_tabcontainer().get_current_tab_control()
	var shaders_container = _select(shader_tab, ["VBoxContainer"])
	if shaders_container == null:
		# We do not print an error here because for this to fail,
		#  get_shader_code_edit() (through find_code_edit()) must have
		#  already failed
		return

	shaders_container.add_child(cursor)
	shaders_container.add_child(status_bar)
	shaders_container.add_child(command_line)


#endregion LOAD


func dispatch(command: String):
	return dispatcher.dispatch(command)


## Finds whatever CodeEdit is open
func find_code_edit() -> Dictionary:
	var code_edit: CodeEdit = get_shader_code_edit()
	var language: LANGUAGE = LANGUAGE.SHADER
	# Shader panel not open; normal gdscript code edit
	if code_edit == null:
		code_edit = get_regular_code_edit()
		language = LANGUAGE.GDSCRIPT
	if code_edit == null:
		return {}

	return {
		"code_edit": code_edit,
		"language": language,
	}


## Gets the regular GDScript CodeEdit using the public ScriptEditorBase API.
func get_regular_code_edit() -> CodeEdit:
	var editor = EditorInterface.get_script_editor().get_current_editor()
	if editor == null:
		return null
	return editor.get_base_editor() as CodeEdit


## Returns the active text shader editor, ignoring visual shaders and other tabs.
func get_shader_code_edit() -> CodeEdit:
	var container = get_shader_tabcontainer()
	if container == null or !container.is_visible_in_tree():
		return null
	var editor = container.get_current_tab_control()
	if editor == null or !editor.is_class("TextShaderEditor"):
		return null
	var code_edits = editor.find_children("*", "CodeEdit", true, false)
	return code_edits[0] as CodeEdit if !code_edits.is_empty() else null


func get_shader_tabcontainer() -> TabContainer:
	# Godot 4.6+ hosts the shader editor in an EditorDock rather than the
	# old fixed ancestor chain through a WindowWrapper.
	var dock = EditorInterface.get_base_control().find_child("Shader Editor", true, false)
	if dock != null:
		return _select(dock, ["HSplitContainer", "TabContainer"]) as TabContainer
	return null


func _select(obj: Node, types: Array[String]) -> Node:
	for type in types:
		if obj == null:
			return null
		var match_node: Node = null
		for child in obj.get_children():
			if child.is_class(type):
				match_node = child
				break
		obj = match_node
	return obj


func _exit_tree():
	if cursor != null:
		cursor.queue_free()
	if command_line != null:
		command_line.queue_free()
	if status_bar != null:
		status_bar.queue_free()


# -------------------------------------------------------------
# ** UTIL **
# -------------------------------------------------------------


func search_regex(text_edit: TextEdit, pattern: String, from_pos: Vector2i) -> RegExMatch:
	var regex: RegEx = RegEx.new()
	var err: int = regex.compile(pattern)
	var idx: int = pos_to_idx(text_edit, from_pos)
	var res: RegExMatch = regex.search(text_edit.text, idx)
	if res == null:
		return regex.search(text_edit.text, 0)
	return res


func search_regex_backwards(text_edit: TextEdit, pattern: String, from_pos: Vector2i) -> RegExMatch:
	var regex: RegEx = RegEx.new()
	var err: int = regex.compile(pattern)
	var idx: int = pos_to_idx(text_edit, from_pos)
	# We use pop_back() so it doesn't print an error
	var res: RegExMatch = regex.search_all(text_edit.text, 0, idx).pop_back()
	if res == null:
		return regex.search_all(text_edit.text).pop_back()
	return res


func pos_to_idx(text_edit: TextEdit, pos: Vector2i) -> int:
	text_edit.select(0, 0, pos.y, pos.x)
	var len: int = text_edit.get_selected_text().length()
	text_edit.deselect()
	return len


func idx_to_pos(text_edit: TextEdit, idx: int) -> Vector2i:
	var line: int = text_edit.text.count("\n", 0, idx)
	var col: int = idx - text_edit.text.rfind("\n", idx) - 1
	return Vector2i(col, line)


func get_first_non_digit_idx(str: String) -> int:
	if str.is_empty():
		return -1
	if str[0] == "0":
		return 0  # '0...' is an exception
	for i in str.length():
		if !DIGITS.contains(str[i]):
			return i
	return -1  # All digits


## Repeat the function `f` and accumulate the result. A bit like Array::reduce()
## f: func(T) -> T  where T is the previous output
func repeat_accum(count: int, inital_value: Variant, f: Callable) -> Variant:
	var value: Variant = inital_value
	for _index in count:
		value = f.call(value)
	return value
