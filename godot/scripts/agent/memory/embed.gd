class_name MemoryEmbed
##
## 本地字符 n-gram 哈希向量（无需 embedding API / 额外 LLM 调用）。
## 检索用余弦相似度，接口与 AGENTS.md §5.2 对齐。
##

static func embed(text: String, dim: int) -> PackedFloat32Array:
	var n: int = maxi(8, dim)
	var v := PackedFloat32Array()
	v.resize(n)
	v.fill(0.0)
	var s := text.strip_edges().to_lower()
	if s.is_empty():
		return v
	var prev := ""
	for i in s.length():
		var ch := s.substr(i, 1)
		_accum(v, ch, 1.0)
		if not prev.is_empty():
			_accum(v, prev + ch, 1.6)
		prev = ch
	return v


static func cosine(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var n: int = mini(a.size(), b.size())
	if n <= 0:
		return 0.0
	var dot := 0.0
	var na := 0.0
	var nb := 0.0
	for i in n:
		var av: float = a[i]
		var bv: float = b[i]
		dot += av * bv
		na += av * av
		nb += bv * bv
	if na < 0.0001 or nb < 0.0001:
		return 0.0
	return clampf(dot / (sqrt(na) * sqrt(nb)), 0.0, 1.0)


static func to_array(v: PackedFloat32Array) -> Array:
	var out: Array = []
	out.resize(v.size())
	for i in v.size():
		out[i] = v[i]
	return out


static func from_array(raw: Variant, dim: int) -> PackedFloat32Array:
	var n: int = maxi(8, dim)
	var v := PackedFloat32Array()
	v.resize(n)
	v.fill(0.0)
	if typeof(raw) != TYPE_ARRAY:
		return v
	var arr: Array = raw
	for i in mini(n, arr.size()):
		v[i] = float(arr[i])
	return v


static func _accum(v: PackedFloat32Array, token: String, weight: float) -> void:
	var h: int = token.hash()
	var n: int = v.size()
	v[absi(h) % n] += weight
	v[absi(h ^ 0x9E3779B9) % n] += weight * 0.45
