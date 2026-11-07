class_name World
extends Node3D
## 3D 世界：天空與光線（時段）、海洋、臺灣地形、機場（跑道、燈光、PAPI、塔台、航廈）、城市、樹木、雲、降水與閃電。

var terrain: Terrain
var env: Environment
var we: WorldEnvironment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var ocean: MeshInstance3D
var ocean_mat: ShaderMaterial
var cloud_mat: ShaderMaterial
var overcast: MeshInstance3D
var overcast_mat: ShaderMaterial
var precip: Node3D
var precip_mats: Array = []
var bld_mat: ShaderMaterial
var runway_mats: Array = []
var papis: Array = []      # [{node, lights:[MeshInstance3D], thr, dir}]
var socks: Array = []
var time_key := "day"
var night := 0.0
var base_fog := 0.00003
var fog_col := Color(0.7, 0.78, 0.88)
var cloud_base := 1300.0
var cloud_top := 1900.0
var overcast_on := false
var _flash := 0.0
var _bolt: Node3D
var _bolt_t := 0.0
var light_mats: Array = []
var ships: Array = []
var wind_dir := 0.0

func setup(tkey: String, weather: String, quality: int) -> void:
	time_key = tkey
	_env()
	terrain = Terrain.new()
	add_child(terrain)
	terrain.build(quality)
	_ocean()
	bld_mat = ShaderMaterial.new()
	bld_mat.shader = load("res://scripts/shaders/building.gdshader")
	for a in G.AIRPORTS:
		_airport(a, quality)
	_cities(quality)
	_clouds(quality, weather)
	_precip()
	_ships()
	set_time(tkey)
	set_weather_look(weather, 0.0)

# ── 天空與光 ──
func _env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	sky_mat.sun_curve = 0.12
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.00003
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.4
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	we = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 450.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_bias = 0.08
	add_child(sun)

func set_time(tkey: String) -> void:
	time_key = tkey
	match tkey:
		"dusk":
			sun.rotation_degrees = Vector3(-7, -115, 0)
			sun.light_color = Color(1.0, 0.62, 0.38)
			sun.light_energy = 1.1
			sky_mat.sky_top_color = Color(0.2, 0.27, 0.52)
			sky_mat.sky_horizon_color = Color(0.98, 0.62, 0.4)
			sky_mat.ground_horizon_color = Color(0.7, 0.5, 0.4)
			sky_mat.ground_bottom_color = Color(0.2, 0.18, 0.2)
			fog_col = Color(0.85, 0.6, 0.48)
			night = 0.45
			env.ambient_light_energy = 0.7
		"night":
			sun.rotation_degrees = Vector3(-38, 30, 0)
			sun.light_color = Color(0.55, 0.65, 0.95)
			sun.light_energy = 0.12
			sky_mat.sky_top_color = Color(0.01, 0.015, 0.05)
			sky_mat.sky_horizon_color = Color(0.05, 0.07, 0.14)
			sky_mat.ground_horizon_color = Color(0.04, 0.05, 0.09)
			sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.02)
			sky_mat.sun_angle_max = 2.0
			fog_col = Color(0.05, 0.07, 0.12)
			night = 1.0
			env.ambient_light_energy = 0.35
		_:
			sun.rotation_degrees = Vector3(-52, -140, 0)
			sun.light_color = Color(1.0, 0.97, 0.92)
			sun.light_energy = 1.25
			sky_mat.sky_top_color = Color(0.2, 0.43, 0.82)
			sky_mat.sky_horizon_color = Color(0.64, 0.76, 0.9)
			sky_mat.ground_horizon_color = Color(0.6, 0.68, 0.78)
			sky_mat.ground_bottom_color = Color(0.25, 0.3, 0.35)
			fog_col = Color(0.72, 0.8, 0.9)
			night = 0.0
			env.ambient_light_energy = 0.9
	env.fog_light_color = fog_col
	terrain.mat.set_shader_parameter("night", night)
	ocean_mat.set_shader_parameter("night", night)
	if bld_mat:
		bld_mat.set_shader_parameter("night", night)
	var li := 0.55 + night * 2.2
	for m in light_mats:
		(m as ShaderMaterial).set_shader_parameter("intensity", li)

