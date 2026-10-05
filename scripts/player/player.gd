extends Node2D
class_name Player
## Player character with Genesis-accurate 360 degree movement.
##
## Every constant below is the value published in the Sonic Retro Physics Guide
## (SPG), expressed in pixels per frame at 60 fps; `_physics_process` scales by
## `delta * 60` so behaviour is identical if the tick rate is changed. They are
## the reference values: live movement reads `stats`, and CharacterStats defaults
## to exactly these numbers, so the roster is defined by what it overrides.
##
## Collision uses SPG-style sensors rather than Godot's move_and_slide: two
## floor sensors, two ceiling sensors and two push sensors are raycast against
## the terrain each frame, and the ground angle is read from the surface normal.
## See scripts/player/sensors.gd for the ray helpers.

signal died()
signal reached_goal()

const ACC := 0.046875           ## ground acceleration
const DEC := 0.5                ## braking when input opposes motion
const FRC := 0.046875           ## ground friction with no input
const TOP := 6.0                ## top speed under own power
const AIR_ACC := 0.09375        ## air acceleration (2x ground)
const GRV := 0.21875            ## gravity
const JUMP_FORCE := 6.5         ## initial jump velocity
const JUMP_RELEASE := 4.0       ## velocity cap when the jump button is let go
const SLOPE := 0.125            ## slope factor while running
const SLOPE_ROLL_UP := 0.078125 ## slope factor rolling uphill
const SLOPE_ROLL_DOWN := 0.3125 ## slope factor rolling downhill
const FRC_ROLL := 0.0234375     ## rolling friction (FRC / 2)
const DEC_ROLL := 0.125         ## braking while rolling
const TOP_ROLL := 16.0
const MAX_SPEED := 16.0         ## per-axis velocity clamp
const AIR_DRAG_LIMIT := 4.0     ## drag applies while -4 < ysp < 0
const AIR_DRAG := 31.0 / 32.0   ## ((xsp / 0.125) / 256) reduces xsp by 1/32
const FALL_OFF_SPEED := 2.5     ## below this speed steep ground is lost
const CONTROL_LOCK_FRAMES := 30
const ROLL_MIN_SPEED := 0.5
const UNROLL_SPEED := 0.5
const SPINDASH_MAX := 8.0
const SPINDASH_BASE := 8.0
const HURT_KNOCKBACK := Vector2(2.0, -4.0)
const INVULN_FRAMES := 120
const DEATH_RISE := 7.0

## Speed shoes double acceleration and lift the cap to 12, for 20 seconds.
const SHOES_ACC := 0.09375
const SHOES_TOP := 12.0
const SHOES_FRC := 0.09375
const SHOES_AIR_ACC := 0.1875
const POWERUP_FRAMES := 1200

const WIDTH_RADIUS := 9.0
const HEIGHT_RADIUS := 19.0
const WIDTH_RADIUS_ROLL := 7.0
const HEIGHT_RADIUS_ROLL := 14.0
const PUSH_RADIUS := 10.0

## Landing conversion thresholds from SPG "Slope Physics" (hex 0x20 / 0x40).
const SHALLOW := deg_to_rad(22.5)
const STEEP := deg_to_rad(45.0)

enum State { NORMAL, SPINDASH, HURT, DEAD, GOAL, CLIMB }

## Air moves are variations on the airborne state rather than states of their own,
## because the SPG air rules (drag, control, landing) still apply around them.
enum AirMove { NONE, FLY, GLIDE, DASH, HAMMER }

@export var start_path_layer := 0

## Movement values for whoever is being played. Assigned before the node enters
## the tree; defaults to the reference character so Player.new() stays usable.
var stats: CharacterStats = Characters.runner()

