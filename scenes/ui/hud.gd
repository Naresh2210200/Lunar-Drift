extends CanvasLayer
## scenes/ui/hud.gd — Phase 10 Paper UI.
##
## Deliberately a pure LISTENER for the gameplay-readout half of this
## script (multiplier meter, score, cooldown meters), same one-way-
## dependency shape as the rest of this project: reaches into
## Player/MoonEnergy's `multiplier_meter_changed`/`multiplier_changed` and
## Player's `score_changed` — nothing on the gameplay side needs to know
## this node exists. Two deliberate exceptions to "pure listener":
##   - IntroSequence calls show_prep_message()/hide_prep_message()
##     directly, since "Good Luck"'s timing belongs to the intro sequence,
##     not a GameState transition (there's no GameState for "about to
##     start"). DeathSequence calls show_continue_prompt() the same way,
##     once its camera turn-around around the wreck has played out — see
##     scenes/main/death_sequence.gd. Neither of those is a state-change
##     listener anymore; this node no longer connects to
##     GameManager.state_changed at all.
##   - This node also OWNS the pause toggle (reads the "pause" input
##     action itself) and the restart/main-menu scene changes — those are
##     genuine UI-initiated actions, not readouts, so they don't fit the
##     listener framing and don't need to.
##
## This node's process_mode is Always (see hud.tscn) specifically so it
## keeps reading input and updating the pause panel while
## get_tree().paused is true — every other node in the project stays at
## the default Inherit/Pausable, so setting get_tree().paused = true from
## here is enough to freeze the entire gameplay simulation (Player,
## CameraRig, ProceduralWorld, etc.) with no per-script pause checks
## needed anywhere else.
##
## Multiplier meter/cooldown bars are plain ColorRects resized against a
## cached full-width, not themed ProgressBars — one less theme resource to
## keep in the paper style, and resizing a rect reads the intent just as
## clearly as a themed bar would.
##
## PC-first per explicit request: pause is keyboard-driven ("pause"
## input action, e.g. Esc) with no on-screen pause button — a touch pass
## later would add one without needing to change any of the logic here,
## since _toggle_pause() doesn't care what triggered it.

@export var player_path: NodePath
@export var moon_energy_node_name: String = "MoonEnergy"

@onready var _multiplier_fill: ColorRect = $EnergyBarBg/EnergyBarFill
@onready var _score_label: Label = $ScoreLabel
@onready var _shard_label: Label = $ShardLabel
@onready var _good_luck_label: Label = $GoodLuckLabel
@onready var _game_over_panel: Panel = $GameOverPanel
@onready var _final_score_label: Label = $GameOverPanel/FinalScoreLabel
@onready var _new_best_label: Label = $GameOverPanel/NewBestLabel
@onready var _restart_button: Button = $GameOverPanel/RestartButton
@onready var _game_over_main_menu_button: Button = $GameOverPanel/MainMenuButton
@onready var _boost_fill: ColorRect = $BoostMeterBg/BoostMeterFill
@onready var _jump_fill: ColorRect = $JumpMeterBg/JumpMeterFill
@onready var _pause_panel: Panel = $PausePanel
@onready var _resume_button: Button = $PausePanel/ResumeButton
@onready var _pause_main_menu_button: Button = $PausePanel/MainMenuButton
@onready var _continue_prompt: Control = $ContinuePrompt

var _multiplier_bar_full_width: float = 0.0
var _boost_meter_full_width: float = 0.0
var _jump_meter_full_width: float = 0.0
var _current_score: int = 0
var _current_multiplier: int = 1
var _player: Node = null


