extends Node2D
class_name Zone
## Builds and runs the act: terrain, objects, player, camera and act flow.
##
## The level is described by LAYOUT as a list of surface segments walked left to
## right, and by OBJECTS as placements anchored to the generated ground. Building
## terrain from data (rather than a hand-placed tilemap) keeps slopes smooth, so
## the sensors always read a clean surface normal.

const GROUND_Y := 320.0
const STEP := 8.0                ## sampling resolution for curved segments
const DEATH_MARGIN := 260.0      ## how far below the lowest ground kills
const TIME_BONUS_CUTOFF := 90.0

## Surface segments. `kind` picks the shape; lengths and heights are in pixels.
const LAYOUT: Array[Dictionary] = [
	{"kind": "flat", "length": 420.0},
	{"kind": "hill", "length": 320.0, "height": 64.0},
	{"kind": "flat", "length": 120.0},
	{"kind": "slope", "length": 256.0, "drop": 96.0},
	{"kind": "valley", "length": 320.0, "depth": 72.0},
	{"kind": "flat", "length": 150.0},
	{"kind": "loop", "radius": 64.0},
	{"kind": "flat", "length": 240.0},
	{"kind": "hill", "length": 280.0, "height": 56.0},
	{"kind": "flat", "length": 90.0},
	{"kind": "gap", "length": 150.0},
	{"kind": "flat", "length": 190.0},
	{"kind": "slope", "length": 240.0, "drop": -120.0},
	{"kind": "flat", "length": 200.0},
	{"kind": "slope", "length": 200.0, "drop": 120.0},
	{"kind": "valley", "length": 280.0, "depth": 64.0},
	{"kind": "loop", "radius": 76.0},
	{"kind": "flat", "length": 260.0},
	{"kind": "hill", "length": 360.0, "height": 88.0},
	{"kind": "flat", "length": 140.0},
	{"kind": "gap", "length": 170.0},
	{"kind": "flat", "length": 300.0},
	{"kind": "ramp", "length": 160.0, "height": 96.0},
	{"kind": "flat", "length": 120.0},
	{"kind": "slope", "length": 180.0, "drop": 96.0},
	{"kind": "flat", "length": 700.0},
]

## Object placements. `y` lifts the object above the ground at that x. Positions
## are chosen against the segment run above: nothing sits over a gap except the
## ring trails and platforms that are meant to be crossed.
const OBJECTS: Array[Dictionary] = [
	{"what": "ring_arc", "x": 300.0, "count": 5, "spacing": 24.0, "y": 34.0, "arc": 26.0},
	{"what": "monitor", "x": 600.0, "y": 0.0, "item": "rings"},
	{"what": "ring_line", "x": 720.0, "count": 4, "spacing": 24.0, "y": 30.0},
	{"what": "badnik", "x": 990.0, "kind": "motobug", "patrol": 80.0, "y": 12.0},
	{"what": "ring_arc", "x": 1180.0, "count": 6, "spacing": 22.0, "y": 60.0, "arc": 34.0},
	{"what": "ring_line", "x": 1480.0, "count": 4, "spacing": 24.0, "y": 40.0},
	{"what": "badnik", "x": 1860.0, "kind": "buzzer", "patrol": 70.0, "y": 96.0},
	{"what": "spring", "x": 2010.0, "y": 8.0, "dir": "up"},
	{"what": "monitor", "x": 2100.0, "y": 0.0, "item": "shoes"},
	{"what": "ring_arc", "x": 2200.0, "count": 5, "spacing": 22.0, "y": 44.0, "arc": 28.0},
	# the first pit: a ring trail baits the jump, the platform is the safe route
	{"what": "ring_line", "x": 2420.0, "count": 5, "spacing": 24.0, "y": 60.0},
	{"what": "platform", "x": 2479.0, "y": 46.0, "travel": Vector2(0, -56), "seconds": 2.4},
	{"what": "checkpoint", "x": 2600.0, "y": 0.0},
	{"what": "ring_line", "x": 2640.0, "count": 3, "spacing": 22.0, "y": 30.0},
	{"what": "spikes", "x": 2700.0, "y": 7.0},
	{"what": "badnik", "x": 2880.0, "kind": "motobug", "patrol": 90.0, "y": 12.0},
	{"what": "monitor", "x": 3050.0, "y": 0.0, "item": "shield"},
	{"what": "ring_arc", "x": 3250.0, "count": 7, "spacing": 22.0, "y": 54.0, "arc": 30.0},
	{"what": "badnik", "x": 4000.0, "kind": "buzzer", "patrol": 90.0, "y": 100.0},
	{"what": "ring_line", "x": 4100.0, "count": 6, "spacing": 22.0, "y": 36.0},
	{"what": "monitor", "x": 4300.0, "y": 0.0, "item": "life"},
	{"what": "spring", "x": 4450.0, "y": 8.0, "dir": "right"},
	{"what": "ring_arc", "x": 4570.0, "count": 5, "spacing": 24.0, "y": 66.0, "arc": 30.0},
	# the second pit
	{"what": "ring_line", "x": 4680.0, "count": 6, "spacing": 24.0, "y": 70.0},
	{"what": "platform", "x": 4741.0, "y": 54.0, "travel": Vector2(0, -64), "seconds": 2.2},
	{"what": "badnik", "x": 4950.0, "kind": "motobug", "patrol": 70.0, "y": 12.0},
	{"what": "spikes", "x": 5060.0, "y": 7.0},
	{"what": "ring_line", "x": 5180.0, "count": 5, "spacing": 22.0, "y": 40.0},
	{"what": "ring_arc", "x": 5320.0, "count": 6, "spacing": 22.0, "y": 48.0, "arc": 30.0},
	{"what": "goal", "x": 5900.0, "y": 0.0},
]

