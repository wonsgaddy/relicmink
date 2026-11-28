extends Node2D
## One draw node with bounded snapshots, using the existing animation textures.

const INTERVAL := 0.035
const LIFETIME := 0.22
const MAX_FRAMES := 7
var frames: Array[Dictionary] = []
var emission_left := 0.0

func _ready() -> void:
	top_level = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -1
	add_to_group(&"dash_trails")

func emit_frame(sprite: AnimatedSprite2D, delta: float, force := false) -> void:
	emission_left -= delta
	if not force and emission_left > 0.0:
		return
	emission_left = INTERVAL
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null:
		return
	var pose := sprite.global_transform
	if sprite.flip_h:
		pose.x = -pose.x
	if sprite.flip_v:
		pose.y = -pose.y
	var origin := sprite.offset
	if sprite.centered:
		origin -= texture.get_size() * 0.5
	if frames.size() >= MAX_FRAMES:
		frames.pop_front()
	frames.append({"texture": texture, "pose": pose, "origin": origin, "age": 0.0})
	queue_redraw()

func clear() -> void:
	frames.clear()
	emission_left = 0.0
	queue_redraw()

func _physics_process(delta: float) -> void:
	if frames.is_empty():
		return
	for frame in frames:
		frame.age += delta
	while not frames.is_empty() and frames[0].age >= LIFETIME:
		frames.pop_front()
	queue_redraw()

func _draw() -> void:
	var inverse := global_transform.affine_inverse()
	for frame in frames:
		var opacity := 0.46 * pow(1.0 - clampf(frame.age / LIFETIME, 0.0, 1.0), 1.5)
		draw_set_transform_matrix(inverse * frame.pose)
		draw_texture(frame.texture, frame.origin, Color(0.55, 0.85, 1.0, opacity))
	draw_set_transform_matrix(Transform2D.IDENTITY)
