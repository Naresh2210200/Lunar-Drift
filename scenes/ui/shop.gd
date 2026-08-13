extends Control
## scenes/ui/shop.gd
##
## Shop screen: shows the current Shards balance, lets the player watch
## a rewarded ad for a top-up, and Back returns to the main menu. No
## script existed for this scene before this — shop.tscn had a
## BackButton, ShardsLabel, WatchAdButton, etc. sitting there with
## nothing driving any of them, which is why Back (and everything else
## here) did nothing.
##
## TODO(wiring): rewarded-ad integration is inferred, not confirmed —
## no AdManager autoload/plugin exists anywhere in the project yet.
## _play_rewarded_ad() below checks for an autoload named "AdManager"
## with:
##   - show_rewarded_ad() -> void
##   - signal rewarded_ad_completed
##   - signal rewarded_ad_failed
## and uses it if present. If it's not there, this falls back to a
## short simulated "ad" (see _simulate_ad()) so the whole reward flow
## (button disable, status text, payout, toast) is testable right now —
## swap in the real plugin later by rewriting _play_rewarded_ad() only.
##
## TODO(edge-gesture fix): BackButton used to sit flush at Header's
## offset_left = 32, which on some Android OEM skins (Samsung
## especially) falls inside the reserved edge-swipe-back strip and can
## eat the touch-down before Godot's UI sees it as a tap. The layout
## has been pushed in to offset_left = 64 as an immediate fix (see
## shop.tscn). The durable fix is a small native Android plugin that
## calls View.setSystemGestureExclusionRects() for this button's rect;
## _register_gesture_exclusion() below checks for an autoload named
## "AndroidGestureExclusion" with a set_rect(x, y, w, h) -> void method
## and uses it if present, so it's a no-op until that plugin exists.

const MAIN_MENU_SCENE_PATH := "res://scenes/ui/main_menu.tscn"

@export var ad_reward_amount: int = 25
@export var simulated_ad_duration: float = 2.0

@onready var _shards_label: Label = $Header/ShardsPill/ShardsLabel
@onready var _back_button: Button = $Header/BackButton
@onready var _watch_ad_button: Button = $Content/AdCard/AdCardMargin/AdCardVBox/WatchAdButton
@onready var _ad_status_label: Label = $Content/AdCard/AdCardMargin/AdCardVBox/AdStatusLabel
@onready var _reward_toast: Panel = $RewardToast
@onready var _reward_toast_label: Label = $RewardToast/RewardToastLabel

var _ad_in_progress: bool = false


func _ready() -> void:
	_reward_toast.visible = false
	_reward_toast.modulate.a = 0.0
	_ad_status_label.text = ""

	_back_button.pressed.connect(_on_back_pressed)
	_watch_ad_button.pressed.connect(_on_watch_ad_pressed)

	_update_shards_label(EconomyManager.shards)
	EconomyManager.shards_changed.connect(_update_shards_label)

	_register_gesture_exclusion()


func _on_back_pressed() -> void:
	AudioManager.play_sfx("button_press")
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _update_shards_label(current: int) -> void:
	_shards_label.text = "%d Shades" % current


## Isolated per the TODO above — a no-op today, becomes live the
## moment an "AndroidGestureExclusion" autoload with set_rect(x, y, w, h)
## exists. Uses the button's actual on-screen rect so it stays correct
## if the layout changes again later.
func _register_gesture_exclusion() -> void:
	if not has_node("/root/AndroidGestureExclusion"):
		return
	var exclusion: Node = get_node("/root/AndroidGestureExclusion")
	if not exclusion.has_method("set_rect"):
		return
	var rect: Rect2 = _back_button.get_global_rect()
	exclusion.set_rect(rect.position.x, rect.position.y, rect.size.x, rect.size.y)


# ---------------------------------------------------------------------
# Watch Ad
# ---------------------------------------------------------------------

func _on_watch_ad_pressed() -> void:
	if _ad_in_progress:
		return
	_ad_in_progress = true
	_watch_ad_button.disabled = true
	_ad_status_label.text = "Loading ad..."
	AudioManager.play_sfx("button_press")
	_play_rewarded_ad()


## Isolated per the wiring TODO above — the one function to rewrite
## once a real ad plugin is in the project.
func _play_rewarded_ad() -> void:
	if has_node("/root/AdManager"):
		var ad_manager: Node = get_node("/root/AdManager")
		if ad_manager.has_signal("rewarded_ad_completed") and ad_manager.has_signal("rewarded_ad_failed") \
				and ad_manager.has_method("show_rewarded_ad"):
			ad_manager.rewarded_ad_completed.connect(_on_ad_completed, CONNECT_ONE_SHOT)
			ad_manager.rewarded_ad_failed.connect(_on_ad_failed, CONNECT_ONE_SHOT)
			ad_manager.show_rewarded_ad()
			return
	# No AdManager wired up yet — simulate the wait so the reward flow
	# is still fully testable.
	_simulate_ad()


func _simulate_ad() -> void:
	await get_tree().create_timer(simulated_ad_duration).timeout
	_on_ad_completed()


func _on_ad_completed() -> void:
	_ad_in_progress = false
	_watch_ad_button.disabled = false
	_ad_status_label.text = ""
	EconomyManager.add_shards(ad_reward_amount)
	_show_reward_toast()


func _on_ad_failed() -> void:
	_ad_in_progress = false
	_watch_ad_button.disabled = false
	_ad_status_label.text = "Ad not available — try again later"


func _show_reward_toast() -> void:
	_reward_toast_label.text = "+%d Shades!" % ad_reward_amount
	_reward_toast.visible = true
	var tween := create_tween()
	tween.tween_property(_reward_toast, "modulate:a", 1.0, 0.2)
	tween.tween_interval(1.4)
	tween.tween_property(_reward_toast, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): _reward_toast.visible = false)
