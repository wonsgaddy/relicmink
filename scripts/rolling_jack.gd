extends CharacterBody2D
## Uses the original seven motions and one shared rectangular shape.

signal health_changed(current: int, maximum: int)
signal pattern_changed(message: String)
signal player_struck
signal defeated
signal terrain_impact(point: Vector2, normal: Vector2, strength: float)

enum State { WALK, WINDUP, ROLL, TIRED_INIT, TIRED, DRINK, DEFEATED, SPRAY, MINES }
enum RollMode { BOUNCE, STRAIGHT, STEEP, SKIPPING }
const LiquidOrb := preload("res://scripts/jack_liquid_orb.gd")
const Dust := preload("res://scripts/jack_dust.gd")
const LiquidMine := preload("res://scripts/jack_liquid_mine.gd")
const AttackWarning := preload("res://scripts/jack_attack_warning.gd")

@export var max_health := 200
@export var walk_speed := 24.0
@export var chase_speed := 175.0
@export var chase_distance := 260.0
@export var chase_stop_distance := 180.0
@export var chase_time_limit := 2.4
@export var roll_ground_gravity := 2400.0
@export var roll_floor_snap := 34.0
@export var roll_speed := 172.0
@export var enraged_roll_speed := 218.0
@export var launch_speed_multiplier := 1.5
@export var launch_acceleration := 3200.0
@export var impact_pause := 0.075
@export var gravity := 850.0
@export var max_fall_speed := 480.0
@export var walk_acceleration := 180.0
@export var tired_duration := 2.3
@export var enraged_tired_duration := 1.6
@export var walk_duration := 1.15
@export var enraged_walk_duration := 0.65
@export var normal_bounces := 6
@export var enraged_bounces := 8
@export_range(4, 24) var liquid_orb_count := 12
@export var liquid_orb_speed := 210.0
@export var max_liquid_orbs := 96
@export var straight_speed_multiplier := 1.25
@export var straight_rebounds := 3
@export var straight_time_limit := 10.0
## Two 16-pixel tiles; taller obstacles still cause a rebound.
@export_range(0.0, 48.0) var roll_step_height := 32.0
## Human frame 12 is index 11 in AnimatedSprite2D.
@export_range(1, 30) var roll_start_frame := 12
@export var arena_left := 46.0
@export var arena_right := 434.0
@export var player_path: NodePath = ^"../Player"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var contact: Area2D = $Contact
@onready var contact_shape: CollisionShape2D = $Contact/CollisionShape2D
@onready var player: CharacterBody2D = get_node(player_path)
@onready var sprite_base_scale := sprite.scale
@onready var sprite_base_position := sprite.position

var health: int
var state := State.WALK
var time_left := 0.0
var direction := -1.0
var rolls_left := 0
var hit_cooldown := 0.0
var contact_cooldown := 0.0
var roll_direction := Vector2.LEFT
var rolling_started := false
var current_roll_speed := 0.0
var burst_time := 0.0
var impact_time := 0.0
var walk_velocity := 0.0
var walk_elapsed := 0.0
var chasing := false
var roll_vertical_speed := 0.0
var visual_scale := Vector2.ONE
var visual_offset := Vector2.ZERO
var roll_mode := RollMode.BOUNCE
var next_roll_mode := RollMode.BOUNCE
var liquid_ring_index := 0
var exhaust_after_impact := false
var impact_normal := Vector2.UP
var trail_dust_time := 0.0
var enraged := false
var attack_cycle := 0
var combo_left := 0
var encounter_cycle := 0
var special_elapsed := 0.0
var special_shots := 0
var attack_warning: Variant = null
var spray_locked := false
var spray_direction := Vector2.LEFT
var mine_targets := PackedVector2Array()
var roll_sound: AudioStreamPlayer


func _ready() -> void:
	health = max_health
	roll_sound = GameAudio.create_roll_loop(self)
	# Keep imported animation resources intact for other instances.
	sprite.sprite_frames = sprite.sprite_frames.duplicate()
	for motion in [&"Rolling_Start", &"Tired_Init", &"Drink"]:
		sprite.sprite_frames.set_animation_loop(motion, false)
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)
	_enter(State.WALK)
	health_changed.emit(health, max_health)