var player: Player
var camera: FollowCamera
var hud: Hud

var _samples := PackedVector2Array()   ## surface height lookup, ascending in x
var _bounds := Rect2()
var _finished := false
var _restarting := false


func _ready() -> void:
	randomize()
	_build_terrain()
	_add_sky()
	_place_objects()
	_spawn_player()
	_add_hud()
	Game.act_running = true
	Sfx.play_music()
	hud.show_title_card()
	hud.fade_in()


# --------------------------------------------------------------------------- #
# terrain
# --------------------------------------------------------------------------- #
func _build_terrain() -> void:
	var terrain_layers: int = Game.COLLISION_LAYERS.terrain_a | Game.COLLISION_LAYERS.terrain_b
	var cursor := Vector2(0.0, GROUND_Y)
	var strip := PackedVector2Array([cursor])
	var lowest := GROUND_Y
	var highest := GROUND_Y

	for segment in LAYOUT:
		match segment["kind"]:
			"flat":
				cursor.x += segment["length"]
				strip.append(cursor)
			"slope":
				cursor += Vector2(segment["length"], segment["drop"])
				strip.append(cursor)
			"hill":
				cursor = _curve(strip, cursor, segment["length"], -segment["height"])
			"valley":
				cursor = _curve(strip, cursor, segment["length"], segment["depth"])
			"ramp":
				cursor = _ramp(strip, cursor, segment["length"], segment["height"])
			"loop":
				var radius: float = segment["radius"]
				var run := radius * 2.0 + 80.0
				var centre := cursor.x + run * 0.5
				add_child(Loop.create(centre, cursor.y, radius))
				cursor.x += run
				strip.append(cursor)
			"gap":
				# close this strip and restart past the hole
				_finish_strip(strip, terrain_layers)
				cursor.x += segment["length"]
				strip = PackedVector2Array([cursor])
		lowest = maxf(lowest, cursor.y)
		highest = minf(highest, cursor.y)

	_finish_strip(strip, terrain_layers)
	_bounds = Rect2(0.0, highest - 200.0, cursor.x, (lowest - highest) + 400.0)
	_add_boundaries(terrain_layers)


## Full-height walls at both ends of the act. The terrain strips only close
## downwards, so without these the player walks straight off the last segment.
func _add_boundaries(layers: int) -> void:
	var top := _bounds.position.y - 200.0
	var bottom := _bounds.end.y + 200.0
	for x in [_bounds.position.x, _bounds.end.x]:
		var wall := StaticBody2D.new()
		wall.collision_layer = layers
		wall.collision_mask = 0
		var shape := CollisionPolygon2D.new()
		shape.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
		shape.polygon = PackedVector2Array([Vector2(x, top), Vector2(x, bottom)])
		wall.add_child(shape)
		add_child(wall)


## Smooth bump (or dip) that returns to the starting height. A raised cosine is
## used rather than a half sine so the slope is zero at both joins: no corner
## where the curve meets flat ground.
func _curve(strip: PackedVector2Array, cursor: Vector2, length: float, height: float) -> Vector2:
	var steps := int(ceilf(length / STEP))
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var rise := height * (1.0 - cos(TAU * t)) * 0.5
		strip.append(Vector2(cursor.x + length * t, cursor.y + rise))
	return Vector2(cursor.x + length, cursor.y)


## Quarter-pipe style launch ramp: shallow at the bottom, steep at the lip.
func _ramp(strip: PackedVector2Array, cursor: Vector2, length: float, height: float) -> Vector2:
	var steps := int(ceilf(length / STEP))
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		strip.append(Vector2(cursor.x + length * t, cursor.y - height * t * t))
	return Vector2(cursor.x + length, cursor.y - height)


func _finish_strip(strip: PackedVector2Array, layers: int) -> void:
	if strip.size() < 2:
		return
	add_child(Terrain.create(strip, layers))
	for point in strip:
		_samples.append(point)


