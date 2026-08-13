class_name GlowTexture
extends RefCounted
## scenes/startup/glow_texture.gd — tiny static helper, NOT a scene or an
## autoload. Both startup screens want a soft radial glow behind text, and
## no glow image asset exists yet in the project, so this builds one
## procedurally at runtime with a Gradient + GradientTexture2D instead of
## duplicating the same lines in both screen scripts. Swap for a real
## hand-painted glow/moon-shine texture later without touching either
## screen's script — just change what `build_radial()` returns.

static func build_radial(size: int = 512, color: Color = Color.WHITE, max_alpha: float = 0.5) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(color.r, color.g, color.b, max_alpha),
		Color(color.r, color.g, color.b, 0.0),
	])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = size
	texture.height = size
	return texture
