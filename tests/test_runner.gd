extends Node
## Physics regression suite. Run it headlessly:
##
##   godot --headless --audio-driver Dummy res://tests/tests.tscn --quit-after 60000
##
## Exits non-zero if anything fails, so it can gate a commit or a CI job.
##
## These tests drive the real Player through the real Zone builder on a small
## fixture act, then assert the numbers the Sonic Retro Physics Guide specifies.
## They exist because the SPG constants are easy to break silently: the game still
## plays after a bad refactor, it just no longer moves like Sonic.

const EPS := 0.001

var _failures: Array[String] = []
var _checks := 0
var _current := ""


func _ready() -> void:
	await _run_all()
	_report()


func _run_all() -> void:
	var suite := [
		{"name": "ground acceleration is 0.046875/frame", "fn": _test_acceleration},
		{"name": "top speed caps at 6", "fn": _test_top_speed},
		{"name": "friction is 0.046875/frame", "fn": _test_friction},
		{"name": "braking is 0.5/frame", "fn": _test_deceleration},
		{"name": "braking through zero snaps to 0.5", "fn": _test_brake_snap},
		{"name": "jump force is 6.5", "fn": _test_jump_force},
		{"name": "releasing jump caps rise at 4", "fn": _test_jump_release},
		{"name": "gravity is 0.21875/frame", "fn": _test_gravity},
		{"name": "downhill running exceeds top speed", "fn": _test_slope_gain},
		{"name": "rolling friction is half of running", "fn": _test_roll_friction},
		{"name": "spindash releases at 8 or more", "fn": _test_spindash},
		{"name": "rolling shrinks the hitbox and keeps the feet down", "fn": _test_roll_hitbox},
		{"name": "loop is traversed, flips path layer, and exits", "fn": _test_loop},
		{"name": "rings are collected and scored", "fn": _test_rings},
		{"name": "sensors agree with the generated surface", "fn": _test_sensors},
	]
	for entry in suite:
		_current = entry["name"]
		var zone := await _fresh_zone()
		await (entry["fn"] as Callable).call(zone)
		_release_all()
		zone.queue_free()
		await get_tree().process_frame


# --------------------------------------------------------------------------- #
# fixture
# --------------------------------------------------------------------------- #
## Flat run, a 26.6 degree descent, more flat, a loop, then a long outrun.
func _fixture() -> ActData:
	var layout: Array[Dictionary] = [
		{"kind": "flat", "length": 1200.0},
		{"kind": "slope", "length": 400.0, "drop": 200.0},
		{"kind": "flat", "length": 500.0},
		{"kind": "loop", "radius": 64.0},
		{"kind": "flat", "length": 900.0},
	]
	var objects: Array[Dictionary] = [
		{"what": "ring_line", "x": 700.0, "count": 3, "spacing": 24.0, "y": 20.0},
	]
	var act := ActData.make("TEST", 1, layout, objects)
	act.start_x = 100.0
	return act


func _fresh_zone() -> Zone:
	Game.reset_run()
	Game.checkpoint_set = false
	var zone := Zone.new()
	zone.act = _fixture()
	zone.auto_restart = false
	add_child(zone)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return zone


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _press(action: String) -> void:
	Input.action_press(action)


func _release(action: String) -> void:
	Input.action_release(action)


func _release_all() -> void:
	for action in ["move_left", "move_right", "jump", "crouch", "look_up"]:
		Input.action_release(action)


## Run frames until the player leaves the ground. Synthetic presses injected from
## outside a physics step are not guaranteed to be seen by the very next one, so
## tests wait for the effect rather than assuming the frame it lands on.
func _wait_airborne(player: Player, limit := 12) -> bool:
	for i in limit:
		await get_tree().physics_frame
		if not player.grounded:
			return true
	return false


## Put the player on the ground at `x`, at rest.
func _place(zone: Zone, x: float) -> void:
	var player := zone.player
	player.global_position = Vector2(x, zone.surface_y(x) - player.height_radius)
	player.ground_speed = 0.0
	player.velocity = Vector2.ZERO
	player.ground_angle = 0.0
	player.grounded = true
	await get_tree().physics_frame


