extends CanvasLayer
## scenes/ui/mobile/customize_controls_overlay.gd
##
## The "Customize Controls" screen. Opened from Settings (see
## main_menu.gd's _on_customize_controls_pressed) — deliberately does
## NOT require GameManager to be PLAYING and does not touch it at all.
##
## Doesn't create a second set of buttons to drag around. Instead it
## reaches into the ALREADY-instanced MobileControls layer (see
## MobileControlsLoader.mobile_controls — one instance for the whole
## app run, this screen never creates another) and temporarily takes
## over input on the three real button nodes:
## - mouse_filter flips from IGNORE to STOP so they start receiving
##   gui_input (they're normally IGNORE because mobile_input_controller.gd
##   does its own manual hit-testing on raw touch events instead — see
##   that script's header comment).
## - gui_input is connected here to drive dragging (position) directly,
##   plus a size slider and opacity slider below for the selected button.
## - Both are reverted in _exit_tree() so gameplay goes right back to
##   exactly how it worked before this screen ever opened.
##
## mobile_input_controller.gd itself is not touched while this is open —
## it just stops reading input at all (see its `_customize_mode` guard),
## so a drag here can never reach jump/boost/steer_left/steer_right.

const BUTTON_NODE_NAMES: Dictionary = {
	&"jump": "JumpButton",
	&"boost": "BoostButton",
	&"pause": "PauseButton",
}
const BUTTON_LABELS: Dictionary = {
	&"jump": "Jump",
	&"boost": "Boost",
	&"pause": "Pause",
}

@onready var _instruction_label: Label = $TopBar/InstructionLabel
@onready var _selected_label: Label = $BottomPanel/Layout/SelectedRow/SelectedLabel
@onready var _size_slider: HSlider = $BottomPanel/Layout/SizeRow/SizeSlider
@onready var _opacity_slider: HSlider = $BottomPanel/Layout/OpacityRow/OpacitySlider
@onready var _reset_button: Button = $BottomPanel/Layout/ButtonRow/ResetButton
@onready var _done_button: Button = $BottomPanel/Layout/ButtonRow/DoneButton

var _mobile_controls: CanvasLayer = null
var _buttons: Dictionary = {}       # StringName -> Control
var _selected_id: StringName = &"jump"

var _drag_touch_index: int = -1
var _dragging_mouse: bool = false
var _drag_start_delta: Vector2 = Vector2.ZERO
var _drag_start_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	layer = 15  # above MobileControls (layer 10, see mobile_controls.tscn)

	_mobile_controls = MobileControlsLoader.mobile_controls
	if _mobile_controls == null:
		# Touch platform only (see mobile_controls_loader.gd) — on desktop
		# there's nothing instanced to customize. Nothing to show.
		push_warning("MobileControls: no mobile control layer on this platform — closing Customize Controls.")
		queue_free()
		return

	for button_id in BUTTON_NODE_NAMES.keys():
		var control: Control = _mobile_controls.get_node(BUTTON_NODE_NAMES[button_id])
		_buttons[button_id] = control
		control.mouse_filter = Control.MOUSE_FILTER_STOP
		control.gui_input.connect(_on_button_gui_input.bind(button_id))

	MobileControls.enter_customize_mode()

	_size_slider.min_value = MobileControls.MIN_SCALE
	_size_slider.max_value = MobileControls.MAX_SCALE
	_opacity_slider.min_value = MobileControls.MIN_OPACITY
	_opacity_slider.max_value = MobileControls.MAX_OPACITY

	_size_slider.value_changed.connect(_on_size_slider_changed)
	_opacity_slider.value_changed.connect(_on_opacity_slider_changed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_done_button.pressed.connect(_on_done_pressed)

	_select(&"jump")
	_instruction_label.text = "Drag a button to move it. Tap one to select it, then use the sliders below."


## Guarantees the real buttons are handed back to mobile_input_controller.gd
## exactly as it left them, no matter how this screen closes (Done button,
## or the node just being freed some other way) — mouse_filter is the one
## thing this screen changes on them, so it's the one thing to undo.
func _exit_tree() -> void:
	for button_id in _buttons.keys():
		var control: Control = _buttons[button_id]
		if is_instance_valid(control):
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if MobileControls.customize_mode:
		MobileControls.exit_customize_mode(true)


# ---------------------------------------------------------------------
# Selection — tapping a button (without dragging it far) selects it so
# the Size/Opacity sliders below reflect and control that button.
# ---------------------------------------------------------------------

func _select(button_id: StringName) -> void:
	_selected_id = button_id
	_selected_label.text = "Selected: %s" % BUTTON_LABELS.get(button_id, String(button_id))
	_size_slider.set_value_no_signal(MobileControls.get_scale(button_id))
	_opacity_slider.set_value_no_signal(MobileControls.get_opacity(button_id))


# ---------------------------------------------------------------------
# Dragging — works from both real touch (mobile) and mouse (desktop
# testing), same as mobile_input_controller.gd's own approach elsewhere
# of not assuming one or the other.
# ---------------------------------------------------------------------

func _on_button_gui_input(event: InputEvent, button_id: StringName) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_select(button_id)
			_drag_touch_index = event.index
			_drag_start_delta = MobileControls.get_offset_delta(button_id)
			_drag_start_pos = event.position
		elif event.index == _drag_touch_index:
			_drag_touch_index = -1

	elif event is InputEventScreenDrag:
		if event.index == _drag_touch_index:
			var moved: Vector2 = event.position - _drag_start_pos
			MobileControls.set_offset_delta(button_id, _drag_start_delta + moved)

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_select(button_id)
			_dragging_mouse = true
			_drag_start_delta = MobileControls.get_offset_delta(button_id)
			_drag_start_pos = event.position
		else:
			_dragging_mouse = false

	elif event is InputEventMouseMotion:
		if _dragging_mouse:
			var moved: Vector2 = event.position - _drag_start_pos
			MobileControls.set_offset_delta(button_id, _drag_start_delta + moved)


# ---------------------------------------------------------------------
# Sliders / buttons
# ---------------------------------------------------------------------

func _on_size_slider_changed(value: float) -> void:
	MobileControls.set_scale(_selected_id, value)


func _on_opacity_slider_changed(value: float) -> void:
	MobileControls.set_opacity(_selected_id, value)


func _on_reset_pressed() -> void:
	MobileControls.reset_button(_selected_id)
	_size_slider.set_value_no_signal(MobileControls.get_scale(_selected_id))
	_opacity_slider.set_value_no_signal(MobileControls.get_opacity(_selected_id))


func _on_done_pressed() -> void:
	queue_free()  # _exit_tree() above saves + exits customize mode + restores mouse_filter
