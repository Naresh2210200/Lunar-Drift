extends Control
## Subway Surfers-style "continue with currency" revive prompt. Self-
## contained and reusable — hud.gd instances this as a child, connects
## its `declined` signal to _show_game_over(), and calls open() from
## _on_game_state_changed() the moment GAME_OVER fires, BEFORE the Run
## Complete panel would otherwise show. The Run Complete panel only
## appears if `declined` fires (skipped, timed out, or couldn't afford
## it) — see hud.gd's _ready()/_on_game_state_changed().
##
## Score is deliberately untouched here — see player.gd, _score_accum is
## a running total that just stops accumulating while GameManager.
## current_state != PLAYING (see player.gd _physics_process's early-out).
## Simply flipping back to PLAYING resumes the same run, same score,
## same position — no explicit "continue from same score" bookkeeping
## needed on this end.
##
## TODO(wiring): this assumes an EconomyManager API inferred from the
## rest of the project but not fully confirmed —
##   - EconomyManager.shards: int          (confirmed — read in hud.gd)
##   - EconomyManager.spend_shards(n) -> bool   (deduct n, false if short)
## EconomyManager.add_shards() and the shards/shards_changed pairing are
## confirmed elsewhere (player.gd, hud.gd), but a matching spend method
## wasn't in any file seen so far — rename _try_spend_shards()'s single
## call site below if the real method differs, or add spend_shards() to
## EconomyManager.gd if it doesn't exist yet.

signal continued
signal declined

@export var continue_cost: int = 50
@export var countdown_seconds: float = 5.0

@onready var _panel: PanelContainer = $Panel
@onready var _cost_label: Label = %CostLabel
@onready var _status_label: Label = %StatusLabel
@onready var _timer_bar: ProgressBar = %TimerBar
@onready var _continue_button: Button = %ContinueButton
@onready var _watch_ad_button: Button = %WatchAdButton
@onready var _skip_button: Button = %SkipButton

var _time_left: float = 0.0
var _open: bool = false

## Once per RUN, not once per death within a run — this node is a child
## of hud.gd, which only exists for the lifetime of one main.tscn
## instance (restart/main-menu both leave via reload_current_scene() or
## change_scene_to_file(), both of which tear this node down), so a
## plain instance var that starts false is enough; no explicit reset
## needed anywhere.
var _ad_continue_used_this_run: bool = false
var _ad_in_progress: bool = false


func _ready() -> void:
	visible = false
	set_process(false)
	_continue_button.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	_watch_ad_button.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	_skip_button.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	_continue_button.pressed.connect(_on_continue_pressed)
	_watch_ad_button.pressed.connect(_on_watch_ad_pressed)
	_skip_button.pressed.connect(_on_skip_pressed)
	_cost_label.text = "Continue for %d Shades" % continue_cost


## Public entry point — call this once per death, right when the run
## ends, instead of immediately showing a final game-over screen. Now
## called by hud.gd's show_continue_prompt(), itself called by
## DeathSequence once its camera turn-around has settled — so this is
## already arriving as the payoff of a cinematic beat, not a cold open.
## The fade + scale-pop below is this prompt's own contribution to that
## feel, so it stays self-contained (open() can still be called from
## anywhere and looks right) rather than depending on the caller to
## animate it in.
func open() -> void:
	_open = true
	_time_left = countdown_seconds
	_status_label.text = ""
	_continue_button.disabled = false
	_timer_bar.max_value = countdown_seconds
	_timer_bar.value = countdown_seconds

	# Once-per-run gate — see _ad_continue_used_this_run's doc comment.
	# Hidden rather than just disabled once used, so a second death this
	# run reads as "that option's gone" rather than "still there but
	# broken."
	_watch_ad_button.visible = not _ad_continue_used_this_run
	_watch_ad_button.disabled = false

	visible = true
	modulate.a = 0.0
	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2.ONE * 0.85

	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	set_process(true)


