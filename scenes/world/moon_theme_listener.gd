extends Node
## Attach this as a child of your moon_rig.gd node (scenes/world/) and
## assign whichever of the two exports below actually apply to your
## setup in the Inspector — leave either blank if it doesn't exist.
##
## `moon_light` — the moon's DirectionalLight3D (or a SpotLight3D/
## OmniLight3D if that's how it's built): its light_color is set to each
## theme's `moon_light_color`.
## `moon_material` — a StandardMaterial3D or ShaderMaterial on the moon's
## own mesh, if it glows via emission rather than (or in addition to)
## a Light3D: its `emission`/`albedo_color` is set to `moon_glow_color`,
## scaled by `moon_glow_strength`.
##
## Written generically since moon_rig.gd itself isn't available to build
## this against directly — send it over and I'll fold these few lines
## straight into it instead of a separate node.

@export var moon_light: Light3D
@export var moon_material: Material


func _ready() -> void:
	if not has_node("/root/ThemeManager"):
		push_warning("moon_theme_listener.gd: ThemeManager autoload not found — moon color will stay at its default.")
		return
	var theme_manager: Node = get_node("/root/ThemeManager")
	theme_manager.theme_changed.connect(_on_theme_changed)
	_on_theme_changed(theme_manager.current_theme_id, theme_manager.get_current_theme())


func _on_theme_changed(_theme_id: int, theme: Dictionary) -> void:
	var glow_color: Color = theme.get("moon_glow_color", Color.WHITE)
	var glow_strength: float = theme.get("moon_glow_strength", 1.0)

	if moon_light:
		moon_light.light_color = theme.get("moon_light_color", Color.WHITE)

	if moon_material:
		if moon_material is StandardMaterial3D:
			var std_mat: StandardMaterial3D = moon_material
			std_mat.emission = glow_color
			std_mat.emission_energy_multiplier = glow_strength
		elif moon_material is ShaderMaterial:
			var shader_mat: ShaderMaterial = moon_material
			shader_mat.set_shader_parameter("moon_glow_color", glow_color)
			shader_mat.set_shader_parameter("glow_strength", glow_strength)
