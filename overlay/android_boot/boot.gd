extends Node
## The port's main autoload, ahead of the game's own (port_loader.gd runs just before it and swaps in the copy of this
## file that ships in the installed APK, so APK releases update it).
## 1. Mounts the user's SlayTheSpire2.pck, which sits next to overlay.pck on the phone, without letting
##    it replace the overlay's files (the overlay carries the Android-specific config and assemblies), then
##    textures_astc.pck (phone-format copies of the game's desktop textures) over it.
## 2. Makes sure the game has a language saved, because the game's own fallback crashes on Android
##    locales with extensions (see _ensure_language). A brand-new settings file also gets the Auto aspect ratio.
## 3. Turns Android's Back into Escape (see _notification).
## 4. Turns touch into mouse input the game understands (see "Touch"), replacing Godot's built-in emulation.
## 5. Feeds Android performance hints for the game thread (see _start_perf_hints).

## The game's settings file for the Null (non-Steam) platform: user://default/<local player id 1>/.
const SETTINGS_PATH := "user://default/1/settings.save"
const SETTINGS_SCHEMA_VERSION := 8
const DEV_CONSOLE_FLAG := "dev_console"
const TEXTURES_PCK := "textures_astc.pck"
## An empty file with this name next to the packs logs performance every PERF_LOG_SEC seconds (for testing).
const PERF_LOG_FLAG := "perf_log"
const PERF_LOG_SEC := 5.0
const PERF_SPIKE_SEC := 0.05  # frames slower than this are logged one by one
const NO_PERF_HINT_FLAG := "no_perf_hint"
const FRAME_TARGET_NS := 16_666_667  # 60 fps
var _perf_hint: Object = null
var _perf_hint_last := 0
var _perf_log := false
var _perf_next := 0.0
var _perf_frames := 0
var _perf_worst_ms := 0.0

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
const TAP_RETRIES := 2  # times a tap hovers again when what's hovered can't be trusted
const DRAG_RELEASE_FRAMES := 2  # between a drag's last motion and its release (see _on_touch_up)
const CARD_PLAY_SETTLE_FRAMES := 6  # after a drag's release, before a card play still running is cancelled
## Godot only re-checks what the cursor is over when the mouse moves. A click that opens something over the clicked
## item (the deck upgrade preview over its grid card) left the item hovered, with its hover tips on top of the new
## screen (issue #10); on PC the mouse always moves a little and they go. A tap's click is followed by the cursor
## sent to the same spot again; if nothing covers the item, hover doesn't change and its tooltip stays up.
const REHOVER_FRAMES := 2

enum Touch { NONE, PENDING, DRAGGING, LONG_PRESSED }
var _touch := Touch.NONE
var _touch_start := Vector2.ZERO
var _touch_down_msec := 0
var _touch_down_frame := 0
var _last_mouse := Vector2.ZERO  # where the newest queued motion puts the cursor
var _sent_mouse := NO_HOVER  # where the cursor really is: the last motion delivered
var _last_sent_frame := -1000  # when the last event was delivered
var _queue: Array = []  # [due process frame, InputEvent or Callable], in order

