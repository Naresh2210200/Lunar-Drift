extends Node3D
## ProceduralWorld — real 2D open-world chunk grid: discrete paper scenery
## (rocks, cliffs), obstacles, and Shade collectibles all spawn in a
## grid of square cells around the player and recycle once they fall
## outside the window. This replaced the original Phase 5/6/7 system,
## which only chunked along Z (a single strip, fixed-width) — straying
## far enough sideways meant leaving the populated band entirely and
## finding nothing out there. This version chunks BOTH axes, so the
## player has full access to the world in any direction, not just along
## a fixed "track":
##
##                New Chunks Spawn
##                       ▲
##                       │
##           ┌─────────────────────────┐
##           │   Chunk   Chunk   Chunk │
##           │                         │
##           │      🚀 Player          │
##           │                         │
##           │   Chunk   Chunk   Chunk │
##           └─────────────────────────┘
##                       │
##                       ▼
##               Old Chunks Deleted
##
## Every generated object is collidable — rocks/cliffs and the dedicated
## black obstacle spikes all end the run on touch; Shades reward
## instead. Each builds its own Area3D with collision shapes sized per
## sub-mesh (see _make_rock_cluster / _make_cliff / _make_obstacle)
## rather than one oversized bounding sphere over the whole prop — that
## approach caused visible "there's a gap but it still collides" false
## positives.
##
## Floating-origin note: chunk placement is keyed off the target's raw
## global X/Z, so the precision-drift issue flagged back in Milestone 3
## is still present and still NOT fixed here — still earmarked for
## Phase 12 per the README, not silently absorbed into this milestone.

@export var target_path: NodePath
@export var outline_material: ShaderMaterial

@export_group("Chunking")
## Square grid cell size — the SAME value drives both X and Z now, since
## the world is a real 2D grid rather than a Z-only strip. Kept the name
## close to the old `chunk_length` on purpose (see README) — it's the
## same "how big is one chunk" number, just no longer forward-only.
@export var chunk_size: float = 40.0
@export var chunks_ahead: int = 5
@export var chunks_behind: int = 1
## NEW — lateral radius, in chunks, on EACH side of the player. This is
## the actual fix for "leaving the track finds nothing": before, chunks
## only existed in a fixed-width Z strip. Raise this if you want the
## player able to wander even further sideways before hitting the edge
## of the populated window (costs more active chunks at once).
@export var chunks_side: int = 3

@export_group("Props")
@export var props_per_chunk_min: int = 2
@export var props_per_chunk_max: int = 4
## Minimum distance enforced between any two props placed in the SAME
## chunk cell — this is the actual fix for scenery spawning touching or
## overlapping (a rock cluster jammed right against a cliff, etc). Uses
## simple rejection sampling: try a few random spots, take the first one
## that clears this distance from every prop already placed in this chunk.
@export var props_min_spacing: float = 8.0
## Cap on placement attempts per prop before giving up and placing it
## wherever the last attempt landed — keeps a tight chunk (small
## chunk_size, high prop count, large spacing) from looping forever
## chasing a gap that doesn't exist, at the cost of occasionally still
## allowing a close pair when the chunk is genuinely crowded.
@export var props_placement_attempts: int = 10
## Margin added around every obstacle/pillar safe zone when checking
## whether a scattered prop's CENTER point falls inside one (see
## _point_in_zone). Props vary in radius (rocks/cliffs up to ~7 units
## across), so rejecting only exact-point overlap would still let a
## large prop's edge poke into a lane it was supposed to leave clear —
## this margin is the buffer against that.
@export var props_safe_zone_margin: float = 4.0

@export_group("Obstacles")
## Phase 6, reworked: obstacles spawn as ROWS across a fixed number of
## lanes, and every row deliberately leaves at least one lane open — no
## row can block a chunk's full width, so there's always somewhere to go.
## Lane math now scales off `chunk_size` (see _spawn_obstacle_row) instead
## of a separate fixed `obstacle_x_range`, since obstacles spawn in every
## chunk cell across the whole grid now, not just a fixed central band.
@export var obstacle_rows_per_chunk_min: int = 0
@export var obstacle_rows_per_chunk_max: int = 2
@export var obstacle_lane_count: int = 3
## Minimum world-Z spacing enforced between rows so the player has real
## reaction time instead of two rows visually merging into one wall.
@export var obstacle_min_row_gap: float = 12.0
## Chunk indices below this (forward distance only, ignores lateral
## offset) spawn no obstacles at all — a short grace window at the start
## of a run so the player isn't dodging on frame one, in any lane.
@export var obstacle_grace_chunks: int = 2
## Same grace idea as obstacle_grace_chunks, but re-triggerable mid-run:
## how many chunks of forward distance stay hazard-free after a "continue
## with Shades" revive (see grant_continue_grace below). Subway Surfers-
## style — you don't just un-pause back into the wall you died on.
@export var continue_grace_chunks: int = 3

@export_group("Speed Difficulty")
## Reads the target's current speed (tries property names `speed`,
## `current_speed`, `forward_speed` in order, then falls back to the length
## of a `velocity`/`linear_velocity` Vector3 if present) and uses it to ease
## obstacle/pillar spacing and density between a baseline and a sparser,
## easier-to-read "hard" setting. Below speed_difficulty_low, generation
## uses its normal defaults; above speed_difficulty_high, it's fully eased
## to the sparser settings. player.gd isn't included here, so these two
## thresholds are a reasonable starting guess — tune them to match the
## boat's actual speed range.
@export var speed_difficulty_low: float = 15.0
@export var speed_difficulty_high: float = 45.0
## At max speed difficulty, row/segment gaps are multiplied by this much —
## more forward spacing so a fast boat still has real reaction time instead
## of two rows reading as one merged wall.
@export var speed_difficulty_gap_multiplier: float = 1.6
## At max speed difficulty, the max fraction of lanes allowed to block in a
## single row is multiplied by this much — fewer simultaneous obstacles to
## read and react to when there's less time to do it in.
@export var speed_difficulty_density_multiplier: float = 0.6

@export_group("Start Grace")
## Chunk indices below this (forward distance only, same convention as
## obstacle_grace_chunks) spawn NO props or collectibles either — the
## very first chunk(s) at spawn are plain, empty ground. Per explicit
## request: the run should visibly begin bare and let the world fill in
## ahead as the player advances, rather than already being fully dressed
## the instant the level loads. Kept smaller than obstacle_grace_chunks
## on purpose, so the reveal reads as layered: bare ground first, then
## scenery, then (a little further out) real obstacles — three steps of
## ramping complexity instead of one flat cutover.
@export var props_grace_chunks: int = 1
## Keeps obstacle rows off the very seam between adjacent chunk cells,
## purely so a spike cluster never looks like it's straddling two chunks'
## worth of pooled geometry.
@export var obstacle_edge_margin: float = 3.0

@export_group("Collectibles")
## Shades (sunglasses) — repurposed from the old Moon Shard energy pickup.
## Spawned independently of the obstacle row system (not slotted into the
## guaranteed-open lane) — deliberately simple. Known consequence, flagged
## rather than hidden: one can land close to an obstacle. Revisit if
## playtesting shows it reads as unfair rather than as a small risk/reward
## choice.
@export var collectibles_per_chunk_min: int = 0
@export var collectibles_per_chunk_max: int = 2
## Chance per chunk of spawning any Shades at all, rolled once per chunk
## before picking a count — keeps them a punctuation mark, not a constant
## background hum the player stops noticing.
@export var collectible_spawn_chance: float = 0.6
## Flat score granted per Shade — NOT scaled by the multiplier itself; the
## multiplier instead scales the ongoing distance score (see player.gd).
@export var collectible_score_value: int = 100
## How much each Shade fills the multiplier meter (see moon_energy.gd's
## max_meter — default 100, so ~4 Shades per tier at this default).
@export var collectible_meter_fill: float = 25.0

@export_group("Biomes")
## The world now cycles through distinct BIOMES as the player travels
## forward, instead of one uniform prop/obstacle mix for the whole run —
## this is the actual mechanism behind "the world grows more complex /
## mood shifts" from the design brief. Biome choice is a pure function of
## a chunk's forward depth (key.y) via _get_biome() below, so it's fully
## deterministic and reproducible from the RNG seed like everything else
## here — no separate biome-tracking state needed.
##
## ROCKFIELD is the existing Milestone 6/7 baseline (scattered rocks/
## cliffs + spike-obstacle lane rows) — unchanged, kept as the "default"
## biome. WINDMILL is a deliberate breather: sparse scenery, a tall
## decorative windmill landmark, and NO dodge obstacles — the "peaceful"
## beat in the cycle. PILLARS is a dense monolith avenue (most lanes
## blocked, never all) — an "intense/urban" beat. CUBES lines up rows of
## floating cube blocks with deliberate GATES — clear lane-wide gaps —
## left open between them, same lane-and-guaranteed-corridor mechanic as
## PILLARS but with a boxier, more "obstacle course" silhouette instead of
## a monolith avenue. Cycle order below is a simple repeating band
## (ROCKFIELD → WINDMILL → PILLARS → CUBES → repeat) rather than a
## one-way ramp from calm to intense — flagging this as a deliberate
## simplification, easy to swap for a true escalating-difficulty curve
## later if repeating bands read as too predictable in a long run.
## CASTLE was added at the end of the enum rather than inserted in the
## middle, so it doesn't renumber any existing biome and doesn't shift
## which biome any already-tuned band used to be. A medieval castle-wall
## avenue: real Wall/Tower FBX scenes (see castle_wall_scenes below)
## block lanes the same way PILLARS' monoliths do, with a
## guaranteed-clear gate lane every row, a big landmark tower off to the
## side per chunk (castle_landmark_scenes, same pattern as
## windmill_scenes), and themed scatter (well, banners, targets —
## castle_prop_scenes) instead of generic rock/cliff clutter.
##
## The MAZE biome (zigzag full-width walls) has been removed entirely —
## its enum value, export group, and generator functions are gone. The
## cycle is now ROCKFIELD → WINDMILL → PILLARS → CUBES → CASTLE → repeat.
enum Biome { ROCKFIELD, WINDMILL, PILLARS, CUBES, CASTLE }

