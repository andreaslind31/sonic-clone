extends Node2D
class_name Boss
## End-of-zone boss: a hover pod with a swinging wrecking ball.
##
## The fight follows the Genesis pattern. The pod sweeps back and forth over a
## sealed arena and drags a ball on a chain; the pod itself is the only thing that
## can be hurt, and only by an attacking player (rolling, jumping, a dash or a
## hammer swing). Every hit knocks it back, makes it flinch, and speeds up the
## next sweep, so the fight tightens as it goes. Eight hits finish it.
##
## The ball hurts on contact no matter what the player is doing — that is the
## point of it, and it is what stops the fight being a jump-spam contest.

signal activated()
signal defeated()

enum Phase { WAITING, SWEEP, HURT, DYING, DONE }

const MAX_HP := 8
const SWEEP_HALF_WIDTH := 108.0
const SWEEP_PERIOD := 3.4          ## seconds for a full there-and-back sweep
const SPEED_PER_HIT := 0.11        ## each hit shortens the sweep by this fraction
const HOVER_AMPLITUDE := 5.0
const CHAIN_LENGTH := 60.0
const CHAIN_LINKS := 8
const BALL_SWING := deg_to_rad(72.0)
const BALL_PERIOD := 1.6
const HURT_FRAMES := 34
const INVULN_FRAMES := 54
const DEATH_SECONDS := 2.4
const TRIGGER_MARGIN := 40.0       ## how far into the arena wakes the boss
const SCORE := 1000

var phase: Phase = Phase.WAITING
var hp := MAX_HP

var _origin := Vector2.ZERO
var _arena_half := 200.0
var _sprite: Sprite2D
var _ball: Sprite2D
var _links: Array[Sprite2D] = []
var _pod_hitbox: Area2D
var _ball_hitbox: Area2D
var _time := 0.0
var _hurt_timer := 0
var _invuln := 0
var _death_timer := 0.0
var _knockback := Vector2.ZERO


static func create(where: Vector2, arena_half_width := 200.0) -> Boss:
	var boss := Boss.new()
	boss.position = where
	boss._origin = where
	boss._arena_half = arena_half_width
	boss._build()
	return boss


func _build() -> void:
	add_to_group("boss")
	_sprite = Art.still("res://assets/sprites/boss.png", 64, 56, 0)
	add_child(_sprite)

	for i in CHAIN_LINKS:
		var link := Sprite2D.new()
		link.texture = load("res://assets/sprites/chain_link.png")
		link.z_index = -1
		add_child(link)
		_links.append(link)

	_ball = Sprite2D.new()
	_ball.texture = load("res://assets/sprites/wrecking_ball.png")
	add_child(_ball)

	_pod_hitbox = _make_hitbox(Vector2(44, 30), Vector2(0, 6))
	_pod_hitbox.area_entered.connect(_on_pod_touched)
	_ball_hitbox = _make_hitbox(Vector2(20, 20), Vector2.ZERO)
	_ball_hitbox.area_entered.connect(_on_ball_touched)
	_update_rig()


func _make_hitbox(size: Vector2, offset: Vector2) -> Area2D:
	var area := Area2D.new()
	area.collision_layer = Game.COLLISION_LAYERS.object
	area.collision_mask = Game.COLLISION_LAYERS.player_hitbox
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = offset
	area.add_child(shape)
	add_child(area)
	return area


func _physics_process(delta: float) -> void:
	match phase:
		Phase.WAITING:
			_watch_for_player()
		Phase.SWEEP:
			_sweep(delta)
		Phase.HURT:
			_flinch(delta)
		Phase.DYING:
			_die(delta)
		Phase.DONE:
			pass
	if _invuln > 0:
		_invuln -= 1
	_update_rig()


func _watch_for_player() -> void:
	var player := _find_player()
	if player == null:
		return
	if player.global_position.x > _origin.x - _arena_half + TRIGGER_MARGIN:
		phase = Phase.SWEEP
		activated.emit()


