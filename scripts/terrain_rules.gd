@tool
extends RefCounted

const STEPS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const SIDES := [
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
	TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_SIDE,
]
const CORNERS := [
	TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
	TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
]


static func apply_exact(layer: TileMapLayer, cells: Dictionary[Vector2i, Vector3i]) -> void:
	var tileset := layer.tile_set
	if tileset.tile_shape != TileSet.TILE_SHAPE_SQUARE:
		return

	var variants := _index_variants(tileset)
	var materials: Dictionary[Vector2i, Vector2i] = {}
	for cell in cells:
		var tile := cells[cell]
		if tile.x == -1:
			materials[cell] = Vector2i(tile.y, tile.z)
		else:
			var atlas := tileset.get_source(tile.x) as TileSetAtlasSource
			var data := atlas.get_tile_data(Vector2i(tile.y, tile.z), 0)
			materials[cell] = Vector2i(data.terrain_set, data.terrain)

	for cell in cells:
		if cells[cell].x != -1:
			continue
		var material := materials[cell]
		var mode := tileset.get_terrain_set_mode(material.x)
		var pattern := PackedInt32Array([material.x, material.y])
		for i in STEPS.size():
			var side: Vector2i = STEPS[i]
			var adjacent := _material_at(materials, cell + side, material.x)
			if mode != TileSet.TERRAIN_MODE_MATCH_CORNERS:
				pattern.append(adjacent)
			if mode != TileSet.TERRAIN_MODE_MATCH_SIDES:
				var next: Vector2i = STEPS[(i + 1) % STEPS.size()]
				var corner := _material_at(materials, cell + side + next, material.x)
				var other := _material_at(materials, cell + next, material.x)
				pattern.append(corner if corner == adjacent and corner == other else -1)
		if variants.has(pattern):
			var tile := variants[pattern]
			layer.set_cell(cell, tile.x, Vector2i(tile.y, tile.z), tile.w)


static func _material_at(materials: Dictionary[Vector2i, Vector2i], cell: Vector2i, terrain_set: int) -> int:
	var material: Vector2i = materials.get(cell, Vector2i(-1, -1))
	return material.y if material.x == terrain_set else -1


static func _index_variants(tileset: TileSet) -> Dictionary[PackedInt32Array, Vector4i]:
	var variants: Dictionary[PackedInt32Array, Vector4i] = {}
	for source_index in tileset.get_source_count():
		var source_id := tileset.get_source_id(source_index)
		var atlas := tileset.get_source(source_id) as TileSetAtlasSource
		if atlas == null:
			continue
		for tile_index in atlas.get_tiles_count():
			var coords := atlas.get_tile_id(tile_index)
			for alt_index in atlas.get_alternative_tiles_count(coords):
				var alt := atlas.get_alternative_tile_id(coords, alt_index)
				var data := atlas.get_tile_data(coords, alt)
				if data.terrain_set == -1 or data.terrain == -1:
					continue
				var mode := tileset.get_terrain_set_mode(data.terrain_set)
				var pattern := PackedInt32Array([data.terrain_set, data.terrain])
				for i in STEPS.size():
					if mode != TileSet.TERRAIN_MODE_MATCH_CORNERS:
						pattern.append(data.get_terrain_peering_bit(SIDES[i]))
					if mode != TileSet.TERRAIN_MODE_MATCH_SIDES:
						pattern.append(data.get_terrain_peering_bit(CORNERS[i]))
				if not variants.has(pattern):
					variants[pattern] = Vector4i(source_id, coords.x, coords.y, alt)
	return variants
