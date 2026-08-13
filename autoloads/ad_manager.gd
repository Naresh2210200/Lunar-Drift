extends Node
## autoload/ad_manager.gd
##
## Wraps the Poing Studios AdMob plugin (https://github.com/poingstudios/godot-admob-plugin)
## behind the interface shop.gd was already written against:
##   - show_rewarded_ad() -> void
##   - signal rewarded_ad_completed
##   - signal rewarded_ad_failed
## shop.gd auto-detects this autoload by name ("AdManager") and switches
## from its simulated ad over to this the moment it's registered — no
## changes needed on the shop.gd side.
##
## SETUP REQUIRED (one-time, in the editor):
##   1. Install the AdMob plugin (AssetLib -> search "AdMob", publisher
##      Poing Studios) and enable it under Project -> Project Settings ->
##      Plugins.
##   2. Project -> Project Settings -> Admob -> General -> Android:
##      check Enabled, paste the App ID below into "App Id".
##        App ID: ca-app-pub-5393182989063953~5552742363
##      (This is separate from the ad unit ID below — the App ID goes in
##      Project Settings, the ad unit ID goes in code.)
##   3. Add this script as an autoload named exactly "AdManager":
##      Project -> Project Settings -> Autoload -> path=this file, name=AdManager.
##      It must be listed ABOVE (or it doesn't matter relative to)
##      EconomyManager/AudioManager since it doesn't depend on them.
##
## TODO(ios): only an Android ad unit ID has been provided so far. The
## iOS branch below falls back to Google's public rewarded test unit so
## nothing crashes if this ever runs on iOS — swap ANDROID/IOS_REWARDED_
## AD_UNIT_ID for the real iOS ID once it exists, and repeat step 2 above
## under the iOS section of Project Settings.
##
## INTERSTITIAL AD (added for continue_prompt.gd's "watch ad to continue"
## and hud.gd's "ad after every completed run"): same plugin, same
## request/load/show shape as the rewarded ad above, just the
## Interstitial* classes instead of Rewarded* ones and no reward
## listener. show_interstitial_ad() is the public entry point — mirrors
## show_rewarded_ad()'s "show cached one if ready, else load-then-show"
## behavior. Ad unit ID below is Google's public interstitial TEST ID —
## same TODO as the rewarded ID above: swap for the real one from the
## AdMob console (and repeat Project Settings step 2, under whatever ad
## type/unit row the console gives an interstitial) before release.

const ANDROID_REWARDED_AD_UNIT_ID := "ca-app-pub-5393182989063953/8370597535"
const IOS_REWARDED_AD_UNIT_ID := "ca-app-pub-3940256099942544/1712485313"  # TODO(ios): test ID placeholder

## TODO: Android ID below is Google's public interstitial TEST unit — swap
## for the real one from the AdMob console before release (see the class
## doc comment above). iOS uses the same public test ID for now, same as
## the rewarded ad's TODO(ios).
const ANDROID_INTERSTITIAL_AD_UNIT_ID := "ca-app-pub-3940256099942544/1033173712"  # TODO: test ID placeholder
const IOS_INTERSTITIAL_AD_UNIT_ID := "ca-app-pub-3940256099942544/4411468910"  # TODO(ios): test ID placeholder

signal rewarded_ad_completed
signal rewarded_ad_failed

signal interstitial_ad_dismissed
signal interstitial_ad_failed

var _rewarded_ad: RewardedAd = null
var _is_loading: bool = false
var _show_requested: bool = false
var _reward_earned: bool = false

var _interstitial_ad: InterstitialAd = null
var _interstitial_is_loading: bool = false
var _interstitial_show_requested: bool = false

var _full_screen_content_callback := FullScreenContentCallback.new()
var _user_earned_reward_listener := OnUserEarnedRewardListener.new()
var _rewarded_ad_load_callback := RewardedAdLoadCallback.new()

