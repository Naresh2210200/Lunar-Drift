extends MeshInstance3D
## WindmillBlades — spins a windmill's blade mesh continuously around its
## own local axis. Attach this script directly to the BLADES mesh node
## itself — "Windmill_Blades" in windmill.tscn, "TowerWindmill_Blades" in
## tower_windmill.tscn — NOT to the tower mesh or the scene root, so only
## the blades spin while the tower stays put.
##
## Uses rotate_object_local() rather than assigning `rotation` directly.
## Both blade meshes carry a baked-in transform from their original
## export — visible in the .tscn as something like
## `Transform3D(100, 0, 0, 0, -1.1920929e-05, 99.99999, 0, -99.99999,
## -1.1920929e-05, ...)` — which is a 90°-ish axis-conversion baked into
## the basis, not a clean identity. rotate_object_local() spins the mesh
## around its OWN local axes as authored, so it keeps working no matter
## what that baked orientation is. Assigning `rotation.x`/`.z` directly
## instead would spin around Godot's post-transform node axes, which do
## NOT reliably line up with "spin like a windmill" for a mesh exported
## this way — that mismatch is exactly what would cause a wobble or a
## spin around the wrong-looking axis if you tried it.

@export_range(0.0, 720.0, 1.0) var degrees_per_second: float = 90.0

## Which of the blade mesh's own local axes it spins around. A real sail
## spins around the axis pointing straight out of the hub toward the
## viewer, but which LOCAL axis that actually is depends on how this
## specific mesh was modeled/exported — not something inferable from the
## .tscn transform alone. Default is Z; if the blades wobble or spin
## around visibly the wrong axis in the editor's live preview, switch
## this to X or Y — no code change needed.
@export_enum("X", "Y", "Z") var spin_axis: String = "Z"

## Flip if the blades spin the "wrong" direction for how the art reads
## against the moon's drift direction.
@export var reverse: bool = false


func _process(delta: float) -> void:
	var axis: Vector3
	match spin_axis:
		"X":
			axis = Vector3.RIGHT
		"Y":
			axis = Vector3.UP
		_:
			axis = Vector3.BACK  # Z
	var spin_sign := -1.0 if reverse else 1.0
	rotate_object_local(axis, deg_to_rad(degrees_per_second) * delta * spin_sign)
