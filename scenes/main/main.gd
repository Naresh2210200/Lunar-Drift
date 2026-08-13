extends Node3D
## Main scene root. Still just a skeleton beyond hosting World/CameraRig/
## MoonRig/etc. — it exists so we have a real entry point to run and to
## hang future systems (UI) off of as we build them in later milestones.
##
## No longer calls GameManager.change_state(PLAYING) itself. The
## IntroSequence node (see scenes/main/intro_sequence.gd) now owns that:
## it holds the game in whatever state GameManager starts in (MENU, since
## there's still no menu screen — that's Phase 10) while it plays the
## opening camera-reveal, then flips to PLAYING itself once the reveal
## finishes so control is handed over the instant the world is fully
## visible, not before.
##
## Audio split: background_music.mp3 belongs to main_menu.gd only —
## main_menu.gd starts it on _ready() and fades it out the moment Play is
## pressed (see main_menu.gd's _on_play_pressed). This scene never starts
## or resumes it, in either direction, so main.tscn never has a reason to
## touch AudioManager.play_music()/stop_music() at all. The only audio
## this scene's tree drives is the jet_starting/jet_flying engine loop,
## owned by player.gd + intro_sequence.gd via AudioManager.start_engine_
## loop()/stop_engine_loop(). (A prior version of this script had an F6-
## testing fallback that called play_music() here if nothing was playing
## yet — removed because it also fired on every HUD restart, reloading
## main.tscn and re-triggering the menu music mid-run.)

func _ready() -> void:
	pass
