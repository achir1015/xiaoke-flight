class_name M
extends RefCounted
## 程序化模型與材質（全部原創）：客機、人物、機艙、機場建築、城市、樹木、臺北 101。

static var _mats: Dictionary = {}
static var font: Font = null
static var font_ui: FontVariation = null
static var font_bold: FontVariation = null
static var light_mats: Dictionary = {}

static func init_fonts() -> void:
	if font_ui:
		return
	var base: Font = load("res://assets/fonts/NotoSansTC.ttf")
	font_ui = _weight(base, 500)
	font_bold = _weight(base, 800)
	font = font_bold

static func _weight(base: Font, w: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): w}
	return fv

static func mat(c: Color, emissive: float = 0.0, rough: float = 0.75, metal: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [c.to_html(), emissive, rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m

static func light_mat(c: Color, size_px := 0.0022, inten := 1.0) -> ShaderMaterial:
	var key := "%s|%s|%s" % [c.to_html(), size_px, inten]
	if light_mats.has(key):
		return light_mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/shaders/lights.gdshader")
	m.set_shader_parameter("tint", c)
	m.set_shader_parameter("min_px", size_px)
	m.set_shader_parameter("intensity", inten)
	light_mats[key] = m
	return m

static func box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rough := 0.75) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat(c, 0.0, rough)
	parent.add_child(mi)
	return mi

static func sphere(parent: Node3D, r: float, pos: Vector3, c: Color, sy := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0 * sy
	s.radial_segments = 16
	s.rings = 8
	mi.mesh = s
	mi.position = pos
	mi.material_override = mat(c, 0.0, 0.6)
	parent.add_child(mi)
	return mi

static func capsule(parent: Node3D, r: float, h: float, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := CapsuleMesh.new()
	s.radius = r
	s.height = maxf(h, r * 2.0)
	s.radial_segments = 12
	s.rings = 4
	mi.mesh = s
	mi.position = pos
	mi.material_override = mat(c, 0.0, 0.7)
	parent.add_child(mi)
	return mi

static func cyl(parent: Node3D, r0: float, r1: float, h: float, pos: Vector3, c: Color, axis := "y", seg := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r1
	cm.bottom_radius = r0
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	if axis == "x":
		mi.rotation.z = PI / 2
	elif axis == "z":
		mi.rotation.x = PI / 2
	mi.material_override = mat(c, 0.0, 0.55)
	parent.add_child(mi)
	return mi

static func label(parent: Node3D, text: String, pos: Vector3, px: float, c: Color, rot_y := 0.0, outline := 0) -> Label3D:
	init_fonts()
	var l := Label3D.new()
	l.text = text
	l.font = font_bold
	l.font_size = 96
	l.pixel_size = px
	l.modulate = c
	l.outline_size = outline
	l.outline_modulate = Color(0, 0, 0, 0.6)
	l.position = pos
	l.rotation.y = rot_y
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.shaded = true
	parent.add_child(l)
	return l

static func light(parent: Node3D, pos: Vector3, c: Color, size := 0.5, px := 0.0018, inten := 1.4) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mi.mesh = q
	mi.scale = Vector3.ONE * size
	mi.position = pos
	mi.material_override = light_mat(c, px, inten)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

# ── 幾何工具 ──
# 三角形依「向外方向」排好正面（Godot 正面為順時針）
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3, na := Vector3.ZERO, nb := Vector3.ZERO, nc := Vector3.ZERO) -> void:
	if (b - a).cross(c - a).dot(out) > 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	var fn := -(b - a).cross(c - a).normalized()
	for p in [[a, na], [b, nb], [c, nc]]:
		var n: Vector3 = p[1]
		st.set_normal(fn if n == Vector3.ZERO else n)
		st.add_vertex(p[0])

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3) -> void:
	_tri(st, a, b, c, out)
	_tri(st, a, c, d, out)

# 翼面：根部前緣 r0、弦向 cdir、展向 sdir、厚度方向 tdir
static func surface_mesh(r0: Vector3, rc: float, tc: float, span: float, sweep_deg: float, th: float, cdir: Vector3, sdir: Vector3, tdir: Vector3, tip_drop := Vector3.ZERO) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sw := tan(deg_to_rad(sweep_deg))
	var rle := r0
	var rte := r0 + cdir * rc
	var tle := r0 + sdir * span + cdir * (span * sw) + tip_drop
	var tte := tle + cdir * tc
	var tr := th * 0.5
	var tt := th * 0.5 * maxf(0.3, tc / rc)
	# 前緣較厚、後緣較薄的簡化翼型：前緣、最厚點（25%）、後緣
	var rmid := rle + cdir * rc * 0.28
	var tmid := tle + cdir * tc * 0.28
	var rU := [rle, rmid + tdir * tr, rte + tdir * tr * 0.12]
	var rD := [rle, rmid - tdir * tr * 0.7, rte - tdir * tr * 0.1]
	var tU := [tle, tmid + tdir * tt, tte + tdir * tt * 0.12]
	var tD := [tle, tmid - tdir * tt * 0.7, tte - tdir * tt * 0.1]
	for i in 2:
		_quad(st, rU[i], rU[i + 1], tU[i + 1], tU[i], tdir + (-cdir if i == 0 else cdir) * 0.3)
		_quad(st, rD[i], rD[i + 1], tD[i + 1], tD[i], -tdir + (-cdir if i == 0 else cdir) * 0.3)
	_quad(st, rU[2], rD[2], tD[2], tU[2], cdir)
	# 封口
	_tri(st, rU[0], rU[1], rD[1], -sdir)
	_tri(st, rU[1], rU[2], rD[2], -sdir)
	_tri(st, rU[1], rD[2], rD[1], -sdir)
	_tri(st, tU[0], tU[1], tD[1], sdir)
	_tri(st, tU[1], tU[2], tD[2], sdir)
	_tri(st, tU[1], tD[2], tD[1], sdir)
	return st.commit()

static func surface(parent: Node3D, c: Color, r0: Vector3, rc: float, tc: float, span: float, sweep: float, th: float, cdir: Vector3, sdir: Vector3, tdir: Vector3, tip_drop := Vector3.ZERO, rough := 0.45) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = surface_mesh(r0, rc, tc, span, sweep, th, cdir, sdir, tdir, tip_drop)
	mi.material_override = mat(c, 0.0, rough, 0.1)
	parent.add_child(mi)
	return mi

# 迴轉體（沿 Z 軸）：profile = [[z, r, cy], ...]
static func lathe(profile: Array, seg := 32, oval := 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for p in profile:
		var ring: Array = []
		var cy: float = p[2] if p.size() > 2 else 0.0
		for k in seg + 1:
			var a := TAU * k / seg
			ring.append(Vector3(cos(a) * p[1], cy + sin(a) * p[1] * oval, p[0]))
		rings.append(ring)
	for i in profile.size() - 1:
		var cy0: float = profile[i][2] if profile[i].size() > 2 else 0.0
		var cy1: float = profile[i + 1][2] if profile[i + 1].size() > 2 else 0.0
		for k in seg:
			var a: Vector3 = rings[i][k]
			var b: Vector3 = rings[i][k + 1]
			var c: Vector3 = rings[i + 1][k + 1]
			var d: Vector3 = rings[i + 1][k]
			var out := ((a + b + c + d) * 0.25 - Vector3(0, (cy0 + cy1) * 0.5, (a.z + d.z) * 0.5)).normalized()
			var na := Vector3(a.x, (a.y - cy0) / oval, 0).normalized()
			var nb := Vector3(b.x, (b.y - cy0) / oval, 0).normalized()
			var nc := Vector3(c.x, (c.y - cy1) / oval, 0).normalized()
			var nd := Vector3(d.x, (d.y - cy1) / oval, 0).normalized()
			if na == Vector3.ZERO: na = out
			if nb == Vector3.ZERO: nb = out
			if nc == Vector3.ZERO: nc = out
			if nd == Vector3.ZERO: nd = out
			_tri(st, a, b, c, out, na, nb, nc)
			_tri(st, a, c, d, out, na, nc, nd)
	return st.commit()

# ── 客機（機頭朝 -Z，原點在機身中心線上）──
const GEAR_H := 4.9   # 機輪著地時原點離地高度

static func airliner(livery := 0) -> Node3D:
	var n := Node3D.new()
	n.name = "Airliner"
	var R := 2.9
	var L := 57.0
	var z0 := -L * 0.5
	var white := Color(0.95, 0.96, 0.97)
	var grey := Color(0.72, 0.75, 0.79)
	var liv: Array = [[Color(0.95, 0.53, 0.2), Color(0.18, 0.43, 0.82)], [Color(0.85, 0.15, 0.2), Color(0.2, 0.25, 0.35)], [Color(0.1, 0.6, 0.45), Color(0.95, 0.75, 0.2)]][livery % 3]
	# 機身
	var prof: Array = []
	var N := 64
	for i in N + 1:
		var t := float(i) / N
		t = t * t * (3.0 - 2.0 * t) * 0.35 + t * 0.65   # 頭尾加密
		var r := R
		var cy := 0.0
		if t < 0.11:
			var k := t / 0.11
			r = R * sqrt(maxf(0.0, 1.0 - (1.0 - k) * (1.0 - k)))
			cy = -0.32 * R * (1.0 - k) * (1.0 - k)
		elif t > 0.68:
			var k := (t - 0.68) / 0.32
			r = R * (1.0 - 0.9 * pow(k, 1.35))
			cy = R * 0.62 * pow(k, 1.5)
		prof.append([z0 + t * L, maxf(r, 0.02), cy])
	var fus := MeshInstance3D.new()
	fus.mesh = lathe(prof, 36, 1.04)
	var fm := ShaderMaterial.new()
	fm.shader = load("res://scripts/shaders/fuselage.gdshader")
	fm.set_shader_parameter("stripe1", liv[0])
	fm.set_shader_parameter("stripe2", liv[1])
	fm.set_shader_parameter("nose_z", z0)
	fm.set_shader_parameter("len", L)
	fm.set_shader_parameter("radius", R)
	fus.material_override = fm
	fus.name = "Fuselage"
	n.add_child(fus)
	# 機翼（下單翼、後掠、上反角）
	var wing_root_z := -7.5
	var wy := -R * 0.62
	var dih := 0.09
	for side in [1.0, -1.0]:
		var sdir := Vector3(side, dih, 0).normalized()
		var w := surface(n, white, Vector3(side * R * 0.6, wy, wing_root_z), 11.5, 2.4, 27.5, 31.0, 1.4, Vector3(0, 0, 1), sdir, Vector3(0, 1, 0))
		w.name = "WingR" if side > 0 else "WingL"
		# 翼尖小翼
		var tip := Vector3(side * R * 0.6, wy, wing_root_z) + sdir * 27.5 + Vector3(0, 0, 27.5 * tan(deg_to_rad(31.0)))
		surface(n, liv[1], tip + Vector3(0, 0.1, 0.2), 2.2, 0.9, 3.4, 40.0, 0.3, Vector3(0, 0, 1), Vector3(side * 0.25, 1, 0).normalized(), Vector3(1, 0, 0))
		# 航行燈
		var lc := Color(0.1, 1.0, 0.2) if side > 0 else Color(1.0, 0.12, 0.1)
		var nl := light(n, tip + Vector3(side * 0.2, 0.1, 0.5), lc, 0.5, 0.0016, 1.6)
		nl.name = "NavR" if side > 0 else "NavL"
		var sl := light(n, tip + Vector3(side * 0.2, 0.1, 2.0), Color(1, 1, 1), 0.7, 0.0025, 3.0)
		sl.name = "StrobeR" if side > 0 else "StrobeL"
		sl.visible = false
		# 襟翼與副翼（後緣鉸鍊）
		var te_root := Vector3(side * R * 0.6, wy, wing_root_z + 11.5)
		var te_tip := tip + Vector3(0, 0, 2.4)
		var te := te_tip - te_root
		_hinged(n, "Flap" + ("R" if side > 0 else "L"), te_root + te * 0.04, te_root + te * 0.55, 3.2, 1.6, grey, side)
		_hinged(n, "Ail" + ("R" if side > 0 else "L"), te_root + te * 0.62, te_root + te * 0.88, 1.8, 0.95, grey, side)
		# 擾流板（翼面上方，前緣鉸鍊）
		_hinged(n, "Spl" + ("R" if side > 0 else "L"), te_root + te * 0.1 + Vector3(0, 0.45, -3.4), te_root + te * 0.55 + Vector3(0, 0.45, -3.4), 1.8, 0.12, Color(0.88, 0.9, 0.92), side)
		# 引擎
		var ep := Vector3(side * 9.8, wy - 2.3, wing_root_z + 9.8 * tan(deg_to_rad(31.0)) - 4.6)
		_engine(n, ep, white, liv[0], side)
	# 翼身整流罩
	var fair := sphere(n, 1.0, Vector3(0, -R * 0.78, -1.5), grey)
	fair.scale = Vector3(R * 1.05, R * 0.42, 12.0)
	# 水平尾翼
	var tz := z0 + L * 0.86
	var ty := R * 0.5
	for side in [1.0, -1.0]:
		var sdir := Vector3(side, 0.12, 0).normalized()
		surface(n, white, Vector3(side * 0.6, ty, tz - 2.0), 6.0, 2.2, 10.0, 36.0, 0.7, Vector3(0, 0, 1), sdir, Vector3(0, 1, 0))
		var e0 := Vector3(side * 0.6, ty, tz + 4.0)
		var e1 := Vector3(side * 0.6, ty, tz - 2.0) + sdir * 9.6 + Vector3(0, 0, 9.6 * tan(deg_to_rad(36.0)) + 2.2)
		_hinged(n, "Elev" + ("R" if side > 0 else "L"), e0, e1, 1.6, 0.6, grey, side)
	# 垂直尾翼與方向舵
	var fz := z0 + L * 0.8
	var fin := surface(n, liv[1], Vector3(0, R * 0.85, fz), 8.6, 3.0, 10.5, 40.0, 0.9, Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0))
	fin.name = "Fin"
	var rud := Node3D.new()
	rud.name = "Rudder"
	rud.position = Vector3(0, R * 0.85, fz + 8.6)
	var top := Vector3(0, 10.5, 10.5 * tan(deg_to_rad(40.0)) + 3.0 - 8.6)
	var yv := top.normalized()
	rud.basis = Basis(Vector3.RIGHT, yv, Vector3.RIGHT.cross(yv))
	n.add_child(rud)
	surface(rud, liv[0], Vector3(0, 0, 0), 2.2, 1.2, top.length() * 0.92, -8.0, 0.5, Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0))
	# 尾翼標誌
	var logo := Sprite3D.new()
	logo.texture = robot_texture(256)
	logo.pixel_size = 0.019
	logo.position = Vector3(0.48, R * 0.85 + 5.2, fz + 6.3)
	logo.rotation.y = PI / 2
	logo.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	n.add_child(logo)
	var logo2: Sprite3D = logo.duplicate()
	logo2.position.x = -0.48
	logo2.rotation.y = -PI / 2
	n.add_child(logo2)
	# 機身字樣
	label(n, "小柯航空", Vector3(R * 1.02 + 0.02, R * 0.48, -11.0), 0.028, Color(0.12, 0.2, 0.38), PI / 2)
	label(n, "小柯航空", Vector3(-R * 1.02 - 0.02, R * 0.48, -11.0), 0.028, Color(0.12, 0.2, 0.38), -PI / 2)
	label(n, "XIAOKE AIR", Vector3(R * 1.02 + 0.02, R * 0.48, 1.5), 0.02, Color(0.12, 0.2, 0.38), PI / 2)
	label(n, "XIAOKE AIR", Vector3(-R * 1.02 - 0.02, R * 0.48, 1.5), 0.02, Color(0.12, 0.2, 0.38), -PI / 2)
	label(n, "B-18888", Vector3(R * 0.62, R * 0.5, 20.5), 0.012, Color(0.2, 0.22, 0.28), PI / 2)
	label(n, "B-18888", Vector3(-R * 0.62, R * 0.5, 20.5), 0.012, Color(0.2, 0.22, 0.28), -PI / 2)
	# 防撞燈、尾燈
	var b1 := light(n, Vector3(0, R * 1.05, -4.0), Color(1, 0.1, 0.05), 0.45, 0.0016, 2.5)
	b1.name = "BeaconT"
	var b2 := light(n, Vector3(0, -R * 1.05, 2.0), Color(1, 0.1, 0.05), 0.45, 0.0016, 2.5)
	b2.name = "BeaconB"
	light(n, Vector3(0, R * 0.95, L * 0.5 - 0.3), Color(1, 1, 1), 0.4, 0.0014, 1.4)
	# 起落架
	_gear(n, "GearN", Vector3(0, -R * 0.85, z0 + 6.0), false)
	_gear(n, "GearL", Vector3(-4.6, wy - 0.4, -0.3), true)
	_gear(n, "GearR", Vector3(4.6, wy - 0.4, -0.3), true)
	# 落地燈
	var ll := light(n, Vector3(0, -R * 0.6, z0 + 5.2), Color(1, 0.98, 0.9), 0.6, 0.002, 2.0)
	ll.name = "LandLight"
	return n

static func _hinged(n: Node3D, nm: String, a: Vector3, b: Vector3, chord: float, th: float, c: Color, side: float) -> void:
	# 鉸鍊節點：X 軸由左往右，控制面往 +Z 延伸，繞 X 軸正轉＝後緣往下
	var p0 := a if side > 0 else b
	var p1 := b if side > 0 else a
	var xa := (p1 - p0)
	var piv := Node3D.new()
	piv.name = nm
	piv.position = p0
	var xn := xa.normalized()
	var zn := Vector3(0, 0, 1)
	zn = (zn - xn * zn.dot(xn)).normalized()
	var yn := zn.cross(xn).normalized()
	piv.basis = Basis(xn, yn, zn)
	n.add_child(piv)
	surface(piv, c, Vector3.ZERO, chord, chord * 0.85, xa.length(), 0.0, th, Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0))

