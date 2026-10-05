extends CanvasLayer
class_name OptionsMenu
## Reusable options overlay for both the title and pause menus.
##
## Audio, display and keyboard changes are applied immediately and persisted by
## Game. The overlay always processes so it remains interactive over a paused
## game, while the game world stays frozen below it.

signal closed()

const MAIN_ITEMS := ["MUSIC", "SFX", "FULLSCREEN", "KEYBOARD CONTROLS", "BACK"]
const LABEL_COLOUR := Color(1, 0.85, 0.15)
const VALUE_COLOUR := Color(0.82, 0.88, 1.0)
const SELECTED_COLOUR := Color(1, 0.92, 0.42)

var _panel: Control
var _main_page: Control
var _controls_page: Control
var _main_rows: Array[Label] = []
var _control_rows: Array[Label] = []
var _capture_label: Label
var _open := false
var _page := 0
var _selected := 0
var _capturing := ""
var _block_frames := 0


static func create() -> OptionsMenu:
	var menu := OptionsMenu.new()
	menu.layer = 30
	menu.process_mode = Node.PROCESS_MODE_ALWAYS
	return menu


func _ready() -> void:
	_build()


func _build() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.035, 0.06, 0.15, 0.96)
	dim.size = Vector2(424, 240)
	_panel.add_child(dim)

	_main_page = Control.new()
	_main_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_page.add_child(_label("OPTIONS", LABEL_COLOUR, 20, 36.0))
	for i in MAIN_ITEMS.size():
		var row := _label("", VALUE_COLOUR, 11, 82.0 + i * 23.0)
		_main_page.add_child(row)
		_main_rows.append(row)
	_main_page.add_child(_label(
		"ARROWS CHANGE     SPACE SELECTS     ESC BACK",
		Color(0.66, 0.72, 0.9), 8, 218.0
	))
	_panel.add_child(_main_page)

	_controls_page = Control.new()
	_controls_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_controls_page.add_child(_label("KEYBOARD CONTROLS", LABEL_COLOUR, 17, 22.0))
	for i in Game.REMAPPABLE_ACTIONS.size() + 2:
		var row := _label("", VALUE_COLOUR, 9, 53.0 + i * 17.0)
		_controls_page.add_child(row)
		_control_rows.append(row)
	_capture_label = _label("", Color(1.0, 0.65, 0.3), 9, 211.0)
	_controls_page.add_child(_capture_label)
	_panel.add_child(_controls_page)

	add_child(_panel)
	_show_page(0)


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


func open() -> void:
	_open = true
	_capturing = ""
	_block_frames = 2
	_panel.visible = true
	_show_page(0)


func close() -> void:
	if not _open:
		return
	_open = false
	_capturing = ""
	_panel.visible = false
	closed.emit()


func is_open() -> bool:
	return _open


func _show_page(page: int) -> void:
	_page = page
	_selected = 0
	_main_page.visible = page == 0
	_controls_page.visible = page == 1
	_refresh()


func _process(_delta: float) -> void:
	if not _open:
		return
	if _block_frames > 0:
		_block_frames -= 1
		return
	if _capturing != "":
		return
	if Input.is_action_just_pressed("pause"):
		_back()
		return
	if Input.is_action_just_pressed("crouch"):
		_move(1)
	elif Input.is_action_just_pressed("look_up"):
		_move(-1)
	elif Input.is_action_just_pressed("move_left"):
		_adjust(-1)
	elif Input.is_action_just_pressed("move_right"):
		_adjust(1)
	elif Input.is_action_just_pressed("start") or Input.is_action_just_pressed("jump"):
		_confirm()


func _unhandled_input(event: InputEvent) -> void:
	if not _open or _capturing == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode != KEY_ESCAPE:
			if Game.set_key_binding(_capturing, event.physical_keycode):
				Sfx.play("checkpoint", 1.1)
			else:
				Sfx.play("hurt", 1.2)
		_capturing = ""
		_block_frames = 2
		_refresh()
		get_viewport().set_input_as_handled()


func _move(step: int) -> void:
	var count := MAIN_ITEMS.size() if _page == 0 else Game.REMAPPABLE_ACTIONS.size() + 2
	_selected = posmod(_selected + step, count)
	_refresh()
	Sfx.play("ring", 1.05)


func _adjust(direction: int) -> void:
	if _page != 0:
		return
	match _selected:
		0:
			Game.set_music_volume(snappedf(clampf(
				Game.music_volume + direction * 0.1, 0.0, 1.0), 0.1))
		1:
			Game.set_sfx_volume(snappedf(clampf(
				Game.sfx_volume + direction * 0.1, 0.0, 1.0), 0.1))
			Sfx.play("ring", 0.9 + Game.sfx_volume * 0.2)
		2:
			Game.set_fullscreen(not Game.fullscreen)
	_refresh()


func _confirm() -> void:
	if _page == 0:
		match _selected:
			2:
				Game.set_fullscreen(not Game.fullscreen)
			3:
				_show_page(1)
			4:
				close()
		return

	if _selected < Game.REMAPPABLE_ACTIONS.size():
		_capturing = Game.REMAPPABLE_ACTIONS[_selected]
		_refresh()
	elif _selected == Game.REMAPPABLE_ACTIONS.size():
		Game.reset_key_bindings()
		Sfx.play("checkpoint", 1.0)
		_refresh()
	else:
		_show_page(0)


func _back() -> void:
	if _page == 1:
		_show_page(0)
	else:
		close()


func _refresh() -> void:
	if _page == 0:
		var values := [
			"%d%%" % roundi(Game.music_volume * 100.0),
			"%d%%" % roundi(Game.sfx_volume * 100.0),
			"ON" if Game.fullscreen else "OFF",
			"",
			"",
		]
		for i in _main_rows.size():
			var marker := ">" if i == _selected else " "
			var suffix := "  < %s >" % values[i] if values[i] != "" else ""
			_main_rows[i].text = "%s %s%s" % [marker, MAIN_ITEMS[i], suffix]
			_main_rows[i].add_theme_color_override(
				"font_color", SELECTED_COLOUR if i == _selected else VALUE_COLOUR
			)
		return

	for i in _control_rows.size():
		var marker := ">" if i == _selected else " "
		if i < Game.REMAPPABLE_ACTIONS.size():
			var action: String = Game.REMAPPABLE_ACTIONS[i]
			_control_rows[i].text = "%s %-16s  %s" % [
				marker, Game.ACTION_LABELS[action], Game.key_binding_text(action)
			]
		elif i == Game.REMAPPABLE_ACTIONS.size():
			_control_rows[i].text = "%s RESET DEFAULTS" % marker
		else:
			_control_rows[i].text = "%s BACK" % marker
		_control_rows[i].add_theme_color_override(
			"font_color", SELECTED_COLOUR if i == _selected else VALUE_COLOUR
		)
	_capture_label.text = "PRESS A KEY     ESC CANCELS" if _capturing != "" \
		else "SPACE CHANGES A KEY     ESC BACK"
