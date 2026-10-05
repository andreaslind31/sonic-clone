extends Node2D
class_name TitleMenu
## Title screen and character select. This is the scene the game boots into:
## nothing starts until the player asks for it.
##
## The character is chosen here and fixed for the whole run, so a route planned
## around one character's moves cannot be undone halfway through by swapping to
## another.

const ROSTER_TOP := 112.0
const ROW_HEIGHT := 13.0
const ROSTER_X := 132.0
const PREVIEW_POSITION := Vector2(78.0, 150.0)

var _selected := 0
var _rows: Array[Label] = []
var _blurb: Label
var _stats: Label
var _records: Label
var _preview: Sprite2D
var _prompt: Label
var _fade: ColorRect
var _options: OptionsMenu
var _starting := false


func _ready() -> void:
	Game.reset_run()
	_selected = Game.character_index
	_build()
	_refresh()
	Sfx.play_music("music_zone")


func _build() -> void:
	# the parallax backdrop doubles as the menu background
	add_child(SkyBackdrop.create(320.0))

	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	var title := _label(ProjectSettings.get_setting(
		"application/config/name", "SONIC CLONE"
	).to_upper(), Color(1, 0.85, 0.15), 26, 34.0)
	layer.add_child(title)
	layer.add_child(_label("A 360 DEGREE PLATFORMER", Color(0.86, 0.92, 1.0), 9, 68.0))

	layer.add_child(_label("CHOOSE YOUR RUNNER", Color(1, 0.85, 0.15), 10, 98.0))
	for i in Characters.count():
		var row := _label("", Color(0.8, 0.86, 1.0), 10, ROSTER_TOP + i * ROW_HEIGHT)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.position.x = ROSTER_X
		layer.add_child(row)
		_rows.append(row)

	_blurb = _label("", Color(0.95, 0.95, 0.7), 8, 181.0)
	layer.add_child(_blurb)
	_stats = _label("", Color(0.72, 0.8, 0.95), 7, 193.0)
	layer.add_child(_stats)
	_records = _label("", Color(0.95, 0.88, 0.5), 7, 205.0)
	layer.add_child(_records)
	_prompt = _label("SPACE STARTS     ARROWS CHOOSE     O OPTIONS",
		Color(1, 1, 1), 8, 226.0)
	layer.add_child(_prompt)

	_preview = Sprite2D.new()
	_preview.centered = true
	_preview.scale = Vector2(2.0, 2.0)
	_preview.position = PREVIEW_POSITION
	layer.add_child(_preview)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.size = Vector2(424, 240)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 0.0, 0.5)

	_options = OptionsMenu.create()
	add_child(_options)


func _label(text: String, colour: Color, size: int, y: float) -> Label:
	var label := Label.new()
	label.text = text
	label.position = Vector2(0, y)
	label.size.x = 424
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", size)
	return label


func _process(_delta: float) -> void:
	if _starting or _options.is_open():
		return
	if Input.is_action_just_pressed("options"):
		_options.open()
		return
	if Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("crouch"):
		_move(1)
	elif Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("look_up"):
		_move(-1)
	for i in Characters.count():
		if Input.is_action_just_pressed("select_%d" % (i + 1)):
			_selected = i
			_refresh()
			Sfx.play("ring", 1.2)
	if Input.is_action_just_pressed("start") or Input.is_action_just_pressed("jump"):
		_start()


func _move(step: int) -> void:
	_selected = posmod(_selected + step, Characters.count())
	_refresh()
	Sfx.play("ring", 1.1)


func _refresh() -> void:
	var character := Characters.get_character(_selected)
	for i in _rows.size():
		var entry := Characters.get_character(i)
		var marker := ">" if i == _selected else " "
		_rows[i].text = "%s %d  %s" % [marker, i + 1, entry.display_name]
		_rows[i].add_theme_color_override(
			"font_color",
			Color(1, 0.9, 0.4) if i == _selected else Color(0.72, 0.78, 0.92)
		)
	_blurb.text = character.blurb.to_upper()
	_stats.text = "TOP SPEED %.2f    JUMP %.2f    %s" % [
		character.top_speed, character.jump_force,
		"SPINDASH" if character.can_spindash else "NO SPINDASH",
	]
	var cleared := Game.cleared_count(_selected)
	var records := PackedStringArray()
	for act_index in Acts.count():
		records.append("A%d %s" % [
			act_index + 1, Game.format_time(Game.best_time(_selected, act_index))
		])
	_records.text = "CLEAR %d/%d   %s" % [cleared, Acts.count(), "   ".join(records)]
	_preview.texture = load(character.sprite_sheet())
	_preview.region_enabled = true
	_preview.region_rect = Rect2(0, 0, 40, 44)


func _start() -> void:
	_starting = true
	Game.character_index = _selected
	Game.act_index = 0
	Sfx.play("checkpoint", 1.0)
	Sfx.fade_music(0.4)
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.4)
	tween.tween_callback(func() -> void:
		get_tree().change_scene_to_file(Game.GAME_SCENE))
