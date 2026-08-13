extends Control
## scenes/startup/studio_logo.gd — Screen 2 of the startup sequence.
##
## 21st Century Studio logo: fade in, scale up with a soft glow, hold,
## fade to black, then hand off to LoadingScreen, which threaded-loads
## Main Menu and swaps to it once ready (scenes/ui/loading_screen.gd).
## Studio Logo no longer background-loads Main Menu itself — Main Menu
## can carry real weight (shop data, high scores, etc.) so it gets the
## same threaded-load + progress-bar treatment as Main Menu -> gameplay,
## instead of a silent background load with no feedback if it runs long.

const MAIN_MENU_SCENE_PATH := "res://scenes/ui/main_menu.tscn"
const LOADING_SCENE_PATH := "res://scenes/ui/loading_screen.tscn"

@export var reveal_fade_duration: float = 0.6
@export var scale_up_duration: float = 1.0
@export var hold_duration: float = 2.0
@export var fade_out_duration: float = 1.0
@export var logo_starting_scale: float = 0.85

@onready var _logo_label: Label = $LogoLabel
@onready var _glow: TextureRect = $Glow
@onready var _ambient_sound: AudioStreamPlayer = $AmbientSound
@onready var _fade: FadeTransition = $FadeTransition


func _ready() -> void:
	_glow.texture = GlowTexture.build_radial(384, Color.WHITE, 0.5)

	_logo_label.modulate.a = 0.0
	_glow.modulate.a = 0.0
	# Scale from the label's own center, not the Control's top-left corner
	# — pivot_offset has to be set AFTER the label has a real size, which
	# is only true once it's actually in the tree (here, not in _init()).
	_logo_label.pivot_offset = _logo_label.size / 2.0
	_logo_label.scale = Vector2.ONE * logo_starting_scale

	if _ambient_sound.stream != null:
		_ambient_sound.play()

	# Phase 9 audio: the opening stinger belongs here, not main_menu.gd —
	# this screen only ever plays once per real app launch (loading_screen
	# -> studio_logo -> main_menu), whereas main_menu.gd reloads every
	# time the player backs out of a run, which would have replayed it.
	AudioManager.play_opening()

	await _fade.fade_in(reveal_fade_duration)
	await _play_logo_animation()
	await get_tree().create_timer(hold_duration).timeout
	await _transition_to_main_menu()


func _play_logo_animation() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_logo_label, "modulate:a", 1.0, reveal_fade_duration)
	tween.tween_property(_glow, "modulate:a", 1.0, reveal_fade_duration)
	tween.tween_property(_logo_label, "scale", Vector2.ONE, scale_up_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished


func _transition_to_main_menu() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_logo_label, "modulate:a", 0.0, fade_out_duration)
	tween.tween_property(_glow, "modulate:a", 0.0, fade_out_duration)
	# Ambient sound fades out alongside the visuals instead of just getting
	# cut off whenever this scene happens to get freed — otherwise it can
	# still be audible during the black-screen hold below and bleed into
	# main_menu.gd's own AudioManager.play_music() call.
	if _ambient_sound.playing:
		tween.tween_property(_ambient_sound, "volume_db", -80.0, fade_out_duration)
	await tween.finished
	_ambient_sound.stop()

	await _fade.fade_out(fade_out_duration)

	_go_to_loading_screen(MAIN_MENU_SCENE_PATH)


## Same hand-off pattern as main_menu.gd's _go_to_loading_screen: instantiate
## loading_screen.tscn by hand (change_scene_to_file() can't take constructor
## args), set target_scene_path before it enters the tree so its _ready()
## picks it up, then swap it in as the current scene ourselves.
func _go_to_loading_screen(target_path: String) -> void:
	var loading_scene: PackedScene = load(LOADING_SCENE_PATH)
	var loading_instance: Control = loading_scene.instantiate()
	loading_instance.target_scene_path = target_path
	get_tree().root.add_child(loading_instance)
	get_tree().current_scene.queue_free()
	get_tree().current_scene = loading_instance
