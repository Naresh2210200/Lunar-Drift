extends CharacterBody3D
## Player boat. Deliberately NOT RigidBody3D/Jolt here — full physics
## simulation fights you when you want tight, predictable arcade steering.
## CharacterBody3D + move_and_slide() gives direct control over exactly how
## the boat responds, which is what "drift feel" actually needs. Jolt still
## earns its keep later for ocean debris/props, just not for this.
##
## This pass adds four feel systems on top of the Milestone 2 baseline,
## all built from input/time the boat already has access to — no new
## dependencies on GameManager or ProceduralWorld:
##   1. Distance-based speed ramp — the run quietly gets faster the further
##      you travel, using the same chunk-length concept ProceduralWorld
##      already spawns scenery on, so "harder" and "denser" scale together.
##   2. Boost+steer lateral push — holding a steer direction WHILE boosting
##      adds a small sideways shove in that direction, on top of the boost's
##      forward speed multiplier. Steering alone or boosting alone doesn't
##      trigger it; the combination is what's rewarded.
##   3. Drift-release roll flip — holding a steer direction for long enough
##      and then releasing it ("taking your hand back") spends that held
##      charge on an automatic 360° barrel roll — the SAME axis (rotation.z)
##      the bank lean uses, just taken all the way around instead of
##      stopping at bank_angle_max — plus a short curved lateral slide and
##      a brief forward speed bonus on landing. Steering briefly and
##      letting go does nothing; only a sustained hold pays off.
##   4. Speed-scaled nose dip — a slight forward pitch (rotation.x) that
##      deepens as current speed climbs, independent of the roll/flip
##      (rotation.z) above so the two always blend instead of competing
##      for the same axis.

signal boost_state_changed(active: bool)
## Fired when a drift roll flip starts/ends — no listener yet, but Phase 9
## (audio) and Phase 11 (polish/VFX) both want this hook rather than
## polling state.
signal drift_started(direction: float)
signal drift_completed()
## Single-use, cooldown-gated jump — clears small obstacles, not a repeat-
## input evasion tool. No listener yet, same as the drift signals above:
## Phase 9 (audio) and Phase 11 (VFX) are the intended consumers.
signal jump_started()
signal jump_completed()
## Fired when a Phase-difficulty low-pass starts/ends — same "signal now,
## HUD/audio hook in later" convention as the other state signals above.
## A near-water warning flash is the obvious first consumer once the HUD
## wants one.
signal water_dip_started()
signal water_dip_ended()
## Score is now a running total (_score_accum), not derived from distance
## directly: it grows every frame by current_forward_speed * delta *
## the multiplier meter's current tier (see moon_energy.gd, repurposed
## from a survival resource into a Race the Sun-style multiplier), plus
## a flat bonus per Shade collected (see collect_shade). Distance itself
## is still tracked separately (_get_distance) purely for the altitude/
## water-difficulty ramp below, which intentionally does NOT want a hot
## multiplier streak to make low passes start any sooner.
signal score_changed(score: int)
## Fired once, the instant the run ends (GameManager leaves PLAYING —
## currently only obstacle hits do that) and the break-apart effect below
## triggers. Same "signal now, HUD/audio hook later" convention as the
## other state signals above — a game-over screen or a screen-shake
## effect are the obvious first consumers.
signal player_destroyed()

@export var forward_speed: float = 22.0
## Raised from 8.0 -> 12.0 per explicit feedback that left/right steering
## felt too weak. This is the target lateral velocity steer input chases
## (see lateral_accel_at_low/high_speed below for HOW FAST it chases it) —
## raising it makes the plane's actual max turn rate more agile, on top of
## (not instead of) the low/high-speed accel bump below.
@export var steer_speed: float = 12.0
@export var bank_angle_max: float = deg_to_rad(25.0)
@export var bank_lerp_speed: float = 6.0
## "Slicing through the air" nose dip — separate axis from the bank roll
## above (rotation.x vs rotation.z), so the two blend rather than compete.
## Scales with how fast the boat is currently going relative to
## pitch_reference_speed, so the dip deepens as the ramp/boost speed up.
@export var pitch_angle_max: float = deg_to_rad(8.0)
@export var pitch_lerp_speed: float = 5.0
@export var pitch_reference_speed: float = 40.0
## Steer input below this magnitude counts as "released" for both the
## lateral-push and drift-charge systems, so small analog noise near zero
## doesn't read as a held direction.
@export var steer_deadzone: float = 0.1