static func _engine(n: Node3D, p: Vector3, body: Color, lip: Color, side: float) -> void:
	var e := Node3D.new()
	e.name = "EngR" if side > 0 else "EngL"
	e.position = p
	n.add_child(e)
	var nac := MeshInstance3D.new()
	nac.mesh = lathe([[-3.6, 1.55], [-3.4, 1.72], [-2.6, 1.82], [0.0, 1.78], [1.6, 1.45], [2.6, 1.05], [3.2, 0.82]], 28)
	nac.material_override = mat(body, 0.0, 0.35, 0.15)
	e.add_child(nac)
	var lipm := MeshInstance3D.new()
	lipm.mesh = lathe([[-3.62, 1.5], [-3.45, 1.74], [-3.0, 1.8]], 28)
	lipm.material_override = mat(Color(0.85, 0.87, 0.9), 0.0, 0.25, 0.6)
	e.add_child(lipm)
	# 進氣口內部（深色）＋風扇轂
	var fan := cyl(e, 1.48, 1.48, 0.1, Vector3(0, 0, -3.2), Color(0.08, 0.09, 0.11), "z", 28)
	fan.name = "Fan"
	var spin := MeshInstance3D.new()
	spin.mesh = lathe([[-3.35, 0.02], [-3.1, 0.3], [-2.9, 0.5]], 16)
	spin.material_override = mat(Color(0.75, 0.78, 0.82), 0.0, 0.3, 0.7)
	e.add_child(spin)
	# 噴嘴
	var noz := MeshInstance3D.new()
	noz.mesh = lathe([[3.1, 0.85], [3.9, 0.55], [4.6, 0.12]], 20)
	noz.material_override = mat(Color(0.35, 0.33, 0.32), 0.0, 0.5, 0.5)
	e.add_child(noz)
	# 橘色條紋
	var band := MeshInstance3D.new()
	band.mesh = lathe([[-1.9, 1.83], [-1.3, 1.83]], 28)
	band.material_override = mat(lip, 0.0, 0.4)
	e.add_child(band)
	# 派龍架
	box(e, Vector3(0.45, 1.8, 5.5), Vector3(0, 1.75, 0.6), body, 0.4)