var ground_speed := 0.0
var velocity := Vector2.ZERO
var ground_angle := 0.0
var grounded := true
var rolling := false
var jumping := false
var pushing := false
var state: State = State.NORMAL
var facing := 1
var control_lock := 0
var path_layer := 0
var invuln := 0
var invincible := 0        ## frames of shield power-up left
var shoes := 0             ## frames of speed shoes left
var spindash_charge := 0.0
var camera_lag := 0            ## frames the camera should hold still
var width_radius := WIDTH_RADIUS
var height_radius := HEIGHT_RADIUS
var push_radius := PUSH_RADIUS
var look_timer := 0            ## frames spent holding up/down, for camera pan
var control_enabled := true
var air_move: AirMove = AirMove.NONE
var air_move_timer := 0
var ability_spent := false     ## one special move per airtime
var climb_side := 0.0          ## which side the wall is on while climbing

var _sensors: Sensors
var _sprite: AnimatedSprite2D
var _hitbox: Area2D
var _hitbox_shape: RectangleShape2D
var _animation := ""
var _dust: AnimatedSprite2D
var _death_timer := 0.0


static func create(character: CharacterStats) -> Player:
	var player := Player.new()
	player.stats = character
	player.width_radius = character.width_radius
	player.height_radius = character.height_radius
	player.push_radius = character.push_radius
	return player


func _ready() -> void:
	add_to_group("player")
	_sensors = Sensors.new(self)
	path_layer = start_path_layer
	_build_sprite()
	_build_hitbox()
	set_physics_process(true)


# --------------------------------------------------------------------------- #
# construction
# --------------------------------------------------------------------------- #
func _build_sprite() -> void:
	var sheet: Texture2D = load(stats.sprite_sheet())
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var layout := {
		"idle": [0],
		"walk": [1, 2, 3, 4],
		"run": [5, 6, 7, 8],
		"roll": [9, 10, 11, 12],
		"skid": [13],
		"crouch": [14],
		"lookup": [15],
		"push": [16, 17],
		"hurt": [18],
		"dead": [19],
		"spring": [20],
		"fly": [22, 23],
		"glide": [24],
		"climb": [25, 26],
		"hammer": [27, 28],
	}
	for anim_name in layout:
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, true)
		frames.set_animation_speed(anim_name, 12.0)
		for index in layout[anim_name]:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2((index % 11) * 40, (index / 11) * 44, 40, 44)
			frames.add_frame(anim_name, atlas)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = frames
	_sprite.animation = "idle"
	_sprite.centered = true
	_sprite.offset = Vector2(0, 0)
	add_child(_sprite)

	var dust_frames := SpriteFrames.new()
	dust_frames.remove_animation("default")
	dust_frames.add_animation("puff")
	dust_frames.set_animation_loop("puff", true)
	dust_frames.set_animation_speed("puff", 16.0)
	var dust_sheet: Texture2D = load("res://assets/sprites/dust.png")
	for i in 4:
		var atlas := AtlasTexture.new()
		atlas.atlas = dust_sheet
		atlas.region = Rect2(i * 24, 0, 24, 24)
		dust_frames.add_frame("puff", atlas)
	_dust = AnimatedSprite2D.new()
	_dust.sprite_frames = dust_frames
	_dust.animation = "puff"
	_dust.visible = false
	_dust.z_index = -1
	add_child(_dust)


func _build_hitbox() -> void:
	_hitbox = Area2D.new()
	_hitbox.collision_layer = Game.COLLISION_LAYERS.player_hitbox
	_hitbox.collision_mask = 0
	_hitbox.monitorable = true
	_hitbox.monitoring = false
	_hitbox_shape = RectangleShape2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = _hitbox_shape
	_hitbox.add_child(shape)
	add_child(_hitbox)
	_update_hitbox()


func _update_hitbox() -> void:
	# SPG: the damage box is narrower than the terrain sensors (8 x height)
	_hitbox_shape.size = Vector2(16.0, height_radius * 2.0 - 6.0)
	_hitbox.position = Vector2.ZERO


## Widen the damage box, for moves that reach past the body.
func set_hitbox_width(width: float, offset_x: float) -> void:
	_hitbox_shape.size = Vector2(width, height_radius * 2.0 - 6.0)
	_hitbox.position = Vector2(offset_x, 0.0)


