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
	Game.settings_path = "user://sonic-clone-tests-settings.cfg"
	Game.progress_path = "user://sonic-clone-tests-progress.cfg"
	_remove_test_files()
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
		{"name": "lost rings bounce off solid objects", "fn": _test_lost_ring_solids},
		{"name": "enemy shots stop at solid objects", "fn": _test_projectile_solids},
		{"name": "sensors agree with the generated surface", "fn": _test_sensors},
		{"name": "every character keeps the SPG defaults it does not override",
			"fn": _test_character_defaults, "zone": false},
		{"name": "flight climbs while jump is held, and runs out", "fn": _test_fly,
			"character": 1},
		{"name": "glide falls slowly and steers", "fn": _test_glide, "character": 2},
		{"name": "air dash homes on a badnik and destroys it", "fn": _test_dash,
			"character": 3},
		{"name": "hammer widens the damage box for its swing", "fn": _test_hammer,
			"character": 4},
		{"name": "an ability is spent once per airtime", "fn": _test_ability_spend,
			"character": 1},
		{"name": "blocks are solid on every face", "fn": _test_block_faces},
		{"name": "no act wall is taller than the roster can jump",
			"fn": _test_walls_passable, "zone": false},
		{"name": "acts are registered and distinct", "fn": _test_act_registry, "zone": false},
		{"name": "no act object is stranded over a gap or off a block",
			"fn": _test_act_placement, "zone": false},
		{"name": "settings persist and keyboard controls can be remapped",
			"fn": _test_settings_persistence, "zone": false},
		{"name": "the window scales by whole multiples to fit big screens",
			"fn": _test_window_scale, "zone": false},
		{"name": "remapping keeps keys unique and Esc on pause",
			"fn": _test_remap_rules, "zone": false},
		{"name": "the 100-ring extra life is earned again after a lost life",
			"fn": _test_ring_life_resets, "zone": false},
		{"name": "completion records preserve the fastest time",
			"fn": _test_completion_records, "zone": false},
		{"name": "the options overlay edits settings and captures a key",
			"fn": _test_options_menu, "zone": false},
		{"name": "the game boots into the menu, not into an act",
			"fn": _test_boots_to_menu, "zone": false},
		{"name": "the menu picks a character and starts the game",
			"fn": _test_menu_select, "zone": false},
		{"name": "the controller start button pauses the game",
			"fn": _test_controller_pause_binding, "zone": false},
		{"name": "character cannot be switched mid-run", "fn": _test_no_mid_run_switch,
			"character": 2},
		{"name": "an active checkpoint stays active after respawning",
			"fn": _test_checkpoint_persists},
		{"name": "escape pauses and resumes, freezing the player", "fn": _test_pause},
		{"name": "options can be changed without unpausing the game",
			"fn": _test_pause_options},
		{"name": "boss wakes in its arena and locks the camera", "fn": _test_boss_wakes, "zone": false},
		{"name": "boss takes hits only from an attacking player", "fn": _test_boss_damage, "zone": false},
		{"name": "boss resumes from the same edge after a hit",
			"fn": _test_boss_resume_edge, "zone": false},
		{"name": "eight hits finish the boss and drop the capsule", "fn": _test_boss_defeat, "zone": false},
		{"name": "the wrecking ball hurts even an attacking player", "fn": _test_boss_ball, "zone": false},
		{"name": "leaving the pause menu never leaves the tree paused",
			"fn": _test_pause_exits_clean},
		{"name": "a wall can be climbed and pushed off", "fn": _test_wall_climb,
			"character": 2},
	]
	for entry in suite:
		_current = entry["name"]
		# data-only and menu scenarios opt out: building a level would put a
		# player in the tree that they would then trip over
		var zone: Zone = null
		if bool(entry.get("zone", true)):
			zone = await _fresh_zone(int(entry.get("character", 0)))
		else:
			Game.reset_run()
		await (entry["fn"] as Callable).call(zone)
		_release_all()
		get_tree().paused = false
		if zone != null:
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


func _fresh_zone(character := 0) -> Zone:
	Game.reset_run()
	Game.checkpoint_set = false
	Game.character_index = character
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
	_remove_test_files()
	if _failures.is_empty():
		print("%d checks passed" % _checks)
		get_tree().quit(0)
		return
	print("%d of %d checks FAILED" % [_failures.size(), _checks])
	for failure in _failures:
		print("  - %s" % failure)
	get_tree().quit(1)


func _remove_test_files() -> void:
	for path in [Game.settings_path, Game.progress_path]:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)


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


