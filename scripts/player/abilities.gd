extends RefCounted
class_name Abilities
## Mid-air special moves, hung off a single hook: jump pressed while already
## airborne. Each character has at most one, chosen by CharacterStats.ability.
##
## These live outside player.gd because they are the only part of movement that is
## not shared: the SPG rules apply to everyone, and this is where a character
## stops being the reference implementation.
##
## The functions here mutate the player directly rather than returning a result,
## which mirrors how the rest of the movement code is written.

const GLIDE_STEER := 0.046875   ## how quickly a glide can be re-aimed
const GLIDE_TURN_SPEED := 2.0   ## horizontal speed retained through a turn
const CLIMB_LEDGE_HOP := Vector2(1.5, -4.0)
const WALL_PUSH_OFF := Vector2(3.5, -4.5)


## Called when jump is pressed in mid-air. Does nothing for characters without an
## ability, or once the ability has been spent for this airtime.
static func trigger(player: Player) -> void:
	match player.stats.ability:
		CharacterStats.Ability.FLY:
			_trigger_fly(player)
		CharacterStats.Ability.GLIDE:
			_trigger_glide(player)
		CharacterStats.Ability.AIR_DASH:
			_trigger_dash(player)
		CharacterStats.Ability.HAMMER:
			_trigger_hammer(player)
		_:
			pass


## Per-frame update for whichever air move is running. Returns true if it has
## taken over vertical motion, in which case the caller skips normal gravity.
static func step(player: Player, dt: float) -> bool:
	match player.air_move:
		Player.AirMove.FLY:
			return _step_fly(player, dt)
		Player.AirMove.GLIDE:
			return _step_glide(player, dt)
		Player.AirMove.DASH:
			return _step_dash(player, dt)
		Player.AirMove.HAMMER:
			return _step_hammer(player, dt)
		_:
			return false


## Clear anything that should not survive touching the ground.
static func on_landed(player: Player) -> void:
	if player.air_move == Player.AirMove.GLIDE:
		# a glide that reaches the floor skids to a stop rather than keeping speed
		player.ground_speed *= 0.5
	player.air_move = Player.AirMove.NONE
	player.air_move_timer = 0
	player.ability_spent = false
	player.refresh_hitbox()


# --------------------------------------------------------------------------- #
# flight
# --------------------------------------------------------------------------- #
static func _trigger_fly(player: Player) -> void:
	if player.air_move == Player.AirMove.FLY:
		return  # already flying; holding jump is what gains height
	if player.ability_spent:
		return
	player.air_move = Player.AirMove.FLY
	player.air_move_timer = player.stats.fly_frames
	player.ability_spent = true
	player.jumping = false  # flight is not an attack
	Sfx.play("spring", 1.5, -8.0)


static func _step_fly(player: Player, dt: float) -> bool:
	player.air_move_timer -= 1
	if player.air_move_timer <= 0:
		# out of puff: fall normally for the rest of the airtime
		player.air_move = Player.AirMove.NONE
		return false
	if Input.is_action_pressed("jump") and player.control_enabled:
		player.velocity.y -= player.stats.fly_lift * dt
		player.velocity.y = maxf(player.velocity.y, -player.stats.fly_max_rise)
		if player.air_move_timer % 12 == 0:
			Sfx.play("spring", 1.8, -18.0)
	else:
		# gliding descent while not climbing
		player.velocity.y += player.stats.gravity * 0.35 * dt
		player.velocity.y = minf(player.velocity.y, 2.0)
	return true


# --------------------------------------------------------------------------- #
# glide and wall climb
# --------------------------------------------------------------------------- #
static func _trigger_glide(player: Player) -> void:
	if player.ability_spent or player.air_move == Player.AirMove.GLIDE:
		return
	player.air_move = Player.AirMove.GLIDE
	player.ability_spent = true
	player.velocity.x = player.facing * player.stats.glide_speed
	player.velocity.y = maxf(player.velocity.y, 0.0)
	Sfx.play("spindash_charge", 0.6, -10.0)


static func _step_glide(player: Player, dt: float) -> bool:
	if not Input.is_action_pressed("jump") or not player.control_enabled:
		player.air_move = Player.AirMove.NONE
		return false

	# steering: holding the opposite direction turns the glide around
	var axis := 0.0
	if Input.is_action_pressed("move_right"):
		axis += 1.0
	if Input.is_action_pressed("move_left"):
		axis -= 1.0
	if axis != 0.0:
		player.velocity.x = move_toward(
			player.velocity.x, axis * player.stats.glide_speed, GLIDE_STEER * dt * 8.0
		)
		if absf(player.velocity.x) < GLIDE_TURN_SPEED:
			player.facing = int(signf(axis))

	player.velocity.y = move_toward(
		player.velocity.y, player.stats.glide_fall, player.stats.gravity * 0.5 * dt
	)

	# grabbing a wall turns the glide into a climb. Probe by facing, not by
	# velocity: the push sensors have already zeroed horizontal speed by the time
	# the player is up against the wall, which would leave no direction to test.
	var side := signf(player.velocity.x)
	if side == 0.0:
		side = float(player.facing)
	if player.wall_ahead(side):
		_begin_climb(player, side)
	return true


