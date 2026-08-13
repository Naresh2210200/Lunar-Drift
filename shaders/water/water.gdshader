shader_type spatial;

uniform vec4 WATER_COL = vec4(0.86, 0.86, 0.88, 1.0);
uniform vec4 WATER2_COL = vec4(0.06, 0.06, 0.07, 1.0);
uniform vec4 FOAM_COL = vec4(0.98, 0.98, 0.97, 1.0);

uniform float distortion_speed = 0.35; // was 2.0 — slower drift reads as sleepy, not choppy
uniform vec2 tile = vec2(5.0, 5.0);
uniform float wave_speed = 0.5; // was 1.5 — same reasoning, a lazy sway not a bob
uniform float wave_height = 0.12; // was 0.15 — slightly gentler swell to match the slower speed
uniform float wave_frequency = 0.4;

// activity is the master gate between "static/frozen" (0.0) and
// "fully animated" (1.0) water. Continuous normal flight drives this to
// 0 — a still, glassy surface reads as calm and is free on mobile — and
// something outside a script pushes it back toward 1 only for the
// opening cinematic approach and for brief low-pass "collisions" with
// the surface (see ocean_activity.gd). Gates BOTH the ripple amplitude
// in vertex() and the distortion phase in fragment() below, so 0 really
// means motionless, not just very slow.
uniform float activity : hint_range(0.0, 1.0) = 0.0;

// Real elapsed animation time, pushed in from ocean_activity.gd each
// frame as an accumulator that only ever advances while activity > 0.
// Using this instead of the engine's raw TIME is what stops a sudden
// swing of speed when the water re-wakes after sitting frozen for a
// long stretch of real TIME: TIME * activity would jump straight to
// wherever TIME happens to be the instant activity leaves 0, while this
// accumulator simply resumes counting from exactly where it paused.
uniform float anim_time = 0.0;

// Placeholder direction — Phase 4 will drive this from the real Moon node
// instead of a fixed value.
uniform vec3 moon_direction = vec3(0.3, 0.6, -0.7);
uniform vec4 moon_glow_color : source_color = vec4(1.0, 0.98, 0.94, 1.0);
uniform float glow_sharpness = 64.0;
uniform float glow_strength = 0.8;

// The ocean plane snaps its X/Z under the player every frame (see
// ocean_follow.gd) so it never runs out of surface — but that also means
// its MESH-LOCAL UV never changes frame to frame; the plane's own vertices
// don't move relative to the plane. Without this, the fold/foam pattern
// would look completely frozen no matter how fast the player travels,
// which reads as "the world isn't moving." Fixing that by driving the
// pattern off the plane's actual WORLD position instead: as ocean_follow.gd
// re-centers the plane under the player, this varying tracks that motion,
// so the pattern scrolls in step with real travel distance.
uniform float world_uv_scale = 0.005; // matches the original mesh UV's 0..1-over-200-units frequency
varying vec2 world_uv;

const float TWOPI = 6.283185307;
const float SIXPI = 18.84955592;

float circ(vec2 pos, vec2 c, float s)
{
    c = abs(pos - c);
    c = min(c, 1.0 - c);

    return smoothstep(0.0, 0.002, sqrt(s) - sqrt(dot(c, c))) * -1.0;
}

