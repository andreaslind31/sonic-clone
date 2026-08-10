extends StaticBody2D
class_name Block
## A rectangular chunk of solid ground: shelves, ledges, roofed corridors, walls.
##
## Terrain generated from a surface polyline can only ever be one floor per x,
## which rules out overhangs, ceilings and upper routes. Blocks are the escape
## hatch: all four faces are solid, so the sensors get a floor on top, a ceiling
## underneath, and walls on the sides for the glide-and-climb ability to grab.
##
## Collision is a segment chain like the rest of the world, so a sensor hitting a
## block reports the same kind of normal as one hitting a hill.

const GRASS_DEPTH := 14.0  ## how much of the top edge uses the grassy strip


static func create(top_left: Vector2, size: Vector2, layers: int) -> Block:
	var block := Block.new()
	block.collision_layer = layers
	block.collision_mask = 0
	block.position = top_left
	block._build(size)
	return block


func _build(size: Vector2) -> void:
	var shape := CollisionPolygon2D.new()
	shape.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
	shape.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(size.x, 0.0),
		Vector2(size.x, size.y),
		Vector2(0.0, size.y),
	])
	add_child(shape)

	# body first, then the grass lip on top, so the two never fight over pixels
	var body_top := minf(GRASS_DEPTH, size.y)
	if size.y > body_top:
		var body := Polygon2D.new()
		body.polygon = PackedVector2Array([
			Vector2(0.0, body_top),
			Vector2(size.x, body_top),
			Vector2(size.x, size.y),
			Vector2(0.0, size.y),
		])
		body.uv = body.polygon
		body.texture = load("res://assets/tiles/dirt_fill.png")
		body.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		body.z_index = -2
		add_child(body)

	var lip := Polygon2D.new()
	lip.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(size.x, 0.0),
		Vector2(size.x, body_top),
		Vector2(0.0, body_top),
	])
	# sample the top of the ground strip, where the grass edge lives
	lip.uv = PackedVector2Array([
		Vector2.ZERO,
		Vector2(size.x, 0.0),
		Vector2(size.x, body_top),
		Vector2(0.0, body_top),
	])
	lip.texture = load("res://assets/tiles/ground_strip.png")
	lip.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	lip.z_index = -1
	add_child(lip)