## Ground height at a world x, interpolated from the generated surface.
func surface_y(x: float) -> float:
	if _samples.is_empty():
		return GROUND_Y
	if x <= _samples[0].x:
		return _samples[0].y
	for i in range(1, _samples.size()):
		if _samples[i].x >= x:
			var a := _samples[i - 1]
			var b := _samples[i]
			if is_equal_approx(a.x, b.x):
				return b.y
			var t := (x - a.x) / (b.x - a.x)
			return lerpf(a.y, b.y, t)
	return _samples[_samples.size() - 1].y


# --------------------------------------------------------------------------- #
# contents
# --------------------------------------------------------------------------- #
func _add_sky() -> void:
	add_child(SkyBackdrop.create(GROUND_Y))


func _place_objects() -> void:
	for entry in OBJECTS:
		var x: float = entry["x"]
		var ground := surface_y(x)
		var lift: float = entry.get("y", 0.0)
		var where := Vector2(x, ground - lift)
		match entry["what"]:
			"ring_line":
				for i in int(entry["count"]):
					var rx: float = x + i * float(entry["spacing"])
					add_child(Ring.create(Vector2(rx, surface_y(rx) - lift)))
			"ring_arc":
				var count := int(entry["count"])
				for i in count:
					var rx: float = x + i * float(entry["spacing"])
					var t := float(i) / maxf(1.0, float(count - 1))
					var arc: float = float(entry.get("arc", 24.0)) * sin(PI * t)
					add_child(Ring.create(Vector2(rx, surface_y(rx) - lift - arc)))
			"monitor":
				var items := {
					"rings": Monitor.Item.RINGS,
					"shoes": Monitor.Item.SHOES,
					"shield": Monitor.Item.SHIELD,
					"life": Monitor.Item.LIFE,
				}
				add_child(Monitor.create(where - Vector2(0, 16), items[entry["item"]]))
			"spring":
				var dirs := {
					"up": Vector2.UP,
					"right": Vector2(0.7, -0.7),
					"left": Vector2(-0.7, -0.7),
				}
				add_child(Spring.create(where, dirs[entry.get("dir", "up")]))
			"spikes":
				add_child(Spikes.create(where))
			"badnik":
				var kinds := {"motobug": Badnik.Kind.MOTOBUG, "buzzer": Badnik.Kind.BUZZER}
				add_child(Badnik.create(where, kinds[entry["kind"]],
					float(entry.get("patrol", 96.0))))
			"platform":
				add_child(MovingPlatform.create(where, entry.get("travel", Vector2(0, -64)),
					float(entry.get("seconds", 3.0))))
			"checkpoint":
				add_child(Checkpoint.create(where))
			"goal":
				add_child(Goal.create(where))


func _spawn_player() -> void:
	player = Player.new()
	var start := Vector2(120.0, surface_y(120.0) - Player.HEIGHT_RADIUS)
	if Game.checkpoint_set:
		start = Game.checkpoint
	player.position = start
	player.z_index = 5
	add_child(player)
	player.died.connect(_on_player_died)
	player.reached_goal.connect(_on_goal_reached)

	camera = FollowCamera.new()
	camera.target = player
	camera.limit_left = int(_bounds.position.x)
	camera.limit_right = int(_bounds.end.x)
	camera.limit_top = int(_bounds.position.y)
	camera.limit_bottom = int(_bounds.end.y + DEATH_MARGIN)
	add_child(camera)
	camera.make_current()
	camera.snap_to_target()


func _add_hud() -> void:
	hud = Hud.new()
	add_child(hud)


# --------------------------------------------------------------------------- #
# act flow
# --------------------------------------------------------------------------- #
func _process(_delta: float) -> void:
	if player == null:
		return
	if Input.is_action_just_pressed("restart"):
		_restart(true)
	if Input.is_action_just_pressed("debug"):
		Game.debug_draw = not Game.debug_draw
		player.queue_redraw()
	if not _finished and player.global_position.y > _bounds.end.y + DEATH_MARGIN:
		player.kill()


func _on_player_died() -> void:
	Game.act_running = false
	Game.lose_life()
	if Game.lives <= 0:
		Game.reset_run()
		_restart(true)
	else:
		Game.reset_life()
		_restart(false)


func _restart(from_start: bool) -> void:
	if _restarting:
		return
	_restarting = true
	if from_start:
		Game.checkpoint_set = false
		Game.time_left = 0.0
	hud.fade_out(0.4)
	await get_tree().create_timer(0.45).timeout
	get_tree().reload_current_scene()


func _on_goal_reached() -> void:
	if _finished:
		return
	_finished = true
	Game.act_running = false
	Sfx.fade_music(0.3)
	Sfx.play("goal")
	var time_bonus := int(maxf(0.0, TIME_BONUS_CUTOFF - Game.time_left) * 100.0)
	var ring_bonus := Game.rings * 100
	Game.add_score(time_bonus + ring_bonus)
	await get_tree().create_timer(1.6).timeout
	hud.show_results("TIME %s   RINGS %d   BONUS %d" % [
		Game.time_string(), Game.rings, time_bonus + ring_bonus
	])