@export var boost_multiplier: float = 1.8
@export var boost_duration: float = 1.2
@export var boost_cooldown: float = 3.0

@export_group("Jump")
## Per explicit request: a single jump to clear small obstacles, gated by
## a cooldown so it can't be spammed — an emergency escape, not a
## replacement for steering around things. Requires an input action named
## "jump" in Project Settings -> Input Map (not added here — this script
## only reads the action by name, same convention as "steer_left" /
## "steer_right" / "boost" above).
##
## Peak height of the hop, in meters.
@export var jump_height: float = 3.5
## Total time from leaving the ground to landing back at the same height.
@export var jump_duration: float = 0.55
## Minimum time between jumps, counted from the START of a jump (not from
## landing) — same convention as boost_cooldown.
@export var jump_cooldown: float = 2.5

@export_group("Altitude / Water Difficulty")
## y = 0 is the ocean surface (see ocean_follow.gd — it only ever snaps
## X/Z, never Y). This is the boat's normal cruising height above that.
## Previously there was no baseline at all: the boat sat AT y = 0, flush
## with the water, with nothing holding it there — any tiny float drift
## from the jump arc's velocity integration had nowhere to go but
## negative, which is the "suddenly sinks into the water" bug. Giving it
## a real target height and continuously correcting toward it (see
## _update_altitude) fixes that as a side effect of fixing the design gap
## that caused it, rather than patching the symptom directly.
@export var base_hover_height: float = 2.2
## How close to the water a "low pass" brings the boat during difficulty
## dips below. Raised from the original 0.4 — combined with the
## nose-dip pitch fix below (dip_pitch_reduction), 0.4 was cutting it
## close enough that a wave crest plus a small pitch swing could put the
## bow at/under the water line, which is what read as "suddenly falls
## into the water" rather than "flies low." 0.6 keeps the low-pass
## feeling genuinely close and dangerous while leaving real margin.
## Tune down again once you've playtested the pitch fix and can judge by
## eye whether 0.4 actually reads fine now — this is a conservative
## first pass, not a hard requirement.
@export var low_hover_height: float = 0.6
## How fast actual height chases its current target (hover or low-pass).
## This is what makes the dip — and the recovery — read as smooth motion
## instead of a snap, and it's also what keeps any residual float error
## from ever accumulating: every frame pulls back toward the real target
## instead of trusting a single arc to land exactly on it.
@export var hover_lerp_speed: float = 3.0
## Distance traveled (meters, same as the altitude system elsewhere reads —
## NOT the multiplier-scaled score) before low passes can start happening
## at all.
@export var difficulty_start_distance: int = 1000
## Seconds between low passes right at the threshold, and the floor that
## shrinks toward as distance past the threshold increases.
@export var dip_interval_at_threshold: float = 9.0
@export var dip_interval_min: float = 3.5
## Distance past the threshold at which dip_interval_min is fully reached.
@export var dip_difficulty_range: float = 3000.0
@export var dip_duration_min: float = 1.2
@export var dip_duration_max: float = 2.2
## Multiplies pitch_angle_max while a low-pass dip is active (1.0 = no
## change, 0.0 = no nose-dip at all during a dip). See the pitch fix note
## in _physics_process for why this exists — full pitch was eating the
## dip's already-thin clearance budget.
@export var dip_pitch_reduction: float = 0.35

@export_group("Speed Ramp")
## Matches ProceduralWorld's chunk_size by convention, not by reference —
## they're two separate exports on purpose (this script has no dependency
## on ProceduralWorld existing), but keep them equal in the editor so
## "further = faster" and "further = denser" line up. (Renamed on
## ProceduralWorld's side when it became a 2D grid — same number, this
## export's own name is unaffected.)
@export var speed_ramp_chunk_length: float = 40.0
## Flat forward-speed bonus added per chunk of distance crossed.
@export var speed_per_chunk: float = 0.6
## Hard ceiling on the ramp bonus so a very long run doesn't eventually
## outrun what's still readable/dodgeable.
@export var max_speed_bonus: float = 18.0

