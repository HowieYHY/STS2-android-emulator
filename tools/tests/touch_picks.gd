extends SceneTree
## Pick/tick behaviour of the touch layer against stand-ins for the game's nodes (matched by script file name, like
## boot.gd does), with no game or save files.

class PickBoot extends "res://boot.gd":
	var shown: Array = []  # every _show_take call
	var buffered: Array = []

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		Input.emulate_mouse_from_touch = false

	func _ready() -> void:
		pass

	## Android buffers parsed input until the next frame (headless handles it at once), so hover lags a frame behind.
	func _send_input(event: InputEvent) -> void:
		buffered.append(event)

	func _process(delta: float) -> void:
		var events := buffered
		buffered = []
		for event in events:
			super._send_input(event)
		super._process(delta)

	func _show_take(show: bool) -> void:
		shown.append(show)

const ITEM_SOURCE := """extends Control
var presses: Array = []  # [button index, pressed]
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		presses.append([event.button_index, event.pressed])
"""
## A shop item whose right click opens the inspect screen on release, like NMerchantSlot.OnPreview.
const PREVIEW_SOURCE := """extends Control
var presses: Array = []
var screen: Control
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		presses.append([event.button_index, event.pressed])
		if event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
			screen.visible = true
			screen.mouse_filter = MOUSE_FILTER_STOP
"""
## An inspect screen whose backdrop closes it on a left release, like NInspectRelicScreen's backstop.
const CLOSING_SOURCE := INSPECT_SOURCE + """
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		Close()
"""
const HAND_SOURCE := "extends Control\nvar IsInCardSelection := false\n"
## A hand whose card play works like NMouseCardPlay: a left press on a card starts it; a release in the play zone (top
## three quarters) plays the card; a release lower down leaves it running, waiting for a click (issue #7).
const PLAYING_HAND_SOURCE := """extends Control
var IsInCardSelection := false
var InCardPlay := false
## Like the game's C# field: reading it after the play is freed throws ObjectDisposedException; count those reads.
var _play: Node = null
var stale_reads := 0
var _had_play := false
var _currentCardPlay: Node:
	get:
		if _had_play and not is_instance_valid(_play):  # a freed object compares equal to null in GDScript
			stale_reads += 1
			return null
		return _play
var cancelled := 0
var played := 0
func _input(event: InputEvent) -> void:
	if InCardPlay and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if event.position.y < size.y * 0.75:
			played += 1
			_finish()
func start() -> void:
	InCardPlay = true
	_play = Node.new()
	_had_play = true
	add_child(_play)
func _finish() -> void:
	InCardPlay = false
	_play.queue_free()
func CancelAllCardPlay() -> void:
	if InCardPlay:
		cancelled += 1
		_finish()
"""
const PLAYING_CARD_SOURCE := """extends Control
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_parent().start()
"""
const PROCEED_SOURCE := "extends Control\nvar IsEnabled := true\n"
const INSPECT_SOURCE := """extends Control
var hide_in := -1
func Close() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	hide_in = 15  # frames, like the game's fade-out tween
func _process(_delta: float) -> void:
	if hide_in > 0:
		hide_in -= 1
		if hide_in == 0:
			visible = false
"""

