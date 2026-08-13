extends MeshInstance3D
## Cheap "infinite ocean." The ocean is one continuous tiling surface, so
## there's nothing to actually spawn — we just snap this plane's X/Z under
## the target every frame and let it extend past the fog distance in every
## direction. Discrete objects (islands, rocks, ruins in Phase 5) are a
## different problem and get real chunk spawn/despawn when we get there.
##
## Known limitation, deferred on purpose: the target's own world position
## still grows unbounded the longer a run goes (this script only moves the
## ocean, not the player). That's a floating-origin precision issue and
## belongs with the Phase 5 chunk system or Phase 12 optimization pass, not
## here — flagging it now so it isn't a surprise later.
##
## Physics-tick judder fix: _target's global_position only changes on
## physics ticks (60/s by default), but this runs in _process (once per
## RENDERED frame — can be 90/120fps on phones). Reading the raw position
## meant the ocean held still for a couple of render frames, then jumped,
## every physics tick — invisible on small objects, very visible on a
## full-screen surface, and reads as "the ocean feels slow/laggy" even
## though real travel speed is correct. get_global_transform_interpolated()
## (Godot 4.3+) returns the blended in-between position for the current
## render frame instead of the last physics tick's raw value. Also requires
## Project Settings > Physics > Common > Physics Interpolation = on
## (see project.godot) — without that project setting this call just
## returns the same raw transform and the judder comes back.

@export var target_path: NodePath

@onready var _target: Node3D = get_node(target_path)

func _process(_delta: float) -> void:
	if _target == null:
		return
	var target_origin: Vector3 = _target.global_transform.origin
	if _target.has_method("get_global_transform_interpolated"):
		target_origin = _target.get_global_transform_interpolated().origin
	global_position.x = target_origin.x
	global_position.z = target_origin.z