func refresh_hitbox() -> void:
	_update_hitbox()


func hitbox_size() -> Vector2:
	return _hitbox_shape.size


## Is there a wall within push range on `side`? Used by the glide/climb ability.
func wall_ahead(side: float) -> bool:
	var hit := _sensors.wall_hit(side, 0.0)
	return not hit.is_empty() and float(hit["distance"]) <= push_radius + 1.0


# --------------------------------------------------------------------------- #
# frame
# --------------------------------------------------------------------------- #
func _physics_process(delta: float) -> void:
	var dt := delta * 60.0
	if invuln > 0:
		invuln -= 1
	if invincible > 0:
		invincible -= 1
	if shoes > 0:
		shoes -= 1
		if shoes == 0:
			Sfx.play("spindash_charge", 0.7)

	match state:
		State.DEAD:
			_step_dead(dt, delta)
		State.HURT:
			_step_air(dt, true)
		State.SPINDASH:
			_step_spindash(dt)
		State.CLIMB:
			Abilities.step_climb(self, dt)
		_:
			if grounded:
				_step_ground(dt)
			else:
				_step_air(dt, false)

	_update_look_timer()
	_animate(delta)


func _input_axis() -> float:
	if not control_enabled or control_lock > 0:
		return 0.0
	var axis := 0.0
	if Input.is_action_pressed("move_right"):
		axis += 1.0
	if Input.is_action_pressed("move_left"):
		axis -= 1.0
	return axis


# --------------------------------------------------------------------------- #
# ground state
# --------------------------------------------------------------------------- #
func _step_ground(dt: float) -> void:
	if control_lock > 0:
		control_lock -= 1

	var axis := _input_axis()
	var down_input := control_enabled and Input.is_action_pressed("crouch")

	if state == State.GOAL:
		# hands off after the sign: coast on and let friction do the stopping
		axis = 0.0
		down_input = false

	# --- start a spindash or a roll ---------------------------------------- #
	if down_input and not rolling:
		if absf(ground_speed) < ROLL_MIN_SPEED:
			if stats.can_spindash and Input.is_action_just_pressed("jump"):
				_begin_spindash()
				return
		else:
			_set_rolling(true)

	# --- slope factor ------------------------------------------------------ #
	var slope_sin := sin(ground_angle)
	if rolling:
		# rolling downhill pulls harder than rolling uphill
		var downhill := signf(ground_speed) == signf(slope_sin) and absf(slope_sin) > 0.01
		var factor := SLOPE_ROLL_DOWN if downhill else SLOPE_ROLL_UP
		ground_speed += factor * slope_sin * dt
	elif absf(ground_speed) > 0.0 or absf(slope_sin) > 0.01:
		ground_speed += SLOPE * slope_sin * dt

	# --- acceleration, braking, friction ----------------------------------- #
	if rolling:
		_apply_roll_input(axis, dt)
	else:
		_apply_run_input(axis, dt)

	if state == State.GOAL:
		ground_speed = clampf(ground_speed, -TOP, TOP)

	# --- jump -------------------------------------------------------------- #
	if control_enabled and state != State.GOAL and Input.is_action_just_pressed("jump"):
		_jump()
		return

	# --- move -------------------------------------------------------------- #
	velocity = Vector2(cos(ground_angle), sin(ground_angle)) * ground_speed
	position += velocity * dt

	# --- collide ----------------------------------------------------------- #
	_check_walls()
	_check_ceiling_grounded()
	_snap_to_floor()

	if grounded:
		_check_slip()

	if rolling and absf(ground_speed) < UNROLL_SPEED:
		_set_rolling(false)


func acceleration() -> float:
	return SHOES_ACC if shoes > 0 else stats.acceleration


func top_speed() -> float:
	return SHOES_TOP if shoes > 0 else stats.top_speed


