class_name PixelTileset
##
## 原作 16×16 像素图集（草地/沙滩/水域/树林/山地），供 TileMapLayer 与迷雾快照共用。
##

const TILE := 16
const COUNT := 5

static var _atlas: ImageTexture
static var _tile_set: TileSet


static func atlas_texture() -> ImageTexture:
	if _atlas == null:
		_atlas = ImageTexture.create_from_image(_build_atlas())
	return _atlas


static func tile_set() -> TileSet:
	if _tile_set == null:
		_tile_set = _build_tile_set()
	return _tile_set


static func atlas_coords(terrain: int) -> Vector2i:
	return Vector2i(clampi(terrain, 0, COUNT - 1), 0)


static func draw_tile(ci: CanvasItem, dest: Vector2, terrain: int, modulate: Color = Color.WHITE) -> void:
	var src := Rect2(float(atlas_coords(terrain).x * TILE), 0.0, float(TILE), float(TILE))
	ci.draw_texture_rect_region(atlas_texture(), Rect2(dest, Vector2(TILE, TILE)), src, modulate)


static func _build_tile_set() -> TileSet:
	var source := TileSetAtlasSource.new()
	source.texture = atlas_texture()
	source.texture_region_size = Vector2i(TILE, TILE)
	for i in COUNT:
		source.create_tile(Vector2i(i, 0))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_source(source)
	return ts


static func _build_atlas() -> Image:
	var img := Image.create(TILE * COUNT, TILE, false, Image.FORMAT_RGBA8)
	_paint_grass(img, 0)
	_paint_sand(img, TILE)
	_paint_water(img, TILE * 2)
	_paint_tree(img, TILE * 3)
	_paint_mountain(img, TILE * 4)
	return img


static func _px(img: Image, ox: int, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= TILE or y >= TILE:
		return
	img.set_pixel(ox + x, y, c)


static func _hash(x: int, y: int, salt: int) -> int:
	return absi(x * 73 + y * 137 + salt * 29) % 256


static func _paint_grass(img: Image, ox: int) -> void:
	var base := Color(0.36, 0.62, 0.26)
	var dark := Color(0.24, 0.46, 0.18)
	var blade := Color(0.55, 0.80, 0.34)
	var dirt := Color(0.42, 0.52, 0.22)
	for y in TILE:
		for x in TILE:
			var h: int = _hash(x, y, 3)
			var c: Color = base
			if h < 40:
				c = dark
			elif h > 220:
				c = dirt
			_px(img, ox, x, y, c)
	for i in 7:
		var x: int = 1 + (i * 5 + 2) % 14
		var y: int = 2 + (i * 3) % 12
		_px(img, ox, x, y, blade)
		_px(img, ox, x, y - 1, blade)


static func _paint_sand(img: Image, ox: int) -> void:
	var base := Color(0.93, 0.82, 0.54)
	var dark := Color(0.78, 0.64, 0.38)
	var light := Color(0.98, 0.92, 0.72)
	for y in TILE:
		for x in TILE:
			var h: int = _hash(x, y, 11)
			var c: Color = base
			if h < 50:
				c = dark
			elif h > 210:
				c = light
			_px(img, ox, x, y, c)
	for i in 5:
		_px(img, ox, 2 + i * 3, 11, dark)
		_px(img, ox, 3 + i * 3, 12, dark)


static func _paint_water(img: Image, ox: int) -> void:
	var deep := Color(0.14, 0.36, 0.62)
	var mid := Color(0.18, 0.46, 0.72)
	var shine := Color(0.42, 0.70, 0.86)
	for y in TILE:
		for x in TILE:
			var c: Color = mid
			if y == 6 or y == 13:
				c = deep
			elif y > 13:
				c = deep.darkened(0.08)
			_px(img, ox, x, y, c)
	_px(img, ox, 3, 4, shine)
	_px(img, ox, 10, 9, shine)


static func _paint_tree(img: Image, ox: int) -> void:
	_paint_grass(img, ox)
	var trunk := Color(0.38, 0.24, 0.12)
	var bark := Color(0.26, 0.16, 0.08)
	var leaf := Color(0.10, 0.32, 0.14)
	var leaf_hi := Color(0.22, 0.50, 0.20)
	for y in range(10, TILE):
		for x in range(6, 10):
			_px(img, ox, x, y, trunk if (x + y) % 2 == 0 else bark)
	for y in range(1, 11):
		for x in range(2, 14):
			var dx: int = x - 8
			var dy: int = y - 5
			if dx * dx + dy * dy * 2 > 28:
				continue
			var c: Color = leaf_hi if _hash(x, y, 19) > 180 else leaf
			_px(img, ox, x, y, c)


static func _paint_mountain(img: Image, ox: int) -> void:
	var rock := Color(0.46, 0.46, 0.50)
	var shade := Color(0.28, 0.28, 0.32)
	var hi := Color(0.72, 0.72, 0.76)
	var dirt := Color(0.40, 0.36, 0.30)
	for y in TILE:
		for x in TILE:
			_px(img, ox, x, y, dirt if y > 12 else rock)
	for y in TILE:
		for x in TILE:
			var peak: int = 14 - absi(x - 8) * 2
			if y > peak:
				continue
			var c: Color = rock
			if x < 7:
				c = shade
			elif x > 10:
				c = hi
			if y < peak - 2 and x >= 7 and x <= 9:
				c = hi
			_px(img, ox, x, y, c)
	_px(img, ox, 4, 10, shade)
	_px(img, ox, 12, 9, hi)
