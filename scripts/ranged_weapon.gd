extends Node2D

const Projectile := preload("res://scripts/player_projectile.gd")

@export var fire_interval := 0.18
@export var enabled := true
@onready var holder: CharacterBody2D = get_parent()

var cooldown := 0.0
var recoil := 0.0
var flash_time := 0.0
var aim_direction := Vector2.RIGHT


func _physics_process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	recoil = move_toward(recoil, 0.0, 28.0 * delta)
	flash_time = maxf(0.0, flash_time - delta)
	if enabled:
		_aim_at(get_global_mouse_position())
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			fire_at(get_global_mouse_position())
	queue_redraw()


func _aim_at(target: Vector2) -> void:
	var aim := target - global_position
	if aim.length_squared() > 1.0:
		aim_direction = aim.normalized()
		global_rotation = aim_direction.angle()


func fire_at(target: Vector2) -> bool:
	if not enabled or cooldown > 0.0 or holder.hurt:
		return false
	_aim_at(target)
	cooldown = fire_interval
	GameAudio.play(&"shot")
	recoil = 3.0
	flash_time = 0.045
	var shot := Projectile.new()
	shot.direction = aim_direction
	# Cast from the hand, not beyond the barrel, so nearby walls block shots.
	holder.get_parent().add_child(shot)
	shot.global_position = global_position
	queue_redraw()
	return true


func _draw() -> void:
	var grip_side := 1.0 if aim_direction.x >= 0.0 else -1.0
	draw_rect(Rect2(-2.0 - recoil, -2.5, 13.0, 5.0), Color(0.3, 0.38, 0.48))
	draw_rect(Rect2(3.0 - recoil, -2.5, 10.0, 2.0), Color(0.7, 0.78, 0.82))
	draw_rect(Rect2(-1.0 - recoil, 0.0 if grip_side > 0.0 else -6.0, 4.0, 6.0), Color(0.46, 0.3, 0.23))
	if flash_time > 0.0:
		draw_line(Vector2(14.0 - recoil, 0), Vector2(20.0 - recoil, 0), Color(1, 0.87, 0.5), 3.0)
