extends Control
## scenes/ui/loading_screen.gd
##
## Threaded-load splash shown between menu and gameplay so heavy
## main.tscn resources (terrain, player, audio) finish loading before
## the scene actually swaps in, instead of the hitch/blank-frame you
## get from a bare change_scene_to_file() on a heavy scene.
##
## Doesn't know or care who sent the player here — whoever does (see
## main_menu.gd's _on_play_pressed -> _go_to_loading_screen) just sets
## target_scene_path on the instance BEFORE adding it to the tree, then
## this scene loads that path on its own and swaps to it when ready.

@export var target_scene_path: String = ""
## Floor on how long the screen stays up even if the load finishes
## instantly (e.g. main.tscn already cached) — stops it flashing by in
## a single frame, which reads as a glitch rather than a loading screen.
@export var min_display_time: float = 0.5

@onready var _status_label: Label = %StatusLabel
@onready var _progress_bar: ProgressBar = %ProgressBar

var _started_at: float = 0.0


func _ready() -> void:
	if target_scene_path == "":
		push_error("loading_screen.gd: no target_scene_path set — nothing to load.")
		return
	_progress_bar.value = 0.0
	_status_label.text = "Loading..."
	_started_at = Time.get_ticks_msec() / 1000.0
	ResourceLoader.load_threaded_request(target_scene_path)
	set_process(true)


func _process(_delta: float) -> void:
	var progress: Array = []
	var status: int = ResourceLoader.load_threaded_get_status(target_scene_path, progress)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if progress.size() > 0:
				_progress_bar.value = progress[0] * 100.0
		ResourceLoader.THREAD_LOAD_LOADED:
			_progress_bar.value = 100.0
			_status_label.text = "Ready!"
			_finish_when_min_time_elapsed()
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			set_process(false)
			_status_label.text = "Failed to load"
			push_error("loading_screen.gd: failed to load '%s' (status %d)" % [target_scene_path, status])


## Waits out whatever's left of min_display_time (if the load beat it)
## before actually swapping, so the screen never just flickers.
func _finish_when_min_time_elapsed() -> void:
	set_process(false)
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - _started_at
	var remaining: float = max(min_display_time - elapsed, 0.0)
	if remaining > 0.0:
		await get_tree().create_timer(remaining).timeout
	_swap_to_target()


## Manual instantiate-then-free swap instead of change_scene_to_packed().
## change_scene_to_packed() frees the current scene FIRST and only adds
## the new one on a deferred call afterward — for that gap there's no
## current_scene at all, so the viewport shows raw clear color (a flat
## gray flash) instead of either screen. Same reasoning as
## studio_logo.gd's and main_menu.gd's own _go_to_loading_screen():
## add the new scene to the tree — and let it render at least one frame
## — before freeing the old one, so there's never a frame with nothing
## in it.
func _swap_to_target() -> void:
	var packed: PackedScene = ResourceLoader.load_threaded_get(target_scene_path)
	var target_instance: Node = packed.instantiate()
	get_tree().root.add_child(target_instance)
	get_tree().current_scene = target_instance
	queue_free()
