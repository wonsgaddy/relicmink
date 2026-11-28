extends Node2D

const Dust := preload("res://scripts/jack_dust.gd")

@onready var boss = $RollingJack
@onready var player = $Player
@onready var health_bar: ProgressBar = $HUD/BossHealth
@onready var title: Label = $HUD/Title
@onready var pattern: Label = $HUD/Pattern
@onready var player_health: Label = $HUD/PlayerHealth
@onready var camera: Camera2D = $ArenaCamera

var lives := 5
var finished := false
@export var player_limits := Vector2(25.0, 935.0)
var shake_time := 0.0
var shake_strength := 0.0
var shake_phase := 0.0


func _ready() -> void:
	boss.health_changed.connect(_on_boss_health_changed)
	boss.pattern_changed.connect(_on_pattern_changed)
	boss.player_struck.connect(_on_player_struck)
	boss.defeated.connect(_on_defeated)
	boss.terrain_impact.connect(_on_terrain_impact)
	_on_boss_health_changed(boss.health, boss.max_health)
	_on_pattern_changed("접근 중 · 닿지 않도록 조심하세요")
	_update_lives()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		get_tree().reload_current_scene()


func _physics_process(delta: float) -> void:
	# Keep this self-contained test fight on the existing tile platform.
	player.position.x = clampf(player.position.x, player_limits.x, player_limits.y)
	_update_camera_shake(delta)


func _on_terrain_impact(point: Vector2, normal: Vector2, strength: float) -> void:
	if finished:
		return
	shake_time = 0.24
	shake_strength = maxf(shake_strength, minf(strength * 10.0, 16.0))
	var dust := Dust.new()
	dust.normal = normal
	dust.strength = strength
	add_child(dust)
	dust.global_position = point + normal * 3.0


func _update_camera_shake(delta: float) -> void:
	shake_time = maxf(0.0, shake_time - delta)
	if shake_time <= 0.0:
		camera.offset = Vector2.ZERO
		shake_strength = 0.0
		return
	shake_phase += delta * 83.0
	var envelope := pow(shake_time / 0.24, 2.0)
	var shake := Vector2(sin(shake_phase * 1.3), cos(shake_phase * 1.7)) * shake_strength * envelope
	camera.offset = (shake * camera.zoom).round() / camera.zoom


func _clear_impact_effects() -> void:
	shake_time = 0.0
	shake_strength = 0.0
	camera.offset = Vector2.ZERO
	get_tree().call_group(&"boss_dust", &"queue_free")
	get_tree().call_group(&"attack_warnings", &"queue_free")
	get_tree().call_group(&"dash_trails", &"clear")


func _on_boss_health_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	title.text = "구르는 잭%s  %d / %d" % [" · 분노" if boss.is_enraged() and current > 0 else "", current, maximum]


func _on_pattern_changed(message: String) -> void:
	if not finished:
		pattern.text = message


func _on_player_struck() -> void:
	if finished:
		return
	lives = maxi(0, lives - 1)
	_update_lives()
	if lives == 0:
		boss.roll_sound.stop()
		GameAudio.play(&"lose")
		finished = true
		_clear_impact_effects()
		$Player/RangedWeapon.enabled = false
		get_tree().call_group(&"player_projectiles", &"queue_free")
		get_tree().call_group(&"enemy_projectiles", &"queue_free")
		boss.set_physics_process(false)
		boss.sprite.play(&"Idle")
		player.set_physics_process(false)
		pattern.text = "도전 실패 · R 다시 도전"


func _on_defeated() -> void:
	finished = true
	_clear_impact_effects()
	$Player/RangedWeapon.enabled = false
	get_tree().call_group(&"player_projectiles", &"queue_free")
	get_tree().call_group(&"enemy_projectiles", &"queue_free")


func _update_lives() -> void:
	player_health.text = "체력 %d / 5" % lives


func _exit_tree() -> void:
	GameAudio.stop_all()