func friction() -> float:
	return SHOES_FRC if shoes > 0 else stats.friction


func air_acceleration() -> float:
	return SHOES_AIR_ACC if shoes > 0 else stats.air_acceleration


func _apply_run_input(axis: float, dt: float) -> void:
	var top := top_speed()
	if axis > 0.0:
		if ground_speed < 0.0:
			ground_speed += stats.deceleration * dt
			if ground_speed >= 0.0:
				ground_speed = 0.5  # SPG: braking through zero snaps to 0.5
		elif ground_speed < top:
			ground_speed = minf(top, ground_speed + acceleration() * dt)
		facing = 1
	elif axis < 0.0:
		if ground_speed > 0.0:
			ground_speed -= stats.deceleration * dt
			if ground_speed <= 0.0:
				ground_speed = -0.5
		elif ground_speed > -top:
			ground_speed = maxf(-top, ground_speed - acceleration() * dt)
		facing = -1
	else:
		var drag := minf(absf(ground_speed), friction() * dt)
		ground_speed -= drag * signf(ground_speed)


func _apply_roll_input(axis: float, dt: float) -> void:
	# rolling cannot accelerate, only brake
	if axis > 0.0 and ground_speed < 0.0:
		ground_speed += stats.roll_deceleration * dt
	elif axis < 0.0 and ground_speed > 0.0:
		ground_speed -= stats.roll_deceleration * dt
	var drag := minf(absf(ground_speed), stats.roll_friction * dt)
	ground_speed -= drag * signf(ground_speed)
	ground_speed = clampf(ground_speed, -stats.roll_top_speed, stats.roll_top_speed)


func _jump() -> void:
	var normal := Vector2(sin(ground_angle), -cos(ground_angle))
	velocity += normal * stats.jump_force
	grounded = false
	jumping = true
	pushing = false
	ground_angle = 0.0
	air_move = AirMove.NONE
	air_move_timer = 0
	ability_spent = false
	_set_size(true, false)
	Sfx.play("jump")


func _check_slip() -> void:
	var angle := wrapf(ground_angle, -PI, PI)
	if absf(ground_speed) >= FALL_OFF_SPEED or absf(angle) < STEEP:
		return
	if absf(angle) >= PI * 0.5:
		# too steep to cling to: drop off entirely
		grounded = false
		ground_speed = 0.0
		velocity = Vector2.ZERO
		ground_angle = 0.0
	else:
		ground_speed = 0.0
	control_lock = CONTROL_LOCK_FRAMES


# --------------------------------------------------------------------------- #
# air state
# --------------------------------------------------------------------------- #
func _step_air(dt: float, hurt: bool) -> void:
	if not hurt:
		var axis := _input_axis()
		if axis != 0.0:
			facing = int(signf(axis))
			# air control never pushes past top speed, but speed already above it
			# (from a slope or a spindash) is preserved
			var top := top_speed()
			var pushed := velocity.x + air_acceleration() * axis * dt
			if absf(pushed) <= top or signf(pushed) != signf(axis):
				velocity.x = pushed
			elif absf(velocity.x) < top:
				velocity.x = top * signf(axis)

		# releasing jump early cuts the rise short
		if jumping and velocity.y < -JUMP_RELEASE and not Input.is_action_pressed("jump"):
			velocity.y = -JUMP_RELEASE

		# air drag: only while rising slowly, and it never touches vertical speed
		if velocity.y < 0.0 and velocity.y > -AIR_DRAG_LIMIT:
			velocity.x *= pow(AIR_DRAG, dt)

		# the one hook every special move hangs off: jump, in mid-air
		if control_enabled and Input.is_action_just_pressed("jump"):
			Abilities.trigger(self)

	# an active air move may take over vertical motion entirely
	if not Abilities.step(self, dt):
		velocity.y += stats.gravity * dt
	velocity.y = minf(velocity.y, MAX_SPEED)
	velocity.x = clampf(velocity.x, -MAX_SPEED, MAX_SPEED)

	position += velocity * dt

	if state == State.HURT:
		# a knocked-back player still lands, but ignores walls and ceilings
		_check_floor_from_air()
		return

	_check_walls()
	_check_ceiling_air()
	_check_floor_from_air()