## Picks: cards, relics and potions that are taken the moment they are clicked (rewards, choices, shop), so a stray
## tap can't be undone. There a tap is a right click instead, which is the
## game's own inspect (card/relic inspect screen, shop preview; otherwise the hover tooltip stays up), and the game's
## own confirm button slides in at its usual place on the right edge. The tick replays a real left click on the item, so the game takes it exactly as
## with a mouse. Screens that already have their own preview + confirm step (deck upgrade/remove/transform, bundles)
## keep tap = click, and so do event options and the choose-a-card screen (owner's choice, issues #1 and #9: potions,
## Discovery, the Knowledge Demon's curses...; a long-press inspects instead).
## Matched by the C# script file of the item, and of its screen when the item type is shared.
const PICK_ITEMS := {
	"NGridCardHolder.cs": ["NCardRewardSelectionScreen.cs"],
	"NRelicBasicHolder.cs": ["NChooseARelicSelection.cs"],
	"NMerchantCard.cs": [],
	"NMerchantRelic.cs": [],
	"NMerchantPotion.cs": [],
}
## A tap on a card in the combat hand would start the game's click-to-play (the card sticks to the cursor until a
## target is clicked). On a phone cards are played by dragging, so a tap there only hovers the card while the finger
## is down. The hand's own selection modes (choose a card to discard, upgrade...) still take taps as clicks.
const HAND_CARD := "NHandCardHolder.cs"
const HAND := "NPlayerHand.cs"
const NO_HOVER := Vector2(-10000, -10000)  # cursor parked off screen, so nothing stays hovered
## The game's inspect screens, each with the node whose mouse filter its Close() sets to Ignore (Open sets it to Stop).
## A closing screen fades out for about 0.25 s, and its card/popup would still catch taps until it hides.
const INSPECT_SCREENS := {"NInspectCardScreen.cs": ".", "NInspectRelicScreen.cs": "Backstop"}
const CLICK_THROUGH_META := "sts2port_click_through"
const GAME := "/root/Game"
const INSPECTION_CONTAINER := "/root/Game/InspectionContainer"
const CONFIRM_BUTTON_SCENE := "res://scenes/ui/confirm_button.tscn"
const PROCEED_GAP := 12.0  # px between a lifted tick and the Proceed/Skip arrow below it
## NInspectCardScreen.Open fades its card in from transparent over 0.25 s (and springs it bigger from 0.1 s), but the
## hover tips beside it (keywords, and cards it refers to) appear at full strength at once, so the other card showed
## first and the inspected card popped out after it (issue #8). Tips made as it opens fade in once the card is up.
const INSPECT_CARD := "NInspectCardScreen.cs"
const HOVER_TIP_SET := "NHoverTipSet.cs"
const INSPECT_TIPS_DELAY := 0.2
const INSPECT_TIPS_FADE := 0.1
var _inspect_card_was_open := false
## Settings that do nothing on a phone (owner's request): shown greyed out and disabled, with a note on the label,
## the way the game itself greys Language during a run. Matched by script file. Fullscreen is hidden by the game's
## own fullscreen-only mode (Sts2Patcher).
const PC_ONLY_SETTINGS := {
	"NKeyboardOnlyModeTickbox.cs": "KeyboardOnlyModeHeader",  # its label sits in the Input panel, not in the row
	"NDisplayDropdown.cs": "DisplaySelection",  # one screen; the dropdown is laid over its row, not inside it
	"NResolutionDropdown.cs": "WindowedResolution",  # the game already disables these two (fullscreen only);
	"NWindowResizeTickbox.cs": "",  # listed so they look like the other PC-only rows
	"NBackgroundModeTickbox.cs": "",  # Limit FPS in Background: Android pauses the game in the background
	"NUploadDataTickbox.cs": "",  # the APK has no INTERNET permission
	"NOpenFeedbackScreenButton.cs": "",  # same
	"NVSyncPaginator.cs": "",  # the phone's driver only has FIFO: Off and Adaptive fall back to On (Godot warns)
	# Long Press Confirmations needs End Turn held down for 0.5 s; touch never holds the left button (a held finger
	# is a right click), so with it on a turn couldn't be ended. Kept off as well as disabled (PC_ONLY_FORCE_OFF).
	"NLongPressConfirmationTickbox.cs": "",
}
const PC_ONLY_FORCE_OFF := ["NLongPressConfirmationTickbox.cs"]
const PC_ONLY_NOTE := "  (not on Android)"
const PC_ONLY_GREY := Color(0.55, 0.55, 0.55)
const PC_ONLY_CHECK_FRAMES := 30  # how often to re-check: the game re-enables some controls (window changes)
var _pc_only: Array = []
## The language list shows 中文/繁體中文/日本語/한국어 in the current language's font. The Latin fonts (Kreon...) have no
## CJK glyphs, so Godot fell back to Android's system font and drew it with the Latin font's MSDF setting; MSDF
## can't draw that font's overlapping outlines and left white wedges over 文 and 繁 (reproduced on the PC with the
## phone's font). Those fonts get the system font as an explicit fallback with MSDF off instead. It's the same file
## Godot's own fallback loads, so it costs nothing extra; the game's own CJK fonts would add ~100 MB of glyph caches.
const CJK_FALLBACK_PATH := "/system/fonts/NotoSansCJK-Regular.ttc"
const LANGUAGE_ITEM := "NLanguageDropdownItem.cs"
var _cjk_fallback: FontFile = null
## The port's version, added to the game's own small build label in the top-right corner (main menu and in a run;
## NDebugInfoLabelManager's %ReleaseInfo), named like the GitHub releases ("Android 0.1.6"). Re-applied with the
## PC-only check, since the game rewrites that label (e.g. once its commit lookup finishes).
const DEBUG_INFO := "NDebugInfoLabelManager.cs"
const PORT_VERSION_FILE := "res://android_boot/version.txt"  # port.pck's stamp: "APK 0.1.6 (7), commit 539956e"
const GAME_RELEASE_INFO := "res://android_boot/release_info.json"  # the game's own, copied in by build_overlay.py
var _build_labels: Array = []
var _port_version := ""
var _game_version := ""
var _game_date := ""
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
	# ASTC copies of the game's desktop-only textures (scripts/build_textures.py). Mounted after the game's pack with
	# replace on, so its .import files (which add path.astc) win; without it the game still runs, just heavier.
	var textures := _main_pack_dir().path_join(TEXTURES_PCK)
	if FileAccess.file_exists(textures) and ProjectSettings.load_resource_pack(textures, true):
		print("[sts2port] Mounted ", textures, " (astc supported: ", OS.has_feature("astc"), ")")
	_ensure_language()
	_sync_full_console(FileAccess.file_exists(_main_pack_dir().path_join(DEV_CONSOLE_FLAG)))
	_perf_log = FileAccess.file_exists(_main_pack_dir().path_join(PERF_LOG_FLAG))


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_start_perf_hints()
	if _perf_log:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


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
			_enqueue(_end_card_play, _frame() + CARD_PLAY_SETTLE_FRAMES)
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
	_let_closing_screens_through()
	var frame := _frame()
	while not _queue.is_empty() and _queue[0][0] <= frame:
		var item = _queue.pop_front()[1]
		if item is Callable:
			item.call()
		else:
			_send_input(item)
	if _pick_holder != null:
		_update_pick()
	_delay_inspect_tips()
	if not _pc_only.is_empty() and frame % PC_ONLY_CHECK_FRAMES == 0:
		_pc_only = _pc_only.filter(func(n): return is_instance_valid(n))
		for node in _pc_only:
			_disable_pc_only(node)
	if not _build_labels.is_empty() and frame % PC_ONLY_CHECK_FRAMES == 0:
		_build_labels = _build_labels.filter(func(l): return is_instance_valid(l))
		for label in _build_labels:
			_stamp_port_version(label)
	if _perf_hint != null:
		var now := Time.get_ticks_usec()
		if _perf_hint_last > 0:
			_perf_hint.reportFrame((now - _perf_hint_last) * 1000)
		_perf_hint_last = now
	if _perf_log:
		_log_perf(_delta)


