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
const DEV_CONSOLE_FLAG := "dev_console"

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
var _queue: Array = []  # [due process frame, InputEvent or Callable], in order

## Picks: cards, relics and potions that are taken the moment they are clicked (rewards, choices, treasure, shop), so a
## stray tap can't be undone. There a tap is a right click instead, which is the game's own inspect (card/relic
## inspect screen, shop preview; otherwise the hover tooltip stays up), and the game's own confirm button slides in at
## its usual place on the right edge. The tick replays a real left click on the item, so the game takes it exactly as
## with a mouse. Screens that already have their own preview + confirm step (deck upgrade/remove/transform, bundles)
## keep tap = click. Matched by the C# script file of the item, and of its screen when the item type is shared.
const PICK_ITEMS := {
	"NGridCardHolder.cs": ["NCardRewardSelectionScreen.cs", "NChooseACardSelectionScreen.cs"],
	"NRelicBasicHolder.cs": ["NChooseARelicSelection.cs"],
	"NTreasureRoomRelicHolder.cs": [],
	"NMerchantCard.cs": [],
	"NMerchantRelic.cs": [],
	"NMerchantPotion.cs": [],
}
const INSPECT_SCREENS := ["NInspectCardScreen.cs", "NInspectRelicScreen.cs"]
const INSPECTION_CONTAINER := "/root/Game/InspectionContainer"
const CONFIRM_BUTTON_SCENE := "res://scenes/ui/confirm_button.tscn"
const TAKE_WAIT_FRAMES := 120  # longest wait for a closing inspect screen to hide before clicking the item anyway
var _pick_holder: Control = null
var _pick_pos := Vector2.ZERO
var _inspect_was_open := false
var _take_layer: CanvasLayer = null
var _take_button: Control = null


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # touch must keep working while the game is paused (pause menu)
	Input.emulate_mouse_from_touch = false
	var pck := _main_pack_dir().path_join("SlayTheSpire2.pck")
	if ProjectSettings.load_resource_pack(pck, false):
		print("[sts2port] Mounted ", pck)
	else:
		push_error("[sts2port] Could not mount %s. Run scripts/push-game.ps1 on the PC." % pck)
	_ensure_language()
	_sync_full_console(FileAccess.file_exists(_main_pack_dir().path_join(DEV_CONSOLE_FLAG)))


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
		var item = _queue.pop_front()[1]
		if item is Callable:
			item.call()
		else:
			Input.parse_input_event(item)
	if _pick_holder != null:
		_update_pick()


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
				# Decided once hover has settled, since that's what tells which item the finger is on.
				_enqueue(_tap.bind(_touch_start), maxi(_touch_down_frame + HOVER_FRAMES, _frame()))
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


## A tap, run once hover has settled: inspects on pick screens, clicks everywhere else.
func _tap(pos: Vector2) -> void:
	var hovered := get_viewport().gui_get_hovered_control()
	var holder := _pick_target(hovered)
	if holder == null:
		# Taps on the take button or inside an open inspect screen keep the pick; _update_pick notices when the
		# inspect screen closes. Any other tap drops it.
		var keep := _within(hovered, _take_button)
		for screen in _inspect_screens():
			keep = keep or _within(hovered, screen)
		if not keep:
			_clear_pick()
		_click(MOUSE_BUTTON_LEFT, pos)
		return
	_clear_pick()
	_pick_holder = holder
	_pick_pos = pos
	_inspect_was_open = false
	_click(MOUSE_BUTTON_RIGHT, pos)  # the game's own inspect for this item
	_show_take(true)
	print("[sts2port] Pick: inspecting ", holder.name)


## The pickable item under the finger, if any (see PICK_ITEMS).
func _pick_target(control: Control) -> Control:
	var holder: Control = null
	var node: Node = control
	while node != null:
		var file := _script_file(node)
		if holder == null and PICK_ITEMS.has(file):
			holder = node as Control
			if PICK_ITEMS[file].is_empty():
				return holder
		elif holder != null and file in PICK_ITEMS[_script_file(holder)]:
			return holder
		node = node.get_parent()
	return null


