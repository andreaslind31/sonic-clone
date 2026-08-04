extends Area2D
class_name Ring
## Collectable ring. Worth one ring and ten points.

const SCORE := 10


static func create(where: Vector2) -> Ring:
	var ring := Ring.new()
	ring.position = where
	ring.collision_layer = Game.COLLISION_LAYERS.object
	ring.collision_mask = Game.COLLISION_LAYERS.player_hitbox
	ring.add_child(Art.animated("res://assets/sprites/ring.png", 16, 16, 4, 14.0))
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8.0
	shape.shape = circle
	ring.add_child(shape)
	ring.area_entered.connect(ring._on_area_entered)
	return ring


func _on_area_entered(area: Area2D) -> void:
	if area.get_parent() is Player:
		collect()


func collect() -> void:
	Game.add_rings(1)
	Game.add_score(SCORE)
	Sfx.play("ring", randf_range(0.96, 1.06))
	Art.effect(get_parent(), "res://assets/sprites/ring_sparkle.png", 16, 16, 4,
		global_position)
	queue_free()