static func _gear(n: Node3D, nm: String, p: Vector3, main: bool) -> void:
	var g := Node3D.new()
	g.name = nm
	g.position = p
	n.add_child(g)
	var drop: float = -(GEAR_H + p.y)    # 支柱長度（到輪子底部）
	var dark := Color(0.12, 0.12, 0.13)
	var metal := Color(0.62, 0.64, 0.66)
	cyl(g, 0.22 if main else 0.16, 0.22 if main else 0.16, drop - 0.6, Vector3(0, -(drop - 0.6) * 0.5, 0), metal)
	if main:
		box(g, Vector3(0.4, 0.3, 3.2), Vector3(0, drop * -1.0 + 0.62, 0), metal)
		for zz in [-1.1, 1.1]:
			for xx in [-0.65, 0.65]:
				cyl(g, 0.6, 0.6, 0.45, Vector3(xx, -drop + 0.6, zz), dark, "x", 18)
				cyl(g, 0.3, 0.3, 0.47, Vector3(xx, -drop + 0.6, zz), Color(0.55, 0.57, 0.6), "x", 12)
	else:
		for xx in [-0.32, 0.32]:
			cyl(g, 0.48, 0.48, 0.32, Vector3(xx, -drop + 0.48, 0), dark, "x", 16)
			cyl(g, 0.22, 0.22, 0.34, Vector3(xx, -drop + 0.48, 0), Color(0.55, 0.57, 0.6), "x", 10)

