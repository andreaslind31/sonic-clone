extends StaticBody2D
class_name Capsule
## The prize capsule that appears once the boss is beaten. Solid enough to stand
## on; landing on the switch plate springs it open and clears the act.

signal opened()

var _sprite: Sprite2D
var _switch: Area2D
var _open := false


static func create(where: Vector2) -> Capsule:
	var capsule := Capsule.new()
	capsule.position = where
	capsule.collision_layer = Game.COLLISION_LAYERS.solid_object
	capsule.collision_mask = 0
	capsule._build()
	return capsule


func _build() -> void:
	_sprite = Art.still("res://assets/sprites/capsule.png", 64, 48)
	_sprite.position = Vector2(0, -24)
	add_child(_sprite)

	var body := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(50, 24)
	body.shape = rect
	body.position = Vector2(0, -12)
	add_child(body)

	_switch = Area2D.new()
	_switch.collision_layer = Game.COLLISION_LAYERS.object
	_switch.collision_mask = Game.COLLISION_LAYERS.player_hitbox
	var switch_shape := CollisionShape2D.new()
	var switch_rect := RectangleShape2D.new()
	switch_rect.size = Vector2(26, 14)
	switch_shape.shape = switch_rect
	switch_shape.position = Vector2(0, -38)
	_switch.add_child(switch_shape)
	_switch.area_entered.connect(_on_switch_hit)
	add_child(_switch)


func _on_switch_hit(area: Area2D) -> void:
	var player := area.get_parent() as Player
	if player == null or _open:
		return
	_open = true
	_sprite.region_rect = Rect2(64, 0, 64, 48)
	_switch.set_deferred("collision_layer", 0)
	Sfx.play("break", 0.9)
	for i in 6:
		Art.effect(get_parent(), "res://assets/sprites/ring_sparkle.png", 16, 16, 4,
			global_position + Vector2(randf_range(-24.0, 24.0), randf_range(-40.0, -8.0)))
	opened.emit()
	player.finish_act()
