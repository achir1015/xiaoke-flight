class_name CabinView
extends SubViewportContainer
## 客艙即時小畫面：獨立 3D 場景（座椅、乘客、空服員、事件人物），走道視角或俯視角。

signal clicked()

const ROWS := 20
var vp: SubViewport
var cam: Camera3D
var root: Node3D
var ceiling: Array = []
var fa: Node3D                 # 走動的空服員
var fa2: Node3D
var actors: Dictionary = {}    # 事件人物
var view := "aisle"
var focus_row := 10
var shake := 0.0
var state := ""                # 事件狀態：labor／labor_born／bp／heart／heart_arrest／heart_ok／hijack／hijack_calm／police
var _t := 0.0
var _fa_z := 0.0
var _fa_dir := -1.0
var _front_z := 0.0

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(480, 270)
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(vp)
	root = Node3D.new()
	vp.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.22, 0.26)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.87, 0.92)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var dl := DirectionalLight3D.new()
	dl.rotation_degrees = Vector3(-60, 20, 0)
	dl.light_energy = 0.5
	root.add_child(dl)
	var cab := M.cabin(ROWS)
	root.add_child(cab)
	for ch in cab.get_children():
		if ch is MeshInstance3D and ((ch as Node3D).position.y > 1.5):
			ceiling.append(ch)
	_front_z = 1.0 - ROWS * 0.82 - 0.9
	# 乘客
	var rng := RandomNumberGenerator.new()
	rng.seed = 888
	var seed_i := 0
	for r in range(1, ROWS + 1):
		for col in 6:
			if _special_seat(r, col):
				continue
			if rng.randf() < 0.82:
				seed_i += 1
				var p := M.person("pax", true, seed_i)
				p.position = seat(r, col)
				root.add_child(p)
	# 事件人物（平常坐在座位上）
	_actor("pregnant", "pregnant", 12, 1)
	_actor("elder", "elder", 8, 4)
	_actor("heart", "heart", 15, 2)
	_actor("wife", "pax", 15, 1)
	_actor("hijacker", "hijacker", 18, 3)
	_actor("doctor", "doctor", 5, 2)
	# 空服員
	fa = M.person("attendant", false, 1)
	root.add_child(fa)
	fa2 = M.person("attendant", false, 2)
	fa2.visible = false
	root.add_child(fa2)
	_fa_z = _front_z + 3.0
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.05
	root.add_child(cam)
	cam.current = true
	set_view("aisle")

func _special_seat(r: int, col: int) -> bool:
	return [r, col] in [[12, 1], [8, 4], [15, 2], [15, 1], [18, 3], [5, 2]]

# 第 row 排（從機頭往後數 1..ROWS）、第 col 個座位（0..5，2/3 靠走道）
func seat(row: int, col: int) -> Vector3:
	return M.seat_pos(ROWS - row, col)

func _actor(id: String, kind: String, row: int, col: int) -> void:
	var p := M.person(kind, true, 900 + actors.size())
	p.position = seat(row, col)
	root.add_child(p)
	actors[id] = p

func set_view(v: String) -> void:
	view = v
	for c in ceiling:
		(c as Node3D).visible = view != "top"

func toggle_view() -> String:
	set_view("top" if view == "aisle" else "aisle")
	return "俯視角" if view == "top" else "走道視角"

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
		accept_event()

# ── 事件狀態 ──
var props: Array = []
var masks: Array = []
var _mask_drop := 0.0

func _clear_props() -> void:
	for p in props:
		if is_instance_valid(p):
			(p as Node).queue_free()
	props.clear()
	for a in ["ArmL", "ArmR"]:
		var arm := fa.get_node("Body/" + a) as Node3D
		arm.rotation = Vector3.ZERO

