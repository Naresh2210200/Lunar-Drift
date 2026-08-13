extends Node
## Autoload: "AudioManager". Phase 9 audio hub — every other script talks to
## THIS, never to raw AudioStreamPlayer nodes directly, so mute/volume/bus
## logic lives in exactly one place.
##
## Deliberately does NOT touch the .tscn scenes at all — every player node
## here is created at runtime in _ready(). That keeps audio wiring a
## pure-code addition on top of the existing scenes (player.tscn,
## main_menu.tscn) instead of another hand-edited node tree to keep in sync.
##
## Register this as an Autoload (Project Settings -> Autoload) named
## "AudioManager" pointing at this script. Order relative to other
## autoloads (GameManager, EconomyManager, HighScoreManager) doesn't matter —
## this script has no dependency on them.

## Update these to match your actual filenames/extensions exactly (spaces in
## filenames are fine in Godot, just keep the path a byte-for-byte match).
const MUSIC_PATH := "res://assets/audio/background_music.mp3"
const OPENING_PATH := "res://assets/audio/opening_sound.mp3"
const ENGINE_START_PATH := "res://assets/audio/jet_starting.mp3"
const ENGINE_LOOP_PATH := "res://assets/audio/jet_flying.mp3"

const SFX := {
	"boost": "res://assets/audio/boost.mp3",
	"button_press": "res://assets/audio/button_press.mp3",
	"collection": "res://assets/audio/collection_sound.mp3",
	"explosion": "res://assets/audio/explosion.mp3",
}

## How many overlapping one-shot SFX (button taps, boosts, pickups landing
## in the same frame) the pool can play at once before it starts stealing
## the oldest voice. 8 is plenty for this game's SFX density.
const SFX_POOL_SIZE := 8

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

@onready var _music_player: AudioStreamPlayer = _make_player(MUSIC_BUS)
@onready var _opening_player: AudioStreamPlayer = _make_player(SFX_BUS)
@onready var _engine_oneshot_player: AudioStreamPlayer = _make_player(SFX_BUS)
@onready var _engine_loop_player: AudioStreamPlayer = _make_player(SFX_BUS)

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_next: int = 0

## Cache of loaded streams so repeated play_sfx() calls don't hit the
## resource loader every time. Missing files load as null and are skipped
## with a warning (once) rather than erroring — lets the rest of the game
## run fine before every asset is dropped in.
var _stream_cache: Dictionary = {}
var _missing_warned: Dictionary = {}

var _muted: bool = false
var _engine_active: bool = false

## True once the menu->gameplay music handoff has happened for real (Play
## button pressed at least once this app session). Lets main.gd tell
## "genuine first boot / F6 skip-menu testing" apart from "reloaded via
## HUD restart after a run" — is_music_playing() alone can't do that,
## since it's also false in the restart case (music was already faded
## out on the original Play press).
var _left_menu: bool = false


func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)

	for i in SFX_POOL_SIZE:
		_sfx_pool.append(_make_player(SFX_BUS))


# ---------------------------------------------------------------------
# Bus / player setup
# ---------------------------------------------------------------------

## Creates the bus routed to Master if it doesn't already exist (checked by
## name so re-running this in the editor across scene reloads is harmless).
func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func _make_player(bus_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus_name
	add_child(p)
	return p


func _load_stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path]

	if not ResourceLoader.exists(path):
		if not _missing_warned.has(path):
			_missing_warned[path] = true
			push_warning("AudioManager: missing audio file at %s" % path)
		return null

	var stream: AudioStream = load(path)
	_stream_cache[path] = stream
	return stream


func _next_pool_player() -> AudioStreamPlayer:
	var p := _sfx_pool[_sfx_pool_next]
	_sfx_pool_next = (_sfx_pool_next + 1) % _sfx_pool.size()
	return p


# ---------------------------------------------------------------------
# One-shot SFX — button taps, boost, collectible pickup
# ---------------------------------------------------------------------

## key must be one of the SFX dictionary keys above ("boost",
## "button_press", "collection", "explosion"). Silently no-ops on an
## unknown key or a missing file, so a typo never crashes gameplay.
func play_sfx(key: String, volume_db: float = 0.0) -> void:
	if not SFX.has(key):
		push_warning("AudioManager: unknown sfx key '%s'" % key)
		return

	var stream := _load_stream(SFX[key])
	if stream == null:
		return

	var player := _next_pool_player()
	player.stream = stream
	player.volume_db = volume_db
	player.play()