@export_group("Speed-Scaled Handling")
## Per explicit request: steering should get heavier — more "drag", less
## instant response — as forward speed climbs from the ramp/boost, rather
## than staying equally snappy at every speed forever. Implemented as a
## lateral ACCELERATION that shrinks with current speed: velocity.x now
## chases steer_input * steer_speed via move_toward() instead of being
## set to it directly every frame, and the move_toward rate is what gets
## slower — steer_speed itself (the max lateral velocity you can reach)
## is untouched, so top turning speed doesn't drop, it just takes longer
## to get there and longer to stop once you release. That's "drag": lag
## and momentum, not a weaker turn.
##
## At low speed this is high enough to feel effectively instant (matches
## the old snap-to-input behavior); at high speed it's low enough that
## you have to lead a turn instead of last-second-correcting it.
## Raised 60.0 -> 75.0 alongside the steer_speed bump above — keeps
## low-speed turn-in reading as snappy/near-instant rather than the
## steer_speed increase alone making it feel like it takes longer to
## reach the (now higher) max lateral velocity.
@export var lateral_accel_at_low_speed: float = 75.0
## Raised 14.0 -> 24.0 — this was the main "turning feels weak at speed"
## culprit: at high forward speed the old value made steering noticeably
## laggy. Still meaningfully lower than the low-speed value (heavier
## handling at speed is intentional, see the design note above), just not
## sluggish anymore.
@export var lateral_accel_at_high_speed: float = 24.0
## The forward speed at which lateral_accel_at_high_speed is fully
## reached. Set with the boosted top speed in mind — forward_speed +
## max_speed_bonus is the unboosted ceiling, so this should sit somewhere
## above that if boost is meant to be where the drag really bites.
@export var handling_reference_speed: float = 70.0

@export_group("Boost Steer Push")
## How fast the sideways push builds toward its max while boost+steer are
## both held.
@export var lateral_boost_gain: float = 14.0
## How fast it decays back to zero once boost or steer input stops.
@export var lateral_boost_decay: float = 10.0
@export var lateral_boost_max: float = 6.0

@export_group("Drift Spin")
## Seconds a steer direction must be held before releasing it pays off with
## a spin. Short taps intentionally do nothing here.
@export var drift_charge_threshold: float = 0.6
## Seconds the 360° spin animation takes to complete.
@export var drift_spin_duration: float = 0.5
## How far the boat slides sideways mid-spin, as a curve back to center
## (see _physics_process) rather than a flat push.
@export var drift_slide_speed: float = 5.0
## Temporary forward-speed bonus granted the instant a spin completes —
## the "reward" for committing to a full charge-and-release drift.
@export var drift_release_speed_bonus: float = 6.0
@export var drift_release_bonus_duration: float = 0.8

@export_group("Destruction")
## How many small debris cubes fly outward when the run ends.
@export var fragment_count: int = 14
@export var fragment_min_size: float = 0.15
@export var fragment_max_size: float = 0.4
@export var fragment_speed_min: float = 4.0
@export var fragment_speed_max: float = 10.0
## Degrees/sec each fragment tumbles while it flies outward.
@export var fragment_spin_speed: float = 360.0
## How long a fragment lives before it's freed — it also starts fading
## out at 60% of this, so it never just pops out of existence.
@export var fragment_lifetime: float = 1.1

@onready var mesh_pivot: Node3D = $MeshPivot
@onready var moon_energy: Node = $MoonEnergy
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D

var _is_boosting: bool = false
var _boost_timer: float = 0.0
var _cooldown_timer: float = 0.0

var _is_jumping: bool = false
var _jump_time: float = 0.0
var _jump_cooldown_timer: float = 0.0

var _rng := RandomNumberGenerator.new()
var _in_dip: bool = false
var _dip_time_remaining: float = 0.0
var _time_to_next_dip: float = 0.0

var _last_score: int = -1
var _score_accum: float = 0.0

## Lets _physics_process notice the exact frame the run ends (PLAYING ->
## anything else) instead of just silently freezing every frame after —
## see the blast/broken effect in _physics_process below. _destroyed
## makes that a one-shot: a fresh Player instance (main.tscn reloads on
## restart) always starts false, so this never needs a manual reset.
var _was_playing: bool = false
var _destroyed: bool = false

