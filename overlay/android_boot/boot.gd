extends Node
## First autoload of the port's overlay pack (inserted ahead of the game's own autoloads).
## 1. Mounts the user's SlayTheSpire2.pck, which sits next to overlay.pck on the phone, without letting
##    it replace the overlay's files (the overlay carries the Android-specific config and assemblies).
## 2. Makes sure the game has a language saved, because the game's own fallback crashes on Android
##    locales with extensions (see _ensure_language). A brand-new settings file also gets the Auto aspect ratio.
## 3. Turns Android's Back into Escape (see _notification).
## 4. Turns touch into mouse input the game understands (see "Touch"), replacing Godot's built-in emulation.

## The game's settings file for the Null (non-Steam) platform: user://default/<local player id 1>/.
const SETTINGS_PATH := "user://default/1/settings.save"
const SETTINGS_SCHEMA_VERSION := 8

## The game's supported languages (LocManager._supportedLanguages), keyed by ISO 639-1 code.
const LANGUAGES := {
	"en": "eng", "de": "deu", "fr": "fra", "id": "ind", "it": "ita", "ja": "jpn", "ko": "kor",
	"pl": "pol", "ru": "rus", "th": "tha", "tr": "tur",
}


## Touch timings. A press waits HOVER_FRAMES after the cursor moves because the game's buttons only accept a
## click once hover has focused them; a tap is held HOLD_FRAMES because a one-frame press can be missed.
const LONG_PRESS_MSEC := 450
const DRAG_SLOP_FRACTION := 0.02  # of the window height (about 22 px on a 1080p-tall screen)
const HOVER_FRAMES := 2
const HOLD_FRAMES := 3

enum Touch { NONE, PENDING, DRAGGING, LONG_PRESSED }
var _touch := Touch.NONE
var _touch_start := Vector2.ZERO
var _touch_down_msec := 0
var _touch_down_frame := 0
var _last_mouse := Vector2.ZERO
var _queue: Array = []  # [due process frame, InputEvent], in order


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # touch must keep working while the game is paused (pause menu)
	Input.emulate_mouse_from_touch = false
	var pck := _main_pack_dir().path_join("SlayTheSpire2.pck")
	if ProjectSettings.load_resource_pack(pck, false):
		print("[sts2port] Mounted ", pck)
	else:
		push_error("[sts2port] Could not mount %s. Run scripts/push-game.ps1 on the PC." % pck)
	_ensure_language()


## Android's Back button/gesture arrives as NOTIFICATION_WM_GO_BACK_REQUEST (quit_on_go_back is turned off in the
## overlay's project settings). Turn it into Escape, which is the game's own back/pause key on PC.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		for pressed in [true, false]:
			var key := InputEventKey.new()
			key.keycode = KEY_ESCAPE
			key.physical_keycode = KEY_ESCAPE
			key.pressed = pressed
			Input.parse_input_event(key)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _touch == Touch.DRAGGING:
			_enqueue(_button(MOUSE_BUTTON_LEFT, false, _last_mouse, 0), _frame())
		_touch = Touch.NONE


# --- Touch -------------------------------------------------------------------------------------------------
# Godot's own touch-to-mouse emulation presses the left button the moment a finger lands. The game's card
# holders then ignore a right click until that press is released, and the release itself picks the card, so a
# long-press could never inspect. Here a press is only sent once the touch is known to be a tap, a drag or a
# long-press:
#   finger down          -> cursor moves there (hover)
#   moves past the slop  -> left press at the start point, then the cursor follows (drag)
#   lifted before that   -> left click (tap)
#   held LONG_PRESS_MSEC -> right click (inspect); the rest of that touch is ignored
# Only the first finger is used, like Godot's emulation.

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
		if event.index != 0:
			return
		if event.pressed:
			_on_touch_down(event.position)
		else:
			_on_touch_up(event.position, event.canceled)
	elif event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
		if event.index == 0:
			_on_touch_drag(event.position)


func _process(_delta: float) -> void:
	if _touch == Touch.PENDING and Time.get_ticks_msec() - _touch_down_msec >= LONG_PRESS_MSEC:
		_touch = Touch.LONG_PRESSED
		_click(MOUSE_BUTTON_RIGHT, _touch_start)
	var frame := _frame()
	while not _queue.is_empty() and _queue[0][0] <= frame:
		Input.parse_input_event(_queue.pop_front()[1])


func _on_touch_down(pos: Vector2) -> void:
	_touch = Touch.PENDING
	_touch_start = pos
	_touch_down_msec = Time.get_ticks_msec()
	_touch_down_frame = _frame()
	_enqueue(_motion(pos, 0), _frame())


func _on_touch_drag(pos: Vector2) -> void:
	match _touch:
		Touch.PENDING:
			if pos.distance_to(_touch_start) > DRAG_SLOP_FRACTION * get_viewport().get_visible_rect().size.y:
				_touch = Touch.DRAGGING
				_enqueue(_button(MOUSE_BUTTON_LEFT, true, _touch_start, MOUSE_BUTTON_MASK_LEFT), _touch_down_frame + HOVER_FRAMES)
				_enqueue(_motion(pos, MOUSE_BUTTON_MASK_LEFT), _frame())
		Touch.DRAGGING:
			_enqueue(_motion(pos, MOUSE_BUTTON_MASK_LEFT), _frame())


func _on_touch_up(pos: Vector2, canceled: bool) -> void:
	match _touch:
		Touch.PENDING:
			if not canceled:
				_click(MOUSE_BUTTON_LEFT, _touch_start)
		Touch.DRAGGING:
			_enqueue(_motion(pos, MOUSE_BUTTON_MASK_LEFT), _frame())
			_enqueue(_button(MOUSE_BUTTON_LEFT, false, pos, 0), _frame())
	_touch = Touch.NONE


## Press after the hover delay, hold, release.
func _click(button: MouseButton, pos: Vector2) -> void:
	var mask := MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	var press_frame := maxi(_touch_down_frame + HOVER_FRAMES, _frame())
	_enqueue(_button(button, true, pos, mask), press_frame)
	_enqueue(_button(button, false, pos, 0), press_frame + HOLD_FRAMES)


## Events keep their order: an event is never due before the one queued ahead of it.
func _enqueue(event: InputEvent, due_frame: int) -> void:
	if not _queue.is_empty():
		due_frame = maxi(due_frame, _queue[-1][0])
	_queue.append([due_frame, event])


func _frame() -> int:
	return Engine.get_process_frames()


func _motion(pos: Vector2, mask: int) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = pos - _last_mouse
	e.button_mask = mask
	_last_mouse = pos
	return e


func _button(button: MouseButton, pressed: bool, pos: Vector2, mask: int) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	e.button_mask = mask
	return e


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
		# First run: also default to the "Auto" aspect ratio, which fills a phone's wide screen without stretching
		# (the game's default is 16:9 with black bars). Only for a brand-new file, never overriding a choice.
		text = "{\n  \"schema_version\": %d,\n  \"language\": \"%s\",\n  \"aspect_ratio\": \"auto\"\n}\n" % [SETTINGS_SCHEMA_VERSION, code]
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