func _sweep(delta: float) -> void:
	_time += delta
	var pace := 1.0 + float(MAX_HP - hp) * SPEED_PER_HIT
	var swing := sin(_time / SWEEP_PERIOD * TAU * pace)
	position.x = _origin.x + swing * SWEEP_HALF_WIDTH
	position.y = _origin.y + sin(_time * 2.2) * HOVER_AMPLITUDE
	_sprite.region_rect = Rect2(64 if absf(swing) > 0.7 else 0, 0, 64, 56)


func _flinch(delta: float) -> void:
	_hurt_timer -= 1
	# drift backwards out of the hit, then resume the sweep
	position += _knockback * delta * 60.0
	_knockback = _knockback.lerp(Vector2.ZERO, 0.08)
	position.y = minf(position.y, _origin.y + HOVER_AMPLITUDE)
	_sprite.region_rect = Rect2(128, 0, 64, 56)
	if _hurt_timer <= 0:
		phase = Phase.SWEEP
		# resume from the nearest edge of the sweep rather than snapping back
		_time = SWEEP_PERIOD * 0.25 if position.x < _origin.x else SWEEP_PERIOD * 0.75


func _die(delta: float) -> void:
	_death_timer += delta
	position.y += 24.0 * delta
	_sprite.region_rect = Rect2(128, 0, 64, 56)
	_sprite.visible = int(_death_timer * 12.0) % 2 == 0
	if fposmod(_death_timer, 0.28) < delta:
		Art.effect(get_parent(), "res://assets/sprites/explosion.png", 32, 32, 4,
			global_position + Vector2(randf_range(-26.0, 26.0), randf_range(-16.0, 16.0)))
		Sfx.play("pop", randf_range(0.7, 1.1))
	if _death_timer >= DEATH_SECONDS:
		phase = Phase.DONE
		defeated.emit()
		queue_free()


## Chain and ball follow the pod, so they are placed after it has moved.
func _update_rig() -> void:
	var swing := 0.0
	if phase == Phase.SWEEP or phase == Phase.HURT:
		swing = sin(_time / BALL_PERIOD * TAU) * BALL_SWING
	var direction := Vector2(sin(swing), cos(swing))
	var anchor := Vector2(0, 18)
	for i in _links.size():
		var t := float(i + 1) / float(_links.size() + 1)
		_links[i].position = anchor + direction * (CHAIN_LENGTH * t)
	_ball.position = anchor + direction * CHAIN_LENGTH
	_ball_hitbox.position = _ball.position
	var visible_rig := phase != Phase.DYING and phase != Phase.DONE
	_ball.visible = visible_rig
	for link in _links:
		link.visible = visible_rig
	_ball_hitbox.monitoring = visible_rig


func _on_pod_touched(area: Area2D) -> void:
	var player := area.get_parent() as Player
	if player == null or phase == Phase.DYING or phase == Phase.DONE:
		return
	if player.is_attacking() and _invuln <= 0:
		take_hit(player)
	elif not player.is_invincible():
		player.take_damage(global_position.x)


func _on_ball_touched(area: Area2D) -> void:
	var player := area.get_parent() as Player
	if player == null or phase == Phase.DYING or phase == Phase.DONE:
		return
	# the ball is not a target: attacking into it still hurts
	if not player.is_invincible():
		player.take_damage(_ball.global_position.x)


func take_hit(player: Player) -> void:
	hp -= 1
	_invuln = INVULN_FRAMES
	player.bounce()
	Sfx.play("break", 1.1)
	Art.effect(get_parent(), "res://assets/sprites/explosion.png", 32, 32, 4,
		global_position + Vector2(0, -8))
	if hp <= 0:
		phase = Phase.DYING
		_death_timer = 0.0
		Game.add_score(SCORE)
		Sfx.fade_music(0.4)
		return
	phase = Phase.HURT
	_hurt_timer = HURT_FRAMES
	var away := signf(global_position.x - player.global_position.x)
	if away == 0.0:
		away = 1.0
	_knockback = Vector2(away * 1.6, -0.8)


func _find_player() -> Player:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] as Player if players.size() > 0 else null
