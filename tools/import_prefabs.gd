extends SceneTree

const Catalog = preload("res://scripts/prefab_catalog.gd")
const TILESET = preload("res://dream_tileset.tres")
const SOURCE_DIR := "res://maps/prefabs"
const OUTPUT := "res://maps/prefabs.tres"
const SIDES := {"left": Vector2i.LEFT, "right": Vector2i.RIGHT, "up": Vector2i.UP, "down": Vector2i.DOWN}

var palette: Dictionary[String, Vector3i] = {}
var terrain_defaults: Dictionary[Vector2i, Vector3i] = {}
var problem := ""


func _initialize() -> void:
	var catalog := _compile_catalog()
	if catalog == null:
		push_error(problem)
		quit(1)
		return
	var result := ResourceSaver.save(catalog, OUTPUT)
	if result != OK:
		push_error("Could not save %s: %s" % [OUTPUT, error_string(result)])
		quit(1)
		return
	print("Compiled %d prefabs into %s" % [catalog.prefabs.size(), OUTPUT])
	quit()


func _compile_catalog() -> Resource:
	var raw_palette: Variant = _read_json("res://maps/tiles.json")
	if not raw_palette is Dictionary:
		problem = "maps/tiles.json must contain a JSON object."
		return null
	for symbol in raw_palette:
		if symbol.is_empty() or not _compile_symbol(symbol, raw_palette[symbol]):
			if problem.is_empty():
				problem = "Give each tile mapping a nonempty name."
			return null

	var catalog := Catalog.new()
	catalog.terrain_defaults = terrain_defaults
	var ids: Dictionary = {}
	var roles := {"start": 0, "normal": 0, "goal": 0}
	var has_normal_spawn := false
	for filename in DirAccess.get_files_at(SOURCE_DIR):
		if not filename.ends_with(".json"):
			continue
		var data: Variant = _read_json(SOURCE_DIR.path_join(filename))
		if not data is Dictionary:
			if problem.is_empty():
				problem = "%s must contain a JSON object." % filename
			return null
		var prefab := _compile_prefab(data)
		if prefab.is_empty():
			problem = "%s: %s" % [filename, problem]
			return null
		if ids.has(prefab.id):
			problem = "%s: duplicate prefab id '%s'." % [filename, prefab.id]
			return null
		ids[prefab.id] = true
		if prefab.kind == "room":
			roles[prefab.role] += 1
			if prefab.role == "normal" and prefab.spawn != Vector2i(-1, -1):
				has_normal_spawn = true
		catalog.prefabs.append(prefab)
	if roles.normal == 0:
		problem = "The catalog needs at least one normal room."
		return null
	if (roles.start == 0 or roles.goal == 0) and not has_normal_spawn:
		problem = "Add dedicated start and goal rooms or give a normal room a spawn."
		return null
	return catalog


func _compile_symbol(symbol: String, entry: Variant) -> bool:
	if entry is Dictionary and entry.get("terrain") is String:
		return _compile_terrain_symbol(symbol, entry)
	if not entry is Array or entry.size() != 3 or not _is_integer(entry[0]) or not _is_integer(entry[1]) or not _is_integer(entry[2]):
		problem = "Invalid mapping for '%s'. Use an atlas triple or a terrain name." % symbol
		return false
	var source_id := int(entry[0])
	var coords := Vector2i(int(entry[1]), int(entry[2]))
	var source := TILESET.get_source(source_id) as TileSetAtlasSource if TILESET.has_source(source_id) else null
	if source == null or not source.has_tile(coords):
		problem = "Unknown atlas tile for '%s'." % symbol
		return false
	palette[symbol] = Vector3i(source_id, coords.x, coords.y)
	return true


func _compile_terrain_symbol(symbol: String, entry: Dictionary) -> bool:
	var matches: Array[Vector2i] = []
	var set_count := TILESET.get_terrain_sets_count()
	var set_filter := -1
	if entry.has("terrain_set"):
		if not _is_integer(entry.terrain_set) or entry.terrain_set < 0 or entry.terrain_set >= set_count:
			problem = "Invalid terrain_set for '%s'." % symbol
			return false
		set_filter = int(entry.terrain_set)
	for set_id in set_count:
		if set_filter >= 0 and set_id != set_filter:
			continue
		for terrain_id in TILESET.get_terrains_count(set_id):
			if TILESET.get_terrain_name(set_id, terrain_id) == entry.terrain:
				matches.append(Vector2i(set_id, terrain_id))
	if matches.size() != 1:
		problem = "Terrain '%s' for '%s' must match exactly once. Set terrain_set if the name is shared." % [entry.terrain, symbol]
		return false
	var terrain := matches[0]
	if not terrain_defaults.has(terrain):
		var tile := _find_terrain_tile(terrain)
		if tile.x == -1:
			problem = "No atlas tile has terrain '%s'." % entry.terrain
			return false
		terrain_defaults[terrain] = tile
	palette[symbol] = Vector3i(-1, terrain.x, terrain.y)
	return true


func _find_terrain_tile(terrain: Vector2i) -> Vector3i:
	for index in TILESET.get_source_count():
		var source_id := TILESET.get_source_id(index)
		var source := TILESET.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for tile_index in source.get_tiles_count():
			var coords := source.get_tile_id(tile_index)
			var data := source.get_tile_data(coords, 0)
			if data.terrain_set == terrain.x and data.terrain == terrain.y:
				return Vector3i(source_id, coords.x, coords.y)
	return Vector3i(-1, -1, -1)


