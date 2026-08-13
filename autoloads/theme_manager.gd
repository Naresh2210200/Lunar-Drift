extends Node
## ThemeManager (autoload)
##
## Fourth deliberate global singleton, after GameManager/HighScoreManager/
## EconomyManager — same narrow-owner shape as all three: this tracks
## which color theme the run is currently in and tells everyone else when
## it changes via `theme_changed`. It does NOT reach into the water
## shader, the sky/fog, or the moon directly — those systems each listen
## to the signal and apply the new palette to themselves.
##
## SCOPE, per explicit request: this only retints the ENVIRONMENT — water,
## fog/sky background, and the moon's glow/light color. Obstacles and all
## other scenery stay strictly black/white/gray always; ProceduralWorld
## does NOT listen to this signal at all anymore, on purpose.
##
## Cycle is Sketch -> Water -> Lava -> Sketch -> ... every
## SCORE_PER_THEME_CHANGE points, looping forever for the rest of a run.

enum ThemeId { SKETCH, WATER, LAVA }

const SCORE_PER_THEME_CHANGE := 15000

signal theme_changed(theme_id: ThemeId, theme: Dictionary)

## One Dictionary per theme. WATER and LAVA are deliberately bright/
## saturated (anime/toon-style, high contrast between the two water-layer
## colors) rather than realistic or washed-out — per explicit request
## after the first pass read as too light/pale. SKETCH is untouched, the
## project's original pale monochrome water.
const _THEMES := {
	ThemeId.SKETCH: {
		"name": "Sketch",
		"water_col": Color(0.86, 0.86, 0.88),
		"water2_col": Color(0.06, 0.06, 0.07),
		"foam_col": Color(0.98, 0.98, 0.97),
		"background_color": Color(0.9, 0.9, 0.91),
		"fog_color": Color(0.9, 0.9, 0.91),
		"ambient_color": Color(0.8, 0.8, 0.8),
		"moon_glow_color": Color(1.0, 0.98, 0.94),
		"moon_light_color": Color(1.0, 1.0, 1.0),
		"moon_glow_strength": 0.8,
	},
	ThemeId.WATER: {
		"name": "Water",
		# Vivid, saturated cyan-blue over a near-navy second layer — bold
		# toon-style contrast instead of a realistic soft gradient.
		"water_col": Color(0.0, 0.7, 1.0),
		"water2_col": Color(0.0, 0.1, 0.55),
		"foam_col": Color(0.85, 1.0, 1.0),
		"background_color": Color(0.25, 0.65, 1.0),
		"fog_color": Color(0.35, 0.75, 1.0),
		"ambient_color": Color(0.35, 0.65, 0.95),
		"moon_glow_color": Color(0.7, 0.95, 1.0),
		"moon_light_color": Color(0.65, 0.9, 1.0),
		"moon_glow_strength": 0.9,
	},
	ThemeId.LAVA: {
		"name": "Lava",
		# Bright orange/yellow molten-rock mix per the reference image —
		# hot orange primary, deep red-black second layer for contrast,
		# and a near-white-yellow foam standing in for churning lava
		# highlights. Punched well past "realistic lava" on purpose.
		"water_col": Color(1.0, 0.45, 0.0),
		"water2_col": Color(0.5, 0.02, 0.0),
		"foam_col": Color(1.0, 0.85, 0.05),
		"background_color": Color(1.0, 0.4, 0.05),
		"fog_color": Color(1.0, 0.45, 0.1),
		"ambient_color": Color(0.9, 0.35, 0.05),
		"moon_glow_color": Color(1.0, 0.6, 0.1),
		"moon_light_color": Color(1.0, 0.5, 0.15),
		"moon_glow_strength": 1.3,
	},
}

var current_theme_id: ThemeId = ThemeId.SKETCH
var _last_tier: int = 0  # how many SCORE_PER_THEME_CHANGE tiers crossed so far this run


## Call this every time the run's score changes (hud.gd's
## _on_score_changed does) — cheap no-op unless a fresh tier was actually
## crossed this call. Deliberately takes the raw running score rather
## than a pre-computed "did we cross a tier" bool, so callers don't need
## their own division/modulo — same "manager owns the math" reasoning as
## HighScoreManager.report_score.
func report_score(score: int) -> void:
	var tier := int(floor(float(score) / float(SCORE_PER_THEME_CHANGE)))
	if tier == _last_tier:
		return
	_last_tier = tier
	var new_theme_id: ThemeId = (tier % ThemeId.size()) as ThemeId
	if new_theme_id == current_theme_id:
		return
	current_theme_id = new_theme_id
	theme_changed.emit(current_theme_id, _THEMES[current_theme_id])
	print("ThemeManager: theme -> ", _THEMES[current_theme_id]["name"])


## Resets back to Sketch and zeroes the tier counter — call this on
## restart/reload (see hud.gd's _on_restart_pressed) so a new run always
## opens on Sketch instead of wherever the previous run's score left the
## cycle. Emits theme_changed only if something actually needs to revert.
func reset() -> void:
	_last_tier = 0
	if current_theme_id != ThemeId.SKETCH:
		current_theme_id = ThemeId.SKETCH
		theme_changed.emit(current_theme_id, _THEMES[current_theme_id])


## Lets a listener that starts up AFTER the last theme_changed already
## fired (e.g. a scene reload mid-run, or a UI panel opened late) pull the
## current palette once instead of staying stuck on Sketch until the next
## 50000-score crossing.
func get_current_theme() -> Dictionary:
	return _THEMES[current_theme_id]