## FIX (audit finding): ProceduralWorld's speed-difficulty easing
## duck-types this target for a "speed"/"current_speed"/"forward_speed"
## property (see procedural_world.gd's _get_target_speed). Before this
## fix, none of those existed as a LIVE value — `forward_speed` above is
## just the static base export (22.0, never mutated), so the density/gap
## easing was permanently frozen at whatever that constant produces,
## completely ignoring the ramp bonus, boost multiplier, and drift bonus
## that _get_current_forward_speed() actually computes every frame. This
## property is that same computed value, published once per physics frame
## so ProceduralWorld's "current_speed" match picks up the real number.
var current_speed: float = 0.0

var _lateral_boost_velocity: float = 0.0

## Charge state for the drift system: how long the current steer direction
## has been held, and which way it's leaning. Reset on release or on a
## direction flip mid-hold (no charging left, tapping right, and cashing in
## a "held right" spin).
var _steer_hold_time: float = 0.0
var _steer_hold_direction: float = 0.0

var _is_drifting: bool = false
var _drift_progress: float = 0.0  # 0..1 across drift_spin_duration
var _drift_direction: float = 1.0
var _drift_bonus_timer: float = 0.0


func _ready() -> void:
	# Lets Phase 6 obstacles identify "did the player hit this" without an
	# explicit reference back to this node — obstacles just check the
	# group on whatever body entered their Area3D.
	add_to_group("player")

	# Start already at cruising height, not at the water — see the
	# Altitude / Water Difficulty export group above for why y = 0 used to
	# be the boat's resting height with nothing holding it there.
	_rng.randomize()
	global_position.y = base_hover_height
	_time_to_next_dip = dip_interval_at_threshold

	# Phase 9 audio: engine start moved to _physics_process below — see
	# the fix note there. Starting it here in _ready() fired jet_starting
	# immediately on scene load, but intro_sequence.gd holds the game in
	# a non-PLAYING state for its whole approach shot, and the early-out
	# in _physics_process below calls stop_engine_loop() every single
	# frame while state != PLAYING — killing the engine sound the instant
	# after it started, before the player ever heard it.

	# MoonEnergy is now a score multiplier meter, not a survival resource —
	# there's no more "ran it to zero, run over" signal to listen for.
	# Obstacle collisions (see procedural_world.gd) are the only way a run
	# ends now.


## Public API for the Shades collectible (see procedural_world.gd). Three
## things happen on pickup: the multiplier meter fills, a flat score bonus
## is granted (NOT scaled by the multiplier — the multiplier instead
## scales the ongoing distance score below, same "multiplier boosts your
## whole run" shape Race the Sun uses), and Shades are banked as
## persistent currency via EconomyManager.add_shards().
##
## FIX (audit finding): this used to poke `EconomyManager.shards` directly
## and manually emit `shards_changed` as a defensive fallback (written
## before EconomyManager's real source was available). That path skipped
## EconomyManager's own `_save()` call entirely, so every Shade earned
## in-game was lost on app close — only Store purchases actually
## persisted. add_shards() is the real API: it increments, emits the
## signal, AND saves. Route through it instead of touching the
## autoload's internals directly.
func collect_shade(meter_fill: float, score_bonus: int) -> void:
	moon_energy.add_progress(meter_fill)
	_score_accum += score_bonus
	EconomyManager.add_shards(1)
	AudioManager.play_sfx("collection")


## Public read-only getters for the Phase 10 HUD's ability meters. 1.0 =
## fully ready (meter full), 0.0 = just used (meter empty, refilling as
## the cooldown counts down). Deliberately getters, not signals — the HUD
## polls these once a frame in its own _process rather than this script
## emitting every physics frame whether or not the value visibly changed;
## keeps the "who owns this state" boundary the same as everywhere else
## (Player owns its own cooldown timers, HUD only ever reads).
func get_boost_ready_ratio() -> float:
	if boost_cooldown <= 0.0:
		return 1.0
	return 1.0 - clamp(_cooldown_timer / boost_cooldown, 0.0, 1.0)