float waterlayer(vec2 uv)
{
    uv = mod(uv, 1.0); // Clamp to [0..1]
    float ret = 1.0;
    ret += circ(uv, vec2(0.37378, 0.277169), 0.0268181);
    ret += circ(uv, vec2(0.0317477, 0.540372), 0.0193742);
    ret += circ(uv, vec2(0.430044, 0.882218), 0.0232337);
    ret += circ(uv, vec2(0.641033, 0.695106), 0.0117864);
    ret += circ(uv, vec2(0.0146398, 0.0791346), 0.0299458);
    ret += circ(uv, vec2(0.43871, 0.394445), 0.0289087);
    ret += circ(uv, vec2(0.909446, 0.878141), 0.028466);
    ret += circ(uv, vec2(0.310149, 0.686637), 0.0128496);
    ret += circ(uv, vec2(0.928617, 0.195986), 0.0152041);
    ret += circ(uv, vec2(0.0438506, 0.868153), 0.0268601);
    ret += circ(uv, vec2(0.308619, 0.194937), 0.00806102);
    ret += circ(uv, vec2(0.349922, 0.449714), 0.00928667);
    ret += circ(uv, vec2(0.0449556, 0.953415), 0.023126);
    ret += circ(uv, vec2(0.117761, 0.503309), 0.0151272);
    ret += circ(uv, vec2(0.563517, 0.244991), 0.0292322);
    ret += circ(uv, vec2(0.566936, 0.954457), 0.00981141);
    ret += circ(uv, vec2(0.0489944, 0.200931), 0.0178746);
    ret += circ(uv, vec2(0.569297, 0.624893), 0.0132408);
    ret += circ(uv, vec2(0.298347, 0.710972), 0.0114426);
    ret += circ(uv, vec2(0.878141, 0.771279), 0.00322719);
    ret += circ(uv, vec2(0.150995, 0.376221), 0.00216157);
    ret += circ(uv, vec2(0.119673, 0.541984), 0.0124621);
    ret += circ(uv, vec2(0.629598, 0.295629), 0.0198736);
    ret += circ(uv, vec2(0.334357, 0.266278), 0.0187145);
    ret += circ(uv, vec2(0.918044, 0.968163), 0.0182928);
    ret += circ(uv, vec2(0.965445, 0.505026), 0.006348);
    ret += circ(uv, vec2(0.514847, 0.865444), 0.00623523);
    ret += circ(uv, vec2(0.710575, 0.0415131), 0.00322689);
    ret += circ(uv, vec2(0.71403, 0.576945), 0.0215641);
    ret += circ(uv, vec2(0.748873, 0.413325), 0.0110795);
    ret += circ(uv, vec2(0.0623365, 0.896713), 0.0236203);
    ret += circ(uv, vec2(0.980482, 0.473849), 0.00573439);
    ret += circ(uv, vec2(0.647463, 0.654349), 0.0188713);
    ret += circ(uv, vec2(0.651406, 0.981297), 0.00710875);
    ret += circ(uv, vec2(0.428928, 0.382426), 0.0298806);
    ret += circ(uv, vec2(0.811545, 0.62568), 0.00265539);
    ret += circ(uv, vec2(0.400787, 0.74162), 0.00486609);
    ret += circ(uv, vec2(0.331283, 0.418536), 0.00598028);
    ret += circ(uv, vec2(0.894762, 0.0657997), 0.00760375);
    ret += circ(uv, vec2(0.525104, 0.572233), 0.0141796);
    ret += circ(uv, vec2(0.431526, 0.911372), 0.0213234);
    ret += circ(uv, vec2(0.658212, 0.910553), 0.000741023);
    ret += circ(uv, vec2(0.514523, 0.243263), 0.0270685);
    ret += circ(uv, vec2(0.0249494, 0.252872), 0.00876653);
    ret += circ(uv, vec2(0.502214, 0.47269), 0.0234534);
    ret += circ(uv, vec2(0.693271, 0.431469), 0.0246533);
    ret += circ(uv, vec2(0.415, 0.884418), 0.0271696);
    ret += circ(uv, vec2(0.149073, 0.41204), 0.00497198);
    ret += circ(uv, vec2(0.533816, 0.897634), 0.00650833);
    ret += circ(uv, vec2(0.0409132, 0.83406), 0.0191398);
    ret += circ(uv, vec2(0.638585, 0.646019), 0.0206129);
    ret += circ(uv, vec2(0.660342, 0.966541), 0.0053511);
    ret += circ(uv, vec2(0.513783, 0.142233), 0.00471653);
    ret += circ(uv, vec2(0.124305, 0.644263), 0.00116724);
    ret += circ(uv, vec2(0.99871, 0.583864), 0.0107329);
    ret += circ(uv, vec2(0.894879, 0.233289), 0.00667092);
    ret += circ(uv, vec2(0.246286, 0.682766), 0.00411623);
    ret += circ(uv, vec2(0.0761895, 0.16327), 0.0145935);
    ret += circ(uv, vec2(0.949386, 0.802936), 0.0100873);
    ret += circ(uv, vec2(0.480122, 0.196554), 0.0110185);
    ret += circ(uv, vec2(0.896854, 0.803707), 0.013969);
    ret += circ(uv, vec2(0.292865, 0.762973), 0.00566413);
    ret += circ(uv, vec2(0.0995585, 0.117457), 0.00869407);
    ret += circ(uv, vec2(0.377713, 0.00335442), 0.0063147);
    ret += circ(uv, vec2(0.506365, 0.531118), 0.0144016);
    ret += circ(uv, vec2(0.408806, 0.894771), 0.0243923);
    ret += circ(uv, vec2(0.143579, 0.85138), 0.00418529);
    ret += circ(uv, vec2(0.0902811, 0.181775), 0.0108896);
    ret += circ(uv, vec2(0.780695, 0.394644), 0.00475475);
    ret += circ(uv, vec2(0.298036, 0.625531), 0.00325285);
    ret += circ(uv, vec2(0.218423, 0.714537), 0.00157212);
    ret += circ(uv, vec2(0.658836, 0.159556), 0.00225897);
    ret += circ(uv, vec2(0.987324, 0.146545), 0.0288391);
    ret += circ(uv, vec2(0.222646, 0.251694), 0.00092276);
    ret += circ(uv, vec2(0.159826, 0.528063), 0.00605293);
	return max(ret, 0.0);
}