# 小柯機器人頭像（尾翼標誌、介面）
static func robot_svg() -> String:
	return "<svg xmlns='http://www.w3.org/2000/svg' width='256' height='256' viewBox='0 0 256 256'><circle cx='128' cy='128' r='120' fill='#ffffff'/><circle cx='128' cy='128' r='112' fill='#f0883a'/><rect x='52' y='70' width='152' height='118' rx='46' fill='#ffffff'/><rect x='72' y='92' width='112' height='68' rx='24' fill='#152038'/><circle cx='106' cy='124' r='12' fill='#62f0ff'/><circle cx='150' cy='124' r='12' fill='#62f0ff'/><path d='M112 144 Q128 154 144 144' fill='none' stroke='#62f0ff' stroke-width='6' stroke-linecap='round'/><line x1='128' y1='70' x2='128' y2='46' stroke='#ffffff' stroke-width='7'/><circle cx='128' cy='40' r='10' fill='#ffffff'/></svg>"

static var _robot_tex: Dictionary = {}
static func robot_texture(size := 256) -> Texture2D:
	if _robot_tex.has(size):
		return _robot_tex[size]
	var img := Image.new()
	img.load_svg_from_string(robot_svg(), size / 256.0)
	var t := ImageTexture.create_from_image(img)
	_robot_tex[size] = t
	return t

