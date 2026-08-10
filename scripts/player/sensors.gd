extends RefCounted
class_name Sensors
## SPG-style collision sensors, raycast against the terrain each frame.
##
## Genesis games sampled per-tile height masks; here the terrain is real
## geometry (segment collision polygons), so the surface angle comes straight
## from the ray's collision normal. Segment normals can face either way
## depending on winding, so every hit's normal is flipped to face the sensor.
##
## All returned distances are measured from the relevant edge of the hitbox:
## positive means there is a gap, negative means the player has penetrated.

const EXTRA_REACH := 32.0
const WALL_REACH := 4.0

var _player: Node2D


func _init(player: Node2D) -> void:
	_player = player


func _cast(from: Vector2, direction: Vector2, length: float) -> Dictionary:
	var space := _player.get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(from, from + direction * length)
	params.collision_mask = _player.terrain_mask()
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return {}
	var normal: Vector2 = hit["normal"]
	if normal.dot(direction) > 0.0:
		normal = -normal
	return {
		"point": hit["position"] as Vector2,
		"normal": normal,
		"travel": from.distance_to(hit["position"]),
	}


## Floor sensors A and B: cast from the player's centre down past the feet.
## Returns the nearer of the two, with `distance` relative to the feet.
##
## Starting at the centre rather than the head matters: a player who has sunk a
## few pixels into a rising slope must still see it as floor, and a ceiling just
## above the head must not be mistaken for one.
func floor_hit(offset: Vector2, angle: float) -> Dictionary:
	var down := Vector2.DOWN.rotated(angle)
	var right := Vector2.RIGHT.rotated(angle)
	var span: float = _player.height_radius
	var best := {}
	for side in [-1.0, 1.0]:
		var origin: Vector2 = _player.global_position + offset \
			+ right * (side * _player.width_radius)
		var hit := _cast(origin, down, span + EXTRA_REACH)
		if hit.is_empty():
			continue
		hit["distance"] = float(hit["travel"]) - span
		hit["side"] = side
		if best.is_empty() or float(hit["distance"]) < float(best["distance"]):
			best = hit
	return best


## Ceiling sensors C and D: cast from the player's centre up past the head.
func ceiling_hit(angle: float) -> Dictionary:
	var up := Vector2.UP.rotated(angle)
	var right := Vector2.RIGHT.rotated(angle)
	var span: float = _player.height_radius
	var best := {}
	for side in [-1.0, 1.0]:
		var origin: Vector2 = _player.global_position \
			+ right * (side * _player.width_radius)
		var hit := _cast(origin, up, span + EXTRA_REACH)
		if hit.is_empty():
			continue
		hit["distance"] = float(hit["travel"]) - span
		hit["side"] = side
		if best.is_empty() or float(hit["distance"]) < float(best["distance"]):
			best = hit
	return best


## Push sensors E and F: horizontal, from the player's centre.
func wall_hit(side: float, angle: float) -> Dictionary:
	var direction := Vector2.RIGHT.rotated(angle) * side
	var hit := _cast(_player.global_position, direction, _player.push_radius + WALL_REACH)
	if hit.is_empty():
		return {}
	hit["distance"] = hit["travel"]
	return hit
