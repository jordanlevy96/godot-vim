extends SceneTree
## An explicit documentation contract, independent of iterating KeyMap.key_map.
## These checks prove dispatch availability, not complete Vim semantics.
const Mode = preload("res://addons/godot_vim/constants.gd").Mode
const Dispatcher = preload("res://addons/godot_vim/dispatcher.gd")
var map: KeyMap
var checks := 0
var scenarios := 0
var failures := 0

func _initialize():
	_run.call_deferred()

func check(condition: bool, label: String):
	checks += 1
	if !condition:
		failures += 1
		push_error(label)

func tokens(value: String) -> Array[String]:
	var result: Array[String] = []
	if value.begins_with("<C-"):
		result.append(value)
	else:
		for character in value:
			result.append(character)
	return result

func binding(keys: String, context: int, kind: int, handler: String):
	scenarios += 1
	var parsed := map.parse_keys(tokens(keys), context)
	check(parsed.get("type") == kind, "%s in mode %d: command kind" % [keys, context])
	var payload := "motion" if kind == KeyMap.Motion else ("action" if kind == KeyMap.Action else "operator")
	check(parsed.get(payload, {}).get("type", "") == handler, "%s in mode %d: handler %s" % [keys, context, handler])

func absent(keys: String, context: int):
	scenarios += 1
	check(!KeyMap.is_cmd_valid(map.parse_keys(tokens(keys), context)), "%s must remain documented as unavailable in mode %d" % [keys, context])

