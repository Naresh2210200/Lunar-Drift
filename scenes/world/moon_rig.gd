extends Node3D
## MoonRig — the single source of truth for "where the moon is right now."
## Follows the player (X/Z, same trick as OceanPlane) so it stays in the
## sky, drifts it laterally over time (the thing the player is visually
## chasing), then syncs the DirectionalLight and the ocean shader's
## moon_direction uniform to match wherever the moon ends up.
##
## Deliberately one script, not three. Light direction, fog, and the water
## glint all have to agree on the same moon position every frame — splitting
## that into separate Light/Fog/ShaderSync scripts would just create three
## places that could drift out of sync with each other. This isn't the
## "avoid tight coupling" rule being broken; that rule is about decoupling
## independent *behaviors*, not about who's allowed to own one shared fact.
##
## "Day/night progression" here means the night itself deepening over a
## run — fog thickening, moonlight sharpening — not a literal sun cycle.
## The brief is set entirely at night; a sun would contradict that. Flagging
## this interpretation explicitly in case a literal day cycle was intended.

@export var target_path: NodePath
@export var ocean_material: ShaderMaterial
@export var environment: Environment

@export_group("Drift")
@export var drift_speed: float = 0.05
@export var drift_range_degrees: float = 14.0

@export_group("Night Progression")
@export var progression_duration: float = 240.0
@export var fog_density_start: float = 0.015
@export var fog_density_end: float = 0.03
@export var light_energy_start: float = 0.8
@export var light_energy_end: float = 1.4

@onready var _target: Node3D = get_node(target_path)
@onready var _moon_pivot: Node3D = $MoonPivot
@onready var _moon: Node3D = $MoonPivot/Moon
@onready var _light: DirectionalLight3D = $Moonlight

var _time: float = 0.0

func _ready() -> void:
	# This rig already owns every surface a color theme touches —
	# ocean_material, environment, and (via _light/_moon) the moonlight
	# and the moon's own glow — so it's the natural place to also react
	# to ThemeManager instead of a separate listener node, per this
	# script's own "single source of truth, one script not three" header.
	# Synced once immediately after connecting in case ThemeManager
	# already left Sketch before this rig existed (e.g. a scene reload
	# mid-run), rather than staying on the default palette until the next
	# 50000-score crossing.
	if has_node("/root/ThemeManager"):
		var theme_manager: Node = get_node("/root/ThemeManager")
		theme_manager.theme_changed.connect(_on_theme_changed)
		_apply_theme(theme_manager.get_current_theme())

func _process(delta: float) -> void:
	_time += delta

	if _target:
		global_position.x = _target.global_position.x
		global_position.z = _target.global_position.z

	# Slow lateral wander overhead — this is what "chasing the moon" means
	# visually right now. It doesn't gate moon energy yet; see the flag
	# in this milestone's writeup for why that's deferred.
	_moon_pivot.rotation_degrees.y = sin(_time * drift_speed) * drift_range_degrees

	# Light travels FROM the moon TOWARD the world — position the light at
	# the moon and look back at the rig's center (roughly the play area).
	var moon_pos := _moon.global_position
	_light.global_position = moon_pos
	_light.look_at(global_position, Vector3.UP)

	# Same contract the water shader has used since Milestone 3:
	# moon_direction points FROM the water TOWARD the moon.
	if ocean_material:
		var to_moon := (moon_pos - global_position).normalized()
		ocean_material.set_shader_parameter("moon_direction", to_moon)

	var progress: float = clamp(_time / progression_duration, 0.0, 1.0)
	if environment:
		environment.fog_density = lerp(fog_density_start, fog_density_end, progress)
	_light.light_energy = lerp(light_energy_start, light_energy_end, progress)


func _on_theme_changed(_theme_id: int, theme: Dictionary) -> void:
	_apply_theme(theme)


## Pushes ThemeManager's environment palette into every surface this rig
## already holds a reference to — ocean_material (water color + the
## shader's own stylized moon-glint), environment (sky background/ambient/
## fog color — NOT fog_density, which stays owned by the night-progression
## lerp above and is left untouched), Moonlight's color, and the Moon
## mesh's own glow material. Kept here rather than split into separate
## listener nodes for the exact reason this script is one file and not
## three (see header): all of these have to agree on the same "what does
## the world look like right now" fact, same as moon_direction/fog above.
func _apply_theme(theme: Dictionary) -> void:
	if ocean_material:
		ocean_material.set_shader_parameter("WATER_COL", theme["water_col"])
		ocean_material.set_shader_parameter("WATER2_COL", theme["water2_col"])
		ocean_material.set_shader_parameter("FOAM_COL", theme["foam_col"])
		ocean_material.set_shader_parameter("moon_glow_color", theme["moon_glow_color"])
		ocean_material.set_shader_parameter("glow_strength", theme["moon_glow_strength"])

	if environment:
		environment.background_color = theme["background_color"]
		environment.ambient_light_color = theme["ambient_color"]
		if environment.fog_enabled:
			environment.fog_light_color = theme["fog_color"]

	if _light:
		_light.light_color = theme["moon_light_color"]

	# _moon is typed Node3D (see the @onready above) since MoonPivot/Moon
	# is only ever moved/read as a plain transform elsewhere in this
	# script — cast locally here, the one place that needs its material.
	var moon_mesh := _moon as MeshInstance3D
	if moon_mesh:
		var moon_mat := moon_mesh.get_surface_override_material(0)
		if moon_mat is StandardMaterial3D:
			moon_mat.emission = theme["moon_glow_color"]
			moon_mat.emission_energy_multiplier = theme["moon_glow_strength"]
