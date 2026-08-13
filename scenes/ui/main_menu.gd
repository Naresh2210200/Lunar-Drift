extends Control
## scenes/ui/main_menu.gd — minimal main menu: title, Settings/Shop/Exit
## list buttons, hero Play button bottom-right, version label, high
## score label, and a toast popup for not-yet-built destinations.
##
## Restyled to match hud.gd's white/black paper chrome (see
## main_menu.tscn's StyleBoxFlat set, which now mirrors hud.tscn's) —
## same button/panel look everywhere in the UI, not just in-run.
##
## FadeTransition is optional here (get_node_or_null) since this project
## doesn't currently ship a fade_transition.tscn alongside this menu —
## if you add one later, name the node "FadeTransition" and it'll be
## picked up automatically, no script changes needed.

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const SHOP_SCENE_PATH := "res://scenes/ui/shop.tscn"
const LOADING_SCENE_PATH := "res://scenes/ui/loading_screen.tscn"

@export var reveal_fade_duration: float = 0.6
@export var button_stagger: float = 0.07
@export var button_slide_time: float = 0.35

@onready var _high_score_label: Label = $FooterRight/HighScoreLabel
@onready var _settings_button: Button = $ButtonColumn/SettingsButton
@onready var _shop_button: Button = $ButtonColumn/ShopButton
@onready var _exit_button: Button = $ButtonColumn/ExitButton
@onready var _play_button: Button = $PlayButton
@onready var _toast: Panel = $Toast
@onready var _toast_label: Label = $Toast/ToastLabel
@onready var _settings_backdrop: ColorRect = $SettingsBackdrop
@onready var _settings_panel: Panel = $SettingsPanel
@onready var _sound_toggle_button: Button = $SettingsPanel/Layout/SoundRow/SoundToggleButton
@onready var _fullscreen_toggle_button: Button = $SettingsPanel/Layout/FullscreenRow/FullscreenToggleButton
@onready var _settings_close_button: Button = $SettingsPanel/Layout/CloseButton
@onready var _fade: Node = get_node_or_null("FadeTransition")

var _sound_muted: bool = false
var _fullscreen: bool = false


func _ready() -> void:
	_toast.modulate.a = 0.0
	_toast.visible = false

	_settings_backdrop.visible = false
	_settings_panel.visible = false
	_sound_toggle_button.text = "OFF" if _sound_muted else "ON"
	_fullscreen_toggle_button.text = "ON" if _fullscreen else "OFF"

	_wire_button(_settings_button, _open_settings)
	_wire_button(_settings_close_button, _close_settings)
	_settings_backdrop.gui_input.connect(_on_settings_backdrop_input)
	_wire_button(_sound_toggle_button, _on_sound_toggled)
	_wire_button(_fullscreen_toggle_button, _on_fullscreen_toggled)
	_wire_button(_exit_button, func(): get_tree().quit())
	_wire_button(_shop_button, _on_shop_pressed)
	_wire_button(_play_button, _on_play_pressed)

	_high_score_label.text = "Best: %d m" % HighScoreManager.high_score
	_play_button.grab_focus()

	# Phase 9 audio: opening stinger moved to studio_logo.gd — it should
	# fire once at true app launch, not every time this scene loads
	# (returning from a run via MainMenuButton would have replayed it).
	# Background music keeps looping straight through into gameplay
	# (AudioManager is an autoload, so it survives the scene change to
	# main.tscn on Play).
	AudioManager.play_music()

	_reveal_buttons_staggered()

	if _fade and _fade.has_method("fade_in"):
		await _fade.fade_in(reveal_fade_duration)


# ---------------------------------------------------------------------
# Entrance — ButtonColumn buttons slide in from the left, staggered.
# Animates each button's own `position` (its layout-assigned position is
# captured first, then offset and tweened back). Play gets a simpler
# fade-in since it's a standalone hero element, not part of a list.
# ---------------------------------------------------------------------