## How many chunks (forward distance only, same convention as
## obstacle_grace_chunks) each biome band lasts before cycling to the
## next. Lower = mood shifts faster; higher = each biome gets more room
## to establish its own feel before changing.
@export var biome_band_length: int = 20
## Same idea as obstacle_grace_chunks/props_grace_chunks below, but it
## fires EVERY time a new biome starts, not just once at the start of the
## run — a fresh grace window every time Rockfield hands off to Windmill,
## Windmill to Pillars, Pillars to Cubes, and so on. For this many chunks
## at the start of each biome, the water is genuinely clear: no dodge
## obstacles AND no scattered rock/cliff scenery either (a Shade or two
## can still appear — that's a reward, not clutter). Without this, the
## last pillar of one biome and the first cube of the next could land
## back-to-back with zero warning that the rules just changed.
## 0 turns this off and reverts to biomes cutting over immediately.
@export var biome_grace_chunks: int = 1

@export_group("Cube Gates (Cube Obstacles)", "cube_")
## How many side-by-side lanes the cube field is divided into. More lanes
## = a wider spread with finer-grained gates between cubes.
@export var cube_lane_count: int = 5
## Fewest rows of cubes that can appear in one chunk of this biome.
@export var cube_rows_per_chunk_min: int = 1
## Most rows of cubes that can appear in one chunk of this biome. Eases
## down toward the minimum above as the boat's speed rises (see the Speed
## Difficulty section above) — fewer rows to dodge when there's less time
## to react to them.
@export var cube_rows_per_chunk_max: int = 3
## How much open water is guaranteed between one row of cubes and the
## next. Bigger number = more breathing room. Stretched out further at
## high speed (speed_difficulty_gap_multiplier).
@export var cube_min_row_gap: float = 14.0
## How crowded a single row of cubes is allowed to get, as a fraction of
## the lanes above (0.5 = at most half the lanes can have a cube in them,
## so at least half are always open GATES to steer through). Reduced
## further at high speed (speed_difficulty_density_multiplier).
@export var cube_max_blocked_lane_fraction: float = 0.5
## Smallest and largest edge length for one cube block (each cube's
## width/height/depth are all randomized independently within this range,
## so they read as chunky blocks rather than perfectly identical dice).
@export var cube_size_min: float = 2.5
@export var cube_size_max: float = 4.5

@export_group("Biomes", "windmill_")
## Chance (per WINDMILL chunk, past the grace window) of placing the
## decorative landmark tower — not every chunk in the biome needs one,
## or it stops reading as a landmark and starts reading as clutter.
@export var windmill_landmark_chance: float = 0.5
## Real windmill scenes (windmill.tscn, tower_windmill.tscn) to
## instantiate as the landmark — assign these in the Inspector. If a
## scene's blade mesh already has windmill_blades.gd attached, rotation
## just happens once instanced; nothing else to wire up here. Left
## empty, falls back to a primitive paper-only landmark built in code
## (see _make_paper_windmill_landmark) so nothing breaks before this is
## set. This is the fix for "the windmill in-game doesn't match the
## model I provided" — the primitive version was always a placeholder,
## not meant to replace your actual asset once you had one to point at.
@export var windmill_scenes: Array[PackedScene] = []

@export_group("Biomes", "castle_")
## Same lane/guaranteed-corridor/no-adjacent-blocks mechanic as PILLARS
## and CUBES — see _spawn_castle_wall_rows. How many side-by-side lanes
## the castle wall avenue is divided into.
@export var castle_lane_count: int = 5
@export var castle_rows_per_chunk_min: int = 1
@export var castle_rows_per_chunk_max: int = 3
@export var castle_min_row_gap: float = 16.0
@export var castle_max_blocked_lane_fraction: float = 0.5
## Wall/tower scenes used to BLOCK a lane in a castle row — point these
## at the imported Wall/WallBricks/TallWall/TallWallBricks/SmallTower/
## PointyTower/etc. FBX scenes from your asset pack. Empty falls back to
## the primitive pillar (_make_pillar) so nothing breaks before you wire
## these up — same "asset optional" pattern as windmill_scenes.
@export var castle_wall_scenes: Array[PackedScene] = []
## Big set-piece landmark placed off to the side per chunk (not in the
## lane grid, decorative only, no collision) — point at LargeTower,
## WatchTowerWRoof, LargeSquareTower, Tower, etc. Same pattern as
## _spawn_windmill_landmark. Empty = skipped entirely, no fallback
## primitive (a generic box tower wouldn't read as "castle" the way the
## windmill fallback reads as "windmill").
@export var castle_landmark_scenes: Array[PackedScene] = []
@export var castle_landmark_chance: float = 0.5
## Small decorative, non-colliding scatter — Well, Banner, Target,
## TargetWithArrows, Dummy, Bridge, Tunnel, Door, WindowGothic,
## WindowSquare all fit here. Empty = no castle scatter (silently skips,
## doesn't fall back to generic rock/cliff props, so the biome stays
## readable as "castle" rather than reverting to paper scenery).
@export var castle_prop_scenes: Array[PackedScene] = []
## Uniform scale applied to every instantiated castle scene. FBX asset
## packs are very commonly authored at a different unit scale than this
## project's hand-built primitives (which sit in roughly the 2-30 unit
## range) — tune this once against a test chunk rather than guessing.
## 1.0 = as-imported, no rescale.
@export var castle_asset_scale: float = 1.0

@export_group("Pillar Obstacles (Monolith Avenue)", "pillar_")
## How many side-by-side lanes the pillar avenue is divided into. More
## lanes = a wider road with finer-grained gaps between pillars.
@export var pillar_lane_count: int = 5
## Fewest rows of pillars that can appear in one chunk of the avenue.
@export var pillar_rows_per_chunk_min: int = 1
## Most rows of pillars that can appear in one chunk of the avenue. Eases
## down toward the minimum above as the boat's speed rises (see the Speed
## Difficulty section above) — fewer rows to dodge when there's less time
## to react to them.
@export var pillar_rows_per_chunk_max: int = 3
## How much open water is guaranteed between one row of pillars and the
## next. Bigger number = more breathing room. Raised from the old 9.0,
## which let rows sit close enough to visually merge into one wall; also
## stretched out further at high speed (speed_difficulty_gap_multiplier).
@export var pillar_min_row_gap: float = 14.0
## How crowded a single row of pillars is allowed to get, as a fraction of
## the lanes above (0.5 = at most half the lanes can have a pillar in
## them, so at least half always stay open). Replaces the old rule that
## blocked 60-80% of lanes and left only a sliver of open water — reduced
## further at high speed (speed_difficulty_density_multiplier).
@export var pillar_max_blocked_lane_fraction: float = 0.5

@onready var _target: Node3D = get_node(target_path)

var _rng := RandomNumberGenerator.new()
var _chunks: Dictionary = {}         # Vector2i (cx, cz) -> Node3D container
## Perf: every prop/obstacle/collectible builder used to call
## `StandardMaterial3D.new()` on every single spawn, even though the vast
## majority of them (paper props, black/near-black spikes, the two Shade
## colors) always resolve to the exact same albedo/emission values. Fresh
## Resource instances with identical properties still can't be batched by
## the renderer and add up to real GC churn given how often chunks recycle
## (~every 1-2s at normal speed). This cache makes every builder below
## fetch-or-create by a stable key instead, so equivalent props now share
## one Material — zero visual change, fewer draw calls, no per-spawn
## allocation. See _get_cached_material().
var _material_cache: Dictionary = {}  # cache key (String) -> StandardMaterial3D
## Perf: node pools keyed by a structural signature string (e.g.
## "rock_3", "obstacle_4", "pillar", "cube", "cliff", "collectible") —
## see _acquire_pooled/_release_to_pool and _recycle_chunk. Companion to
## _material_cache above: that cache stops materials from being
## reallocated every spawn, this stops the meshes/collision shapes/Area3D
## wrapper themselves from being rebuilt every spawn too.
var _prop_pools: Dictionary = {}      # signature (String) -> Array[Node3D]
var _pool_holder: Node3D              # parent for pooled-but-inactive nodes; set in _ready()
var _pool: Array[Node3D] = []        # recycled, hidden containers ready to reuse
var _current_center: Vector2i = Vector2i(999999, 999999)  # forces first update
## Forward chunk index (key.y) up to which newly-populated chunks should
## skip hazard spawning — the mid-run counterpart to obstacle_grace_chunks.
## Stays far below any real chunk index until grant_continue_grace() sets
## it, so it's a no-op for the entire rest of a normal run.
var _continue_grace_until_y: int = -999999

const PAPER_COLOR := Color(0.92, 0.92, 0.93, 1.0)

## Deliberate, explicit deviation from the brief's strict white/black/gray
## (+ subtle moon glow) palette, per direct request: Shades now come
## in two saturated colors so pickups read as a distinct "game token"
## rather than more paper scenery. Flagging it here the same way every
## other deliberate rule-break in this project gets flagged (see the Art
## Direction Retrofit section of the README) rather than silently bending
## the rule. If this reads as too jarring against the paper-diorama look
## in motion, the fix is to desaturate/darken these two rather than
## remove the color signal entirely — the color is doing real gameplay
## communication work now (see Design Reasoning in chat).
const SHADE_COLORS := [
	Color(0.2, 0.85, 0.35, 1.0),   # green
	Color(0.9, 0.15, 0.2, 1.0),    # red
]


func _ready() -> void:
	_rng.randomize()
	# Lets a continue/revive flow reach grant_continue_grace() via
	# get_first_node_in_group() instead of every caller needing a NodePath
	# wired to this specific instance — same reasoning as Player's
	# add_to_group("player") in player.gd.
	add_to_group("procedural_world")
	# Perf: parent for pooled props/obstacles/collectibles between chunk
	# recycles (see _release_to_pool / _acquire_pooled). Kept out of any
	# chunk container so it survives chunk reuse untouched; hidden so a
	# pooled-but-not-yet-reacquired node never renders or gets confused
	# for something still in play.
	_pool_holder = Node3D.new()
	_pool_holder.name = "PropPoolHolder"
	_pool_holder.visible = false
	add_child(_pool_holder)


