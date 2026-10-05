extends Node
## Global run state: score, rings, lives, timer, checkpoints and the input map.
##
## Registered as the `Game` autoload. Keyboard bindings are created here rather
## than in project.godot so the mapping stays readable and greppable.

signal rings_changed(count: int)
signal score_changed(value: int)
signal lives_changed(count: int)
signal life_lost()
signal settings_changed()
signal progress_changed()

const MENU_SCENE := "res://scenes/menu.tscn"
const GAME_SCENE := "res://scenes/game.tscn"
const SETTINGS_PATH := "user://settings.cfg"
const PROGRESS_PATH := "user://progress.cfg"

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
	"select_1": [KEY_1],
	"select_2": [KEY_2],
	"select_3": [KEY_3],
	"select_4": [KEY_4],
	"select_5": [KEY_5],
	"start": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE],
	"pause": [KEY_ESCAPE, KEY_P],
	"options": [KEY_O],
}

const REMAPPABLE_ACTIONS := [
	"move_left", "move_right", "look_up", "crouch", "jump", "restart", "pause",
]

const ACTION_LABELS := {
	"move_left": "MOVE LEFT",
	"move_right": "MOVE RIGHT",
	"look_up": "LOOK UP",
	"crouch": "CROUCH / ROLL",
	"jump": "JUMP / ABILITY",
	"restart": "RESTART ACT",
	"pause": "PAUSE",
}

var score := 0
var rings := 0
var act_index := 0        ## which act in the Acts registry is being played
var character_index := 0  ## chosen from the Characters roster; survives a game over
var lives := 3
var time_left := 0.0        ## seconds elapsed in the act
var act_running := false
var checkpoint := Vector2.ZERO
var checkpoint_set := false
var debug_draw := false

var music_volume := 0.8
var sfx_volume := 1.0
var fullscreen := false

## Kept as vars so the test suite can point persistence at disposable files.
var settings_path := SETTINGS_PATH
var progress_path := PROGRESS_PATH

var _ring_life_marks := 0   ## how many 100-ring extra lives have been awarded
var _custom_keys: Dictionary = {}
var _best_times: Dictionary = {}


func _ready() -> void:
	_register_input()
	_load_settings()
	_load_progress()
	_apply_fullscreen()
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
	_add_joy_button("pause", JOY_BUTTON_START)


func _add_joy_axis(action: String, axis: JoyAxis, direction: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = direction
	InputMap.action_add_event(action, event)


func _add_joy_button(action: String, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


# --------------------------------------------------------------------------- #
# persistent settings
# --------------------------------------------------------------------------- #
func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return
	music_volume = clampf(float(config.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	fullscreen = bool(config.get_value("display", "fullscreen", fullscreen))
	for action in REMAPPABLE_ACTIONS:
		if config.has_section_key("controls", action):
			set_key_binding(action, int(config.get_value("controls", action)), false)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("display", "fullscreen", fullscreen)
	for action in _custom_keys:
		config.set_value("controls", action, _custom_keys[action])
	var error := config.save(settings_path)
	if error != OK:
		push_warning("could not save settings (%d)" % error)


func set_music_volume(value: float, save := true) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	if is_instance_valid(Sfx):
		Sfx.apply_settings()
	if save:
		_save_settings()
	settings_changed.emit()


func set_sfx_volume(value: float, save := true) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	if is_instance_valid(Sfx):
		Sfx.apply_settings()
	if save:
		_save_settings()
	settings_changed.emit()


func set_fullscreen(value: bool, save := true) -> void:
	fullscreen = value
	_apply_fullscreen()
	if save:
		_save_settings()
	settings_changed.emit()


func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)


func set_key_binding(action: String, keycode: Key, save := true) -> void:
	if action not in REMAPPABLE_ACTIONS or keycode == KEY_NONE:
		return
	_clear_keyboard_events(action)
	_add_key(action, keycode)
	_custom_keys[action] = keycode
	if save:
		_save_settings()
	settings_changed.emit()


func reset_key_bindings(save := true) -> void:
	_custom_keys.clear()
	for action in REMAPPABLE_ACTIONS:
		_clear_keyboard_events(action)
		for key in BINDINGS[action]:
			_add_key(action, key)
	if save:
		_save_settings()
	settings_changed.emit()


func _clear_keyboard_events(action: String) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)


func _add_key(action: String, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


func key_binding_text(action: String) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event.as_text_physical_keycode()
	return "UNBOUND"


static func volume_db(value: float) -> float:
	return -80.0 if value <= 0.0 else linear_to_db(value)


# --------------------------------------------------------------------------- #
# persistent completion records
# --------------------------------------------------------------------------- #
func _load_progress() -> void:
	_best_times.clear()
	var config := ConfigFile.new()
	if config.load(progress_path) != OK:
		return
	for key in config.get_section_keys("best_times"):
		_best_times[String(key)] = float(config.get_value("best_times", key))


func _save_progress() -> void:
	var config := ConfigFile.new()
	for key in _best_times:
		config.set_value("best_times", key, _best_times[key])
	var error := config.save(progress_path)
	if error != OK:
		push_warning("could not save progress (%d)" % error)


func _record_key(character: int, act: int) -> String:
	return "%s_act_%d" % [Characters.get_character(character).slug, act]


## Returns true when this completion sets a new personal best.
func record_completion(character: int, act: int, elapsed: float) -> bool:
	var key := _record_key(character, act)
	var previous := float(_best_times.get(key, INF))
	if elapsed >= previous:
		return false
	_best_times[key] = elapsed
	_save_progress()
	progress_changed.emit()
	return true


func best_time(character: int, act: int) -> float:
	return float(_best_times.get(_record_key(character, act), -1.0))


func cleared_count(character: int) -> int:
	var count := 0
	for index in Acts.count():
		if best_time(character, index) >= 0.0:
			count += 1
	return count


func format_time(seconds_value: float) -> String:
	if seconds_value < 0.0:
		return "--:--:--"
	var minutes := int(seconds_value) / 60
	var seconds := int(seconds_value) % 60
	var centis := int(fposmod(seconds_value, 1.0) * 100.0)
	return "%d:%02d:%02d" % [minutes, seconds, centis]


## Fresh run: called on boot and after a game over.
func reset_run() -> void:
	score = 0
	act_index = 0
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