func get_jump_ready_ratio() -> float:
	if jump_cooldown <= 0.0:
		return 1.0
	return 1.0 - clamp(_jump_cooldown_timer / jump_cooldown, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	# GameManager is the single source of truth for run state (see
	# game_manager.gd) — once an obstacle ends the run, stop simulating
	# movement here instead of letting the boat keep sliding through a
	# game-over screen that doesn't exist yet.
	if GameManager.current_state != GameManager.GameState.PLAYING:
		# Run just ended (obstacle hit, per procedural_world.gd's Area3D ->
		# "player" group check) — break the boat apart right on the frame
		# control is taken away, instead of it just silently freezing
		# mid-air with zero feedback that anything happened.
		if _was_playing and not _destroyed:
			_explode()
		_was_playing = false
		# Idempotent — safe to call every frame the run isn't active without
		# re-triggering a fade each time.
		AudioManager.stop_engine_loop()
		return

	# FIX: continue_prompt.gd's "Continue" button flips GameManager straight
	# back to PLAYING to resume this SAME run/instance (see its own
	# docstring — no respawn/reload involved). Without this, _explode()'s
	# hidden mesh + disabled collision would stay broken forever the
	# instant the player paid to continue, even though DeathSequence/HUD
	# think the run is back underway.
	if _destroyed:
		_revive()
	_was_playing = true

	# Phase 9 audio fix: jet_starting/jet_flying now begin the instant
	# state reaches PLAYING (matching exactly when this function stops
	# early-returning and the plane starts actually moving under real
	# physics), instead of firing in _ready() where intro_sequence.gd's
	# pre-PLAYING approach shot immediately killed it via the stop_engine_
	# loop() call above. start_engine_loop() no-ops on repeat calls once
	# active (_engine_active guard in audio_manager.gd), so calling it
	# every PLAYING frame here is harmless, not a re-trigger each frame.
	AudioManager.start_engine_loop()

	_update_boost(delta)
	_update_jump(delta)

	var steer_input := Input.get_axis("steer_left", "steer_right")

	_update_lateral_boost_push(delta, steer_input)
	_update_drift_charge(delta, steer_input)
	_update_drift_spin(delta)

	var current_forward_speed := _get_current_forward_speed()
	current_speed = current_forward_speed
	_score_accum += current_forward_speed * delta * moon_energy.current_multiplier

	if _is_drifting:
		# Player's "hand is back" during a flip by definition — this isn't
		# steered, it's spent charge playing itself out. The sideways
		# motion is a curve that peaks mid-flip and returns to zero
		# (sin over 0..PI), so the boat slides out and pulls back in
		# rather than drifting away in a straight line.
		velocity.x = _drift_direction * drift_slide_speed * sin(_drift_progress * PI)
	else:
		# Lateral velocity now CHASES the steer target via move_toward
		# instead of snapping to it instantly — the chase rate
		# (lateral_accel) shrinks as current_forward_speed climbs toward
		# handling_reference_speed, so the same steer input produces a
		# slower, laggier turn-in (and slower stop) at high speed than at
		# low speed. steer_speed itself — the target/ceiling — doesn't
		# change, so this reads as "heavier to control," not "weaker."
		var target_lateral_velocity := steer_input * steer_speed + _lateral_boost_velocity
		var handling_ratio: float = clamp(current_forward_speed / handling_reference_speed, 0.0, 1.0)
		var lateral_accel: float = lerp(lateral_accel_at_low_speed, lateral_accel_at_high_speed, handling_ratio)
		velocity.x = move_toward(velocity.x, target_lateral_velocity, lateral_accel * delta)
	velocity.z = -current_forward_speed
	move_and_slide()
	_update_altitude(delta)

	# Visual-only bank on the mesh, separate from the collision body, so
	# the hull leans into turns without the hitbox itself rotating. Runs
	# on rotation.z — the SAME axis the drift roll-flip below uses, on
	# purpose: a "roll flip" is a full 360° version of this exact lean,
	# not a separate motion, so they share the axis instead of each
	# fighting for their own. _update_drift_spin() already wrote
	# rotation.z for this frame while a flip is in progress, so the lerp
	# here is skipped while _is_drifting — otherwise this would immediately
	# overwrite it back toward the small bank_angle_max lean.
	if not _is_drifting:
		var target_bank := -steer_input * bank_angle_max
		mesh_pivot.rotation.z = lerp_angle(mesh_pivot.rotation.z, target_bank, delta * bank_lerp_speed)

	# Nose-dip pitch on rotation.x — independent of the roll/flip (z) above,
	# so pitch and roll always blend instead of competing for the same axis.
	# Deepens as current_forward_speed climbs toward pitch_reference_speed,
	# so the "slicing through the air" feel grows with the ramp and with
	# boost rather than staying constant.
	# Explicit `: float` on both, not `:=` — same fix as moon_rig.gd's
	# clamp()/lerp() note in the README: clamp() returns Variant in its
	# engine binding, so type inference has nothing concrete to grab.
	#
	# FIX (audit finding — "falls into the water at ~1000 score"): this
	# pitch used to apply at full strength during a low-pass dip too. At
	# base_hover_height (2.2) that's invisible headroom to spare; at
	# low_hover_height (0.4, see the dip export group above) it wasn't —
	# nose-down rotation pivots the bow toward/under the water line right
	# when the ALTITUDE system has already spent nearly all its clearance
	# getting the hull down there. Two systems independently tuned for
	# the normal-height case were stacking at exactly the moment they
	# overlap. dip_pitch_reduction scales pitch down (not to zero — a
	# little nose-down still reads as "skimming low", it just can't eat
	# the whole clearance budget anymore) whenever a dip is active.
	var speed_ratio: float = clamp(current_forward_speed / pitch_reference_speed, 0.0, 1.0)
	var pitch_scale := dip_pitch_reduction if _in_dip else 1.0
	var target_pitch: float = -pitch_angle_max * speed_ratio * pitch_scale
	mesh_pivot.rotation.x = lerp_angle(mesh_pivot.rotation.x, target_pitch, delta * pitch_lerp_speed)

	_update_score()


## Raw meters traveled — deliberately NOT the score anymore (see
## _get_score below). The altitude/water-difficulty ramp keys off actual
## distance, not the multiplier-scaled score, so a hot multiplier streak
## doesn't accidentally accelerate how soon low passes start.
func _get_distance() -> int:
	return maxi(floori(-global_position.z), 0)


func _get_score() -> int:
	return maxi(floori(_score_accum), 0)


## Emits only on an actual change to the rounded value, not every frame —
## HUD only needs to know when the displayed number would differ, not get
## called 60x/sec for no visible change.
func _update_score() -> void:
	var score := _get_score()
	if score != _last_score:
		_last_score = score
		score_changed.emit(score)


## Runs after move_and_slide(). During a jump, the jump arc already owns
## velocity.y/position.y for this frame and this function only advances the
## dip schedule underneath it. Otherwise it continuously pulls actual
## height toward whatever the current target is (cruise or low-pass) via
## lerp rather than ever trusting a single motion to land exactly on it —
## that continuous correction is what stops float drift from accumulating
## into the water over a long run.
func _update_altitude(delta: float) -> void:
	var distance := _get_distance()
	_update_dip_schedule(delta, distance)

	var target_height := low_hover_height if _in_dip else base_hover_height
	if not _is_jumping:
		global_position.y = lerp(global_position.y, target_height, clamp(delta * hover_lerp_speed, 0.0, 1.0))


## Below difficulty_start_distance, low passes never trigger at all. Above it,
## dips fire on a randomized timer whose average interval shrinks from
## dip_interval_at_threshold toward dip_interval_min as distance past the
## threshold grows, capped at dip_difficulty_range so a very long run
## doesn't eventually demand impossible reaction time.
func _update_dip_schedule(delta: float, distance: int) -> void:
	if distance < difficulty_start_distance:
		if _in_dip:
			_in_dip = false
			water_dip_ended.emit()
		return

	if _in_dip:
		_dip_time_remaining -= delta
		if _dip_time_remaining <= 0.0:
			_in_dip = false
			_time_to_next_dip = _next_dip_interval(distance)
			water_dip_ended.emit()
		return

	_time_to_next_dip -= delta
	if _time_to_next_dip <= 0.0:
		_in_dip = true
		_dip_time_remaining = _rng.randf_range(dip_duration_min, dip_duration_max)
		water_dip_started.emit()


func _next_dip_interval(distance: int) -> float:
	var progress: float = clamp(
		float(distance - difficulty_start_distance) / dip_difficulty_range, 0.0, 1.0
	)
	var interval: float = lerp(dip_interval_at_threshold, dip_interval_min, progress)
	return _rng.randf_range(interval * 0.7, interval * 1.3)


## One-shot: hides the hull, disables the collision shape (so the now-
## invisible boat can't keep blocking/triggering anything), stops it dead,
## and scatters small debris cubes outward in the existing white-hull/
## black-outline "paper" look — no new assets needed. Purely visual/audio;
## it doesn't touch GameManager itself, since GameManager is what already
## drove this by leaving PLAYING in the first place.
func _explode() -> void:
	_destroyed = true
	velocity = Vector3.ZERO
	mesh_pivot.visible = false
	_collision_shape.set_deferred("disabled", true)
	AudioManager.play_sfx("explosion")
	_spawn_fragments()
	player_destroyed.emit()


## Counterpart to _explode() — restores the boat when a run resumes after
## a death (continue_prompt.gd's "Continue" button). Debris fragments
## aren't cleaned up here; they're already tweening themselves to
## queue_free() on their own timers regardless of what the boat does next.
func _revive() -> void:
	_destroyed = false
	mesh_pivot.visible = true
	_collision_shape.set_deferred("disabled", false)


## Debris cubes are added under the current scene root (not under this
## node) so they keep flying/tumbling in world space even though this
## node itself just went invisible and non-colliding above.
func _spawn_fragments() -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return

	for i in fragment_count:
		var frag := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * _rng.randf_range(fragment_min_size, fragment_max_size)
		frag.mesh = box

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Alternate white hull / black outline chips, matching Hull +
		# HullOutline's own paper/ink materials in player.tscn.
		mat.albedo_color = Color(0.97, 0.97, 0.98) if i % 2 == 0 else Color(0.08, 0.08, 0.08)
		frag.material_override = mat

		scene_root.add_child(frag)
		frag.global_position = global_position + Vector3(
			_rng.randf_range(-0.4, 0.4),
			_rng.randf_range(-0.1, 0.3),
			_rng.randf_range(-0.6, 0.6)
		)
		frag.rotation = Vector3(
			_rng.randf_range(0.0, TAU), _rng.randf_range(0.0, TAU), _rng.randf_range(0.0, TAU)
		)

		# Mostly-outward, mostly-upward burst direction, per fragment.
		var dir := Vector3(
			_rng.randf_range(-1.0, 1.0), _rng.randf_range(0.4, 1.0), _rng.randf_range(-1.0, 1.0)
		).normalized()
		var speed := _rng.randf_range(fragment_speed_min, fragment_speed_max)
		var target_pos := frag.global_position + dir * speed * fragment_lifetime
		var spin := Vector3(
			_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)
		) * deg_to_rad(fragment_spin_speed) * fragment_lifetime

		var tween := create_tween().set_parallel(true)
		tween.tween_property(frag, "global_position", target_pos, fragment_lifetime) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(frag, "rotation", frag.rotation + spin, fragment_lifetime)
		tween.tween_property(mat, "albedo_color:a", 0.0, fragment_lifetime * 0.4) \
			.set_delay(fragment_lifetime * 0.6)
		tween.tween_callback(frag.queue_free).set_delay(fragment_lifetime)


