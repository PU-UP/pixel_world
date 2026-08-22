extends CharacterBody2D
class_name Player
##
## P1 玩家控制: WASD/方向键 移动, 占用像素坐标系 (1 瓦片 = 16 px)
## P2 阶段会改为: 收到 MOVE_TO 原语后,A* 寻路并按路径点 walk。
##

const GameWorldScript = preload("res://scripts/world/world.gd")
const TILE_SIZE: int = GameWorldScript.TILE_SIZE

@export var move_speed_px: float = 80.0   # 像素/秒,约 5 瓦片/秒
@export var body_color: Color = Color(0.78, 0.23, 0.23)  # 玩家红
@export var face_color: Color = Color(0.95, 0.78, 0.61)  # 肤色

var _world: Node2D = null   # GameWorld 引用
var _last_dir: Vector2 = Vector2.DOWN

func _ready() -> void:
	# 程序生成 16x16 红色 sprite
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(body_color)
	# 头顶肤色"脸"
	for px in 4:
		for py in 3:
			img.set_pixel(6 + px, 2 + py, face_color)
	# 黑色描边
	img.set_pixel(0, 0, Color.BLACK); img.set_pixel(TILE_SIZE - 1, 0, Color.BLACK)
	img.set_pixel(0, TILE_SIZE - 1, Color.BLACK); img.set_pixel(TILE_SIZE - 1, TILE_SIZE - 1, Color.BLACK)
	for i in 1..TILE_SIZE - 1:
		img.set_pixel(i, 0, Color.BLACK)
		img.set_pixel(i, TILE_SIZE - 1, Color.BLACK)
		img.set_pixel(0, i, Color.BLACK)
		img.set_pixel(TILE_SIZE - 1, i, Color.BLACK)
	var tex := ImageTexture.create_from_image(img)
	$Sprite2D.texture = tex

func bind_world(world: Node2D) -> void:
	_world = world

func _physics_process(delta: float) -> void:
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down")  - Input.get_action_strength("move_up")
	)
	if input.length() > 0.0:
		input = input.normalized()
		_last_dir = input

	velocity = input * move_speed_px
	move_and_slide()
	# 阻挡: 不能走到水/山/树
	if _world != null:
		# 用一个 4-向滑动的容错:检查中心点
		var center := global_position
		if not _world.is_walkable(center):
			# 弹回上一帧位置
			global_position -= input * move_speed_px * delta

	# 限制在世界范围内
	var half := TILE_SIZE * 0.5
	var size := (_world.world_size() if _world else Vector2(1024, 1024))
	global_position.x = clamp(global_position.x, half, size.x - half)
	global_position.y = clamp(global_position.y, half, size.y - half)