var boot: PickBoot
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	Input.use_accumulated_input = false
	root.size = Vector2i(2424, 1080)  # the headless window starts at 64x64, where nothing could be hovered
	boot = PickBoot.new()
	root.add_child(boot)
	root.notify_mouse_entered()
	await _frames(2)
	await _test_quick_second_tap()
	await _test_tap_burst_follows_inspect()
	await _test_tap_after_closing_tap()
	await _test_hand_card_tap()
	await _test_hand_card_let_go()
	await _test_tick_lift()
	await _test_take_through_closing_inspect()
	await _test_choose_a_card_takes_on_tap()
	await _test_inspect_tips_wait_for_card()
	await _test_tap_unhovers_covered_card()
	print("Touch pick checks: ", "PASS" if failures == 0 else "%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)


## Tap a plain button, then a shop item before the first tap's events have gone out. The second tap must be judged
## by the shop item's own hover: inspect (right click), never a left click (which buys).
func _test_quick_second_tap() -> void:
	var plain := _box(Control.new(), Vector2(200, 200))
	var item := _box(_scripted("NMerchantCard.cs", ITEM_SOURCE), Vector2(900, 200))
	await _frames(2)
	_tap_now(_centre(plain))
	_tap_now(_centre(item))
	await _frames(20)
	_check(not item.presses.has([MOUSE_BUTTON_LEFT, true]), "a quick second tap on a shop item never left-clicks it")
	_check(item.presses.has([MOUSE_BUTTON_RIGHT, true]), "a quick second tap on a shop item inspects it")
	# The same with one frame between the taps.
	item.presses.clear()
	boot._clear_pick()
	_tap_now(_centre(plain))
	await process_frame
	_tap_now(_centre(item))
	await _frames(20)
	_check(not item.presses.has([MOUSE_BUTTON_LEFT, true]), "a second tap one frame later never left-clicks the item")
	_check(item.presses.has([MOUSE_BUTTON_RIGHT, true]), "a second tap one frame later inspects the item")
	boot._clear_pick()
	plain.queue_free()
	item.queue_free()
	await _frames(2)


## Tap one shop item and, straight away, another. The first tap's inspect screen opens over both, so the second tap
## lands on that screen: the item behind it must not become the pick (the tick would buy it while the first item is
## on display).
func _test_tap_burst_follows_inspect() -> void:
	var game := _inspection_container()
	var screen := _scripted("NInspectCardScreen.cs", INSPECT_SOURCE)
	screen.size = Vector2(2424, 1080)
	screen.visible = false
	game.get_node("InspectionContainer").add_child(screen)
	var first := _box(_scripted("NMerchantCard.cs", PREVIEW_SOURCE), Vector2(600, 300))
	var second := _box(_scripted("NMerchantCard.cs", PREVIEW_SOURCE), Vector2(1300, 300))
	first.screen = screen
	second.screen = screen
	root.move_child(game, -1)  # the inspect screen draws (and catches input) above the items
	await _frames(2)
	_tap_now(_centre(first))
	_tap_now(_centre(second))
	await _frames(30)
	_check(first.presses.has([MOUSE_BUTTON_RIGHT, false]), "the first tap inspects the first item")
	_check(screen.visible, "the first item's inspect screen is open")
	_check(second.presses.is_empty(), "the second tap lands on the inspect screen, not the item behind it")
	_check(boot._pick_holder != second, "the item behind the inspect screen never becomes the pick")
	boot._clear_pick()
	first.queue_free()
	second.queue_free()
	game.queue_free()
	await _frames(2)


## An open inspect screen's popup covers a shop item. Tap the screen's backdrop (the game closes it on that release
## and fades it out), then tap the popup over the item. Whatever the timing, even as the popup vanishes, that tap must
## inspect the item underneath, never click it (seen on the emulator: the click landed after the fade and bought it).
func _test_tap_after_closing_tap() -> void:
	var game := _inspection_container()
	var screen := _scripted("NInspectCardScreen.cs", CLOSING_SOURCE)
	screen.size = Vector2(2424, 1080)
	game.get_node("InspectionContainer").add_child(screen)
	var popup := Control.new()
	popup.position = Vector2(800, 200)
	popup.size = Vector2(500, 500)
	screen.add_child(popup)
	var item := _box(_scripted("NMerchantCard.cs", ITEM_SOURCE), Vector2(900, 300))
	root.move_child(game, -1)
	for gap in range(1, 19):
		boot._clear_pick()
		screen.visible = true
		screen.mouse_filter = Control.MOUSE_FILTER_STOP
		screen.hide_in = -1
		await _frames(20)
		_check(popup.mouse_filter == Control.MOUSE_FILTER_STOP, "the popup catches taps again after the screen hid")
		item.presses.clear()
		_tap_now(Vector2(200, 900))  # the backdrop
		await _frames(gap)
		_tap_now(_centre(item))
		await _frames(40)
		_check(not item.presses.has([MOUSE_BUTTON_LEFT, true]),
			"a tap %d frames after the closing tap never clicks the item under the popup" % gap)
		_check(item.presses.has([MOUSE_BUTTON_RIGHT, true]),
			"a tap %d frames after the closing tap inspects the item under the popup" % gap)
	boot._clear_pick()
	item.queue_free()
	game.queue_free()
	await _frames(2)


func _inspection_container() -> Node:
	var game := Node.new()
	game.name = "Game"
	root.add_child(game)
	var container := Node.new()
	container.name = "InspectionContainer"
	game.add_child(container)
	return game


## A tap on a card in the combat hand only hovers it, then nothing stays hovered. In a hand selection mode it clicks.
func _test_hand_card_tap() -> void:
	var hand := _scripted("NPlayerHand.cs", HAND_SOURCE)
	hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand.size = Vector2(2424, 1080)
	root.add_child(hand)
	var card := _scripted("NHandCardHolder.cs", ITEM_SOURCE)
	card.position = Vector2(1100, 800)
	card.size = Vector2(200, 260)
	hand.add_child(card)
	await _frames(2)
	_touch_now(_centre(card), true)
	await _frames(4)
	_check(root.gui_get_hovered_control() == card, "the hand card is hovered while the finger is down")
	_touch_now(_centre(card), false)
	await _frames(16)
	_check(card.presses.is_empty(), "a tap on a hand card in play sends no click")
	_check(root.gui_get_hovered_control() == null, "the hand card is no longer hovered after the tap")
	hand.IsInCardSelection = true
	_tap_now(_centre(card))
	await _frames(20)
	_check(card.presses.has([MOUSE_BUTTON_LEFT, true]), "a tap on a hand card in a selection mode clicks it")
	hand.queue_free()
	await _frames(2)


## Issue #7: a card dragged a little and let go in the hand goes back (the play is cancelled); one dragged into the
## play zone is played and not cancelled.
func _test_hand_card_let_go() -> void:
	var hand := _scripted("NPlayerHand.cs", PLAYING_HAND_SOURCE)
	hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand.size = Vector2(2424, 1080)
	root.add_child(hand)
	var card := _scripted("NHandCardHolder.cs", PLAYING_CARD_SOURCE)
	card.position = Vector2(1100, 820)
	card.size = Vector2(200, 260)
	hand.add_child(card)
	await _frames(2)
	var start := _centre(card)
	_drag_now([start, start + Vector2(0, -60)])
	await _frames(20)
	_check(hand.cancelled == 1 and hand.played == 0, "a card let go in the hand goes back to it")
	_check(not hand.InCardPlay, "no card play is left running after letting go in the hand")
	_drag_now([start, start + Vector2(0, -100), Vector2(1200, 300)])
	await _frames(20)
	_check(hand.played == 1 and hand.cancelled == 1, "a card dragged into the play zone is played, not cancelled")
	_check(hand.stale_reads == 0, "the port never reads a freed card play (ObjectDisposedException in the game)")
	hand.queue_free()
	await _frames(2)


## The tick lifts only above a Proceed/Skip arrow that is enabled and on screen.
func _test_tick_lift() -> void:
	var tick := Control.new()
	tick.position = Vector2(2200, 860)
	tick.size = Vector2(160, 120)
	root.add_child(tick)
	boot._take_button = tick
	var arrow := _scripted("NProceedButton.cs", PROCEED_SOURCE)
	arrow.size = Vector2(200, 120)
	arrow.position = Vector2(2190, 880)
	root.add_child(arrow)
	await process_frame
	_check(boot._proceed_overlap() > 0.0, "the tick lifts above a shown arrow")
	arrow.IsEnabled = false
	_check(is_zero_approx(boot._proceed_overlap()), "the tick ignores a disabled arrow")
	arrow.IsEnabled = true
	arrow.position.x = 2424 + 40  # the game's hidden position: still visible, slid off the right edge
	_check(is_zero_approx(boot._proceed_overlap()), "the tick ignores an arrow slid off screen")
	boot._take_button = null
	tick.queue_free()
	arrow.queue_free()
	await _frames(2)


## Pressing the tick clicks the item at once, through the inspect screen that is still fading out, and the inspect
## screen catches clicks again after it has hidden.
func _test_take_through_closing_inspect() -> void:
	var item := _box(_scripted("NMerchantRelic.cs", ITEM_SOURCE), Vector2(900, 400))
	var game := _inspection_container()
	var screen := _scripted("NInspectCardScreen.cs", INSPECT_SOURCE)
	screen.size = Vector2(2424, 1080)
	game.get_node("InspectionContainer").add_child(screen)
	var backstop := Control.new()
	backstop.size = Vector2(2424, 1080)
	screen.add_child(backstop)
	await _frames(2)
	boot._pick_holder = item
	boot._pick_pos = _centre(item)
	boot._on_take()
	await _frames(8)
	_check(screen.visible, "the inspect screen is still fading out")
	_check(item.presses.has([MOUSE_BUTTON_LEFT, true]) and item.presses.has([MOUSE_BUTTON_LEFT, false]),
		"the tick clicks the item without waiting for the fade")
	await _frames(12)
	_check(not screen.visible, "the inspect screen hides at the end of its fade")
	_check(backstop.mouse_filter == Control.MOUSE_FILTER_STOP, "the inspect backstop catches clicks again once hidden")
	item.queue_free()
	game.queue_free()
	await _frames(2)


## The choose-a-card screen (potions, Discovery, the Knowledge Demon's curses) takes a card on tap, with no tick
## (issue #9); card rewards keep tap = inspect.
func _test_choose_a_card_takes_on_tap() -> void:
	for case in [["NChooseACardSelectionScreen.cs", MOUSE_BUTTON_LEFT], ["NCardRewardSelectionScreen.cs", MOUSE_BUTTON_RIGHT]]:
		var screen := _box(_scripted(case[0], "extends Control
"), Vector2.ZERO)
		screen.size = Vector2(2424, 1080)
		screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var card := _scripted("NGridCardHolder.cs", ITEM_SOURCE)
		card.position = Vector2(900, 300)
		card.size = Vector2(200, 200)
		screen.add_child(card)
		boot.shown.clear()
		await _frames(2)
		_tap_now(_centre(card))
		await _frames(20)
		var other := MOUSE_BUTTON_RIGHT if case[1] == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_LEFT
		_check(card.presses.has([case[1], true]) and not card.presses.has([other, true]),
			"a tap on a card in %s %s" % [case[0], "takes it" if case[1] == MOUSE_BUTTON_LEFT else "inspects it"])
		_check(boot.shown.has(true) == (case[1] == MOUSE_BUTTON_RIGHT),
			"the tick %s in %s" % ["shows" if case[1] == MOUSE_BUTTON_RIGHT else "stays hidden", case[0]])
		boot._clear_pick()
		screen.queue_free()
		await _frames(2)


## The card inspect screen's hover tips (e.g. a card the inspected one refers to) appear only once its card has faded
## in (issue #8); tips of anything else are left alone.
const OPENING_CARD_SOURCE := """extends Control
var screen: Control
var tips_script: Script
var tips: Control
var other_tips: Control
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		screen.visible = true
		screen.mouse_filter = MOUSE_FILTER_STOP
		tips = tips_script.new()
		tips._owner = screen
		get_tree().root.add_child(tips)
		other_tips = tips_script.new()
		other_tips._owner = self
		get_tree().root.add_child(other_tips)
"""
func _test_inspect_tips_wait_for_card() -> void:
	var game := _inspection_container()
	var screen := _scripted("NInspectCardScreen.cs", INSPECT_SOURCE)
	screen.visible = false
	screen.size = Vector2(2424, 1080)
	game.get_node("InspectionContainer").add_child(screen)
	var card := _box(_scripted("NMerchantCard.cs", OPENING_CARD_SOURCE), Vector2(900, 300))
	card.screen = screen
	card.tips_script = _scripted("NHoverTipSet.cs", "extends Control
var _owner: Control
").get_script()
	await _frames(2)
	_tap_now(_centre(card))
	for i in range(20):
		await process_frame
		if card.tips != null:
			break
	_check(card.tips != null, "the tap opened the inspect screen")
	if card.tips != null:
		await process_frame
		_check(card.tips.modulate.a < 0.01, "the inspect screen's tips are hidden while its card fades in")
		_check(card.other_tips.modulate.a == 1.0, "other tips are left alone")
		await create_timer(0.4).timeout
		_check(card.tips.modulate.a > 0.99, "the inspect screen's tips are shown once its card is up")
		card.tips.queue_free()
		card.other_tips.queue_free()
	boot._clear_pick()
	card.queue_free()
	game.queue_free()
	await _frames(2)


## Issue #10: a tap on a card in the deck upgrade grid opens the upgrade preview over it. The card must lose its hover
## (the game clears its hover tips then), as it does on PC when the mouse moves; a finger's cursor never moves.
const COVERING_CARD_SOURCE := """extends Control
var hovered := false
var preview: Control
func _ready() -> void:
	mouse_entered.connect(func() -> void: hovered = true)
	mouse_exited.connect(func() -> void: hovered = false)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		preview.visible = true
		preview.mouse_filter = MOUSE_FILTER_STOP
"""
func _test_tap_unhovers_covered_card() -> void:
	var screen := _box(_scripted("NDeckUpgradeSelectScreen.cs", "extends Control
"), Vector2.ZERO)
	screen.size = Vector2(2424, 1080)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := _scripted("NGridCardHolder.cs", COVERING_CARD_SOURCE)
	card.position = Vector2(900, 300)
	card.size = Vector2(200, 200)
	screen.add_child(card)
	var preview := Control.new()
	preview.size = Vector2(2424, 1080)
	preview.visible = false
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(preview)
	card.preview = preview
	var plain := _box(_scripted("NPlainCard.cs", COVERING_CARD_SOURCE), Vector2(1400, 300))
	plain.preview = Control.new()  # a click that covers nothing
	await _frames(2)
	_tap_now(_centre(card))
	await _frames(20)
	_check(preview.visible, "the tap clicked the card and opened the preview")
	_check(not card.hovered, "the card covered by the preview its tap opened is no longer hovered")
	_tap_now(_centre(plain))
	await _frames(20)
	_check(plain.hovered, "a tapped card that nothing covers stays hovered (its tooltip stays up)")
	plain.preview.free()
	plain.queue_free()
	screen.queue_free()
	await _frames(2)


## One script per file name and source: taking over a path again would clear it on the earlier script.
var _scripts := {}
func _scripted(file: String, source: String) -> Control:
	var key := file + "\n" + source
	if not _scripts.has(key):
		var script := GDScript.new()
		script.source_code = source
		script.reload()
		script.take_over_path("res://mock/%d/%s" % [_scripts.size(), file])
		_scripts[key] = script
	var control: Control = _scripts[key].new()
	return control


func _box(control: Control, pos: Vector2) -> Control:
	control.position = pos
	control.size = Vector2(200, 200)
	root.add_child(control)
	return control


func _centre(control: Control) -> Vector2:
	return control.position + control.size / 2


## A finger down and up straight away, delivered to the touch layer this frame.
func _tap_now(pos: Vector2) -> void:
	_touch_now(pos, true)
	_touch_now(pos, false)


func _touch_now(pos: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = pos
	event.pressed = pressed
	boot._input(event)


## Finger down at the first point, moved through the rest one frame apart, lifted at the last.
func _drag_now(points: Array) -> void:
	_touch_now(points[0], true)
	for point in points.slice(1):
		await process_frame
		var drag := InputEventScreenDrag.new()
		drag.position = point
		boot._input(drag)
	await process_frame
	_touch_now(points[-1], false)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