func _process(_delta: float) -> void:
	if _target == null:
		return
	var center := Vector2i(
		floori(_target.global_position.x / chunk_size),
		floori(-_target.global_position.z / chunk_size)
	)
	if center == _current_center:
		return
	_current_center = center
	_update_chunks(center)


func _update_chunks(center: Vector2i) -> void:
	var wanted: Dictionary = {}
	for dz in range(-chunks_behind, chunks_ahead + 1):
		for dx in range(-chunks_side, chunks_side + 1):
			wanted[Vector2i(center.x + dx, center.y + dz)] = true

	# Recycle anything outside the window before spawning new chunks, so the
	# pool has containers ready instead of always allocating fresh ones.
	for existing_key in _chunks.keys().duplicate():
		if not wanted.has(existing_key):
			_recycle_chunk(existing_key)

	for key in wanted.keys():
		if not _chunks.has(key):
			_spawn_chunk(key)


func _spawn_chunk(key: Vector2i) -> void:
	var container := _get_pooled_container()
	container.position = Vector3(key.x * chunk_size, 0.0, -key.y * chunk_size)
	container.visible = true
	_populate_chunk(container, key)
	_chunks[key] = container


## Perf: any node built by a pooling-aware builder (rock cluster, cliff,
## obstacle spikes, pillar, cube, collectible — see each _make_* below)
## carries a "pool_sig" meta string identifying its exact structure (shape
## type + child count, since a couple of these have a randomized boulder/
## spike count). On recycle, those get parked under _pool_holder instead
## of freed, so the next chunk that needs the same signature can reuse the
## node's existing meshes/collision shapes instead of allocating new ones.
## Anything WITHOUT that meta (landmark scenes, castle wall pieces sourced
## from real FBX assets, castle scatter props) is rare/chance-gated enough
## that it isn't worth pooling yet, and still gets queue_free()'d exactly
## like before this change.
func _recycle_chunk(key: Vector2i) -> void:
	var container: Node3D = _chunks[key]
	_chunks.erase(key)
	container.visible = false
	for child in container.get_children():
		if child.has_meta("pool_sig"):
			_release_to_pool(child)
		else:
			child.queue_free()
	_pool.append(container)


func _get_pooled_container() -> Node3D:
	if _pool.size() > 0:
		return _pool.pop_back()
	var container := Node3D.new()
	add_child(container)
	return container


## Returns a previously-released node matching `sig`, fully reactivated
## (visible, Area3D monitoring re-enabled) and detached from the pool
## holder — ready for the caller to reposition/re-randomize and add to a
## chunk container. Returns null if the pool is empty for that signature,
## in which case the caller builds a fresh node as it always did.
func _acquire_pooled(sig: String) -> Node3D:
	if not _prop_pools.has(sig) or _prop_pools[sig].is_empty():
		return null
	var node: Node3D = _prop_pools[sig].pop_back()
	_pool_holder.remove_child(node)
	node.visible = true
	if node is Area3D:
		node.monitoring = true
		node.monitorable = true
	return node


## Parks a poolable node under _pool_holder, disabling anything that would
## let it keep affecting gameplay while sitting there — physics detection
## in particular, since an Area3D that stayed monitoring while hidden could
## still emit body_entered for something clipping through the pool holder.
func _release_to_pool(node: Node3D) -> void:
	var sig: String = node.get_meta("pool_sig")
	node.get_parent().remove_child(node)
	node.visible = false
	if node is Area3D:
		node.monitoring = false
		node.monitorable = false
	_pool_holder.add_child(node)
	if not _prop_pools.has(sig):
		_prop_pools[sig] = []
	_prop_pools[sig].append(node)


## Pure function of forward depth (key.y) — deliberately ignores lateral
## offset (key.x), so every chunk at the same forward distance is the
## same biome regardless of how far the player has wandered sideways.
## That matters here specifically because this is a 2D grid (Milestone
## "real open world" upgrade, see file header) — without this rule, a
## player who drifts sideways could straddle two different biomes at the
## same forward distance, which would read as arbitrary rather than as a
## deliberate world-level mood shift.
func _get_biome(key: Vector2i) -> Biome:
	var band := int(floor(float(key.y) / float(biome_band_length)))
	var count := Biome.size()
	# Modulo that stays positive even for negative bands (chunks_behind
	# means key.y can go slightly negative) — GDScript's % on a negative
	# int returns a negative result, which would index out of range.
	var index := ((band % count) + count) % count
	return index as Biome


## How many chunks into ITS OWN biome band this chunk is (0 = the very
## first chunk of a new biome). Used to place biome_grace_chunks
## of clear water right at the start of every biome. Separate function
## from _get_biome rather than
## folded into it, since one is "which biome" and the other is "how deep
## into it" — different callers want different halves of that math.
func _get_biome_band_local(key: Vector2i) -> int:
	var band := int(floor(float(key.y) / float(biome_band_length)))
	return key.y - band * biome_band_length


## Duck-types the target rather than casting to a specific Player class,
## since player.gd isn't part of this file's dependencies — tries the most
## likely property names in order, then falls back to a velocity vector's
## length if one of those exists instead. Returns 0.0 (treated as "calm")
## if none of them are present, so a missing/renamed property degrades to
## the old fixed-difficulty behavior rather than erroring.
##
## FIX (audit finding): "current_speed" now comes FIRST, ahead of
## "forward_speed". Previously "forward_speed" matched first for the
## real Player, but that property is player.gd's static BASE tuning
## export (22.0, never mutated) — it silently won every match and this
## whole function returned a frozen constant for the entire run,
## regardless of the ramp bonus / boost / drift bonus actually being
## applied. player.gd now publishes a live `current_speed` property every
## physics frame specifically so this duck-type check finds a real,
## moving value instead. Order matters here: keep "current_speed" ahead
## of "forward_speed" so a future target with both doesn't regress back
## to reading the static one.
func _get_target_speed() -> float:
	if _target == null:
		return 0.0
	for prop_name in ["current_speed", "speed", "forward_speed"]:
		var value = _target.get(prop_name)
		if value != null and (value is float or value is int):
			return float(value)
	for prop_name in ["velocity", "linear_velocity"]:
		var value = _target.get(prop_name)
		if value is Vector3:
			return value.length()
	return 0.0


## 0.0 (baseline/calm) .. 1.0 (fully eased to the sparser hard-speed
## settings), smoothstepped across speed_difficulty_low/high rather than a
## hard cutover, so the density/spacing shift reads as a gradual ramp
## instead of a sudden rules change mid-run.
func _get_speed_difficulty_factor() -> float:
	if speed_difficulty_high <= speed_difficulty_low:
		return 0.0
	var speed := _get_target_speed()
	# Explicit `: float` — clamp() is a generic builtin (works on int, float,
	# Vector2/3, etc.), so its return type is Variant and `:=` can't infer a
	# concrete type from it. Same fix pattern as the `segment` vars elsewhere
	# in this file that go through max()/min().
	var t: float = clamp(
		(speed - speed_difficulty_low) / (speed_difficulty_high - speed_difficulty_low), 0.0, 1.0
	)
	return smoothstep(0.0, 1.0, t)


func _populate_chunk(container: Node3D, key: Vector2i) -> void:
	var half := chunk_size * 0.5
	var biome := _get_biome(key)

	# CHANGED ORDER: obstacles/pillars/cube gates now spawn FIRST, before
	# scattered props — previously props went first. Reason: every one of
	# the lane-based systems below (_spawn_obstacle_row / _spawn_pillar_row
	# / _spawn_cube_gate_rows) guarantees SOME lane or gap stays open at its
	# own row_z, but that guarantee only holds if nothing else also lands
	# in that exact spot. Scattered rocks/cliffs used to be placed
	# completely independently of where those open lanes were, so a rock
	# could — and did — land right on top of what was supposed to be the
	# clear escape route, silently closing it (this is the real fix for
	# "a stone sits in the path, how does the player get through"). Now
	# each lane/wall function returns the open lane(s)/gap it left as a
	# list of "safe zone" rectangles, and prop placement below is told to
	# reject any spot inside one. Don't reorder these two blocks without
	# also moving the safe_zones hookup.
	var safe_zones: Array = []
	var in_biome_grace := _get_biome_band_local(key) < biome_grace_chunks
	# maxi(...) so whichever grace window reaches further forward wins — the
	# start-of-run grace early on, a continue grace whenever one is active.
	if key.y >= maxi(obstacle_grace_chunks, _continue_grace_until_y) and not in_biome_grace:
		match biome:
			Biome.PILLARS:
				safe_zones = _spawn_pillar_rows(container, half)
			Biome.CUBES:
				safe_zones = _spawn_cube_gate_rows(container, half)
			Biome.CASTLE:
				safe_zones = _spawn_castle_wall_rows(container, half)
			Biome.WINDMILL:
				pass  # calm biome — no dodge obstacles, so nothing to protect
			_:  # ROCKFIELD
				safe_zones = _spawn_obstacle_rows(container, half)

	# Same forward-distance-only grace convention as obstacle_grace_chunks
	# above, just a smaller window: chunk(s) right at spawn skip props and
	# collectibles entirely so the run visibly starts on plain, empty
	# ground instead of a fully-dressed world from frame one. Everything
	# past this window scatters as before. The biome transition buffer
	# reuses the same "skip scatter" treatment — it wasn't enough to just
	# stop dodge obstacles above; a chunk still cluttered with rocks/cliffs
	# doesn't read as a real open, clear breather, just a slightly emptier
	# obstacle course. Collectibles are the one exception: a Shade or two
	# is a small, unobtrusive reward, not clutter, so it still spawns here.
	if key.y >= props_grace_chunks and not in_biome_grace:
		# ROCKFIELD and PILLARS keep the full scatter density (an avenue of
		# monoliths still has loose rubble around it); WINDMILL and CUBES
		# use a lighter pass — WINDMILL because a calm biome shouldn't be
		# visually busy, CUBES because its own rows of gates already fill
		# the chunk and more scatter on top would just clutter the gates
		# players are trying to read at speed.
		match biome:
			Biome.WINDMILL, Biome.CUBES:
				_populate_sparse_props(container, half, safe_zones)
			Biome.CASTLE:
				# Themed scatter (well/banner/target/...) instead of the
				# generic rock/cliff pool — a castle yard shouldn't have
				# loose boulders lying around. See _populate_castle_props.
				_populate_castle_props(container, half, safe_zones)
			_:
				_populate_default_props(container, half, safe_zones)

		if biome == Biome.WINDMILL and _rng.randf() < windmill_landmark_chance:
			_spawn_windmill_landmark(container, half)
		elif biome == Biome.CASTLE and _rng.randf() < castle_landmark_chance:
			_spawn_castle_landmark(container, half)

	if key.y >= props_grace_chunks:
		_populate_collectibles(container, half)


