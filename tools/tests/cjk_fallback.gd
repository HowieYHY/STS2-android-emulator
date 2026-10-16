extends SceneTree
## The language list's fonts get the CJK fallback where Godot looks for it (a FontVariation without fallbacks of its
## own uses its base font's), once, against a stand-in NLanguageDropdownItem with no game files.

class FontBoot extends "res://boot.gd":
	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

var boot: FontBoot
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	boot = FontBoot.new()
	root.add_child(boot)
	await process_frame
	var cjk := FontFile.new()
	boot._cjk_fallback = cjk  # stands in for the phone's system font

	# Like the game's shared fonts: a FontVariation over a FontFile, neither with fallbacks.
	var base := FontFile.new()
	var shared := FontVariation.new()
	shared.base_font = base
	# A variation with fallbacks of its own: Godot ignores its base font's there.
	var own_base := FontFile.new()
	var own := FontVariation.new()
	own.base_font = own_base
	var other := FontFile.new()
	own.fallbacks = [other]

	var item := _scripted("NLanguageDropdownItem.cs")
	var label := RichTextLabel.new()
	label.add_theme_font_override("normal_font", shared)
	label.add_theme_font_override("bold_font", own)
	item.add_child(label)
	root.add_child(item)
	await process_frame
	_check(base.fallbacks == [cjk], "a shared font's base font gets the fallback")
	_check(shared.fallbacks.is_empty(), "the variation itself keeps no fallbacks (so it still uses its base's)")
	_check(own.fallbacks == [other, cjk], "a variation with its own fallbacks gets it added to those")
	_check(own_base.fallbacks.is_empty(), "that variation's base font is left alone")

	var second := _scripted("NLanguageDropdownItem.cs")
	var label2 := RichTextLabel.new()
	label2.add_theme_font_override("normal_font", shared)
	second.add_child(label2)
	root.add_child(second)
	await process_frame
	_check(base.fallbacks == [cjk], "a second item doesn't add it twice")

	var unrelated_base := FontFile.new()
	var unrelated := _scripted("NSomethingElse.cs")
	var label3 := RichTextLabel.new()
	label3.add_theme_font_override("normal_font", unrelated_base)
	unrelated.add_child(label3)
	root.add_child(unrelated)
	await process_frame
	_check(unrelated_base.fallbacks.is_empty(), "other screens' fonts are untouched")
	print("CJK fallback checks: ", "PASS" if failures == 0 else "%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)


var _scripts := {}
func _scripted(file: String) -> Control:
	if not _scripts.has(file):
		var script := GDScript.new()
		script.source_code = "extends Control\n"
		script.reload()
		script.take_over_path("res://mock/%d/%s" % [_scripts.size(), file])
		_scripts[file] = script
	return _scripts[file].new()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", message)
