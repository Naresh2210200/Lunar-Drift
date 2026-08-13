class_name FadeTransition
extends CanvasLayer
## scenes/transitions/fade_transition.gd — reusable fade-to/from-black component.
##
## Instanced as a CHILD of any screen that needs a fade (LoadingScreen,
## StudioLogo, and later the Main Menu itself if a fade-in-on-appear is
## wanted). Deliberately NOT an autoload/singleton — a fade is a per-scene
## visual effect, not global game state, so it follows this project's
## "avoid unnecessary singleton usage" rule the same way CameraRig/HUD do:
## reusable through scene instancing, not a global manager.
##
## CanvasLayer with a high `layer` value so the overlay always draws above
## everything else in whatever scene it's instanced into, regardless of
## that scene's own node order.

@onready var _overlay: ColorRect = $Overlay


func _ready() -> void:
	layer = 100
	_overlay.color = Color.BLACK
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.modulate.a = 0.0


## Starts fully opaque black and fades to transparent, revealing the scene
## underneath. Await this to know when the reveal has finished.
func fade_in(duration: float = 1.0) -> void:
	_overlay.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 0.0, duration)
	await tween.finished


## Starts transparent and fades to opaque black, hiding the scene. Await
## this before switching scenes so the cut happens while the screen is
## fully black instead of on a visible frame.
func fade_out(duration: float = 1.0) -> void:
	_overlay.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 1.0, duration)
	await tween.finished
