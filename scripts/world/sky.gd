extends ParallaxBackground
class_name SkyBackdrop
## Parallax backdrop: sky gradient, drifting clouds and two hill bands.
##
## The cloud and hill art comes from Kenney's CC0 platformer pack, box-filtered
## down to pixel scale by tools/gen_art.py; the gradient and hill silhouettes are
## generated from the same sampled palette.

const CLOUD_DRIFT := 6.0  ## pixels per second

var _clouds: ParallaxLayer


static func create(horizon_y: float) -> SkyBackdrop:
	var sky := SkyBackdrop.new()
	sky._build(horizon_y)
	return sky


func _build(horizon_y: float) -> void:
	# a negative CanvasLayer keeps the whole backdrop behind the world canvas
	layer = -10
	_add_layer("res://assets/bg/sky.png", Vector2(0.02, 0.04), horizon_y - 232.0, -60)
	_clouds = _add_layer("res://assets/bg/clouds.png", Vector2(0.08, 0.1),
		horizon_y - 214.0, -55)
	_add_layer("res://assets/bg/hills_far.png", Vector2(0.24, 0.12), horizon_y - 196.0, -50)
	_add_layer("res://assets/bg/hills_near.png", Vector2(0.45, 0.2), horizon_y - 168.0, -45)


func _add_layer(path: String, scale_factor: Vector2, offset_y: float, z: int) -> ParallaxLayer:
	var texture: Texture2D = load(path)
	var layer := ParallaxLayer.new()
	layer.motion_scale = scale_factor
	layer.motion_mirroring = Vector2(texture.get_width(), 0)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = Vector2(0, offset_y)
	sprite.z_index = z
	layer.add_child(sprite)
	add_child(layer)
	return layer


func _process(delta: float) -> void:
	if _clouds:
		_clouds.motion_offset.x -= CLOUD_DRIFT * delta
