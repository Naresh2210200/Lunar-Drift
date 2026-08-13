shader_type canvas_item;
// Full-screen radial streak overlay for the "sense of speed" motion effect.
// Deliberately monochrome (near-black streaks, low alpha) to stay inside
// the white/black/gray palette rather than adding a stylized speed-line
// color of its own. Intensity is driven entirely from script
// (speed_lines.gd) via the `intensity` uniform — this shader has no
// opinion on what "fast" means, just how to draw the streak pattern.

// 0 = fully invisible, 1 = strongest streaks. Set every frame from
// speed_lines.gd based on the player's current velocity.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
// How many streaks wrap around the circle. Higher = thinner, more
// numerous lines.
uniform float line_count : hint_range(4.0, 64.0) = 28.0;
// Normalized distance from center where streaks start fading in / are
// fully opaque, so the very center of the screen (where the player is
// looking) stays clear and the effect reads as peripheral.
uniform float inner_clear_radius : hint_range(0.0, 0.5) = 0.18;
uniform float outer_fade_radius : hint_range(0.2, 0.9) = 0.7;

void fragment() {
	vec2 centered = (UV - vec2(0.5, 0.5)) * vec2(1.0, 1.0);
	float dist = length(centered);
	float angle = atan(centered.y, centered.x);

	// A sharpened sine gives thin bright streaks with dark gaps between
	// them, rather than a smooth gradient band — reads as distinct lines
	// radiating outward instead of a soft vignette.
	float streak = pow(abs(sin(angle * line_count)), 10.0);

	// Streaks only live in the peripheral ring, fully clear near center
	// and faded out again at the very edge so it doesn't read as a hard
	// screen border.
	float radial_fade = smoothstep(inner_clear_radius, outer_fade_radius, dist);
	radial_fade *= 1.0 - smoothstep(outer_fade_radius, outer_fade_radius + 0.25, dist);

	float alpha = streak * radial_fade * intensity;
	COLOR = vec4(0.05, 0.05, 0.06, alpha * 0.55);
}