func _run():
	var dummy := Control.new()
	root.add_child(dummy)
	map = KeyMap.new(dummy)
	for row in [
		["h", "move_by_chars"], ["l", "move_by_chars"],
		["j", "move_by_lines"], ["k", "move_by_lines"],
		["w", "move_by_word"], ["b", "move_by_word"], ["e", "move_by_word"], ["ge", "move_by_word"],
		["W", "move_by_word"], ["B", "move_by_word"], ["E", "move_by_word"], ["gE", "move_by_word"],
		["fq", "find_in_line"], ["Fq", "find_in_line"], ["tq", "find_in_line"], ["Tq", "find_in_line"],
		[";", "find_in_line_again"], [",", "find_in_line_again"],
		["n", "find_again"], ["N", "find_again"],
		["0", "move_to_bol"], ["^", "move_to_first_non_whitespace_char"], ["$", "move_to_eol"],
		["gg", "move_to_bof"], ["G", "move_to_eof"], ["gm", "move_to_center_of_line"],
		["{", "move_by_paragraph"], ["}", "move_by_paragraph"],
		["[[", "move_by_section"], ["]]", "move_by_section"],
		["<C-u>", "move_by_screen"], ["<C-d>", "move_by_screen"], ["%", "jump_to_next_brace_pair"],
	]:
		binding(row[0], Mode.NORMAL, KeyMap.Motion, row[1])
	for row in [
		["i", "insert"], ["a", "insert"], ["I", "insert"], ["A", "insert"], ["o", "insert"], ["O", "insert"],
		["v", "visual"], ["V", "visual"], ["u", "undo"], ["<C-r>", "redo"],
		["rq", "replace"], ["J", "join"], ["zz", "center_caret"],
		[":", "command"], ["/", "command"], ["ma", "mark"], ["mZ", "mark"],
		["`a", "jump_to_mark"], ["`Z", "jump_to_mark"], ["`0", "jump_to_mark"],
	]:
		binding(row[0], Mode.NORMAL, KeyMap.Action, row[1])
	for row in [["D", "delete"], ["x", "delete"], ["C", "change"], ["s", "change"], ["Y", "yank"], ["p", "paste"], ["gcc", "comment"], ["~", "toggle_uppercase"]]:
		binding(row[0], Mode.NORMAL, KeyMap.OperatorMotion, row[1])

	# Check composition separately: ciw and its peers really are operator + object.
	for operator in ["d", "c", "y", ">", "<", "gc"]:
		var handler: String = {"d":"delete", "c":"change", "y":"yank", ">":"indent", "<":"indent", "gc":"comment"}[operator]
		for motion in ["w", "$", "iw", "aW", "ip", "a\"", "i("]:
			scenarios += 1
			var parsed := map.parse_keys(tokens(operator + motion), Mode.NORMAL)
			check(parsed.get("type") == KeyMap.Operator and parsed.get("operator", {}).get("type") == handler,
				"Composed operator: " + operator + motion)
			check(parsed.get("modifier", {}).get("type") == KeyMap.Motion, "Composed motion/object: " + operator + motion)
	for sequence in ["dd", "cc", "yy", ">>", "<<"]:
		scenarios += 1
		var parsed := map.parse_keys(tokens(sequence), Mode.NORMAL)
		check(parsed.get("type") == KeyMap.Operator and parsed.get("modifier", {}).get("type") == KeyMap.Operator,
			"Doubled linewise operator: " + sequence)

	for prefix in ["i", "a"]:
		for suffix in ["w", "W", "p", "\"", "'", "`", "(", ")", "b", "[", "]", "{", "}", "B"]:
			scenarios += 1
			var parsed := map.parse_keys(tokens(prefix + suffix), Mode.VISUAL)
			check(parsed.get("type") == KeyMap.Motion, "Visual text object: " + prefix + suffix)
	for row in [["d", "delete"], ["c", "change"], ["y", "yank"], ["p", "paste"], [">", "indent"], ["<", "indent"], ["gc", "comment"], ["o", "visual_jump_to_other_end"]]:
		for context in [Mode.VISUAL, Mode.VISUAL_LINE]:
			binding(row[0], context, KeyMap.Operator, row[1])
	for row in [["x", "delete"], ["s", "change"], ["~", "toggle_uppercase"], ["u", "set_uppercase"], ["U", "set_uppercase"], ["V", "visual"]]:
		binding(row[0], Mode.VISUAL, KeyMap.Operator, row[1])
	binding("v", Mode.VISUAL_LINE, KeyMap.Operator, "visual")

	# Gaps are intentionally asserted, not counted as implemented features.
	for sequence in ["P", "X", "R", "S", "?", "*", "#", ".", "q", "@", "Q", "<C-v>",
		"H", "M", "L", "g_", "gj", "gk", "gJ", "zt", "zb", "<C-f>", "<C-b>", "<C-e>", "<C-y>",
		"<C-o>", "<C-i>", "<C-a>", "<C-x>", "gd", "gD", "gv", "gu", "gU", "ZZ", "ZQ",
		"'a", "\"a", "2w", "3dd", "d2w", "ci<", "cit", "cis", "ci,", "<C-[>"]:
		absent(sequence, Mode.NORMAL)
	for sequence in ["x", "s", "~", "u", "U", "V"]:
		absent(sequence, Mode.VISUAL_LINE)
	for sequence in ["v", "J", "r", ":", "/", "ma", "`a", "<C-r>"]:
		absent(sequence, Mode.VISUAL)
	for sequence in ["<C-[>", "<C-c>", "<C-w>", "<C-u>", "<C-o>", "<C-r>"]:
		absent(sequence, Mode.INSERT)

	# Escape is handled by Cursor._input, not by this map. Ctrl-S/B are deliberately
	# left to Godot. Do not conclude that any unbound key is safely inert in the UI.
	check(KeyMap.BLACKLIST == ["<C-s>", "<C-b>"], "Reserved Godot shortcuts match documentation")
	var dispatcher := Dispatcher.new()
	var actual := dispatcher.handlers.keys()
	actual.sort()
	var expected := ["delmarks", "find", "goto", "marks", "movecolumn", "moveline", "reload", "remap", "w", "wa"]
	expected.sort()
	check(actual == expected, "Ex handler inventory matches documentation")
	check(dispatcher.aliases == {"delm": ":delmarks"}, "Ex alias inventory matches documentation")
	print("Shortcut inventory tests: %s (%d scenarios, %d assertions)" % ["PASS" if failures == 0 else "FAIL", scenarios, checks])
	quit(0 if failures == 0 else 1)
