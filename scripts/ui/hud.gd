extends CanvasLayer
class_name Hud
## Score / time / rings readout, life counter, title card and results screen.
## Built in code so the whole UI lives in one readable place.

const MARGIN := Vector2(12, 8)
const LABEL_COLOUR := Color(1, 0.85, 0.15)
const VALUE_COLOUR := Color(1, 1, 1)

var _score_value: Label
var _time_value: Label
var _rings_value: Label
var _lives_value: Label
var _lives_icon: Sprite2D
var _character_value: Label
var _title_card: Control
var _zone_label: Label
var _act_label: Label
var _results: Control
var _results_summary: Label
var _results_footer: Label
var _fade: ColorRect


func _ready() -> void:
	layer = 10
	_build_readout()
	_build_title_card()
	_build_results()
	_build_fade()
	Game.score_changed.connect(_on_score_changed)
	Game.rings_changed.connect(_on_rings_changed)
	Game.lives_changed.connect(_on_lives_changed)
	_on_score_changed(Game.score)
	_on_rings_changed(Game.rings)
	_on_lives_changed(Game.lives)


func _label(text: String, colour: Color, position: Vector2, size := 8) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", size)
	return label


func _build_readout() -> void:
	var rows := [["SCORE", "0"], ["TIME", "0:00"], ["RINGS", "0"]]
	var y := MARGIN.y
	var values: Array[Label] = []
	for row in rows:
		add_child(_label(row[0], LABEL_COLOUR, Vector2(MARGIN.x, y), 9))
		var value := _label(row[1], VALUE_COLOUR, Vector2(MARGIN.x + 46, y), 9)
		add_child(value)
		values.append(value)
		y += 11
	_score_value = values[0]
	_time_value = values[1]
	_rings_value = values[2]

	_lives_icon = Art.still(Characters.get_character(Game.character_index).sprite_sheet(),
		40, 44, 0)
	_lives_icon.scale = Vector2(0.5, 0.5)
	_lives_icon.position = Vector2(MARGIN.x + 8, 224)
	add_child(_lives_icon)
	_lives_value = _label("x3", VALUE_COLOUR, Vector2(MARGIN.x + 22, 218), 9)
	add_child(_lives_value)
	_character_value = _label("", LABEL_COLOUR, Vector2(MARGIN.x + 44, 218), 9)
	add_child(_character_value)
	refresh_character()


func _build_title_card() -> void:
	_title_card = Control.new()
	_title_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.08, 0.12, 0.28, 0.85)
	backdrop.size = Vector2(424, 240)
	_title_card.add_child(backdrop)
	_zone_label = _label("", LABEL_COLOUR, Vector2(0, 92), 20)
	_zone_label.size.x = 424
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_card.add_child(_zone_label)
	_act_label = _label("", VALUE_COLOUR, Vector2(0, 122), 12)
	_act_label.size.x = 424
	_act_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_card.add_child(_act_label)
	# roster: the number keys switch character at any time, so list them here
	var y := 148
	for i in Characters.count():
		var character := Characters.get_character(i)
		var line := "%d  %-6s %s" % [i + 1, character.display_name, character.blurb]
		_title_card.add_child(_label(line, Color(0.82, 0.88, 1.0), Vector2(122, y), 8))
		y += 11
	_title_card.add_child(_label(
		"ARROWS move   SPACE jump   DOWN+SPACE spindash",
		Color(0.7, 0.76, 0.92), Vector2(52, 220), 8
	))
	add_child(_title_card)


func _build_results() -> void:
	_results = Control.new()
	_results.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.visible = false
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.1, 0.22, 0.9)
	backdrop.size = Vector2(424, 240)
	_results.add_child(backdrop)
	var heading := _label("ACT CLEARED", LABEL_COLOUR, Vector2(0, 70), 20)
	heading.size.x = 424
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results.add_child(heading)
	_results_summary = _label("", VALUE_COLOUR, Vector2(0, 112), 11)
	_results_summary.size.x = 424
	_results_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results.add_child(_results_summary)
	_results_footer = _label("", VALUE_COLOUR, Vector2(0, 168), 10)
	_results_footer.size.x = 424
	_results_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results.add_child(_results_footer)
	add_child(_results)


func _build_fade() -> void:
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.size = Vector2(424, 240)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _process(_delta: float) -> void:
	_time_value.text = Game.time_string()


## Re-read the chosen character: the readout icon and name follow the switch.
func refresh_character() -> void:
	var character := Characters.get_character(Game.character_index)
	_lives_icon.texture = load(character.sprite_sheet())
	_character_value.text = character.display_name


func show_title_card(zone_name: String, act_number: int, duration := 2.0) -> void:
	_zone_label.text = zone_name
	_act_label.text = "ZONE  ACT %d" % act_number
	_title_card.visible = true
	var tween := create_tween()
	tween.tween_interval(duration)
	tween.tween_property(_title_card, "modulate:a", 0.0, 0.45)
	tween.tween_callback(func() -> void:
		_title_card.visible = false
		_title_card.modulate.a = 1.0)


func show_results(summary: String, footer := "") -> void:
	_results_summary.text = summary
	_results_footer.text = footer if footer != "" else "PRESS R TO RUN IT AGAIN"
	_results.visible = true


func fade_out(duration := 0.6) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, duration)


func fade_in(duration := 0.5) -> void:
	_fade.color.a = 1.0
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 0.0, duration)


func _on_score_changed(value: int) -> void:
	_score_value.text = str(value)


func _on_rings_changed(value: int) -> void:
	_rings_value.text = str(value)
	_rings_value.add_theme_color_override(
		"font_color", VALUE_COLOUR if value > 0 else Color(1, 0.4, 0.35)
	)


func _on_lives_changed(value: int) -> void:
	_lives_value.text = "x%d" % value