# 天氣外觀：kind＝clear/cloudy/rain/storm/typhoon/snow；k 0..1 強度
var weather_kind := "clear"
func set_weather_look(kind: String, k: float) -> void:
	weather_kind = kind
	var gray := 0.0
	match kind:
		"cloudy": gray = 0.3; base_fog = 0.00005
		"rain": gray = 0.6; base_fog = 0.00022
		"storm": gray = 0.75; base_fog = 0.00026
		"typhoon": gray = 0.85; base_fog = 0.00034
		"snow": gray = 0.6; base_fog = 0.00025
		_: gray = 0.0; base_fog = 0.000028
	overcast_on = kind in ["rain", "storm", "typhoon", "snow"]
	overcast.visible = overcast_on
	var gc := Color(0.45, 0.48, 0.52) if night < 0.9 else Color(0.03, 0.035, 0.05)
	sky_mat.sky_top_color = sky_mat.sky_top_color.lerp(gc * 0.8, gray * 0.85)
	sky_mat.sky_horizon_color = sky_mat.sky_horizon_color.lerp(gc, gray * 0.85)
	env.fog_light_color = fog_col.lerp(gc, gray)
	sun.light_energy *= (1.0 - gray * 0.55)
	cloud_mat.set_shader_parameter("dark", gray * 0.7 + night * 0.6)
	var storm := 0.0
	if kind == "storm": storm = 0.5
	if kind == "typhoon": storm = 1.0
	if kind == "rain": storm = 0.2
	ocean_mat.set_shader_parameter("storm", storm)
	var wet := 1.0 if kind in ["rain", "storm", "typhoon"] else 0.0
	terrain.mat.set_shader_parameter("wet", wet * 0.6)
	terrain.mat.set_shader_parameter("snow", 1.0 if kind == "snow" else 0.0)
	terrain.mat.set_shader_parameter("snow_line", 650.0 if kind == "snow" else 9000.0)
	for m in runway_mats:
		(m as ShaderMaterial).set_shader_parameter("wet", wet)
		(m as ShaderMaterial).set_shader_parameter("snow", 0.6 if kind == "snow" else 0.0)
	for m in precip_mats:
		(m as ShaderMaterial).set_shader_parameter("snow", 1.0 if kind == "snow" else 0.0)
	env.fog_density = base_fog

# ── 海洋 ──
func _ocean() -> void:
	ocean = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(140000, 140000)
	ocean.mesh = pm
	ocean_mat = ShaderMaterial.new()
	ocean_mat.shader = load("res://scripts/shaders/ocean.gdshader")
	ocean_mat.set_shader_parameter("hmap", terrain.height_tex)
	ocean_mat.set_shader_parameter("hrect", Vector4(Terrain.X0, Terrain.Z0, (terrain.NX - 1) * terrain.S, (terrain.NZ - 1) * terrain.S))
	ocean.material_override = ocean_mat
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ocean.position.y = 0.0
	add_child(ocean)