func _check(condition: bool, detail: String) -> void:
	_checks += 1
	if not condition:
		_failures.append("%s: %s" % [_current, detail])


func _check_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	_check(absf(actual - expected) <= tolerance,
		"%s expected %.5f, got %.5f (tolerance %.5f)" % [label, expected, actual, tolerance])


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("%d checks passed" % _checks)
		get_tree().quit(0)
		return
	print("%d of %d checks FAILED" % [_failures.size(), _checks])
	for failure in _failures:
		print("  - %s" % failure)
	get_tree().quit(1)


# --------------------------------------------------------------------------- #
# tests
# --------------------------------------------------------------------------- #
func _test_acceleration(zone: Zone) -> void:
	await _place(zone, 200.0)
	_press("move_right")
	await _frames(40)
	# 40 frames x ACC, with a one frame allowance for where the probe lands
	_check_near(zone.player.ground_speed, 40.0 * Player.ACC, Player.ACC * 1.5, "ground speed")


func _test_top_speed(zone: Zone) -> void:
	await _place(zone, 200.0)
	_press("move_right")
	await _frames(220)
	_check_near(zone.player.ground_speed, Player.TOP, EPS, "ground speed")


func _test_friction(zone: Zone) -> void:
	await _place(zone, 200.0)
	_press("move_right")
	await _frames(64)
	var before: float = zone.player.ground_speed
	_release("move_right")
	await _frames(20)
	var expected := before - 20.0 * Player.FRC
	_check_near(zone.player.ground_speed, expected, Player.FRC * 1.5, "ground speed after coasting")


func _test_deceleration(zone: Zone) -> void:
	await _place(zone, 300.0)
	_press("move_right")
	await _frames(64)
	var before: float = zone.player.ground_speed
	_release("move_right")
	_press("move_left")
	await _frames(4)
	var expected := before - 4.0 * Player.DEC
	_check_near(zone.player.ground_speed, expected, Player.DEC * 0.6, "ground speed while braking")


func _test_brake_snap(zone: Zone) -> void:
	await _place(zone, 300.0)
	_press("move_right")
	await _frames(30)
	_release("move_right")
	_press("move_left")
	await _frames(6)
	# SPG: braking that crosses zero leaves the player at 0.5 in the new direction
	_check(zone.player.ground_speed <= -0.5 + EPS,
		"expected the player to be moving left, got %.4f" % zone.player.ground_speed)


func _test_jump_force(zone: Zone) -> void:
	await _place(zone, 400.0)
	var player := zone.player
	_press("jump")
	# gravity is not applied on the frame the jump is issued, so the fastest
	# upward velocity seen in the window is the jump force itself
	var peak := 0.0
	for i in 8:
		await get_tree().physics_frame
		peak = minf(peak, player.velocity.y)
	_check_near(peak, -Player.JUMP_FORCE, EPS, "peak vertical velocity")
	_check(not player.grounded, "expected the player to be airborne")
	_release("jump")


func _test_jump_release(zone: Zone) -> void:
	await _place(zone, 400.0)
	var player := zone.player
	_press("jump")
	_check(await _wait_airborne(player), "expected the jump to leave the ground")
	_release("jump")
	await _frames(2)
	_check(player.velocity.y >= -Player.JUMP_RELEASE - EPS,
		"rise should be capped at %.2f, got %.4f" % [-Player.JUMP_RELEASE, player.velocity.y])


func _test_gravity(zone: Zone) -> void:
	await _place(zone, 400.0)
	var player := zone.player
	_press("jump")
	_check(await _wait_airborne(player), "expected the jump to leave the ground")
	_release("jump")
	await _frames(3)  # past the release cap, in free flight
	var before: float = player.velocity.y
	await get_tree().physics_frame
	_check_near(player.velocity.y - before, Player.GRV, EPS, "velocity gained per airborne frame")


