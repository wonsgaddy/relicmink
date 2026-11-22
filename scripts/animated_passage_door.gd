@tool
extends Node2D

const CELL_SIZE := 16
const LAST_FRAME := 3
const PROXIMITY := 40.0
const HIDDEN_FRAME := Vector2i(-1, -1)

const V_SINGLE: Array[Vector2i] = [Vector2i(0, 0), Vector2i(3, 0), Vector2i(6, 0), Vector2i(9, 0)]
const V_DOUBLE: Array[Vector2i] = [Vector2i(1, 0), Vector2i(4, 0), Vector2i(7, 0), Vector2i(10, 0)]
const V_TOP: Array[Vector2i] = [Vector2i(2, 0), Vector2i(5, 0), Vector2i(8, 0), Vector2i(11, 0)]
const V_MIDDLE: Array[Vector2i] = [Vector2i(2, 1), Vector2i(5, 1), Vector2i(8, 1), Vector2i(11, 1)]
const V_BOTTOM: Array[Vector2i] = [Vector2i(2, 2), Vector2i(5, 2), Vector2i(8, 2), Vector2i(11, 2)]
const V_EXTENSION: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, 1), Vector2i(0, 1), HIDDEN_FRAME]

const H_SINGLE: Array[Vector2i] = [Vector2i(1, 3), Vector2i(6, 3), Vector2i(11, 3), Vector2i(1, 5)]
const H_DOUBLE: Array[Vector2i] = [Vector2i(0, 4), Vector2i(5, 4), Vector2i(10, 4), Vector2i(0, 6)]
const H_LEFT: Array[Vector2i] = [Vector2i(2, 3), Vector2i(7, 3), Vector2i(12, 3), Vector2i(2, 5)]
const H_MIDDLE: Array[Vector2i] = [Vector2i(3, 3), Vector2i(8, 3), Vector2i(13, 3), Vector2i(3, 5)]
const H_RIGHT: Array[Vector2i] = [Vector2i(4, 3), Vector2i(9, 3), Vector2i(14, 3), Vector2i(4, 5)]
const H_EXTENSION: Array[Vector2i] = [Vector2i(0, 3), Vector2i(0, 3), Vector2i(0, 3), HIDDEN_FRAME]

var frame := 0
var footprint := Rect2()
var _target_frame := 0
var _elapsed := 0.0
var _seconds_per_frame := 0.08
var _axis := Vector2i.DOWN
var _atlas: Texture2D
var _player: Node2D
var _shape: CollisionShape2D
var _pieces: Array[Sprite2D] = []
var _coordinates: Array[Array] = []


func configure(axis: Vector2i, length: int, atlas: Texture2D, seconds_per_frame: float, tracked_player: Node2D, preview := false) -> void:
	_axis = axis
	_atlas = atlas
	_player = tracked_player
	_seconds_per_frame = seconds_per_frame
	footprint = Rect2(Vector2.ZERO, Vector2(Vector2i.ONE + _axis * (length - 1)) * CELL_SIZE)
	_build_pieces(length)
	if not preview:
		var body := StaticBody2D.new()
		body.collision_mask = 0
		var rectangle := RectangleShape2D.new()
		rectangle.size = footprint.size
		_shape = CollisionShape2D.new()
		_shape.shape = rectangle
		_shape.position = footprint.get_center()
		body.add_child(_shape)
		add_child(body)
	_draw_frame()


func _ready() -> void:
	set_physics_process(_shape != null and not Engine.is_editor_hint())


func set_open(value: bool) -> void:
	_target_frame = LAST_FRAME if value else 0


func _physics_process(delta: float) -> void:
	if is_instance_valid(_player):
		set_open(footprint.grow(PROXIMITY).has_point(to_local(_player.global_position)))
	if frame == _target_frame:
		_elapsed = 0.0
		return

	_elapsed += delta
	if _elapsed < _seconds_per_frame:
		return
	_elapsed -= _seconds_per_frame
	frame += 1 if _target_frame > frame else -1
	_draw_frame()
	if frame == 0 or frame == LAST_FRAME:
		_shape.set_deferred("disabled", frame == LAST_FRAME)


func _build_pieces(length: int) -> void:
	var vertical := _axis == Vector2i.DOWN
	if length == 1:
		_add_piece(0, 1, V_SINGLE if vertical else H_SINGLE)
		return
	if length == 2:
		_add_piece(0, 2, V_DOUBLE if vertical else H_DOUBLE)
		return

	var middle_length := 2 if vertical and length % 2 == 0 else 1
	var middle_start := 1 + floori((length - 2 - middle_length) / 2.0)
	_add_piece(0, 1, V_TOP if vertical else H_LEFT)
	for index in range(1, middle_start):
		_add_piece(index, 1, V_EXTENSION if vertical else H_EXTENSION)
	var middle := H_MIDDLE
	if vertical:
		middle = V_DOUBLE if middle_length == 2 else V_MIDDLE
	_add_piece(middle_start, middle_length, middle)
	for index in range(middle_start + middle_length, length - 1):
		_add_piece(index, 1, V_EXTENSION if vertical else H_EXTENSION)
	_add_piece(length - 1, 1, V_BOTTOM if vertical else H_RIGHT)


func _add_piece(offset: int, length: int, coordinates: Array[Vector2i]) -> void:
	var piece := Sprite2D.new()
	piece.texture = _atlas
	piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	piece.centered = false
	piece.region_enabled = true
	piece.region_filter_clip_enabled = true
	piece.position = Vector2(_axis * offset) * CELL_SIZE
	piece.region_rect = Rect2(Vector2.ZERO, Vector2(Vector2i.ONE + _axis * (length - 1)) * CELL_SIZE)
	add_child(piece)
	_pieces.append(piece)
	_coordinates.append(coordinates)


func _draw_frame() -> void:
	for index in _pieces.size():
		var piece := _pieces[index]
		var coord: Vector2i = _coordinates[index][frame]
		piece.visible = coord != HIDDEN_FRAME
		if piece.visible:
			piece.region_rect.position = Vector2(coord) * CELL_SIZE
