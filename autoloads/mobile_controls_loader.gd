extends Node
## scripts/autoload/mobile_controls_loader.gd
##
## Registered as an autoload (see project.godot) so it runs before any
## scene loads, decides ONCE whether this is a touch platform, and if so
## adds mobile_controls.tscn directly under the tree root — completely
## independent of whichever gameplay/menu scene happens to be active, so
## main.tscn, player.gd, and hud.tscn need zero changes and zero
## awareness this exists. Desktop builds are entirely untouched: this
## autoload no-ops immediately on non-touch platforms.
##
## Also fixes a latent cross-platform trap in the existing input map:
## the "jump" action's desktop binding includes a left mouse click (see
## project.godot's jump action) for dev convenience. Godot's default
## "Emulate Mouse From Touch" means every real touch on a touch device
## ALSO fires a synthetic mouse click — which, left alone, would trigger
## "jump" directly through the InputMap on every single touch (steering,
## boost, anywhere on screen), completely bypassing MobileControls' own
## cooldown and tap handling. Stripping just the mouse-button event from
## "jump" (its keyboard bindings are untouched, and don't apply on
## mobile anyway) fixes this while leaving mouse-from-touch emulation
## itself ON, since the HUD's Pause/Resume/Restart/Main-Menu Buttons
## still rely on that emulation to work under touch.

var mobile_controls: CanvasLayer = null


func _ready() -> void:
	if not _is_touch_platform():
		return

	_strip_mouse_binding_from_jump_action()

	var packed: PackedScene = load("res://scenes/ui/mobile/mobile_controls.tscn")
	mobile_controls = packed.instantiate()
	get_tree().root.add_child.call_deferred(mobile_controls)


func _is_touch_platform() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]


func _strip_mouse_binding_from_jump_action() -> void:
	if not InputMap.has_action("jump"):
		return
	for event in InputMap.action_get_events("jump"):
		if event is InputEventMouseButton:
			InputMap.action_erase_event("jump", event)
