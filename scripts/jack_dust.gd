extends Node2D
## Short-lived pixel dust using drawing only, with no collision geometry.

var normal := Vector2.UP
var strength := 1.0
var count := 18
var age := 0.0
var particles: Array[Dictionary] = []
var rolling_trail := false
var drift := Vector2.ZERO

func _ready() -> void:
	add_to_group(&"boss_dust")
	z_index = 3
	var tangent := normal.orthogonal()
	for index in range(count):
		particles.append({
			"position": tangent * randf_range(-15.0, 15.0),
			"velocity": drift + normal * randf_range(45.0, 125.0) * strength + tangent * randf_range(-105.0, 105.0) * strength,
			"life": randf_range(0.32, 0.52) if rolling_trail else randf_range(0.3, 0.6),
			"size": randf_range(10.0, 18.0) if rolling_trail else (4.0 if index % 3 else 6.0),
		})

func _physics_process(delta: float) -> void:
	age += delta
	if age >= (0.56 if rolling_trail else 0.65):
		queue_free()
		return
	for particle in particles:
		particle["velocity"] += Vector2(0, 80.0 if rolling_trail else 320.0) * delta
		particle["position"] += particle["velocity"] * delta
	queue_redraw()

func _draw() -> void:
	for index in range(particles.size()):
		var particle := particles[index]
		var opacity := maxf(0.0, 1.0 - age / float(particle["life"]))
		if opacity <= 0.0:
			continue
		var color := Color("92839e") if index % 2 else Color("635875")
		if rolling_trail:
			var progress := clampf(age / float(particle["life"]), 0.0, 1.0)
			var size := roundf(float(particle["size"]) * (0.65 + progress * 0.9) / 2.0) * 2.0
			var point: Vector2 = (particle["position"] / 2.0).round() * 2.0
			point -= Vector2(size * 0.5, size)
			color = Color("a29287") if index % 2 else Color("c6b6a0")
			color.a = pow(opacity, 1.5) * 0.72
			# Distinct square blocks overlap loosely, then spread apart as they fade.
			var spread := 0.8 + progress * 0.6
			_draw_square(point, size * 0.75, color)
			var light := Color("cdbda5", color.a * 0.85)
			_draw_square(point + Vector2(size * 0.6, -size * 0.15) * spread, size * 0.5, light)
			var dark := Color("93867b", color.a * 0.8)
			_draw_square(point + Vector2(-size * 0.3, size * 0.5) * spread, size * 0.4, dark)
			continue
		color.a = opacity
		var point: Vector2 = (particle["position"] / 2.0).round() * 2.0
		draw_rect(Rect2(point, Vector2.ONE * float(particle["size"])), color)


func _draw_square(point: Vector2, side: float, color: Color) -> void:
	var pixel_side := maxf(4.0, roundf(side / 2.0) * 2.0)
	draw_rect(Rect2((point / 2.0).round() * 2.0, Vector2.ONE * pixel_side), color)