func _reveal_buttons_staggered() -> void:
	var left_buttons: Array[Button] = [_settings_button, _shop_button, _exit_button]
	const LEFT_CLOSED_OFFSET := Vector2(-120.0, 0.0)

	# ButtonColumn (VBoxContainer) hasn't run its first sort pass yet at
	# _ready() time, so reading .position here would give every button
	# the same stale pre-layout value — wait a frame so the container
	# has actually placed them before we capture "real" positions.
	await get_tree().process_frame

	# Capture each button's real layout position before displacing it,
	# so the tween can animate back to wherever the VBoxContainer
	# actually placed it rather than a hardcoded value.
	var left_targets: Array[Vector2] = []
	for b in left_buttons:
		left_targets.append(b.position)
		b.position += LEFT_CLOSED_OFFSET

	var tween := create_tween().set_parallel()
	for i in left_buttons.size():
		tween.tween_property(left_buttons[i], ^"position", left_targets[i], button_slide_time) \
			.set_delay(i * button_stagger).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_play_button.modulate.a = 0.0
	tween.tween_property(_play_button, ^"modulate:a", 1.0, button_slide_time).set_delay(button_stagger * 2)
	tween.tween_callback(_start_play_idle_pulse).set_delay(button_slide_time + button_stagger * 2)


# ---------------------------------------------------------------------
# Small polish pass: a slow, subtle breathing pulse on the hero Play
# button once the entrance animation settles, so the most important
# action on screen has a little life without being distracting.
# ---------------------------------------------------------------------

func _start_play_idle_pulse() -> void:
	_play_button.pivot_offset = _play_button.size / 2.0
	var pulse := create_tween().set_loops()
	pulse.tween_property(_play_button, ^"scale", Vector2(1.03, 1.03), 1.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(_play_button, ^"scale", Vector2.ONE, 1.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ---------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------

func _wire_button(button: Button, on_pressed: Callable) -> void:
	button.pressed.connect(func():
		AudioManager.play_sfx("button_press")
		on_pressed.call()
	)


func _show_toast(text: String) -> void:
	_toast_label.text = text
	_toast.visible = true
	var tween := create_tween()
	tween.tween_property(_toast, "modulate:a", 1.0, 0.2)
	tween.tween_interval(1.4)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): _toast.visible = false)


# ---------------------------------------------------------------------
# Settings panel — simple modal: Sound on/off, Fullscreen on/off, Close.
# Backdrop blocks clicks to the menu behind it and closes the panel
# when tapped, same as tapping the Close button.
# ---------------------------------------------------------------------

func _open_settings() -> void:
	_settings_backdrop.visible = true
	_settings_panel.visible = true


func _close_settings() -> void:
	_settings_backdrop.visible = false
	_settings_panel.visible = false


func _on_settings_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_settings()


func _on_sound_toggled() -> void:
	_sound_muted = not _sound_muted
	AudioManager.set_muted(_sound_muted)
	_sound_toggle_button.text = "OFF" if _sound_muted else "ON"


func _on_fullscreen_toggled() -> void:
	_fullscreen = not _fullscreen
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if _fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	_fullscreen_toggle_button.text = "ON" if _fullscreen else "OFF"


# ---------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------

## Quick fade-out (not an instant cut) on the menu's background music the
## moment Play is pressed — jet_starting/jet_flying take over once
## player.gd's _ready() runs in main.tscn, so the two never overlap.
const MUSIC_FADE_OUT_ON_PLAY: float = 0.3

func _on_play_pressed() -> void:
	AudioManager.stop_music(MUSIC_FADE_OUT_ON_PLAY)
	_go_to_loading_screen(MAIN_SCENE_PATH)


## change_scene_to_file() can't take constructor args, and loading_screen.gd
## needs target_scene_path set before its _ready() runs — so instantiate it
## by hand, hand it the path, then swap it in as the current scene
## ourselves instead of letting change_scene_to_file() do it blind.
func _go_to_loading_screen(target_path: String) -> void:
	var loading_scene: PackedScene = load(LOADING_SCENE_PATH)
	var loading_instance: Control = loading_scene.instantiate()
	loading_instance.target_scene_path = target_path
	get_tree().root.add_child(loading_instance)
	get_tree().current_scene.queue_free()
	get_tree().current_scene = loading_instance


## Shop keeps the menu's music playing (unlike Play) since it's not
## gameplay — same reasoning as returning from a run via MainMenuButton.
func _on_shop_pressed() -> void:
	get_tree().change_scene_to_file(SHOP_SCENE_PATH)
