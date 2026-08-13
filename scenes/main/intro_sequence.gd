extends Node
## Opening sequence: a fixed establishing camera watches the aircraft
## approach nose-on ("front view") from a distance, holding completely
## static — no dolly, no zoom — while the aircraft closes the distance and
## flies past it toward the world. Once it's passed, the camera cuts back
## to CameraRig's normal chase framing (its "origin" position/rotation)
## and resumes following. A short prep gap follows before GameManager
## flips to PLAYING, so the player gets a beat to get oriented rather than
## being dropped straight into a scoring, obstacle-spawning run.
##
## Supersedes the earlier version of this file (tight zoom + fog reveal,
## pulling back smoothly) — per explicit correction, this is a fixed shot
## + cut back to chase-cam instead, closer to the reference screenshots'
## "static wide establishing shot, then cut to gameplay framing" read.
##
## Continuity fix (per explicit feedback: "when camera changes the angle,
## game/player pause for a few seconds"): GameManager now flips to PLAYING
## the INSTANT the approach tween finishes, before the return-to-chase
## camera tween even starts, instead of after everything (return tween +
## prep_duration) has already played out. Player.gd's own _physics_process
## picks up real forward motion + steering the moment that happens, so the
## aircraft keeps flying continuously of its own accord while the camera
## cuts back to chase framing in parallel — there's no longer a window
## where state != PLAYING and player.gd's early-return leaves the aircraft
## sitting dead in the air mid-cut. prep_duration is still available below
## as a non-blocking cosmetic window (e.g. a "Good Luck" HUD fade once
## scenes/ui/ exists) — it no longer gates PLAYING, so it can't reintroduce
## the pause it's meant to avoid.
##
## Deliberately its own node/script rather than folded into main.gd or
## camera_rig.gd — same reasoning as before: main.gd stays the thin
## entry-point skeleton, and camera_rig.gd stays a plain chase camera with
## no cinematics logic of its own. This script only touches CameraRig's
## already-public fields (global_position, rotation, follow_offset) and
## its built-in set_process(), so camera_rig.gd needed no changes at all
## this time.
##
## Deliberately does NOT touch player.gd's physics. The aircraft's forward
## creep during the approach is a direct global_position tween, bypassing
## move_and_slide() entirely — player.gd's own _physics_process() already
## no-ops while GameManager.current_state != PLAYING, so there's no
## competing writer. Kept short (see approach_camera_offset/
## overshoot_distance below) so the distance covered stays under one
## speed-ramp chunk (speed_ramp_chunk_length on player.gd) — the real run
## still starts its distance-based ramp at effectively zero.

@export var camera_rig_path: NodePath
@export var player_path: NodePath
## Phase 10: HUD's "Good Luck" prep message is driven from here rather
## than from a GameState value, since there isn't (and shouldn't be) a
## GameState for "about to start" — that timing only exists inside this
## sequence. Optional: if unset or the node doesn't resolve, the intro
## just runs without a prep message instead of erroring.
@export var hud_path: NodePath

@export_group("Approach (static shot)")
## Where the static camera sits, relative to the player's spawn position —
## ahead of it along the flight path (-Z) and slightly elevated, roughly
## matching the reference screenshot's framing.
@export var approach_camera_offset: Vector3 = Vector3(0.0, 2.0, -22.0)
## Small downward tilt so the incoming aircraft reads centered-low in
## frame rather than dead-center on the horizon.
@export var approach_pitch_degrees: float = -4.0
## How far past the static camera's Z the aircraft travels before it's
## treated as "passed" and the return-to-chase transition begins.
@export var overshoot_distance: float = 4.0
## Total time for the approach, start to "passed the camera". Eases in —
## slow while the aircraft is small and far off, picking up speed as it
## closes the distance — rather than a constant crawl.
@export var approach_duration: float = 2.4

@export_group("Return to Chase")
## How long the cut back to CameraRig's normal chase framing takes.
@export var return_duration: float = 0.5

@export_group("Prep Gap")
## Pause after the camera has settled into chase position and before
## GameManager flips to PLAYING. This is where a "Good Luck" / countdown
## HUD message would show once scenes/ui/ exists (still empty — Phase 10
## per the README) — see the hook at the end of _run() below.
@export var prep_duration: float = 1.0


func _ready() -> void:
	# Wait a frame so CameraRig's own _ready() (which resolves _target,
	# _camera, etc.) has definitely run before this script starts driving
	# it, regardless of sibling order in the scene file.
	await get_tree().process_frame

	var camera_rig: Node3D = get_node_or_null(camera_rig_path) as Node3D
	var player: Node3D = get_node_or_null(player_path) as Node3D
	if camera_rig == null or player == null:
		push_warning("intro_sequence.gd: camera_rig_path/player_path did not resolve — skipping the intro, jumping straight to PLAYING.")
		AudioManager.start_engine_loop()
		GameManager.change_state(GameManager.GameState.PLAYING)
		return

	_run(camera_rig, player)