func _demo(s: String) -> void:
	_clear_props()
	var body := fa.get_node("Body") as Node3D
	var al := body.get_node("ArmL") as Node3D
	var ar := body.get_node("ArmR") as Node3D
	match s:
		"demo_belt":
			al.rotation.x = -1.1
			ar.rotation.x = -1.1
			props.append(M.box(body, Vector3(0.62, 0.05, 0.02), Vector3(0, 0.12, -0.42), Color(0.25, 0.27, 0.32)))
			props.append(M.box(body, Vector3(0.1, 0.07, 0.03), Vector3(0, 0.12, -0.44), Color(0.8, 0.82, 0.85)))
		"demo_oxy":
			ar.rotation.x = -2.3
			var head := body.get_node("Head") as Node3D
			props.append(M.box(head, Vector3(0.12, 0.1, 0.07), Vector3(0, -0.04, -0.15), Color(1.0, 0.85, 0.2)))
			props.append(M.box(head, Vector3(0.015, 0.4, 0.015), Vector3(0, 0.18, -0.17), Color(0.9, 0.9, 0.92)))
			if masks.is_empty():
				for r in range(1, ROWS + 1):
					for sx in [-1.0, 1.0]:
						var mk := M.box(root, Vector3(0.08, 0.07, 0.05), Vector3(sx * 0.95, 2.0, seat(r, 1).z - 0.15), Color(1.0, 0.85, 0.2))
						masks.append(mk)
			_mask_drop = 0.0
		"demo_vest":
			props.append(M.box(body, Vector3(0.46, 0.5, 0.3), Vector3(0, 0.35, 0), Color(1.0, 0.5, 0.1)))
			al.rotation.x = -0.6
			ar.rotation.x = -0.6
		"demo_exit":
			al.rotation.z = -1.4
			ar.rotation.z = 1.4
		"demo_end", "demo":
			for mk in masks:
				(mk as Node).queue_free()
			masks.clear()

func set_state(s: String) -> void:
	if s.begins_with("demo"):
		state = s if s != "demo_end" else ""
		_demo(s)
		set_view("demo" if s != "demo_end" else "aisle")
		return
	_clear_props()
	state = s
	if s in ["labor", "bp", "heart", "hijack"]:
		set_view("top")
	var preg: Node3D = actors.pregnant
	var heart: Node3D = actors.heart
	var hij: Node3D = actors.hijacker
	var doc: Node3D = actors.doctor
	match s:
		"labor":
			focus_row = 12
			preg.rotation.x = 0.0
			(preg.get_node("Body") as Node3D).rotation.x = 0.45
		"labor_born":
			focus_row = 12
			if not actors.has("baby"):
				var b := M.sphere(root, 0.09, preg.position + Vector3(0.0, 0.85, -0.25), Color(0.98, 0.85, 0.8))
				actors["baby"] = b
				M.box(root, Vector3(0.3, 0.12, 0.2), preg.position + Vector3(0.0, 0.78, -0.25), Color(0.95, 0.95, 1.0))
		"bp":
			focus_row = 8
			var e: Node3D = actors.elder
			if not actors.has("mask"):
				actors["mask"] = M.box(e.get_node("Body/Head") as Node3D, Vector3(0.12, 0.1, 0.06), Vector3(0, -0.04, -0.15), Color(1.0, 0.85, 0.2))
				(actors["mask"] as Node3D).visible = false
			(e.get_node("Body") as Node3D).rotation.x = 0.35
		"bp_oxygen":
			if actors.has("mask"):
				(actors["mask"] as Node3D).visible = true
		"heart", "heart_arrest":
			focus_row = 15
			# 倒在走道上
			heart.position = seat(15, 2) + Vector3(0.42, 0.12, 0.2)
			heart.rotation = Vector3(-PI / 2, 0, 0)
			(heart.get_node("Body") as Node3D).position.y = 0.2
			(actors.wife as Node3D).rotation.y = -0.6
		"heart_ok":
			focus_row = 15
		"hijack":
			focus_row = 18
			hij.position = Vector3(0.0, 0.0, seat(17, 2).z)
			hij.rotation = Vector3.ZERO
			var body: Node3D = hij.get_node("Body")
			body.position.y = 0.95
			for leg in ["LegL", "LegR"]:
				pass
			var arm: Node3D = body.get_node("ArmR")
			arm.rotation.x = -1.3
			if not actors.has("knife"):
				actors["knife"] = M.box(arm, Vector3(0.03, 0.03, 0.22), Vector3(0, -0.5, -0.1), Color(0.75, 0.77, 0.8))
			_rebuild_standing(hij, "hijacker")
		"hijack_calm":
			if actors.has("knife"):
				(actors["knife"] as Node3D).visible = false
			var arm2: Node3D = (actors.hijacker as Node3D).get_node("Body/ArmR")
			arm2.rotation.x = -PI + 0.3
			((actors.hijacker as Node3D).get_node("Body/ArmL") as Node3D).rotation.x = -PI + 0.3
		"police":
			for i in 3:
				var po := M.person("police", false, 50 + i)
				po.position = Vector3(0.0, 0.0, seat(17, 2).z + 1.0 + i * 0.8)
				po.rotation.y = 0.0
				root.add_child(po)
	if s == "doctor":
		doc.position = Vector3(0.0, 0.0, seat(focus_row, 2).z - 0.6)
		_rebuild_standing(doc, "doctor")

