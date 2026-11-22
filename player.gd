extends CharacterBody2D

const RUN_SPEED := 64.0
const JUMP_SPEED := 200.0
const DOUBLE_JUMP_SPEED := 285.0
const COYOTE_TIME := 0.10
const JUMP_BUFFER_TIME := 0.12
const DUST_OFFSET := 6.0
const GRAVITY := 850.0
const MAX_FALL_SPEED := 480.0
const DASH_SPEED := 130.0
const DASH_DURATION := 0.20
const HIT_SPEED := 155.0
const HIT_LIFT := 185.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var dust: AnimatedSprite2D = $Dust
@onready var spawn_position := position

var facing := 1.0
var dash_time := 0.0
var coyote_time_left := 0.0
var jump_buffer_left := 0.0
var air_dash_used := false
var double_jump_used := false
var hurt := false
var move_input := 0.0


func _ready() -> void:
	sprite.animation_finished.connect(_on_animation_finished)
	dust.animation_finished.connect(dust.hide)
	sprite.play(&"Idle")


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
		dash_time = maxf(0.0, dash_time - delta)
	elif hurt:
		velocity.x = move_toward(velocity.x, 0.0, 420.0 * delta)
		_apply_gravity(delta)
	else:
		if not is_zero_approx(move_input):
			facing = signf(move_input)
			sprite.flip_h = facing < 0.0
		velocity.x = move_input * RUN_SPEED
		_apply_gravity(delta)

		if Input.is_action_just_pressed(&"dash") and not air_dash_used:
			_start_dash()
		elif jump_buffer_left > 0.0:
			_try_jump()

	move_and_slide()
	if position.y > 320.0 or position.x < -40.0 or position.x > 520.0:
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
	coyote_time_left = 0.0
	dash_time = 0.0
	facing = -direction
	sprite.flip_h = facing < 0.0
	velocity = Vector2(direction * HIT_SPEED, -HIT_LIFT)
	sprite.play(&"Damaged")


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)


func _start_dash() -> void:
	air_dash_used = true
	dash_time = DASH_DURATION
	velocity = Vector2(facing * DASH_SPEED, 0.0)
	sprite.play(&"Dash_Init")


func _try_jump() -> void:
	if coyote_time_left > 0.0:
		coyote_time_left = 0.0
		jump_buffer_left = 0.0
		velocity.y = -JUMP_SPEED
		sprite.play(&"Jump_Init")
		_play_dust(velocity.x)
	elif not double_jump_used:
		jump_buffer_left = 0.0
		double_jump_used = true
		velocity.y = -DOUBLE_JUMP_SPEED
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
	position = spawn_position
	reset_physics_interpolation()
	velocity = Vector2.ZERO
	dash_time = 0.0
	coyote_time_left = 0.0
	jump_buffer_left = 0.0
	hurt = false
	double_jump_used = false
	air_dash_used = false
	facing = 1.0
	sprite.flip_h = false
	sprite.play(&"Idle")
	dust.stop()
	dust.hide()
