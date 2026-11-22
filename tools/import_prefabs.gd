extends SceneTree

const Catalog = preload("res://scripts/prefab_catalog.gd")
const TILESET = preload("res://dream_tileset.tres")
const SOURCE_DIR := "res://maps/prefabs"
const OUTPUT := "res://maps/prefabs.tres"
const SIDES := {"left": Vector2i.LEFT, "right": Vector2i.RIGHT, "up": Vector2i.UP, "down": Vector2i.DOWN}

var palette: Dictionary = {}
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
		var entry: Variant = raw_palette[symbol]
		if symbol.is_empty() or not entry is Array or entry.size() != 3 or not _is_integer(entry[0]) or not _is_integer(entry[1]) or not _is_integer(entry[2]):
			problem = "Invalid tile mapping for '%s'. Use a name and [source, atlas_x, atlas_y]." % symbol
			return null
		var source_id := int(entry[0])
		var coords := Vector2i(int(entry[1]), int(entry[2]))
		if source_id not in [0, 1] or not TILESET.has_source(source_id) or not TILESET.get_source(source_id).has_tile(coords):
			problem = "Unknown grass or grass_deco tile for '%s'." % symbol
			return null
		palette[symbol] = Vector3i(source_id, coords.x, coords.y)

	var catalog := Catalog.new()
	var ids: Dictionary = {}
	var roles := {"start": 0, "normal": 0, "goal": 0}
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
		catalog.prefabs.append(prefab)
	for role in roles:
		if roles[role] == 0:
			problem = "The catalog needs at least one '%s' room." % role
			return null
	return catalog


func _compile_prefab(data: Dictionary) -> Dictionary:
	var id: Variant = data.get("id")
	var kind: Variant = data.get("kind")
	var role: Variant = data.get("role", "normal")
	var size := _pair(data.get("size"))
	if not id is String or id.is_empty() or kind not in ["room", "corridor", "shaft"] or size.x <= 0 or size.y <= 0:
		problem = "Set a unique id, a valid kind and a positive size [width, height]."
		return {}
	if role not in ["start", "normal", "goal"] or (kind != "room" and role != "normal"):
		problem = "Only rooms can have a start or goal role."
		return {}
	var spawn := _pair(data.get("spawn"))
	if role in ["start", "goal"] and not Rect2i(Vector2i.ZERO, size).has_point(spawn):
		problem = "Start and goal rooms need a spawn [x, y] within their bounds."
		return {}

	var terrain := _compile_layer(data.get("terrain", []), size, 0)
	var decoration := _compile_layer(data.get("decoration", []), size, 1)
	if not problem.is_empty():
		return {}
	var raw_exits: Variant = data.get("exits")
	if not raw_exits is Array or raw_exits.is_empty() or (kind != "room" and raw_exits.size() != 2):
		problem = "Rooms need at least one exit. Connectors need exactly two."
		return {}

	var exits: Array[Dictionary] = []
	for door in raw_exits:
		if not door is Dictionary or not SIDES.has(door.get("side")) or not _is_integer(door.get("offset")) or not _is_integer(door.get("span")):
			problem = "Each exit needs a side, integer offset and integer span."
			return {}
		var direction: Vector2i = SIDES[door.side]
		if (kind == "corridor" and direction.x == 0) or (kind == "shaft" and direction.y == 0):
			problem = "Corridors use left and right exits. Shafts use up and down exits."
			return {}
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
		if not raw_cap is Dictionary or not raw_cap.get("terrain") is Array or raw_cap.terrain.is_empty():
			problem = "Each exit needs cap.terrain tiles."
			return {}
		var cap_terrain := _compile_layer(raw_cap.terrain, size, 0)
		var cap_decoration := _compile_layer(raw_cap.get("decoration", []), size, 1)
		if not problem.is_empty():
			return {}
		exits.append({"direction": direction, "anchor": anchor, "span": span, "terrain": cap_terrain, "decoration": cap_decoration})
	if kind != "room" and exits[0].direction != -exits[1].direction:
		problem = "Connector exits must face opposite directions."
		return {}
	return {"id": id, "kind": kind, "role": role, "size": size, "spawn": spawn, "terrain": terrain, "decoration": decoration, "exits": exits}


func _compile_layer(entries: Variant, size: Vector2i, source_id: int) -> PackedInt32Array:
	var packed := PackedInt32Array()
	if not entries is Array:
		problem = "Tile placements must be an array of [x, y, symbol]."
		return packed
	for entry in entries:
		if not entry is Array or entry.size() != 3 or not _is_integer(entry[0]) or not _is_integer(entry[1]):
			problem = "Expected a tile placement [x, y, symbol]."
			return packed
		var cell := Vector2i(int(entry[0]), int(entry[1]))
		if not Rect2i(Vector2i.ZERO, size).has_point(cell) or not palette.has(entry[2]) or palette[entry[2]].x != source_id:
			problem = "Tile '%s' at %s is outside the prefab or belongs to the wrong layer." % [entry[2], cell]
			return packed
		var tile: Vector3i = palette[entry[2]]
		packed.append_array(PackedInt32Array([cell.x, cell.y, tile.y, tile.z]))
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