func _rebuild_standing(old: Node3D, kind: String) -> void:
	# 換成站姿模型（保留位置）
	var pos := old.position
	var rot := old.rotation
	var n := M.person(kind, false, 900 + actors.size())
	n.position = pos
	n.rotation = rot
	root.add_child(n)
	for k in actors:
		if actors[k] == old:
			actors[k] = n
	if kind == "hijacker":
		var arm: Node3D = n.get_node("Body/ArmR")
		arm.rotation.x = -1.3
		actors["knife"] = M.box(arm, Vector3(0.03, 0.03, 0.22), Vector3(0, -0.5, -0.1), Color(0.75, 0.77, 0.8))
	old.queue_free()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	# 空服員：平常沿走道走動；有事件時到病人旁邊
	var target_z := _fa_z
	if state in ["labor", "labor_born", "bp", "bp_oxygen", "heart", "heart_arrest", "heart_ok"]:
		target_z = seat(focus_row, 2).z + 0.7
		_fa_z = move_toward(_fa_z, target_z, delta * 1.2)
		fa2.visible = true
		fa2.position = Vector3(0.05, 0, seat(focus_row, 2).z - 0.8)
		fa2.rotation.y = PI
		if state.begins_with("heart"):
			# CPR 動作
			var bd: Node3D = fa.get_node("Body")
			bd.rotation.x = 0.7
			for a in ["ArmL", "ArmR"]:
				(bd.get_node(a) as Node3D).rotation.x = -1.2 + sin(_t * 12.0) * 0.15
	elif state.begins_with("demo"):
		_fa_z = _front_z + 2.0
		fa.rotation.y = PI
		fa2.visible = false
		if not masks.is_empty():
			_mask_drop = minf(1.0, _mask_drop + delta * 1.5)
			for mk in masks:
				(mk as Node3D).position.y = lerpf(2.0, 1.45, _mask_drop) + sin(_t * 3.0 + (mk as Node3D).position.z) * 0.02
	elif state.begins_with("hijack"):
		_fa_z = move_toward(_fa_z, seat(16, 2).z, delta * 1.0)
		fa.rotation.y = PI
		var bd: Node3D = fa.get_node("Body")
		for a in ["ArmL", "ArmR"]:
			(bd.get_node(a) as Node3D).rotation.x = -PI + 0.3
	else:
		_fa_z += _fa_dir * delta * 0.7
		if _fa_z < _front_z + 1.5:
			_fa_dir = 1.0
		if _fa_z > 0.3:
			_fa_dir = -1.0
		fa.rotation.y = 0.0 if _fa_dir < 0 else PI
	fa.position = Vector3(0.0, 0.0, _fa_z)
	# 鏡頭
	var tz := seat(focus_row, 2).z
	var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.03
	if view == "demo":
		cam.position = Vector3(0.0, 2.05, _front_z + 5.2) + sh
		cam.look_at(Vector3(0.0, 1.25, _front_z + 2.0), Vector3.UP)
		cam.fov = 60.0
	elif view == "aisle":
		cam.position = Vector3(0.0, 1.78, _front_z + 0.7) + sh
		cam.look_at(Vector3(0.0, 0.9, _front_z + 9.0), Vector3.UP)
		cam.fov = 68.0
	else:
		cam.position = Vector3(0.0, 6.5, tz + 2.6) + sh
		cam.look_at(Vector3(0.0, 0.4, tz - 0.3), Vector3.UP)
		cam.fov = 55.0
	# 乘客小動作
	if state == "labor":
		var b: Node3D = (actors.pregnant as Node3D).get_node("Body")
		b.rotation.x = 0.45 + sin(_t * 2.0) * 0.06
	if state == "hijack":
		(actors.hijacker as Node3D).rotation.y = sin(_t * 1.3) * 0.5