func _test_slope_gain(zone: Zone) -> void:
	# the fixture descends 200px over 400px starting at x = 1200
	await _place(zone, 1150.0)
	_press("move_right")
	await _frames(160)
	_check(zone.player.ground_speed > Player.TOP,
		"expected to outrun top speed downhill, got %.3f" % zone.player.ground_speed)
	_check(zone.player.grounded, "expected to stay on the slope")


func _test_roll_friction(zone: Zone) -> void:
	await _place(zone, 200.0)
	_press("move_right")
	await _frames(90)
	_release("move_right")
	_press("crouch")
	await get_tree().physics_frame
	_check(zone.player.rolling, "expected the player to be rolling")
	var before: float = zone.player.ground_speed
	await _frames(20)
	var expected := before - 20.0 * Player.FRC_ROLL
	_check_near(zone.player.ground_speed, expected, Player.FRC_ROLL * 2.0,
		"ground speed while rolling")


func _test_spindash(zone: Zone) -> void:
	await _place(zone, 300.0)
	_press("crouch")
	await _frames(4)
	for i in 5:
		_press("jump")
		await get_tree().physics_frame
		_release("jump")
		await _frames(3)
	_release("crouch")
	await _frames(2)
	_check(zone.player.ground_speed >= Player.SPINDASH_BASE,
		"expected at least %.1f out of a spindash, got %.3f" % [
			Player.SPINDASH_BASE, zone.player.ground_speed])
	_check(zone.player.rolling, "expected to leave the spindash rolling")


func _test_roll_hitbox(zone: Zone) -> void:
	await _place(zone, 200.0)
	_press("move_right")
	await _frames(90)
	var feet_before: float = zone.player.global_position.y + zone.player.height_radius
	_press("crouch")
	await get_tree().physics_frame
	_check_near(zone.player.height_radius, Player.HEIGHT_RADIUS_ROLL, EPS, "roll height radius")
	var feet_after: float = zone.player.global_position.y + zone.player.height_radius
	_check_near(feet_after, feet_before, 1.5, "feet position across the hitbox change")


func _test_loop(zone: Zone) -> void:
	# the loop sits after the slope and the flat that follows it
	await _place(zone, 1650.0)
	_press("move_right")
	var seen_upside_down := false
	var seen_layer_b := false
	var exit_speed := 0.0
	var exit_x := 0.0
	var player := zone.player
	for i in 420:
		await get_tree().physics_frame
		if absf(wrapf(player.ground_angle, -PI, PI)) > deg_to_rad(150.0) and player.grounded:
			seen_upside_down = true
		if player.path_layer == 1:
			seen_layer_b = true
		# sample on the way out, before the far wall of the fixture stops us
		if exit_x == 0.0 and player.global_position.x > 2360.0:
			exit_x = player.global_position.x
			exit_speed = player.ground_speed
	_check(seen_upside_down, "expected to run upside down across the top of the loop")
	_check(seen_layer_b, "expected the path layer to flip to B at the apex")
	_check(exit_x > 0.0, "expected to get past the loop at all")
	_check(exit_speed > 0.0,
		"expected to exit the loop still moving right, got %.3f" % exit_speed)


func _test_rings(zone: Zone) -> void:
	# the fixture puts three rings on the flat at x = 700
	await _place(zone, 640.0)
	_press("move_right")
	await _frames(150)
	_check(Game.rings >= 3, "expected 3 rings, got %d" % Game.rings)
	_check(Game.score >= 30, "expected 30 points of ring score, got %d" % Game.score)


func _test_sensors(zone: Zone) -> void:
	var space := zone.get_world_2d().direct_space_state
	var x := 120.0
	while x < 1500.0:
		var query := PhysicsRayQueryParameters2D.create(
			Vector2(x, -200.0), Vector2(x, 1200.0)
		)
		query.collision_mask = Game.COLLISION_LAYERS.terrain_a
		var hit: Dictionary = space.intersect_ray(query)
		_check(not hit.is_empty(), "no terrain found below x = %.0f" % x)
		if not hit.is_empty():
			_check_near(hit["position"].y, zone.surface_y(x), 1.0,
				"surface height at x = %.0f" % x)
		x += 60.0