## The original scatter loop, unchanged in spirit — now also rejects any
## candidate spot inside a `safe_zones` rectangle (see _populate_chunk's
## reordering note above) in addition to the existing prop-vs-prop
## spacing check. Extracted into its own function so ROCKFIELD/PILLARS
## and the lighter WINDMILL/CUBES pass (see _populate_sparse_props) can
## both reach it without duplicating the rejection-sampling logic.
func _populate_default_props(container: Node3D, half: float, safe_zones: Array) -> void:
	var prop_count := _rng.randi_range(props_per_chunk_min, props_per_chunk_max)
	var placed: Array[Vector2] = []
	for i in prop_count:
		var prop := _make_random_prop()
		var spot := _pick_spaced_position(half, props_min_spacing, props_placement_attempts, placed, safe_zones)
		placed.append(spot)
		prop.position = Vector3(spot.x, 0.0, spot.y)
		prop.rotation.y = _rng.randf_range(0.0, TAU)
		container.add_child(prop)


## Lighter scatter for WINDMILL (calm — shouldn't compete with the
## landmark) and CUBES (the cube rows already fill the space). Reuses the
## same spaced-placement helper at a capped, lower count rather than a
## whole separate placement algorithm.
func _populate_sparse_props(container: Node3D, half: float, safe_zones: Array) -> void:
	var prop_count := _rng.randi_range(0, 1)
	var placed: Array[Vector2] = []
	for i in prop_count:
		var prop := _make_random_prop()
		var spot := _pick_spaced_position(half, props_min_spacing, props_placement_attempts, placed, safe_zones)
		placed.append(spot)
		prop.position = Vector3(spot.x, 0.0, spot.y)
		prop.rotation.y = _rng.randf_range(0.0, TAU)
		container.add_child(prop)


## Deliberately not gated behind obstacle_grace_chunks like the obstacle
## rows above — the grace window exists so the player isn't dodging on
## frame one, but there's nothing unsafe about picking up a Shade, so the
## very first chunks are allowed to offer some.
func _populate_collectibles(container: Node3D, half: float) -> void:
	if _rng.randf() > collectible_spawn_chance:
		return
	var count := _rng.randi_range(collectibles_per_chunk_min, collectibles_per_chunk_max)
	for i in count:
		var shade := _make_collectible()
		shade.position = Vector3(
			_rng.randf_range(-half, half), 1.5, _rng.randf_range(-half, half)
		)
		container.add_child(shade)


## Rejection-sampling placement: tries up to `attempts` random spots inside
## [-half, half] on both axes, returns the first one at least `min_dist`
## away from every position already in `existing` AND outside every
## rectangle in `safe_zones` (expanded by `props_safe_zone_margin` so a
## prop's own radius can't still poke into a lane it was supposed to
## clear — see _populate_chunk's reordering note for why safe_zones
## exists at all). Falls back to the last spot tried if nothing clears
## every check in time, rather than looping forever or silently dropping
## the prop — same known trade-off as before, just now also applying to
## the safe-zone check, not only prop-vs-prop spacing. Known limitation,
## not solved here: this only checks spacing WITHIN one chunk cell — a
## prop near the edge of one chunk can still land close to a prop in the
## neighboring chunk, since each cell is populated independently. Minor
## and rare enough not to be worth the cross-chunk bookkeeping yet;
## revisit if it turns out to read as a problem in practice.
func _pick_spaced_position(
	half: float, min_dist: float, attempts: int, existing: Array[Vector2], safe_zones: Array = []
) -> Vector2:
	var candidate := Vector2.ZERO
	for attempt in attempts:
		candidate = Vector2(_rng.randf_range(-half, half), _rng.randf_range(-half, half))
		var ok := true
		for other in existing:
			if candidate.distance_to(other) < min_dist:
				ok = false
				break
		if ok:
			for zone in safe_zones:
				if _point_in_zone(candidate, zone):
					ok = false
					break
		if ok:
			return candidate
	return candidate


## `candidate.y` is Z, by the same (x, z)-as-Vector2(x, y) convention the
## rest of this file already uses for chunk-local positions.
func _point_in_zone(candidate: Vector2, zone: Dictionary) -> bool:
	var margin := props_safe_zone_margin
	return (
		candidate.x >= zone.x_min - margin and candidate.x <= zone.x_max + margin
		and candidate.y >= zone.z_min - margin and candidate.y <= zone.z_max + margin
	)


## FIX (audit finding — "unfair deaths" / "increase reaction time at high
## speed"): ROCKFIELD's plain spike-obstacle rows were the one biome that
## never eased with _get_speed_difficulty_factor() and never guaranteed a
## single consistent corridor across a chunk's rows — every row picked a
## fresh random open lane independently, which is the exact "gotcha at
## speed" problem the PILLARS biome's own header comment already
## diagnosed and fixed for itself (the open lane jumping from one side to
## the other between rows only ~12 units apart). ROCKFIELD is the DEFAULT
## biome — it spawns more than any other — so this was the single
## biggest source of "that felt unfair" in the whole generation system.
## Rewritten to match the Pillars/Cubes pattern exactly: one
## guaranteed-open lane reserved for the whole chunk, no two blocked
## lanes ever adjacent, and row count / row gap / blocked-lane fraction
## all ease toward sparser as real speed rises (now reading a real value —
## see the current_speed fix above).
func _spawn_obstacle_rows(container: Node3D, half: float) -> Array:
	var speed_factor := _get_speed_difficulty_factor()

	var effective_rows_max := int(round(lerp(
		float(obstacle_rows_per_chunk_max), float(obstacle_rows_per_chunk_min), speed_factor
	)))
	effective_rows_max = max(effective_rows_max, obstacle_rows_per_chunk_min)
	var row_count := _rng.randi_range(obstacle_rows_per_chunk_min, effective_rows_max)

	var effective_row_gap: float = lerp(
		obstacle_min_row_gap, obstacle_min_row_gap * speed_difficulty_gap_multiplier, speed_factor
	)
	var usable_length := chunk_size - effective_row_gap
	var segment: float = usable_length / max(row_count, 1)

	var guaranteed_open_lane := _rng.randi_range(0, obstacle_lane_count - 1)

	var zones: Array = []
	for i in row_count:
		var row_z := -half + i * segment + _rng.randf_range(0.0, max(segment, 0.01))
		zones += _spawn_obstacle_row(container, row_z, half, guaranteed_open_lane, speed_factor)
	return zones


