extends Node
## Attach this as a child of whichever node holds the ocean's
## ShaderMaterial (water.gdshader) — likely right alongside
## ocean_activity.gd/ocean_follow.gd — and assign `water_material` in the
## Inspector to that same ShaderMaterial resource.
##
## Purely reactive and narrow on purpose, same shape as every other
## ThemeManager listener in this project: it only ever pushes
## WATER_COL/WATER2_COL/FOAM_COL (plus the water shader's own stylized
## moon-glint moon_glow_color/glow_strength uniforms) on a theme change.
## It does NOT touch `activity` or `anim_time` — those stay exactly
## whatever ocean_activity.gd is already driving every frame, so this
## can't fight that script or need to know anything about it.
##
## If you'd rather not add a whole extra node just for this, these same
## lines can be pasted straight into ocean_activity.gd's _ready()/a
## theme_changed handler instead — send me that script and I'll fold it
## in directly.

@export var water_material: ShaderMaterial


func _ready() -> void:
	if not has_node("/root/ThemeManager"):
		push_warning("water_theme_listener.gd: ThemeManager autoload not found — water color will stay at its default.")
		return
	var theme_manager: Node = get_node("/root/ThemeManager")
	theme_manager.theme_changed.connect(_on_theme_changed)
	_on_theme_changed(theme_manager.current_theme_id, theme_manager.get_current_theme())


func _on_theme_changed(_theme_id: int, theme: Dictionary) -> void:
	if water_material == null:
		push_warning("water_theme_listener.gd: water_material not assigned in the Inspector — nothing to retint.")
		return
	water_material.set_shader_parameter("WATER_COL", theme["water_col"])
	water_material.set_shader_parameter("WATER2_COL", theme["water2_col"])
	water_material.set_shader_parameter("FOAM_COL", theme["foam_col"])
	# The water shader's own stylized moon-glint reflection — separate
	# from the actual moon mesh/light that moon_theme_listener.gd handles,
	# but reads better matched to the same theme (a cool white-blue glint
	# in Water, a hot orange-yellow glint in Lava) rather than staying a
	# fixed cool-white glint against a molten-orange surface.
	water_material.set_shader_parameter("moon_glow_color", theme.get("moon_glow_color", Color.WHITE))
	water_material.set_shader_parameter("glow_strength", theme.get("moon_glow_strength", 0.8))