func _check_floor_from_air() -> void:
	if velocity.y < 0.0:
		return
	var hit := _sensors.floor_hit(Vector2.ZERO, 0.0)
	if hit.is_empty():
		return
	var distance: float = hit["distance"]
	# land only once the feet have reached or passed the surface this frame
	if distance > 0.0 or distance < -maxf(16.0, absf(velocity.y) + 8.0):
		return
	_land(hit)


func _land(hit: Dictionary) -> void:
	position += Vector2.DOWN * hit["distance"]
	ground_angle = _angle_from_normal(hit["normal"])
	grounded = true
	jumping = false
	Abilities.on_landed(self)
	if state == State.HURT:
		state = State.NORMAL
		ground_speed = 0.0
		velocity = Vector2.ZERO
		return

	# SPG landing conversion: shallow ground keeps xsp, steeper ground trades
	# vertical speed for ground speed.
	var angle := wrapf(ground_angle, -PI, PI)
	if absf(angle) < SHALLOW:
		ground_speed = velocity.x
	elif absf(angle) < STEEP:
		ground_speed = velocity.x if absf(velocity.x) > absf(velocity.y) \
			else velocity.y * 0.5 * signf(sin(angle))
	else:
		ground_speed = velocity.x if absf(velocity.x) > absf(velocity.y) \
			else velocity.y * signf(sin(angle))

	if rolling:
		_set_size(true, false)
	else:
		_set_size(false, false)
	_snap_to_floor()


# --------------------------------------------------------------------------- #
# spindash
# --------------------------------------------------------------------------- #
func _begin_spindash() -> void:
	state = State.SPINDASH
	spindash_charge = 0.0
	ground_speed = 0.0
	_set_rolling(false)
	Sfx.play("spindash_charge")


func _step_spindash(dt: float) -> void:
	# charge bleeds away, so mashing is what builds real speed
	spindash_charge -= ((spindash_charge / 0.125) / 256.0) * dt
	spindash_charge = maxf(0.0, spindash_charge)

	if Input.is_action_just_pressed("jump"):
		spindash_charge = minf(SPINDASH_MAX, spindash_charge + 2.0)
		Sfx.play("spindash_charge", 1.0 + spindash_charge * 0.06)

	if not Input.is_action_pressed("crouch") or not control_enabled:
		_release_spindash()
		return

	_snap_to_floor()
	if not grounded:
		state = State.NORMAL


func _release_spindash() -> void:
	state = State.NORMAL
	ground_speed = (SPINDASH_BASE + floorf(spindash_charge) / 2.0) * facing
	spindash_charge = 0.0
	camera_lag = 16
	_set_rolling(true)
	Sfx.play("spindash_release")


# --------------------------------------------------------------------------- #
# collision helpers
# --------------------------------------------------------------------------- #
func _snap_to_floor() -> void:
	var hit := _sensors.floor_hit(Vector2.ZERO, ground_angle)
	if hit.is_empty():
		grounded = false
		return
	var distance: float = hit["distance"]
	# SPG: how far the player may be pulled down to stay on the ground
	var limit := minf(absf(velocity.x) + 4.0, 14.0)
	if distance > limit:
		grounded = false
		return
	var normal_angle := _angle_from_normal(hit["normal"])
	if absf(angle_difference(normal_angle, ground_angle)) > deg_to_rad(70.0):
		# a wall face, not the floor we are running along
		return
	position += Vector2.DOWN.rotated(ground_angle) * distance
	ground_angle = normal_angle
	grounded = true
	jumping = false