func _ready() -> void:
	# Cache the fill's designed width BEFORE anything resizes it, so every
	# later resize is a fraction of the original full bar, not of
	# whatever it happened to shrink to last frame.
	_multiplier_bar_full_width = _multiplier_fill.size.x
	_boost_meter_full_width = _boost_fill.size.x
	_jump_meter_full_width = _jump_fill.size.x

	_good_luck_label.modulate.a = 0.0
	_game_over_panel.visible = false
	_game_over_panel.modulate.a = 0.0
	_new_best_label.visible = false
	_pause_panel.visible = false

	# button_press SFX fires from here rather than inside each
	# _on_*_pressed handler, so every HUD button gets it uniformly —
	# mirrors main_menu.gd's _wire_button() pattern without needing to
	# duplicate that helper into this script.
	_restart_button.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	_resume_button.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	_pause_main_menu_button.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	_game_over_main_menu_button.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	_restart_button.pressed.connect(_on_restart_pressed)
	_resume_button.pressed.connect(_on_resume_pressed)
	_pause_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_game_over_main_menu_button.pressed.connect(_on_main_menu_pressed)
	# GAME_OVER used to open ContinuePrompt directly from here, the same
	# frame the state changed. It's now opened by DeathSequence
	# (scenes/main/death_sequence.gd) instead, once its camera turn-around
	# around the wreck has actually played out — see show_continue_prompt()
	# below — so death doesn't cut straight from "still flying" to "here's
	# a prompt" with no beat in between.
	# The Run Complete panel still only appears if that prompt is actually
	# declined (skipped, timed out, or the player couldn't afford it), not
	# on every death.
	_continue_prompt.declined.connect(_show_game_over)

	# Currency label relabeled Shards -> Shades per the multiplier/currency
	# rework — still reading EconomyManager.shards itself unchanged, since
	# that's the same persistent pool, just renamed in the UI.
	_shard_label.text = "%d Shades" % EconomyManager.shards
	EconomyManager.shards_changed.connect(_on_shards_changed)

	_player = get_node_or_null(player_path)
	if _player == null:
		push_warning("hud.gd: player_path did not resolve — multiplier/score/cooldown readouts will stay static.")
		return

	if _player.has_node(moon_energy_node_name):
		var moon_energy: Node = _player.get_node(moon_energy_node_name)
		moon_energy.multiplier_meter_changed.connect(_on_multiplier_meter_changed)
		moon_energy.multiplier_changed.connect(_on_multiplier_changed)
	else:
		push_warning("hud.gd: '%s' not found under player_path — multiplier meter will stay static." % moon_energy_node_name)

	if _player.has_signal("score_changed"):
		_player.score_changed.connect(_on_score_changed)


## Cooldown meters are polled here rather than driven by a signal from
## Player — there's no natural "changed" event for a continuously
## counting-down timer the way there is for the multiplier meter or score, and a
## per-frame signal would be no cheaper than just reading the getter
## directly. Also owns the pause toggle: this whole node's process_mode is
## set to Always in the .tscn specifically so this keeps running (and
## Input still reaches it) while get_tree().paused is true — see
## _toggle_pause below.
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		_toggle_pause()

	if _player == null:
		return
	if _player.has_method("get_boost_ready_ratio"):
		_boost_fill.size.x = _boost_meter_full_width * _player.get_boost_ready_ratio()
	if _player.has_method("get_jump_ready_ratio"):
		_jump_fill.size.x = _jump_meter_full_width * _player.get_jump_ready_ratio()


func _on_multiplier_meter_changed(current: float, max_value: float) -> void:
	var ratio: float = clamp(current / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0
	_multiplier_fill.size.x = _multiplier_bar_full_width * ratio


func _on_multiplier_changed(new_multiplier: int) -> void:
	_current_multiplier = new_multiplier
	_update_score_label()


func _on_score_changed(score: int) -> void:
	_current_score = score
	_update_score_label()
	# ThemeManager no-ops unless this crosses a fresh 50000-point tier —
	# see its report_score() header for why the raw score is passed
	# straight through rather than HUD pre-computing a tier itself.
	if has_node("/root/ThemeManager"):
		get_node("/root/ThemeManager").report_score(score)


## Reused for both a score change and a multiplier-tier change, since the
## displayed text depends on both — appends the tier ("x2", "x3"...) onto
## the same score label rather than adding a new Control node for it, per
## "keep the existing UI... relabel and repurpose where possible."
func _update_score_label() -> void:
	if _current_multiplier > 1:
		_score_label.text = "%d   x%d" % [_current_score, _current_multiplier]
	else:
		_score_label.text = str(_current_score)


func _on_shards_changed(new_total: int) -> void:
	_shard_label.text = "%d Shards" % new_total


## Called by IntroSequence at the start of its prep_duration window.
func show_prep_message() -> void:
	_good_luck_label.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_good_luck_label, "modulate:a", 1.0, 0.3)