## node_added fires before the node's _ready, and the settings screen sets its labels in its own _ready (after its
## children's), so wait for ready and then one more frame.
func _on_node_added(node: Node) -> void:
	if PC_ONLY_SETTINGS.has(_script_file(node)):
		_pc_only.append(node)
		node.ready.connect(func() -> void: _disable_pc_only.call_deferred(node), CONNECT_ONE_SHOT)
	elif _script_file(node) == LANGUAGE_ITEM:
		node.ready.connect(func() -> void: _add_cjk_fallback_to(node), CONNECT_ONE_SHOT)
	elif _script_file(node) == DEBUG_INFO:
		node.ready.connect(func() -> void: _add_build_label(node), CONNECT_ONE_SHOT)


func _add_build_label(manager: Node) -> void:
	var label = manager.get_node_or_null("%ReleaseInfo")
	if label is Label:
		_build_labels.append(label)
		_stamp_port_version(label)


## Main menu: the game's two lines (version, date) plus ours. In a run: "[version] (date)" plus ours on one line.
## The game writes "NONE" and "???" there because it can't find its release_info.json on Android; the overlay
## carries a copy from the install its packs were built from (build_overlay.py), so those become the real values.
func _stamp_port_version(label: Label) -> void:
	if _port_version == "":
		var stamp := FileAccess.get_file_as_string(PORT_VERSION_FILE).strip_edges()
		var found := RegEx.create_from_string("APK (\\S+)").search(stamp)
		_port_version = "Android " + (found.get_string(1) if found != null else "(overlay copy)")
		var info = JSON.parse_string(FileAccess.get_file_as_string(GAME_RELEASE_INFO)) \
				if FileAccess.file_exists(GAME_RELEASE_INFO) else null
		if info is Dictionary:
			_game_version = str(info.get("version", ""))
			_game_date = str(info.get("date", "")).left(10).replace("-", ".")  # the game's yyyy.MM.dd
	if label.text.ends_with(_port_version):
		return
	var text := label.text
	if _game_version != "":
		text = text.replace("NONE", _game_version)
	if _game_date != "":
		text = text.replace("???", _game_date)
	label.text = text + ("\n" if "\n" in text else "  ·  ") + _port_version


