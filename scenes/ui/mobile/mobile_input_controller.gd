extends Node
## scenes/ui/mobile/mobile_input_controller.gd
##
## Owns ALL touch handling for the mobile control scheme via raw
## InputEventScreenTouch events, rather than letting each zone/button
## handle its own Control input — that keeps the one genuinely tricky
## part (which finger owns which control, and ref-counting per action so
## two fingers on the same steering zone don't fight over a single
## release) in exactly one place instead of scattered across five nodes.
## LeftTouchZone/RightTouchZone/JumpButton/BoostButton are all
## mouse_filter = IGNORE and otherwise passive — this node hit-tests
## their get_global_rect() directly against each touch's position.
##
## Simulates the existing gameplay input actions via
## Input.action_press()/action_release() — steer_left, steer_right,
## jump, boost — so player.gd (and anything else reading those actions)
## needs zero changes and zero awareness this scene exists.
##
## Deliberately does NOT handle InputEventScreenDrag: which control a
## touch controls is decided once, at touch-down, by where the finger
## landed. Per spec this is a hold-zone scheme, not swipe/drag — a
## finger dragging from one zone into another should not retarget
## mid-touch.
##
## Hides the whole MobileControls layer (and releases every held action)
## whenever GameManager leaves PLAYING, same "read GameManager,
## everything else is a one-way listener" shape as hud.gd — so controls
## disappear during Menu/Paused/Game Over instead of sitting uselessly
## on top of those screens, and nothing is left stuck held mid-touch
## across a state change.

@export var jump_cooldown_seconds: float = 1.2

@onready var _left_zone: Control = get_node("../LeftTouchZone")
@onready var _right_zone: Control = get_node("../RightTouchZone")
@onready var _jump_button: Control = get_node("../JumpButton")
@onready var _boost_button: Control = get_node("../BoostButton")
@onready var _pause_button: Control = get_node("../PauseButton")
@onready var _cooldown_ring: Control = get_node("../JumpButton/CooldownCircle")

# touch index (int) -> which control claimed it: "left"/"right"/"jump"/"boost"
var _touch_owner: Dictionary = {}
# Ref-counted per held action so N fingers on one zone/button release cleanly
# (only the LAST finger lifting off actually releases the action).
var _action_hold_counts: Dictionary = {"steer_left": 0, "steer_right": 0, "boost": 0}

var _jump_on_cooldown: bool = false
var _jump_cooldown_remaining: float = 0.0


func _ready() -> void:
	_apply_safe_area()
	_cooldown_ring.set_progress(0.0)
	set_process(false)

	GameManager.state_changed.connect(_on_game_state_changed)
	_on_game_state_changed(GameManager.current_state)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_touch_down(event.index, event.position)
		else:
			_on_touch_up(event.index)


func _on_touch_down(index: int, position: Vector2) -> void:
	if not get_parent().visible:
		return  # controls hidden (menu/paused/game over) — ignore stray touches

	if _pause_button.get_global_rect().has_point(position):
		# A bare tap, same as jump — hud.gd's own PausePanel (with the
		# actual Resume button) reacts to Input.is_action_just_pressed
		# ("pause") in its own _process, same trigger the "pause" key
		# uses on desktop, so this button needs no pause/resume logic of
		# its own. This whole layer hides itself once GameManager leaves
		# PLAYING (see _on_game_state_changed), so tapping here again
		# mid-pause isn't reachable — resuming happens through hud.gd's
		# real Resume button instead, which already works under touch
		# via Godot's default mouse-from-touch emulation.
		Input.action_press("pause")
		Input.action_release("pause")
		return

	if _boost_button.get_global_rect().has_point(position):
		_touch_owner[index] = "boost"
		_hold_action("boost")
		_boost_button.set_pressed_visual(true)
		return

	if _jump_button.get_global_rect().has_point(position):
		if not _jump_on_cooldown:
			_touch_owner[index] = "jump"
			Input.action_press("jump")
			Input.action_release("jump")  # jump is a tap, not a hold
			_jump_button.set_pressed_visual(true)
			_start_jump_cooldown()
		return

	if _left_zone.get_global_rect().has_point(position):
		_touch_owner[index] = "left"
		_hold_action("steer_left")
		return

	if _right_zone.get_global_rect().has_point(position):
		_touch_owner[index] = "right"
		_hold_action("steer_right")


