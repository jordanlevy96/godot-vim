@tool
extends EditorPlugin

var failures: Array[String] = []

func _enter_tree():
	_run.call_deferred()

func _frames(count: int = 5):
	for frame in count:
		await get_tree().process_frame

func _check(condition: bool, message: String):
	if !condition:
		failures.append(message)
		push_error(message)

func _vim() -> EditorPlugin:
	for node in get_parent().get_children():
		if node.get_script() != null and node.get_script().resource_path == "res://addons/godot_vim/plugin.gd":
			return node
	return null

func _run():
	await _frames(20)
	var vim = _vim()
	_check(vim != null, "Vim plugin enabled on a clean editor startup")
	if vim == null:
		_finish()
		return
	_check(vim.get_regular_code_edit() == null, "No script editor is safe")
	_check(vim.get_shader_code_edit() == null, "No shader editor is safe")
	var missing_path: Array[String] = ["CodeEdit"]
	_check(vim._select(self, missing_path) == null, "A missing UI path returns null")

	# A shader must work even before any GDScript file has been opened.
	EditorInterface.edit_resource(load("res://tests/fixtures/sample.gdshader"))
	await _frames(20)
	var shader_code = vim.get_shader_code_edit()
	_check(shader_code is CodeEdit, "Current text shader CodeEdit is found")
	_check(is_instance_valid(vim.cursor), "Shader-first startup installs the cursor")
	if is_instance_valid(vim.cursor):
		_check(vim.cursor.code_edit == shader_code, "Cursor attached to the active shader")
		_check(vim.cursor.is_inside_tree(), "Shader cursor is in the editor tree")
		_check(vim.status_bar.get_parent() is VBoxContainer, "Shader status bar is below its split view")

	hide_bottom_panel()
	EditorInterface.edit_script(load("res://tests/fixtures/sample.gd"))
	await _frames(20)
	var code = vim.get_regular_code_edit()
	_check(code is CodeEdit, "GDScript CodeEdit is found through the public API")
	_check(is_instance_valid(vim.cursor), "Script startup installs the cursor")
	if is_instance_valid(vim.cursor):
		_check(vim.cursor.code_edit == code, "Cursor switches from shader to GDScript")
		vim.cursor.set_caret_pos(0, 1)
		vim.cursor.draw_cursor()
		_check(vim.cursor.get_caret_pos() == Vector2i(1, 0), "Block highlight preserves the actual editor caret")
		var old_cursor = vim.cursor
		vim.initialize(true)
		await _frames()
		_check(!is_instance_valid(old_cursor), "Reload releases the previous cursor")
		_check(vim.cursor.code_edit == code, "Reload keeps the correct CodeEdit")

	EditorInterface.set_plugin_enabled("godot_vim", false)
	await _frames()
	_check(_vim() == null, "Disable removes the plugin")
	EditorInterface.set_plugin_enabled("godot_vim", true)
	await _frames(10)
	vim = _vim()
	_check(vim != null and is_instance_valid(vim.cursor), "Re-enable installs a fresh cursor")
	EditorInterface.set_plugin_enabled("godot_vim", false)
	await _frames()
	_finish()

func _finish():
	if failures.is_empty():
		print("EDITOR COMPATIBILITY TESTS PASSED")
	else:
		print("EDITOR COMPATIBILITY TESTS FAILED: ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
