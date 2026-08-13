extends Node
## Cinematic camera turn-around played the instant a run ends (obstacle
## hit -> GameManager.GameState.GAME_OVER, per player.gd's _explode()).
## CameraRig breaks off its normal chase-follow, sweeps around the wrecked
## boat from a low "hero" angle while pulling back and rising, then hands
## off to HUD to reveal the continue-with-Shades prompt — instead of that
## prompt just popping up instantly over a boat that's still silently
## sitting there, which is what happened before this script existed.
##
## Same reasoning as intro_sequence.gd for being its own node/script
## rather than folded into camera_rig.gd or hud.gd: camera_rig.gd stays a
## plain chase camera with no cinematics logic of its own, and this script
## only touches CameraRig's already-public fields (global_position,
## rotation) plus its built-in set_process() — exactly the same surface
## intro_sequence.gd already uses for the opening approach shot.
##
## hud.gd no longer opens ContinuePrompt itself on GAME_OVER — see its
## show_continue_prompt() — specifically so this cinematic has room to
## play first. This script calls that method once the camera settles.

@export var camera_rig_path: NodePath
@export var player_path: NodePath
@export var hud_path: NodePath

@export_group("Orbit Shot")
## Blend from wherever the chase camera happened to be into the orbit's
## starting framing, so the cut into the cinematic reads as one continuous
## move rather than a jump-cut — same idea as intro_sequence.gd's own
## return-to-chase blend, just entering a shot instead of leaving one.
@export var entry_blend_duration: float = 0.35
## How long the camera sweeps around the wreck.
@export var orbit_duration: float = 2.2
## Degrees of azimuth the camera sweeps through around the wreck — the
## "turn around" itself.
@export var orbit_sweep_degrees: float = 150.0
## Starting azimuth, degrees, measured the same way the sweep is applied
## (0 = directly behind the wreck, matching the chase camera's own
## default framing before the cut).
@export var orbit_start_angle_degrees: float = -60.0
@export var orbit_start_radius: float = 5.0
@export var orbit_end_radius: float = 8.5
## Starts low (a dramatic "hero" angle close to the water) and rises
## through the sweep — the "super angle" read the orbit is going for.
@export var orbit_start_height: float = 1.2
@export var orbit_end_height: float = 4.0
## How much of the wreck's local up-offset the camera aims at, so it's
## framing the boat's center rather than the water line under it.
@export var look_at_height: float = 0.6

@export_group("Hold")
## Beat held on the final framing before the UI reveals — a hard cut
## straight into the prompt reads as rushed even after a good camera move.
@export var hold_duration: float = 0.5

@export_group("Return to Chase")
## How long the blend from the orbit's final framing back to CameraRig's
## normal chase position/rotation takes, right before control is handed
## back to it. Same problem intro_sequence.gd's own _transition_to_chase()
## solves, just in the opposite direction (cutscene -> chase instead of
## chase -> cutscene): camera_rig.gd's _process() only ever touches
## rotation.z (bank follow) — it has no code path that resets rotation.x/y
## back to the rig's "locked forward" base state. The orbit above drives
## rotation every frame via look_at(), which sets all three axes to
## whatever angle frames the wreck from the side. Without this blend,
## camera_rig.set_process(true) resumes the position chase fine (that's
## recomputed fresh every frame) but rotation.x/y are left exactly where
## the last look_at() call put them — permanently, since nothing
## afterward ever touches them again — which reads as the camera "stuck"
## looking sideways at the boat even once it's revived and flying
## forward again.
@export var return_duration: float = 0.4


func _ready() -> void:
	# Same reasoning as intro_sequence.gd: wait a frame so CameraRig's own
	# _ready() has resolved its target/camera before anything here tries
	# to read or drive it.
	await get_tree().process_frame
	GameManager.state_changed.connect(_on_game_state_changed)


func _on_game_state_changed(new_state: GameManager.GameState) -> void:
	if new_state == GameManager.GameState.GAME_OVER:
		_run_death_cam()


