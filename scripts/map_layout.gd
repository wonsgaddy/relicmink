extends RefCounted

const MAX_ATTEMPTS := 96
const CONNECTOR_CHANCE := 0.35

var _rng := RandomNumberGenerator.new()
var _rooms: Dictionary = {"start": [], "normal": [], "goal": []}
var _connectors: Dictionary = {"corridor": [], "shaft": []}
var placements: Array[Dictionary] = []
var goal_index := -1


func generate(prefabs: Array[Dictionary], seed_value: int, path_range: Vector2i, branch_range: Vector2i, depth_range: Vector2i) -> bool:
	placements.clear()
	goal_index = -1
	if path_range.x < 2 or path_range.y < path_range.x or branch_range.x < 0 or branch_range.y < branch_range.x or depth_range.x < 1 or depth_range.y < depth_range.x:
		return false
	_rng.seed = seed_value
	_rooms = {"start": [], "normal": [], "goal": []}
	_connectors = {"corridor": [], "shaft": []}
	for prefab in prefabs:
		if prefab.kind == "room":
			_rooms[prefab.role].append(prefab)
		else:
			_connectors[prefab.kind].append(prefab)
	if _rooms.start.is_empty() or _rooms.normal.is_empty() or _rooms.goal.is_empty():
		return false

	var path_size := _rng.randi_range(path_range.x, path_range.y)
	var branch_count := _rng.randi_range(branch_range.x, branch_range.y)
	var branch_sizes: Array[int] = []
	for index in branch_count:
		branch_sizes.append(_rng.randi_range(depth_range.x, depth_range.y))

	for attempt in MAX_ATTEMPTS:
		placements.clear()
		goal_index = -1
		if _make_tree(path_size, branch_sizes):
			return true
	placements.clear()
	goal_index = -1
	return false


func _make_tree(path_size: int, branch_sizes: Array[int]) -> bool:
	var start: Dictionary = _rooms.start[_rng.randi_range(0, _rooms.start.size() - 1)]
	placements.append(_placement(start, Vector2i.ZERO))
	var tail := 0
	var branch_roots: Array[int] = []
	for step in range(1, path_size):
		var role := "goal" if step == path_size - 1 else "normal"
		tail = _extend([tail], role)
		if tail == -1:
			return false
		if role == "normal":
			branch_roots.append(tail)
	goal_index = tail

	for depth in branch_sizes:
		var branch_tail := _extend(branch_roots, "normal")
		if branch_tail == -1:
			return false
		for step in range(1, depth):
			branch_tail = _extend([branch_tail], "normal")
			if branch_tail == -1:
				return false
	return true


func _extend(from_rooms: Array[int], role: String) -> int:
	var exits: Array[Vector2i] = []
	for room in from_rooms:
		for index in placements[room].prefab.exits.size():
			if not placements[room].joined.has(index):
				exits.append(Vector2i(room, index))
	while not exits.is_empty():
		var from: Vector2i = exits.pop_at(_rng.randi_range(0, exits.size() - 1))
		var use_connector := _rng.randf() < CONNECTOR_CHANCE
		if use_connector:
			var connected := _via_connector(from, _rooms[role])
			if connected != -1:
				return connected
		var direct := _choose_fit(from, _rooms[role])
		if not direct.is_empty():
			var room := placements.size()
			placements.append(direct.placement)
			_join(from, Vector2i(room, direct.exit))
			return room
		if not use_connector:
			var connected := _via_connector(from, _rooms[role])
			if connected != -1:
				return connected
	return -1


func _via_connector(from: Vector2i, rooms: Array) -> int:
	var direction: Vector2i = placements[from.x].prefab.exits[from.y].direction
	var kind := "corridor" if direction.x != 0 else "shaft"
	var options := _fits(from, _connectors[kind])
	while not options.is_empty():
		var connector: Dictionary = options.pop_at(_rng.randi_range(0, options.size() - 1))
		var connector_index := placements.size()
		placements.append(connector.placement)
		var far_end := Vector2i(connector_index, 1 - int(connector.exit))
		var room := _choose_fit(far_end, rooms)
		if not room.is_empty():
			var room_index := placements.size()
			placements.append(room.placement)
			_join(from, Vector2i(connector_index, connector.exit))
			_join(far_end, Vector2i(room_index, room.exit))
			return room_index
		placements.pop_back()
	return -1


func _choose_fit(from: Vector2i, candidates: Array) -> Dictionary:
	var fits := _fits(from, candidates)
	if fits.is_empty():
		return {}
	return fits[_rng.randi_range(0, fits.size() - 1)]


func _fits(from: Vector2i, candidates: Array) -> Array[Dictionary]:
	var parent := placements[from.x]
	var exit: Dictionary = parent.prefab.exits[from.y]
	var entrance_cell: Vector2i = parent.origin + exit.anchor + exit.direction
	var fits: Array[Dictionary] = []
	for prefab in candidates:
		for index in prefab.exits.size():
			var entrance: Dictionary = prefab.exits[index]
			if entrance.direction != -exit.direction or entrance.span != exit.span:
				continue
			var origin: Vector2i = entrance_cell - entrance.anchor
			var bounds := Rect2i(origin, prefab.size)
			var overlaps := false
			for placed in placements:
				if bounds.intersects(Rect2i(placed.origin, placed.prefab.size)):
					overlaps = true
					break
			if not overlaps:
				fits.append({"placement": _placement(prefab, origin), "exit": index})
	return fits


func _placement(prefab: Dictionary, origin: Vector2i) -> Dictionary:
	return {"prefab": prefab, "origin": origin, "joined": {}}


func _join(a: Vector2i, b: Vector2i) -> void:
	placements[a.x].joined[a.y] = b
	placements[b.x].joined[b.y] = a
