extends Node
## MobileControls (autoload)
##
## Register this as an Autoload (Project Settings -> Autoload) named
## "MobileControls" pointing at this script, ordered BEFORE
## MobileControlsLoader in the autoload list — MobileControlsLoader
## instantiates mobile_controls.tscn in its own _ready(), and
## mobile_input_controller.gd (that scene's input owner) reads saved
## layout values from here the moment it wakes up, so this singleton's
## data needs to already be loaded from disk by then.
##
## Deliberately split from MobileControlsLoader: that autoload's one job
## is instancing mobile_controls.tscn once per app run and living for as
## long as the app runs (see its own header comment). This singleton's
## job is different and longer-lived than any one scene instance — it
## owns the *saved customization data* (per-button position offset,
## scale, opacity) and the *customize_mode* flag, both of which need to
## be reachable from the Settings menu whether or not a run is in
## progress, and whether or not GameManager is even in PLAYING.
##
## Nothing here touches a Control node directly. mobile_input_controller.gd
## listens to `layout_changed` and applies these values to the actual
## JumpButton/BoostButton/PauseButton nodes itself — this keeps "the
## data" and "the nodes" cleanly separated, same reasoning GameManager's
## own header gives for staying state-only.

## The three round buttons in mobile_controls.tscn that customization
## covers. LeftTouchZone/RightTouchZone (steering) are deliberately left
## out — they're full-screen swipe zones, not discrete buttons with a
## position/size that "dragging" makes sense for.
const BUTTON_IDS: Array[StringName] = [&"jump", &"boost", &"pause"]

const DEFAULT_SCALE: float = 1.0
## Matches each button's authored `idle_alpha` in mobile_controls.tscn —
## PauseButton sits dimmed in the corner by design, Jump/Boost are opaque.
const DEFAULT_OPACITY: Dictionary = {&"jump": 1.0, &"boost": 1.0, &"pause": 0.4}

const MIN_SCALE: float = 0.7
const MAX_SCALE: float = 1.6
const MIN_OPACITY: float = 0.15
const MAX_OPACITY: float = 1.0

const SAVE_PATH := "user://mobile_controls_layout.cfg"

## Emitted whenever a button's saved position/scale/opacity changes —
## both live during customization (so the real button node updates in
## real time as the player drags/adjusts sliders) and once per button
## right after customize mode exits (so a discarded drag snaps back).
signal layout_changed(button_id: StringName)

## Emitted exactly once each way. mobile_input_controller.gd listens to
## this instead of polling GameManager or customize_mode every frame —
## it's the one signal that tells it "stop reading gameplay touches" /
## "resume reading gameplay touches".
signal customize_mode_changed(active: bool)

var customize_mode: bool = false

var _offset_delta: Dictionary = {}  # StringName -> Vector2
var _scale: Dictionary = {}         # StringName -> float
var _opacity: Dictionary = {}       # StringName -> float


func _ready() -> void:
	_reset_in_memory_to_defaults()
	_load()


# ---------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------

func get_offset_delta(button_id: StringName) -> Vector2:
	return _offset_delta.get(button_id, Vector2.ZERO)


func get_scale(button_id: StringName) -> float:
	return _scale.get(button_id, DEFAULT_SCALE)


func get_opacity(button_id: StringName) -> float:
	return _opacity.get(button_id, DEFAULT_OPACITY.get(button_id, 1.0))


# ---------------------------------------------------------------------
# Writes — called by the Customize Controls screen while dragging/
# adjusting sliders. Each one updates the in-memory value and fires
# layout_changed immediately for live preview; nothing is written to
# disk until exit_customize_mode(true) (Save/Done) actually saves.
# ---------------------------------------------------------------------

func set_offset_delta(button_id: StringName, value: Vector2) -> void:
	_offset_delta[button_id] = value
	layout_changed.emit(button_id)


func set_scale(button_id: StringName, value: float) -> void:
	_scale[button_id] = clampf(value, MIN_SCALE, MAX_SCALE)
	layout_changed.emit(button_id)


func set_opacity(button_id: StringName, value: float) -> void:
	_opacity[button_id] = clampf(value, MIN_OPACITY, MAX_OPACITY)
	layout_changed.emit(button_id)


func reset_button(button_id: StringName) -> void:
	_offset_delta[button_id] = Vector2.ZERO
	_scale[button_id] = DEFAULT_SCALE
	_opacity[button_id] = DEFAULT_OPACITY.get(button_id, 1.0)
	layout_changed.emit(button_id)


# ---------------------------------------------------------------------
# Customize mode — the single source of truth mobile_input_controller.gd
# and the Customize Controls screen both read/react to. Entering never
# depends on GameManager.current_state, so it can be opened straight
# from the Settings menu without a run in progress.
# ---------------------------------------------------------------------

func enter_customize_mode() -> void:
	if customize_mode:
		return
	customize_mode = true
	customize_mode_changed.emit(true)


## save=true (Save/Done/Back per spec — all three exit paths persist):
## writes current in-memory values to disk. save=false: reloads
## last-saved values from disk, discarding any drags made this session,
## then tells every button to re-apply (snapping back visually).
func exit_customize_mode(save: bool = true) -> void:
	if not customize_mode:
		return
	if save:
		_save()
	else:
		_load()
	customize_mode = false
	customize_mode_changed.emit(false)
	for button_id in BUTTON_IDS:
		layout_changed.emit(button_id)


# ---------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------

func _reset_in_memory_to_defaults() -> void:
	for button_id in BUTTON_IDS:
		_offset_delta[button_id] = Vector2.ZERO
		_scale[button_id] = DEFAULT_SCALE
		_opacity[button_id] = DEFAULT_OPACITY.get(button_id, 1.0)


func _save() -> void:
	var cfg := ConfigFile.new()
	for button_id in BUTTON_IDS:
		var section: String = String(button_id)
		cfg.set_value(section, "offset_delta", _offset_delta[button_id])
		cfg.set_value(section, "scale", _scale[button_id])
		cfg.set_value(section, "opacity", _opacity[button_id])
	var err: Error = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("MobileControls: couldn't save layout (error %d) — changes won't persist." % err)


func _load() -> void:
	_reset_in_memory_to_defaults()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		push_warning("MobileControls: save file exists but couldn't be parsed — using defaults.")
		return
	for button_id in BUTTON_IDS:
		var section: String = String(button_id)
		if not cfg.has_section(section):
			continue
		_offset_delta[button_id] = cfg.get_value(section, "offset_delta", Vector2.ZERO)
		_scale[button_id] = cfg.get_value(section, "scale", DEFAULT_SCALE)
		_opacity[button_id] = cfg.get_value(section, "opacity", DEFAULT_OPACITY.get(button_id, 1.0))