## Called by IntroSequence right before it hands off to gameplay.
func hide_prep_message() -> void:
	var tween := create_tween()
	tween.tween_property(_good_luck_label, "modulate:a", 0.0, 0.3)


## Only toggles during PLAYING/PAUSED — pressing pause during the intro's
## approach shot or from the Game Over screen shouldn't do anything, both
## because get_tree().paused mid-intro would fight IntroSequence's own
## tweens/awaits, and because pausing a run that's already over is
## meaningless.
func _toggle_pause() -> void:
	if GameManager.current_state == GameManager.GameState.PLAYING:
		GameManager.change_state(GameManager.GameState.PAUSED)
		get_tree().paused = true
		_pause_panel.visible = true
	elif GameManager.current_state == GameManager.GameState.PAUSED:
		_resume()


func _resume() -> void:
	get_tree().paused = false
	_pause_panel.visible = false
	GameManager.change_state(GameManager.GameState.PLAYING)


func _on_resume_pressed() -> void:
	_resume()


## Shared by both PausePanel's and GameOverPanel's "Main Menu" buttons —
## the destination and required cleanup (unpause first, reset state) are
## identical either way. get_tree().paused is unconditionally cleared
## even though GAME_OVER never actually paused the tree — harmless if
## already false, and it means this function stays correct if that ever
## changes rather than assuming which panel called it.
func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	GameManager.change_state(GameManager.GameState.MENU)
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


## Called by DeathSequence (scenes/main/death_sequence.gd) once its camera
## turn-around around the wreck has finished — this is what actually
## reveals ContinuePrompt now, not a direct reaction to GAME_OVER firing.
## continue_prompt.gd's own open() handles its fade/scale-in itself.
func show_continue_prompt() -> void:
	_continue_prompt.open()


func _show_game_over() -> void:
	_final_score_label.text = "Score: %d" % _current_score
	var is_new_best: bool = HighScoreManager.report_score(_current_score)
	_new_best_label.visible = is_new_best
	_game_over_panel.visible = true
	var tween := create_tween()
	tween.tween_property(_game_over_panel, "modulate:a", 1.0, 0.4)

	# Once per COMPLETED run, not once per death — this only fires here,
	# not from continue_prompt.gd, so a player who keeps paying Shades
	# (or uses their one free ad-continue) to keep a run alive isn't
	# interrupted by an interstitial between lives. AdManager itself
	# no-ops harmlessly if nothing's loaded/wired up.
	_show_interstitial_ad()


func _show_interstitial_ad() -> void:
	if has_node("/root/AdManager"):
		var ad_manager: Node = get_node("/root/AdManager")
		if ad_manager.has_method("show_interstitial_ad"):
			ad_manager.show_interstitial_ad()


func _on_restart_pressed() -> void:
	# GameManager is an autoload — it survives reload_current_scene()
	# untouched, so current_state would still read GAME_OVER the instant
	# the reloaded IntroSequence's _ready() runs otherwise. Reset it to
	# MENU first (IntroSequence expects to start from MENU and flips to
	# PLAYING itself once its reveal finishes) so the reloaded scene
	# starts from a genuinely clean state, not a stale GAME_OVER.
	GameManager.change_state(GameManager.GameState.MENU)
	# Same "autoload survives reload_current_scene()" reasoning applies to
	# ThemeManager — without this, a run that ended mid-Lava would reload
	# straight back into the Lava palette instead of a fresh Sketch start.
	if has_node("/root/ThemeManager"):
		get_node("/root/ThemeManager").reset()
	get_tree().reload_current_scene()