func _process(delta: float) -> void:
	if not _open:
		return
	# Freeze the countdown while an ad is actually playing — a rewarded
	# ad can easily run longer than countdown_seconds (5s default), and
	# the whole point of watching it is to buy a revive, not to have the
	# prompt time out and decline underneath the player mid-ad.
	if _ad_in_progress:
		return
	_time_left -= delta
	_timer_bar.value = maxf(_time_left, 0.0)
	if _time_left <= 0.0:
		_close(false)


func _on_continue_pressed() -> void:
	if not _open:
		return
	if not _try_spend_shards(continue_cost):
		# Not enough Shades — leave the prompt open (countdown keeps
		# running) but tell the player why the button didn't work,
		# rather than silently doing nothing.
		_status_label.text = "Not enough Shades"
		return
	_grant_world_grace()
	GameManager.change_state(GameManager.GameState.PLAYING)
	_close(true)


func _on_skip_pressed() -> void:
	_close(false)


## Same "watch a rewarded ad" flow as shop.gd's _on_watch_ad_pressed(),
## but the reward here is the revive itself (via the shared
## _grant_world_grace() + GameManager.change_state() path _on_continue_
## pressed() already uses) rather than a Shades payout — no
## EconomyManager call on success.
func _on_watch_ad_pressed() -> void:
	if not _open or _ad_in_progress or _ad_continue_used_this_run:
		return
	_ad_in_progress = true
	_watch_ad_button.disabled = true
	_continue_button.disabled = true
	_status_label.text = "Loading ad..."
	_play_rewarded_ad()


## Mirrors shop.gd's _play_rewarded_ad() exactly — same autoload-by-name
## detection (has_node/has_signal/has_method) against "AdManager", same
## show_rewarded_ad()/rewarded_ad_completed/rewarded_ad_failed contract.
## See autoloads/ad_manager.gd for what actually backs that interface.
func _play_rewarded_ad() -> void:
	if has_node("/root/AdManager"):
		var ad_manager: Node = get_node("/root/AdManager")
		if ad_manager.has_signal("rewarded_ad_completed") and ad_manager.has_signal("rewarded_ad_failed") \
				and ad_manager.has_method("show_rewarded_ad"):
			ad_manager.rewarded_ad_completed.connect(_on_watch_ad_completed, CONNECT_ONE_SHOT)
			ad_manager.rewarded_ad_failed.connect(_on_watch_ad_failed, CONNECT_ONE_SHOT)
			ad_manager.show_rewarded_ad()
			return

	# No AdManager wired up — same graceful no-op stance as
	# show_interstitial_ad() taking a no-op path elsewhere; the button
	# just goes back to normal and the player can still pay Shades or
	# skip instead.
	_on_watch_ad_failed()


func _on_watch_ad_completed() -> void:
	if not _open:
		return
	_ad_in_progress = false
	_ad_continue_used_this_run = true
	_grant_world_grace()
	GameManager.change_state(GameManager.GameState.PLAYING)
	_close(true)


func _on_watch_ad_failed() -> void:
	_ad_in_progress = false
	if not _open:
		return
	_continue_button.disabled = false
	_watch_ad_button.disabled = false
	_status_label.text = "Ad not available — try again later"


## Isolated in its own function per the wiring TODO above — this is the
## one line to change if the real EconomyManager method has a different
## name/signature.
func _try_spend_shards(amount: int) -> bool:
	if EconomyManager.shards < amount:
		return false
	return EconomyManager.spend_shards(amount)


## ProceduralWorld registers itself into the "procedural_world" group in
## its own _ready() specifically so this lookup doesn't need a NodePath
## wired per-scene — see grant_continue_grace()'s doc comment there for
## what this actually clears.
func _grant_world_grace() -> void:
	var world := get_tree().get_first_node_in_group("procedural_world")
	if world and world.has_method("grant_continue_grace"):
		world.grant_continue_grace()
	else:
		push_warning("continue_prompt.gd: no 'procedural_world' group node with grant_continue_grace() found — continuing without a safe-zone clear.")


func _close(did_continue: bool) -> void:
	_open = false
	set_process(false)
	visible = false
	if did_continue:
		continued.emit()
	else:
		declined.emit()