func _exit_tree() -> void:
	roll_sound.stop()
	roll_sound.stream = null


func is_enraged() -> bool:
	# Once provoked, healing cannot reset the second phase.
	if health > 0 and health * 5 <= max_health * 3:
		enraged = true
	return enraged


func is_vulnerable() -> bool:
	return state in [State.TIRED_INIT, State.TIRED, State.DRINK]


func _physics_process(delta: float) -> void:
	if state == State.DEFEATED:
		return
	time_left -= delta
	hit_cooldown = maxf(0.0, hit_cooldown - delta)
	contact_cooldown = maxf(0.0, contact_cooldown - delta)
	sprite.modulate = Color(1.6, 1.1, 1.1) if hit_cooldown > 0.0 else Color.WHITE
	var rolling := state == State.ROLL or (state == State.WINDUP and rolling_started)
	if not rolling:
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
		velocity.x = 0.0
	match state:
		State.WALK:
			_face_player()
			walk_elapsed += delta
			var distance := absf(player.global_position.x - global_position.x)
			if distance > chase_distance:
				chasing = true
			elif distance <= chase_stop_distance:
				chasing = false
			var target_speed := maxf(walk_speed, chase_speed) if chasing else walk_speed
			var acceleration := maxf(walk_acceleration, 900.0) if chasing else walk_acceleration
			walk_velocity = move_toward(walk_velocity, direction * target_speed, acceleration * delta)
			velocity.x = walk_velocity
			if time_left <= 0.0 and (not chasing or walk_elapsed >= chase_time_limit):
				_start_encounter_attack()
		State.WINDUP:
			# Direction is locked at the start of the tell; no homing mid-roll.
			pass
		State.ROLL:
			pass
		State.TIRED:
			if time_left <= 0.0:
				_enter(State.DRINK)
		State.SPRAY:
			special_elapsed += delta * (1.15 if is_enraged() else 1.0)
			_update_spray_warning()
			while special_shots < 3 and special_elapsed >= 0.65 + special_shots * 0.45:
				_emit_aimed_spray()
				special_shots += 1
				if special_shots < 3:
					_begin_spray_warning()
			if time_left <= 0.0:
				_enter(State.TIRED_INIT)
		State.MINES:
			special_elapsed += delta
			if is_instance_valid(attack_warning):
				attack_warning.progress = clampf(special_elapsed / (0.55 if is_enraged() else 0.8), 0.0, 1.0)
			if special_shots == 0 and special_elapsed >= (0.55 if is_enraged() else 0.8):
				_place_liquid_mines()
				special_shots = 1
			if time_left <= 0.0:
				_enter(State.TIRED_INIT)
	rolling = state == State.ROLL or (state == State.WINDUP and rolling_started)
	if rolling:
		_move_rolling(delta)
	else:
		move_and_slide()
		if state == State.WALK and is_on_wall():
			for index in range(get_slide_collision_count()):
				if _try_roll_step(get_slide_collision(index)):
					break
		global_position.x = clampf(global_position.x, arena_left, arena_right)
	_update_motion_visuals(delta)
	_check_contact()


func _on_frame_changed() -> void:
	if state == State.WINDUP and not rolling_started and sprite.frame >= roll_start_frame - 1:
		_start_rolling()


func _start_rolling() -> void:
	GameAudio.play(&"launch")
	rolling_started = true
	current_roll_speed = _base_roll_speed() * 0.35
	burst_time = 0.12
	visual_scale = Vector2(1.28, 0.8)
	visual_offset = Vector2.ZERO
	# Prefer ground travel; only the hop variants briefly leave the floor.
	roll_direction = Vector2(direction, 0.0)
	roll_vertical_speed = 0.0
	if roll_mode == RollMode.STEEP and player.global_position.y < global_position.y - 96.0:
		roll_vertical_speed = -_base_roll_speed() * 0.65
	elif roll_mode == RollMode.SKIPPING:
		roll_vertical_speed = -_base_roll_speed() * 0.22


