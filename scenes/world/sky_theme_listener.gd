extends Node
## Attach this anywhere that can reach the scene's WorldEnvironment (a
## child of it works fine) and assign `environment` in the Inspector to
## that WorldEnvironment node's `environment` resource.
##
## Written against a flat Environment.background_color, since the actual
## WorldEnvironment/sky setup isn't available to build this against
## directly — if the project uses a ProceduralSkyMaterial instead of a
## flat background color, swap the background_color line below for:
##   environment.sky.sky_material.set("sky_top_color", theme["background_color"])
##   environment.sky.sky_material.set("sky_horizon_color", theme["fog_color"])
## Send me the WorldEnvironment scene/script and I'll wire this exactly
## instead of leaving that swap to you.

@export var environment: Environment


func _ready() -> void:
	if not has_node("/root/ThemeManager"):
		push_warning("sky_theme_listener.gd: ThemeManager autoload not found — sky color will stay at its default.")
		return
	var theme_manager: Node = get_node("/root/ThemeManager")
	theme_manager.theme_changed.connect(_on_theme_changed)
	_on_theme_changed(theme_manager.current_theme_id, theme_manager.get_current_theme())


func _on_theme_changed(_theme_id: int, theme: Dictionary) -> void:
	if environment == null:
		push_warning("sky_theme_listener.gd: environment not assigned in the Inspector — nothing to retint.")
		return
	environment.background_color = theme["background_color"]
	environment.ambient_light_color = theme["ambient_color"]
	if environment.fog_enabled:
		environment.fog_light_color = theme["fog_color"]
