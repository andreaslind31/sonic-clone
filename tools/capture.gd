extends Node
## Scripted playtest harness (development only; not part of the shipped game).
##
## Runs the real main scene, feeds it synthetic input, and writes PNG snapshots
## of the viewport, so gameplay can be verified without a human at the keyboard.
##
##   Godot res://tools/capture.tscn -- --out=/tmp/run --shots=60,240,480 \
##       --frames=520 --hold=move_right@0-520 --tap=jump@150,jump@300
##
## --hold  action@from-to     press an action for a frame range
## --tap   action@frame       press for a single frame
## --probe frame              print player state at that frame
## --warp  x                  start the player at this world x
## --act   n                  build act n instead of the current one
## --char  n                  play as roster entry n

var _out := "/tmp/sonic"
var _frames := 300
var _shots: Array[int] = []
var _probes: Array[int] = []
var _holds: Array[Dictionary] = []
var _taps: Array[Dictionary] = []
var _frame := 0
var _zone: Node
var _surface_probe := Vector3.ZERO  ## x from, x to, step; zero disables
var _warp_x := -1.0                 ## drop the player in at this x before testing
var _act := -1                      ## which act to build; -1 keeps the current one
var _character := -1                ## which character to play; -1 keeps the current one


func _ready() -> void:
	_parse_args()
	# Game.reset_run() has already run by now, so these have to be set after boot
	if _act >= 0:
		Game.act_index = _act
	if _character >= 0:
		Game.character_index = _character
	_zone = load("res://scenes/main.tscn").instantiate()
	add_child(_zone)
	if _warp_x >= 0.0:
		var player := _player()
		if player != null:
			player.global_position = Vector2(_warp_x, _zone.surface_y(_warp_x) - 19.0)
			_zone.camera.snap_to_target()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		var value := arg.substr(key.length() + 1)
		match key:
			"--out":
				_out = value
			"--frames":
				_frames = int(value)
			"--shots":
				for token in value.split(","):
					_shots.append(int(token))
			"--probe":
				for token in value.split(","):
					if token.contains("-"):
						for f in range(int(token.get_slice("-", 0)), int(token.get_slice("-", 1)) + 1):
							_probes.append(f)
					else:
						_probes.append(int(token))
			"--hold":
				for token in value.split(","):
					var action := token.get_slice("@", 0)
					var span := token.get_slice("@", 1).split("-")
					_holds.append({
						"action": action,
						"from": int(span[0]),
						"to": int(span[1]) if span.size() > 1 else int(span[0]),
					})
			"--tap":
				for token in value.split(","):
					_taps.append({
						"action": token.get_slice("@", 0),
						"frame": int(token.get_slice("@", 1)),
					})
			"--surface":
				var parts := value.split(",")
				_surface_probe = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
			"--warp":
				_warp_x = float(value)
			"--act":
				_act = int(value)
			"--char":
				_character = int(value)


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame == 2 and _surface_probe != Vector3.ZERO:
		_probe_surface()
	_drive_input()
	if _probes.has(_frame):
		_print_state()
	if _shots.has(_frame):
		_snapshot.call_deferred(_frame)
	if _frame >= _frames:
		print("capture: finished at frame %d" % _frame)
		get_tree().quit()


func _drive_input() -> void:
	for hold in _holds:
		if _frame == int(hold["from"]):
			Input.action_press(hold["action"])
		elif _frame == int(hold["to"]) + 1:
			Input.action_release(hold["action"])
	for tap in _taps:
		if _frame == int(tap["frame"]):
			Input.action_press(tap["action"])
		elif _frame == int(tap["frame"]) + 1:
			Input.action_release(tap["action"])


func _player() -> Node:
	var found := get_tree().get_nodes_in_group("player")
	return found[0] if found.size() > 0 else null


func _print_state() -> void:
	var player := _player()
	if player == null:
		print("frame %d: no player" % _frame)
		return
	var states := ["NORMAL", "SPINDASH", "HURT", "DEAD", "GOAL"]
	print("frame %4d  pos=(%7.1f,%7.1f) gsp=%6.2f vel=(%5.2f,%5.2f) angle=%6.1f deg %s%s%s layer=%d rings=%d %s score=%d lives=%d cp=%s" % [
		_frame,
		player.global_position.x, player.global_position.y,
		player.ground_speed, player.velocity.x, player.velocity.y,
		rad_to_deg(player.ground_angle),
		"ground" if player.grounded else "air   ",
		" roll" if player.rolling else "",
		" push" if player.pushing else "",
		player.path_layer,
		Game.rings,
		states[player.state],
		Game.score,
		Game.lives,
		str(Game.checkpoint) if Game.checkpoint_set else "none",
	])


## Raycast straight down at a range of x positions and report what the sensors
## would see, next to the height the level builder thinks is there.
func _probe_surface() -> void:
	var space: PhysicsDirectSpaceState2D = _zone.get_world_2d().direct_space_state
	var x := _surface_probe.x
	while x <= _surface_probe.y:
		var from := Vector2(x, -200.0)
		var query := PhysicsRayQueryParameters2D.create(from, Vector2(x, 1200.0))
		query.collision_mask = Game.COLLISION_LAYERS.terrain_a
		var hit: Dictionary = space.intersect_ray(query)
		var expected: float = _zone.surface_y(x)
		if hit.is_empty():
			print("surface x=%7.1f  no hit                       expected y=%7.1f" % [x, expected])
		else:
			var normal: Vector2 = hit["normal"]
			print("surface x=%7.1f  y=%7.1f normal=(%5.2f,%5.2f) angle=%6.1f  expected y=%7.1f" % [
				x, hit["position"].y, normal.x, normal.y,
				rad_to_deg(normal.angle() + PI * 0.5), expected,
			])
		x += _surface_probe.z


func _snapshot(frame: int) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s_%04d.png" % [_out, frame]
	var error := image.save_png(path)
	if error != OK:
		push_error("could not write %s (error %d)" % [path, error])
	else:
		print("capture: wrote %s" % path)