func _add_cjk_fallback_to(item: Node) -> void:
	if _cjk_fallback == null:
		if not FileAccess.file_exists(CJK_FALLBACK_PATH):
			return
		_cjk_fallback = FontFile.new()
		_cjk_fallback.load_dynamic_font(CJK_FALLBACK_PATH)
		_cjk_fallback.multichannel_signed_distance_field = false
	for label in item.find_children("*", "RichTextLabel", true, false) + item.find_children("*", "Label", true, false):
		for font_name in ["normal_font", "bold_font", "font"]:
			if label.has_theme_font(font_name):
				_add_fallback(label.get_theme_font(font_name), _cjk_fallback)


## Adds a fallback where Godot looks for it: a FontVariation without fallbacks of its own uses its base font's.
func _add_fallback(font: Font, fallback: Font) -> void:
	while font is FontVariation and font.fallbacks.is_empty() and font.base_font != null:
		font = font.base_font
	if font == null or font == fallback or font.fallbacks.has(fallback):
		return
	font.fallbacks = font.fallbacks + [fallback]
	print("[sts2port] CJK fallback added to ", font.resource_path)


func _disable_pc_only(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if _script_file(node) in PC_ONLY_FORCE_OFF and node.get("IsTicked") == true:
		node.call("ForceToggleTick")  # the tickbox's own toggle, so the game saves the preference as off
	# Controls without their own Disable (the arrow selectors) take taps through their buttons.
	for control in [node] + _find_controls(node, []):
		if control.get("IsEnabled") == true and control.has_method("Disable"):
			control.call("Disable")
	if node is CanvasItem:
		node.modulate = PC_ONLY_GREY
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE  # selectors also page on their own input (keys, controller)
		node.focus_mode = Control.FOCUS_NONE
	var label := _pc_only_label(node)
	if label == null and not node.has_meta("sts2port_no_label"):
		node.set_meta("sts2port_no_label", true)
		push_warning("[sts2port] No row label found for PC-only setting %s" % node.get_path())
	if label != null:
		label.modulate = PC_ONLY_GREY
		if not label.text.ends_with(PC_ONLY_NOTE):  # the game re-localises labels (e.g. language change)
			label.text += PC_ONLY_NOTE


## The setting's row label: a "Label" child of the row the control sits in (see NSettingsScreen.LocHelper), or, for
## controls laid out apart from their row, the row or label found by name in the same panel.
func _pc_only_label(node: Node) -> RichTextLabel:
	var name_hint: String = PC_ONLY_SETTINGS[_script_file(node)]
	var parent := node.get_parent()
	for i in range(3):
		if parent == null:
			break
		var found: Node = parent.get_node_or_null("Label") if name_hint == "" else parent.find_child(name_hint, true, false)
		if found != null and not found is RichTextLabel:
			found = found.get_node_or_null("Label")
		if found is RichTextLabel:
			return found
		parent = parent.get_parent()
	return null


## Android performance hints (the APK's Sts2PortPerf plugin): tells Android the game thread wants FRAME_TARGET_NS per
## frame and how long each frame really took, so it raises that thread's CPU clock when frames run long. Without
## it the main thread sat at 650-1,300 MHz of 2,600 during combat animations. A "no_perf_hint" file turns it off.
func _start_perf_hints() -> void:
	if not Engine.has_singleton("Sts2PortPerf"):
		print("[sts2port] Performance hints: plugin not in this APK")
		return
	if FileAccess.file_exists(_main_pack_dir().path_join(NO_PERF_HINT_FLAG)):
		print("[sts2port] Performance hints: off (", NO_PERF_HINT_FLAG, " flag)")
		return
	var plugin := Engine.get_singleton("Sts2PortPerf")
	if plugin.startSession(FRAME_TARGET_NS):
		_perf_hint = plugin
		print("[sts2port] Performance hints: on")
	else:
		print("[sts2port] Performance hints: not supported on this device")


## One line per PERF_LOG_SEC: average fps, worst frame, CPU process time, memory and video memory.
func _log_perf(delta: float) -> void:
	_perf_frames += 1
	_perf_worst_ms = maxf(_perf_worst_ms, delta * 1000.0)
	if delta > PERF_SPIKE_SEC:
		var vp := get_viewport().get_viewport_rid()
		print("[sts2port] spike %.0fms (process %.0fms, render cpu %.1fms gpu %.1fms, draws %d)" % [delta * 1000.0,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(),
			RenderingServer.viewport_get_measured_render_time_gpu(vp),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	var now := Time.get_ticks_msec() / 1000.0
	if now < _perf_next:
		return
	if _perf_next > 0.0:
		print("[sts2port] perf fps=%.1f worst=%.0fms process=%.1fms mem=%dMB vram=%dMB tex=%dMB objects=%d draws=%d" % [
			_perf_frames / PERF_LOG_SEC, _perf_worst_ms,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			OS.get_static_memory_usage() / 1048576,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576,
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576,
			Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
		var volumes := _fmod_volumes()
		if volumes != "":
			print("[sts2port] fmod ", volumes)
	_perf_next = now + PERF_LOG_SEC
	_perf_frames = 0
	_perf_worst_ms = 0.0


## The game's FMOD volume controls (the Sound sliders end up here), so a test can check a slider reached the audio
## engine. The FMOD addon has no output metering, so this is the volume FMOD applies, not what the speaker plays.
func _fmod_volumes() -> String:
	if not Engine.has_singleton("FmodServer"):
		return ""
	var fmod: Object = Engine.get_singleton("FmodServer")
	var parts := []
	for getter in ["get_all_vca", "get_all_buses", "get_all_bus"]:
		if not fmod.has_method(getter):
			continue
		for item in fmod.call(getter):
			if item is Object and item.has_method("get_volume"):
				var path: String = item.call("get_path") if item.has_method("get_path") else str(item)
				parts.append("%s=%.3f" % [path, item.call("get_volume")])
	return " ".join(parts)


func _on_touch_down(pos: Vector2) -> void:
	_touch = Touch.PENDING
	_touch_start = pos
	_touch_down_msec = Time.get_ticks_msec()
	# The frame the cursor actually gets there: it waits behind a previous tap's queued events, and hover only
	# settles HOVER_FRAMES after that. Timing from the touch itself let a quick second tap be judged by the first
	# tap's hover (a shop item was then clicked, i.e. bought, instead of inspected).
	_touch_down_frame = _enqueue(_motion(pos, 0), _frame())


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
			# The release waits a frame or two behind the last motion: a card flicked into the play zone and let go in
			# the same frame would start the game's click-to-target mode instead of being played.
			var moved := _enqueue(_motion(pos, MOUSE_BUTTON_MASK_LEFT), _frame())
			var released := _enqueue(_button(MOUSE_BUTTON_LEFT, false, pos, 0), moved + DRAG_RELEASE_FRAMES)
			_enqueue(_end_card_play, released + CARD_PLAY_SETTLE_FRAMES)
	_touch = Touch.NONE


## A dragged hand card that is let go before it reaches the play zone (or, if it needs a target, over no enemy) leaves
## the game's card play running: on PC the card then sticks to the cursor until a click picks a target or a right
## click cancels (NMouseCardPlay, NTargetManager), and on a phone it stayed stuck (issue #7). Once the finger is up and
## the game has handled the release, a play still running is waiting for one of those clicks, so cancel it and the
## card goes back to the hand. A card that was played has finished by then (TryPlayCard runs synchronously).
func _end_card_play() -> void:
	if _touch != Touch.NONE:
		return  # a new touch is under way; it ends its own play
	var game := get_node_or_null("/root/Game")
	for hand in _find_all_by_script(game if game != null else get_tree().root, HAND, []):
		# InCardPlay first: it checks the play is still a live object. Once the play is freed, reading _currentCardPlay
		# throws ObjectDisposedException in the game's C# (logged on every card play on the phone, 16 Oct).
		if hand.get("InCardPlay") != true:
			continue
		var play = hand.get("_currentCardPlay")
		if is_instance_valid(play) and not play.is_queued_for_deletion():
			print("[sts2port] Hand: card let go outside a play, returned to the hand")
			hand.call("CancelAllCardPlay")


## Hover (if the cursor isn't there yet), press, hold, release. The click goes ahead of anything newer touches have
## queued, and those wait until it has landed: a quick next tap must be judged by what this click opened (e.g. the
## inspect screen). Otherwise a burst of taps left the tick on one shop item while another one was on display.
## With rehover, the cursor is sent to the same spot once more after the release (see REHOVER_FRAMES).
func _click(button: MouseButton, pos: Vector2, rehover := false) -> void:
	var mask := MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	var later := _queue
	_queue = []
	var newest_mouse := _last_mouse  # where the queued events taken out (if any) leave the cursor
	var press_frame := _frame()
	if _sent_mouse != pos:
		press_frame = _enqueue(_motion(pos, 0), _frame()) + HOVER_FRAMES
	_enqueue(_button(button, true, pos, mask), press_frame)
	var done := _enqueue(_button(button, false, pos, 0), press_frame + HOLD_FRAMES)
	if rehover:
		done = _enqueue(_motion(pos, 0), done + REHOVER_FRAMES)
	if not later.is_empty():
		_last_mouse = newest_mouse
	_append_delayed(later, done + 1)


## Run a callable ahead of everything queued, on frame `due`; the rest waits behind it.
func _run_first(item: Callable, due: int) -> void:
	var later := _queue
	_queue = []
	_append_delayed(later, _enqueue(item, due))


## Put back events taken out of the queue, no earlier than frame `from` and keeping their spacing.
func _append_delayed(later: Array, from: int) -> void:
	if later.is_empty():
		return
	var delay := maxi(0, from - later[0][0])
	if _touch_down_frame >= later[0][0]:
		_touch_down_frame += delay  # the current touch's hover is among the delayed events
	for item in later:
		item[0] += delay
		_queue.append(item)


## A tap, run once hover has settled: inspects on pick screens, clicks everywhere else.
func _tap(pos: Vector2, tries := 0) -> void:
	# Decide only once the game has seen everything sent so far: a click that just went out may still close an
	# inspect screen and uncover a shop item, and a plain click decided before that would buy the item.
	var settled := _last_sent_frame + HOVER_FRAMES
	if _frame() < settled:
		_run_first(_tap.bind(pos, tries), settled)
		return
	var hovered := get_viewport().gui_get_hovered_control()
	# Hover can be stale: none at all when the cursor moved in the same frame as a click's release, or a closing
	# inspect screen (it lets taps through now). Hover again and decide then; if still unsure, do nothing rather than
	# risk a plain click on a shop item.
	var closing := false
	for screen in _inspect_screens():
		closing = closing or (_within(hovered, screen) and _closing(screen))
	if closing or hovered == null or not _under(hovered, pos):
		if tries < TAP_RETRIES:
			var later := _queue
			_queue = []
			var hovered_at := _enqueue(_motion(pos, 0), _frame()) + HOVER_FRAMES
			_append_delayed(later, _enqueue(_tap.bind(pos, tries + 1), hovered_at))
			return
		if closing:
			_clear_pick()
			return
	if _is_hand_card_in_play(hovered):
		_clear_pick()
		if _last_mouse == pos:  # unless a newer touch already moved the cursor
			_enqueue(_motion(NO_HOVER, 0), _frame())
		return
	var holder := _pick_target(hovered)
	if holder == null:
		# Taps on the take button or inside an open inspect screen keep the pick; _update_pick notices when the
		# inspect screen closes. Any other tap drops it.
		var keep := _within(hovered, _take_button)
		for screen in _inspect_screens():
			keep = keep or _within(hovered, screen)
		if not keep:
			_clear_pick()
		_click(MOUSE_BUTTON_LEFT, pos, true)
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


## Whether pos (viewport coordinates) is inside the control, which may be scaled or rotated (hand cards).
func _under(control: Control, pos: Vector2) -> bool:
	var local := control.get_global_transform_with_canvas().affine_inverse() * pos
	return Rect2(Vector2.ZERO, control.size).has_point(local)


## True for a card in the combat hand while the hand is in normal play (see HAND_CARD). Unknown states count as
## selection, so a tap still clicks.
func _is_hand_card_in_play(control: Control) -> bool:
	var node: Node = control
	var on_card := false
	while node != null:
		var file := _script_file(node)
		if file == HAND_CARD:
			on_card = true
		elif file == HAND:
			return on_card and node.get("IsInCardSelection") == false
		node = node.get_parent()
	return false


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
		if screen.visible and not _closing(screen):
			return screen
	return null


func _closing(screen: Control) -> bool:
	var mark := screen.get_node_or_null(INSPECT_SCREENS[_script_file(screen)]) as Control
	return screen.visible and mark != null and mark.mouse_filter == Control.MOUSE_FILTER_IGNORE


## A closing inspect screen lets taps through at once, so nothing is decided (or clicked) against a screen that is
## about to vanish. A plain click on its popup was delivered just after it hid and bought the shop item underneath.
func _let_closing_screens_through() -> void:
	for screen in _inspect_screens():
		if _closing(screen) and not screen.has_meta(CLICK_THROUGH_META):
			_click_through(screen)


## On the frame the card inspect screen opens, hide its tips and fade them in after the card (see INSPECT_CARD). Open
## makes them itself, before this runs; tips made later (its arrows, the upgrade tickbox) show at once, as the card
## doesn't fade then.
func _delay_inspect_tips() -> void:
	var screen: Control = null
	for candidate in _inspect_screens():
		if _script_file(candidate) == INSPECT_CARD and candidate.visible and not _closing(candidate):
			screen = candidate
	var opened := screen != null and not _inspect_card_was_open
	_inspect_card_was_open = screen != null
	if not opened:
		return
	var game := get_node_or_null(GAME)
	var container = game.get("HoverTipsContainer") if game != null else null  # NGame's, where every tip set goes
	for tips in _find_all_by_script(container if container is Node else get_tree().root, HOVER_TIP_SET, []):
		if tips is CanvasItem and tips.get("_owner") == screen:
			tips.modulate.a = 0.0
			tips.create_tween().tween_property(tips, "modulate:a", 1.0, INSPECT_TIPS_FADE).set_delay(INSPECT_TIPS_DELAY)


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
	if show:
		_take_layer.offset = Vector2(0, -_proceed_overlap())


## Some screens also show the game's Proceed/Skip arrow in the same corner as the confirm button (seen in the treasure
## room before it lost its tick; kept as a guard for any other screen that does the same).
## Returns how far to lift the tick so it sits just above any shown one. Only the vertical extent is compared:
## the tick slides in horizontally, so its x isn't final yet. A disabled arrow stays visible but slides off the right
## edge, so it only counts while enabled and on screen; counting those lifted the tick for nothing (too high).
func _proceed_overlap() -> float:
	var tick := _take_button.get_global_rect()  # in the tick layer's own space, i.e. before any lift
	var screen := get_viewport().get_visible_rect()
	var lift := 0.0
	for button in _find_all_by_script(get_tree().root, "NProceedButton.cs", []):
		if button is Control and button.is_visible_in_tree() and button.get("IsEnabled") != false:
			var xform: Transform2D = button.get_global_transform_with_canvas()  # screen space, incl. its layer
			var arrow := Rect2(xform.origin, button.size * xform.get_scale())
			if arrow.position.x >= screen.end.x:
				continue
			if tick.position.y < arrow.end.y and arrow.position.y < tick.end.y:
				lift = maxf(lift, tick.end.y - arrow.position.y + PROCEED_GAP)
	return lift


func _find_all_by_script(node: Node, file: String, found: Array) -> Array:
	if _script_file(node) == file:
		found.append(node)
	for child in node.get_children():
		_find_all_by_script(child, file, found)
	return found


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
		_let_closing_screens_through()
	# A real left click on the item: hover, press, hold, release.
	var start := _enqueue(_motion(pos, 0), _frame())
	_enqueue(_button(MOUSE_BUTTON_LEFT, true, pos, MOUSE_BUTTON_MASK_LEFT), start + HOVER_FRAMES)
	_enqueue(_button(MOUSE_BUTTON_LEFT, false, pos, 0), start + HOVER_FRAMES + HOLD_FRAMES)


## Let clicks through a closing inspect screen and restore its mouse filters once it's hidden. Waiting for the fade
## instead made the tick feel slow.
func _click_through(screen: Control) -> void:
	screen.set_meta(CLICK_THROUGH_META, true)
	var saved := []
	for control in _find_controls(screen, []):
		if control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			saved.append([control, control.mouse_filter])
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visibility_changed.connect(_restore_mouse_filters.bind(screen, saved), CONNECT_ONE_SHOT)


func _restore_mouse_filters(screen: Control, saved: Array) -> void:
	if is_instance_valid(screen):
		screen.remove_meta(CLICK_THROUGH_META)
	for entry in saved:
		if is_instance_valid(entry[0]):
			entry[0].mouse_filter = entry[1]


func _find_controls(node: Node, found: Array) -> Array:
	if node is Control:
		found.append(node)
	for child in node.get_children():
		_find_controls(child, found)
	return found


func _within(node: Node, ancestor: Node) -> bool:
	return node != null and ancestor != null and (node == ancestor or ancestor.is_ancestor_of(node))


func _script_file(node: Node) -> String:
	var script = node.get_script()
	return script.resource_path.get_file() if script != null else ""


## Events keep their order: an event is never due before the one queued ahead of it. Returns the frame it's due.
func _enqueue(event: Variant, due_frame: int) -> int:  # InputEvent, or Callable run on that frame
	if not _queue.is_empty():
		due_frame = maxi(due_frame, _queue[-1][0])
	_queue.append([due_frame, event])
	return due_frame


func _frame() -> int:
	return Engine.get_process_frames()


## _input receives viewport coordinates, but Input.parse_input_event enters through the window and converts
## them again. Undo that conversion before sending mouse events, including letterbox offsets and scaling.
## Convert at delivery time so queued events use the current aspect ratio; keep Input's button state updated.
func _send_input(event: InputEvent) -> void:
	_last_sent_frame = _frame()
	if event is InputEventMouseMotion:
		_sent_mouse = event.position
	if event is InputEventMouse:
		var window_event: InputEventMouse = event.xformed_by(get_viewport().get_final_transform())
		# Mouse xformed_by transforms position/relative, but leaves global_position unchanged.
		window_event.global_position = window_event.position
		Input.parse_input_event(window_event)
	else:
		Input.parse_input_event(event)


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
