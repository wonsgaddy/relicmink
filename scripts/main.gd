@tool
extends Node2D

const AnimatedDoor = preload("res://scripts/animated_passage_door.gd")
const DOOR_ATLAS = preload("res://sprites/door.png")
const TerrainRules = preload("res://scripts/terrain_rules.gd")
const Layout = preload("res://scripts/map_layout.gd")
const CATALOG = preload("res://maps/prefabs.tres")
const PLAYER_SCENE = preload("res://Player.tscn")
const CAMERA_RESPONSE := 12.0

@export var generation_seed: int = 0
@export var main_path_rooms := Vector2i(6, 8)
@export var branch_count := Vector2i(1, 3)
@export var branch_depth := Vector2i(1, 2)
@export_range(0.01, 1.0, 0.01) var door_seconds_per_frame := 0.08
@export_tool_button("Generate Map Preview") var generate_preview_button := _generate_preview
@export_tool_button("Clear Map Preview") var clear_preview_button := _clear_preview

@onready var terrain: TileMapLayer = $Terrain
@onready var decoration: TileMapLayer = $Decoration
@onready var status: Label = $HUD/Status

var active_seed: int
var layout := Layout.new()
var player: CharacterBody2D
var goal_bounds: Rect2
var reached_goal := false

var camera: Camera2D
var room_bounds: Array[Rect2] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	active_seed = _resolve_seed()
	if not layout.generate(CATALOG.prefabs, active_seed, main_path_rooms, branch_count, branch_depth):
		status.text = "Could not generate a map (seed %d)" % active_seed
		push_error("No layout for seed %d. Check the room exits and generation settings." % active_seed)
		return

	var map_bounds := _draw_layout(layout, terrain, decoration)
	var start: Dictionary = layout.placements[0]
	var goal: Dictionary = layout.placements[layout.goal_index]
	var tile_size := Vector2(terrain.tile_set.tile_size)
	goal_bounds = Rect2(Vector2(goal.origin) * tile_size, Vector2(goal.prefab.size) * tile_size)
	_mark_goal(terrain.map_to_local(goal.origin + goal.prefab.spawn))

	for placed in layout.placements:
		if placed.prefab.kind == "room":
			room_bounds.append(Rect2(Vector2(placed.origin) * tile_size, Vector2(placed.prefab.size) * tile_size))
	player = PLAYER_SCENE.instantiate()
	player.position = terrain.map_to_local(start.origin + start.prefab.spawn) - Vector2(0, 2)
	player.respawn_bounds = Rect2(Vector2(map_bounds.position) * tile_size, Vector2(map_bounds.size) * tile_size).grow(96.0)
	camera = Camera2D.new()
	camera.name = "Camera2D"
	add_child(player)
	_place_doors(layout, self, terrain, player)
	add_child(camera)
	_update_camera(0.0, true)
	status.text = "Find the goal  /  Seed %d" % active_seed


func _draw_layout(generated, ground: TileMapLayer, decor: TileMapLayer) -> Rect2i:
	var map_bounds := Rect2i()
	var terrain_cells: Dictionary[Vector2i, Vector3i] = {}
	for placed in generated.placements:
		var prefab: Dictionary = placed.prefab
		var origin: Vector2i = placed.origin
		var bounds := Rect2i(origin, prefab.size)
		map_bounds = bounds if not map_bounds.has_area() else map_bounds.merge(bounds)
		_collect_tiles(terrain_cells, origin, prefab.terrain)
		_place_decoration(decor, origin, prefab.decoration)
		for index in prefab.exits.size():
			var door: Dictionary = prefab.exits[index]
			if not placed.joined.has(index):
				_collect_tiles(terrain_cells, origin, door.terrain)
				_place_decoration(decor, origin, door.decoration)
			else:
				var opening: Vector2i = placed.openings[index]
				if opening.y < door.span:
					var open_cells := Rect2i(door.anchor + door.tangent * opening.x, Vector2i.ONE + door.tangent * (opening.y - 1))
					_collect_tiles(terrain_cells, origin, door.terrain, open_cells)

	_apply_terrain(ground, terrain_cells)
	return map_bounds


func _place_doors(generated, parent: Node2D, ground: TileMapLayer, tracked_player: Node2D = null) -> void:
	for placed in generated.placements:
		for index in placed.joined:
			var door: Dictionary = placed.prefab.exits[index]
			if door.direction != Vector2i.RIGHT and door.direction != Vector2i.DOWN:
				continue
			var opening: Vector2i = placed.openings[index]
			var anchor: Vector2i = placed.origin + door.anchor + door.tangent * opening.x
			var animated := AnimatedDoor.new()
			animated.position = ground.map_to_local(anchor) - Vector2(ground.tile_set.tile_size) / 2.0
			animated.configure(door.tangent, opening.y, DOOR_ATLAS, door_seconds_per_frame, tracked_player, tracked_player == null)
			parent.add_child(animated)


