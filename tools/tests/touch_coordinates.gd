extends SceneTree
## Exercise the real touch queue through Godot's window input pipeline, with no game or save files.

class TouchBoot extends "res://boot.gd":
	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		Input.emulate_mouse_from_touch = false

	func _ready() -> void:
		pass

	func _tap(pos: Vector2) -> void:
		_click(MOUSE_BUTTON_LEFT, pos)

class MouseObserver extends Node:
	var events: Array = []

	func _input(event: InputEvent) -> void:
		if event is InputEventMouse:
			events.append([event, Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
				Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)])

var boot: TouchBoot
var observer: MouseObserver
var button: Button
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	Input.use_accumulated_input = false
	boot = TouchBoot.new()
	root.add_child(boot)
	observer = MouseObserver.new()
	root.add_child(observer)
	button = Button.new()
	button.position = Vector2(800, 250)
	button.size = Vector2(160, 100)
	root.add_child(button)
	root.notify_mouse_entered()
	await _frames(2)
	for transform in [Transform2D.IDENTITY,
		Transform2D(Vector2(0.9, 0), Vector2(0, 0.9), Vector2(348, 0)),
		Transform2D(Vector2(0.75, 0), Vector2(0, 0.75), Vector2(492, 0)),
		Transform2D(Vector2(1.2, 0), Vector2(0, 1.2), Vector2(0, 90))]:
		root.global_canvas_transform = transform
		await _frames(2)
		observer.events.clear()
		var target := button.position + button.size / 2
		_touch(transform * target, true)
		_touch(transform * target, false)
		await _frames(12)
		_check_mouse(target, MOUSE_BUTTON_LEFT, true)
		_check_mouse(target, MOUSE_BUTTON_LEFT, false)
		# Drag coordinates, relative motion and global mouse-button state must also survive the transform.
		observer.events.clear()
		_touch(transform * target, true)
		await _frames(4)
		var end := target + Vector2(80, 50)
		var drag := InputEventScreenDrag.new()
		drag.position = transform * end
		Input.parse_input_event(drag)
		await _frames(4)
		_touch(transform * end, false)
		await _frames(8)
		_check_mouse(target, MOUSE_BUTTON_LEFT, true)
		_check_mouse(end, MOUSE_BUTTON_LEFT, false)
		var moved := false
		for entry in observer.events:
			var event = entry[0]
			if event is InputEventMouseMotion and event.button_mask == MOUSE_BUTTON_MASK_LEFT:
				moved = moved or (event.position.is_equal_approx(end) and event.relative.is_equal_approx(end - target))
		_check(moved, "drag position and relative motion remain in viewport coordinates")
		_check(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "drag releases Input's left-button state")
		# Long press still sends right-click inspect at the finger's viewport position.
		observer.events.clear()
		_touch(transform * target, true)
		boot._touch_down_msec = Time.get_ticks_msec() - boot.LONG_PRESS_MSEC
		await _frames(8)
		_touch(transform * target, false)
		await _frames(2)
		_check_mouse(target, MOUSE_BUTTON_RIGHT, true)
		_check_mouse(target, MOUSE_BUTTON_RIGHT, false)
	# A queued event must use the transform at delivery, after an aspect-ratio change.
	observer.events.clear()
	root.global_canvas_transform = Transform2D.IDENTITY
	var target := button.position + button.size / 2
	boot._enqueue(boot._motion(target, 0), boot._frame() + 2)
	boot._enqueue(boot._button(MOUSE_BUTTON_LEFT, true, target, MOUSE_BUTTON_MASK_LEFT), boot._frame() + 4)
	boot._enqueue(boot._button(MOUSE_BUTTON_LEFT, false, target, 0), boot._frame() + 7)
	root.global_canvas_transform = Transform2D(Vector2(0.9, 0), Vector2(0, 0.9), Vector2(348, 0))
	await _frames(12)
	_check_mouse(target, MOUSE_BUTTON_LEFT, true)
	_check_mouse(target, MOUSE_BUTTON_LEFT, false)
	print("Touch-coordinate checks: ", "PASS" if failures == 0 else "%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)


func _touch(screen_pos: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = screen_pos
	event.pressed = pressed
	Input.parse_input_event(event)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _check_mouse(pos: Vector2, mouse_button: MouseButton, pressed: bool) -> void:
	var found := false
	for entry in observer.events:
		var event = entry[0]
		if event is InputEventMouseButton and event.button_index == mouse_button and event.pressed == pressed:
			found = true
			_check(event.position.is_equal_approx(pos), "mouse button position matches the finger")
			_check(event.global_position.is_equal_approx(pos), "global mouse position matches viewport position")
			if mouse_button == MOUSE_BUTTON_LEFT:
				_check(entry[1] == pressed, "Input reports the correct left-button state")
			else:
				_check(entry[2] == pressed, "Input reports the correct right-button state")
	_check(found, "mouse button %d pressed=%s is delivered" % [mouse_button, pressed])


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