# ── 人物（坐姿／站姿）──
const SKIN := [Color(0.96, 0.82, 0.68), Color(0.9, 0.74, 0.58), Color(0.8, 0.62, 0.46), Color(0.98, 0.86, 0.74)]
const HAIR := [Color(0.08, 0.07, 0.07), Color(0.18, 0.12, 0.08), Color(0.35, 0.22, 0.12), Color(0.75, 0.75, 0.76)]
const CLOTH := [Color(0.85, 0.3, 0.3), Color(0.25, 0.45, 0.75), Color(0.3, 0.6, 0.4), Color(0.9, 0.75, 0.3), Color(0.55, 0.4, 0.7), Color(0.95, 0.95, 0.95), Color(0.3, 0.3, 0.35), Color(0.9, 0.55, 0.65)]

static func person(kind: String, seated := true, seed_i := 0) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i * 7919 + 13
	var n := Node3D.new()
	var skin: Color = SKIN[rng.randi() % SKIN.size()]
	var hair: Color = HAIR[rng.randi() % 3]
	var cloth: Color = CLOTH[rng.randi() % CLOTH.size()]
	var pants := Color(0.2, 0.22, 0.3)
	var long_hair := rng.randf() < 0.45
	match kind:
		"attendant":
			cloth = Color(0.13, 0.2, 0.42)
			pants = Color(0.13, 0.2, 0.42)
			long_hair = true
			hair = HAIR[0]
		"copilot", "captain":
			cloth = Color(0.95, 0.96, 0.98)
			pants = Color(0.1, 0.13, 0.22)
			long_hair = false
		"elder":
			hair = HAIR[3]
			cloth = Color(0.55, 0.45, 0.35)
			long_hair = false
		"pregnant":
			cloth = Color(0.95, 0.65, 0.72)
			long_hair = true
		"heart":
			cloth = Color(0.3, 0.42, 0.62)
			long_hair = false
		"hijacker":
			cloth = Color(0.14, 0.14, 0.16)
			pants = Color(0.1, 0.1, 0.12)
			long_hair = false
		"doctor":
			cloth = Color(0.92, 0.94, 0.96)
			long_hair = false
		"police":
			cloth = Color(0.08, 0.1, 0.14)
			pants = Color(0.08, 0.1, 0.14)
	var hip_y := 0.48 if seated else 0.95
	var body := Node3D.new()
	body.name = "Body"
	body.position.y = hip_y
	n.add_child(body)
	capsule(body, 0.2, 0.62, Vector3(0, 0.3, 0), cloth)
	if kind == "pregnant":
		sphere(body, 0.17, Vector3(0, 0.2, -0.13), cloth)
	if kind == "doctor":
		box(body, Vector3(0.36, 0.5, 0.05), Vector3(0, 0.32, -0.19), Color(0.98, 0.98, 1.0))
	if kind == "attendant":
		box(body, Vector3(0.12, 0.08, 0.04), Vector3(0.0, 0.52, -0.2), Color(0.95, 0.53, 0.2))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.78, 0)
	body.add_child(head)
	sphere(head, 0.14, Vector3.ZERO, skin, 1.1)
	var hcap := sphere(head, 0.148, Vector3(0, 0.04, 0.02), hair, 1.0)
	hcap.scale = Vector3(1, 0.8, 1)
	if long_hair:
		box(head, Vector3(0.26, 0.26, 0.08), Vector3(0, -0.06, 0.1), hair)
	for ex in [-0.05, 0.05]:
		sphere(head, 0.018, Vector3(ex, 0.02, -0.13), Color(0.05, 0.05, 0.06))
	var mouth := box(head, Vector3(0.06, 0.012, 0.01), Vector3(0, -0.06, -0.135), Color(0.55, 0.25, 0.25))
	mouth.name = "Mouth"
	if kind == "hijacker":
		box(head, Vector3(0.3, 0.06, 0.3), Vector3(0, 0.12, 0), Color(0.1, 0.1, 0.12))
		box(head, Vector3(0.2, 0.03, 0.12), Vector3(0, 0.1, -0.18), Color(0.1, 0.1, 0.12))
	if kind == "copilot" or kind == "captain":
		box(head, Vector3(0.3, 0.07, 0.3), Vector3(0, 0.13, 0), Color(0.1, 0.13, 0.22))
		box(body, Vector3(0.1, 0.03, 0.03), Vector3(0.2, 0.62, 0), Color(0.95, 0.78, 0.25))
		box(body, Vector3(0.1, 0.03, 0.03), Vector3(-0.2, 0.62, 0), Color(0.95, 0.78, 0.25))
	if kind == "police":
		box(head, Vector3(0.32, 0.18, 0.32), Vector3(0, 0.1, 0), Color(0.08, 0.1, 0.14))
	for sx in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "ArmL" if sx < 0 else "ArmR"
		arm.position = Vector3(sx * 0.25, 0.55, 0)
		body.add_child(arm)
		capsule(arm, 0.065, 0.48, Vector3(0, -0.22, 0), cloth)
		sphere(arm, 0.055, Vector3(0, -0.48, 0), skin)
		if seated:
			arm.rotation.x = -0.6
		var leg := Node3D.new()
		leg.name = "LegL" if sx < 0 else "LegR"
		leg.position = Vector3(sx * 0.1, 0.0, 0)
		body.add_child(leg)
		if seated:
			capsule(leg, 0.085, 0.45, Vector3(0, 0, -0.22), pants).rotation.x = PI / 2
			capsule(leg, 0.075, 0.45, Vector3(0, -0.24, -0.44), pants)
			box(leg, Vector3(0.11, 0.06, 0.22), Vector3(0, -0.46, -0.5), Color(0.1, 0.1, 0.1))
		else:
			capsule(leg, 0.085, 0.9, Vector3(0, -0.45, 0), pants)
			box(leg, Vector3(0.11, 0.06, 0.22), Vector3(0, -0.92, -0.04), Color(0.1, 0.1, 0.1))
	return n