func _move_rolling(delta: float) -> void:
	if state not in [State.WINDUP, State.ROLL]:
		return
	if impact_time > 0.0:
		impact_time = maxf(0.0, impact_time - delta)
		velocity = Vector2.ZERO
		if impact_time <= 0.0:
			sprite.speed_scale = 1.0
			visual_offset = Vector2.ZERO
			visual_scale = Vector2(1.3, 0.8) if absf(impact_normal.x) > 0.5 else Vector2(0.82, 1.28)
			if exhaust_after_impact:
				_finish_roll()
		return
	sprite.speed_scale = 1.0
	var base_speed := _base_roll_speed()
	if burst_time > 0.0:
		burst_time = maxf(0.0, burst_time - delta)
		current_roll_speed = move_toward(current_roll_speed, base_speed * launch_speed_multiplier, launch_acceleration * delta)
	else:
		current_roll_speed = move_toward(current_roll_speed, base_speed, base_speed * 2.5 * delta)
	velocity = Vector2(signf(roll_direction.x) * current_roll_speed, roll_vertical_speed)
	# A collision consumes this tick's remaining travel for the impact pause.
	var collision := move_and_collide(Vector2(velocity.x * delta, 0))
	if collision != null and _try_roll_step(collision):
		collision = null
	if collision == null:
		collision = _follow_roll_floor(delta)
	if collision != null:
		var normal := collision.get_normal()
		GameAudio.play(&"impact")
		_emit_liquid_ring()
		roll_direction = roll_direction.bounce(normal).normalized()
		roll_direction = Vector2(signf(roll_direction.x), 0)
		roll_vertical_speed = 0.0
		if roll_mode == RollMode.SKIPPING and absf(normal.x) > 0.5:
			roll_vertical_speed = -base_speed * 0.22
		direction = signf(roll_direction.x)
		sprite.flip_h = direction > 0.0
		rolls_left -= 1
		pattern_changed.emit("프레임 반사! · 2층도 조심하세요")
		exhaust_after_impact = rolls_left <= 0
		var impact_strength := (1.3 if roll_mode == RollMode.STRAIGHT else 1.0) * (1.2 if is_enraged() else 1.0)
		terrain_impact.emit(collision.get_position(), normal, impact_strength)
		# Compress against the surface for a few physics ticks, then fire out.
		impact_time = impact_pause
		impact_normal = normal
		current_roll_speed = base_speed * 0.45
		burst_time = 0.1
		sprite.speed_scale = 0.0
		visual_scale = Vector2(0.58, 1.25) if absf(normal.x) > 0.5 else Vector2(1.25, 0.58)
		visual_offset = Vector2(-normal.x * 24.0 * sprite_base_scale.x, 0.0)
		velocity = Vector2.ZERO
	else:
		_emit_roll_dust(delta)
	# Safety limit for unusual tile layouts; animation time is separate.
	if state == State.ROLL and time_left <= 0.0 and impact_time <= 0.0:
		_finish_roll()
		velocity = Vector2.ZERO


func _follow_roll_floor(delta: float) -> KinematicCollision2D:
	# Separate vertical travel so ordinary floor contact never spends a bounce.
	roll_vertical_speed = minf(roll_vertical_speed + roll_ground_gravity * delta, max_fall_speed)
	var fall_speed := roll_vertical_speed
	var collision := move_and_collide(Vector2(0, roll_vertical_speed * delta))
	if collision != null:
		roll_vertical_speed = 0.0
		if collision.get_normal().y < -0.9:
			if fall_speed > 220.0:
				return collision
			return null
		return collision
	# Follow descending steps, but let gravity handle genuine platform drops.
	if roll_vertical_speed >= 0.0 and roll_vertical_speed <= 220.0:
		var floor_hit := KinematicCollision2D.new()
		if test_move(global_transform, Vector2(0, roll_floor_snap), floor_hit, 0.001) and floor_hit.get_normal().y < -0.9:
			global_position += floor_hit.get_travel()
			roll_vertical_speed = 0.0
	return null


