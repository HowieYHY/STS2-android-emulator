extends Node
## First autoload of the port's overlay pack (inserted ahead of the game's own autoloads).
## 1. Mounts the user's SlayTheSpire2.pck, which sits next to overlay.pck on the phone, without letting
##    it replace the overlay's files (the overlay carries the Android-specific config and assemblies).
## 2. Makes sure the game has a language saved, because the game's own fallback crashes on Android
##    locales with extensions (see _ensure_language).

## The game's settings file for the Null (non-Steam) platform: user://default/<local player id 1>/.
const SETTINGS_PATH := "user://default/1/settings.save"
const SETTINGS_SCHEMA_VERSION := 8

## The game's supported languages (LocManager._supportedLanguages), keyed by ISO 639-1 code.
const LANGUAGES := {
	"en": "eng", "de": "deu", "fr": "fra", "id": "ind", "it": "ita", "ja": "jpn", "ko": "kor",
	"pl": "pol", "ru": "rus", "th": "tha", "tr": "tur",
}


func _init() -> void:
	var pck := _main_pack_dir().path_join("SlayTheSpire2.pck")
	if ProjectSettings.load_resource_pack(pck, false):
		print("[sts2port] Mounted ", pck)
	else:
		push_error("[sts2port] Could not mount %s. Run scripts/push-game.ps1 on the PC." % pck)
	_ensure_language()


func _main_pack_dir() -> String:
	var args := OS.get_cmdline_args()
	var i := args.find("--main-pack")
	if i >= 0 and i + 1 < args.size():
		return args[i + 1].get_base_dir()
	return "/storage/emulated/0/Android/data/com.howieyhy.sts2port/files"


## When settings.save has no language, the game builds a CultureInfo from OS.get_locale(). On Android that
## is Java's Locale.toString(), which can carry extensions like "en_SG_#u-fw-sun-ms-metric", and
## CultureInfo throws on it before the game can show anything. Saving a language first skips that path.
## The file is edited as text, never re-serialised: Godot's JSON turns every number into a float
## ("schema_version": 8.0), which the game then rejects as a corrupt save.
func _ensure_language() -> void:
	var code := _language_code()
	var text: String
	if FileAccess.file_exists(SETTINGS_PATH):
		var current := FileAccess.get_file_as_string(SETTINGS_PATH)
		var re := RegEx.create_from_string("\"language\"\\s*:\\s*(null|\"\")")
		if re.search(current) == null:
			return  # already has a language (or a format we don't recognise): leave it alone
		text = re.sub(current, "\"language\": \"%s\"" % code)
	else:
		text = "{\n  \"schema_version\": %d,\n  \"language\": \"%s\"\n}\n" % [SETTINGS_SCHEMA_VERSION, code]
		DirAccess.make_dir_recursive_absolute(SETTINGS_PATH.get_base_dir())
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[sts2port] Could not write %s" % SETTINGS_PATH)
		return
	f.store_string(text)
	print("[sts2port] Set game language to ", code, " (system locale ", OS.get_locale(), ")")


func _language_code() -> String:
	var lang := OS.get_locale_language()
	var locale := OS.get_locale().to_lower()
	match lang:
		"zh":
			return "zht" if ("hant" in locale or "_tw" in locale or "_hk" in locale or "_mo" in locale) else "zhs"
		"pt":
			return "ptb"
		"es":
			return "spa" if "_es" in locale else "esp"
	return LANGUAGES.get(lang, "eng")