func _check_walls() -> void:
	pushing = false
	var moving := ground_speed if grounded else velocity.x
	var angle := ground_angle if grounded else 0.0
	for side in [-1.0, 1.0]:
		var hit := _sensors.wall_hit(side, angle)
		if hit.is_empty():
			continue
		var overlap: float = push_radius - float(hit["distance"])
		if overlap <= 0.0:
			continue
		position -= Vector2.RIGHT.rotated(angle) * side * overlap
		if signf(moving) == side:
			if grounded:
				ground_speed = 0.0
				var axis := _input_axis()
				pushing = axis != 0.0 and signf(axis) == side
			else:
				velocity.x = 0.0


func _check_ceiling_grounded() -> void:
	var hit := _sensors.ceiling_hit(ground_angle)
	if hit.is_empty():
		return
	var distance: float = hit["distance"]
	if distance < 0.0:
		# pushed into a low ceiling: shove back down along the ground normal
		position += Vector2.DOWN.rotated(ground_angle) * -distance


func _check_ceiling_air() -> void:
	if velocity.y >= 0.0:
		return
	var hit := _sensors.ceiling_hit(0.0)
	if hit.is_empty():
		return
	var distance: float = hit["distance"]
	if distance > 0.0:
		return
	position += Vector2.DOWN * -distance
	var angle := wrapf(_angle_from_normal(hit["normal"]), -PI, PI)
	# steep enough ceilings can be run along, otherwise the player bonks
	if absf(angle) > deg_to_rad(135.0) and absf(velocity.y) > absf(velocity.x):
		grounded = true
		jumping = false
		ground_angle = angle
		ground_speed = velocity.y * signf(sin(angle))
	else:
		velocity.y = 0.0


func _angle_from_normal(normal: Vector2) -> float:
	# 0 on flat ground; positive as the surface descends to the right
	return normal.angle() + PI * 0.5


# --------------------------------------------------------------------------- #
# size / state changes
# --------------------------------------------------------------------------- #
func _set_rolling(value: bool) -> void:
	if rolling == value:
		return
	rolling = value
	_set_size(value, grounded)
	if value:
		Sfx.play("spindash_charge", 1.4)


func _set_size(ball: bool, compensate: bool) -> void:
	var new_height: float = stats.roll_height_radius if ball else stats.height_radius
	var new_width: float = stats.roll_width_radius if ball else stats.width_radius
	if compensate and not is_equal_approx(new_height, height_radius):
		# keep the feet planted when the hitbox grows or shrinks
		position += Vector2.DOWN.rotated(ground_angle) * (height_radius - new_height)
	height_radius = new_height
	width_radius = new_width
	_update_hitbox()


func set_path_layer(layer: int) -> void:
	path_layer = layer


func terrain_mask() -> int:
	var terrain: int = Game.COLLISION_LAYERS.terrain_a if path_layer == 0 \
		else Game.COLLISION_LAYERS.terrain_b
	return terrain | Game.COLLISION_LAYERS.solid_object


# --------------------------------------------------------------------------- #
# interactions used by objects
# --------------------------------------------------------------------------- #
## Launch straight out of a spring; `direction` is a unit vector.
func launch(direction: Vector2, power: float) -> void:
	grounded = false
	jumping = false
	state = State.NORMAL
	velocity = direction * power
	if absf(direction.x) > 0.01:
		ground_speed = velocity.x
		facing = int(signf(direction.x))
	if direction.y < 0.0:
		_animation = "spring"
		_sprite.animation = "spring"
	control_lock = 0
	_set_size(false, false)
	rolling = false
	_end_air_move()


## Bounce off a destroyed badnik or a monitor.
func bounce() -> void:
	if Input.is_action_pressed("jump"):
		velocity.y = -stats.jump_force * 0.85
	else:
		velocity.y = -absf(velocity.y) * 0.6 - 1.5
	grounded = false


func is_attacking() -> bool:
	if air_move == AirMove.FLY:
		return false  # flying is travel, not an attack
	if air_move == AirMove.DASH or air_move == AirMove.HAMMER:
		return true
	if air_move == AirMove.GLIDE:
		return true   # a glide connects, as it classically does
	return rolling or jumping or state == State.SPINDASH


