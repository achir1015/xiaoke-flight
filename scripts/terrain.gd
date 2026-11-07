class_name Terrain
extends Node3D
## 程序化臺灣地形：海岸線（經緯度多邊形）＋中央山脈與海岸山脈＋雜訊，機場周圍整平。

const X0 := -21000.0
const Z0 := -25500.0
const W := 36000.0
const H := 51000.0

const TAIWAN := [
	[121.51, 25.30], [121.62, 25.22], [121.74, 25.15], [121.87, 25.12], [122.00, 25.01], [121.90, 24.90], [121.83, 24.75],
	[121.86, 24.58], [121.80, 24.40], [121.66, 24.15], [121.61, 23.95], [121.55, 23.70], [121.50, 23.45], [121.42, 23.20],
	[121.30, 22.95], [121.17, 22.75], [121.03, 22.60], [120.90, 22.35], [120.87, 22.10], [120.84, 21.92], [120.74, 21.95],
	[120.70, 22.10], [120.62, 22.30], [120.48, 22.45], [120.30, 22.56], [120.26, 22.70], [120.17, 22.90], [120.10, 23.05],
	[120.08, 23.25], [120.13, 23.45], [120.19, 23.70], [120.30, 23.95], [120.42, 24.12], [120.52, 24.30], [120.64, 24.50],
	[120.80, 24.68], [120.92, 24.85], [121.03, 24.97], [121.15, 25.05], [121.30, 25.12], [121.40, 25.20],
]
const PENGHU := [[119.52, 23.70], [119.62, 23.67], [119.70, 23.63], [119.70, 23.52], [119.60, 23.51], [119.54, 23.55], [119.50, 23.62]]
# 中央山脈稜線：經度、緯度、高度、半寬（公尺）
const RIDGE := [
	[121.70, 24.78, 500, 2200], [121.45, 24.55, 900, 2600], [121.25, 24.38, 1300, 3200], [121.15, 24.05, 1150, 3600],
	[121.03, 23.75, 1100, 3600], [120.96, 23.47, 1320, 3400], [120.88, 23.15, 1050, 3000], [120.78, 22.75, 800, 2600],
	[120.75, 22.35, 500, 2000], [120.80, 22.05, 250, 1500],
]
const COAST_RANGE := [[121.56, 23.95, 300, 900], [121.42, 23.45, 520, 1100], [121.22, 22.90, 320, 900]]
# 單獨山丘或小島：經度、緯度、高度、半徑
const BUMPS := [[121.55, 25.18, 420, 1300], [121.49, 22.665, 140, 420], [121.55, 22.045, 220, 620], [120.56, 23.50, 380, 2200]]

var S := 150.0
var NX := 0
var NZ := 0
var hts := PackedFloat32Array()
var _sdf := PackedFloat32Array()
var _sdf_nx := 0
var _sdf_nz := 0
const SDF_S := 500.0
var _n_coast := FastNoiseLite.new()
var _n_hill := FastNoiseLite.new()
var _n_ridge := FastNoiseLite.new()
var _ridge_pts: Array = []
var _coast_pts: Array = []
var _polys: Array = []
var _apts: Array = []
var _cities: Array = []
var map_tex: ImageTexture
var height_tex: ImageTexture
var mat: ShaderMaterial

func _init_data() -> void:
	_n_coast.seed = 11
	_n_coast.frequency = 1.0 / 2600.0
	_n_coast.fractal_octaves = 3
	_n_hill.seed = 23
	_n_hill.frequency = 1.0 / 2200.0
	_n_hill.fractal_octaves = 4
	_n_ridge.seed = 37
	_n_ridge.frequency = 1.0 / 1700.0
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_ridge.fractal_octaves = 5
	for poly in [TAIWAN, PENGHU]:
		var pts := PackedVector2Array()
		for q in poly:
			pts.append(G.geo(q[0], q[1]))
		_polys.append(pts)
	for r in RIDGE:
		var p := G.geo(r[0], r[1])
		_ridge_pts.append(Vector4(p.x, p.y, r[2], r[3]))
	for r in COAST_RANGE:
		var p := G.geo(r[0], r[1])
		_coast_pts.append(Vector4(p.x, p.y, r[2], r[3]))
	for a in G.AIRPORTS:
		var c := G.geo(a.lon, a.lat)
		var hr := deg_to_rad(a.hdg)
		_apts.append({"c": c, "u": Vector2(sin(hr), -cos(hr)), "hl": a.len * 0.5 + 650.0, "hw": 520.0, "e": a.elev})
	for c in G.CITIES:
		_cities.append(Vector3(G.geo(c[1], c[2]).x, G.geo(c[1], c[2]).y, c[3]))

