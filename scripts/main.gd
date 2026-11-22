extends Node2D

const Layout = preload("res://scripts/map_layout.gd")
const CATALOG = preload("res://maps/prefabs.tres")
const PLAYER_SCENE = preload("res://Player.tscn")

@export var generation_seed: int = 0
@export var main_path_rooms := Vector2i(6, 8)
@export var branch_count := Vector2i(1, 3)
@export var branch_depth := Vector2i(1, 2)

@onready var terrain: TileMapLayer = $Terrain
@onready var decoration: TileMapLayer = $Decoration
@onready var status: Label = $HUD/Status

var active_seed: int
var layout := Layout.new()
var player: CharacterBody2D
var goal_bounds: Rect2
var reached_goal := false


func _ready() -> void:
	active_seed = generation_seed if generation_seed != 0 else randi()
	if not layout.generate(CATALOG.prefabs, active_seed, main_path_rooms, branch_count, branch_depth):
		status.text = "Could not generate a map (seed %d)" % active_seed
		push_error("No layout for seed %d. Check the room exits and generation settings." % active_seed)
		return

	var map_bounds := Rect2i()
	for placed in layout.placements:
		var prefab: Dictionary = placed.prefab
		var origin: Vector2i = placed.origin
		var bounds := Rect2i(origin, prefab.size)
		map_bounds = bounds if not map_bounds.has_area() else map_bounds.merge(bounds)
		_place_tiles(terrain, origin, prefab.terrain, 0)
		_place_tiles(decoration, origin, prefab.decoration, 1)
		for index in prefab.exits.size():
			if not placed.joined.has(index):
				var cap: Dictionary = prefab.exits[index]
				_place_tiles(terrain, origin, cap.terrain, 0)
				_place_tiles(decoration, origin, cap.decoration, 1)

	var start: Dictionary = layout.placements[0]
	var goal: Dictionary = layout.placements[layout.goal_index]
	var tile_size := Vector2(terrain.tile_set.tile_size)
	goal_bounds = Rect2(Vector2(goal.origin) * tile_size, Vector2(goal.prefab.size) * tile_size)
	_mark_goal(terrain.map_to_local(goal.origin + goal.prefab.spawn))

	player = PLAYER_SCENE.instantiate()
	player.position = terrain.map_to_local(start.origin + start.prefab.spawn) - Vector2(0, 2)
	player.respawn_bounds = Rect2(Vector2(map_bounds.position) * tile_size, Vector2(map_bounds.size) * tile_size).grow(96.0)
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	player.add_child(camera)
	add_child(player)
	status.text = "Find the goal  /  Seed %d" % active_seed


func _physics_process(_delta: float) -> void:
	if not reached_goal and is_instance_valid(player) and goal_bounds.has_point(player.position):
		reached_goal = true
		status.text = "Goal reached  /  Seed %d" % active_seed


func _place_tiles(layer: TileMapLayer, origin: Vector2i, tiles: PackedInt32Array, source: int) -> void:
	for index in range(0, tiles.size(), 4):
		var cell := Vector2i(tiles[index], tiles[index + 1])
		var atlas := Vector2i(tiles[index + 2], tiles[index + 3])
		layer.set_cell(origin + cell, source, atlas)


func _mark_goal(at: Vector2) -> void:
	var marker := Label.new()
	marker.text = "GOAL"
	marker.position = at + Vector2(-20, -25)
	add_child(marker)