var _interstitial_full_screen_content_callback := FullScreenContentCallback.new()
var _interstitial_ad_load_callback := InterstitialAdLoadCallback.new()


func _ready() -> void:
	_full_screen_content_callback.on_ad_showed_full_screen_content = _on_ad_showed_full_screen_content
	_full_screen_content_callback.on_ad_dismissed_full_screen_content = _on_ad_dismissed_full_screen_content
	_full_screen_content_callback.on_ad_failed_to_show_full_screen_content = _on_ad_failed_to_show_full_screen_content

	_user_earned_reward_listener.on_user_earned_reward = _on_user_earned_reward

	_rewarded_ad_load_callback.on_ad_loaded = _on_ad_loaded
	_rewarded_ad_load_callback.on_ad_failed_to_load = _on_ad_failed_to_load

	_interstitial_full_screen_content_callback.on_ad_showed_full_screen_content = _on_interstitial_showed_full_screen_content
	_interstitial_full_screen_content_callback.on_ad_dismissed_full_screen_content = _on_interstitial_dismissed_full_screen_content
	_interstitial_full_screen_content_callback.on_ad_failed_to_show_full_screen_content = _on_interstitial_failed_to_show_full_screen_content

	_interstitial_ad_load_callback.on_ad_loaded = _on_interstitial_loaded
	_interstitial_ad_load_callback.on_ad_failed_to_load = _on_interstitial_failed_to_load

	# Only needs to happen once, ideally at app launch.
	MobileAds.initialize()

	# Warm both caches so the first "Watch Ad" tap in the shop/continue
	# prompt, and the first run-complete interstitial, don't have to wait
	# on a network round trip.
	_load_rewarded_ad()
	_load_interstitial_ad()


## Public API — this is the only method shop.gd calls.
func show_rewarded_ad() -> void:
	if _rewarded_ad:
		_show_ad()
		return

	# Nothing cached yet (first launch, or previous ad was just used).
	# Ask for a fresh one and show it the moment it lands; if it can't
	# be loaded, rewarded_ad_failed fires from _on_ad_failed_to_load.
	_show_requested = true
	if not _is_loading:
		_load_rewarded_ad()


## Public API — call once per completed run (hud.gd's _show_game_over()),
## not on every death/continue, so a player who keeps paying Shades to
## continue mid-run isn't interrupted by an interstitial between lives.
## No reward involved — just shows if one's ready and otherwise loads
## then shows, same "cached or load-then-show" shape as
## show_rewarded_ad(). Silently no-ops (no signal fires) if the plugin
## can't produce one at all — a missing interstitial shouldn't block
## returning to the menu.
func show_interstitial_ad() -> void:
	if _interstitial_ad:
		_show_interstitial_ad()
		return

	_interstitial_show_requested = true
	if not _interstitial_is_loading:
		_load_interstitial_ad()


func _current_unit_id() -> String:
	return ANDROID_REWARDED_AD_UNIT_ID if OS.get_name() == "Android" else IOS_REWARDED_AD_UNIT_ID


func _current_interstitial_unit_id() -> String:
	return ANDROID_INTERSTITIAL_AD_UNIT_ID if OS.get_name() == "Android" else IOS_INTERSTITIAL_AD_UNIT_ID


func _load_rewarded_ad() -> void:
	if _is_loading:
		return
	_is_loading = true

	if _rewarded_ad:
		_rewarded_ad.destroy()
		_rewarded_ad = null

	RewardedAdLoader.new().load(_current_unit_id(), AdRequest.new(), _rewarded_ad_load_callback)


func _show_ad() -> void:
	_reward_earned = false
	_rewarded_ad.full_screen_content_callback = _full_screen_content_callback
	_rewarded_ad.show(_user_earned_reward_listener)


func _load_interstitial_ad() -> void:
	if _interstitial_is_loading:
		return
	_interstitial_is_loading = true

	if _interstitial_ad:
		_interstitial_ad.destroy()
		_interstitial_ad = null

	InterstitialAdLoader.new().load(_current_interstitial_unit_id(), AdRequest.new(), _interstitial_ad_load_callback)


