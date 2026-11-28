extends Camera2D
## Round rendered camera coordinates; gameplay bodies keep their precision.

static func snap_point(point: Vector2, magnification: Vector2) -> Vector2:
	return (point * magnification).round() / magnification

func _ready() -> void:
	position_smoothing_enabled = false
	rotation_smoothing_enabled = false
	ignore_rotation = true
	process_priority = 100
	_snap_view()

func _process(_delta: float) -> void:
	_snap_view()

func _snap_view() -> void:
	global_position = snap_point(global_position, zoom)
	offset = snap_point(offset, zoom)
	force_update_scroll()
