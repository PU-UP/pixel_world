extends Camera2D
class_name CameraRig
##
## 滚轮缩放 + 中键拖动画布；跟随目标由 Main 设置
## G 键切换上帝视角：全图可见、无迷雾
##

signal pan_changed(offset: Vector2)

enum ViewMode { FOLLOW_AGENT, GOD_MAP }

const ZOOM_MIN: float = 0.25
const ZOOM_MAX: float = 3.0
const ZOOM_STEP: float = 0.12

var pan_offset: Vector2 = Vector2.ZERO
var view_mode: int = ViewMode.FOLLOW_AGENT

var _follow_target: Node2D = null
var _world_center: Vector2 = Vector2.ZERO
var _panning: bool = false
var _pan_mouse_start: Vector2 = Vector2.ZERO
var _pan_offset_start: Vector2 = Vector2.ZERO


func set_follow_target(target: Node2D) -> void:
	_follow_target = target


func set_view_mode(mode: int) -> void:
	view_mode = mode


func set_world_center(center: Vector2) -> void:
	_world_center = center


func reset_view() -> void:
	zoom = Vector2.ONE
	pan_offset = Vector2.ZERO
	_panning = false
	view_mode = ViewMode.FOLLOW_AGENT


func fit_world(world_size: Vector2) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var view_size: Vector2 = vp.get_visible_rect().size
	if world_size.x <= 0.0 or world_size.y <= 0.0:
		return
	var zx: float = view_size.x / world_size.x
	var zy: float = view_size.y / world_size.y
	var z: float = clampf(minf(zx, zy) * 0.92, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)
	global_position = world_size * 0.5 + pan_offset


func apply_follow() -> void:
	if view_mode == ViewMode.GOD_MAP:
		position_smoothing_enabled = false
		global_position = _world_center + pan_offset
		return
	position_smoothing_enabled = pan_offset.length() < 0.5 and not _panning
	if _follow_target != null and is_instance_valid(_follow_target):
		global_position = _follow_target.global_position + pan_offset
	elif pan_offset != Vector2.ZERO:
		global_position = pan_offset


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_MIDDLE:
				if event.pressed:
					_panning = true
					_pan_mouse_start = event.position
					_pan_offset_start = pan_offset
				else:
					_panning = false
				return true
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_by(ZOOM_STEP, event.position)
					return true
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_by(-ZOOM_STEP, event.position)
					return true
	elif event is InputEventMouseMotion and _panning:
		var z: float = maxf(zoom.x, 0.001)
		var delta: Vector2 = (event.position - _pan_mouse_start) / z
		pan_offset = _pan_offset_start - delta
		pan_changed.emit(pan_offset)
		return true
	return false


func _zoom_by(delta: float, screen_pos: Vector2) -> void:
	var old_z: float = zoom.x
	var new_z: float = clampf(old_z + delta, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(old_z, new_z):
		return
	var vp := get_viewport()
	if vp == null:
		zoom = Vector2(new_z, new_z)
		return
	var canvas_xform: Transform2D = vp.get_canvas_transform()
	var world_before: Vector2 = canvas_xform.affine_inverse() * screen_pos
	zoom = Vector2(new_z, new_z)
	var world_after: Vector2 = vp.get_canvas_transform().affine_inverse() * screen_pos
	pan_offset += world_before - world_after
	pan_changed.emit(pan_offset)