func _test_lost_ring_solids(zone: Zone) -> void:
	var platform := MovingPlatform.create(Vector2(500.0, 200.0), Vector2.ZERO)
	zone.add_child(platform)
	var ring := LostRing.new()
	ring.position = Vector2(500.0, 160.0)
	ring.velocity = Vector2(0.0, 4.0)
	zone.add_child(ring)
	await _frames(12)
	_check(is_instance_valid(ring), "the lost ring disappeared before its lifetime ended")
	if is_instance_valid(ring):
		_check(ring.velocity.y < 0.0,
			"expected the lost ring to bounce off the platform, y velocity is %.3f"
				% ring.velocity.y)


func _test_projectile_solids(zone: Zone) -> void:
	var blocker := Monitor.create(Vector2(500.0, 200.0), Monitor.Item.RINGS)
	zone.add_child(blocker)
	var shot := Projectile.create(Vector2(450.0, 200.0), Vector2(4.0, 0.0))
	zone.add_child(shot)
	await _frames(20)
	_check(not is_instance_valid(shot), "the enemy shot passed through a solid monitor")


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


# --------------------------------------------------------------------------- #
# characters and abilities
# --------------------------------------------------------------------------- #
## The roster is defined by what it overrides, so anything it does not override
## must still be the guide's number.
func _test_character_defaults(_zone: Zone) -> void:
	var reference := CharacterStats.new()
	_check(Characters.names() == PackedStringArray([
		"SONIC", "TAILS", "KNUCKLES", "SHADOW", "AMY",
	]), "roster uses the Sonic character names")
	_check_near(reference.acceleration, Player.ACC, EPS, "default acceleration")
	_check_near(reference.friction, Player.FRC, EPS, "default friction")
	_check_near(reference.deceleration, Player.DEC, EPS, "default deceleration")
	_check_near(reference.top_speed, Player.TOP, EPS, "default top speed")
	_check_near(reference.gravity, Player.GRV, EPS, "default gravity")
	_check_near(reference.jump_force, Player.JUMP_FORCE, EPS, "default jump force")
	_check_near(reference.roll_friction, Player.FRC_ROLL, EPS, "default roll friction")
	_check_near(reference.height_radius, Player.HEIGHT_RADIUS, EPS, "default height radius")
	for i in Characters.count():
		var stats := Characters.get_character(i)
		_check(stats.slug != "", "character %d needs a slug" % i)
		_check(ResourceLoader.exists(stats.sprite_sheet()),
			"missing sheet for %s: %s" % [stats.display_name, stats.sprite_sheet()])


func _test_fly(zone: Zone) -> void:
	var player := zone.player
	_check(player.stats.ability == CharacterStats.Ability.FLY, "expected the flier")
	await _place(zone, 400.0)
	_press("jump")
	_check(await _wait_airborne(player), "expected a jump")
	_release("jump")
	await _frames(6)
	_press("jump")  # second press starts flight
	await _frames(4)
	_check(player.air_move == Player.AirMove.FLY, "expected to be flying")
	var height_before: float = player.global_position.y
	await _frames(30)
	_check(player.global_position.y < height_before,
		"expected to climb while flying, went from %.1f to %.1f" % [
			height_before, player.global_position.y])
	_check(not player.is_attacking(), "flight should not count as an attack")
	# flight has a time limit; burn through it and confirm it drops
	player.air_move_timer = 2
	await _frames(4)
	_check(player.air_move == Player.AirMove.NONE, "expected flight to run out")
	_release("jump")


func _test_glide(zone: Zone) -> void:
	var player := zone.player
	_check(player.stats.ability == CharacterStats.Ability.GLIDE, "expected the glider")
	_check_near(player.stats.jump_force, 6.0, EPS, "the heavier character jumps lower")
	await _place(zone, 400.0)
	_press("move_right")
	await _frames(30)
	_press("jump")
	_check(await _wait_airborne(player), "expected a jump")
	await _frames(4)
	_release("jump")
	await get_tree().physics_frame
	_press("jump")  # second press opens the glide
	await _frames(6)
	_check(player.air_move == Player.AirMove.GLIDE, "expected to be gliding")
	await _frames(20)
	_check(player.velocity.y <= player.stats.glide_fall + EPS,
		"glide descent should settle at %.2f, got %.3f" % [
			player.stats.glide_fall, player.velocity.y])
	_check(player.velocity.x > 0.0, "expected to keep moving forward in a glide")
	_check(player.is_attacking(), "a glide should connect with badniks")
	_release("jump")
	_release("move_right")
	await _frames(4)
	_check(player.air_move == Player.AirMove.NONE, "releasing jump should end the glide")


