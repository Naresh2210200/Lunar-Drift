extends Node
## Was the survival-energy resource through Milestone 6/7. Per explicit
## request, repurposed into a Score Multiplier Meter, Race the Sun style —
## filename and node name (MoonEnergy) kept as-is on purpose so
## player.tscn and hud.gd's existing node paths don't need touching, but
## everything this node actually DOES is now about the multiplier, not
## survival. All drain-to-zero-means-game-over logic is gone: running the
## meter empty just means you're sitting at the 1x floor, not that the run
## ends (player.gd no longer listens for a depletion signal at all).

## Emitted whenever the meter's fill changes, for the HUD bar — same
## (current, max_value) shape the old energy_changed had, renamed for
## clarity since hud.gd is being updated to match anyway.
signal multiplier_meter_changed(current: float, max_value: float)
## Emitted only when the actual multiplier TIER changes (1/2/3/4x), not
## on every partial fill — separate from the per-frame meter signal above
## so the HUD can react to a tier-up distinctly (flash, sound hook later)
## instead of re-parsing the meter fraction every frame to infer it.
signal multiplier_changed(new_multiplier: int)

@export var max_meter: float = 100.0
@export var max_multiplier: int = 4
## Seconds since the last collection before the meter starts bleeding back
## down. Not from run start — only counts idle time between pickups.
@export var idle_timeout: float = 4.0
## Meter units per second lost once idle_timeout has passed.
@export var decay_rate: float = 18.0

var current_meter: float = 0.0
var current_multiplier: int = 1

var _idle_timer: float = 0.0


func _ready() -> void:
	current_meter = 0.0
	current_multiplier = 1
	multiplier_meter_changed.emit(current_meter, max_meter)
	multiplier_changed.emit(current_multiplier)


func _process(delta: float) -> void:
	if current_multiplier <= 1 and current_meter <= 0.0:
		return  # already at the floor — nothing left to decay

	_idle_timer += delta
	if _idle_timer < idle_timeout:
		return

	current_meter -= decay_rate * delta
	if current_meter <= 0.0:
		if current_multiplier > 1:
			current_multiplier -= 1
			multiplier_changed.emit(current_multiplier)
			current_meter = max_meter  # keep melting through the tier below, same idle streak
		else:
			current_meter = 0.0
	multiplier_meter_changed.emit(current_meter, max_meter)


## Called on every Shade pickup. Fills the meter; a full meter advances
## the multiplier a tier and carries the overflow into the next tier's
## bar rather than losing it, so back-to-back pickups near a tier-up don't
## feel like wasted progress. Capped at max_multiplier — extra fill past
## that just tops the bar out instead of erroring past 100%.
func add_progress(amount: float) -> void:
	_idle_timer = 0.0
	current_meter += amount

	while current_meter >= max_meter and current_multiplier < max_multiplier:
		current_meter -= max_meter
		current_multiplier += 1
		multiplier_changed.emit(current_multiplier)

	if current_multiplier >= max_multiplier:
		current_meter = min(current_meter, max_meter)

	multiplier_meter_changed.emit(current_meter, max_meter)
