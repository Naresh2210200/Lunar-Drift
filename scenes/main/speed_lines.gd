extends ColorRect
## Screen-space "sense of speed" overlay. Same one-script-per-effect
## pattern as ocean_follow.gd/moon_rig.gd — this owns "how strong do the
## speed lines look right now" and nothing else; the actual streak drawing
## lives entirely in speed_lines.gdshader.
##
## Sits on a full-rect ColorRect in a CanvasLayer above the 3D viewport
## (see main.tscn) rather than a 3D-space effect, so it stays resolution-
## independent and doesn't need its own camera.
##
## Placed under scenes/main/ alongside camera_rig.gd rather than
## scenes/ui/ — Phase 10 (Paper UI) is still empty and this is a gameplay
## feel effect tied to camera/motion, not a menu/HUD element, even though
## it happens to render through a CanvasLayer.

@export var target_path: NodePath
## Velocity length below this contributes zero intensity — cruising speed
## shouldn't show streaks at all; they're for boosts and ramp-fueled highs.
@export var min_speed: float = 24.0
## Velocity length at which the effect reaches full intensity (matches the
## uniform's 0..1 range). Kept as its own number rather than reusing
## camera_rig's fov_reference_speed — the two effects are allowed to peak
## at different speeds if that reads better once tuned.
@export var max_speed: float = 60.0
@export var intensity_lerp_speed: float = 5.0

@onready var _target: CharacterBody3D = get_node(target_path) as CharacterBody3D

var _current_intensity: float = 0.0


func _process(delta: float) -> void:
	if _target == null or material == null:
		return

	var speed := _target.velocity.length()
	var target_intensity: float = clamp(
		(speed - min_speed) / max(max_speed - min_speed, 0.01), 0.0, 1.0
	)
	_current_intensity = move_toward(_current_intensity, target_intensity, intensity_lerp_speed * delta)
	material.set_shader_parameter("intensity", _current_intensity)
