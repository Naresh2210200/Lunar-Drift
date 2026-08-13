extends Node3D
## Chase camera. Position lerps to trail the target; rotation stays fixed
## looking forward (-Z, same as the player's travel direction) as its base
## state — a full look_at() every frame reads as jittery for a runner where
## the player barely changes facing, so a locked base rotation still reads
## calmer and matches the genre (Race the Sun, Subway Surfers).
## Deliberately decoupled from Player (NodePath, not a child-of
## relationship) so Player.tscn stays testable on its own without dragging
## a camera along with it.
##
## Two additions on top of that locked-forward baseline:
##   - Bank follow: the rig itself rolls a fraction of however much the
##     player's hull is currently banked, read straight off Player's
##     MeshPivot rather than re-deriving it from input. Deliberately a
##     *fraction* (camera_bank_influence, default 0.35) — copying the
##     player's full bank would make the horizon lurch and fight the
##     "calm chase camera" read this rig exists for.
##   - Speed FOV punch: field of view widens as the target's actual
##     move_and_slide() velocity grows, so a boosted or ramped-up run
##     reads as faster even though the camera never gets closer or the
##     boat never visually speeds up its own animation.

@export var target_path: NodePath
@export var follow_offset: Vector3 = Vector3(0.0, 3.0, 6.0)
@export var position_smoothing: float = 5.0

@export_group("Bank Follow")
@export var camera_bank_influence: float = 0.35
@export var bank_follow_smoothing: float = 4.0
## Caps how far rotation.z is allowed to read before scaling by
## camera_bank_influence. Needed because Player's MeshPivot.rotation.z now
## also carries the full 360° drift roll flip (added after this rig was
## first written) — that axis briefly sweeps the whole circle instead of
## staying inside the small normal lean range, and without this clamp the
## camera would try to follow the entire flip too, which is exactly the
## "horizon lurch" this rig's fractional-influence design was meant to
## avoid in the first place. Default matches Player's bank_angle_max
## (~25°) plus a little headroom — keep the two roughly in sync in the
## editor.
@export var bank_follow_clamp: float = deg_to_rad(30.0)
## Name of the target's mesh-pivot child to read bank rotation from. Kept
## as a name lookup rather than a second NodePath export so wiring a new
## target in the editor only means setting target_path, same as before.
@export var target_mesh_pivot_name: String = "MeshPivot"

@export_group("Speed FOV")
@export var camera_path: NodePath = ^"Camera3D"
@export var fov_base: float = 75.0
@export var fov_max: float = 88.0
## Target velocity length at which fov_max is fully reached. Deliberately
## a separate number from Player's own speed exports — this script has no
## reference to Player's script, only to its Node3D/CharacterBody3D API
## (global_position, velocity) — so keep it roughly matched to Player's
## forward_speed + max_speed_bonus + boost in the editor.
@export var fov_reference_speed: float = 55.0
@export var fov_lerp_speed: float = 3.0

@onready var _target: Node3D = get_node(target_path)
## Declared null here and resolved in _ready() below with an explicit
## is_empty() guard, rather than an inline @onready expression — an inline
## get_node()/get_node_or_null() call still runs (and can still log an
## error) even when camera_path is empty, since NodePath("") is an
## invalid path rather than a "no path" sentinel. Guarding first means
## camera_path being left unset just quietly disables the FOV feature
## instead of logging anything.
var _camera: Camera3D = null

var _target_mesh_pivot: Node3D = null
## Node3D (the type target_path is typed as) has no `velocity` member — only
## CharacterBody3D does. Cached once here via `as`, rather than casting
## every frame, so _update_speed_fov can read it directly and just no-ops
## if the target ever isn't a CharacterBody3D.
var _target_body: CharacterBody3D = null


func _ready() -> void:
	if _target and _target.has_node(target_mesh_pivot_name):
		_target_mesh_pivot = _target.get_node(target_mesh_pivot_name)
	_target_body = _target as CharacterBody3D

	if not camera_path.is_empty():
		_camera = get_node_or_null(camera_path) as Camera3D
		if _camera == null:
			# Left unset/wrong in the editor rather than silently eating the
			# FOV feature — worth a warning since it's easy to miss otherwise.
			push_warning("camera_rig.gd: camera_path '%s' did not resolve to a Camera3D — speed FOV disabled." % camera_path)

	_configure_physics_interpolation()


## Physics interpolation smooths the visual transform between physics ticks,
## which is what makes the desktop build read as buttery even when the
## physics tick rate dips — but on mobile it adds an extra transform lerp on
## top of already-tighter frame budgets, and that's the "worse" feel being
## reported there. Rather than pick one setting for both, decide at runtime:
## desktop keeps interpolation ON (that's the smoother feel worth keeping),
## mobile explicitly forces it OFF (matching how it already behaved before
## interpolation was turned on project-wide). This overrides whatever the
## editor/.tscn default was baked to, so the .tscn value no longer needs to
## be kept in sync by hand.
func _configure_physics_interpolation() -> void:
	var mode := Node.PHYSICS_INTERPOLATION_MODE_OFF if OS.has_feature("mobile") else Node.PHYSICS_INTERPOLATION_MODE_ON
	if _camera:
		_camera.physics_interpolation_mode = mode
	if _target:
		_target.physics_interpolation_mode = mode


func _process(delta: float) -> void:
	if _target == null:
		return

	var desired_position := _target.global_position + follow_offset
	global_position = global_position.lerp(desired_position, delta * position_smoothing)

	_update_bank_follow(delta)
	_update_speed_fov(delta)


## Reads the player's current bank angle straight off its MeshPivot rather
## than recomputing it from steer input here — this rig has no opinion on
## how banking is produced, only that it exists and is worth a fraction of.
## Clamped to bank_follow_clamp first — see that export's comment — so a
## drift roll flip's full 360° sweep on the same axis doesn't drag the
## camera through the whole rotation with it.
func _update_bank_follow(delta: float) -> void:
	var target_roll := 0.0
	if _target_mesh_pivot:
		var clamped_bank := clampf(_target_mesh_pivot.rotation.z, -bank_follow_clamp, bank_follow_clamp)
		target_roll = clamped_bank * camera_bank_influence
	rotation.z = lerp_angle(rotation.z, target_roll, delta * bank_follow_smoothing)


## CharacterBody3D exposes `velocity` publicly, so this reads the boat's
## actual current move_and_slide() speed directly — no dependency on
## Player's internal speed-ramp/boost math, just the result of it.
func _update_speed_fov(delta: float) -> void:
	if _camera == null or _target_body == null:
		return
	var speed_ratio: float = clamp(_target_body.velocity.length() / fov_reference_speed, 0.0, 1.0)
	# `: float`, not `:=` — lerp() returns Variant in its engine binding too,
	# same reason clamp() needed it two lines up.
	var target_fov: float = lerp(fov_base, fov_max, speed_ratio)
	_camera.fov = lerp(_camera.fov, target_fov, delta * fov_lerp_speed)
