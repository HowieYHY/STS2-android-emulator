extends SceneTree
## The game's corner build label gets the real game version/date and the port's version, in both of its layouts,
## once, and again after the game rewrites it; against a stand-in NDebugInfoLabelManager with no game files.

class LabelBoot extends "res://boot.gd":
	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

var boot: LabelBoot
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	boot = LabelBoot.new()
	root.add_child(boot)
	await process_frame

	# No version files in this project: the port falls back to "(overlay copy)" and the game's placeholders stay.
	var bare := _manager("NONE\n???")
	await process_frame
	_check(bare.text == "NONE\n???\nAndroid (overlay copy)", "without version files: placeholders kept, port fallback added (%s)" % bare.text.c_escape())

	boot._port_version = "Android 0.1.7"
	boot._game_version = "v0.111.0"
	boot._game_date = "2026.08.13"
	var menu := _manager("NONE\n???")
	await process_frame
	_check(menu.text == "v0.111.0\n2026.08.13\nAndroid 0.1.7", "main menu: real game version, date, then the port (%s)" % menu.text.c_escape())
	var run := _manager("[NONE] (???)")
	await process_frame
	_check(run.text == "[v0.111.0] (2026.08.13)  ·  Android 0.1.7", "in a run: one line (%s)" % run.text)

	boot._stamp_port_version(menu)
	_check(menu.text.count("Android 0.1.7") == 1, "stamping again adds nothing")
	run.text = "[NONE] (???)"  # the game rewrites its label
	for i in range(boot.PC_ONLY_CHECK_FRAMES + 2):
		await process_frame
	_check(run.text == "[v0.111.0] (2026.08.13)  ·  Android 0.1.7", "re-stamped after the game rewrites it (%s)" % run.text)
	print("Version label checks: ", "PASS" if failures == 0 else "%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)


## Like the game's scene: the manager owns a Label with the unique name %ReleaseInfo, which _Ready fills.
func _manager(text: String) -> Label:
	var manager := _scripted("NDebugInfoLabelManager.cs")
	var label := Label.new()
	label.name = "ReleaseInfo"
	label.text = text
	manager.add_child(label)
	label.owner = manager
	label.unique_name_in_owner = true
	root.add_child(manager)
	return label


var _scripts := {}
func _scripted(file: String) -> Node:
	if not _scripts.has(file):
		var script := GDScript.new()
		script.source_code = "extends Node\n"
		script.reload()
		script.take_over_path("res://mock/%d/%s" % [_scripts.size(), file])
		_scripts[file] = script
	return _scripts[file].new()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", message)
