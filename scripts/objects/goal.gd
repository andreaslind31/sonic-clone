extends Area2D
class_name Goal
## End-of-act sign. Spins when hit, then hands control to the level's results
## sequence via Player.finish_act().

var _sprite: AnimatedSprite2D
var _spins := 0
var _triggered := false


static func create(where: Vector2) -> Goal:
	var goal := Goal.new()
	goal.position = where
	goal.collision_layer = Game.COLLISION_LAYERS.object
	goal.collision_mask = Game.COLLISION_LAYERS.player_hitbox
	goal._build()
	return goal


func _build() -> void:
	_sprite = Art.animated("res://assets/sprites/goal.png", 48, 64, 4, 14.0)
	_sprite.position = Vector2(0, -32)
	_sprite.stop()
	_sprite.frame = 0
	add_child(_sprite)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, 64)
	shape.shape = rect
	shape.position = Vector2(0, -32)
	add_child(shape)
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	var player := area.get_parent() as Player
	if player == null or _triggered:
		return
	_triggered = true
	_sprite.play()
	_sprite.frame_changed.connect(_count_frames)
	player.finish_act()


func _count_frames() -> void:
	if _sprite.frame == 0:
		_spins += 1
	if _spins >= 4:
		_sprite.stop()
		_sprite.frame = 0
