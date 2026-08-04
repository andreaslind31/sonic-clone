extends RefCounted
class_name Art
## Helpers for slicing the generated spritesheets into Godot resources.
##
## Every sheet produced by tools/gen_art.py is a single horizontal strip of
## equally sized frames (the player sheet is the one exception and is handled in
## player.gd), so one loader covers all of them.

static func frames(path: String, frame_w: int, frame_h: int, count: int, fps := 12.0,
		loop := true) -> SpriteFrames:
	var sheet: Texture2D = load(path)
	var result := SpriteFrames.new()
	result.set_animation_speed("default", fps)
	result.set_animation_loop("default", loop)
	for i in count:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * frame_w, 0, frame_w, frame_h)
		result.add_frame("default", atlas)
	return result


static func animated(path: String, frame_w: int, frame_h: int, count: int, fps := 12.0,
		loop := true) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames(path, frame_w, frame_h, count, fps, loop)
	sprite.animation = "default"
	sprite.play()
	return sprite


static func still(path: String, frame_w: int, frame_h: int, index := 0) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = load(path)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(index * frame_w, 0, frame_w, frame_h)
	return sprite


## Spawn a non-looping effect that deletes itself when the animation ends.
static func effect(parent: Node, path: String, frame_w: int, frame_h: int, count: int,
		where: Vector2, fps := 16.0) -> AnimatedSprite2D:
	var sprite := animated(path, frame_w, frame_h, count, fps, false)
	sprite.global_position = where
	sprite.z_index = 20
	parent.add_child(sprite)
	sprite.animation_finished.connect(sprite.queue_free)
	return sprite
