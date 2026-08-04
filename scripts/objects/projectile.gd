extends Area2D
class_name Projectile
## Buzzer shot: falls in a straight line, hurts on contact, pops on terrain.

const LIFETIME := 4.0

var velocity := Vector2.ZERO

var _age := 0.0


static func create(where: Vector2, motion: Vector2) -> Projectile:
	var shot := Projectile.new()
	shot.position = where
	shot.velocity = motion
	shot.collision_layer = Game.COLLISION_LAYERS.object
	shot.collision_mask = Game.COLLISION_LAYERS.player_hitbox
	shot._build()
	return shot


func _build() -> void:
	add_child(Art.animated("res://assets/sprites/shot.png", 8, 12, 2, 10.0))
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(8, 12)
	shape.shape = rect
	add_child(shape)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	var dt := delta * 60.0
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	var motion := velocity * dt
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + motion)
	query.collision_mask = Game.COLLISION_LAYERS.terrain_a | Game.COLLISION_LAYERS.terrain_b
	if not space.intersect_ray(query).is_empty():
		Art.effect(get_parent(), "res://assets/sprites/dust.png", 24, 24, 4, global_position)
		queue_free()
		return
	position += motion


func _on_area_entered(area: Area2D) -> void:
	var player := area.get_parent() as Player
	if player == null:
		return
	if player.is_invincible():
		queue_free()
		return
	player.take_damage(global_position.x)
	queue_free()
