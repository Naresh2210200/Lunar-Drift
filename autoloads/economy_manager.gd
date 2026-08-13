extends Node
## EconomyManager (autoload)
##
## Third deliberate global singleton, after GameManager and
## HighScoreManager — same justification as HighScoreManager's own header:
## Shard balance and owned cosmetics need to survive scene changes (menu
## <-> gameplay <-> store) and actual game restarts, which nothing else in
## the project already owns.
##
## Save format is a single Dictionary via store_var/get_var rather than a
## lone int — this is the exact "point to revisit" HighScoreManager's own
## header comment flagged in advance: once more than one field needs to
## persist together (a balance AND a set of owned IDs), store_var/get_var
## is the simplest thing that's still correct, without reaching for JSON
## or a database for two fields.
const SAVE_PATH := "user://lunar_drift_economy.save"
const STARTING_SHARDS := 50  # enough for one cheap cosmetic on first launch
signal shards_changed(new_total: int)
signal cosmetic_unlocked(item_id: String)
var shards: int = 0
var _owned_ids: Dictionary = {}  # item_id (String) -> true; Dictionary-as-set
func _ready() -> void:
	_load()
func is_owned(item_id: String) -> bool:
	return _owned_ids.has(item_id)
func add_shards(amount: int) -> void:
	if amount <= 0:
		return
	shards += amount
	shards_changed.emit(shards)
	_save()
## Returns true if `amount` was deducted, false if the balance couldn't
## cover it (balance is left untouched on failure). Used by things like
## the continue-with-currency prompt, which aren't tied to a CosmeticItem
## the way purchase() is.
func spend_shards(amount: int) -> bool:
	if amount <= 0:
		return true
	if shards < amount:
		return false
	shards -= amount
	shards_changed.emit(shards)
	_save()
	return true
## Returns true if the purchase succeeded, false if already owned or
## unaffordable. The caller (a Store card) decides how to communicate
## failure — this just reports pass/fail, it doesn't own any UI feedback.
func purchase(item: CosmeticItem) -> bool:
	if item == null or is_owned(item.id):
		return false
	if shards < item.cost:
		return false
	shards -= item.cost
	_owned_ids[item.id] = true
	shards_changed.emit(shards)
	cosmetic_unlocked.emit(item.id)
	_save()
	return true
func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		shards = STARTING_SHARDS
		_save()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("EconomyManager: save file exists but couldn't be opened — starting from defaults.")
		shards = STARTING_SHARDS
		return
	var data: Variant = file.get_var()
	file.close()
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("EconomyManager: save file was unreadable — starting from defaults.")
		shards = STARTING_SHARDS
		return
	shards = data.get("shards", STARTING_SHARDS)
	_owned_ids = data.get("owned", {})
func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("EconomyManager: couldn't open save file for writing — progress won't persist this run.")
		return
	file.store_var({"shards": shards, "owned": _owned_ids})
	file.close()
