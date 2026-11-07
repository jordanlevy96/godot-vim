extends SceneTree
## Table-driven integration checks use real KeyMap input, with fresh search/parser state per case.
const Cursor = preload("res://addons/godot_vim/cursor.gd")
const Mode = Cursor.Mode
var cursor: Cursor
var edit: CodeEdit
var failures := 0
var assertions := 0
var scenarios := 0

func _initialize():
	call_deferred("run")

func check(actual: Variant, expected: Variant, label: String):
	assertions += 1
	if actual != expected:
		failures += 1
		push_error("%s: expected %s, actual %s" % [label, str(expected), str(actual)])

func key(value: String):
	var event := InputEventKey.new()
	event.pressed = true
	event.unicode = value.unicode_at(0)
	event.keycode = value.to_upper().unicode_at(0)
	cursor.draw_cursor()
	cursor.key_map.register_event(event, cursor.mode)
	await process_frame
	cursor.draw_cursor()

func fixture(text: String, pos: Vector2i):
	scenarios += 1
	cursor.set_mode(Mode.INSERT)
	edit.text = text
	cursor.globals.clear()
	cursor.key_map.clear()
	cursor.set_mode(Mode.NORMAL)
	cursor.set_caret_pos(pos.y, pos.x)
	await process_frame
	cursor.draw_cursor()

func motion(text: String, start: Vector2i, keys: String, expected: Vector2i):
	await fixture(text, start)
	for ch in keys:
		await key(ch)
	check(cursor.get_caret_pos(), expected, "motion %s on %s from %s" % [keys, text.c_escape(), start])

