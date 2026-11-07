extends SceneTree
## Pure parser/remapping checks, separate from command execution and editor UI.

const Constants = preload("res://addons/godot_vim/constants.gd")
const Mode = Constants.Mode
var checks := 0
var scenarios := 0
var failures: Array[String] = []
var map: KeyMap
var dummy: Control

func _initialize():
	_run.call_deferred()

func check(condition: bool, message: String):
	checks += 1
	if !condition:
		failures.append(message)
		push_error(message)

func scenario():
	scenarios += 1

func tokens(value: String) -> Array[String]:
	var result: Array[String] = []
	for character in value:
		result.append(character)
	return result

func event(value: String, control: bool = false, shifted: bool = false) -> InputEventKey:
	var result := InputEventKey.new()
	result.pressed = true
	result.keycode = value.to_upper().unicode_at(0)
	result.unicode = value.unicode_at(0)
	result.ctrl_pressed = control
	result.shift_pressed = shifted
	return result

func expand_keys(sequence: Array) -> Array:
	var result: Array = [[]]
	for item in sequence:
		var choices: Array = item if item is Array else ["q" if item == "{char}" else item]
		var next: Array = []
		for prefix in result:
			for choice in choices:
				var expanded: Array[String] = []
				expanded.assign(prefix)
				expanded.append(choice)
				next.append(expanded)
		result = next
	return result

func _run():
	dummy = Control.new()
	root.add_child(dummy)
	map = KeyMap.new(dummy)
	# Every declared mapping, including alternate text-object keys, must be
	# discoverable with its own context and yield the intended command payload.
	for definition in map.key_map:
		for sequence in expand_keys(definition.keys):
			scenario()
			var context: int = definition.get("context", Mode.NORMAL)
			var parsed := map.find_cmd(sequence, context, map.get_blacklist_types_in_context(context))
			check(KeyMap.is_cmd_valid(parsed), "Mapping exists: %s in %s" % [sequence, context])
			check(parsed.get("type") == definition.type, "Mapping type: %s" % [sequence])
			for field in ["motion", "operator", "action"]:
				if definition.has(field):
					check(parsed.get(field) == definition[field], "Mapping payload: %s %s" % [sequence, field])
			if definition.keys[-1] is String and definition.keys[-1] == "{char}":
				check(parsed.get("selected_char") == "q", "Wildcard captures argument: %s" % [sequence])

	for prefix in ["g", "z", "f", "t", "F", "T", "r", "m", "`", "[", "]", "d", "c", "y", ">", "<"]:
		scenario()
		var parsed := map.parse_keys(tokens(prefix), Mode.NORMAL)
		check(parsed.get("type") == KeyMap.Incomplete, "Prefix waits for more input: " + prefix)
		check(!KeyMap.is_cmd_valid(parsed), "Incomplete prefix cannot execute: " + prefix)
		await process_frame

	for sequence in ["dw", "de", "db", "d$", "d0", "dgg", "dG", "diw", "daw", "ciw", "cw", "c$", "yw", "ye", "y$", "yap", "dd", "cc", "yy", ">>", "<<"]:
		scenario()
		var parsed := map.parse_keys(tokens(sequence), Mode.NORMAL)
		check(parsed.get("type") == KeyMap.Operator, "Operator parsed: " + sequence)
		check(parsed.has("modifier"), "Operator modifier retained: " + sequence)
		check(KeyMap.is_cmd_valid(parsed), "Operator sequence executable: " + sequence)
		await process_frame

	for sequence in ["g?", "z?", "d?", "c?", "y?", "<TAB>", "<ESC>", "<C-s>", "<C-b>"]:
		scenario()
		var sequence_tokens: Array[String] = []
		sequence_tokens.assign([sequence] if sequence.begins_with("<") else tokens(sequence))
		var parsed := map.parse_keys(sequence_tokens, Mode.NORMAL)
		check(!KeyMap.is_cmd_valid(parsed), "Unknown or reserved input is not executable: " + sequence)
		await process_frame

	for key in ["h", "i", "a", "x", "d", "v", "u", "/", ":"]:
		scenario()
		check(!KeyMap.is_cmd_valid(map.find_cmd(tokens(key), Mode.INSERT)), "Default normal binding stays out of Insert: " + key)
	for key in ["d", "c", "y", "x", "u", "U", "~", "o"]:
		scenario()
		check(KeyMap.is_cmd_valid(map.parse_keys(tokens(key), Mode.VISUAL)), "Visual binding executes immediately: " + key)
		await process_frame

	for value in ["a", "A", "1", "0", "$", ":", ";", "[", "]", "é", "λ", "中"]:
		scenario()
		check(KeyMap.event_to_string(event(value)) == value, "Unicode event translation: " + value)
	for value in ["r", "s", "b", "u", "d", "["]:
		scenario()
		check(KeyMap.event_to_string(event(value, true)) == "<C-%s>" % value, "Control translation: " + value)
		check(KeyMap.event_to_string(event(value, true, true)) == "<C-%s>" % value.to_upper(), "Shift-control translation: " + value)
	for pair in [[KEY_ENTER, "<CR>"], [KEY_TAB, "<TAB>"], [KEY_ESCAPE, "<ESC>"]]:
		scenario()
		var special := InputEventKey.new()
		special.keycode = pair[0]
		check(KeyMap.event_to_string(special) == pair[1], "Special event: " + pair[1])
	for value in ["s", "b"]:
		scenario()
		map.clear()
		check(map.register_event(event(value, true), Mode.NORMAL).is_empty(), "Reserved shortcut is passed through: " + value)
		check(map.input_stream.is_empty(), "Reserved shortcut does not pollute parser: " + value)

	_test_remaps()
	_test_timeouts()
	print("Keymap regression tests: %s (%d scenarios, %d assertions)" % ["PASS" if failures.is_empty() else "FAIL", scenarios, checks])
	quit(0 if failures.is_empty() else 1)

