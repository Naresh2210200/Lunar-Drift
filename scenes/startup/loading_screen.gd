extends Control
## scenes/startup/loading_screen.gd — Screen 1 of the startup sequence.
##
## Shows the "Lunar Drift" title on a black background while StudioLogo.tscn
## loads in the background (ResourceLoader threaded load, not a blocking
## `load()`), then fades out and hands off to it. No input is read anywhere
## in this script — the whole startup sequence runs with zero required
## interaction, per the brief.

const STUDIO_LOGO_SCENE_PATH := "res://scenes/startup/studio_logo.tscn"

@export var minimum_display_duration: float = 2.5
@export var title_fade_in_duration: float = 1.0
@export var title_fade_out_duration: float = 0.6
@export var reveal_fade_duration: float = 0.4

@onready var _title_label: Label = $TitleLabel
@onready var _moon_glow: TextureRect = $MoonGlow
@onready var _loading_label: Label = $LoadingLabel
@onready var _ambient_sound: AudioStreamPlayer = $AmbientSound
@onready var _fade: FadeTransition = $FadeTransition

var _dot_count: int = 0
var _dot_timer: float = 0.0
var _elapsed: float = 0.0
var _studio_logo_ready: bool = false
var _finishing: bool = false


func _ready() -> void:
	_moon_glow.texture = GlowTexture.build_radial(512, Color.WHITE, 0.45)
	_title_label.modulate.a = 0.0
	_moon_glow.modulate.a = 0.0
	_loading_label.text = "Loading"

	# Play immediately, same spot studio_logo.gd starts its own sound —
	# don't wait on the fade-in await below, so audio and the very first
	# visible frame land together instead of sound lagging behind it.
	if _ambient_sound.stream != null:
		_ambient_sound.play()

	# Reveal the (still-invisible) screen from black first, then fade the
	# title itself in — two separate fades so the black->scene cut from a
	# PREVIOUS screen (none exists before this one, but the pattern is
	# reused by StudioLogo) never fights the title's own entrance.
	await _fade.fade_in(reveal_fade_duration)
	_fade_in_title()

	# Kick off the background load immediately so the ~2.5s the title
	# spends on screen is loading time, not dead time in front of it.
	ResourceLoader.load_threaded_request(STUDIO_LOGO_SCENE_PATH)


func _process(delta: float) -> void:
	_elapsed += delta
	_update_loading_dots(delta)

	if not _studio_logo_ready:
		var status := ResourceLoader.load_threaded_get_status(STUDIO_LOGO_SCENE_PATH)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_studio_logo_ready = true

	# Gate on BOTH conditions: never leave before the minimum duration
	# (the title needs a moment to actually be read), and never leave
	# before the next scene is actually ready (that's what avoids the
	# loading stutter the brief calls out).
	if _studio_logo_ready and _elapsed >= minimum_display_duration and not _finishing:
		_finishing = true
		_finish()


func _fade_in_title() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_title_label, "modulate:a", 1.0, title_fade_in_duration)
	tween.tween_property(_moon_glow, "modulate:a", 1.0, title_fade_in_duration)


func _update_loading_dots(delta: float) -> void:
	_dot_timer += delta
	if _dot_timer >= 0.4:
		_dot_timer = 0.0
		_dot_count = (_dot_count + 1) % 4
		_loading_label.text = "Loading" + ".".repeat(_dot_count)


func _finish() -> void:
	set_process(false)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(_title_label, "modulate:a", 0.0, title_fade_out_duration)
	tween.tween_property(_moon_glow, "modulate:a", 0.0, title_fade_out_duration)
	tween.tween_property(_loading_label, "modulate:a", 0.0, title_fade_out_duration)
	await tween.finished

	await _fade.fade_out(title_fade_out_duration)

	# Already confirmed THREAD_LOAD_LOADED in _process, so this returns
	# instantly — no second wait, no stutter.
	var studio_logo_scene: PackedScene = ResourceLoader.load_threaded_get(STUDIO_LOGO_SCENE_PATH)

	# Manual instantiate-then-free swap instead of change_scene_to_packed()
	# — same fix as ui/loading_screen.gd's _swap_to_target() and same
	# reason: change_scene_to_packed() frees the current scene FIRST and
	# only adds the new one on a deferred call afterward, so for that gap
	# there's no current_scene in the tree at all and the viewport shows
	# raw clear color instead of either screen. Adding StudioLogo before
	# freeing this screen means there's never a frame with nothing in it.
	var studio_logo_instance: Node = studio_logo_scene.instantiate()
	get_tree().root.add_child(studio_logo_instance)
	get_tree().current_scene = studio_logo_instance
	queue_free()
