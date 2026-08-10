extends Node2D
class_name Badnik
## Enemies. Two kinds share this script because their only real differences are
## how they move and whether they shoot:
##
##   MOTOBUG - drives back and forth along the ground, turning at the patrol ends
##   BUZZER  - hovers, and lobs a projectile when the player is below and ahead
##
## Rolling, jumping or spindashing into one destroys it and bounces the player;
## touching one any other way costs rings.

enum Kind { MOTOBUG, BUZZER }

const SCORE := 100
const MOTOBUG_SPEED := 1.1
const BUZZER_SPEED := 0.9
const SHOT_INTERVAL := 2.4
const SHOT_RANGE := Vector2(140.0, 190.0)

var kind: Kind = Kind.MOTOBUG
var patrol := 96.0
var facing := -1

var _origin := Vector2.ZERO
var _sprite: AnimatedSprite2D
var _hitbox: Area2D
var _shot_timer := 0.0
var _dead := false


static func create(where: Vector2, which: Kind, patrol_range := 96.0) -> Badnik:
	var badnik := Badnik.new()
	badnik.position = where
	badnik.kind = which
	badnik.patrol = patrol_range
	badnik._build()
	return badnik


func _build() -> void:
	add_to_group("badnik")   # the air dash homes on this group
	_origin = position
	_shot_timer = SHOT_INTERVAL * randf()
	var size := Vector2(32, 24)
	if kind == Kind.MOTOBUG:
		_sprite = Art.animated("res://assets/sprites/motobug.png", 32, 24, 2, 8.0)
	else:
		_sprite = Art.animated("res://assets/sprites/buzzer.png", 40, 24, 2, 14.0)
		size = Vector2(36, 20)
	add_child(_sprite)

	_hitbox = Area2D.new()
	_hitbox.collision_layer = Game.COLLISION_LAYERS.object
	_hitbox.collision_mask = Game.COLLISION_LAYERS.player_hitbox
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	_hitbox.add_child(shape)
	_hitbox.area_entered.connect(_on_area_entered)
	add_child(_hitbox)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	var dt := delta * 60.0
	match kind:
		Kind.MOTOBUG:
			_move_motobug(dt)
		Kind.BUZZER:
			_move_buzzer(dt, delta)
	_sprite.flip_h = facing > 0


func _move_motobug(dt: float) -> void:
	position.x += MOTOBUG_SPEED * facing * dt
	if absf(position.x - _origin.x) > patrol:
		facing *= -1
		position.x = _origin.x + patrol * signf(position.x - _origin.x)
	# ride the terrain so patrols work on slopes
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position + Vector2(0, -24), global_position + Vector2(0, 40)
	)
	query.collision_mask = Game.COLLISION_LAYERS.terrain_a | Game.COLLISION_LAYERS.terrain_b
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		global_position.y = hit["position"].y - 12.0


func _move_buzzer(dt: float, delta: float) -> void:
	position.x += BUZZER_SPEED * facing * dt
	if absf(position.x - _origin.x) > patrol:
		facing *= -1
		position.x = _origin.x + patrol * signf(position.x - _origin.x)
	position.y = _origin.y + sin(Time.get_ticks_msec() / 700.0) * 4.0

	_shot_timer -= delta
	if _shot_timer > 0.0:
		return
	var player := _find_player()
	if player == null:
		return
	var offset := player.global_position - global_position
	if absf(offset.x) > SHOT_RANGE.x or offset.y < 0.0 or offset.y > SHOT_RANGE.y:
		return
	if signf(offset.x) != signf(facing) and absf(offset.x) > 24.0:
		return
	_shot_timer = SHOT_INTERVAL
	var shot := Projectile.create(global_position + Vector2(facing * 14.0, 8.0),
		Vector2(facing * 1.2, 2.4))
	get_parent().add_child(shot)


func _find_player() -> Player:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] as Player if players.size() > 0 else null


func _on_area_entered(area: Area2D) -> void:
	var player := area.get_parent() as Player
	if player == null or _dead:
		return
	if player.is_attacking() or player.is_invincible():
		_destroy(player)
	else:
		player.take_damage(global_position.x)


func _destroy(player: Player) -> void:
	_dead = true
	if player.is_attacking():
		player.bounce()
	Game.add_score(SCORE)
	Sfx.play("pop")
	Art.effect(get_parent(), "res://assets/sprites/explosion.png", 32, 32, 4, global_position)
	queue_free()
