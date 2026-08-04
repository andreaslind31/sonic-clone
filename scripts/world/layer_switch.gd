extends Area2D
class_name LayerSwitch
## Path swapper, as used around Genesis loops.
##
## Two terrain layers exist: A (`terrain_a`) and B (`terrain_b`). Flat ground is
## solid on both; a loop's right arc is solid only on A and its left arc only on
## B. Crossing a switcher changes which layer the player's sensors collide with,
## which is what lets the two halves of a loop overlap in space.

enum Mode {
	BY_DIRECTION,  ## moving right selects A, moving left selects B
	ALWAYS_A,
	ALWAYS_B,
}

var mode: Mode = Mode.BY_DIRECTION


static func create(where: Vector2, height: float, mode_value: Mode, width := 8.0) -> LayerSwitch:
	var switcher := LayerSwitch.new()
	switcher.mode = mode_value
	switcher.position = where
	switcher.collision_layer = 0
	switcher.collision_mask = Game.COLLISION_LAYERS.player_hitbox
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, height)
	shape.shape = rect
	switcher.add_child(shape)
	switcher.area_entered.connect(switcher._on_area_entered)
	return switcher


func _on_area_entered(area: Area2D) -> void:
	var player := area.get_parent() as Player
	if player == null:
		return
	match mode:
		Mode.ALWAYS_A:
			player.set_path_layer(0)
		Mode.ALWAYS_B:
			player.set_path_layer(1)
		Mode.BY_DIRECTION:
			# use world velocity, not ground speed: at the top of a loop the
			# player is upside down and running "forward" means moving left
			if player.velocity.x > 0.0:
				player.set_path_layer(0)
			elif player.velocity.x < 0.0:
				player.set_path_layer(1)