func is_invulnerable() -> bool:
	return invuln > 0 or invincible > 0 or state == State.DEAD


## True while the shield power-up is active: damage is ignored and badniks die
## on contact even when the player is not attacking.
func is_invincible() -> bool:
	return invincible > 0


func give_speed_shoes() -> void:
	shoes = POWERUP_FRAMES
	Sfx.play("extra_life", 1.4)


func give_invincibility() -> void:
	invincible = POWERUP_FRAMES
	Sfx.play("checkpoint", 1.2)


func take_damage(from_x: float) -> void:
	if is_invulnerable() or state == State.DEAD or state == State.GOAL:
		return
	if Game.rings > 0:
		_scatter_rings()
		_end_air_move()
		state = State.HURT
		invuln = INVULN_FRAMES
		grounded = false
		jumping = false
		rolling = false
		_set_size(false, false)
		var away := -1.0 if from_x > position.x else 1.0
		velocity = Vector2(HURT_KNOCKBACK.x * away, HURT_KNOCKBACK.y)
		ground_speed = 0.0
		Sfx.play("hurt")
	else:
		kill()


## A hit or a spring cancels any special move, so it stops counting as an attack.
func _end_air_move() -> void:
	air_move = AirMove.NONE
	air_move_timer = 0
	refresh_hitbox()


func kill() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	grounded = false
	rolling = false
	velocity = Vector2(0.0, -DEATH_RISE)
	ground_speed = 0.0
	_death_timer = 0.0
	# deferred: kill() can be reached from a physics callback
	_hitbox.set_deferred("collision_layer", 0)
	Sfx.fade_music(0.2)
	Sfx.play("death")


func _step_dead(dt: float, delta: float) -> void:
	velocity.y += stats.gravity * dt
	position += velocity * dt
	_death_timer += delta
	if _death_timer > 1.4:
		died.emit()
		set_physics_process(false)


func finish_act() -> void:
	if state == State.GOAL:
		return
	state = State.GOAL
	control_enabled = false
	reached_goal.emit()


func _scatter_rings() -> void:
	var count := mini(Game.rings, 32)
	# Damage arrives from an Area2D callback. Constructing collision shapes in
	# that callback makes PhysicsServer reject them while it is flushing queries,
	# so create the lost rings once the callback has unwound.
	call_deferred("_spawn_scattered_rings", count, position)
	Game.rings = 0
	Game.rings_changed.emit(0)


func _spawn_scattered_rings(count: int, where: Vector2) -> void:
	var scene := load("res://scripts/objects/lost_ring.gd") as GDScript
	var angle := 101.25
	var flip := false
	var speed := 4.0
	for i in count:
		var ring: Node2D = scene.new()
		ring.position = where
		var direction := Vector2(cos(deg_to_rad(angle)), -sin(deg_to_rad(angle)))
		if flip:
			direction.x *= -1.0
			angle += 22.5
		flip = not flip
		if i == 16:
			speed = 2.0
			angle = 101.25
		ring.set("velocity", direction * speed)
		get_parent().add_child(ring)


# --------------------------------------------------------------------------- #
# presentation
# --------------------------------------------------------------------------- #
func _update_look_timer() -> void:
	if not control_enabled or not grounded or absf(ground_speed) > 0.0:
		look_timer = 0
		return
	if Input.is_action_pressed("look_up") or Input.is_action_pressed("crouch"):
		look_timer += 1
	else:
		look_timer = 0