## Same lane math as _spawn_pillar_row: one reserved corridor for the whole
## chunk, blocked lanes capped by (speed-eased) obstacle density, and no
## two blocked lanes ever adjacent so a spike cluster never reads as part
## of a continuous wall with its neighbor.
func _spawn_obstacle_row(
	container: Node3D, row_z: float, half: float, guaranteed_open_lane: int, speed_factor: float
) -> Array:
	var usable_half := half - obstacle_edge_margin
	var lane_width := (2.0 * usable_half) / obstacle_lane_count

	var candidates: Array[int] = []
	for i in obstacle_lane_count:
		if i != guaranteed_open_lane:
			candidates.append(i)
	# Manual Fisher-Yates using the seeded RNG, so this run is reproducible
	# from its seed the same way every other spawn decision here is.
	for i in range(candidates.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	# Density fraction defaults to "up to all-but-the-corridor" at calm
	# speed (matches the old 1..(lane_count-1) range's upper bound) and
	# eases down toward speed_difficulty_density_multiplier at high speed,
	# same shape as Pillars/Cubes.
	var effective_fraction: float = lerp(
		1.0, speed_difficulty_density_multiplier, speed_factor
	)
	var max_blocked: int = max(1, int(floor((obstacle_lane_count - 1) * effective_fraction)))

	var blocked_set := {}
	for lane_index in candidates:
		if blocked_set.size() >= max_blocked:
			break
		if blocked_set.has(lane_index - 1) or blocked_set.has(lane_index + 1):
			continue
		blocked_set[lane_index] = true

	for lane_index: int in blocked_set.keys():
		var lane_center := -usable_half + lane_width * (lane_index + 0.5)
		var obstacle := _make_obstacle()
		obstacle.position = Vector3(
			lane_center + _rng.randf_range(-lane_width * 0.15, lane_width * 0.15),
			0.0,
			row_z + _rng.randf_range(-1.5, 1.5)
		)
		obstacle.rotation.y = _rng.randf_range(0.0, TAU)
		container.add_child(obstacle)

	var zones: Array = []
	for lane_index in obstacle_lane_count:
		if not blocked_set.has(lane_index):
			var lane_center := -usable_half + lane_width * (lane_index + 0.5)
			zones.append({
				"x_min": lane_center - lane_width * 0.5,
				"x_max": lane_center + lane_width * 0.5,
				"z_min": row_z - 3.0,
				"z_max": row_z + 3.0,
			})
	return zones


## PILLARS biome — same lane math as _spawn_obstacle_row, but with a taller,
## thinner pillar mesh instead of a spike cluster so the silhouette reads
## as architectural rather than more ROCKFIELD danger-spikes.
##
## Reworked for fairness (previously blocked 60-80% of lanes with a fresh
## random open lane every row — dense, and the open lane could jump from
## one side of the chunk to the other between rows only ~9 units apart,
## which reads as a "gotcha" at speed rather than something reaction time
## can solve). Now:
##   - One lane is picked ONCE per chunk and reserved as a guaranteed-clear
##     corridor that every row in the chunk leaves open — a single straight,
##     clearly visible safe route through the whole section, not a
##     different gap to find each row.
##   - Blocked lanes are capped at pillar_max_blocked_lane_fraction (default
##     half), and two blocked lanes are never adjacent — that's the actual
##     "no pillars directly next to each other" fix, since adjacent-lane
##     pillars sit close enough to read (and nearly collide) as one
##     continuous wall instead of two separate, passable obstacles.
##   - Row count, row spacing, and blocked-lane fraction all ease toward
##     fewer/sparser as _get_speed_difficulty_factor() rises, so a fast run
##     gets easier layouts instead of the same density with less time to
##     react to it.
## Returns the combined open-lane safe zones across all rows in this chunk
## (see _populate_chunk).
func _spawn_pillar_rows(container: Node3D, half: float) -> Array:
	var speed_factor := _get_speed_difficulty_factor()

	var effective_rows_max := int(round(lerp(
		float(pillar_rows_per_chunk_max), float(pillar_rows_per_chunk_min), speed_factor
	)))
	effective_rows_max = max(effective_rows_max, pillar_rows_per_chunk_min)
	var row_count := _rng.randi_range(pillar_rows_per_chunk_min, effective_rows_max)

	# Explicit `: float` — lerp() is a generic builtin (also works on
	# Vector2/3/Color/etc.), so its return type is Variant and `:=` can't
	# infer a concrete type from it. Same fix as `t` in
	# _get_speed_difficulty_factor() above.
	var effective_row_gap: float = lerp(
		pillar_min_row_gap, pillar_min_row_gap * speed_difficulty_gap_multiplier, speed_factor
	)
	var usable_length := chunk_size - effective_row_gap
	# Explicit `: float` — max()'s engine binding returns a generic
	# Variant (int/float overloaded), which `:=` can't infer a concrete
	# type from. Same fix as moon_rig.gd's `progress` (see README).
	var segment: float = usable_length / max(row_count, 1)

	var guaranteed_open_lane := _rng.randi_range(0, pillar_lane_count - 1)

	var zones: Array = []
	for i in row_count:
		var row_z := -half + i * segment + _rng.randf_range(0.0, max(segment, 0.01))
		zones += _spawn_pillar_row(container, row_z, half, guaranteed_open_lane, speed_factor)
	return zones


func _spawn_pillar_row(
	container: Node3D, row_z: float, half: float, guaranteed_open_lane: int, speed_factor: float
) -> Array:
	var usable_half := half - obstacle_edge_margin
	var lane_width := (2.0 * usable_half) / pillar_lane_count

	# Every lane except the reserved corridor is a candidate for blocking.
	var candidates: Array[int] = []
	for i in pillar_lane_count:
		if i != guaranteed_open_lane:
			candidates.append(i)
	for i in range(candidates.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	# Explicit `: float`, same lerp()-returns-Variant reason as above.
	var effective_fraction: float = lerp(
		pillar_max_blocked_lane_fraction,
		pillar_max_blocked_lane_fraction * speed_difficulty_density_multiplier,
		speed_factor
	)
	# Explicit `: int` — max() is a generic builtin (also works on float),
	# so its return type is Variant and `:=` can't infer a concrete type
	# from it. Same fix as `t`/`effective_row_gap`/`effective_fraction` above.
	var max_blocked: int = max(1, int(floor(pillar_lane_count * effective_fraction)))

	# Greedily accept shuffled candidates, skipping any lane directly next
	# to one already blocked, so no two pillars in this row ever end up in
	# neighboring lanes with nothing between them.
	var blocked_set := {}
	for lane_index in candidates:
		if blocked_set.size() >= max_blocked:
			break
		if blocked_set.has(lane_index - 1) or blocked_set.has(lane_index + 1):
			continue
		blocked_set[lane_index] = true

	# `: int` on the loop var — blocked_set.keys() returns an untyped Array
	# (Variant elements) since blocked_set itself is an untyped Dictionary,
	# so without this the parser can't infer a type for lane_center below
	# (it does arithmetic on lane_index).
	for lane_index: int in blocked_set.keys():
		var lane_center := -usable_half + lane_width * (lane_index + 0.5)
		var pillar := _make_pillar()
		pillar.position = Vector3(
			lane_center + _rng.randf_range(-lane_width * 0.1, lane_width * 0.1),
			0.0,
			row_z + _rng.randf_range(-1.0, 1.0)
		)
		container.add_child(pillar)

	var zones: Array = []
	for lane_index in pillar_lane_count:
		if not blocked_set.has(lane_index):
			var lane_center := -usable_half + lane_width * (lane_index + 0.5)
			zones.append({
				"x_min": lane_center - lane_width * 0.5,
				"x_max": lane_center + lane_width * 0.5,
				"z_min": row_z - 3.0,
				"z_max": row_z + 3.0,
			})
	return zones


## Tall thin box, not a prism — a monolith avenue reads as architectural
## with a flat-topped silhouette; a tapered prism would read as more
## ROCKFIELD cliff. Collision shrunk on X/Z slightly (same 0.85 factor
## _make_cliff uses) so the hitbox tracks the mesh's actual footprint
## rather than a full bounding box.
func _make_pillar() -> Node3D:
	var area := _acquire_pooled("pillar")
	if area == null:
		area = Area3D.new()
		area.add_to_group("obstacle")
		var new_mesh_instance := _make_paper_mesh_instance(BoxMesh.new())
		area.add_child(new_mesh_instance)
		var new_collision := CollisionShape3D.new()
		new_collision.shape = BoxShape3D.new()
		area.add_child(new_collision)
		area.body_entered.connect(_on_obstacle_body_entered)
		area.set_meta("pool_sig", "pillar")

	var mesh_instance: MeshInstance3D = area.get_child(0)
	var collision: CollisionShape3D = area.get_child(1)
	var mesh: BoxMesh = mesh_instance.mesh
	mesh.size = Vector3(
		_rng.randf_range(2.0, 3.2), _rng.randf_range(14.0, 26.0), _rng.randf_range(2.0, 3.2)
	)
	mesh_instance.position.y = mesh.size.y * 0.5
	var shape: BoxShape3D = collision.shape
	shape.size = mesh.size * Vector3(0.85, 1.0, 0.85)
	collision.position.y = mesh.size.y * 0.5
	return area


## CUBES biome — same lane/guaranteed-corridor/no-adjacent-blocks mechanic
## as _spawn_pillar_rows, but reads as an "obstacle course" of floating
## boxes with deliberate GATES rather than a monolith avenue. See the
## Biome enum doc comment above and the "Cube Gates" export group for the
## per-biome knobs this pulls from (cube_lane_count, cube_rows_per_chunk_*,
## cube_min_row_gap, cube_max_blocked_lane_fraction, cube_size_*).
## Returns the combined open-lane safe zones across all rows in this chunk
## (see _populate_chunk).
func _spawn_cube_gate_rows(container: Node3D, half: float) -> Array:
	var speed_factor := _get_speed_difficulty_factor()

	var effective_rows_max := int(round(lerp(
		float(cube_rows_per_chunk_max), float(cube_rows_per_chunk_min), speed_factor
	)))
	effective_rows_max = max(effective_rows_max, cube_rows_per_chunk_min)
	var row_count := _rng.randi_range(cube_rows_per_chunk_min, effective_rows_max)

	# Explicit `: float` — lerp() is a generic builtin, same Variant-return
	# reason as _spawn_pillar_rows' effective_row_gap above.
	var effective_row_gap: float = lerp(
		cube_min_row_gap, cube_min_row_gap * speed_difficulty_gap_multiplier, speed_factor
	)
	var usable_length := chunk_size - effective_row_gap
	# Explicit `: float` — same max()-returns-Variant reason as
	# _spawn_pillar_rows' segment above.
	var segment: float = usable_length / max(row_count, 1)

	var guaranteed_open_lane := _rng.randi_range(0, cube_lane_count - 1)

	var zones: Array = []
	for i in row_count:
		var row_z := -half + i * segment + _rng.randf_range(0.0, max(segment, 0.01))
		zones += _spawn_cube_gate_row(container, row_z, half, guaranteed_open_lane, speed_factor)
	return zones


func _spawn_cube_gate_row(
	container: Node3D, row_z: float, half: float, guaranteed_open_lane: int, speed_factor: float
) -> Array:
	var usable_half := half - obstacle_edge_margin
	var lane_width := (2.0 * usable_half) / cube_lane_count

	# Every lane except the reserved corridor is a candidate for blocking.
	var candidates: Array[int] = []
	for i in cube_lane_count:
		if i != guaranteed_open_lane:
			candidates.append(i)
	for i in range(candidates.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	# Explicit `: float`, same lerp()-returns-Variant reason as above.
	var effective_fraction: float = lerp(
		cube_max_blocked_lane_fraction,
		cube_max_blocked_lane_fraction * speed_difficulty_density_multiplier,
		speed_factor
	)
	# Explicit `: int` — max() is a generic builtin, same Variant-return
	# reason as _spawn_pillar_row's max_blocked above.
	var max_blocked: int = max(1, int(floor(cube_lane_count * effective_fraction)))

	# Greedily accept shuffled candidates, skipping any lane directly next
	# to one already blocked — same "no two obstacles in neighboring lanes"
	# fairness fix as _spawn_pillar_row, so gates never merge into one
	# wider wall than intended.
	var blocked_set := {}
	for lane_index in candidates:
		if blocked_set.size() >= max_blocked:
			break
		if blocked_set.has(lane_index - 1) or blocked_set.has(lane_index + 1):
			continue
		blocked_set[lane_index] = true

	# `: int` on the loop var, same untyped-Dictionary-keys() reason as
	# _spawn_pillar_row above.
	for lane_index: int in blocked_set.keys():
		var lane_center := -usable_half + lane_width * (lane_index + 0.5)
		var cube := _make_cube()
		cube.position = Vector3(
			lane_center + _rng.randf_range(-lane_width * 0.1, lane_width * 0.1),
			0.0,
			row_z + _rng.randf_range(-1.0, 1.0)
		)
		container.add_child(cube)

	var zones: Array = []
	for lane_index in cube_lane_count:
		if not blocked_set.has(lane_index):
			var lane_center := -usable_half + lane_width * (lane_index + 0.5)
			zones.append({
				"x_min": lane_center - lane_width * 0.5,
				"x_max": lane_center + lane_width * 0.5,
				"z_min": row_z - 3.0,
				"z_max": row_z + 3.0,
			})
	return zones


## Boxy floating block, sized independently on each axis within
## cube_size_min/max so cubes read as a chunky obstacle-course kit rather
## than identical dice. Floated at half its own height, same convention
## as _make_pillar, so it rests on the water plane rather than sinking
## into it. Collision shrunk 0.85 on X/Z/Y, same fudge _make_pillar/
## _make_cliff use so the hitbox tracks the mesh's actual footprint.
func _make_cube() -> Node3D:
	var area := _acquire_pooled("cube")
	if area == null:
		area = Area3D.new()
		area.add_to_group("obstacle")
		var new_mesh_instance := _make_paper_mesh_instance(BoxMesh.new())
		area.add_child(new_mesh_instance)
		var new_collision := CollisionShape3D.new()
		new_collision.shape = BoxShape3D.new()
		area.add_child(new_collision)
		area.body_entered.connect(_on_obstacle_body_entered)
		area.set_meta("pool_sig", "cube")

	var mesh_instance: MeshInstance3D = area.get_child(0)
	var collision: CollisionShape3D = area.get_child(1)
	var mesh: BoxMesh = mesh_instance.mesh
	mesh.size = Vector3(
		_rng.randf_range(cube_size_min, cube_size_max),
		_rng.randf_range(cube_size_min, cube_size_max),
		_rng.randf_range(cube_size_min, cube_size_max)
	)
	mesh_instance.position.y = mesh.size.y * 0.5
	var shape: BoxShape3D = collision.shape
	shape.size = mesh.size * Vector3(0.85, 0.85, 0.85)
	collision.position.y = mesh.size.y * 0.5
	return area


## Picks and places the WINDMILL biome's landmark. Prefers an actual
## uploaded scene from `windmill_scenes` if any are assigned; only falls
## back to the code-built primitive version (_make_paper_windmill_landmark)
## when that array is empty. Neither path needs any rotation setup HERE
## anymore — a real instanced scene rotates on its own via
## windmill_blades.gd already attached to its blade node the moment it's
## added to the tree, and the primitive fallback below is now static
## (it was previously spun by a manual Tween in this script, which is
## exactly the duplicated logic windmill_blades.gd replaces — removed).
func _spawn_windmill_landmark(container: Node3D, half: float) -> void:
	var windmill: Node3D
	if windmill_scenes.size() > 0:
		var scene: PackedScene = windmill_scenes[_rng.randi_range(0, windmill_scenes.size() - 1)]
		windmill = scene.instantiate()
	else:
		windmill = _make_paper_windmill_landmark()

	windmill.position = Vector3(
		_rng.randf_range(-half * 0.7, half * 0.7), 0.0, _rng.randf_range(-half, half)
	)
	windmill.rotation.y = _rng.randf_range(0.0, TAU)
	container.add_child(windmill)


## WINDMILL biome landmark FALLBACK — decorative ONLY: no Area3D, no
## collision, doesn't join the "obstacle" group, so it can never end a
## run. Built from primitives in the paper palette (tower = PrismMesh,
## blades = thin PrismMesh fins). Only used when `windmill_scenes` is
## empty — see _spawn_windmill_landmark above, which prefers your actual
## uploaded windmill assets once any are assigned. Static (no rotation)
## now that the manual Tween-spin has been removed from this file — if
## you want this fallback to spin too, attach windmill_blades.gd to a
## dedicated blade node the same way you already did on the real scenes,
## rather than reintroducing a second rotation mechanism here.
func _make_paper_windmill_landmark() -> Node3D:
	var root := Node3D.new()

	var tower := PrismMesh.new()
	tower.size = Vector3(2.0, _rng.randf_range(10.0, 16.0), 2.0)
	var tower_instance := _make_paper_mesh_instance(tower)
	tower_instance.position.y = tower.size.y * 0.5
	root.add_child(tower_instance)

	var blade_count := 4
	for i in blade_count:
		var blade := PrismMesh.new()
		blade.size = Vector3(0.3, 3.5, 1.4)
		var blade_instance := _make_paper_mesh_instance(blade)
		blade_instance.position = Vector3(0.0, tower.size.y, 0.0)
		blade_instance.position.y += blade.size.y * 0.5
		blade_instance.rotation.z = (TAU / blade_count) * i
		root.add_child(blade_instance)

	return root


## CASTLE biome — same lane/guaranteed-corridor/no-adjacent-blocks
## mechanic as _spawn_pillar_rows/_spawn_cube_gate_rows, but blocks lanes
## with real wall/tower scenes (castle_wall_scenes) instead of a
## primitive box, so the avenue reads as a castle gate corridor rather
## than more monoliths. Falls back to the primitive pillar
## (_make_pillar) if no scenes are assigned yet — see _make_castle_wall_piece.
func _spawn_castle_wall_rows(container: Node3D, half: float) -> Array:
	var speed_factor := _get_speed_difficulty_factor()

	var effective_rows_max := int(round(lerp(
		float(castle_rows_per_chunk_max), float(castle_rows_per_chunk_min), speed_factor
	)))
	effective_rows_max = max(effective_rows_max, castle_rows_per_chunk_min)
	var row_count := _rng.randi_range(castle_rows_per_chunk_min, effective_rows_max)

	var effective_row_gap: float = lerp(
		castle_min_row_gap, castle_min_row_gap * speed_difficulty_gap_multiplier, speed_factor
	)
	var usable_length := chunk_size - effective_row_gap
	var segment: float = usable_length / max(row_count, 1)

	var guaranteed_open_lane := _rng.randi_range(0, castle_lane_count - 1)

	var zones: Array = []
	for i in row_count:
		var row_z := -half + i * segment + _rng.randf_range(0.0, max(segment, 0.01))
		zones += _spawn_castle_wall_row(container, row_z, half, guaranteed_open_lane, speed_factor)
	return zones


func _spawn_castle_wall_row(
	container: Node3D, row_z: float, half: float, guaranteed_open_lane: int, speed_factor: float
) -> Array:
	var usable_half := half - obstacle_edge_margin
	var lane_width := (2.0 * usable_half) / castle_lane_count

	var candidates: Array[int] = []
	for i in castle_lane_count:
		if i != guaranteed_open_lane:
			candidates.append(i)
	for i in range(candidates.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	var effective_fraction: float = lerp(
		castle_max_blocked_lane_fraction,
		castle_max_blocked_lane_fraction * speed_difficulty_density_multiplier,
		speed_factor
	)
	var max_blocked: int = max(1, int(floor(castle_lane_count * effective_fraction)))

	var blocked_set := {}
	for lane_index in candidates:
		if blocked_set.size() >= max_blocked:
			break
		if blocked_set.has(lane_index - 1) or blocked_set.has(lane_index + 1):
			continue
		blocked_set[lane_index] = true

	for lane_index: int in blocked_set.keys():
		var lane_center := -usable_half + lane_width * (lane_index + 0.5)
		var wall := _make_castle_wall_piece()
		wall.position = Vector3(
			lane_center + _rng.randf_range(-lane_width * 0.1, lane_width * 0.1),
			0.0,
			row_z + _rng.randf_range(-1.0, 1.0)
		)
		# Real wall/tower scenes have a "face" (front/back reads
		# differently), so only jitter yaw slightly instead of a full
		# random spin — the primitive pillar fallback is a box, so a full
		# spin there is harmless and keeps its existing look.
		if castle_wall_scenes.is_empty():
			wall.rotation.y = _rng.randf_range(0.0, TAU)
		else:
			wall.rotation.y = _rng.randf_range(-0.08, 0.08)
		container.add_child(wall)

	var zones: Array = []
	for lane_index in castle_lane_count:
		if not blocked_set.has(lane_index):
			var lane_center := -usable_half + lane_width * (lane_index + 0.5)
			zones.append({
				"x_min": lane_center - lane_width * 0.5,
				"x_max": lane_center + lane_width * 0.5,
				"z_min": row_z - 3.0,
				"z_max": row_z + 3.0,
			})
	return zones


## Builds one lane-blocking castle wall/tower obstacle. Prefers a real
## imported scene from castle_wall_scenes; falls back to the primitive
## pillar (_make_pillar) when the array is empty, same "don't break
## before the asset is wired up" pattern as _spawn_windmill_landmark.
func _make_castle_wall_piece() -> Node3D:
	if castle_wall_scenes.is_empty():
		return _make_pillar()

	# Perf fix: this used to instantiate() a fresh copy of the real FBX
	# scene (plus a full tree-walk in _get_visual_aabb) on EVERY spawn and
	# queue_free() it on every chunk recycle — the only builder in this
	# file that bypassed the node pool. In an endless runner recycling ~15
	# active chunks continuously, that's a steady stream of heavy
	# alloc/free churn, which is what was reading as stutter/lost
	# smoothness on device. Pooled per scene index now, same as every
	# other builder here — same signature (same source asset) always
	# means same AABB/collision box, so it's safe to reuse untouched.
	var scene_index := _rng.randi_range(0, castle_wall_scenes.size() - 1)
	var sig := "castle_wall_%d" % scene_index

	var area := _acquire_pooled(sig)
	if area == null:
		var scene: PackedScene = castle_wall_scenes[scene_index]
		var visual: Node3D = scene.instantiate()
		visual.name = "Visual"
		visual.scale = Vector3.ONE * castle_asset_scale

		area = Area3D.new()
		area.add_to_group("obstacle")
		area.add_child(visual)

		# Real FBX imports don't come with a pre-set .size the way this
		# file's primitive meshes do (BoxMesh.size, PrismMesh.size, etc.), so
		# the hitbox is derived from the instanced scene's own visual bounds
		# via _get_visual_aabb instead of a hand-tuned constant per asset —
		# same 0.85 shrink-to-visible-footprint factor _make_pillar()/
		# _make_cliff() already use, so it doesn't feel unfair relative to
		# the rest of the obstacle roster. Only run once per pooled node now
		# (on first build), not on every spawn.
		var aabb := _get_visual_aabb(visual)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = aabb.size * castle_asset_scale * Vector3(0.85, 1.0, 0.85)
		collision.shape = shape
		collision.position = (aabb.position + aabb.size * 0.5) * castle_asset_scale
		area.add_child(collision)

		area.body_entered.connect(_on_obstacle_body_entered)
		area.set_meta("pool_sig", sig)

	return area


## Walks an instantiated scene's tree and merges every MeshInstance3D's
## local AABB (transformed up to the root's own local space) into one
## bounding box. Needed because real FBX imports have no exported
## `.size` the way BoxMesh/PrismMesh do — this is the fallback that lets
## _make_castle_wall_piece build a correctly-sized collision box for
## whatever asset ends up in castle_wall_scenes, sight unseen. Returns a
## small sane default box if the scene has no mesh at all (shouldn't
## happen for these assets, but better than a zero-size hitbox).
func _get_visual_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	if root is MeshInstance3D and root.mesh != null:
		result = root.mesh.get_aabb()
		found = true

	var stack: Array = []
	for child in root.get_children():
		stack.append([child, Transform3D.IDENTITY])

	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var node: Node = entry[0]
		var parent_xform: Transform3D = entry[1]
		var node_xform := parent_xform
		if node is Node3D:
			node_xform = parent_xform * node.transform
		if node is MeshInstance3D and node.mesh != null:
			var world_aabb: AABB = node_xform * node.mesh.get_aabb()
			if not found:
				result = world_aabb
				found = true
			else:
				result = result.merge(world_aabb)
		for child in node.get_children():
			stack.append([child, node_xform])

	if not found:
		return AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 4.0, 2.0))
	return result


## Picks and places the CASTLE biome's landmark — a big tower silhouette
## off to the side of the lane grid, same placement convention as
## _spawn_windmill_landmark. Decorative only, no collision, so it can
## never end a run. Skipped entirely (not a primitive fallback) if no
## scenes are assigned — a generic box tower wouldn't read as "castle"
## the way the windmill primitive fallback reads as "windmill".
func _spawn_castle_landmark(container: Node3D, half: float) -> void:
	if castle_landmark_scenes.is_empty():
		return
	# Perf fix: pooled now instead of instantiate()/queue_free() every
	# chunk — see _make_castle_wall_piece for why. Decorative-only, no
	# Area3D, so the generic _acquire_pooled/_release_to_pool path just
	# needs visibility toggling, which it already does.
	var scene_index := _rng.randi_range(0, castle_landmark_scenes.size() - 1)
	var sig := "castle_landmark_%d" % scene_index
	var landmark := _acquire_pooled(sig)
	if landmark == null:
		var scene: PackedScene = castle_landmark_scenes[scene_index]
		landmark = scene.instantiate()
		landmark.scale = Vector3.ONE * castle_asset_scale
		landmark.set_meta("pool_sig", sig)
	landmark.position = Vector3(
		_rng.randf_range(-half * 0.7, half * 0.7), 0.0, _rng.randf_range(-half, half)
	)
	landmark.rotation.y = _rng.randf_range(0.0, TAU)
	container.add_child(landmark)


## Lightweight CASTLE-themed scatter — well, banner, target, dummy,
## bridge fragments — same spaced-placement/safe-zone rejection as
## _populate_default_props/_populate_sparse_props, just pulling from
## castle_prop_scenes instead of the generic rock/cliff pool so the
## biome reads as a castle yard rather than more paper scenery. Silently
## spawns nothing if the array is empty.
func _populate_castle_props(container: Node3D, half: float, safe_zones: Array) -> void:
	if castle_prop_scenes.is_empty():
		return
	var prop_count := _rng.randi_range(0, 2)
	var placed: Array[Vector2] = []
	for i in prop_count:
		# Perf fix: pooled now instead of instantiate()/queue_free() every
		# chunk — see _make_castle_wall_piece for why.
		var scene_index := _rng.randi_range(0, castle_prop_scenes.size() - 1)
		var sig := "castle_prop_%d" % scene_index
		var prop := _acquire_pooled(sig)
		if prop == null:
			var scene: PackedScene = castle_prop_scenes[scene_index]
			prop = scene.instantiate()
			prop.scale = Vector3.ONE * castle_asset_scale
			prop.set_meta("pool_sig", sig)
		var spot := _pick_spaced_position(half, props_min_spacing, props_placement_attempts, placed, safe_zones)
		placed.append(spot)
		prop.position = Vector3(spot.x, 0.0, spot.y)
		prop.rotation.y = _rng.randf_range(0.0, TAU)
		container.add_child(prop)


func _make_random_prop() -> Node3D:
	# Paper-island (flat box slab) removed from the pool on purpose — it
	# read as a flat, featureless mesh in-game rather than folded paper.
	# Only rock clusters and cliffs spawn until a proper folded-island
	# shape replaces it.
	match _rng.randi_range(0, 1):
		0:
			return _make_rock_cluster()
		_:
			return _make_cliff()


## Fetch-or-create a shared StandardMaterial3D for a given (color, emission)
## combo. `cache_key` just needs to be stable and unique per distinct look —
## callers pass a short string like "paper" or "spike_black" rather than
## re-deriving one from the color values. Pass emission_color with alpha > 0
## to enable emission (used by the Shade collectible glow); leave it at the
## default (alpha 0) for plain albedo-only materials like paper props and
## obstacle spikes.
func _get_cached_material(
	cache_key: String, color: Color, emission_color: Color = Color(0.0, 0.0, 0.0, 0.0)
) -> StandardMaterial3D:
	if _material_cache.has(cache_key):
		return _material_cache[cache_key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if emission_color.a > 0.0:
		mat.emission_enabled = true
		mat.emission = emission_color
		mat.emission_energy_multiplier = 1.6
	if outline_material:
		mat.next_pass = outline_material
	_material_cache[cache_key] = mat
	return mat


func _make_paper_mesh_instance(mesh: Mesh) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _get_cached_material("paper", PAPER_COLOR)
	return mesh_instance


func _make_rock_cluster() -> Node3D:
	var boulder_count := _rng.randi_range(2, 4)
	var sig := "rock_%d" % boulder_count
	var area := _acquire_pooled(sig)
	if area == null:
		area = Area3D.new()
		area.add_to_group("obstacle")
		for i in boulder_count:
			var new_mesh_instance := _make_paper_mesh_instance(SphereMesh.new())
			area.add_child(new_mesh_instance)
			# One collision sphere per boulder, sized to that boulder alone —
			# a single sphere wrapping the whole cluster used to block a much
			# wider circle of "air" than any boulder actually occupied, which
			# is exactly the "there's a gap but it still collides" complaint.
			var new_collision := CollisionShape3D.new()
			new_collision.shape = SphereShape3D.new()
			area.add_child(new_collision)
		area.body_entered.connect(_on_obstacle_body_entered)
		area.set_meta("pool_sig", sig)

	# Re-randomize every boulder pair regardless of whether `area` is
	# freshly built above or was just pulled out of the pool — this is
	# what gives a reused node the same visual variety a brand-new one
	# would have had.
	for i in boulder_count:
		var mesh_instance: MeshInstance3D = area.get_child(i * 2)
		var collision: CollisionShape3D = area.get_child(i * 2 + 1)
		var mesh: SphereMesh = mesh_instance.mesh
		mesh.radius = _rng.randf_range(1.5, 3.5)
		mesh.height = mesh.radius * 1.6
		mesh.radial_segments = 8
		mesh.rings = 5
		var offset := Vector3(
			_rng.randf_range(-2.0, 2.0), mesh.radius * 0.3, _rng.randf_range(-2.0, 2.0)
		)
		mesh_instance.position = offset
		mesh_instance.scale.y = _rng.randf_range(0.6, 0.9)
		var shape: SphereShape3D = collision.shape
		shape.radius = mesh.radius
		collision.position = offset
	return area


func _make_cliff() -> Node3D:
	var area := _acquire_pooled("cliff")
	if area == null:
		area = Area3D.new()
		area.add_to_group("obstacle")
		var new_mesh_instance := _make_paper_mesh_instance(PrismMesh.new())
		area.add_child(new_mesh_instance)
		# A box, not a sphere sized to the diagonal — the old version used the
		# corner-to-center distance as a sphere radius, which over-covers along
		# the faces (where the player actually approaches from) by roughly 40%.
		# Slightly shrunk on X/Z besides, since a prism's silhouette narrows
		# toward its ridge and a full-width box still over-covers there.
		var new_collision := CollisionShape3D.new()
		new_collision.shape = BoxShape3D.new()
		area.add_child(new_collision)
		area.body_entered.connect(_on_obstacle_body_entered)
		area.set_meta("pool_sig", "cliff")

	var mesh_instance: MeshInstance3D = area.get_child(0)
	var collision: CollisionShape3D = area.get_child(1)
	var mesh: PrismMesh = mesh_instance.mesh
	mesh.size = Vector3(
		_rng.randf_range(4.0, 7.0), _rng.randf_range(10.0, 22.0), _rng.randf_range(4.0, 7.0)
	)
	mesh_instance.position.y = mesh.size.y * 0.5
	var shape: BoxShape3D = collision.shape
	shape.size = mesh.size * Vector3(0.8, 1.0, 0.8)
	collision.position.y = mesh.size.y * 0.5
	return area


## Phase 6 — an obstacle is an Area3D (not a StaticBody3D) on purpose: a
## solid physics body would let move_and_slide() collide with and shove the
## boat, which fights the arcade steering the same way RigidBody3D would.
## An Area3D just detects overlap and lets the game logic decide what
## happens, same "detect, don't simulate" approach as the rest of the
## controller.
func _make_obstacle() -> Node3D:
	# Jagged, near-black spike cluster — deliberately reads as a different
	# silhouette and value from the pale rounded rock props, so the player
	# can tell "scenery" from "dodge this" at a glance without needing a
	# saturated warning color the art direction rules out.
	var spike_count := _rng.randi_range(2, 4)
	var sig := "obstacle_%d" % spike_count
	var area := _acquire_pooled(sig)
	if area == null:
		area = Area3D.new()
		area.add_to_group("obstacle")
		for i in spike_count:
			var new_mesh_instance := MeshInstance3D.new()
			new_mesh_instance.mesh = CylinderMesh.new()
			area.add_child(new_mesh_instance)
			# One collider per spike, sized to that spike's own base radius —
			# same fix as the rock cluster. A cylinder rather than a sphere
			# since the spike doesn't taper away in collision the way it does
			# visually, but it at least tracks each spike's real footprint
			# instead of one sphere spanning the whole cluster.
			var new_collision := CollisionShape3D.new()
			new_collision.shape = CylinderShape3D.new()
			area.add_child(new_collision)
		area.body_entered.connect(_on_obstacle_body_entered)
		area.set_meta("pool_sig", sig)

	for i in spike_count:
		var mesh_instance: MeshInstance3D = area.get_child(i * 2)
		var collision: CollisionShape3D = area.get_child(i * 2 + 1)
		var mesh: CylinderMesh = mesh_instance.mesh
		mesh.top_radius = 0.05
		mesh.bottom_radius = _rng.randf_range(0.8, 1.6)
		mesh.height = _rng.randf_range(3.0, 6.0)
		mesh.radial_segments = 6
		# Alternate pure black in with the near-black — the brief calls for
		# a strict white/black/gray palette, and pure black on some spikes
		# reads as more strongly "danger" than a uniform dark gray would.
		var is_pure_black := _rng.randf() < 0.5
		mesh_instance.material_override = _get_cached_material(
			"spike_black" if is_pure_black else "spike_near_black",
			Color(0.0, 0.0, 0.0, 1.0) if is_pure_black else Color(0.05, 0.05, 0.06, 1.0)
		)
		var offset := Vector3(_rng.randf_range(-1.0, 1.0), mesh.height * 0.5, _rng.randf_range(-1.0, 1.0))
		mesh_instance.position = offset
		var shape: CylinderShape3D = collision.shape
		shape.radius = mesh.bottom_radius
		shape.height = mesh.height
		collision.position = offset
	return area


func _on_obstacle_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		GameManager.change_state(GameManager.GameState.GAME_OVER)


## Public API for the "continue with Shades" revive flow (Subway Surfers
## keys-style): call this once, right when the player chooses to continue,
## BEFORE flipping GameManager back to PLAYING. It does two things:
##
## 1. Immediately clears every currently-spawned hazard (anything in the
##    "obstacle" group — rocks, cliffs, spike clusters, pillars, cube
##    gates, castle walls; every lethal prop in this file
##    already tags itself into that one group) inside the current chunk
##    window, so control doesn't hand back to a boat that's still
##    overlapping — or one chunk-row away from — whatever killed it.
## 2. Remembers a forward-distance grace window (continue_grace_chunks) so
##    chunks that stream in fresh over the next few seconds of travel also
##    spawn hazard-free, giving the player a real runway to get moving
##    again instead of a single clear chunk followed immediately by a wall.
##
## Deliberately does NOT touch score, position, GameManager state, or
## Shades balance — this function only ever clears world hazards. Spending
## the 50 Shades and flipping back to PLAYING belong to whatever owns the
## continue-prompt UI, since this script has no business knowing the cost
## or the currency API.
func grant_continue_grace(chunks: int = continue_grace_chunks) -> void:
	if _target == null:
		return
	var current_y := floori(-_target.global_position.z / chunk_size)
	_continue_grace_until_y = current_y + chunks

	for key: Vector2i in _chunks.keys():
		if key.y < current_y - chunks_behind or key.y > _continue_grace_until_y:
			continue
		var container: Node3D = _chunks[key]
		for node in container.get_children():
			if node is Node and node.is_in_group("obstacle"):
				node.queue_free()


## Shades — the collectible that fills the multiplier meter, grants a flat
## score bonus, and banks currency (see player.gd's collect_shade). Area3D,
## same "detect, don't simulate" reasoning as the obstacles above, but on
## overlap it rewards instead of ending the run.
##
## Visually a thin folded diamond (two stacked, oppositely-flipped
## PrismMeshes — a crude bipyramid) rather than a rounded/spiky primitive,
## so it doesn't share a silhouette with rocks or obstacle spikes — the
## original Moon Shard look, kept as-is per feedback that the sunglasses
## silhouette read worse than this did. Each Shade randomly picks one of
## SHADE_COLORS (green or red) — see the note on that constant above for
## why this deliberately breaks the strict white/black/gray palette.
func _make_collectible() -> Node3D:
	var area := _acquire_pooled("collectible")
	if area == null:
		area = Area3D.new()
		area.add_to_group("collectible")

		# Meshes live under a visual-only wrapper, NOT directly under the
		# Area3D — see _play_collect_pop below for why: scaling the Area3D
		# itself down to zero also scales its CollisionShape3D to zero, which
		# Jolt logs as an invalid/singular transform. Scaling this wrapper
		# instead leaves the Area3D's own transform untouched at all times.
		var visual := Node3D.new()
		visual.name = "Visual"
		area.add_child(visual)

		var top := PrismMesh.new()
		top.size = Vector3(0.9, 0.7, 0.9)
		var top_instance := MeshInstance3D.new()
		top_instance.name = "TopHalf"
		top_instance.mesh = top
		visual.add_child(top_instance)

		var bottom := PrismMesh.new()
		bottom.size = Vector3(0.9, 0.7, 0.9)
		var bottom_instance := MeshInstance3D.new()
		bottom_instance.name = "BottomHalf"
		bottom_instance.mesh = bottom
		# Flip the second prism upside-down and butt it against the first so
		# the pair reads as one faceted gem rather than two separate wedges.
		bottom_instance.rotation.x = PI
		bottom_instance.position.y = -0.7
		visual.add_child(bottom_instance)

		# Single sphere collider is plenty here — unlike the rocks/cliffs above,
		# a Shade is small and roughly uniform in every direction, so there's no
		# "gap but it still collides" complaint to solve.
		var new_collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.9
		new_collision.shape = shape
		area.add_child(new_collision)

		area.body_entered.connect(_on_collectible_body_entered.bind(area))
		area.set_meta("pool_sig", "collectible")

	# Collected Shades free themselves outright at the end of their pop
	# tween (see _play_collect_pop) rather than going back through
	# _recycle_chunk, so only UNcollected ones — which never had their
	# scale/monitoring touched — actually reach this reuse path. Still,
	# resetting them here is cheap insurance against future changes to
	# that pop flow leaving a pooled instance in a half-popped state.
	var visual: Node3D = area.get_node("Visual")
	visual.scale = Vector3.ONE
	# get_child(1) instead of get_node("CollisionShape3D") — the collision
	# shape below is never given an explicit .name, so it's at the mercy of
	# Godot's auto-naming, which isn't guaranteed to land on exactly
	# "CollisionShape3D". Every other pooled builder in this file (pillar,
	# cube, cliff, rock cluster) already looks its collision shape up by
	# child index for this exact reason — matching that here instead of
	# the name lookup that was crashing on reused pool nodes.
	var collision: CollisionShape3D = area.get_child(1)
	collision.disabled = false

	var gem_index := _rng.randi_range(0, SHADE_COLORS.size() - 1)
	var gem_color: Color = SHADE_COLORS[gem_index]
	var mat := _get_cached_material("shade_%d" % gem_index, gem_color, gem_color)
	visual.get_node("TopHalf").material_override = mat
	visual.get_node("BottomHalf").material_override = mat
	return area


## Rewards the player, then plays a quick "pop" (scale punch up, then
## collapse to nothing) instead of vanishing instantly, so a pickup reads
## as an actual event rather than a flicker — before queue_free()ing the
## Shade for real.
func _on_collectible_body_entered(body: Node, area: Area3D) -> void:
	if not (body.is_in_group("player") and body.has_method("collect_shade")):
		return
	# Stop this Area3D from firing again mid-animation (defensive — a
	# body_entered signal only fires once per genuine overlap start, but
	# there's no reason to leave the window open while it's popping).
	# set_deferred, not a direct assignment — Godot blocks mutating a
	# monitoring Area3D's monitoring state from inside its own
	# body_entered callback ("Function blocked during in/out signal"),
	# since the physics step that's currently iterating overlaps hasn't
	# finished yet. set_deferred queues it for right after that step.
	area.set_deferred("monitoring", false)
	# Same reasoning applies to the collision shape: disable it deferred
	# too so nothing else can start overlapping it mid-pop either, on top
	# of monitoring already being off.
	var collision_shape: CollisionShape3D = area.get_child(1) if area.get_child_count() > 1 else null
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	body.collect_shade(collectible_meter_fill, collectible_score_value)
	AudioManager.play_sfx("collection")
	_play_collect_pop(area)


## Calls collect_shade() on the player rather than reaching into `$MoonEnergy`
## directly — a collectible shouldn't need to know MoonEnergy is a child of
## Player, or under what name. That's Player's own internal detail to keep
## encapsulated.
func _play_collect_pop(area: Area3D) -> void:
	# Animates the "Visual" wrapper (meshes only), NOT the Area3D itself —
	# scaling the Area3D's own transform to Vector3.ZERO also scales its
	# CollisionShape3D to zero, which Jolt Physics logs as an invalid/
	# singular transform every frame it happens. The wrapper carries no
	# collision shape, so it can freely animate down to zero with nothing
	# for Jolt to complain about. Falls back to animating the area itself
	# if "Visual" somehow isn't there, rather than silently no-op'ing.
	var target: Node = area.get_node("Visual") if area.has_node("Visual") else area
	var tween := create_tween()
	tween.tween_property(target, "scale", Vector3.ONE * 1.5, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "scale", Vector3.ZERO, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(area.queue_free)