func _update_boost(delta: float) -> void:
	if _is_boosting:
		_boost_timer -= delta
		if _boost_timer <= 0.0:
			_is_boosting = false
			_cooldown_timer = boost_cooldown
			boost_state_changed.emit(false)
	elif _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	if Input.is_action_just_pressed("boost") and not _is_boosting and _cooldown_timer <= 0.0:
		_is_boosting = true
		_boost_timer = boost_duration
		boost_state_changed.emit(true)
		AudioManager.play_sfx("boost")


## Single hop, timed rather than gravity-simulated: velocity.y is driven
## directly from the derivative of a height(t) = jump_height * sin(pi * t)
## arc, so move_and_slide() (which already applies velocity.x/z every
## frame) integrates it back into a clean up-then-down curve that returns
## to exactly the starting height at t = jump_duration — no floor check
## needed since there's no gravity accumulating here to begin with, same
## "no physics simulation fighting the arcade feel" reasoning the rest of
## this controller uses. is_action_just_pressed (not "pressed") plus the
## not-already-jumping guard makes this strictly single-use per press —
## holding the button doesn't chain jumps, and the cooldown below is what
## stops rapid re-presses instead.
func _update_jump(delta: float) -> void:
	if _jump_cooldown_timer > 0.0:
		_jump_cooldown_timer -= delta

	if Input.is_action_just_pressed("jump") and not _is_jumping and _jump_cooldown_timer <= 0.0:
		_is_jumping = true
		_jump_time = 0.0
		_jump_cooldown_timer = jump_cooldown
		jump_started.emit()

	if not _is_jumping:
		velocity.y = 0.0
		return

	_jump_time += delta
	var t: float = clamp(_jump_time / jump_duration, 0.0, 1.0)
	velocity.y = jump_height * PI / jump_duration * cos(t * PI)

	if t >= 1.0:
		_is_jumping = false
		velocity.y = 0.0
		jump_completed.emit()