func _run_death_cam() -> void:
	var camera_rig: Node3D = get_node_or_null(camera_rig_path) as Node3D
	var player: Node3D = get_node_or_null(player_path) as Node3D
	var hud: Node = get_node_or_null(hud_path)
	if camera_rig == null or player == null:
		push_warning("death_sequence.gd: camera_rig_path/player_path did not resolve — skipping the death cam, revealing the continue prompt immediately.")
		if hud and hud.has_method("show_continue_prompt"):
			hud.show_continue_prompt()
		return

	# CameraRig drives its own position/rotation every frame in _process()
	# — switched off for the whole cinematic so it doesn't fight this
	# script's direct control, same as intro_sequence.gd does for the
	# opening approach shot.
	camera_rig.set_process(false)

	# player.gd's _explode() already zeroed velocity and froze the boat in
	# place the instant GAME_OVER hit, so this position is stable for the
	# whole shot — no need to keep re-reading it every frame the way
	# intro_sequence.gd has to for a boat that's still flying under it.
	var wreck_position: Vector3 = player.global_position
	var look_target: Vector3 = wreck_position + Vector3(0.0, look_at_height, 0.0)
	var start_position: Vector3 = camera_rig.global_position

	var elapsed := 0.0
	var total_duration := entry_blend_duration + orbit_duration
	while elapsed < total_duration:
		elapsed += get_process_delta_time()

		var orbit_t: float = clamp((elapsed - entry_blend_duration) / orbit_duration, 0.0, 1.0)
		# Eases into the sweep rather than starting at full speed —
		# TRANS_SINE-equivalent curve via ease(), matching the "calm,
		# deliberate" cinematic read the rest of the project's camera work
		# goes for (see camera_rig.gd's own docstring).
		var eased_orbit: float = ease(orbit_t, 0.4)

		var angle := deg_to_rad(orbit_start_angle_degrees + orbit_sweep_degrees * eased_orbit)
		var radius: float = lerp(orbit_start_radius, orbit_end_radius, eased_orbit)
		var height: float = lerp(orbit_start_height, orbit_end_height, eased_orbit)
		var orbit_position: Vector3 = wreck_position + Vector3(sin(angle) * radius, height, cos(angle) * radius)

		var blend_t: float = clamp(elapsed / entry_blend_duration, 0.0, 1.0)
		if blend_t < 1.0:
			camera_rig.global_position = start_position.lerp(orbit_position, ease(blend_t, -2.0))
		else:
			camera_rig.global_position = orbit_position

		camera_rig.look_at(look_target, Vector3.UP)
		await get_tree().process_frame

	if hold_duration > 0.0:
		await get_tree().create_timer(hold_duration).timeout

	if hud and hud.has_method("show_continue_prompt"):
		hud.show_continue_prompt()

	# Blend rotation (and position, so the two don't fall out of sync)
	# from wherever the orbit's last look_at() left them back to
	# CameraRig's own chase framing before handing control back — see
	# return_duration's doc comment above for why this step can't be
	# skipped. Reads player.global_position fresh each frame rather than
	# using the cached wreck_position, same reasoning as
	# intro_sequence.gd's _transition_to_chase(): if the player has
	# already revived and started moving again by the time this runs,
	# the blend should ease toward where the boat IS, not a stale point.
	await _transition_to_chase(camera_rig, player)

	# Hand control back to CameraRig's normal chase logic. If the player
	# pays to continue, the boat revives (see player.gd's _revive()) and
	# CameraRig picks up chasing it again exactly like any other frame —
	# no special-case handoff needed here. If the run stays over, CameraRig
	# just holds position relative to the stationary wreck, which is
	# harmless to leave running.
	camera_rig.set_process(true)


## Mirrors intro_sequence.gd's _transition_to_chase() — same shape, same
## reasoning, just entering the chase from the death orbit instead of
## from the opening approach shot. Eases both position and rotation from
## wherever the cinematic left them down to CameraRig's configured chase
## offset and its Vector3.ZERO "locked forward" base rotation, so handing
## off to camera_rig.set_process(true) afterward reads as one continuous
## move rather than a snap.
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
