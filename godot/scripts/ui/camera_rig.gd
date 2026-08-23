extends Camera2D
class_name CameraRig
##
## 滚轮缩放 + 中键拖动画布；跟随目标由 Main 设置
##

signal pan_changed(offset: Vector2)

const ZOOM_MIN: float = 0.5
const ZOOM_MAX: float = 3.0
const ZOOM_STEP: float = 0.12

var pan_offset: Vector2 = Vector2.ZERO

var _follow_target: Node2D = null
var _panning: bool = false
var _pan_mouse_start: Vector2 = Vector2.ZERO
var _pan_offset_start: Vector2 = Vector2.ZERO


func set_follow_target(target: Node2D) -> void:
	_follow_target = target


func reset_view() -> void:
	zoom = Vector2.ONE
	pan_offset = Vector2.ZERO
	_panning = false


func apply_follow() -> void:
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