func _try_roll_step(collision: KinematicCollision2D) -> bool:
	# Only climb a low wall while supported by terrain, never in midair.
	if roll_step_height <= 0.0 or absf(collision.get_normal().x) < 0.9:
		return false
	var floor_hit := KinematicCollision2D.new()
	if not test_move(global_transform, Vector2(0, 6), floor_hit, 0.001) or floor_hit.get_normal().y > -0.9:
		return false
	var forward := Vector2(collision.get_remainder().x, 0)
	if absf(forward.x) < 0.01:
		return false
	var raised := global_transform
	var lift := Vector2(0, -roll_step_height - 0.2)
	var lift_hit := KinematicCollision2D.new()
	if test_move(raised, lift, lift_hit, 0.001):
		# A nearby ceiling may still leave enough room for a shorter step.
		if lift_hit.get_normal().y < 0.9 or lift_hit.get_travel().y > -0.5:
			return false
		lift = lift_hit.get_travel()
	raised.origin += lift
	if test_move(raised, forward, null, 0.001):
		return false
	raised.origin += forward
	var landing := KinematicCollision2D.new()
	if not test_move(raised, Vector2(0, roll_step_height + 6.2), landing, 0.001) or landing.get_normal().y > -0.9:
		return false
	var destination := raised.origin + landing.get_travel()
	var rise := global_position.y - destination.y
	if rise < 0.5 or rise > roll_step_height + 0.1:
		return false
	# All three segments are clear. Keep the launch momentum and bounce budget.
	global_position = destination
	return true


func _start_encounter_attack() -> void:
	encounter_cycle += 1
	combo_left = 0
	match encounter_cycle % 4:
		2:
			_enter(State.SPRAY)
		0:
			_enter(State.MINES)
		_:
			_start_attack_cycle()


func _start_attack_cycle() -> void:
	attack_cycle += 1
	combo_left = 1 if is_enraged() and attack_cycle % 2 == 0 else 0
	var selected := next_roll_mode
	next_roll_mode = (next_roll_mode + 1) % RollMode.size()
	_prepare_roll(selected)


func _prepare_roll(mode: int, followup := false) -> void:
	roll_mode = mode
	rolls_left = enraged_bounces if is_enraged() else normal_bounces
	if roll_mode == RollMode.STRAIGHT:
		rolls_left = straight_rebounds + (1 if is_enraged() else 0)
	if followup:
		rolls_left = 2 if roll_mode == RollMode.STRAIGHT else 3
	_enter(State.WINDUP)


func _finish_roll() -> void:
	velocity = Vector2.ZERO
	if combo_left > 0:
		combo_left -= 1
		_prepare_roll(RollMode.STEEP if roll_mode == RollMode.STRAIGHT else RollMode.STRAIGHT, true)
	else:
		_enter(State.TIRED_INIT)


func _base_roll_speed() -> float:
	var base := enraged_roll_speed if is_enraged() else roll_speed
	return base * (straight_speed_multiplier if roll_mode == RollMode.STRAIGHT else 1.0)