func _test_dash(zone: Zone) -> void:
	var player := zone.player
	_check(player.stats.ability == CharacterStats.Ability.AIR_DASH, "expected the striker")
	await _place(zone, 400.0)
	# put a badnik just ahead and slightly above the jump arc
	var target := Badnik.create(Vector2(470.0, zone.surface_y(470.0) - 40.0),
		Badnik.Kind.BUZZER, 0.0)
	zone.add_child(target)
	await _frames(2)
	_press("jump")
	_check(await _wait_airborne(player), "expected a jump")
	_release("jump")
	await _frames(4)
	_press("jump")
	await _frames(3)
	_check(player.air_move == Player.AirMove.DASH, "expected to be dashing")
	_check(player.is_attacking(), "a dash should count as an attack")
	_check(player.velocity.x > 0.0, "expected the dash to carry us at the target")
	_release("jump")
	await _frames(30)
	_check(not is_instance_valid(target) or target.is_queued_for_deletion(),
		"expected the dash to destroy the badnik it homed on")


func _test_hammer(zone: Zone) -> void:
	var player := zone.player
	_check(player.stats.ability == CharacterStats.Ability.HAMMER, "expected the smasher")
	_check(not player.stats.can_spindash, "the smasher trades the spindash away")
	await _place(zone, 400.0)
	var normal_width: float = player.hitbox_size().x
	_press("jump")
	_check(await _wait_airborne(player), "expected a jump")
	_release("jump")
	await _frames(4)
	_press("jump")
	await _frames(3)
	_check(player.air_move == Player.AirMove.HAMMER, "expected a hammer swing")
	_check(player.hitbox_size().x > normal_width,
		"the swing should reach further than %.1f, got %.1f" % [
			normal_width, player.hitbox_size().x])
	_check(player.is_attacking(), "the swing should count as an attack")
	_release("jump")
	await _frames(30)
	_check_near(player.hitbox_size().x, normal_width, EPS, "hitbox width after the swing")


func _test_ability_spend(zone: Zone) -> void:
	var player := zone.player
	await _place(zone, 400.0)
	_press("jump")
	_check(await _wait_airborne(player), "expected a jump")
	_release("jump")
	await _frames(4)
	_press("jump")
	await _frames(3)
	_release("jump")
	_check(player.ability_spent, "the ability should be marked spent in mid-air")
	# land, and the ability should be available again
	await _frames(120)
	_check(player.grounded, "expected to land")
	_check(not player.ability_spent, "landing should refresh the ability")


# --------------------------------------------------------------------------- #
# block geometry
# --------------------------------------------------------------------------- #
## A block has to behave as ground on top, ceiling below and wall at the sides,
## because that is the whole reason it exists.
func _test_block_faces(zone: Zone) -> void:
	var ground := zone.surface_y(600.0)
	var top := ground - 80.0
	zone.add_child(Block.create(Vector2(560.0, top), Vector2(120.0, 24.0),
		Game.COLLISION_LAYERS.terrain_a | Game.COLLISION_LAYERS.terrain_b))
	await _frames(2)
	var player := zone.player

	# land on it from above
	player.global_position = Vector2(600.0, top - 60.0)
	player.velocity = Vector2(0.0, 2.0)
	player.grounded = false
	await _frames(60)
	_check(player.grounded, "expected to land on top of the block")
	_check_near(player.global_position.y + player.height_radius, top, 2.0,
		"feet should rest on the block top")

	# the underside stops an upward jump
	player.global_position = Vector2(600.0, top + 24.0 + player.height_radius + 30.0)
	player.velocity = Vector2(0.0, -6.0)
	player.grounded = false
	player.ground_speed = 0.0
	await _frames(30)
	_check(player.global_position.y > top + 24.0,
		"expected the block underside to block the rise, got y = %.1f (block bottom %.1f)" % [
			player.global_position.y, top + 24.0])

	# the side stops a run
	player.velocity = Vector2.ZERO
	player.grounded = false
	player.global_position = Vector2(560.0 - player.push_radius - 1.0, top + 12.0)
	await get_tree().physics_frame
	_check(player.wall_ahead(1.0), "expected the block side to read as a wall")


