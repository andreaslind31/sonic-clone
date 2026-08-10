extends CanvasLayer
class_name PauseMenu
## Escape menu: resume, restart the act, or quit to the title screen.
##
## This node runs with PROCESS_MODE_ALWAYS because it is the only thing still
## awake once the tree is paused — anything PAUSABLE, including the Zone that
## created this, cannot un-pause itself.
##
## Every exit path clears `paused` before it fires. A scene change made while the
## tree is paused would load the next scene already frozen, and SceneTreeTimers
## do not advance either, so the fades on the far side would never finish.

signal resumed()
signal restart_requested()
signal quit_requested()

const OPTIONS := ["RESUME", "RESTART ACT", "QUIT TO TITLE"]

var can_pause := true

var _panel: Control
var _rows: Array[Label] = []
var _selected := 0
var _paused := false


static func create() -> PauseMenu:
	var menu := PauseMenu.new()
	menu.layer = 20
	menu.process_mode = Node.PROCESS_MODE_ALWAYS
	return menu


func _ready() -> void:
	_build()


func _build() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.07, 0.16, 0.82)
	dim.size = Vector2(424, 240)
	_panel.add_child(dim)

	_panel.add_child(_label("PAUSED", Color(1, 0.85, 0.15), 20, 62.0))
	for i in OPTIONS.size():
		var row := _label("", Color(0.8, 0.86, 1.0), 11, 116.0 + i * 18.0)
		_panel.add_child(row)
		_rows.append(row)
	_panel.add_child(_label("ESC RESUMES     ARROWS AND SPACE TO CHOOSE",
		Color(0.66, 0.72, 0.9), 8, 208.0))
	add_child(_panel)
	_refresh()


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


func is_paused() -> bool:
	return _paused


func _process(_delta: float) -> void:
	if not _paused:
		if can_pause and Input.is_action_just_pressed("pause"):
			pause()
		return

	if Input.is_action_just_pressed("pause"):
		resume()
		return
	if Input.is_action_just_pressed("crouch") or Input.is_action_just_pressed("move_right"):
		_move(1)
	elif Input.is_action_just_pressed("look_up") or Input.is_action_just_pressed("move_left"):
		_move(-1)
	elif Input.is_action_just_pressed("start") or Input.is_action_just_pressed("jump"):
		_confirm()


func pause() -> void:
	if _paused:
		return
	_paused = true
	_selected = 0
	_refresh()
	_panel.visible = true
	get_tree().paused = true
	Sfx.play("checkpoint", 0.8)


func resume() -> void:
	if not _paused:
		return
	_paused = false
	_panel.visible = false
	get_tree().paused = false
	Sfx.play("ring", 0.9)
	resumed.emit()


func _move(step: int) -> void:
	_selected = posmod(_selected + step, OPTIONS.size())
	_refresh()
	Sfx.play("ring", 1.1)


func _refresh() -> void:
	for i in _rows.size():
		var marker := ">" if i == _selected else " "
		_rows[i].text = "%s %s" % [marker, OPTIONS[i]]
		_rows[i].add_theme_color_override(
			"font_color",
			Color(1, 0.9, 0.4) if i == _selected else Color(0.72, 0.78, 0.92)
		)


func _confirm() -> void:
	match _selected:
		1:
			_leave()
			restart_requested.emit()
		2:
			_leave()
			quit_requested.emit()
		_:
			resume()


## Shared teardown for the options that hand control back to the Zone.
func _leave() -> void:
	_paused = false
	_panel.visible = false
	get_tree().paused = false
