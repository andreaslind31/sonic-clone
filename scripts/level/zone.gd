extends Node2D
class_name Zone
## Builds and runs an act: terrain, objects, player, camera and act flow.
##
## The level arrives as an ActData: a list of surface segments walked left to
## right, plus object placements anchored to the generated ground. Building
## terrain from data (rather than a hand-placed tilemap) keeps slopes smooth, so
## the sensors always read a clean surface normal.
##
## Set `act` before the node enters the tree to build a specific level; otherwise
## the act named by Game.act_index is used.

const STEP := 8.0                ## sampling resolution for curved segments
const DEATH_MARGIN := 260.0      ## how far below the lowest ground kills

@export var act: ActData
## Off for the test suite: a restart would reload whatever scene is running.
@export var auto_restart := true

var player: Player
var camera: FollowCamera
var hud: Hud
var pause_menu: PauseMenu

var _ground_y := 320.0
var _samples := PackedVector2Array()   ## surface height lookup, ascending in x
var _bounds := Rect2()
var _finished := false
var _restarting := false
var _awaiting_title := false  ## the last act is cleared; waiting for a keypress


func _ready() -> void:
	randomize()
	if act == null:
		act = Acts.get_act(Game.act_index)
	_ground_y = act.ground_y
	_build_terrain()
	_add_sky()
	_place_objects()
	_spawn_player()
	_add_hud()
	Game.act_running = true
	Sfx.play_music(act.music)
	hud.show_title_card(act.zone_name, act.act_number)
	hud.fade_in()


# --------------------------------------------------------------------------- #
# terrain
# --------------------------------------------------------------------------- #
## Solid on both paths: only loop arcs are layer-specific.
func _terrain_layers() -> int:
	return Game.COLLISION_LAYERS.terrain_a | Game.COLLISION_LAYERS.terrain_b


func _build_terrain() -> void:
	var terrain_layers := _terrain_layers()
	var cursor := Vector2(0.0, _ground_y)
	var strip := PackedVector2Array([cursor])
	var lowest := _ground_y
	var highest := _ground_y

	for segment in act.layout:
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
		return _ground_y
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
	add_child(SkyBackdrop.create(_ground_y))


func _place_objects() -> void:
	for entry in act.objects:
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
			"block":
				# `y` is how high the block's top sits above the ground here
				var width: float = float(entry.get("width", 96.0))
				var height: float = float(entry.get("height", 20.0))
				add_child(Block.create(
					Vector2(x - width * 0.5, where.y), Vector2(width, height), _terrain_layers()
				))
			"wall":
				# a climbable pillar standing on the ground
				var wall_width: float = float(entry.get("width", 24.0))
				var wall_height: float = float(entry.get("height", 120.0))
				add_child(Block.create(
					Vector2(x - wall_width * 0.5, ground - wall_height),
					Vector2(wall_width, wall_height), _terrain_layers()
				))
			"boss":
				var arena_half: float = float(entry.get("arena", 200.0))
				var boss := Boss.create(
					Vector2(x, ground - float(entry.get("height", 96.0))), arena_half
				)
				boss.activated.connect(_on_boss_activated.bind(x, arena_half))
				boss.defeated.connect(_on_boss_defeated.bind(x, ground))
				add_child(boss)
			"checkpoint":
				add_child(Checkpoint.create(where))
			"goal":
				add_child(Goal.create(where))


func _spawn_player() -> void:
	player = Player.create(Characters.get_character(Game.character_index))
	var start := Vector2(act.start_x, surface_y(act.start_x) - player.height_radius)
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


# --------------------------------------------------------------------------- #
# boss fight
# --------------------------------------------------------------------------- #
## Seal the arena and pin the camera to it, so the fight cannot be walked away
## from and the pod always stays on screen.
func _on_boss_activated(centre_x: float, arena_half: float) -> void:
	var left := centre_x - arena_half
	var right := centre_x + arena_half
	camera.limit_left = int(left)
	camera.limit_right = int(right)
	add_child(Block.create(
		Vector2(left - 24.0, _bounds.position.y), Vector2(24.0, _bounds.size.y + 200.0),
		_terrain_layers()
	))
	Sfx.play_music("music_boss")


