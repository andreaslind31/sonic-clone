extends Node
## Development helper: screenshot the title menu, optionally after moving the
## cursor. Same idea as capture.gd, but for the menu scene.
##
##   Godot res://tools/menu_capture.tscn -- --out=/tmp/menu --shots=40,90 \
##       --frames=120 --tap=select_3@50

var _out := "/tmp/menu"
var _frames := 120
var _shots: Array[int] = []
var _taps: Array[Dictionary] = []
var _frame := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		var value := arg.substr(key.length() + 1)
		match key:
			"--out":
				_out = value
			"--frames":
				_frames = int(value)
			"--shots":
				for token in value.split(","):
					_shots.append(int(token))
			"--tap":
				for token in value.split(","):
					_taps.append({
						"action": token.get_slice("@", 0),
						"frame": int(token.get_slice("@", 1)),
					})
	add_child(load(Game.MENU_SCENE).instantiate())


func _process(_delta: float) -> void:
	_frame += 1
	for tap in _taps:
		if _frame == int(tap["frame"]):
			Input.action_press(tap["action"])
		elif _frame == int(tap["frame"]) + 1:
			Input.action_release(tap["action"])
	if _shots.has(_frame):
		_snapshot.call_deferred(_frame)
	if _frame >= _frames:
		get_tree().quit()


func _snapshot(frame: int) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s_%04d.png" % [_out, frame]
	if image.save_png(path) == OK:
		print("menu capture: wrote %s" % path)