# ── 機艙內部（3-3 單走道，沿 -Z 往機頭）──
static func cabin(rows: int) -> Node3D:
	var n := Node3D.new()
	var W := 3.7
	var pitch := 0.82
	var Lc := rows * pitch + 4.0
	var carpet := Color(0.22, 0.27, 0.4)
	box(n, Vector3(W, 0.1, Lc), Vector3(0, -0.05, -Lc * 0.5 + 2.0), Color(0.55, 0.56, 0.6))
	box(n, Vector3(0.5, 0.11, Lc), Vector3(0, -0.04, -Lc * 0.5 + 2.0), carpet)
	# 側牆與窗戶
	for sx in [-1.0, 1.0]:
		box(n, Vector3(0.1, 2.1, Lc), Vector3(sx * W * 0.5, 1.0, -Lc * 0.5 + 2.0), Color(0.9, 0.9, 0.88))
		for r in rows:
			var z := 1.0 - r * pitch - 0.3
			var w := box(n, Vector3(0.02, 0.32, 0.24), Vector3(sx * (W * 0.5 - 0.06), 1.05, z), Color(0.65, 0.82, 1.0))
			w.material_override = mat(Color(0.65, 0.82, 1.0), 1.2)
			w.name = "Win"
		# 行李櫃
		box(n, Vector3(0.62, 0.4, Lc - 1.5), Vector3(sx * (W * 0.5 - 0.36), 1.82, -Lc * 0.5 + 2.0), Color(0.93, 0.93, 0.92))
		var strip := box(n, Vector3(0.04, 0.03, Lc - 1.5), Vector3(sx * (W * 0.5 - 0.68), 1.6, -Lc * 0.5 + 2.0), Color(0.75, 0.85, 1.0))
		strip.material_override = mat(Color(0.75, 0.85, 1.0), 2.0)
	box(n, Vector3(W, 0.08, Lc), Vector3(0, 2.15, -Lc * 0.5 + 2.0), Color(0.95, 0.95, 0.94))
	# 座椅
	var seat_c := Color(0.16, 0.3, 0.58)
	for r in rows:
		var z := 1.0 - r * pitch
		for k in 6:
			var x: float = [-1.42, -0.92, -0.42, 0.42, 0.92, 1.42][k]
			box(n, Vector3(0.46, 0.12, 0.46), Vector3(x, 0.42, z - 0.06), seat_c)
			box(n, Vector3(0.46, 0.68, 0.1), Vector3(x, 0.8, z + 0.17), seat_c)
			box(n, Vector3(0.36, 0.14, 0.02), Vector3(x, 1.06, z + 0.11), Color(0.95, 0.95, 0.96))
			box(n, Vector3(0.05, 0.05, 0.4), Vector3(x + 0.24, 0.6, z - 0.04), Color(0.3, 0.3, 0.32))
	# 機頭隔板與駕駛艙門
	var fz := 1.0 - rows * pitch - 0.9
	box(n, Vector3(W, 2.1, 0.1), Vector3(0, 1.05, fz), Color(0.82, 0.83, 0.86))
	var door := box(n, Vector3(0.8, 1.9, 0.12), Vector3(0, 0.95, fz + 0.02), Color(0.55, 0.58, 0.64))
	door.name = "CockpitDoor"
	label(n, "駕駛艙", Vector3(0, 1.75, fz + 0.1), 0.0025, Color(0.15, 0.17, 0.2))
	# 頭頂燈光
	var ol := OmniLight3D.new()
	ol.position = Vector3(0, 1.9, -Lc * 0.25)
	ol.omni_range = Lc
	ol.light_energy = 0.8
	n.add_child(ol)
	var ol2 := OmniLight3D.new()
	ol2.position = Vector3(0, 1.9, -Lc * 0.75)
	ol2.omni_range = Lc
	ol2.light_energy = 0.8
	n.add_child(ol2)
	return n