func _on_boss_defeated(centre_x: float, ground: float) -> void:
	# the prize capsule drops in where the pod was, and clears the act when opened
	add_child(Capsule.create(Vector2(centre_x, ground)))
	camera.limit_right = int(_bounds.end.x)
	Sfx.play_music("music_zone")


func _add_hud() -> void:
	hud = Hud.new()
	add_child(hud)
	pause_menu = PauseMenu.create()
	pause_menu.restart_requested.connect(func() -> void: _restart(true))
	pause_menu.quit_requested.connect(_return_to_title)
	add_child(pause_menu)


# --------------------------------------------------------------------------- #
# act flow
# --------------------------------------------------------------------------- #
func _process(_delta: float) -> void:
	if player == null:
		return
	if _awaiting_title:
		if Input.is_action_just_pressed("start") or Input.is_action_just_pressed("jump"):
			_return_to_title()
		return
	if Input.is_action_just_pressed("restart") and not _finished:
		_restart(true)
	if Input.is_action_just_pressed("debug"):
		Game.debug_draw = not Game.debug_draw
		player.queue_redraw()
	if not _finished and player.global_position.y > _bounds.end.y + DEATH_MARGIN:
		player.kill()


func _on_player_died() -> void:
	# A cleared act or a quit already in progress owns what happens next.
	if _finished or _restarting:
		return
	Game.act_running = false
	Game.lose_life()
	if Game.lives <= 0:
		# out of lives: the run is over, so hand control back to the title screen
		_return_to_title()
	else:
		Game.reset_life()
		_restart(false)


func _return_to_title() -> void:
	if _restarting:
		return
	_restarting = true
	Game.reset_run()
	if not auto_restart:
		return
	pause_menu.can_pause = false
	hud.fade_out(0.5)
	await get_tree().create_timer(0.55).timeout
	# The timer runs through a pause, so never hand a paused tree to the next scene.
	get_tree().paused = false
	get_tree().change_scene_to_file(Game.MENU_SCENE)


func _restart(from_start: bool) -> void:
	if _restarting or not auto_restart:
		return
	# A manual restart while dying would dodge the lost life.
	if from_start and player.state == Player.State.DEAD:
		return
	_restarting = true
	pause_menu.can_pause = false
	Game.act_running = false
	if from_start:
		Game.checkpoint_set = false
		Game.time_left = 0.0
	hud.fade_out(0.4)
	await get_tree().create_timer(0.45).timeout
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_goal_reached() -> void:
	if _finished:
		return
	_finished = true
	Game.act_running = false
	pause_menu.can_pause = false
	Sfx.fade_music(0.3)
	Sfx.play("goal")
	var new_best := Game.record_completion(
		Game.character_index, Game.act_index, Game.time_left
	)
	var time_bonus := int(maxf(0.0, act.time_bonus_cutoff - Game.time_left) * 100.0)
	var ring_bonus := Game.rings * 100
	Game.add_score(time_bonus + ring_bonus)
	await get_tree().create_timer(1.6).timeout
	var last_act := Game.act_index >= Acts.count() - 1
	hud.show_results("TIME %s   RINGS %d   BONUS %d" % [
		Game.time_string(), Game.rings, time_bonus + ring_bonus
	], _results_footer(last_act, new_best))
	if last_act:
		_awaiting_title = true
		return
	# roll on to the next act, keeping score, lives and the chosen character
	await get_tree().create_timer(2.4).timeout
	Game.act_index += 1
	Game.checkpoint_set = false
	Game.time_left = 0.0
	Game.reset_life()
	hud.fade_out(0.5)
	await get_tree().create_timer(0.55).timeout
	get_tree().reload_current_scene()


func _results_footer(last_act: bool, new_best: bool) -> String:
	var destination := "SPACE FOR THE TITLE SCREEN" if last_act else "NEXT ACT..."
	return "NEW BEST!   %s" % destination if new_best else destination