vec3 water(vec2 uv, vec3 cdir, float iTime)
{
    uv *= vec2(0.25);

    // Parallax height distortion with two directional waves at
    // slightly different angles.
    vec2 a = 0.025 * cdir.xz / cdir.y; // Parallax offset
    float h = sin(uv.x + iTime); // Height at UV
    uv += a * h;
    h = sin(0.841471 * uv.x - 0.540302 * uv.y + iTime);
    uv += a * h;
    
    // Texture distortion
    float d1 = mod(uv.x + uv.y, TWOPI);
    float d2 = mod((uv.x + uv.y + 0.25) * 1.3, SIXPI);
    d1 = iTime * 0.07 + d1;
    d2 = iTime * 0.5 + d2;
    vec2 dist = vec2(
    	sin(d1) * 0.15 + sin(d2) * 0.05,
    	cos(d1) * 0.15 + cos(d2) * 0.05
    );
    
    vec3 ret = mix(WATER_COL.rgb, WATER2_COL.rgb, waterlayer(uv + dist.xy));
    ret = mix(ret, FOAM_COL.rgb, waterlayer(vec2(1.0) - uv - dist.yx));
    return ret;
}

void vertex() {
	// Capture world-space XZ before the wave displacement below touches
	// VERTEX.y — MODEL_MATRIX already includes ocean_follow.gd's snap to
	// the player's real global position, so this scrolls with true travel
	// distance instead of staying fixed to the mesh's own local UV.
	world_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz * world_uv_scale;

	// Two overlapping sine waves — cheap and mobile-friendly. Full Gerstner
	// waves would look nicer up close but aren't needed at this stylized,
	// low-poly scale and cost meaningfully more on a phone GPU.
	// Both scaled by activity: at 0 the amplitude collapses to exactly
	// zero, so the plane is a flat, motionless sheet, not a slowed-down
	// one — that's what makes "static during continuous flight" actually
	// static instead of just subtle.
	float wave = sin(VERTEX.x * wave_frequency + anim_time * wave_speed) * wave_height * activity;
	wave += sin(VERTEX.z * wave_frequency * 0.7 + anim_time * wave_speed * 1.3) * wave_height * 0.5 * activity;
	VERTEX.y += wave;
}

void fragment() {
	vec2 uv = world_uv;
	// anim_time (not TIME) drives the surface-pattern distortion too, so
	// the fold/foam pattern genuinely stops drifting when activity hits
	// 0 instead of just slowing to a crawl — see the uniform comments up
	// top for why this can't just be TIME * activity.
	ALBEDO = water(uv * tile, vec3(0,1,0), anim_time * distortion_speed);

	// Stylized moon glint via EMISSION, not a real reflection probe — it
	// reads as "glowing magical water" per the art direction, is nearly
	// free on mobile, and doesn't depend on scene lighting existing yet.
	vec3 view_dir = normalize(VIEW);
	vec3 reflect_dir = reflect(-normalize(moon_direction), NORMAL);
	float glint = pow(max(dot(view_dir, reflect_dir), 0.0), glow_sharpness);
	EMISSION = moon_glow_color.rgb * glint * glow_strength;
}