extends Node
## HighScoreManager (autoload)
##
## The one other deliberate global singleton besides GameManager — same
## justification: persistent best-score data needs to survive both scene
## changes (main menu <-> gameplay) and, unlike everything else in this
## project, actual game restarts (get_tree().reload_current_scene()
## doesn't touch autoloads, but it also doesn't touch a value that needs
## to persist ACROSS runs, which a plain scene-tree node can't do either
## way). A CanvasLayer HUD node reaching into a save file directly would
## mean every future screen that wants the high score (main menu, HUD,
## game over) re-implementing load/save — same "one narrow owner" reasoning
## GameManager's own header comment gives for itself.
##
## Deliberately NOT using ConfigFile/JSON for a single integer — FileAccess
## reading/writing one plain int is the simplest thing that's actually
## correct here. Revisit if more persistent fields show up later (settings,
## unlocks, etc.) and a single int stops being enough.

const SAVE_PATH := "user://lunar_drift_highscore.save"

signal high_score_changed(new_high_score: int)

var high_score: int = 0


func _ready() -> void:
	high_score = _load_high_score()


## Call with the run's final score. Returns true if it's a new record
## (so callers — the Game Over screen — can show a "New Best!" without
## needing to compare against the old value themselves).
func report_score(score: int) -> bool:
	if score <= high_score:
		return false
	high_score = score
	_save_high_score(high_score)
	high_score_changed.emit(high_score)
	return true


func _load_high_score() -> int:
	if not FileAccess.file_exists(SAVE_PATH):
		return 0
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("HighScoreManager: save file exists but couldn't be opened — starting from 0.")
		return 0
	var value := file.get_32()
	file.close()
	return value


func _save_high_score(value: int) -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("HighScoreManager: couldn't open save file for writing — high score won't persist this run.")
		return
	file.store_32(value)
	file.close()