func _test_wall_climb(zone: Zone) -> void:
	var player := zone.player
	_check(player.stats.ability == CharacterStats.Ability.GLIDE, "expected the glider")
	var ground := zone.surface_y(700.0)
	zone.add_child(Block.create(Vector2(700.0, ground - 140.0), Vector2(24.0, 140.0),
		Game.COLLISION_LAYERS.terrain_a | Game.COLLISION_LAYERS.terrain_b))
	await _frames(2)

	# glide into the wall from the left
	player.global_position = Vector2(640.0, ground - 90.0)
	player.grounded = false
	player.facing = 1
	player.velocity = Vector2(2.0, 0.0)
	player.ability_spent = false
	await get_tree().physics_frame
	_press("jump")
	await _frames(40)
	_check(player.state == Player.State.CLIMB,
		"expected to grab the wall, state is %d at x = %.1f" % [
			player.state, player.global_position.x])
	if player.state == Player.State.CLIMB:
		var height_before: float = player.global_position.y
		_press("look_up")
		await _frames(30)
		_check(player.global_position.y < height_before,
			"expected to climb upward, went %.1f -> %.1f" % [
				height_before, player.global_position.y])
		_release("look_up")
		_release("jump")
		await get_tree().physics_frame
		_press("jump")
		await _frames(6)
		_check(player.state == Player.State.NORMAL, "expected to push off the wall")
		_check(player.velocity.x < 0.0, "expected to be pushed away from the wall")
	_release("jump")


## Level-data guard: a wall the shortest jump cannot clear would soft-lock any
## character without a climb or a flight, so no act may contain one.
func _test_walls_passable(_zone: Zone) -> void:
	var weakest := INF
	var gravity := 0.0
	for i in Characters.count():
		var stats := Characters.get_character(i)
		weakest = minf(weakest, stats.jump_force)
		gravity = maxf(gravity, stats.gravity)
	# peak height of a jump: v^2 / 2g
	var reach := weakest * weakest / (2.0 * gravity)
	for index in Acts.count():
		var act := Acts.get_act(index)
		for entry in act.objects:
			if entry.get("what", "") != "wall":
				continue
			var height: float = float(entry.get("height", 120.0))
			_check(height < reach * 0.9,
				"%s act %d has a %.0fpx wall at x = %.0f, but the weakest jump only reaches %.0fpx" % [
					act.zone_name, act.act_number, height, float(entry["x"]), reach])


func _test_act_registry(_zone: Zone) -> void:
	_check(Acts.count() >= 2, "expected at least two acts")
	var seen := {}
	for index in Acts.count():
		var act := Acts.get_act(index)
		_check(act.layout.size() > 0, "act %d has no layout" % index)
		_check(act.objects.size() > 0, "act %d has no objects" % index)
		# an act ends either at a signpost or at a boss (whose capsule clears it)
		var has_exit := false
		for entry in act.objects:
			if entry.get("what", "") in ["goal", "boss"]:
				has_exit = true
		_check(has_exit, "act %d has neither a goal nor a boss, so it cannot be finished"
			% index)
		var key := "%s-%d" % [act.zone_name, act.act_number]
		_check(not seen.has(key), "two acts share the title %s" % key)
		seen[key] = true
		# every object must name a placement the builder understands
		const KNOWN := ["ring_line", "ring_arc", "monitor", "spring", "spikes", "badnik",
			"platform", "checkpoint", "goal", "block", "wall", "boss"]
		for entry in act.objects:
			_check(KNOWN.has(entry.get("what", "")),
				"act %d has an unknown object kind: %s" % [index, entry.get("what", "?")])


# --------------------------------------------------------------------------- #
# settings and persistent progress
# --------------------------------------------------------------------------- #
func _test_settings_persistence(_zone: Zone) -> void:
	_remove_test_files()
	Game.reset_key_bindings(false)
	Game.set_music_volume(0.3, false)
	Game.set_sfx_volume(0.6, false)
	Game.set_fullscreen(true, false)
	Game.set_key_binding("jump", KEY_K)

	# Scramble memory, then prove the file restores every setting.
	Game.music_volume = 1.0
	Game.sfx_volume = 1.0
	Game.fullscreen = false
	Game.reset_key_bindings(false)
	Game.call("_load_settings")
	_check_near(Game.music_volume, 0.3, EPS, "saved music volume")
	_check_near(Game.sfx_volume, 0.6, EPS, "saved SFX volume")
	_check(Game.fullscreen, "saved fullscreen setting was not restored")
	_check(Game.key_binding_text("jump") == "K",
		"saved jump key should be K, got %s" % Game.key_binding_text("jump"))

	Game.reset_key_bindings(false)
	Game.set_music_volume(0.8, false)
	Game.set_sfx_volume(1.0, false)
	Game.set_fullscreen(false, false)
	_remove_test_files()


func _test_window_scale(_zone: Zone) -> void:
	var base := Vector2i(424, 240)
	_check(Game.window_scale_for(Vector2i(1366, 728), base) == 2, "768p laptop should get 2x")
	_check(Game.window_scale_for(Vector2i(1920, 1040), base) == 3, "1080p should get 3x")
	_check(Game.window_scale_for(Vector2i(2560, 1400), base) == 5, "1440p should get 5x")
	_check(Game.window_scale_for(Vector2i(3840, 2120), base) == 7, "4K should get 7x")
	_check(Game.window_scale_for(Vector2i(400, 200), base) == 1, "tiny screens still get 1x")
	_check(InputMap.has_action("fullscreen"), "F11 fullscreen action is registered")