func _emit_liquid_ring() -> void:
	var count := liquid_orb_count + (4 if is_enraged() else 0)
	count = mini(count, maxi(0, max_liquid_orbs - get_tree().get_nodes_in_group(&"enemy_projectiles").size()))
	if count <= 0:
		return
	GameAudio.play(&"burst")
	var speed := liquid_orb_speed * (1.3 if is_enraged() else 1.0)
	# Rotate successive rings by half a gap rather than stacking every lane.
	var offset := (liquid_ring_index % 2) * PI / count
	liquid_ring_index += 1
	var focused_ring := is_enraged() and liquid_ring_index % 2 == 0
	var predicted_target := player.global_position + player.velocity.limit_length(420.0) * 0.18
	var aimed_direction := (predicted_target - contact_shape.global_position).normalized()
	for index in range(count):
		var orb := LiquidOrb.new()
		orb.velocity = Vector2.from_angle(TAU * index / count + offset) * speed
		if roll_mode == RollMode.STEEP and index % 2:
			orb.velocity *= 0.72
		if focused_ring and index < 3:
			# Reuse three slots in the ring instead of increasing projectile count.
			orb.velocity = aimed_direction.rotated((index - 1) * 0.2) * speed * 1.1
		orb.shooter = self
		orb.phase = float(index % 4)
		get_parent().add_child(orb)
		orb.global_position = contact_shape.global_position
	if roll_mode == RollMode.SKIPPING and liquid_ring_index % 2 == 0:
		var aim := (player.global_position - contact_shape.global_position).normalized()
		var fan_count := mini(3, maxi(0, max_liquid_orbs - get_tree().get_nodes_in_group(&"enemy_projectiles").size()))
		for index in range(fan_count):
			var orb := LiquidOrb.new()
			orb.velocity = aim.rotated((index - 1) * 0.22) * speed * 1.15
			orb.shooter = self
			orb.phase = float(index)
			get_parent().add_child(orb)
			orb.global_position = contact_shape.global_position


func _emit_roll_dust(delta: float) -> void:
	trail_dust_time -= delta
	if trail_dust_time > 0.0:
		return
	trail_dust_time = 0.065
	if get_tree().get_nodes_in_group(&"boss_dust").size() >= 14:
		return
	var bottom := contact_shape.global_position + Vector2(0, contact_shape.shape.get_rect().size.y * 0.5)
	var query := PhysicsRayQueryParameters2D.create(bottom - Vector2(0, 4), bottom + Vector2(0, 9), 1)
	var floor_hit := get_world_2d().direct_space_state.intersect_ray(query)
	if floor_hit.is_empty():
		return
	var dust := Dust.new()
	dust.count = 4
	dust.strength = 0.6
	dust.rolling_trail = true
	dust.drift = Vector2(-roll_direction.x * current_roll_speed * 0.22, 0)
	get_parent().add_child(dust)
	dust.global_position = floor_hit["position"] - Vector2(roll_direction.x * 30.0, 0)


func _remaining_projectiles() -> int:
	return maxi(0, max_liquid_orbs - get_tree().get_nodes_in_group(&"enemy_projectiles").size())


func _emit_aimed_spray() -> void:
	GameAudio.play(&"spray")
	if not spray_locked:
		_track_spray_target()
	var origin := _spray_origin()
	var aim := spray_direction
	var count := mini(7 if is_enraged() else 5, _remaining_projectiles())
	for index in range(count):
		var orb := LiquidOrb.new()
		orb.shooter = self
		orb.velocity = aim.rotated((index - (count - 1) * 0.5) * 0.15) * liquid_orb_speed * (1.3 if is_enraged() else 1.12)
		orb.phase = float(index % 4)
		get_parent().add_child(orb)
		orb.global_position = origin
	visual_scale = Vector2(0.9, 1.12)
	_clear_attack_warning()
	spray_locked = false


func _spray_origin() -> Vector2:
	return contact_shape.global_position + Vector2(direction * 35.0, -20.0)


func _track_spray_target() -> void:
	_face_player()
	var prediction := player.global_position + player.velocity.limit_length(420.0) * 0.12
	spray_direction = (prediction - _spray_origin()).normalized()


func _clear_attack_warning() -> void:
	if is_instance_valid(attack_warning):
		attack_warning.queue_free()
	attack_warning = null


func _begin_spray_warning() -> void:
	_clear_attack_warning()
	spray_locked = false
	_track_spray_target()
	attack_warning = AttackWarning.new()
	attack_warning.spread = 0.45 if is_enraged() else 0.3
	attack_warning.heading = spray_direction
	get_parent().add_child(attack_warning)
	attack_warning.global_position = _spray_origin()
	attack_warning.refresh_geometry()


