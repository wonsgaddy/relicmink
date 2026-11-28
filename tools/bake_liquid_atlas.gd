extends SceneTree
## Regenerate the shared pixel atlas: godot --headless --path . --script tools/bake_liquid_atlas.gd

const FRAME_SIZE := 32
const BODY_FRAMES := 4
const SPLASH_FRAMES := 6
const PHASES := 4

func _initialize() -> void:
	var atlas := Image.create(FRAME_SIZE * (BODY_FRAMES + SPLASH_FRAMES * PHASES), FRAME_SIZE, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	var outline := Color("593346")
	var shadow := Color("9d5138")
	var liquid := Color("e9a743")
	var highlight := Color("ffe49a")
	for frame in range(BODY_FRAMES):
		var stretch := 1.1 if frame in [0, 1] else 0.9
		var center := Vector2i(frame * FRAME_SIZE + 16, 16)
		for y in range(-5, 6):
			for x in range(-5, 6):
				var point := Vector2(float(x) / stretch, float(y) * stretch)
				var wobble := sin(float(y) * 1.8 + frame * PI * 0.5) * 0.3
				var radius := point.length() + wobble
				if radius > 4.4:
					continue
				var color := outline if radius > 3.5 else (shadow if y > 1 else liquid)
				if x in [-2, -1] and y in [-2, -1]:
					color = highlight
				atlas.fill_rect(Rect2i(center + Vector2i(x, y) * 2, Vector2i(2, 2)), color)
	for phase in range(PHASES):
		for frame in range(SPLASH_FRAMES):
			var center := Vector2i((BODY_FRAMES + phase * SPLASH_FRAMES + frame) * FRAME_SIZE + 16, 16)
			var spread := float(frame) / SPLASH_FRAMES * 14.0
			for index in range(6):
				var point := Vector2.from_angle(index * TAU / 6.0 + phase) * spread
				point = (point / 2.0).round() * 2.0
				atlas.fill_rect(Rect2i(center + Vector2i(point) - Vector2i(2, 2), Vector2i(4, 4)), liquid)
	var error := atlas.save_png("res://sprites/jack_liquid_atlas.png")
	if error != OK:
		push_error("Liquid atlas save failed: %s" % error_string(error))
	quit(0 if error == OK else 1)