func _test_remaps():
	for combo_order in [false, true]:
		scenario()
		var remap := KeyRemap.new(["Q"])
		if combo_order:
			remap.motion("move_by_lines", {"move_by": 2}).operator("delete")
		else:
			remap.operator("delete").motion("move_by_lines", {"move_by": 2})
		check(remap.inner.type == KeyMap.OperatorMotion, "Combining operator and motion is order independent")
		check(remap.inner.motion.move_by == 2, "Combined remap preserves motion arguments")
		check(remap.inner.operator.type == "delete", "Combined remap preserves operator")

	for insertion in ["append", "prepend", "insert_at"]:
		scenario()
		var fresh := KeyMap.new(dummy)
		var old_size := fresh.key_map.size()
		var remap := KeyRemap.new(["Q"]).motion("move_by_chars", {"move_by": 5})
		var expected_index := old_size
		if insertion == "prepend":
			remap.prepend()
			expected_index = 0
		elif insertion == "insert_at":
			remap.insert_at(2)
			expected_index = 2
		remap.apply(fresh.key_map)
		check(fresh.key_map.size() == old_size + 1, insertion + " adds exactly one mapping")
		check(fresh.key_map[expected_index].keys == ["Q"], insertion + " uses requested position")
		check(fresh.find_cmd(["Q"], Mode.NORMAL).motion.move_by == 5, insertion + " resolves the new payload")

	scenario()
	var fresh := KeyMap.new(dummy)
	var size_before := fresh.key_map.size()
	KeyRemap.new(["h"]).motion("move_by_chars", {"move_by": -5}).replace().apply(fresh.key_map)
	check(fresh.key_map.size() == size_before, "Replacement preserves mapping count")
	check(fresh.find_cmd(["h"], Mode.NORMAL).motion.move_by == -5, "Replacement takes effect")
	KeyRemap.new(["h"]).remove().apply(fresh.key_map)
	check(fresh.key_map.size() == size_before - 1, "Remove deletes exactly matching binding")
	check(!KeyMap.is_cmd_valid(fresh.find_cmd(["h"], Mode.NORMAL)), "Removed mapping no longer resolves")
	KeyRemap.new(["?"]).remove().apply(fresh.key_map)
	check(fresh.key_map.size() == size_before - 1, "Removing an absent mapping is safe")

	scenario()
	fresh = KeyMap.new(dummy)
	KeyRemap.new(["j", "k"]).action("normal").with_context(Mode.INSERT).apply(fresh.key_map)
	check(fresh.find_cmd(["j"], Mode.INSERT).type == KeyMap.Incomplete, "Insert remap prefix waits")
	check(fresh.find_cmd(["j", "k"], Mode.INSERT).action.type == "normal", "Insert remap resolves in Insert mode")
	check(fresh.find_cmd(["j"], Mode.NORMAL).motion.type == "move_by_lines", "Insert remap leaves Normal j unchanged")
	KeyRemap.new(["j", "k"]).with_context(Mode.INSERT).remove().apply(fresh.key_map)
	check(!KeyMap.is_cmd_valid(fresh.find_cmd(["j", "k"], Mode.INSERT)), "Context-constrained removal works")

	scenario()
	fresh = KeyMap.new(dummy)
	KeyRemap.new(["v"]).operator("visual", {"line_wise": true}).with_context(Mode.VISUAL_LINE).replace().apply(fresh.key_map)
	check(fresh.find_cmd(["v"], Mode.VISUAL_LINE, fresh.get_blacklist_types_in_context(Mode.VISUAL_LINE)).operator.line_wise, "Context-specific replacement updates matching context")
	check(fresh.find_cmd(["v"], Mode.NORMAL).type == KeyMap.Action, "Context-specific replacement preserves Normal binding")

	scenario()
	fresh = KeyMap.new(dummy)
	size_before = fresh.key_map.size()
	KeyRemap.new(["d", "d"]).remove().apply(fresh.key_map)
	check(fresh.key_map.size() == size_before, "Removing nonexistent two-key mapping must not remove operator prefix")
	check(fresh.find_cmd(["d"], Mode.NORMAL).type == KeyMap.Operator, "Exact removal preserves shorter operator binding")

func _test_timeouts():
	scenario()
	map.clear()
	check(!map.handle_insert_mode_timeout(), "First Insert key does not time out")
	map.input_stream = ["j"]
	map.last_insert_mode_input_ms = Time.get_ticks_msec()
	check(!map.handle_insert_mode_timeout(), "Immediate Insert continuation stays active")
	map.last_insert_mode_input_ms = Time.get_ticks_msec() - KeyMap.INSERT_MODE_TIMEOUT_MS - 1
	check(map.handle_insert_mode_timeout(), "Expired Insert continuation times out")
	map.clear()
	check(map.get_input_stream_as_string().is_empty(), "Clear discards all pending keys")
	map.input_stream = ["g", "c"]
	check(map.get_input_stream_as_string() == "gc", "Pending stream retains exact key order")