func _show_interstitial_ad() -> void:
	_interstitial_ad.full_screen_content_callback = _interstitial_full_screen_content_callback
	_interstitial_ad.show()


# ---------------------------------------------------------------------
# RewardedAdLoadCallback
# ---------------------------------------------------------------------

func _on_ad_loaded(rewarded_ad: RewardedAd) -> void:
	_is_loading = false
	_rewarded_ad = rewarded_ad

	if _show_requested:
		_show_requested = false
		_show_ad()


func _on_ad_failed_to_load(ad_error: LoadAdError) -> void:
	_is_loading = false
	push_warning("AdManager: rewarded ad failed to load — %s" % ad_error.message)

	if _show_requested:
		_show_requested = false
		rewarded_ad_failed.emit()


# ---------------------------------------------------------------------
# InterstitialAdLoadCallback
# ---------------------------------------------------------------------

func _on_interstitial_loaded(interstitial_ad: InterstitialAd) -> void:
	_interstitial_is_loading = false
	_interstitial_ad = interstitial_ad

	if _interstitial_show_requested:
		_interstitial_show_requested = false
		_show_interstitial_ad()


func _on_interstitial_failed_to_load(ad_error: LoadAdError) -> void:
	_interstitial_is_loading = false
	push_warning("AdManager: interstitial ad failed to load — %s" % ad_error.message)

	if _interstitial_show_requested:
		_interstitial_show_requested = false
		interstitial_ad_failed.emit()


# ---------------------------------------------------------------------
# FullScreenContentCallback
# ---------------------------------------------------------------------

func _on_ad_showed_full_screen_content() -> void:
	pass


## Fires whether or not a reward was earned, so this is where the final
## completed/failed signal actually gets decided and emitted — the user
## can always close the ad early without watching it through.
func _on_ad_dismissed_full_screen_content() -> void:
	if _reward_earned:
		rewarded_ad_completed.emit()
	else:
		rewarded_ad_failed.emit()

	if _rewarded_ad:
		_rewarded_ad.destroy()
		_rewarded_ad = null

	# Refill the cache for next time.
	_load_rewarded_ad()


func _on_ad_failed_to_show_full_screen_content(ad_error: AdError) -> void:
	push_warning("AdManager: rewarded ad failed to show — %s" % ad_error.message)
	rewarded_ad_failed.emit()

	if _rewarded_ad:
		_rewarded_ad.destroy()
		_rewarded_ad = null

	_load_rewarded_ad()


# ---------------------------------------------------------------------
# OnUserEarnedRewardListener
# ---------------------------------------------------------------------

func _on_user_earned_reward(rewarded_item: RewardedItem) -> void:
	_reward_earned = true
	# rewarded_item.amount / rewarded_item.type are available here if the
	# AdMob-side reward amount should ever replace shop.gd's own
	# ad_reward_amount — not wired up since shop.gd controls the payout
	# itself today.


# ---------------------------------------------------------------------
# Interstitial FullScreenContentCallback
# ---------------------------------------------------------------------

func _on_interstitial_showed_full_screen_content() -> void:
	pass


## No reward to decide here, unlike the rewarded ad's dismiss handler —
## an interstitial is just watched-or-skipped, so this always fires
## interstitial_ad_dismissed and refills the cache for next time.
func _on_interstitial_dismissed_full_screen_content() -> void:
	interstitial_ad_dismissed.emit()

	if _interstitial_ad:
		_interstitial_ad.destroy()
		_interstitial_ad = null

	_load_interstitial_ad()


func _on_interstitial_failed_to_show_full_screen_content(ad_error: AdError) -> void:
	push_warning("AdManager: interstitial ad failed to show — %s" % ad_error.message)
	interstitial_ad_failed.emit()

	if _interstitial_ad:
		_interstitial_ad.destroy()
		_interstitial_ad = null

	_load_interstitial_ad()