func _run(camera_rig: Node3D, player: Node3D) -> void:
	var hud: Node = get_node_or_null(hud_path)
	# CameraRig drives its own position/rotation every frame in _process()
	# — switched off for the whole intro so it doesn't fight this script's
	# direct control, then switched back on once camera_rig is already
	# sitting exactly where its own chase logic would put it (see
	# _transition_to_chase), so resuming reads as continuous, not a second
	# jump.
	camera_rig.set_process(false)

	# Engine audio: jet_starting plays as the aircraft begins its approach,
	# then AudioManager crossfades/hands off into the looping jet_flying
	# clip on its own timing — intro_sequence.gd only needs to kick the
	# sequence off once, here, rather than track the starting->flying
	# handoff itself. Matches main.gd's docstring: this script owns the
	# "start" side of AudioManager.start_engine_loop()/stop_engine_loop(),
	# player.gd owns the corresponding stop (e.g. on crash/restart).
	AudioManager.start_engine_loop()

	var spawn_position: Vector3 = player.global_position
	var camera_position: Vector3 = spawn_position + approach_camera_offset
	camera_rig.global_position = camera_position
	# rotation.y = PI flips the rig to face back along +Z, toward the
	# aircraft's spawn, instead of its normal forward -Z — this is the
	# "front view of the incoming aircraft" shot.
	camera_rig.rotation = Vector3(deg_to_rad(approach_pitch_degrees), PI, 0.0)

	var end_z: float = camera_position.z - overshoot_distance
	var approach_tween := create_tween()
	approach_tween.set_ease(Tween.EASE_IN)
	approach_tween.set_trans(Tween.TRANS_QUAD)
	approach_tween.tween_property(player, "global_position:z", end_z, approach_duration)
	await approach_tween.finished

	# Hand off control to real physics HERE, before the camera cut, not
	# after it. player.gd's _physics_process no-ops while current_state !=
	# PLAYING — flipping the state now means the aircraft's own forward
	# speed/steering takes over on the very next physics frame, so it
	# keeps moving under its own power for the whole return-to-chase cut
	# below instead of hanging motionless (the direct z-tween above has
	# already ended, and nothing else was driving position in the gap).
	GameManager.change_state(GameManager.GameState.PLAYING)

	# Runs concurrently with the plane's own physics-driven flight — this
	# coroutine awaiting a tween does not pause any other node's
	# _physics_process, so the flight underneath stays continuous.
	await _transition_to_chase(camera_rig, player)
	camera_rig.set_process(true)

	# Cosmetic-only from here on: nothing below gates PLAYING anymore, so
	# it can't reintroduce a pause. "Good Luck" fades in for prep_duration
	# then out, purely as an overlay — the plane is already flying under
	# real physics underneath it the whole time.
	if hud and hud.has_method("show_prep_message"):
		hud.show_prep_message()
	if prep_duration > 0.0:
		await get_tree().create_timer(prep_duration).timeout
	if hud and hud.has_method("hide_prep_message"):
		hud.hide_prep_message()


## Cuts the camera from the static approach shot back to CameraRig's own
## configured chase framing — "goes back to his origin position." Reads
## camera_rig.follow_offset directly (rather than caching a second copy of
## it) so whatever's tuned on the rig in the editor is what it returns to.
##
## Deliberately NOT a single Tween to a fixed target position anymore. The
## plane is now flying under its own physics for the whole return cut (see
## the state-flip above), so a chase_position computed once at the start
## would target where the plane WAS, not where it ends up — the camera
## would settle behind a stale point instead of the moving aircraft. This
## recomputes player.global_position + follow_offset every frame instead,
## easing rig->player_target from where the static shot left off down to
## effectively 0 over return_duration, using the same lerp-toward-target
## shape CameraRig's own _process() chase logic uses, so handing control
## back to camera_rig.set_process(true) afterward reads as one continuous
## motion rather than a second, different-feeling camera move.
func _transition_to_chase(camera_rig: Node3D, player: Node3D) -> void:
	var start_position: Vector3 = camera_rig.global_position
	var start_rotation: Vector3 = camera_rig.rotation
	var elapsed := 0.0
	while elapsed < return_duration:
		elapsed += get_process_delta_time()
		var t: float = clamp(elapsed / return_duration, 0.0, 1.0)
		var eased_t: float = ease(t, -2.0)  # EASE_IN_OUT-equivalent curve
		var chase_position: Vector3 = player.global_position + camera_rig.follow_offset
		camera_rig.global_position = start_position.lerp(chase_position, eased_t)
		camera_rig.rotation = start_rotation.lerp(Vector3.ZERO, eased_t)
		await get_tree().process_frame
	camera_rig.global_position = player.global_position + camera_rig.follow_offset
	camera_rig.rotation = Vector3.ZERO
