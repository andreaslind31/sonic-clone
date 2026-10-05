extends Area2D
class_name Checkpoint
## Lamppost. Stores a respawn point and spins its lamp once triggered.

const SCORE := 10

var _sprite: Sprite2D
var _lit := false


static func create(where: Vector2) -> Checkpoint:
	var post := Checkpoint.new()
	post.position = where
	# A restarted act rebuilds its objects from scratch. Restore the active
	# checkpoint instead of showing it as unlit and awarding its score again as
	# soon as the respawned player overlaps it.
	post._lit = Game.checkpoint_set and is_equal_approx(Game.checkpoint.x, where.x)
	post.collision_layer = Game.COLLISION_LAYERS.object
	post.collision_mask = Game.COLLISION_LAYERS.player_hitbox
	post._build()
	return post


func _build() -> void:
	_sprite = Art.still("res://assets/sprites/checkpoint.png", 24, 48, 1 if _lit else 0)
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
