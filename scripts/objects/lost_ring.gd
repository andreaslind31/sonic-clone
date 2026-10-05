extends Area2D
class_name LostRing
## A ring scattered by taking a hit: falls, bounces, and can be picked back up
## after a short grace period. Uses the same scatter pattern as the Genesis
## games (alternating left/right in 22.5 degree steps, two speed rings).

const GRAVITY := 0.09375
const BOUNCE := 0.75
const GRACE_FRAMES := 24
const LIFETIME := 256

var velocity := Vector2.ZERO

var _age := 0
var _shape: CollisionShape2D


func _init() -> void:
	collision_layer = Game.COLLISION_LAYERS.object
	# Keep pickup detection off during the grace period. Using the area's mask
	# avoids toggling a CollisionShape2D while this ring is being spawned from a
	# physics callback.
	collision_mask = 0
	monitoring = true
	add_child(Art.animated("res://assets/sprites/ring.png", 16, 16, 4, 14.0))
	_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8.0
	_shape.shape = circle
	add_child(_shape)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	var dt := delta * 60.0
	_age += 1
	if _age == GRACE_FRAMES:
		set_deferred("collision_mask", Game.COLLISION_LAYERS.player_hitbox)
	if _age > LIFETIME:
		queue_free()
		return
	if _age > LIFETIME - 60 and _age % 4 < 2:
		modulate.a = 0.35
	else:
		modulate.a = 1.0

	velocity.y += GRAVITY * dt
	var motion := velocity * dt
	position.x += motion.x

	if velocity.y <= 0.0:
		position.y += motion.y
		return

	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position, global_position + Vector2(0.0, motion.y + 8.0)
	)
	query.collision_mask = Game.COLLISION_LAYERS.terrain_a \
		| Game.COLLISION_LAYERS.terrain_b | Game.COLLISION_LAYERS.solid_object
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		position.y += motion.y
		return
	global_position.y = hit["position"].y - 8.0
	velocity.y = -velocity.y * BOUNCE
	if absf(velocity.y) < 0.6:
		velocity.y = 0.0


func _on_area_entered(area: Area2D) -> void:
	if area.get_parent() is Player:
		Game.add_rings(1)
		Sfx.play("ring", randf_range(0.96, 1.06))
		queue_free()
