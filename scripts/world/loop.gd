extends Node2D
class_name Loop
## A full 360 degree loop, assembled from two arcs on opposite path layers.
##
## The circle is tangent to the ground at its lowest point, so a player running
## in at speed transitions onto it without a seam. The right arc is solid on
## layer A and the left arc on layer B, and three switchers arrange the handover:
##
##   * left edge  - always selects A, so a player arriving from the left rides
##                  up the right arc while the left arc is see-through
##   * centre top - by direction: heading left at the apex selects B, so the
##                  descent down the left arc becomes solid
##   * right edge - always selects B, mirroring the entry for a player arriving
##                  from the right
##
## With B still active at the bottom of the descent, the right arc is no longer
## solid, so the player rolls straight out of the loop instead of riding it again.

const ARC_STEPS := 64  ## finer arcs keep the reported surface angle smooth
const OVERLAP := deg_to_rad(10.0)  ## arcs run past the apex/base so there is no gap
const TRACK_THICKNESS := 16.0


static func create(centre_x: float, ground_y: float, radius: float) -> Loop:
	var loop := Loop.new()
	loop.position = Vector2(centre_x, ground_y - radius)
	loop._build(radius)
	return loop


func _build(radius: float) -> void:
	# angles are measured in Godot screen space: +y is down, so PI/2 is the base
	var base := PI * 0.5
	var apex := -PI * 0.5
	var right_arc := _arc(radius, base + OVERLAP, apex - OVERLAP, false)
	var left_arc := _arc(radius, base - OVERLAP, apex + OVERLAP, true)

	_add_arc_body(right_arc, Game.COLLISION_LAYERS.terrain_a)
	_add_arc_body(left_arc, Game.COLLISION_LAYERS.terrain_b)
	_add_track(radius)

	var height := radius * 2.0 + 8.0
	add_child(LayerSwitch.create(Vector2(-radius - 12.0, 0.0), height, LayerSwitch.Mode.ALWAYS_A))
	add_child(LayerSwitch.create(Vector2(radius + 12.0, 0.0), height, LayerSwitch.Mode.ALWAYS_B))
	# only the upper half switches by direction; the lower half must not, or the
	# exit would flip back to A and feed the player into the loop a second time
	add_child(LayerSwitch.create(
		Vector2(0.0, -radius * 0.5), radius, LayerSwitch.Mode.BY_DIRECTION
	))


## Sample a circular arc between two angles.
func _arc(radius: float, from: float, to: float, counter_clockwise: bool) -> PackedVector2Array:
	var points := PackedVector2Array()
	if counter_clockwise and to < from:
		to += TAU
	for i in ARC_STEPS + 1:
		var t := float(i) / float(ARC_STEPS)
		var angle: float = lerpf(from, to, t)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _add_arc_body(points: PackedVector2Array, layer: int) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionPolygon2D.new()
	shape.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
	# an open chain: repeat the points in reverse so the implicit closing edge
	# lands on top of the arc instead of cutting across the loop
	var chain := PackedVector2Array(points)
	for i in range(points.size() - 2, 0, -1):
		chain.append(points[i])
	shape.polygon = chain
	body.add_child(shape)
	add_child(body)


func _add_track(radius: float) -> void:
	## Visual annulus sitting just outside the running surface.
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var polys: Array[PackedInt32Array] = []
	var steps := ARC_STEPS * 2
	var circumference := TAU * radius
	for i in steps:
		var a0 := float(i) / float(steps) * TAU
		var a1 := float(i + 1) / float(steps) * TAU
		var inner0 := Vector2(cos(a0), sin(a0)) * radius
		var inner1 := Vector2(cos(a1), sin(a1)) * radius
		var outer0 := Vector2(cos(a0), sin(a0)) * (radius + TRACK_THICKNESS)
		var outer1 := Vector2(cos(a1), sin(a1)) * (radius + TRACK_THICKNESS)
		var base := verts.size()
		verts.append(inner0)
		verts.append(inner1)
		verts.append(outer1)
		verts.append(outer0)
		var u0 := float(i) / float(steps) * circumference
		var u1 := float(i + 1) / float(steps) * circumference
		uvs.append(Vector2(u0, 0.0))
		uvs.append(Vector2(u1, 0.0))
		uvs.append(Vector2(u1, TRACK_THICKNESS))
		uvs.append(Vector2(u0, TRACK_THICKNESS))
		polys.append(PackedInt32Array([base, base + 1, base + 2, base + 3]))

	var track := Polygon2D.new()
	track.polygon = verts
	track.uv = uvs
	track.polygons = polys
	track.texture = load("res://assets/tiles/loop_track.png")
	track.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	track.z_index = -1
	add_child(track)