# ── 有號距離（陸地為正）──
func _poly_sd(p: Vector2, pts: PackedVector2Array) -> float:
	var inside := false
	var dmin := 1e12
	var n := pts.size()
	var j := n - 1
	for i in n:
		var a := pts[i]
		var b := pts[j]
		if ((a.y > p.y) != (b.y > p.y)) and (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x):
			inside = not inside
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		dmin = minf(dmin, (a + ab * t - p).length_squared())
		j = i
	var d := sqrt(dmin)
	return d if inside else -d

func _build_sdf() -> void:
	_sdf_nx = int(W / SDF_S) + 1
	_sdf_nz = int(H / SDF_S) + 1
	_sdf.resize(_sdf_nx * _sdf_nz)
	for iz in _sdf_nz:
		for ix in _sdf_nx:
			var p := Vector2(X0 + ix * SDF_S, Z0 + iz * SDF_S)
			var d := -1e9
			for poly in _polys:
				d = maxf(d, _poly_sd(p, poly))
			_sdf[iz * _sdf_nx + ix] = d

func _sdf_at(x: float, z: float) -> float:
	var fx := clampf((x - X0) / SDF_S, 0.0, _sdf_nx - 1.001)
	var fz := clampf((z - Z0) / SDF_S, 0.0, _sdf_nz - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * _sdf_nx + ix
	var a := lerpf(_sdf[i], _sdf[i + 1], tx)
	var b := lerpf(_sdf[i + _sdf_nx], _sdf[i + _sdf_nx + 1], tx)
	return lerpf(a, b, tz)

func _chain(p: Vector2, pts: Array) -> float:
	var best := 0.0
	for i in pts.size() - 1:
		var a: Vector4 = pts[i]
		var b: Vector4 = pts[i + 1]
		var a2 := Vector2(a.x, a.y)
		var ab := Vector2(b.x, b.y) - a2
		var t := clampf((p - a2).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := (a2 + ab * t - p).length()
		var hh := lerpf(a.z, b.z, t)
		var ww := lerpf(a.w, b.w, t)
		best = maxf(best, hh * exp(-(d * d) / (ww * ww)))
	return best

func raw_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var d := _sdf_at(x, z) + _n_coast.get_noise_2d(x, z) * 380.0
	var h := 0.0
	if d <= 0.0:
		h = maxf(-80.0, -2.0 + d * 0.05)
	else:
		var hill := _n_hill.get_noise_2d(x, z)
		var plains := 2.0 + minf(d, 4000.0) * 0.010 + maxf(0.0, hill) * 70.0 * smoothstep(600.0, 3500.0, d)
		var rg := _chain(p, _ridge_pts)
		var cr := _chain(p, _coast_pts)
		var rn := _n_ridge.get_noise_2d(x, z)
		var mount := (rg + cr) * (0.62 + 0.5 * rn)
		var foot := maxf(0.0, hill + 0.15) * 300.0 * clampf((rg + cr) / 500.0, 0.0, 1.0)
		h = (plains + mount + foot) * smoothstep(0.0, 700.0, d) + minf(d, 0.0)
	for b in BUMPS:
		var c := G.geo(b[0], b[1])
		var r := (p - c).length()
		var bh: float = b[2] * exp(-(r * r) / (float(b[3]) * float(b[3])))
		if bh > 4.0:
			h = maxf(h, bh * (0.8 + 0.3 * _n_ridge.get_noise_2d(x * 2.0, z * 2.0)) - 2.0)
	# 機場整平（必要時填海造陸）
	for a in _apts:
		var rel: Vector2 = p - a.c
		var u: float = absf(rel.dot(a.u))
		var v: float = absf(rel.dot(Vector2(-a.u.y, a.u.x)))
		var ou := maxf(0.0, u - a.hl)
		var ov := maxf(0.0, v - a.hw)
		var od := sqrt(ou * ou + ov * ov)
		if od < 1100.0:
			h = lerpf(a.e, h, smoothstep(0.0, 1100.0, od))
	return h

# ── 建置 ──
func build(quality: int) -> void:
	_init_data()
	S = 150.0 if quality >= 1 else 220.0
	NX = int(W / S) + 1
	NZ = int(H / S) + 1
	_build_sdf()
	hts.resize(NX * NZ)
	for iz in NZ:
		for ix in NX:
			hts[iz * NX + ix] = raw_height(X0 + ix * S, Z0 + iz * S)
	_make_material()
	var CH := 40
	for cz in range(0, NZ - 1, CH):
		for cx in range(0, NX - 1, CH):
			_chunk(cx, cz, mini(cx + CH, NX - 1), mini(cz + CH, NZ - 1))
	_make_textures()

func _make_material() -> void:
	mat = ShaderMaterial.new()
	mat.shader = load("res://scripts/shaders/terrain.gdshader")

func height_at(x: float, z: float) -> float:
	var fx := (x - X0) / S
	var fz := (z - Z0) / S
	if fx < 0.0 or fz < 0.0 or fx >= NX - 1 or fz >= NZ - 1:
		return -60.0
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * NX + ix
	# 跟網格三角形一致的插值
	if tx + tz <= 1.0:
		return hts[i] + (hts[i + 1] - hts[i]) * tx + (hts[i + NX] - hts[i]) * tz
	return hts[i + NX + 1] + (hts[i + NX] - hts[i + NX + 1]) * (1.0 - tx) + (hts[i + 1] - hts[i + NX + 1]) * (1.0 - tz)

func _h(ix: int, iz: int) -> float:
	return hts[clampi(iz, 0, NZ - 1) * NX + clampi(ix, 0, NX - 1)]

func _normal(ix: int, iz: int) -> Vector3:
	return Vector3(_h(ix - 1, iz) - _h(ix + 1, iz), 2.0 * S, _h(ix, iz - 1) - _h(ix, iz + 1)).normalized()

func urban_at(x: float, z: float) -> float:
	var u := 0.0
	for c in _cities:
		var d := Vector2(x - c.x, z - c.y).length()
		u = maxf(u, 1.0 - smoothstep(c.z * 0.35, c.z, d))
	return u

func _color(x: float, z: float, h: float, n: Vector3) -> Array:
	var slope := 1.0 - n.y
	var c: Color
	var farm := 0.0
	var urban := 0.0
	var var1 := _n_hill.get_noise_2d(x * 3.1, z * 3.1)
	if h < 0.5:
		c = Color(0.62, 0.6, 0.48)
	elif h < 4.0 and _sdf_at(x, z) < 500.0:
		c = Color(0.78, 0.73, 0.56)
	else:
		var low := Color(0.40, 0.52, 0.25)
		var forest := Color(0.17, 0.32, 0.15)
		var high := Color(0.13, 0.26, 0.14)
		var rock := Color(0.44, 0.41, 0.36)
		c = low.lerp(forest, smoothstep(60.0, 320.0, h + var1 * 60.0))
		c = c.lerp(high, smoothstep(500.0, 1000.0, h))
		c = c.lerp(rock, clampf(smoothstep(0.32, 0.6, slope) + smoothstep(1150.0, 1350.0, h) * 0.5, 0.0, 1.0))
		if h < 110.0 and slope < 0.07:
			farm = clampf(0.6 + var1 * 1.4, 0.0, 1.0) * (1.0 - smoothstep(70.0, 110.0, h))
		urban = urban_at(x, z) * (1.0 - smoothstep(0.08, 0.2, slope))
		farm *= 1.0 - urban
	return [c, farm, urban]

func _chunk(x0: int, z0: int, x1: int, z1: int) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var w := x1 - x0 + 1
	var any_land := false
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var x := X0 + ix * S
			var z := Z0 + iz * S
			var h := _h(ix, iz)
			if h > -6.0:
				any_land = true
			var n := _normal(ix, iz)
			verts.append(Vector3(x, h, z))
			norms.append(n)
			var cc: Array = _color(x, z, h, n)
			cols.append(cc[0])
			uvs.append(Vector2(cc[1], cc[2]))
	if not any_land:
		return
	for iz in range(z1 - z0):
		for ix in range(x1 - x0):
			var i := iz * w + ix
			idx.append_array([i, i + 1, i + w, i + 1, i + w + 1, i + w])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _make_textures() -> void:
	# 海洋著色用的深度圖（L8：0＝-40m、1＝+40m）
	var him := Image.create(NX, NZ, false, Image.FORMAT_L8)
	var mw := NX / 2
	var mh := NZ / 2
	var mim := Image.create(mw, mh, false, Image.FORMAT_RGB8)
	for iz in NZ:
		for ix in NX:
			var h := hts[iz * NX + ix]
			him.set_pixel(ix, iz, Color(clampf((h + 40.0) / 80.0, 0.0, 1.0), 0, 0))
	for iz in mh:
		for ix in mw:
			var x := X0 + ix * 2 * S
			var z := Z0 + iz * 2 * S
			var h := _h(ix * 2, iz * 2)
			var c: Color
			if h <= 0.0:
				c = Color(0.13, 0.33, 0.55).lerp(Color(0.25, 0.55, 0.7), clampf(1.0 + h / 30.0, 0.0, 1.0))
			else:
				c = Color(0.45, 0.62, 0.36).lerp(Color(0.26, 0.45, 0.25), smoothstep(50.0, 500.0, h))
				c = c.lerp(Color(0.55, 0.48, 0.38), smoothstep(700.0, 1300.0, h))
				var nn := _normal(ix * 2, iz * 2)
				c = c * (0.75 + 0.5 * clampf(nn.x * -0.6 + nn.z * -0.6 + 0.6, 0.0, 1.0))
				c = c.lerp(Color(0.7, 0.68, 0.65), urban_at(x, z) * 0.8)
			mim.set_pixel(ix, iz, c)
	height_tex = ImageTexture.create_from_image(him)
	map_tex = ImageTexture.create_from_image(mim)

func is_land(x: float, z: float) -> bool:
	return height_at(x, z) > 0.5