func _resolve_seed() -> int:
	return generation_seed if generation_seed != 0 else randi()


func _generate_preview() -> void:
	_clear_preview()
	var seed_value := _resolve_seed()
	var preview_layout := Layout.new()
	var catalog := ResourceLoader.load("res://maps/prefabs.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	if not preview_layout.generate(catalog.prefabs, seed_value, main_path_rooms, branch_count, branch_depth):
		push_error("No preview layout for seed %d. Check the generation settings." % seed_value)
		return

	var preview := Node2D.new()
	preview.name = "MapPreview"
	add_child(preview)
	var ground := _make_preview_layer(preview, "TerrainPreview")
	var decor := _make_preview_layer(preview, "DecorationPreview")
	_draw_layout(preview_layout, ground, decor)
	_place_doors(preview_layout, preview, ground)
	print("Map preview seed: %d" % seed_value)


func _make_preview_layer(parent: Node2D, layer_name: String) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = terrain.tile_set
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.collision_enabled = false
	parent.add_child(layer)
	return layer


func _clear_preview() -> void:
	var preview := get_node_or_null("MapPreview")
	if preview != null:
		remove_child(preview)
		preview.queue_free()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint() and is_instance_valid(player):
		_update_camera(delta)


func _update_camera(delta: float, snap := false) -> void:
	var target_center := player.position
	var target_zoom := 1.0
	var view_size := get_viewport_rect().size
	for room in room_bounds:
		if not room.has_point(player.position):
			continue
		target_zoom = maxf(1.0, maxf(view_size.x / room.size.x, view_size.y / room.size.y))
		var half_view := (view_size / (2.0 * target_zoom)).min(room.size / 2.0)
		target_center = target_center.clamp(room.position + half_view, room.end - half_view)
		break

	var weight := 1.0 - exp(-CAMERA_RESPONSE * delta)
	if snap or camera.position.distance_squared_to(target_center) < 0.01:
		camera.position = target_center
	else:
		camera.position = camera.position.lerp(target_center, weight)
	if snap or absf(camera.zoom.x - target_zoom) < 0.0001:
		camera.zoom = Vector2.ONE * target_zoom
	else:
		camera.zoom = Vector2.ONE * lerpf(camera.zoom.x, target_zoom, weight)
	camera.force_update_scroll()


func _physics_process(_delta: float) -> void:
	if not Engine.is_editor_hint() and not reached_goal and is_instance_valid(player) and goal_bounds.has_point(player.position):
		reached_goal = true
		status.text = "Goal reached  /  Seed %d" % active_seed


func _collect_tiles(cells: Dictionary[Vector2i, Vector3i], origin: Vector2i, tiles: PackedInt32Array, open_cells := Rect2i()) -> void:
	for index in range(0, tiles.size(), 5):
		var cell := Vector2i(tiles[index], tiles[index + 1])
		if open_cells.has_point(cell):
			continue
		cells[origin + cell] = Vector3i(tiles[index + 2], tiles[index + 3], tiles[index + 4])


func _place_decoration(layer: TileMapLayer, origin: Vector2i, tiles: PackedInt32Array) -> void:
	for index in range(0, tiles.size(), 5):
		var cell := origin + Vector2i(tiles[index], tiles[index + 1])
		layer.set_cell(cell, tiles[index + 2], Vector2i(tiles[index + 3], tiles[index + 4]))


func _apply_terrain(layer: TileMapLayer, cells: Dictionary[Vector2i, Vector3i]) -> void:
	var groups: Dictionary[Vector2i, Array] = {}
	for cell in cells:
		var tile := cells[cell]
		if tile.x == -1:
			var key := Vector2i(tile.y, tile.z)
			if not groups.has(key):
				var positions: Array[Vector2i] = []
				groups[key] = positions
			groups[key].append(cell)
			tile = CATALOG.terrain_defaults[key]
		layer.set_cell(cell, tile.x, Vector2i(tile.y, tile.z))

	# Seed every material first so neighboring terrain groups can see each other.
	for key in groups:
		layer.set_cells_terrain_connect(groups[key], key.x, key.y, false)

	for cell in cells:
		var tile := cells[cell]
		if tile.x >= 0:
			layer.set_cell(cell, tile.x, Vector2i(tile.y, tile.z))
			continue
		var data := layer.get_cell_tile_data(cell)
		if data == null or data.terrain_set != tile.y or data.terrain != tile.z:
			var fallback: Vector3i = CATALOG.terrain_defaults[Vector2i(tile.y, tile.z)]
			layer.set_cell(cell, fallback.x, Vector2i(fallback.y, fallback.z))

	TerrainRules.apply_exact(layer, cells)


func _mark_goal(at: Vector2) -> void:
	var marker := Label.new()
	marker.text = "GOAL"
	marker.position = at + Vector2(-20, -25)
	add_child(marker)
