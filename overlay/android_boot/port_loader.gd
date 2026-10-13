extends Node
## First autoload of the overlay pack, ahead of boot.gd. Mounts the port's own code that ships inside the installed
## APK (port.pck: boot.gd and a version stamp, repo code only) over the overlay's copy, so the next autoload,
## res://android_boot/boot.gd, comes from the APK. A new APK release then updates the port's code without rebuilding
## overlay.pck on the PC; overlay.pck only has to change for game updates and sts2.dll patches.
## The APK's Android plugin copies port.pck out of its assets next to the packs, because Godot can't read the APK's
## assets while overlay.pck is the main pack. Without the plugin method or port.pck, the overlay's own boot.gd runs.

const PLUGIN := "Sts2PortPerf"
const VERSION_FILE := "res://android_boot/version.txt"


func _init() -> void:
	if not Engine.has_singleton(PLUGIN):
		print("[sts2port] Port code: overlay's copy (no Android plugin in this APK)")
		return
	var path = Engine.get_singleton(PLUGIN).call("installPortPack")
	if typeof(path) != TYPE_STRING or path == "":
		print("[sts2port] Port code: overlay's copy (this APK carries no port.pck)")
		return
	if not ProjectSettings.load_resource_pack(path, true):
		push_error("[sts2port] Could not mount %s; using the overlay's copy of the port code" % path)
		return
	var version := FileAccess.get_file_as_string(VERSION_FILE).strip_edges()
	print("[sts2port] Port code: from the APK, ", version if version != "" else "unknown version")
