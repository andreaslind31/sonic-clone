extends StaticBody2D
class_name Spikes
## Spike strip. Solid so the player can stand on the flat side, and the spiked
## face hurts on contact regardless of how fast the player is going.

var facing_up := true


static func create(where: Vector2, up := true) -> Spikes:
	var spikes := Spikes.new()
	spikes.position = where
	spikes.facing_up = up
	spikes.collision_layer = Game.COLLISION_LAYERS.solid_object
	spikes.collision_mask = 0
	spikes._build()
	return spikes


func _build() -> void:
	var sprite := Art.still("res://assets/sprites/spikes.png", 32, 16)
	if not facing_up:
		sprite.flip_v = true
	add_child(sprite)

	var body_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(32, 14)
	body_shape.shape = rect
	add_child(body_shape)

	var hurt := Area2D.new()
	hurt.collision_layer = Game.COLLISION_LAYERS.object
	hurt.collision_mask = Game.COLLISION_LAYERS.player_hitbox
	var hurt_shape := CollisionShape2D.new()
	var hurt_rect := RectangleShape2D.new()
	hurt_rect.size = Vector2(30, 10)
	hurt_shape.shape = hurt_rect
	# only the pointed face is dangerous
	hurt_shape.position = Vector2(0, -6 if facing_up else 6)
	hurt.add_child(hurt_shape)
	hurt.area_entered.connect(_on_area_entered)
	add_child(hurt)


func _on_area_entered(area: Area2D) -> void:
	var player := area.get_parent() as Player
	if player == null or player.is_invincible():
		return
	# spikes throw the player back the way they came
	player.take_damage(player.global_position.x + player.facing * 8.0)
