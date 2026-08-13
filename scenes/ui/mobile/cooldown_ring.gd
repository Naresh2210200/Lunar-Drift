extends Control
## scenes/ui/mobile/cooldown_ring.gd
##
## Ring overlay drawn on top of JumpButton showing jump cooldown
## remaining. mobile_input_controller.gd owns all the timing — it calls
## set_progress(remaining / jump_cooldown_seconds) every _process() while
## on cooldown, and set_progress(0.0) once ready. This node just draws
## whatever fraction it's given.

const RING_OFFSET: float = 8.0  # sits just outside the button's own outline
const RING_WIDTH: float = 8.0
const COLOR_RING: Color = Color(0.08, 0.08, 0.08, 0.85)

# Matches BASE_RADIUS in round_touch_button.gd so the ring hugs the button.
# (Was 60.0, silently out of sync with round_touch_button's 90.0 — fixed
# to actually match now, and bumped to 108.0 alongside that button's own
# size increase.)
const BUTTON_RADIUS: float = 108.0

var _progress: float = 0.0  # 1.0 = just used (full ring), 0.0 = ready (no ring)


func _ready() -> void:
	resized.connect(queue_redraw)


func set_progress(value: float) -> void:
	var clamped: float = clamp(value, 0.0, 1.0)
	if is_equal_approx(clamped, _progress):
		return
	_progress = clamped
	queue_redraw()


func _draw() -> void:
	if _progress <= 0.0:
		return
	var center: Vector2 = size / 2.0
	var radius: float = BUTTON_RADIUS + RING_OFFSET
	# Sweeps clockwise from the top, draining as the cooldown finishes —
	# a full ring right after jumping, shrinking to nothing when ready.
	var start_angle: float = -PI / 2.0
	var end_angle: float = start_angle + TAU * _progress
	draw_arc(center, radius, start_angle, end_angle, 48, COLOR_RING, RING_WIDTH, true)
