extends Node2D
## Shared baked pixels avoid rebuilding each drop's geometry every frame.

const ATLAS := preload("res://sprites/jack_liquid_atlas.png")
const FRAME_SIZE := Vector2(32, 32)
const LIQUID_SCALE := 0.5
const SHADOW := Color("9d5138")

var velocity := Vector2.ZERO
var shooter: Node
var lifetime := 3.4
var age := 0.0
var splash_time := 0.0
var splashing := false
var phase := 0.0
var _visual_frame := -1
var _travel := Vector2.ZERO
var _side := Vector2.ZERO
var _cached_velocity := Vector2.INF
var _query := PhysicsRayQueryParameters2D.new()
var _space: PhysicsDirectSpaceState2D


func _ready() -> void:
	add_to_group(&"enemy_projectiles")
	z_index = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_query.collision_mask = 5
	_query.hit_from_inside = true
	_space = get_world_2d().direct_space_state
	_cached_velocity = velocity
	_travel = velocity.normalized()
	_side = _travel.orthogonal() * 5.0 * LIQUID_SCALE
	_refresh_visual()


func _physics_process(delta: float) -> void:
	age += delta
	if splashing:
		splash_time -= delta
		if splash_time <= 0.0:
			queue_free()
		_refresh_visual()
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_splash()
		return
	var destination := global_position + velocity * delta
	if velocity != _cached_velocity:
		_cached_velocity = velocity
		_travel = velocity.normalized()
		_side = _travel.orthogonal() * 5.0 * LIQUID_SCALE
	# Sweep the center and both edges to include the liquid body's width.
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for edge in range(3):
		var offset := Vector2.ZERO if edge == 0 else (_side if edge == 1 else -_side)
		_query.from = global_position + offset
		_query.to = destination + offset
		var hit := _space.intersect_ray(_query)
		if not hit.is_empty():
			var distance := global_position.distance_squared_to(hit["position"] - offset)
			if distance < nearest_distance:
				nearest = hit
				nearest_distance = distance
	if not nearest.is_empty():
		if nearest["collider"].has_method("take_hit") and is_instance_valid(shooter):
			shooter.hit_player_from(global_position)
		global_position = nearest["position"]
		_splash(true)
		return
	global_position = destination
	_refresh_visual()


func _splash(impact := false) -> void:
	if impact:
		GameAudio.play(&"splash")
	splashing = true
	splash_time = 0.14
	_refresh_visual()


func _refresh_visual() -> void:
	var frame := int(age * 12.0 + phase) % 4
	if splashing:
		frame = 4 + (int(phase) % 4) * 6 + clampi(int((1.0 - splash_time / 0.14) * 6.0), 0, 5)
	if frame == _visual_frame:
		return
	_visual_frame = frame
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * LIQUID_SCALE)
	if not splashing:
		for index in range(1, 3):
			var tail := (-_travel * (8.0 + index * 5.0) + Vector2(0, sin(age * 18.0 + index) * 2.0))
			tail = (tail / 2.0).round() * 2.0
			draw_rect(Rect2(tail, Vector2.ONE * (4.0 if index == 1 else 2.0)), SHADOW)
	draw_texture_rect_region(ATLAS, Rect2(-FRAME_SIZE * 0.5, FRAME_SIZE), Rect2(Vector2(_visual_frame * 32, 0), FRAME_SIZE))
