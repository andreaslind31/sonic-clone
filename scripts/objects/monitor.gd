extends StaticBody2D
class_name Monitor
## Item box. Solid enough to stand on, breaks when hit while rolling, jumping or
## spindashing, then hands out its item.

enum Item { RINGS, SHOES, SHIELD, LIFE }

const ITEM_FRAME := {Item.RINGS: 0, Item.SHOES: 1, Item.SHIELD: 2, Item.LIFE: 3}
const BROKEN_FRAME := 4
const SCORE := 10

var item: Item = Item.RINGS

var _sprite: Sprite2D
var _detector: Area2D
var _broken := false


static func create(where: Vector2, which: Item) -> Monitor:
	var monitor := Monitor.new()
	monitor.position = where
	monitor.item = which
	monitor.collision_layer = Game.COLLISION_LAYERS.solid_object
	monitor.collision_mask = 0
	monitor._build()
	return monitor


func _build() -> void:
	_sprite = Art.still("res://assets/sprites/monitor.png", 32, 32, ITEM_FRAME[item])
	add_child(_sprite)

	var body_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(30, 30)
	body_shape.shape = rect
	add_child(body_shape)

	_detector = Area2D.new()
	_detector.collision_layer = Game.COLLISION_LAYERS.object
	_detector.collision_mask = Game.COLLISION_LAYERS.player_hitbox
	var detect_shape := CollisionShape2D.new()
	var detect_rect := RectangleShape2D.new()
	detect_rect.size = Vector2(34, 34)
	detect_shape.shape = detect_rect
	_detector.add_child(detect_shape)
	_detector.area_entered.connect(_on_area_entered)
	add_child(_detector)


func _on_area_entered(area: Area2D) -> void:
	var player := area.get_parent() as Player
	if player == null or _broken or not player.is_attacking():
		return
	_break(player)


func _break(player: Player) -> void:
	_broken = true
	_sprite.region_rect = Rect2(BROKEN_FRAME * 32, 0, 32, 32)
	# deferred: this runs inside a physics callback, where layers are locked
	set_deferred("collision_layer", 0)
	_detector.set_deferred("collision_layer", 0)
	player.bounce()
	Game.add_score(SCORE)
	Sfx.play("break")
	Art.effect(get_parent(), "res://assets/sprites/explosion.png", 32, 32, 4, global_position)
	_grant(player)


func _grant(player: Player) -> void:
	match item:
		Item.RINGS:
			Game.add_rings(10)
		Item.SHOES:
			player.give_speed_shoes()
		Item.SHIELD:
			player.give_invincibility()
		Item.LIFE:
			Game.add_life()