func _animate(delta: float) -> void:
	if camera_lag > 0:
		camera_lag -= 1

	var speed := absf(ground_speed)
	var next := "idle"
	var rate := 1.0

	match state:
		State.DEAD:
			next = "dead"
		State.HURT:
			next = "hurt"
		State.CLIMB:
			next = "climb"
			var climbing := Input.is_action_pressed("look_up") \
				or Input.is_action_pressed("crouch")
			rate = 1.6 if climbing else 0.0
		State.SPINDASH:
			next = "roll"
			rate = 2.0 + spindash_charge * 0.35
		_:
			if air_move == AirMove.FLY:
				next = "fly"
				rate = 3.0
			elif air_move == AirMove.GLIDE:
				next = "glide"
				rate = 1.0
			elif air_move == AirMove.HAMMER:
				next = "hammer"
				rate = 2.4
			elif air_move == AirMove.DASH:
				next = "roll"
				rate = 4.0
			elif rolling or jumping:
				next = "roll"
				# SPG: roll animation speed is max(0, 4 - |gsp|) frames per frame
				rate = clampf(speed / 4.0 + 0.6, 0.8, 4.0)
			elif not grounded:
				next = _animation if _animation == "spring" else "walk"
				rate = clampf(speed / 4.0, 0.6, 3.0)
			elif pushing:
				next = "push"
				rate = 1.0
			elif speed > 0.0:
				var run := speed >= 6.0
				next = "run" if run else "walk"
				# SPG: frame duration is max(0, 8 - |gsp|) frames
				rate = clampf(speed / (8.0 - minf(speed, 7.0)) * 1.4, 0.6, 4.0)
			elif Input.is_action_pressed("look_up") and control_enabled:
				next = "lookup"
			elif Input.is_action_pressed("crouch") and control_enabled:
				next = "crouch"
			else:
				next = "idle"

	# skidding overrides the run cycle while braking hard
	if grounded and not rolling and state == State.NORMAL:
		var axis := _input_axis()
		if axis != 0.0 and signf(axis) != signf(ground_speed) and speed > 4.0:
			next = "skid"
			Sfx.play_once("skid")

	if next != _animation:
		_animation = next
		_sprite.animation = next
		_sprite.frame = 0
	_sprite.speed_scale = rate
	if not _sprite.is_playing():
		_sprite.play()

	_sprite.flip_h = facing < 0
	_sprite.visible = invuln == 0 or state == State.DEAD \
		or int(Time.get_ticks_msec() / 66) % 2 == 0
	# shield power-up: pulse rather than draw an orbiting star field
	if invincible > 0:
		var pulse := int(Time.get_ticks_msec() / 100) % 2 == 0
		_sprite.modulate = Color(0.75, 0.95, 1.5) if pulse else Color(1.4, 1.4, 1.6)
	elif shoes > 0:
		_sprite.modulate = Color(1.15, 1.05, 0.85)
	else:
		_sprite.modulate = Color.WHITE

	# smoothly follow the terrain angle; upright again once airborne
	var target := ground_angle if grounded and not rolling else 0.0
	if grounded and rolling:
		target = 0.0
	_sprite.rotation = lerp_angle(_sprite.rotation, target, 1.0 - pow(0.0001, delta))

	_update_dust()
	if Game.debug_draw:
		queue_redraw()


func _update_dust() -> void:
	var show := state == State.SPINDASH or (rolling and grounded and absf(ground_speed) > 6.0)
	_dust.visible = show
	if show:
		_dust.position = Vector2(-facing * 12.0, height_radius - 6.0)
		_dust.flip_h = facing < 0
		if not _dust.is_playing():
			_dust.play()


func _draw() -> void:
	if not Game.debug_draw:
		return
	var down := Vector2.DOWN.rotated(ground_angle)
	var right := Vector2.RIGHT.rotated(ground_angle)
	for side: float in [-1.0, 1.0]:
		var origin: Vector2 = right * (side * width_radius)
		draw_line(origin, origin + down * (height_radius + 16.0), Color.LIME, 1.0)
		draw_line(origin, origin - down * (height_radius + 16.0), Color.CYAN, 1.0)
	for side in [-1.0, 1.0]:
		draw_line(Vector2.ZERO, right * side * push_radius, Color.MAGENTA, 1.0)
	draw_line(Vector2.ZERO, velocity * 4.0, Color.YELLOW, 1.0)
