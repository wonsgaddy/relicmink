extends Node2D
## Lightweight attack tells: lines/brackets only, updated at pixel-animation rate.

enum Kind { SPRAY, GROUND }
var kind := Kind.SPRAY
var heading := Vector2.RIGHT
var spread := 0.3
var progress := 0.0
var locked := false
var points := PackedVector2Array()
var age := 0.0
var visual_tick := -1
var line_ends := PackedVector2Array()
var ray_query := PhysicsRayQueryParameters2D.new()

func _ready() -> void:
	add_to_group(&"attack_warnings")
	z_index = 4

func _physics_process(delta: float) -> void:
	age += delta
	var tick := int(age * 12.0)
	if tick != visual_tick:
		visual_tick = tick
		refresh_geometry()

func refresh_geometry() -> void:
	if kind == Kind.SPRAY:
		line_ends.clear()
		ray_query.collision_mask = 1
		ray_query.hit_from_inside = true
		var space := get_world_2d().direct_space_state
		for angle in [-spread, 0.0, spread]:
			var ray := heading.rotated(angle)
			ray_query.from = global_position + ray * 18.0
			ray_query.to = global_position + ray * 720.0
			var hit := space.intersect_ray(ray_query)
			var endpoint: Vector2 = hit["position"] if not hit.is_empty() else ray_query.to
			line_ends.append(endpoint - global_position)
	queue_redraw()

func _draw() -> void:
	var color := Color(1.0, 0.68, 0.26, 0.55 + progress * 0.3)
	if locked or progress > 0.75:
		color = Color(1.0, 0.35, 0.24, 0.85)
	if kind == Kind.SPRAY:
		var index := 0
		for angle in [-spread, 0.0, spread]:
			var ray := heading.rotated(angle)
			var endpoint := line_ends[index] if line_ends.size() == 3 else ray * 720.0
			draw_line(ray * 18.0, endpoint, color, 2.0)
			index += 1
		draw_rect(Rect2(-4, -4, 8, 8), color)
	else:
		for point in points:
			var width := 28.0 - progress * 6.0
			draw_line(point + Vector2(-width, -18), point + Vector2(-width, -2), color, 3.0)
			draw_line(point + Vector2(width, -18), point + Vector2(width, -2), color, 3.0)
			draw_line(point + Vector2(-width, -2), point + Vector2(width, -2), color, 3.0)
