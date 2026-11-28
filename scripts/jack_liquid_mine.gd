extends Node2D
## The shared liquid atlas provides a visible warning before the burst.

const ATLAS := preload("res://sprites/jack_liquid_atlas.png")
const LIQUID_SCALE := preload("res://scripts/jack_liquid_orb.gd").LIQUID_SCALE
var shooter: Node
var arm_delay := 0.9
var age := 0.0
var visual_frame := -1

func _ready() -> void:
	add_to_group(&"enemy_projectiles")
	add_to_group(&"enemy_mines")
	z_index = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_refresh_visual()

func _physics_process(delta: float) -> void:
	age += delta
	if age >= arm_delay:
		if is_instance_valid(shooter):
			shooter.emit_mine_burst(global_position)
		queue_free()
		return
	var pulse := 1.0 + sin(age * 18.0) * 0.12
	scale = Vector2(pulse, 1.0 / pulse)
	_refresh_visual()

func _refresh_visual() -> void:
	var frame := int(age * 12.0) % 4
	if frame == visual_frame:
		return
	visual_frame = frame
	self_modulate = Color(1.35, 1.2, 1.0) if age > arm_delay * 0.6 and frame % 2 == 0 else Color.WHITE
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * LIQUID_SCALE)
	draw_texture_rect_region(ATLAS, Rect2(-24, -11, 48, 16), Rect2(visual_frame * 32, 0, 32, 32))
	var color := Color(1.0, 0.68, 0.26, 0.8)
	if age >= arm_delay * 0.6:
		color = Color(1.0, 0.35, 0.24, 0.9)
	var width := 26.0 - clampf(age / arm_delay, 0.0, 1.0) * 10.0
	draw_line(Vector2(-width, -14), Vector2(-width, -2), color, 2.0)
	draw_line(Vector2(width, -14), Vector2(width, -2), color, 2.0)