static func seat_pos(row: int, col: int) -> Vector3:
	var x: float = [-1.42, -0.92, -0.42, 0.42, 0.92, 1.42][col]
	return Vector3(x, 0.0, 1.0 - row * 0.82 - 0.05)

# ── 機場建築 ──
static func tower(parent: Node3D, p: Vector3) -> void:
	cyl(parent, 4.5, 3.5, 42.0, p + Vector3(0, 21, 0), Color(0.82, 0.83, 0.85), "y", 12)
	cyl(parent, 7.0, 8.0, 7.0, p + Vector3(0, 45.5, 0), Color(0.1, 0.18, 0.25), "y", 12).material_override = mat(Color(0.12, 0.25, 0.35), 0.0, 0.1, 0.6)
	cyl(parent, 8.5, 7.5, 2.0, p + Vector3(0, 50, 0), Color(0.9, 0.9, 0.92), "y", 12)
	cyl(parent, 0.3, 0.3, 10.0, p + Vector3(0, 56, 0), Color(0.8, 0.2, 0.2))
	light(parent, p + Vector3(0, 61.2, 0), Color(1, 0.15, 0.1), 1.2, 0.002, 2.0)

static func terminal(parent: Node3D, p: Vector3, yaw: float, w := 260.0) -> void:
	var t := Node3D.new()
	t.position = p
	t.rotation.y = yaw
	parent.add_child(t)
	box(t, Vector3(w, 16, 60), Vector3(0, 8, 0), Color(0.86, 0.87, 0.9))
	var glass := box(t, Vector3(w + 0.4, 10, 60.4), Vector3(0, 9, 0), Color(0.3, 0.5, 0.65))
	glass.material_override = mat(Color(0.25, 0.45, 0.6), 0.0, 0.08, 0.7)
	glass.scale = Vector3(1, 1, 0.9)
	# 弧形屋頂
	var roof := cyl(t, 32.0, 32.0, w + 8.0, Vector3(0, 12, 0), Color(0.75, 0.78, 0.82), "x", 24)
	roof.scale = Vector3(1, 0.25, 1)
	# 空橋
	for i in 4:
		var x := -w * 0.35 + i * w * 0.23
		box(t, Vector3(4, 4, 34), Vector3(x, 6, -46), Color(0.82, 0.83, 0.86))

