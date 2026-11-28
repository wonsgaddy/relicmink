extends CharacterBody2D

const RUN_SPEED := 210.0
const JUMP_SPEED := 540.0
const SHORT_JUMP_SPEED := 240.0
const DOUBLE_JUMP_SPEED := 560.0
const COYOTE_TIME := 0.10
const JUMP_BUFFER_TIME := 0.12
const DUST_OFFSET := 6.0
const GRAVITY := 1150.0
const MAX_FALL_SPEED := 720.0
const DASH_SPEED := 560.0
const DASH_DURATION := 0.28
const HIT_SPEED := 260.0
const HIT_LIFT := 300.0
const DashTrail := preload("res://scripts/dash_trail.gd")

@export var respawn_bounds := Rect2(-40, -10000, 560, 10320)
@export_group("Movement")
@export var run_speed := RUN_SPEED
@export var jump_speed := JUMP_SPEED
@export var short_jump_speed := SHORT_JUMP_SPEED
@export var double_jump_speed := DOUBLE_JUMP_SPEED
@export var gravity := GRAVITY
@export var max_fall_speed := MAX_FALL_SPEED
@export var dash_speed := DASH_SPEED
@export var dash_duration := DASH_DURATION
@export var hit_speed := HIT_SPEED
@export var hit_lift := HIT_LIFT

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var dust: AnimatedSprite2D = $Dust
@onready var spawn_position := position

var facing := 1.0
var dash_time := 0.0
var coyote_time_left := 0.0
var jump_buffer_left := 0.0
var air_dash_used := false
var double_jump_used := false
var variable_jump_active := false
var hurt := false
var move_input := 0.0
var dash_trail: Node2D


func _ready() -> void:
	sprite.animation_finished.connect(_on_animation_finished)
	dust.animation_finished.connect(dust.hide)
	sprite.play(&"Idle")
	dash_trail = DashTrail.new()
	add_child(dash_trail)


func _physics_process(delta: float) -> void:
	var was_on_floor := is_on_floor()
	if was_on_floor:
		air_dash_used = false
		double_jump_used = false
		coyote_time_left = COYOTE_TIME
	else:
		coyote_time_left = maxf(0.0, coyote_time_left - delta)

	if Input.is_action_just_pressed(&"jump"):
		jump_buffer_left = JUMP_BUFFER_TIME
	else:
		jump_buffer_left = maxf(0.0, jump_buffer_left - delta)

	move_input = Input.get_axis(&"move_left", &"move_right")
	if Input.is_action_just_pressed(&"test_hit"):
		take_hit(-facing)

	if dash_time > 0.0:
		if jump_buffer_left > 0.0:
			_try_jump()
		dash_time = maxf(0.0, dash_time - delta)
	elif hurt:
		velocity.x = move_toward(velocity.x, 0.0, 420.0 * delta)
		_apply_gravity(delta)
	else:
		if not is_zero_approx(move_input):
			facing = signf(move_input)
			sprite.flip_h = facing < 0.0
		velocity.x = move_input * run_speed
		_apply_gravity(delta)

		if Input.is_action_just_pressed(&"dash") and not air_dash_used:
			_start_dash()
		elif jump_buffer_left > 0.0:
			_try_jump()

	if variable_jump_active:
		if velocity.y >= 0.0:
			variable_jump_active = false
		elif not Input.is_action_pressed(&"jump"):
			velocity.y = maxf(velocity.y, -short_jump_speed)
			variable_jump_active = false

	move_and_slide()
	if dash_time > 0.0:
		dash_trail.emit_frame(sprite, delta)
	if was_on_floor and not is_on_floor() and dash_time > 0.0:
		air_dash_used = true
	if not respawn_bounds.has_point(position):
		_respawn()
		return

	var landed := not was_on_floor and is_on_floor() and sprite.animation != &"Idle"
	if landed:
		_play_dust(get_real_velocity().x)
	if hurt:
		return
	if dash_time > 0.0:
		return
	if sprite.animation == &"Dash_Init" or sprite.animation == &"Dash_Loop":
		_play_motion_animation()
	if landed:
		sprite.play(&"Jump_Land")
	elif is_on_floor() and sprite.animation != &"Jump_Land":
		_play_ground_animation()
	elif not is_on_floor() and was_on_floor and not _is_air_animation():
		_play_motion_animation()


func take_hit(direction: float) -> void:
	if hurt:
		return
	hurt = true
	GameAudio.play(&"hurt")
	variable_jump_active = false
	coyote_time_left = 0.0
	dash_time = 0.0
	facing = -direction
	sprite.flip_h = facing < 0.0
	velocity = Vector2(direction * hit_speed, -hit_lift)
	sprite.play(&"Damaged")


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


func _start_dash() -> void:
	GameAudio.play(&"dash")
	variable_jump_active = false
	air_dash_used = not is_on_floor()
	dash_time = dash_duration
	velocity = Vector2(facing * dash_speed, 0.0)
	sprite.play(&"Dash_Init")
	dash_trail.emit_frame(sprite, 0.0, true)


func _try_jump() -> void:
	var ground_jump := coyote_time_left > 0.0
	if not ground_jump and double_jump_used:
		return

	if dash_time > 0.0:
		dash_time = 0.0
		velocity.x = move_input * run_speed
	jump_buffer_left = 0.0
	variable_jump_active = ground_jump
	if ground_jump:
		coyote_time_left = 0.0
		velocity.y = -jump_speed
		sprite.play(&"Jump_Init")
		_play_dust(velocity.x)
	else:
		double_jump_used = true
		velocity.y = -double_jump_speed
		sprite.play(&"DoubleJump_Init")


func _play_dust(horizontal_speed: float) -> void:
	var direction := 0.0 if is_zero_approx(horizontal_speed) else signf(horizontal_speed)
	dust.flip_h = (facing if direction == 0.0 else direction) < 0.0
	dust.global_position = to_global(Vector2(direction * DUST_OFFSET, 0.0))
	dust.stop()
	dust.show()
	dust.play(&"default")


func _play_ground_animation() -> void:
	sprite.play(&"Idle" if is_zero_approx(move_input) else &"Run")


func _play_motion_animation() -> void:
	if is_on_floor():
		_play_ground_animation()
	elif double_jump_used:
		sprite.play(&"DoubleJump_Loop")
	else:
		sprite.play(&"Jump_Loop")


func _is_air_animation() -> bool:
	return sprite.animation in [&"Jump_Init", &"Jump_Loop", &"DoubleJump_Init", &"DoubleJump_Loop"]


func _on_animation_finished() -> void:
	match sprite.animation:
		&"Jump_Init", &"DoubleJump_Init", &"Jump_Land":
			_play_motion_animation()
		&"Dash_Init":
			sprite.play(&"Dash_Loop")
		&"Damaged":
			hurt = false
			_play_motion_animation()


func _respawn() -> void:
	dash_trail.clear()
	position = spawn_position
	reset_physics_interpolation()
	velocity = Vector2.ZERO
	dash_time = 0.0
	coyote_time_left = 0.0
	jump_buffer_left = 0.0
	hurt = false
	variable_jump_active = false
	double_jump_used = false
	air_dash_used = false
	facing = 1.0
	sprite.flip_h = false
	sprite.play(&"Idle")
	dust.stop()
	dust.hide()