## The game's inspect screens. It creates them on first use, under this container, so look them up each time.
func _inspect_screens() -> Array:
	var found := []
	var container := get_node_or_null(INSPECTION_CONTAINER)
	if container != null:
		for child in container.get_children():
			if _script_file(child) in INSPECT_SCREENS:
				found.append(child)
	return found


func _inspect_open() -> Control:
	for screen in _inspect_screens():
		if screen.visible:
			return screen
	return null


func _update_pick() -> void:
	if not is_instance_valid(_pick_holder) or not _pick_holder.is_inside_tree() or not _pick_holder.is_visible_in_tree():
		_clear_pick()
		return
	var open := _inspect_open() != null
	if _inspect_was_open and not open:
		_clear_pick()  # inspect screen closed with Back or by tapping outside the item
	_inspect_was_open = open


func _clear_pick() -> void:
	_pick_holder = null
	_show_take(false)


func _show_take(show: bool) -> void:
	if _take_button == null:
		if not show:
			return
		_take_layer = CanvasLayer.new()
		_take_layer.layer = 128  # above the game's inspect screen
		add_child(_take_layer)
		_take_button = load(CONFIRM_BUTTON_SCENE).instantiate()
		_take_layer.add_child(_take_button)
		_take_button.connect("Released", _on_take)
	_take_button.call("Enable" if show else "Disable")


func _on_take(_button = null) -> void:
	var holder := _pick_holder
	var pos := _pick_pos
	_clear_pick()
	if not is_instance_valid(holder) or not holder.is_inside_tree():
		return
	print("[sts2port] Pick: taking ", holder.name)
	var screen := _inspect_open()
	if screen != null:
		screen.call("Close")  # fades out first; it only hides at the end of its tween
	_click_when_clear(pos, TAKE_WAIT_FRAMES)


## A real left click on the item once no inspect screen covers it: hover, press, hold, release.
func _click_when_clear(pos: Vector2, frames_left: int) -> void:
	if _inspect_open() != null and frames_left > 0:
		_enqueue(_click_when_clear.bind(pos, frames_left - 1), _frame() + 1)
		return
	var start := _frame()
	_enqueue(_motion(pos, 0), start)
	_enqueue(_button(MOUSE_BUTTON_LEFT, true, pos, MOUSE_BUTTON_MASK_LEFT), start + HOVER_FRAMES)
	_enqueue(_button(MOUSE_BUTTON_LEFT, false, pos, 0), start + HOVER_FRAMES + HOLD_FRAMES)


func _within(node: Node, ancestor: Node) -> bool:
	return node != null and ancestor != null and (node == ancestor or ancestor.is_ancestor_of(node))


func _script_file(node: Node) -> String:
	var script = node.get_script()
	return script.resource_path.get_file() if script != null else ""


## Events keep their order: an event is never due before the one queued ahead of it.
func _enqueue(event: Variant, due_frame: int) -> void:  # InputEvent, or Callable run on that frame
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


## The game only offers its debug console commands (room, gold, fight...) when settings.save has "full_console": true.
## For testing, an empty file named DEV_CONSOLE_FLAG next to the packs turns that on; without it the key is removed
## again, so cheats are never left on by accident. Text edit only, like _ensure_language.
func _sync_full_console(enable: bool) -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var text := FileAccess.get_file_as_string(SETTINGS_PATH)
	# The key followed by a comma, or (as the last key) preceded by one.
	var with_next := RegEx.create_from_string("\\s*\"full_console\"\\s*:\\s*(true|false)\\s*,")
	var as_last := RegEx.create_from_string(",\\s*\"full_console\"\\s*:\\s*(true|false)")
	var has := text.contains("\"full_console\"")
	if enable == has:
		return
	if enable:
		var brace := text.find("{")
		if brace < 0:
			return
		text = text.substr(0, brace + 1) + "\n  \"full_console\": true," + text.substr(brace + 1)
	elif with_next.search(text) != null:
		text = with_next.sub(text, "")
	else:
		text = as_last.sub(text, "")
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		print("[sts2port] Full dev console ", "on" if enable else "off", ": ", text.left(60).c_escape())


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