func _compile_prefab(data: Dictionary) -> Dictionary:
	var id: Variant = data.get("id")
	var kind: Variant = data.get("kind")
	var role: Variant = data.get("role", "normal")
	var size := _pair(data.get("size"))
	if not id is String or id.is_empty() or kind not in ["room", "corridor"] or size.x <= 0 or size.y <= 0:
		problem = "Set a unique id, a valid kind and a positive size [width, height]."
		return {}
	if role not in ["start", "normal", "goal"] or (kind != "room" and role != "normal"):
		problem = "Only rooms can have a start or goal role."
		return {}
	var spawn := _pair(data.get("spawn"))
	if (role in ["start", "goal"] or data.has("spawn")) and not Rect2i(Vector2i.ZERO, size).has_point(spawn):
		problem = "Set spawn to a valid [x, y] within the prefab. Start and goal rooms require it."
		return {}

	var terrain := _compile_layer(data.get("terrain", []), size, true)
	var decoration := _compile_layer(data.get("decoration", []), size, false)
	if not problem.is_empty():
		return {}
	var raw_exits: Variant = data.get("exits")
	if not raw_exits is Array or raw_exits.is_empty() or (kind == "corridor" and raw_exits.size() < 2):
		problem = "Rooms need at least one exit. Corridors need at least two."
		return {}

	var exits: Array[Dictionary] = []
	var door_cells: Dictionary[Vector2i, bool] = {}
	for door in raw_exits:
		if not door is Dictionary or not SIDES.has(door.get("side")) or not _is_integer(door.get("offset")) or not _is_integer(door.get("span")):
			problem = "Each exit needs a side, integer offset and integer span."
			return {}
		var direction: Vector2i = SIDES[door.side]
		var offset := int(door.offset)
		var span := int(door.span)
		var wall_length := size.y if direction.x != 0 else size.x
		if offset < 0 or span <= 0 or offset + span > wall_length:
			problem = "Exit extends outside its wall."
			return {}
		var anchor := Vector2i(offset, 0) if direction.y else Vector2i(0, offset)
		if direction == Vector2i.RIGHT:
			anchor.x = size.x - 1
		elif direction == Vector2i.DOWN:
			anchor.y = size.y - 1
		var raw_cap: Variant = door.get("cap")
		var align: Variant = door.get("align", "center")
		if align not in ["start", "center", "end"]:
			problem = "Exit align must be start, center or end."
			return {}
		var tangent := Vector2i.DOWN if direction.x != 0 else Vector2i.RIGHT
		if not raw_cap is Dictionary or not (raw_cap.get("terrain") is Array or raw_cap.get("terrain") is String):
			problem = "Set cap.terrain to a tile name or a tile list."
			return {}
		var cap_entries: Array = []
		if raw_cap.terrain is String:
			for index in span:
				var cell := anchor + tangent * index
				cap_entries.append([cell.x, cell.y, raw_cap.terrain])
		else:
			cap_entries = raw_cap.terrain
		var cap_terrain := _compile_layer(cap_entries, size, true)
		var cap_decoration := _compile_layer(raw_cap.get("decoration", []), size, false)
		if not problem.is_empty():
			return {}
		var covered: Dictionary[Vector2i, bool] = {}
		for index in range(0, cap_terrain.size(), 5):
			covered[Vector2i(cap_terrain[index], cap_terrain[index + 1])] = true
		for index in span:
			var cell := anchor + tangent * index
			if not covered.has(cell):
				problem = "The %s exit cap is missing tile %s." % [door.side, cell]
				return {}
			if door_cells.has(cell):
				problem = "Two exit openings share cell %s." % cell
				return {}
			door_cells[cell] = true
		if covered.size() != span:
			problem = "Cap terrain must stay within the %s exit opening." % door.side
			return {}
		exits.append({
			"direction": direction, "anchor": anchor, "tangent": tangent, "span": span,
			"align": align, "terrain": cap_terrain, "decoration": cap_decoration,
		})

	return {"id": id, "kind": kind, "role": role, "size": size, "spawn": spawn, "terrain": terrain, "decoration": decoration, "exits": exits}


func _compile_layer(entries: Variant, size: Vector2i, allow_auto_terrain: bool) -> PackedInt32Array:
	var packed := PackedInt32Array()
	if not entries is Array:
		problem = "Tile placements must be an array of [x, y, symbol]."
		return packed
	for entry in entries:
		if not entry is Array or entry.size() != 3 or not _is_integer(entry[0]) or not _is_integer(entry[1]):
			problem = "Expected a tile placement [x, y, symbol]."
			return packed
		var cell := Vector2i(int(entry[0]), int(entry[1]))
		if not Rect2i(Vector2i.ZERO, size).has_point(cell) or not entry[2] is String or not palette.has(entry[2]):
			problem = "Tile '%s' at %s is unknown or outside the prefab." % [entry[2], cell]
			return packed
		var tile: Vector3i = palette[entry[2]]
		if tile.x == -1 and not allow_auto_terrain:
			problem = "Auto terrain '%s' belongs in terrain, not decoration." % entry[2]
			return packed
		packed.append_array(PackedInt32Array([cell.x, cell.y, tile.x, tile.y, tile.z]))
	return packed


func _pair(value: Variant) -> Vector2i:
	if value is Array and value.size() == 2 and _is_integer(value[0]) and _is_integer(value[1]):
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-1, -1)


func _is_integer(value: Variant) -> bool:
	return (value is int or value is float) and float(value) == floorf(value)


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		problem = "Could not open %s." % path
		return null
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		problem = "%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()]
		return null
	return json.data