func _on_touch_up(index: int) -> void:
	var owner: String = _touch_owner.get(index, "")
	if owner == "":
		return
	_touch_owner.erase(index)
	_release_owner(owner)


func _release_owner(owner: String) -> void:
	match owner:
		"boost":
			_release_action("boost")
			if _action_hold_counts["boost"] == 0:
				_boost_button.set_pressed_visual(false)
		"left":
			_release_action("steer_left")
		"right":
			_release_action("steer_right")
		"jump":
			_jump_button.set_pressed_visual(false)


func _hold_action(action: StringName) -> void:
	_action_hold_counts[action] += 1
	if _action_hold_counts[action] == 1:
		Input.action_press(action)


func _release_action(action: StringName) -> void:
	if _action_hold_counts.get(action, 0) <= 0:
		return
	_action_hold_counts[action] -= 1
	if _action_hold_counts[action] == 0:
		Input.action_release(action)


func _start_jump_cooldown() -> void:
	_jump_on_cooldown = true
	_jump_cooldown_remaining = jump_cooldown_seconds
	_jump_button.set_ready_state(false)
	set_process(true)


func _process(delta: float) -> void:
	if not _jump_on_cooldown:
		set_process(false)
		return
	_jump_cooldown_remaining = max(_jump_cooldown_remaining - delta, 0.0)
	_cooldown_ring.set_progress(_jump_cooldown_remaining / jump_cooldown_seconds)
	if _jump_cooldown_remaining <= 0.0:
		_jump_on_cooldown = false
		_jump_button.set_ready_state(true)


func _on_game_state_changed(new_state) -> void:
	var should_show: bool = new_state == GameManager.GameState.PLAYING
	get_parent().visible = should_show
	if not should_show:
		_release_all_touches()


## Clears every in-progress touch/action when controls hide (pause, game
## over, menu) so nothing is left stuck "held" — e.g. a finger still
## down on the Boost button when the player pauses shouldn't leave boost
## silently active when they resume.
func _release_all_touches() -> void:
	for owner in _touch_owner.values():
		_release_owner(owner)
	_touch_owner.clear()


func _apply_safe_area() -> void:
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	if screen_size.x <= 0 or screen_size.y <= 0:
		return
	var safe_rect: Rect2i = DisplayServer.get_display_safe_area()

	var inset_left: float = safe_rect.position.x
	var inset_top: float = safe_rect.position.y
	var inset_right: float = screen_size.x - (safe_rect.position.x + safe_rect.size.x)
	var inset_bottom: float = screen_size.y - (safe_rect.position.y + safe_rect.size.y)

	if inset_left <= 0.0 and inset_top <= 0.0 and inset_right <= 0.0 and inset_bottom <= 0.0:
		return  # no notch/cutout/gesture-bar inset to account for

	# Zones stretch-anchor across a fraction of the screen (see
	# mobile_controls.tscn) — inset from just the outer edge each one
	# touches, rather than translating the whole rect, so they still
	# meet in the middle instead of leaving (or opening) a gap.
	_left_zone.offset_left += inset_left
	_left_zone.offset_bottom -= inset_bottom
	_right_zone.offset_right -= inset_right
	_right_zone.offset_bottom -= inset_bottom

	# Jump/Boost are fixed-size, point-anchored controls (see
	# mobile_controls.tscn) — translate the whole rect to keep them off
	# the notch/cutout/gesture-bar without resizing them.
	_shift_control(_jump_button, inset_left, -inset_bottom)
	_shift_control(_boost_button, -inset_right, -inset_bottom)
	_shift_control(_pause_button, -inset_right, inset_top)


## Moves a fixed-size, point-anchored Control by (dx, dy) without
## resizing it — offset_left/right/top/bottom together define its rect
## relative to its anchor point, so shifting all four by the same amount
## translates the whole rect in place.
func _shift_control(control: Control, dx: float, dy: float) -> void:
	control.offset_left += dx
	control.offset_right += dx
	control.offset_top += dy
	control.offset_bottom += dy
