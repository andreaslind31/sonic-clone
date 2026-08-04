extends StaticBody2D
class_name MovingPlatform
## Platform that slides along an axis. A rider standing on it is carried, since
## the player's own floor snapping only handles vertical movement.

var travel := Vector2(0, -64)
var period := 3.0
var phase := 0.0

var _origin := Vector2.ZERO
var _rider_zone: Area2D
var _riders: Array[Player] = []
var _time := 0.0


static func create(where: Vector2, offset: Vector2, seconds := 3.0, start_phase := 0.0) -> MovingPlatform:
	var platform := MovingPlatform.new()
	platform.position = where
	platform.travel = offset
	platform.period = seconds
	platform.phase = start_phase
	platform.collision_layer = Game.COLLISION_LAYERS.solid_object
	platform.collision_mask = 0
	platform._build()
	return platform


func _build() -> void:
	_origin = position
	_time = phase * period
	var sprite := Art.still("res://assets/sprites/platform.png", 64, 20)
	sprite.centered = false
	sprite.position = Vector2(-32, -10)
	add_child(sprite)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(64, 18)
	shape.shape = rect
	add_child(shape)

	_rider_zone = Area2D.new()
	_rider_zone.collision_layer = 0
	_rider_zone.collision_mask = Game.COLLISION_LAYERS.player_hitbox
	var zone_shape := CollisionShape2D.new()
	var zone_rect := RectangleShape2D.new()
	zone_rect.size = Vector2(66, 12)
	zone_shape.shape = zone_rect
	zone_shape.position = Vector2(0, -16)
	_rider_zone.add_child(zone_shape)
	_rider_zone.area_entered.connect(_on_rider_entered)
	_rider_zone.area_exited.connect(_on_rider_exited)
	add_child(_rider_zone)


func _physics_process(delta: float) -> void:
	_time += delta
	var t: float = (sin(_time / period * TAU) + 1.0) * 0.5
	var next := _origin + travel * t
	var shift := next - position
	position = next
	for rider in _riders:
		if rider != null and rider.grounded:
			rider.position += shift


func _on_rider_entered(area: Area2D) -> void:
	var player := area.get_parent() as Player
	if player != null and not _riders.has(player):
		_riders.append(player)


func _on_rider_exited(area: Area2D) -> void:
	var player := area.get_parent() as Player
	if player != null:
		_riders.erase(player)