func _update_spray_warning() -> void:
	if special_shots >= 3:
		return
	var just_locked := false
	if not spray_locked:
		_track_spray_target()
		if special_elapsed >= 0.65 + special_shots * 0.45 - 0.25:
			spray_locked = true
			just_locked = true
	if is_instance_valid(attack_warning):
		attack_warning.global_position = _spray_origin()
		attack_warning.heading = spray_direction
		attack_warning.locked = spray_locked
		attack_warning.progress = clampf(1.0 - (0.65 + special_shots * 0.45 - special_elapsed) / (0.65 if special_shots == 0 else 0.45), 0.0, 1.0)
		if just_locked:
			attack_warning.refresh_geometry()


func _find_mine_targets() -> PackedVector2Array:
	var targets := PackedVector2Array()
	var half_width := contact_shape.shape.get_rect().size.x * 0.5
	for offset in [-120.0, 0.0, 120.0]:
		var x := clampf(player.global_position.x + offset, arena_left - half_width + 12.0, arena_right + half_width - 12.0)
		var start := Vector2(x, maxf(20.0, player.global_position.y - 20.0))
		var query := PhysicsRayQueryParameters2D.create(start, start + Vector2(0, 800), 1)
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		targets.append(hit["position"])
	return targets


func _place_liquid_mines() -> void:
	if mine_targets.is_empty():
		mine_targets = _find_mine_targets()
	for point in mine_targets:
		if _remaining_projectiles() <= 0:
			break
		var mine := LiquidMine.new()
		mine.shooter = self
		mine.arm_delay = 0.7 if is_enraged() else 0.9
		get_parent().add_child(mine)
		mine.global_position = point
	_clear_attack_warning()


func emit_mine_burst(point: Vector2) -> void:
	if state == State.DEFEATED or get_parent().get("finished") == true:
		return
	GameAudio.play(&"burst")
	var count := mini(9 if is_enraged() else 7, _remaining_projectiles())
	for index in range(count):
		var angle := lerpf(-PI, 0.0, float(index) / maxi(1, count - 1))
		var orb := LiquidOrb.new()
		orb.shooter = self
		orb.velocity = Vector2.from_angle(angle) * liquid_orb_speed * (1.15 if is_enraged() else 1.0)
		orb.phase = float(index % 4)
		get_parent().add_child(orb)
		orb.global_position = point - Vector2(0, 8)


func _update_motion_visuals(delta: float) -> void:
	var rolling := state == State.ROLL or (state == State.WINDUP and rolling_started)
	if GameAudio.enabled and rolling and impact_time <= 0.0 and get_parent().get("finished") != true:
		roll_sound.pitch_scale = clampf(0.7 + current_roll_speed / maxf(_base_roll_speed(), 1.0) * 0.35, 0.75, 1.35)
		if not roll_sound.playing:
			roll_sound.play()
	else:
		roll_sound.stop()
	if state == State.WINDUP and not rolling_started:
		var progress := (float(sprite.frame) + sprite.frame_progress) / maxf(1.0, roll_start_frame - 1.0)
		var charge := smoothstep(0.35, 1.0, progress)
		visual_scale = Vector2(1.0 + 0.12 * charge, 1.0 - 0.18 * charge)
		visual_offset = Vector2(-direction * 12.5 * sprite_base_scale.x * charge, 0.0)
	elif impact_time <= 0.0:
		visual_scale = visual_scale.lerp(Vector2.ONE, 1.0 - exp(-12.0 * delta))
		visual_offset = visual_offset.lerp(Vector2.ZERO, 1.0 - exp(-20.0 * delta))
	sprite.scale = sprite_base_scale * visual_scale
	# Keep the feet anchored while compressing the existing sprite.
	sprite.position = sprite_base_position + visual_offset + Vector2(0.0, 90.0 * sprite_base_scale.y * (1.0 - visual_scale.y))


func _check_contact() -> void:
	if state == State.DEFEATED or not contact.overlaps_body(player) or player.hurt:
		return
	if contact_cooldown <= 0.0:
		contact_cooldown = 1.1
		hit_player_from(global_position)


