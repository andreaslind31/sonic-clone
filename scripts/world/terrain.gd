extends StaticBody2D
class_name Terrain
## Solid ground built from a left-to-right surface polyline.
##
## Collision uses BUILD_SEGMENTS so the shape is a chain of surface lines rather
## than a filled body: sensors then hit the actual surface from either side and
## report a usable normal, which is what the SPG sensor model expects.
##
## The visuals are generated from the same polyline, so what you see is exactly
## what the sensors collide with: a textured strip that follows the surface, and
## a tiled fill below it.

const STRIP_DEPTH := 48.0
const FILL_BOTTOM := 900.0


static func create(surface: PackedVector2Array, layers: int, tint := Color.WHITE) -> Terrain:
	var terrain := Terrain.new()
	terrain.collision_layer = layers
	terrain.collision_mask = 0
	terrain._build(surface, tint)
	return terrain


func _build(surface: PackedVector2Array, tint: Color) -> void:
	if surface.size() < 2:
		push_error("terrain needs at least two surface points")
		return

	_add_collision(surface)
	_add_fill(surface, tint)
	_add_strip(surface, tint)


func _add_collision(surface: PackedVector2Array) -> void:
	var outline := PackedVector2Array(surface)
	# close the shape below the level so the ends act as walls
	outline.append(Vector2(surface[surface.size() - 1].x, FILL_BOTTOM))
	outline.append(Vector2(surface[0].x, FILL_BOTTOM))
	var shape := CollisionPolygon2D.new()
	shape.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
	shape.polygon = outline
	add_child(shape)


func _add_strip(surface: PackedVector2Array, tint: Color) -> void:
	## One textured quad per surface segment, with UVs advancing along the
	## surface so the grass lip always sits on the ground line.
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var polys: Array[PackedInt32Array] = []
	var travelled := 0.0
	for i in surface.size() - 1:
		var a := surface[i]
		var b := surface[i + 1]
		var length := a.distance_to(b)
		var base := verts.size()
		verts.append(a)
		verts.append(b)
		verts.append(b + Vector2(0.0, STRIP_DEPTH))
		verts.append(a + Vector2(0.0, STRIP_DEPTH))
		uvs.append(Vector2(travelled, 0.0))
		uvs.append(Vector2(travelled + length, 0.0))
		uvs.append(Vector2(travelled + length, STRIP_DEPTH))
		uvs.append(Vector2(travelled, STRIP_DEPTH))
		polys.append(PackedInt32Array([base, base + 1, base + 2, base + 3]))
		travelled += length

	var strip := Polygon2D.new()
	strip.polygon = verts
	strip.uv = uvs
	strip.polygons = polys
	strip.texture = load("res://assets/tiles/ground_strip.png")
	strip.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	strip.color = tint
	strip.z_index = -2
	add_child(strip)


func _add_fill(surface: PackedVector2Array, tint: Color) -> void:
	var verts := PackedVector2Array()
	for point in surface:
		verts.append(point + Vector2(0.0, STRIP_DEPTH - 2.0))
	verts.append(Vector2(surface[surface.size() - 1].x, FILL_BOTTOM))
	verts.append(Vector2(surface[0].x, FILL_BOTTOM))

	var fill := Polygon2D.new()
	fill.polygon = verts
	fill.uv = verts  # world-space UVs so the pattern tiles seamlessly
	fill.texture = load("res://assets/tiles/dirt_fill.png")
	fill.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	fill.color = tint.darkened(0.25)
	fill.z_index = -3
	add_child(fill)