func selection(text: String, start: Vector2i, keys: String, expected: String):
	await fixture(text, start)
	for ch in keys:
		await key(ch)
	check(edit.get_selected_text(), expected, "selection %s on %s from %s" % [keys, text.c_escape(), start])

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

	# Every starting character tests clamping and code-point, rather than byte, indexing.
	for text in ["", "a", "ab", "abcde", "é猫🙂x", "  cat", "\tcat", "     "]:
		for col in range(maxi(1, text.length())):
			await motion(text, Vector2i(col, 0), "h", Vector2i(maxi(0, col - 1), 0))
			await motion(text, Vector2i(col, 0), "l", Vector2i(mini(maxi(0, text.length() - 1), col + 1), 0))
		await motion(text, Vector2i(maxi(0, text.length() - 1), 0), "0", Vector2i.ZERO)
		await motion(text, Vector2i.ZERO, "$", Vector2i(maxi(0, text.length() - 1), 0))
		var first: int = text.length() - text.strip_edges(true, false).length()
		await motion(text, Vector2i.ZERO, "^", Vector2i(mini(first, maxi(0, text.length() - 1)), 0))

	# Word starts/ends distinguish punctuation from WORDs and cross line boundaries.
	for case in [
		[0,"w",4], [1,"w",4], [2,"w",4], [3,"w",4], [4,"w",7],
		[0,"e",2], [1,"e",2], [2,"e",6], [3,"e",6], [4,"e",6],
		[4,"b",0], [5,"b",4], [6,"b",4], [7,"b",4], [8,"b",7],
		[4,"ge",2], [6,"ge",2], [7,"ge",6], [8,"ge",7],
		[0,"W",4], [4,"W",13], [7,"W",13], [8,"W",13],
		[0,"E",2], [2,"E",10], [4,"E",10], [7,"E",10],
		[4,"B",0], [7,"B",4], [10,"B",4], [12,"B",4],
		[4,"gE",2], [7,"gE",2], [11,"gE",10], [12,"gE",10],
		[0,"ww",7], [0,"www",8], [0,"wwww",13], [12,"bb",7],
	]:
		await motion("one two,red  end", Vector2i(case[0], 0), case[1], Vector2i(case[2], 0))
	for case in [
		["one\ntwo",Vector2i(0,0),"w",Vector2i(0,1)],
		["one\n\ntwo",Vector2i(0,0),"w",Vector2i(0,1)],
		["one\n\ntwo",Vector2i(0,0),"W",Vector2i(0,1)],
		["one\n\ntwo",Vector2i(0,1),"w",Vector2i(0,2)],
		["one\n\ntwo",Vector2i(0,2),"b",Vector2i(0,1)],
		["one\n\ntwo",Vector2i(0,2),"B",Vector2i(0,1)],
		["one\n\ntwo",Vector2i(0,2),"ge",Vector2i(0,1)],
		["one\n\ntwo",Vector2i(0,2),"gE",Vector2i(0,1)],
		["one\n\ntwo",Vector2i(2,0),"e",Vector2i(2,2)],
		["one\n\ntwo",Vector2i(2,0),"E",Vector2i(2,2)],
		["one\n  \ntwo",Vector2i(0,0),"w",Vector2i(0,2)],
		["one\ntwo",Vector2i(0,1),"b",Vector2i(0,0)],
		["one\ntwo",Vector2i(2,0),"e",Vector2i(2,1)],
		["été 猫猫",Vector2i.ZERO,"w",Vector2i(4,0)],
		["été 猫猫",Vector2i.ZERO,"e",Vector2i(2,0)],
		["été 猫猫",Vector2i(5,0),"b",Vector2i(4,0)],
		["été 猫猫",Vector2i(4,0),"ge",Vector2i(2,0)],
	]:
		await motion(case[0],case[1],case[2],case[3])

	for case in [
		[0,"fx",2], [0,"tx",1], [8,"Fx",5], [8,"Tx",6],
		[0,"fx;",5], [0,"fx;;",8], [0,"fx;;;",8],
		[8,"Fx;",2], [8,"Fx;;",2], [0,"fx;,",2], [8,"Fx,",8],
		[0,"fz",0], [8,"Fz",8], [3,"tz",3], [3,"Tz",3],
		[0,";",0], [4,",",4], [0,"tx;",4], [8,"Tx;",3],
		[0,"Fx",0], [0,"Tx",0],
		[0,"tx;,",3], [8,"Tx;,",4], [0,"tx;,;",4], [8,"Tx;,;",3],
	]:
		await motion("abx cxd x",Vector2i(case[0],0),case[1],Vector2i(case[2],0))
	await motion("猫a猫b猫",Vector2i.ZERO,"f猫;",Vector2i(4,0))
	await motion("ab\nx",Vector2i.ZERO,"fx",Vector2i.ZERO)

	for case in [
		[Vector2i(2,0),"j",Vector2i(0,1)],
		[Vector2i(2,0),"jj",Vector2i(0,2)],
		[Vector2i(2,0),"k",Vector2i(2,0)],
		[Vector2i(3,3),"j",Vector2i(3,3)],
		[Vector2i(3,3),"k",Vector2i(0,2)],
		[Vector2i(3,3),"gg",Vector2i.ZERO],
		[Vector2i(2,0),"G",Vector2i(0,3)],
		[Vector2i(3,3),"0",Vector2i(0,3)],
	]:
		await motion("abcdef\nx\n\nlast",case[0],case[1],case[2])
	for case in [[0,"}",2],[1,"}",2],[2,"}",5],[4,"}",5],[5,"}",6],[6,"{",5],[4,"{",2],[2,"{",0],[0,"{",0]]:
		await motion("one\ntwo\n\nthree\nfour\n\nend",Vector2i(0,case[0]),case[1],Vector2i(0,case[2]))
	# Section navigation is plugin-specific: targets the end of func/class/region headers.
	for case in [[0,"]]",2],[2,"]]",4],[4,"]]",6],[6,"[[",4],[4,"[[",2],[2,"[[",0]]:
		var lines := ["start", "", "func a():", "  pass", "class Cat:", "  pass", "#region Main", "end"]
		var target: int = case[2]
		await motion("\n".join(lines),Vector2i(0,case[0]),case[1],Vector2i(0 if target == 0 else lines[target].length()-1,target))

	for case in [
		["(abc)",0,4],["(abc)",4,0],["[ab]",0,3],["[ab]",3,0],
		["{x}",0,2],["{x}",2,0],["((x))",0,4],["((x))",1,3],
		["a [b] c",0,4],["plain",2,2],["(oops",0,0],
	]:
		await motion(case[0],Vector2i(case[1],0),"%",Vector2i(case[2],0))
	await motion("(\na\n)",Vector2i.ZERO,"%",Vector2i(0,2))
	await motion("(\na\n)",Vector2i(0,2),"%",Vector2i.ZERO)

	for case in [
		["abcdef",2,"v","c"],["abcdef",2,"vl","cd"],["abcdef",2,"vh","bc"],
		["abcdef",2,"vllh","cd"],["abcdef",2,"vhhl","bc"],
		["abcdef",2,"v$","cdef"],["abcdef",2,"v0","abc"],
		["abcdef",2,"vloh","bcd"],["é猫🙂x",1,"vl","猫🙂"],
		["one two",1,"viw","one"],["one two",1,"vaw","one "],
		["one two",5,"viw","two"],["one two",5,"vaw"," two"],
		["a,b end",1,"viW","a,b"],["a,b end",1,"vaW","a,b "],
		["(abc)",2,"vi(","abc"],["(abc)",2,"va(","(abc)"],
		["(abc)",2,"vib","abc"],["[abc]",2,"vi]","abc"],
		["[abc]",2,"va[","[abc]"],["{abc}",2,"viB","abc"],
		["{abc}",2,"va}","{abc}"],
		['"abc"',2,'vi"',"abc"],['"abc"',2,'va"','"abc"'],
		["'abc'",2,"vi'","abc"],["`abc`",2,"va`","`abc`"],
	]:
		await selection(case[0],Vector2i(case[1],0),case[2],case[3])
	await selection("abc\ndef",Vector2i(1,0),"vj","bc\nde")
	await selection("abc\ndef",Vector2i(1,1),"vk","bc\nde")
	await selection("abc\ndef",Vector2i(1,0),"Vj","abc\ndef")
	await selection("abc\ndef",Vector2i(1,1),"Vk","abc\ndef")
	# VISUAL_LINE stores the preceding newline as its native CodeEdit range;
	# logical line bounds, rather than the raw leading newline, define the paragraph.
	await selection("a\n\nb\nc\n\nd",Vector2i(0,2),"vip","\nb\nc")
	check(cursor.selection_from.y, 2, "Inner paragraph logical start excludes preceding blank line")
	check(cursor.selection_to.y, 3, "Inner paragraph logical end excludes following blank line")
	await selection("a\n\nb\nc\n\nd",Vector2i(0,2),"vap","\nb\nc\n")
	check(cursor.selection_from.y, 2, "Around paragraph logical start excludes preceding blank line")
	check(cursor.selection_to.y, 4, "Around paragraph includes following blank line")

	await fixture("λx", Vector2i.ZERO)
	check(cursor.get_char_at(0, 0), "λ", "Character helper includes column zero and Unicode")
	check(cursor.get_char_at(0, 1), "x", "Character helper reads the final character")
	check(cursor.get_char_at(0, 2), "", "Character helper safely handles end-of-line")
	check(cursor.get_char_at(0, -1), "", "Character helper safely handles negative columns")
	check(cursor.get_char_at(-1, 0), "", "Character helper safely handles negative lines")
	check(cursor.get_char_at(1, 0), "", "Character helper safely handles past-last-line")

	print("Motion regression tests: %s (%d assertions, %d scenarios)" % ["PASS" if failures == 0 else "%d failures" % failures, assertions, scenarios])
	quit(0 if failures == 0 else 1)