static func hangar(parent: Node3D, p: Vector3, yaw: float) -> void:
	var t := Node3D.new()
	t.position = p
	t.rotation.y = yaw
	parent.add_child(t)
	box(t, Vector3(90, 14, 70), Vector3(0, 7, 0), Color(0.62, 0.65, 0.7))
	var roof := cyl(t, 45.0, 45.0, 70.0, Vector3(0, 14, 0), Color(0.55, 0.58, 0.64), "z", 20)
	roof.scale = Vector3(1, 0.22, 1)
	box(t, Vector3(80, 12, 0.6), Vector3(0, 6, -35.2), Color(0.42, 0.45, 0.5))

static func taipei101(parent: Node3D, p: Vector3) -> void:
	var t := Node3D.new()
	t.position = p
	parent.add_child(t)
	var g := Color(0.33, 0.52, 0.5)
	box(t, Vector3(44, 60, 44), Vector3(0, 30, 0), g)
	var y := 60.0
	for i in 8:
		var seg := cyl(t, 18.0, 23.0, 30.0, Vector3(0, y + 15.0, 0), g, "y", 4)
		seg.rotation.y = PI / 4
		seg.material_override = mat(g, 0.0, 0.2, 0.5)
		y += 30.0
	box(t, Vector3(20, 30, 20), Vector3(0, y + 15, 0), g)
	cyl(t, 2.0, 0.5, 60.0, Vector3(0, y + 60, 0), Color(0.8, 0.82, 0.84))
	light(t, Vector3(0, y + 92, 0), Color(1, 0.2, 0.1), 3.0, 0.002, 2.0)