## Distance-based ramp: forward_speed grows with chunks crossed (same
## chunk_length concept ProceduralWorld spawns scenery on), capped at
## max_speed_bonus, then the boost multiplier and any live drift-release
## bonus are layered on top.
func _get_current_forward_speed() -> float:
	var chunks_crossed := floori(-global_position.z / speed_ramp_chunk_length)
	var ramp_bonus: float = min(chunks_crossed * speed_per_chunk, max_speed_bonus)
	var speed := forward_speed + ramp_bonus
	if _is_boosting:
		speed *= boost_multiplier

	if _drift_bonus_timer > 0.0:
		speed += drift_release_speed_bonus
	return speed


## Only steering WHILE boosting builds the sideways push — steering alone
## (normal turning) and boosting alone (straight-line speed) each leave
## this at zero. That combination-gating is the point: it rewards actively
## carving during a boost rather than just holding boost in a straight line.
func _update_lateral_boost_push(delta: float, steer_input: float) -> void:
	var target := 0.0
	if _is_boosting and absf(steer_input) > steer_deadzone:
		target = sign(steer_input) * lateral_boost_max

	if absf(target) > 0.0:
		_lateral_boost_velocity = move_toward(_lateral_boost_velocity, target, lateral_boost_gain * delta)
	else:
		_lateral_boost_velocity = move_toward(_lateral_boost_velocity, 0.0, lateral_boost_decay * delta)


