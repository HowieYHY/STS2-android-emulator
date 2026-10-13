extends SceneTree
## PC-only settings are disabled and greyed with a note, against stand-ins named like the game's scripts
## (boot.gd matches by script file), with no game or save files.

class SettingsBoot extends "res://boot.gd":
	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

const CONTROL_SOURCE := """extends Control
var IsEnabled := true
func Disable() -> void:
	IsEnabled = false
func Enable() -> void:
	IsEnabled = true
"""

var boot: SettingsBoot
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	boot = SettingsBoot.new()
	root.add_child(boot)
	await process_frame
	# A General-tab row: the row's own "Label", and the control inside the row.
	var row := Control.new()
	row.name = "LimitFpsInBackground"
	var label := RichTextLabel.new()
	label.name = "Label"
	label.text = "Limit FPS in Background"
	row.add_child(label)
	var tickbox := _scripted("NBackgroundModeTickbox.cs")
	row.add_child(tickbox)
	# A setting the port leaves alone.
	var fast_row := Control.new()
	var fast_label := RichTextLabel.new()
	fast_label.name = "Label"
	fast_label.text = "Fast Mode"
	fast_row.add_child(fast_label)
	var fast := _scripted("NFastModeTickbox.cs")
	fast_row.add_child(fast)
	# The Input panel: the label is a named node in the panel, not in the tickbox's row.
	var panel := Control.new()
	var header := RichTextLabel.new()
	header.name = "KeyboardOnlyModeHeader"
	header.text = "Keyboard-Only Mode"
	panel.add_child(header)
	header.owner = panel
	header.unique_name_in_owner = true
	var kb_row := Control.new()
	panel.add_child(kb_row)
	kb_row.owner = panel
	var kb := _scripted("NKeyboardOnlyModeTickbox.cs")
	kb_row.add_child(kb)
	kb.owner = panel
	# The Graphics panel: the Display dropdown is the panel's child, laid over its "DisplaySelection" row.
	var graphics := Control.new()
	var display_row := Control.new()
	display_row.name = "DisplaySelection"
	var display_label := RichTextLabel.new()
	display_label.name = "Label"
	display_label.text = "Display Selection"
	display_row.add_child(display_label)
	var content := Control.new()
	content.add_child(display_row)
	graphics.add_child(content)
	var display := _scripted("NDisplayDropdown.cs")
	graphics.add_child(display)
	for node in [row, fast_row, panel, graphics]:
		root.add_child(node)
	await _frames(3)
	_check(tickbox.IsEnabled == false, "Limit FPS in Background is disabled")
	_check(label.text == "Limit FPS in Background" + boot.PC_ONLY_NOTE, "its label carries the note once")
	_check(label.modulate == boot.PC_ONLY_GREY, "its label is greyed")
	_check(kb.IsEnabled == false, "Keyboard-Only Mode is disabled")
	_check(header.text == "Keyboard-Only Mode" + boot.PC_ONLY_NOTE, "the Input panel's header carries the note")
	_check(display.IsEnabled == false, "Display Selection is disabled")
	_check(display_label.text == "Display Selection" + boot.PC_ONLY_NOTE, "the Display row, found by name, carries the note")
	_check(fast.IsEnabled and fast_label.text == "Fast Mode", "other settings are left alone")
	# The game re-enables some controls and re-localises labels; the port puts them back, without doubling the note.
	tickbox.Enable()
	label.text = "Limit FPS in Background"
	await _frames(boot.PC_ONLY_CHECK_FRAMES + 2)
	_check(tickbox.IsEnabled == false, "a re-enabled setting is disabled again")
	_check(label.text == "Limit FPS in Background" + boot.PC_ONLY_NOTE, "a re-localised label gets the note again")
	await _frames(boot.PC_ONLY_CHECK_FRAMES + 2)
	_check(label.text.count(boot.PC_ONLY_NOTE) == 1, "the note is never added twice")
	print("Android settings checks: ", "PASS" if failures == 0 else "%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)


var _scripts := {}
func _scripted(file: String) -> Control:
	if not _scripts.has(file):
		var script := GDScript.new()
		script.source_code = CONTROL_SOURCE
		script.reload()
		script.take_over_path("res://mock/%d/%s" % [_scripts.size(), file])
		_scripts[file] = script
	return _scripts[file].new()


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