static func _begin_climb(player: Player, side: float) -> void:
	player.state = Player.State.CLIMB
	player.air_move = Player.AirMove.NONE
	player.climb_side = side
	player.facing = int(side)
	player.velocity = Vector2.ZERO
	player.ground_speed = 0.0
	Sfx.play("break", 1.6, -14.0)


## Climbing is its own player state: no gravity, vertical movement along a wall.
static func step_climb(player: Player, dt: float) -> void:
	if not player.control_enabled:
		return
	if Input.is_action_just_pressed("jump"):
		# push off backwards, away from the wall
		player.state = Player.State.NORMAL
		player.velocity = Vector2(
			-player.climb_side * WALL_PUSH_OFF.x, WALL_PUSH_OFF.y
		)
		player.facing = int(-player.climb_side)
		player.grounded = false
		player.jumping = true
		player.ability_spent = false
		Sfx.play("jump", 1.1)
		return

	var climb := 0.0
	if Input.is_action_pressed("look_up"):
		climb -= 1.0
	if Input.is_action_pressed("crouch"):
		climb += 1.0
	player.position.y += climb * player.stats.climb_speed * dt

	if not player.wall_ahead(player.climb_side):
		# topped out: hop over the lip onto whatever is up there
		player.state = Player.State.NORMAL
		player.grounded = false
		player.velocity = Vector2(
			player.climb_side * CLIMB_LEDGE_HOP.x, CLIMB_LEDGE_HOP.y
		)
		return

	# let go by pressing away from the wall
	var away := -player.climb_side
	if (away > 0.0 and Input.is_action_pressed("move_right")) \
			or (away < 0.0 and Input.is_action_pressed("move_left")):
		player.state = Player.State.NORMAL
		player.grounded = false
		player.velocity = Vector2.ZERO


# --------------------------------------------------------------------------- #
# air dash
# --------------------------------------------------------------------------- #
static func _trigger_dash(player: Player) -> void:
	if player.ability_spent:
		return
	player.air_move = Player.AirMove.DASH
	player.air_move_timer = player.stats.dash_frames
	player.ability_spent = true

	var target := _nearest_target(player)
	if target != null:
		var to_target := (target.global_position - player.global_position).normalized()
		player.velocity = to_target * player.stats.dash_speed
		player.facing = int(signf(to_target.x)) if absf(to_target.x) > 0.1 else player.facing
	else:
		player.velocity = Vector2(player.facing * player.stats.dash_speed, 0.0)
	Sfx.play("spindash_release", 1.4, -6.0)


static func _step_dash(player: Player, dt: float) -> bool:
	player.air_move_timer -= 1
	if player.air_move_timer <= 0:
		player.air_move = Player.AirMove.NONE
		# bleed the dash off rather than dropping like a stone
		player.velocity.x *= 0.6
		return false
	return true  # no gravity for the duration


## Closest badnik within homing range and roughly ahead of the player.
static func _nearest_target(player: Player) -> Node2D:
	var best: Node2D = null
	var best_distance := player.stats.homing_range
	for node in player.get_tree().get_nodes_in_group("badnik"):
		var badnik := node as Node2D
		if badnik == null:
			continue
		var offset := badnik.global_position - player.global_position
		if signf(offset.x) != signf(player.facing) and absf(offset.x) > 16.0:
			continue
		var distance := offset.length()
		if distance < best_distance:
			best_distance = distance
			best = badnik
	return best


# --------------------------------------------------------------------------- #
# hammer
# --------------------------------------------------------------------------- #
static func _trigger_hammer(player: Player) -> void:
	if player.ability_spent:
		return
	player.air_move = Player.AirMove.HAMMER
	player.air_move_timer = player.stats.hammer_frames
	player.ability_spent = true
	player.velocity.y = minf(player.velocity.y, -player.stats.hammer_lift)
	# the swing reaches further than the body, so widen the damage box
	player.set_hitbox_width(38.0, player.facing * 10.0)
	Sfx.play("break", 1.3, -6.0)


static func _step_hammer(player: Player, dt: float) -> bool:
	player.air_move_timer -= 1
	if player.air_move_timer <= 0:
		player.air_move = Player.AirMove.NONE
		player.refresh_hitbox()
	return false  # the swing does not change how gravity applies