## Tracks how long the current steer direction has been held. Releasing
## the stick (or flipping direction, which spends the old charge without
## paying off a spin) is where charge is either cashed in or discarded.
func _update_drift_charge(delta: float, steer_input: float) -> void:
	if absf(steer_input) > steer_deadzone:
		var input_sign := signf(steer_input)
		if _steer_hold_direction == 0.0 or input_sign == _steer_hold_direction:
			_steer_hold_direction = input_sign
			_steer_hold_time += delta
		else:
			# Direction flipped mid-hold — old charge is spent, not carried
			# over into the new direction; start a fresh charge instead.
			_steer_hold_direction = input_sign
			_steer_hold_time = delta
		return

	# Input released this frame (or was never held). A long-enough hold
	# pays off with a spin; anything shorter is discarded silently.
	if _steer_hold_time >= drift_charge_threshold and not _is_drifting:
		_start_drift(_steer_hold_direction)
	_steer_hold_time = 0.0
	_steer_hold_direction = 0.0


func _start_drift(direction: float) -> void:
	_is_drifting = true
	_drift_progress = 0.0
	_drift_direction = direction if direction != 0.0 else 1.0
	drift_started.emit(_drift_direction)


## Advances the 360° roll flip and, on completion, resets rotation.z to
## exactly zero (rather than leaving it at +-TAU, and rather than leaving
## it wherever the last bank lean happened to be) and starts the short
## forward speed-bonus window as the reward for seeing the flip through.
## Deliberately rotation.z, the same axis the bank lean uses above — this
## is a barrel roll around the forward axis, not a spin-in-place around
## the vertical axis, so it's the bank lean taken all the way around
## rather than a separate motion on its own axis.
func _update_drift_spin(delta: float) -> void:
	if _drift_bonus_timer > 0.0:
		_drift_bonus_timer = max(_drift_bonus_timer - delta, 0.0)

	if not _is_drifting:
		return

	_drift_progress += delta / drift_spin_duration
	if _drift_progress >= 1.0:
		_drift_progress = 1.0
		mesh_pivot.rotation.z = 0.0
		_is_drifting = false
		_drift_bonus_timer = drift_release_bonus_duration
		drift_completed.emit()
	else:
		mesh_pivot.rotation.z = _drift_direction * _drift_progress * TAU