# ---------------------------------------------------------------------
# Background music — started once from the main menu, survives the scene
# change into gameplay since this whole node is an autoload.
# ---------------------------------------------------------------------

func is_music_playing() -> bool:
	return _music_player.playing


func play_music(fade_in: float = 1.0) -> void:
	if _music_player.playing:
		return

	var stream := _load_stream(MUSIC_PATH)
	if stream == null:
		return
	if "loop" in stream:
		stream.loop = true

	_music_player.stream = stream
	_music_player.volume_db = -80.0 if fade_in > 0.0 else 0.0
	_music_player.play()

	if fade_in > 0.0:
		var tween := create_tween()
		tween.tween_property(_music_player, ^"volume_db", 0.0, fade_in)


func stop_music(fade_out: float = 1.0) -> void:
	_left_menu = true
	if not _music_player.playing:
		return
	if fade_out <= 0.0:
		_music_player.stop()
		return

	var tween := create_tween()
	tween.tween_property(_music_player, ^"volume_db", -80.0, fade_out)
	tween.tween_callback(_music_player.stop)


# ---------------------------------------------------------------------
# Opening stinger — main menu reveal, once.
# ---------------------------------------------------------------------

func play_opening() -> void:
	var stream := _load_stream(OPENING_PATH)
	if stream == null:
		return
	_opening_player.stream = stream
	_opening_player.volume_db = 0.0
	_opening_player.play()


# ---------------------------------------------------------------------
# Engine sound — jet_starting plays once, then jet_flying loops for as
# long as the run is active. Player calls start_engine_loop() from _ready()
# and stop_engine_loop() the moment GameManager leaves PLAYING.
# ---------------------------------------------------------------------

func start_engine_loop() -> void:
	if _engine_active:
		return
	_engine_active = true

	var start_stream := _load_stream(ENGINE_START_PATH)
	if start_stream == null:
		# No starting stinger available — just go straight into the loop.
		_start_engine_loop_stream()
		return

	_engine_oneshot_player.stream = start_stream
	_engine_oneshot_player.volume_db = 0.0
	_engine_oneshot_player.play()

	if not _engine_oneshot_player.finished.is_connected(_on_engine_start_finished):
		_engine_oneshot_player.finished.connect(_on_engine_start_finished, CONNECT_ONE_SHOT)


func _on_engine_start_finished() -> void:
	if _engine_active:
		_start_engine_loop_stream()


func _start_engine_loop_stream() -> void:
	var loop_stream := _load_stream(ENGINE_LOOP_PATH)
	if loop_stream == null:
		return
	if "loop" in loop_stream:
		loop_stream.loop = true

	_engine_loop_player.stream = loop_stream
	_engine_loop_player.volume_db = 0.0
	_engine_loop_player.play()


## Safe to call repeatedly / when the loop was never started — idempotent.
func stop_engine_loop(fade_out: float = 0.4) -> void:
	if not _engine_active:
		return
	_engine_active = false

	if _engine_oneshot_player.finished.is_connected(_on_engine_start_finished):
		_engine_oneshot_player.finished.disconnect(_on_engine_start_finished)

	_fade_out_and_stop(_engine_oneshot_player, fade_out)
	_fade_out_and_stop(_engine_loop_player, fade_out)


func _fade_out_and_stop(player: AudioStreamPlayer, fade_out: float) -> void:
	if not player.playing:
		return
	if fade_out <= 0.0:
		player.stop()
		player.volume_db = 0.0
		return

	var tween := create_tween()
	tween.tween_property(player, ^"volume_db", -80.0, fade_out)
	tween.tween_callback(player.stop)
	tween.tween_callback(func(): player.volume_db = 0.0)


# ---------------------------------------------------------------------
# Mute — main_menu's existing Sound on/off toggle should call this instead
# of poking AudioServer directly, so this is the single source of truth.
# ---------------------------------------------------------------------

func set_muted(muted: bool) -> void:
	_muted = muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)


func is_muted() -> bool:
	return _muted


## Has the game ever transitioned out of the main menu this session?
## main.gd uses this (instead of is_music_playing() alone) to decide
## whether it's safe to auto-start menu music — see main.gd for why.
func has_left_menu() -> bool:
	return _left_menu
