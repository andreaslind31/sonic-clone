extends Camera2D
class_name FollowCamera
## Camera that tracks the player the way the Genesis games did.
##
## Horizontally the player is kept inside a 16px window and the camera never
## moves faster than 16px per frame, which is what produces the familiar "run
## ahead and the view catches up" feel. Vertically the camera is glued to the
## player while grounded (6px/frame, 16px/frame at speed) but has a 32px window
## in the air, so jumping does not shake the view. Holding up or down for two
## seconds pans the view; a spindash briefly freezes it.

const H_WINDOW := 8.0
const H_SPEED := 16.0
const V_WINDOW_AIR := 32.0
const V_SPEED_SLOW := 6.0
const V_SPEED_FAST := 16.0
const FAST_THRESHOLD := 8.0
const LOOK_SHIFT := 104.0
const LOOK_SPEED := 2.0
const LOOK_DELAY := 120

var target: Player

var _look_offset := 0.0


func _ready() -> void:
	position_smoothing_enabled = false
	ignore_rotation = true


func snap_to_target() -> void:
	if target:
		global_position = target.global_position
		reset_smoothing()


func _physics_process(_delta: float) -> void:
	if target == null:
		return
	if target.camera_lag > 0:
		return

	var focus := target.global_position

	var dx := focus.x - global_position.x
	if absf(dx) > H_WINDOW:
		global_position.x += signf(dx) * minf(absf(dx) - H_WINDOW, H_SPEED)

	var dy := focus.y - global_position.y
	if target.grounded:
		var limit := V_SPEED_FAST if absf(target.ground_speed) >= FAST_THRESHOLD \
			else V_SPEED_SLOW
		global_position.y += signf(dy) * minf(absf(dy), limit)
	elif absf(dy) > V_WINDOW_AIR:
		global_position.y += signf(dy) * minf(absf(dy) - V_WINDOW_AIR, V_SPEED_FAST)

	_update_look()


func _update_look() -> void:
	var want := 0.0
	if target.look_timer >= LOOK_DELAY:
		if Input.is_action_pressed("look_up"):
			want = -LOOK_SHIFT
		elif Input.is_action_pressed("crouch"):
			want = LOOK_SHIFT
	_look_offset = move_toward(_look_offset, want, LOOK_SPEED)
	offset.y = _look_offset
