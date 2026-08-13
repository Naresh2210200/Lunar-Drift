extends Control
## scenes/ui/mobile/round_touch_button.gd
##
## Draws a round papercraft-style touch button (Jump / Boost / Pause).
## Pure visual — mouse_filter is IGNORE on these nodes in
## mobile_controls.tscn, so mobile_input_controller.gd does all the hit
## testing and just calls set_pressed_visual()/set_ready_state() on this
## node directly.

## 0 = jump, 1 = boost, 2 = pause — matches icon= values in mobile_controls.tscn
@export var icon: int = 0
## Idle (non-pressed) alpha. JumpButton/BoostButton default to fully
## opaque; PauseButton sets 0.4 in the scene to sit quietly in the corner.
@export var idle_alpha: float = 1.0

const BASE_RADIUS: float = 90.0
const PRESSED_SCALE: float = 0.92
const OUTLINE_WIDTH: float = 6.0
const COLOR_PAPER: Color = Color(1, 1, 1, 1)
const COLOR_INK: Color = Color(0.08, 0.08, 0.08, 1)
const COLOR_DISABLED_FILL: Color = Color(0.65, 0.65, 0.65, 1)

var _pressed: bool = false
var _ready_state: bool = true


func _ready() -> void:
	modulate.a = idle_alpha
	# Redraw whenever the rect actually gets its runtime size from anchors,
	# since _draw() below centers on `size`.
	resized.connect(queue_redraw)


func set_pressed_visual(pressed: bool) -> void:
	if _pressed == pressed:
		return
	_pressed = pressed
	queue_redraw()


func set_ready_state(is_ready: bool) -> void:
	if _ready_state == is_ready:
		return
	_ready_state = is_ready
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size / 2.0
	var radius: float = BASE_RADIUS * (PRESSED_SCALE if _pressed else 1.0)
	var fill_color: Color = COLOR_PAPER if _ready_state else COLOR_DISABLED_FILL

	# Folded-paper disc: flat fill + bold ink outline, no gradients/shadows,
	# consistent with the rest of Lunar Drift's papercraft art direction.
	draw_circle(center, radius, fill_color)
	draw_arc(center, radius, 0.0, TAU, 48, COLOR_INK, OUTLINE_WIDTH, true)

	var icon_color: Color = COLOR_INK if _ready_state else COLOR_DISABLED_FILL.darkened(0.3)
	match icon:
		0:
			_draw_jump_icon(center, radius, icon_color)
		1:
			_draw_boost_icon(center, radius, icon_color)
		2:
			_draw_pause_icon(center, radius, icon_color)
		_:
			pass


## Single upward chevron — "go up".
func _draw_jump_icon(center: Vector2, radius: float, color: Color) -> void:
	var s: float = radius * 0.5
	var points := PackedVector2Array([
		center + Vector2(0, -s),
		center + Vector2(s * 0.85, s * 0.55),
		center + Vector2(0, s * 0.1),
		center + Vector2(-s * 0.85, s * 0.55),
	])
	draw_colored_polygon(points, color)


## Stacked double chevron — "go up, faster".
func _draw_boost_icon(center: Vector2, radius: float, color: Color) -> void:
	var s: float = radius * 0.42
	for offset_y in [-s * 0.55, s * 0.55]:
		var points := PackedVector2Array([
			center + Vector2(0, offset_y - s * 0.45),
			center + Vector2(s * 0.75, offset_y + s * 0.3),
			center + Vector2(-s * 0.75, offset_y + s * 0.3),
		])
		draw_colored_polygon(points, color)


## Two vertical bars.
func _draw_pause_icon(center: Vector2, radius: float, color: Color) -> void:
	var bar_w: float = radius * 0.2
	var bar_h: float = radius * 0.7
	var gap: float = radius * 0.14
	draw_rect(Rect2(center - Vector2(gap + bar_w, bar_h / 2.0), Vector2(bar_w, bar_h)), color)
	draw_rect(Rect2(center + Vector2(gap, -bar_h / 2.0), Vector2(bar_w, bar_h)), color)
