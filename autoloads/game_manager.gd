extends Node
## GameManager (autoload)
##
## The ONLY global singleton in this project. Its job is narrow on purpose:
## track what "mode" the game is in and tell everyone else when it changes.
## It does NOT touch the player, the world, the UI, or audio directly —
## those systems listen to `state_changed` and react on their own.
## If you're about to add a new responsibility here, stop and ask whether
## it deserves its own node/script instead.

enum GameState {
	MENU,
	PLAYING,
	PAUSED,
	GAME_OVER,
}

signal state_changed(new_state: GameState)

var current_state: GameState = GameState.MENU

# Always go through this instead of setting current_state directly.
# That way the signal is guaranteed to fire and nothing can silently
# drift out of sync with what's on screen.
func change_state(new_state: GameState) -> void:
	if new_state == current_state:
		return
	current_state = new_state
	state_changed.emit(new_state)
	print("GameManager: state -> ", GameState.keys()[new_state])