# ── 機場 ──
func _airport(a: Dictionary, quality: int) -> void:
	var c := G.apt_pos(a)
	var node := Node3D.new()
	node.name = a.id
	node.position = c
	node.rotation.y = -deg_to_rad(a.hdg)
	add_child(node)
	var L: float = a.len
	var Wd := 45.0
	# 道肩
	_quad_mesh(node, Vector3(0, 0.08, 0), 70.0, L + 120.0, null, Color(0.32, 0.33, 0.33))
	# 跑道
	var rm := ShaderMaterial.new()
	rm.shader = load("res://scripts/shaders/runway.gdshader")
	rm.set_shader_parameter("len", L)
	rm.set_shader_parameter("wid", Wd)
	runway_mats.append(rm)
	_quad_mesh(node, Vector3(0, 0.14, 0), Wd, L, rm, Color.WHITE)
	# 跑道號碼
	for i in 2:
		var lb := M.label(node, a.rwy[i], Vector3(0, 0.2, (L * 0.5 - 95.0) * (1 if i == 0 else -1)), 0.22, Color(0.93, 0.93, 0.93))
		lb.rotation = Vector3(-PI / 2, 0 if i == 0 else PI, 0)
		lb.shaded = false
	# 滑行道、聯絡道、停機坪
	var side := 1.0
	var tw := Color(0.27, 0.27, 0.28)
	M.box(node, Vector3(23, 0.3, L), Vector3(side * 190, 0.05, 0), tw)
	M.box(node, Vector3(0.6, 0.32, L), Vector3(side * 190, 0.06, 0), Color(0.85, 0.7, 0.15))
	for zz in [-L * 0.5 + 40.0, 0.0, L * 0.5 - 40.0]:
		M.box(node, Vector3(190, 0.3, 23), Vector3(side * 95, 0.04, zz), tw)
	M.box(node, Vector3(240, 0.3, 700), Vector3(side * 330, 0.04, 0), Color(0.55, 0.56, 0.57))
	M.terminal(node, Vector3(side * 500, 0, 0), PI / 2, minf(560.0, L * 0.2))
	M.tower(node, Vector3(side * 420, 0, L * 0.3))
	M.hangar(node, Vector3(side * 470, 0, -L * 0.33), PI / 2)
	# 停放的飛機
	if quality >= 1:
		for i in 2:
			var pl := M.airliner(i + 1)
			pl.position = Vector3(side * 395, M.GEAR_H, -120.0 + i * 160.0)
			pl.rotation.y = -PI / 2
			node.add_child(pl)
			_hide_far(pl, 7000.0)
	# 燈光
	var lights := []
	for i in range(0, int(L / 60.0) + 1):
		var z := -L * 0.5 + i * 60.0
		for sx in [-1.0, 1.0]:
			lights.append([Vector3(sx * (Wd * 0.5 + 1.0), 0.6, z), Color(1.0, 0.95, 0.8)])
	for k in 8:
		var x := -Wd * 0.5 + 3.0 + k * (Wd - 6.0) / 7.0
		lights.append([Vector3(x, 0.6, L * 0.5 + 2.0), Color(0.2, 1.0, 0.35)])
		lights.append([Vector3(x, 0.6, -L * 0.5 - 2.0), Color(0.2, 1.0, 0.35)])
	# 進場燈（兩端各 900 公尺）
	for e in [1.0, -1.0]:
		for i in range(1, 16):
			var z: float = e * (L * 0.5 + i * 60.0)
			for k in 5:
				lights.append([Vector3((k - 2) * 1.6, 0.8, z), Color(1.0, 0.95, 0.85)])
			if i == 5:
				for k in 12:
					lights.append([Vector3((k - 5.5) * 3.0, 0.8, z), Color(1.0, 0.95, 0.85)])
	_lights_mm(node, lights, 1.6)
	# PAPI（兩端，跑道左側）
	for i in 2:
		var e := 1.0 if i == 0 else -1.0
		var p := Node3D.new()
		p.position = Vector3(-e * (Wd * 0.5 + 18.0), 1.0, e * (L * 0.5 - 330.0))
		node.add_child(p)
		var ls: Array = []
		for k in 4:
			var m := M.light(p, Vector3(-e * k * 9.0, 0, 0), Color.WHITE, 2.0, 0.0028, 2.0)
			m.material_override = (m.material_override as ShaderMaterial).duplicate()
			ls.append(m)
		var rw := G.runway(a, i)
		papis.append({"lights": ls, "thr": rw.thr, "pos": p, "dir": rw.dir})
	# 風向袋
	var sock := Node3D.new()
	sock.position = Vector3(-60, 0, L * 0.5 - 200.0)
	node.add_child(sock)
	M.cyl(sock, 0.15, 0.15, 8.0, Vector3(0, 4, 0), Color(0.9, 0.9, 0.9))
	var cone := M.cyl(sock, 0.9, 0.4, 5.0, Vector3(0, 0, 2.6), Color(1.0, 0.45, 0.1), "z")
	var piv := Node3D.new()
	piv.position.y = 7.6
	sock.add_child(piv)
	cone.reparent(piv, false)
	cone.position = Vector3(0, 0, 2.6)
	cone.rotation = Vector3(-PI / 2, 0, 0)
	socks.append(piv)
	# 機場周圍的樹
	if quality >= 1:
		_trees(c, a, 700 if quality == 1 else 1400)

func _hide_far(n: Node, dist: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).visibility_range_end = dist
	for ch in n.get_children():
		_hide_far(ch, dist)