func hit_player_from(source_position: Vector2) -> bool:
	if state == State.DEFEATED or player.hurt or get_parent().get("finished") == true:
		return false
	var knockback := -1.0 if player.global_position.x < source_position.x else 1.0
	player.take_hit(knockback)
	player_struck.emit()
	return true


func take_projectile_hit(damage: int = 1) -> bool:
	if state in [State.DEFEATED, State.WINDUP, State.ROLL] or hit_cooldown > 0.0 or damage <= 0:
		return false
	health = maxi(0, health - damage * (2 if is_vulnerable() else 1))
	hit_cooldown = 0.12
	health_changed.emit(health, max_health)
	if health == 0:
		_enter(State.DEFEATED)
	else:
		GameAudio.play(&"boss_hit")
	return true


func _face_player() -> void:
	if not is_equal_approx(player.global_position.x, global_position.x):
		direction = signf(player.global_position.x - global_position.x)
	sprite.flip_h = direction > 0.0


func _enter(next: State) -> void:
	_clear_attack_warning()
	mine_targets.clear()
	state = next
	if next != State.ROLL:
		roll_sound.stop()
	if next not in [State.ROLL, State.WINDUP]:
		exhaust_after_impact = false
		impact_time = 0.0
		burst_time = 0.0
		current_roll_speed = 0.0
		sprite.speed_scale = 1.0
	match state:
		State.WALK:
			walk_velocity = 0.0
			walk_elapsed = 0.0
			chasing = absf(player.global_position.x - global_position.x) > chase_distance
			time_left = enraged_walk_duration if is_enraged() else walk_duration
			sprite.play(&"Walk")
			pattern_changed.emit("접근 중 · 구르기를 유도하세요")
		State.WINDUP:
			GameAudio.play(&"charge")
			_face_player()
			rolling_started = false
			exhaust_after_impact = false
			impact_time = 0.0
			sprite.speed_scale = 1.0
			velocity.x = 0.0
			sprite.play(&"Rolling_Start")
			pattern_changed.emit("구르기 · 돌진을 피하세요!")
		State.ROLL:
			time_left = straight_time_limit if roll_mode == RollMode.STRAIGHT else 8.0
			sprite.flip_h = direction > 0.0
			sprite.play(&"Rolling_Loop")
		State.TIRED_INIT:
			rolling_started = false
			sprite.play(&"Tired_Init")
			pattern_changed.emit("빈틈! · 사격하세요")
		State.TIRED:
			time_left = enraged_tired_duration if is_enraged() else tired_duration
			sprite.play(&"Tired_Loop")
		State.DRINK:
			GameAudio.play(&"drink")
			sprite.speed_scale = 1.45 if is_enraged() else 1.25
			sprite.play(&"Drink")
			pattern_changed.emit("마시기 · 사격 기회")
		State.SPRAY, State.MINES:
			if state == State.MINES:
				GameAudio.play(&"mine")
			special_elapsed = 0.0
			special_shots = 0
			time_left = 1.95 if is_enraged() else 2.2
			sprite.play(&"Drink")
			pattern_changed.emit("")
			if state == State.SPRAY:
				_begin_spray_warning()
			else:
				mine_targets = _find_mine_targets()
				attack_warning = AttackWarning.new()
				attack_warning.kind = AttackWarning.Kind.GROUND
				attack_warning.points = mine_targets
				get_parent().add_child(attack_warning)
		State.DEFEATED:
			GameAudio.play(&"win")
			velocity = Vector2.ZERO
			sprite.play(&"Tired_Loop")
			sprite.modulate = Color(0.6, 0.6, 0.6, 0.75)
			pattern_changed.emit("구르는 잭 격파! · R 다시 도전")
			defeated.emit()


func _on_animation_finished() -> void:
	match state:
		State.WINDUP:
			_enter(State.ROLL)
		State.TIRED_INIT:
			_enter(State.TIRED)
		State.DRINK:
			health = mini(max_health, health + 1)
			health_changed.emit(health, max_health)
			_enter(State.WALK)
