extends Node2D
## A swept ray reuses world/body collisions without adding projectile polygons.

@export var speed := 1100.0
var direction := Vector2.RIGHT
var lifetime := 1.1
var damage := 1


func _ready() -> void:
	add_to_group(&"player_projectiles")
	queue_redraw()


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	var destination := global_position + direction * speed * delta
	var query := PhysicsRayQueryParameters2D.create(global_position, destination, 3)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var body: Object = hit["collider"]
		if body.has_method("take_projectile_hit"):
			body.take_projectile_hit(damage)
		queue_free()
		return
	global_position = destination


func _draw() -> void:
	draw_line(-direction * 12.0, Vector2.ZERO, Color(1.0, 0.8, 0.38), 3.0)
	draw_line(-direction * 5.0, Vector2.ZERO, Color(1.0, 0.97, 0.8), 2.0)