func _quad_mesh(parent: Node3D, pos: Vector3, w: float, l: float, m: Material, c: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-w * 0.5, 0, l * 0.5), Vector3(w * 0.5, 0, l * 0.5), Vector3(w * 0.5, 0, -l * 0.5), Vector3(-w * 0.5, 0, -l * 0.5)]
	var uvs := [Vector2(0, -w * 0.5), Vector2(0, w * 0.5), Vector2(l, w * 0.5), Vector2(l, -w * 0.5)]
	for idx in [0, 2, 1, 0, 3, 2]:
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[idx])
		st.add_vertex(pts[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.position = pos
	mi.material_override = m if m != null else M.mat(c, 0.0, 0.9)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func _lights_mm(parent: Node3D, lights: Array, size: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = lights.size()
	for i in lights.size():
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * size), lights[i][0]))
		mm.set_instance_color(i, lights[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/shaders/lights.gdshader")
	m.set_shader_parameter("min_px", 0.0016)
	light_mats.append(m)
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)

func _trees(c: Vector3, a: Dictionary, count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(a.id)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 6
	cm.rings = 1
	mm.mesh = cm
	var xf: Array = []
	var u := G.hdg_dir(a.hdg)
	var v := Vector3(-u.z, 0, u.x)
	var tries := 0
	while xf.size() < count and tries < count * 4:
		tries += 1
		var p := c + Vector3(rng.randf_range(-3200, 3200), 0, rng.randf_range(-3200, 3200))
		var rel := p - c
		if absf(rel.dot(u)) < a.len * 0.5 + 900.0 and absf(rel.dot(v)) < 700.0:
			continue
		var h := terrain.height_at(p.x, p.z)
		if h < 2.0 or h > 700.0 or terrain.urban_at(p.x, p.z) > 0.3:
			continue
		var s := rng.randf_range(6.0, 13.0)
		var col := Color(0.16, 0.34, 0.15).lerp(Color(0.3, 0.45, 0.2), rng.randf())
		xf.append([Transform3D(Basis().scaled(Vector3(s * 0.38, s, s * 0.38)), Vector3(p.x, h + s * 0.45, p.z)), col])
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i][0])
		mm.set_instance_color(i, xf[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	mmi.material_override = m
	mmi.visibility_range_end = 6000.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

# ── 城市大樓 ──
func _cities(quality: int) -> void:
	var mult: float = [0.35, 0.7, 1.0][quality]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for city in G.CITIES:
		var cp := G.geo(city[1], city[2])
		var R: float = city[3]
		var count := int(city[4] * mult)
		var xf: Array = []
		var tries := 0
		while xf.size() < count and tries < count * 5:
			tries += 1
			var r := R * sqrt(rng.randf()) * 0.85
			var ang := rng.randf() * TAU
			var p := Vector2(cp.x + cos(ang) * r, cp.y + sin(ang) * r)
			p = Vector2(snappedf(p.x, 35.0), snappedf(p.y, 35.0))
			var h := terrain.height_at(p.x, p.y)
			if h < 1.5 or _near_runway(p, 500.0):
				continue
			var center := 1.0 - r / R
			var bh := rng.randf_range(12.0, 30.0) + pow(rng.randf(), 3.0) * (140.0 if city[0] == "臺北" or city[0] == "高雄" or city[0] == "臺中" else 60.0) * center
			var bw := rng.randf_range(16.0, 28.0)
			var bd := rng.randf_range(16.0, 28.0)
			var col: Color = [Color(0.82, 0.8, 0.76), Color(0.7, 0.72, 0.74), Color(0.62, 0.68, 0.75), Color(0.88, 0.85, 0.8), Color(0.55, 0.58, 0.62)][rng.randi() % 5]
			xf.append([Transform3D(Basis().scaled(Vector3(bw, bh, bd)), Vector3(p.x, h + bh * 0.5 - 1.0, p.y)), col])
		if xf.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var bm := BoxMesh.new()
		mm.mesh = bm
		mm.instance_count = xf.size()
		for i in xf.size():
			mm.set_instance_transform(i, xf[i][0])
			mm.set_instance_color(i, xf[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = bld_mat
		mmi.visibility_range_end = 26000.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	var p101 := G.geo(121.565, 25.034)
	M.taipei101(self, Vector3(p101.x, terrain.height_at(p101.x, p101.y) - 1.0, p101.y))

func _near_runway(p: Vector2, margin: float) -> bool:
	for a in G.AIRPORTS:
		var c := G.geo(a.lon, a.lat)
		var hr := deg_to_rad(a.hdg)
		var u := Vector2(sin(hr), -cos(hr))
		var rel := p - c
		if absf(rel.dot(u)) < a.len * 0.5 + margin + 400.0 and absf(rel.dot(Vector2(-u.y, u.x))) < 620.0 + margin * 0.3:
			return true
	return false

# ── 雲 ──
func _cloud_tex() -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = 5
	n.frequency = 0.035
	n.fractal_octaves = 4
	var S := 128
	var img := Image.create(S, S, true, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var dx := (x - S * 0.5) / (S * 0.5)
			var dy := (y - S * 0.55) / (S * 0.45)
			var r := sqrt(dx * dx + dy * dy)
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((1.0 - r) * 1.6 + (v - 0.5) * 1.2, 0.0, 1.0)
			a *= smoothstep(1.0, 0.7, r)
			img.set_pixel(x, y, Color(v, v, v, a * 0.92))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _clouds(quality: int, weather: String) -> void:
	cloud_mat = ShaderMaterial.new()
	cloud_mat.shader = load("res://scripts/shaders/cloud.gdshader")
	cloud_mat.set_shader_parameter("tex", _cloud_tex())
	var clusters: int = [60, 110, 170][quality]
	var per: int = [6, 8, 10][quality]
	if weather in ["cloudy", "rain", "storm", "snow"]:
		clusters = int(clusters * 1.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = clusters * per
	var i := 0
	for c in clusters:
		var cp := Vector3(rng.randf_range(-42000, 34000), rng.randf_range(cloud_base, cloud_base + 500.0), rng.randf_range(-48000, 48000))
		var cs := rng.randf_range(500.0, 1100.0)
		for k in per:
			var off := Vector3(rng.randf_range(-1, 1) * cs, rng.randf_range(0, 0.6) * cs * 0.6, rng.randf_range(-1, 1) * cs * 0.6)
			var s := rng.randf_range(0.45, 0.9) * cs
			var shade := 0.85 + 0.15 * (off.y / (cs * 0.36 + 1.0))
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), cp + off))
			mm.set_instance_color(i, Color(shade, shade, shade, 1.0))
			i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = cloud_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-60000, 0, -60000), Vector3(120000, 5000, 120000))
	add_child(mmi)
	# 陰天雲層（雨、雷雨、颱風、雪）
	overcast = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(90000, 90000)
	overcast.mesh = pm
	overcast_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float dark = 0.4;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); vec2 u = f*f*(3.0-2.0*f);
	return mix(mix(hash(i), hash(i+vec2(1,0)), u.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), u.x), u.y); }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz * 0.0006 + TIME * 0.004;
	float n = vn(p) * 0.5 + vn(p * 2.3) * 0.3 + vn(p * 5.1) * 0.2;
	float d = length(CAMERA_POSITION_WORLD - wpos);
	ALBEDO = mix(vec3(0.75, 0.77, 0.8), vec3(0.32, 0.34, 0.38), dark) * (0.8 + 0.3 * n);
	ALPHA = clamp(0.55 + n * 0.6, 0.0, 0.97) * smoothstep(40.0, 400.0, abs(CAMERA_POSITION_WORLD.y - wpos.y)) * (1.0 - smoothstep(30000.0, 44000.0, d));
}
"""
	overcast_mat.shader = sh
	overcast.material_override = overcast_mat
	overcast.position.y = cloud_top
	overcast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overcast.visible = false
	add_child(overcast)

# ── 雨雪（跟著攝影機）──
func _precip() -> void:
	precip = Node3D.new()
	add_child(precip)
	for r in [9.0, 22.0, 45.0]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = r * 2.2
		cm.cap_top = false
		cm.cap_bottom = false
		cm.radial_segments = 24
		mi.mesh = cm
		var m := ShaderMaterial.new()
		m.shader = load("res://scripts/shaders/precip.gdshader")
		m.set_shader_parameter("amount", 0.0)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		precip_mats.append(m)
		precip.add_child(mi)
	_bolt = Node3D.new()
	_bolt.visible = false
	add_child(_bolt)

func set_precip(amount: float) -> void:
	for m in precip_mats:
		(m as ShaderMaterial).set_shader_parameter("amount", amount)

func lightning(at: Vector3) -> void:
	_flash = 1.0
	for ch in _bolt.get_children():
		ch.queue_free()
	var p := at
	var bm := M.mat(Color(0.85, 0.9, 1.0), 6.0)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	while p.y > maxf(0.0, terrain.height_at(p.x, p.z)):
		var q := p + Vector3(rng.randf_range(-90, 90), -rng.randf_range(80, 160), rng.randf_range(-90, 90))
		var seg := MeshInstance3D.new()
		var bx := BoxMesh.new()
		var d := q - p
		bx.size = Vector3(4, d.length(), 4)
		seg.mesh = bx
		seg.material_override = bm
		seg.position = (p + q) * 0.5
		var up := d.normalized()
		var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
		seg.basis = Basis(side, up, side.cross(up))
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bolt.add_child(seg)
		p = q
	_bolt.visible = true
	_bolt_t = 0.25

func _ships() -> void:
	var spots := [[120.15, 22.55, 20.0], [120.0, 23.4, 200.0], [119.9, 24.2, 30.0], [121.9, 24.4, 190.0], [121.45, 25.35, 260.0], [120.6, 22.0, 110.0]]
	for s in spots:
		var p := G.geo(s[0], s[1])
		var sh := Node3D.new()
		sh.position = Vector3(p.x, 0, p.y)
		sh.rotation.y = -deg_to_rad(s[2])
		add_child(sh)
		M.box(sh, Vector3(28, 9, 190), Vector3(0, 3, 0), Color(0.25, 0.28, 0.35))
		M.box(sh, Vector3(26, 2, 150), Vector3(0, 8, -10), Color(0.7, 0.35, 0.25))
		for k in 5:
			M.box(sh, Vector3(24, 6, 20), Vector3(0, 12, -60 + k * 24), [Color(0.8, 0.3, 0.2), Color(0.2, 0.45, 0.7), Color(0.9, 0.75, 0.25), Color(0.3, 0.6, 0.35)][k % 4])
		M.box(sh, Vector3(22, 16, 14), Vector3(0, 16, 80), Color(0.92, 0.92, 0.92))
		_hide_far(sh, 9000.0)
		ships.append(sh)

# ── 每格更新 ──
func update(cam_pos: Vector3, eye: Vector3, delta: float, wind_heading: float) -> void:
	ocean.position = Vector3(snappedf(cam_pos.x, 500.0), 0.0, snappedf(cam_pos.z, 500.0))
	precip.position = cam_pos
	overcast.position = Vector3(snappedf(cam_pos.x, 1000.0), cloud_top, snappedf(cam_pos.z, 1000.0))
	# 雲層裡面：霧變濃
	var in_cloud := 0.0
	if overcast_on:
		in_cloud = 1.0 - smoothstep(0.0, 260.0, absf(cam_pos.y - cloud_top) - 60.0)
	env.fog_density = lerpf(base_fog, 0.006, in_cloud)
	# 閃電
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.0)
		env.background_energy_multiplier = 1.0 + _flash * 3.0
		env.ambient_light_energy = (0.35 if night >= 1.0 else 0.8) + _flash * 3.0
	if _bolt_t > 0.0:
		_bolt_t -= delta
		if _bolt_t <= 0.0:
			_bolt.visible = false
	for sh in ships:
		(sh as Node3D).translate_object_local(Vector3(0, 0, -3.0 * delta))
	# PAPI：從眼睛位置看過去的角度
	for p in papis:
		var lp: Vector3 = (p.pos as Node3D).global_position
		var d: Vector3 = eye - lp
		var horiz := Vector2(d.x, d.z).length()
		var ang := rad_to_deg(atan2(d.y, horiz))
		var ahead := (lp - eye).dot(p.dir) > 0.0
		var th := [3.5, 3.17, 2.83, 2.5]
		for k in 4:
			var white: bool = ang > th[k]
			var m: ShaderMaterial = (p.lights[k] as MeshInstance3D).material_override
			m.set_shader_parameter("tint", Color(1, 1, 1) if white else Color(1, 0.08, 0.05))
			(p.lights[k] as MeshInstance3D).visible = ahead and horiz < 12000.0
	for s in socks:
		(s as Node3D).global_rotation.y = -deg_to_rad(wind_heading) + PI
