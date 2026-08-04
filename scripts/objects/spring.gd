extends Area2D
class_name Spring
## Red spring. Vertical springs launch at 10 px/frame, diagonals at 8 on each
## axis, matching the Genesis values.

const POWER_UP := 10.0
const POWER_DIAGONAL := 8.0 * sqrt(2.0)

var direction := Vector2.UP
var power := POWER_UP

var _sprite: AnimatedSprite2D
var _flash := 0.0


static func create(where: Vector2, dir := Vector2.UP) -> Spring:
	var spring := Spring.new()
	spring.position = where
	spring.direction = dir.normalized()
	spring.power = POWER_UP if absf(dir.x) < 0.01 else POWER_DIAGONAL
	spring.collision_layer = Game.COLLISION_LAYERS.object
	spring.collision_mask = Game.COLLISION_LAYERS.player_hitbox
	spring._build()
	return spring


func _build() -> void:
	_sprite = Art.animated("res://assets/sprites/spring.png", 32, 32, 2, 18.0, false)
	_sprite.frame = 0
	_sprite.stop()
	_sprite.offset = Vector2(0, -4)
	_sprite.rotation = direction.angle() + PI * 0.5
	add_child(_sprite)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(30, 16)
	shape.shape = rect
	shape.position = Vector2(0, -4).rotated(_sprite.rotation)
	shape.rotation = _sprite.rotation
	add_child(shape)
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	var player := area.get_parent() as Player
	if player == null:
		return
	player.launch(direction, power)
	_sprite.frame = 1
	_flash = 0.16
	Sfx.play("spring")


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_sprite.frame = 0
