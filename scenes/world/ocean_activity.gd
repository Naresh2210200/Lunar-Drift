extends Node
## Drives water.gdshader's `activity` / `anim_time` uniforms from what's
## actually happening in the run, instead of letting the shader animate
## nonstop. Per design direction: continuous normal flight over the
## ocean should read as still and glassy — hazy, sleepy, "daizy/lazy" —
## and the water only wakes up for two things:
##   1. The opening cinematic approach in intro_sequence.gd (state isn't
##      PLAYING yet during the static-shot portion of that sequence).
##   2. A low-pass "collision" with the surface — player.gd's
##      water_dip_started/water_dip_ended is the closest thing this
##      project has to the boat actually brushing the water, so that's
##      the trigger rather than a literal CollisionShape hit.
##
## Deliberately its own small node rather than folded into
## ocean_follow.gd (owns re-centering the plane under the player) or
## moon_rig.gd (owns the moon/lighting side of the same material) — one
## job per script, same convention the rest of the project follows.
## Sits as a plain child of OceanPlane in main.tscn; it only reaches out
## to the shared ShaderMaterial resource and to Player's signals, so it
## needed no changes to either of those existing scripts.

## Same ShaderMaterial resource assigned to OceanPlane's
## surface_material_override/0 — set in the editor so this always
## targets whatever's actually on the mesh, rather than this script
## reaching into OceanPlane's MeshInstance3D to fish it out itself.
@export var ocean_material: ShaderMaterial
@export var player_path: NodePath

## How fast the target activity level (0 or 1) is chased. Deliberately
## slow rather than snapping — an instant on/off would read as a glitch,
## and the unhurried wake-up/settle-down is itself part of the lazy feel.
## 0.6 means a full 0->1 or 1->0 sweep takes roughly 1.6s.
@export var activity_lerp_speed: float = 0.6

var _activity: float = 1.0
var _anim_time: float = 0.0
var _in_dip: bool = false
var _player: Node = null


func _ready() -> void:
	_player = get_node_or_null(player_path)
	if _player:
		if _player.has_signal("water_dip_started"):
			_player.water_dip_started.connect(_on_dip_started)
		if _player.has_signal("water_dip_ended"):
			_player.water_dip_ended.connect(_on_dip_ended)
	else:
		push_warning("ocean_activity.gd: player_path did not resolve — water will only react to GameManager state, not low-pass dips.")

	# Starts fully awake: the opening approach shot should show live,
	# moving water, not a frozen plane, from the very first frame.
	_activity = 1.0
	_push()


func _process(delta: float) -> void:
	var target: float = 1.0 if (_in_dip or not _is_continuous_flight()) else 0.0
	_activity = move_toward(_activity, target, activity_lerp_speed * delta)
	_anim_time += delta * _activity
	_push()


## "Continuous flight" == the normal run loop. Any other state (menu,
## the pre-PLAYING portion of the intro, paused, game-over, etc.) counts
## as "not continuously moving" and keeps the water animated.
func _is_continuous_flight() -> bool:
	return GameManager.current_state == GameManager.GameState.PLAYING


func _on_dip_started() -> void:
	_in_dip = true


func _on_dip_ended() -> void:
	_in_dip = false


func _push() -> void:
	if ocean_material:
		ocean_material.set_shader_parameter("activity", _activity)
		ocean_material.set_shader_parameter("anim_time", _anim_time)