func _test_remap_rules(_zone: Zone) -> void:
	Game.reset_key_bindings(false)
	_check(Game.set_key_binding("jump", KEY_R, false), "jump should accept R")
	_check(not _action_has_key("restart", KEY_R), "R should leave restart once jump takes it")
	_check(not Game.set_key_binding("jump", KEY_ESCAPE, false), "Esc is reserved")
	_check(not Game.set_key_binding("pause", KEY_SPACE, false),
		"pause must not share a menu confirm key")
	_check(Game.set_key_binding("pause", KEY_X, false), "pause should accept X")
	_check(_action_has_key("pause", KEY_ESCAPE), "Esc should always stay on pause")
	_check(_action_has_key("pause", KEY_X), "pause should gain X")
	Game.reset_key_bindings(false)


func _action_has_key(action: String, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false


func _test_ring_life_resets(_zone: Zone) -> void:
	Game.reset_run()
	var start := Game.lives
	Game.add_rings(100)
	_check(Game.lives == start + 1, "100 rings should award a life")
	Game.reset_life()
	Game.add_rings(100)
	_check(Game.lives == start + 2, "the next life should be able to earn it again")
	Game.reset_run()


func _test_completion_records(_zone: Zone) -> void:
	_remove_test_files()
	Game.set("_best_times", {})
	_check(Game.record_completion(1, 0, 65.0), "a first clear should be a new best")
	_check(not Game.record_completion(1, 0, 80.0), "a slower clear replaced the best time")
	_check(Game.record_completion(1, 0, 60.0), "a faster clear should be a new best")
	_check_near(Game.best_time(1, 0), 60.0, EPS, "best completion time")
	_check(Game.cleared_count(1) == 1, "expected one cleared act for the character")

	Game.set("_best_times", {})
	Game.call("_load_progress")
	_check_near(Game.best_time(1, 0), 60.0, EPS, "reloaded completion time")
	Game.set("_best_times", {})
	_remove_test_files()


func _test_options_menu(_zone: Zone) -> void:
	Game.reset_key_bindings(false)
	Game.set_music_volume(0.8, false)
	var menu := OptionsMenu.create()
	add_child(menu)
	await get_tree().process_frame
	menu.open()
	menu.call("_adjust", -1)
	_check_near(Game.music_volume, 0.7, EPS, "music volume changed by the options menu")

	menu.call("_show_page", 1)
	menu.set("_selected", 0)
	menu.call("_confirm")
	_check(menu.get("_capturing") == "move_left", "control selection did not await a key")
	var key_event := InputEventKey.new()
	key_event.pressed = true
	key_event.physical_keycode = KEY_Q
	menu.call("_unhandled_input", key_event)
	_check(Game.key_binding_text("move_left") == "Q",
		"options menu should bind move left to Q, got %s" % Game.key_binding_text("move_left"))
	menu.close()
	_check(not menu.is_open(), "options menu should close cleanly")
	menu.queue_free()
	await get_tree().process_frame
	Game.reset_key_bindings(false)
	Game.set_music_volume(0.8, false)
	_remove_test_files()


# --------------------------------------------------------------------------- #
# menu and run boundaries
# --------------------------------------------------------------------------- #
## Launching the app must not drop straight into gameplay.
func _test_boots_to_menu(_zone: Zone) -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	_check(main_scene == Game.MENU_SCENE,
		"main scene should be %s, is %s" % [Game.MENU_SCENE, main_scene])
	_check(ResourceLoader.exists(Game.MENU_SCENE), "the menu scene is missing")
	_check(ResourceLoader.exists(Game.GAME_SCENE), "the game scene is missing")
	# the menu must not build a level of its own
	var menu: Node = load(Game.MENU_SCENE).instantiate()
	add_child(menu)
	await _frames(3)
	_check(menu.get_tree().get_nodes_in_group("player").is_empty(),
		"the menu should not spawn a player")
	menu.queue_free()
	await get_tree().process_frame


## Moving the cursor and confirming should settle on a character and hand over.
func _test_menu_select(_zone: Zone) -> void:
	Game.character_index = 0
	var menu: Node = load(Game.MENU_SCENE).instantiate()
	add_child(menu)
	await _frames(3)
	_press("select_3")
	await _frames(3)
	_release("select_3")
	await _frames(2)
	_check(menu.get("_selected") == 2, "expected the number keys to move the cursor")
	_press("move_right")
	await _frames(3)
	_release("move_right")
	await _frames(2)
	_check(menu.get("_selected") == 3, "expected the arrows to move the cursor")
	_check(menu.get("_options") is OptionsMenu, "the title screen should contain options")
	menu.call("_start")
	await _frames(2)
	_check(Game.character_index == 3,
		"expected the confirmed character to be recorded, got %d" % Game.character_index)
	_check(Game.act_index == 0, "a fresh run should start at the first act")
	menu.queue_free()
	await get_tree().process_frame

	# and the choice must survive into the run the menu hands off to
	var game: Node = load(Game.GAME_SCENE).instantiate()
	add_child(game)
	await _frames(3)
	var zone := game as Zone
	_check(zone != null, "the game scene should be a Zone")
	if zone != null:
		_check(zone.player != null, "the run should have a player")
		if zone.player != null:
			_check(zone.player.stats.slug == Characters.get_character(3).slug,
				"the run should use the character the menu confirmed, got %s"
					% zone.player.stats.slug)
	game.queue_free()
	await get_tree().process_frame


func _test_controller_pause_binding(_zone: Zone) -> void:
	var has_start := false
	for event in InputMap.action_get_events("pause"):
		if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_START:
			has_start = true
	_check(has_start, "the pause action has no controller start-button binding")


## A run keeps whichever character started it.
func _test_no_mid_run_switch(zone: Zone) -> void:
	var before := zone.player.stats.slug
	_check(before == Characters.get_character(2).slug,
		"expected the run to start as the chosen character")
	for i in Characters.count():
		_press("select_%d" % (i + 1))
		await _frames(2)
		_release("select_%d" % (i + 1))
	await _frames(4)
	_check(zone.player.stats.slug == before,
		"character changed mid-run from %s to %s" % [before, zone.player.stats.slug])
	_check(Game.character_index == 2, "the roster choice should be untouched during a run")


func _test_checkpoint_persists(zone: Zone) -> void:
	var where := Vector2(520.0, zone.surface_y(520.0))
	Game.set_checkpoint(where + Vector2(0, -20))
	Game.score = 50
	var post := Checkpoint.create(where)
	zone.add_child(post)
	await get_tree().process_frame
	_check(bool(post.get("_lit")), "the rebuilt checkpoint should already be active")
	var sprite := post.get("_sprite") as Sprite2D
	_check(sprite != null and is_equal_approx(sprite.region_rect.position.x, 24.0),
		"the rebuilt checkpoint should show its lit frame")
	post.call("_on_area_entered", _player_hitbox(zone.player))
	_check(Game.score == 50, "respawning at the checkpoint awarded its score again")


# --------------------------------------------------------------------------- #
# pause
# --------------------------------------------------------------------------- #
func _test_pause(zone: Zone) -> void:
	var player := zone.player
	await _place(zone, 300.0)
	_press("move_right")
	await _frames(40)
	_check(player.ground_speed > 0.0, "expected to be running before the pause")

	zone.pause_menu.pause()
	await _frames(2)
	_check(get_tree().paused, "expected the tree to be paused")
	_check(zone.pause_menu.is_paused(), "expected the pause menu to know it is up")
	var frozen_x: float = player.global_position.x
	var frozen_speed: float = player.ground_speed
	await _frames(30)
	_check_near(player.global_position.x, frozen_x, EPS, "position while paused")
	_check_near(player.ground_speed, frozen_speed, EPS, "ground speed while paused")

	zone.pause_menu.resume()
	await _frames(10)
	_check(not get_tree().paused, "expected the tree to resume")
	_check(player.global_position.x > frozen_x, "expected movement to continue after resuming")


func _test_pause_options(zone: Zone) -> void:
	zone.pause_menu.pause()
	zone.pause_menu.set("_selected", 2)
	zone.pause_menu.call("_confirm")
	var options := zone.pause_menu.get("_options_menu") as OptionsMenu
	_check(options != null and options.is_open(), "pause menu should open the options overlay")
	_check(get_tree().paused, "opening options should keep gameplay paused")
	if options != null:
		options.close()
	_check(get_tree().paused, "closing options should return to the paused menu")
	zone.pause_menu.resume()
	_check(not get_tree().paused, "resuming after options should unpause the game")


## A scene change made while paused would load the next scene frozen, so every
## way out of this menu has to clear the flag.
func _test_pause_exits_clean(zone: Zone) -> void:
	# Options stays paused by design; the three actual exits must clear the flag.
	for option in [0, 1, 3]:
		zone.pause_menu.pause()
		await _frames(2)
		_check(get_tree().paused, "option %d: expected a pause" % option)
		zone.pause_menu.set("_selected", option)
		zone.pause_menu.call("_confirm")
		await _frames(2)
		_check(not get_tree().paused,
			"option %d (%s) left the tree paused" % [option, PauseMenu.OPTIONS[option]])
		_check(not zone.pause_menu.is_paused(),
			"option %d left the menu thinking it is still up" % option)


# --------------------------------------------------------------------------- #
# boss
# --------------------------------------------------------------------------- #
## The boss lives in act 3, so these build that act rather than the fixture.
func _boss_zone() -> Zone:
	Game.reset_run()
	Game.checkpoint_set = false
	var zone := Zone.new()
	zone.act = Acts.canyon_act_3()
	zone.auto_restart = false
	add_child(zone)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return zone


func _find_boss(zone: Zone) -> Boss:
	for node in zone.get_children():
		if node is Boss:
			return node
	return null


func _test_boss_wakes(_fixture: Zone) -> void:
	var zone := await _boss_zone()
	var boss := _find_boss(zone)
	_check(boss != null, "act 3 should contain a boss")
	if boss == null:
		zone.queue_free()
		return
	_check(boss.phase == Boss.Phase.WAITING, "the boss should wait until approached")
	var wide_limit := zone.camera.limit_right
	# walk the player into the arena
	zone.player.global_position = Vector2(boss.position.x - 150.0, boss.position.y + 80.0)
	await _frames(20)
	_check(boss.phase != Boss.Phase.WAITING, "the boss should wake once inside the arena")
	_check(zone.camera.limit_right < wide_limit,
		"the camera should be pinned to the arena, right limit is still %d"
			% zone.camera.limit_right)
	_check(zone.camera.limit_left > int(boss.position.x) - 400,
		"the camera's left limit should seal the arena")
	zone.queue_free()
	await get_tree().process_frame


func _test_boss_damage(_fixture: Zone) -> void:
	var zone := await _boss_zone()
	var boss := _find_boss(zone)
	if boss == null:
		zone.queue_free()
		return
	var player := zone.player
	Game.add_rings(5)
	player.global_position = Vector2(boss.position.x - 150.0, boss.position.y + 80.0)
	await _frames(20)

	# walking into the pod without attacking costs rings, not boss health
	var hp_before: int = boss.hp
	_reset_player(player, boss.global_position + Vector2(0, 10))
	await _frames(4)
	_check(boss.hp == hp_before, "an unattacking touch should not hurt the boss")
	_check(Game.rings < 5, "an unattacking touch should cost the player rings")

	# attacking into it does damage. Step clear first: area_entered only fires on
	# entry, so re-touching from inside the pod would raise nothing. Park inside
	# the arena rather than below it, or the fall would kill the player instead.
	_reset_player(player, Vector2(boss.position.x - 160.0, boss.position.y + 80.0))
	await _frames(6)
	# attack as a jump, not a standing roll: a roll with no ground speed uncurls
	# on the same frame, which is correct SPG behaviour and would be an
	# impossible way to reach the pod in real play
	_reset_player(player, boss.global_position + Vector2(0, 10))
	player.grounded = false
	player.jumping = true
	player.velocity = Vector2(0.0, -1.0)
	await _frames(4)
	_check(boss.hp < hp_before, "jumping into the pod should hurt it, hp is %d" % boss.hp)
	zone.queue_free()
	await get_tree().process_frame


func _test_boss_resume_edge(_fixture: Zone) -> void:
	var zone := await _boss_zone()
	var boss := _find_boss(zone)
	if boss == null:
		zone.queue_free()
		return
	var origin: Vector2 = boss.get("_origin")
	zone.player.global_position = Vector2(origin.x - 300.0, origin.y + 80.0)
	boss.hp = Boss.MAX_HP - 1
	boss.phase = Boss.Phase.HURT
	boss.position.x = origin.x - 60.0
	boss.set("_hurt_timer", 1)
	boss.set("_knockback", Vector2.ZERO)
	await _frames(2)
	_check(boss.position.x < origin.x,
		"the boss crossed the arena after flinching on the left (x %.1f, centre %.1f)"
			% [boss.position.x, origin.x])
	zone.queue_free()
	await get_tree().process_frame


## Drop the player at `where` in a clean, unhurt, non-attacking state.
func _reset_player(player: Player, where: Vector2) -> void:
	player.state = Player.State.NORMAL
	player.invuln = 0
	player.rolling = false
	player.jumping = false
	player.velocity = Vector2.ZERO
	player.ground_speed = 0.0
	player.global_position = where


func _test_boss_defeat(_fixture: Zone) -> void:
	var zone := await _boss_zone()
	var boss := _find_boss(zone)
	if boss == null:
		zone.queue_free()
		return
	var player := zone.player
	player.global_position = Vector2(boss.position.x - 150.0, boss.position.y + 80.0)
	await _frames(20)
	_check(boss.hp == Boss.MAX_HP, "the boss should start on full health")

	for i in Boss.MAX_HP:
		boss.take_hit(player)
		await get_tree().physics_frame
	_check(boss.phase == Boss.Phase.DYING or boss.phase == Boss.Phase.DONE,
		"%d hits should finish the boss" % Boss.MAX_HP)

	# the death sequence runs, then the capsule appears
	await _frames(int(Boss.DEATH_SECONDS * 60.0) + 20)
	var capsule: Capsule = null
	for node in zone.get_children():
		if node is Capsule:
			capsule = node
	_check(capsule != null, "beating the boss should drop the capsule")
	if capsule != null:
		capsule.call("_on_switch_hit", _player_hitbox(player))
		await _frames(4)
		_check(player.state == Player.State.GOAL, "opening the capsule should clear the act")
	zone.queue_free()
	await get_tree().process_frame


func _test_boss_ball(_fixture: Zone) -> void:
	var zone := await _boss_zone()
	var boss := _find_boss(zone)
	if boss == null:
		zone.queue_free()
		return
	var player := zone.player
	Game.add_rings(9)
	player.global_position = Vector2(boss.position.x - 150.0, boss.position.y + 80.0)
	await _frames(20)
	var hp_before: int = boss.hp
	player.rolling = true
	player.invuln = 0
	var ball: Node2D = boss.get("_ball")
	player.global_position = ball.global_position + Vector2(0, 400)
	await _frames(2)
	player.global_position = ball.global_position
	await _frames(4)
	_check(Game.rings < 9, "the ball should hurt even an attacking player")
	_check(boss.hp == hp_before, "the ball is not a target")
	zone.queue_free()
	await get_tree().process_frame


## The player's damage box, as objects see it.
func _player_hitbox(player: Player) -> Area2D:
	for child in player.get_children():
		if child is Area2D:
			return child
	return null


# --------------------------------------------------------------------------- #
# act placement validation
# --------------------------------------------------------------------------- #
## Walk an act's segments the way Zone does and return the x ranges with no
## ground under them.
func _gap_ranges(act: ActData) -> Array[Vector2]:
	var gaps: Array[Vector2] = []
	var x := 0.0
	for segment in act.layout:
		var length := 0.0
		match segment["kind"]:
			"loop":
				length = float(segment["radius"]) * 2.0 + 80.0
			"gap":
				length = float(segment["length"])
				gaps.append(Vector2(x, x + length))
			_:
				length = float(segment["length"])
		x += length
	return gaps


## Object kinds that are *meant* to hang over a pit.
func _may_span_gap(what: String) -> bool:
	return what in ["ring_line", "ring_arc", "platform"]


## Placement mistakes that cost real time to find by playing: something resting
## on nothing, or a reward sitting just past the edge of the ledge meant to hold
## it. Both happened while act 2 was being built.
func _test_act_placement(_zone: Zone) -> void:
	for index in Acts.count():
		var act := Acts.get_act(index)
		var label := "%s act %d" % [act.zone_name, act.act_number]
		var gaps := _gap_ranges(act)

		# collect the blocks first: things placed high up are usually on one
		var blocks: Array[Dictionary] = []
		for entry in act.objects:
			if entry.get("what", "") == "block":
				var width: float = float(entry.get("width", 96.0))
				blocks.append({
					"left": float(entry["x"]) - width * 0.5,
					"right": float(entry["x"]) + width * 0.5,
					"top": float(entry.get("y", 0.0)),
				})

		for entry in act.objects:
			var what := String(entry.get("what", ""))
			var x := float(entry.get("x", 0.0))
			var lift := float(entry.get("y", 0.0))

			# nothing may rest over a pit unless it is a trail or a ferry
			if not _may_span_gap(what):
				for gap in gaps:
					_check(x < gap.x or x > gap.y,
						"%s: %s at x = %.0f is over the gap %.0f-%.0f" % [
							label, what, x, gap.x, gap.y])

			# anything lifted to a block's height should be within that block
			if what in ["monitor", "spring", "spikes", "checkpoint", "goal"] and lift > 24.0:
				var supported := false
				for block in blocks:
					if is_equal_approx(float(block["top"]), lift) \
							and x >= float(block["left"]) and x <= float(block["right"]):
						supported = true
				_check(supported,
					"%s: %s at x = %.0f sits %.0f up with no block under it" % [
						label, what, x, lift])
