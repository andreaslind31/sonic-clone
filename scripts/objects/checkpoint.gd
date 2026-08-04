extends Area2D
class_name Checkpoint
## Lamppost. Stores a respawn point and spins its lamp once triggered.

const SCORE := 10

var _sprite: Sprite2D
var _lit := false


static func create(where: Vector2) -> Checkpoint:
	var post := Checkpoint.new()
	post.position = where
	post.collision_layer = Game.COLLISION_LAYERS.object
	post.collision_mask = Game.COLLISION_LAYERS.player_hitbox
	post._build()
	return post


func _build() -> void:
	_sprite = Art.still("res://assets/sprites/checkpoint.png", 24, 48)
	_sprite.position = Vector2(0, -24)
	add_child(_sprite)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 48)
	shape.shape = rect
	shape.position = Vector2(0, -24)
	add_child(shape)
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	if _lit or not (area.get_parent() is Player):
		return
	_lit = true
	_sprite.region_rect = Rect2(24, 0, 24, 48)
	Game.set_checkpoint(global_position + Vector2(0, -20))
	Game.add_score(SCORE)
	Sfx.play("checkpoint")
