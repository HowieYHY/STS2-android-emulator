@tool
extends EditorPlugin
## Registers fmod/libs/android/fmod-{debug,release}.aar (from the fetched FMOD addon) and the port's own
## sts2port-perf.aar with Android Gradle exports. The aar holds fmod.jar plus a Godot plugin that calls org.fmod.FMOD.init(), which FMOD needs on
## Android. This replaces the FMOD addon's own editor plugin, which also loads banks and editor UI we don't need.

var _export_plugin: AndroidExport


func _enter_tree() -> void:
	_export_plugin = AndroidExport.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class AndroidExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "sts2port_android"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"fmod/libs/android/fmod-%s.aar" % ("debug" if debug else "release"),
			# ADPF performance hints for the game thread (tools/android-perf-plugin, built by build-perf-plugin.ps1).
			"sts2port_android/libs/sts2port-perf.aar",
		])
