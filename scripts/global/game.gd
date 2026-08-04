extends Node
## Global run state: score, rings, lives, timer, checkpoints and the input map.
##
## Registered as the `Game` autoload. Keyboard bindings are created here rather
## than in project.godot so the mapping stays readable and greppable.

signal rings_changed(count: int)
signal score_changed(value: int)
signal lives_changed(count: int)
signal life_lost()

const COLLISION_LAYERS := {
	"terrain_a": 1 << 0,
	"terrain_b": 1 << 1,
	"player": 1 << 2,
	"player_hitbox": 1 << 3,
	"object": 1 << 4,
	"solid_object": 1 << 5,
}

const BINDINGS := {
	"move_left": [KEY_LEFT, KEY_A],
	"move_right": [KEY_RIGHT, KEY_D],
	"look_up": [KEY_UP, KEY_W],
	"crouch": [KEY_DOWN, KEY_S],
	"jump": [KEY_SPACE, KEY_Z, KEY_J],
	"restart": [KEY_R],
	"debug": [KEY_F1],
}

var score := 0
var rings := 0
var lives := 3
var time_left := 0.0        ## seconds elapsed in the act
var act_running := false
var checkpoint := Vector2.ZERO
var checkpoint_set := false
var debug_draw := false

var _ring_life_marks := 0   ## how many 100-ring extra lives have been awarded


func _ready() -> void:
	_register_input()
	reset_run()


func _register_input() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	# gamepad: left stick / dpad plus the bottom face button
	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("look_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("crouch", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_button("move_left", JOY_BUTTON_DPAD_LEFT)
	_add_joy_button("move_right", JOY_BUTTON_DPAD_RIGHT)
	_add_joy_button("look_up", JOY_BUTTON_DPAD_UP)
	_add_joy_button("crouch", JOY_BUTTON_DPAD_DOWN)
	_add_joy_button("jump", JOY_BUTTON_A)


func _add_joy_axis(action: String, axis: JoyAxis, direction: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = direction
	InputMap.action_add_event(action, event)


func _add_joy_button(action: String, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


## Fresh run: called on boot and after a game over.
func reset_run() -> void:
	score = 0
	rings = 0
	lives = 3
	time_left = 0.0
	checkpoint_set = false
	_ring_life_marks = 0
	act_running = false
	score_changed.emit(score)
	rings_changed.emit(rings)
	lives_changed.emit(lives)


## Per-life reset; keeps score, lives and any checkpoint.
func reset_life() -> void:
	rings = 0
	rings_changed.emit(rings)


func _process(delta: float) -> void:
	if act_running:
		time_left += delta


func add_rings(amount: int) -> void:
	rings += amount
	rings_changed.emit(rings)
	# 100 and 200 rings each grant an extra life, as in the Genesis games
	while rings >= (_ring_life_marks + 1) * 100 and _ring_life_marks < 2:
		_ring_life_marks += 1
		add_life()


func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)


func add_life() -> void:
	lives += 1
	lives_changed.emit(lives)
	Sfx.play("extra_life")


func lose_life() -> void:
	lives -= 1
	lives_changed.emit(lives)
	life_lost.emit()


func set_checkpoint(where: Vector2) -> void:
	checkpoint = where
	checkpoint_set = true


func time_string() -> String:
	var minutes := int(time_left) / 60
	var seconds := int(time_left) % 60
	var centis := int(fposmod(time_left, 1.0) * 100.0)
	return "%d:%02d:%02d" % [minutes, seconds, centis]
