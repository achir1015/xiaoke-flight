class_name FlightCam
extends Camera3D
## 攝影機：外部追蹤（可拖曳環視、滾輪縮放）、駕駛艙、機翼、電影視角（定點掠過）、標題畫面環繞。

const MODES := ["chase", "cockpit", "wing", "flyby"]
const MODE_NAMES := {"chase": "外部追蹤", "cockpit": "駕駛艙", "wing": "機翼視角", "flyby": "定點掠過"}

var target: Aircraft
var mode := "chase"
var yaw_off := 0.0
var pitch_off := 0.14
var dist := 95.0
var shake := 0.0
var title_mode := false
var _flyby_pos := Vector3.ZERO
var _smooth := Transform3D()
var _drag := false
var _t := 0.0
var cockpit_frame: Node3D

func _ready() -> void:
	near = 0.5
	far = 60000.0
	fov = 62.0
	current = true

func next_mode() -> String:
	var i := MODES.find(mode)
	set_mode(MODES[(i + 1) % MODES.size()])
	return MODE_NAMES[mode]

func set_mode(m: String) -> void:
	mode = m
	if mode == "flyby" and target:
		var fwd := Vector3(target.v.x, 0, target.v.z)
		if fwd.length() < 5.0:
			fwd = -target.global_basis.z
		fwd = fwd.normalized()
		_flyby_pos = target.global_position + fwd * 900.0 + Vector3(-fwd.z, 0, fwd.x) * 120.0
		var gh := target.world.terrain.height_at(_flyby_pos.x, _flyby_pos.z)
		_flyby_pos.y = maxf(target.global_position.y - 20.0, maxf(gh, 0.0) + 12.0)
	if cockpit_frame:
		cockpit_frame.visible = mode == "cockpit"
	fov = 70.0 if mode == "cockpit" else 62.0

func reset_view() -> void:
	yaw_off = 0.0
	pitch_off = 0.14
	dist = 95.0

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			dist = clampf(dist * 0.9, 40.0, 600.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			dist = clampf(dist * 1.1, 40.0, 600.0)
	elif e is InputEventMouseMotion and _drag:
		var mm := e as InputEventMouseMotion
		orbit(mm.relative)
	elif e is InputEventMagnifyGesture:
		dist = clampf(dist / (e as InputEventMagnifyGesture).factor, 40.0, 600.0)

func orbit(rel: Vector2) -> void:
	yaw_off -= rel.x * 0.006
	pitch_off = clampf(pitch_off + rel.y * 0.004, -0.4, 1.3)

func zoom(f: float) -> void:
	dist = clampf(dist * f, 40.0, 600.0)

func _process(delta: float) -> void:
	if target == null:
		return
	_t += delta
	var tp := target.global_position
	var tb := target.global_basis
	var xf := Transform3D()
	match mode if not title_mode else "title":
		"title":
			var a := _t * 0.07 + 2.2
			var off := Vector3(sin(a), 0.0, cos(a)) * 120.0 + Vector3(0, 22, 0)
			xf = Transform3D(Basis(), tp + tb * Vector3(0, 0, 0) + off).looking_at(tp + Vector3(0, 2, 0), Vector3.UP)
		"cockpit":
			var eye := tp + tb * Vector3(-0.55, 1.15, -25.3)
			xf = Transform3D(tb, eye)
			xf.basis = xf.basis * Basis(Vector3.UP, yaw_off * 0.6) * Basis(Vector3.RIGHT, -0.08 - (pitch_off - 0.14) * 0.6)
		"wing":
			var eye := tp + tb * Vector3(4.5, 1.6, 8.0)
			xf = Transform3D(Basis(), eye).looking_at(tp + tb * Vector3(26, -1.5, -2.0), tb.y)
		"flyby":
			xf = Transform3D(Basis(), _flyby_pos).looking_at(tp, Vector3.UP)
			if _flyby_pos.distance_to(tp) > 2500.0:
				set_mode("flyby")
		_:
			# 追蹤：跟著航向（不跟著坡度），可環視
			var fwd := -tb.z
			var hy := atan2(-fwd.x, -fwd.z)
			var b := Basis(Vector3.UP, hy + yaw_off) * Basis(Vector3.RIGHT, -pitch_off)
			var eye := tp + b * Vector3(0, 6.0, dist)
			var gh := target.world.terrain.height_at(eye.x, eye.z)
			eye.y = maxf(eye.y, maxf(gh, 0.0) + 3.0)
			xf = Transform3D(Basis(), eye).looking_at(tp + Vector3(0, 4.0, 0) + fwd * 8.0, Vector3.UP)
			# 輕微跟著坡度傾斜，增加速度感
			xf.basis = xf.basis * Basis(Vector3.FORWARD, -target.bank * 0.25)
	if mode == "chase" and not title_mode and _smooth != Transform3D():
		var k := 1.0 - exp(-delta * 8.0)
		_smooth.origin = _smooth.origin.lerp(xf.origin, k)
		_smooth.basis = _smooth.basis.slerp(xf.basis.orthonormalized(), k)
	else:
		_smooth = xf
	var out := _smooth
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 1.5)
		var s := shake * (0.6 if mode == "cockpit" else 1.0)
		out.origin += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * s * 0.6
		out.basis = out.basis * Basis(Vector3.FORWARD, randf_range(-1, 1) * s * 0.012)
	global_transform = out
	if mode != "cockpit" and _smooth.origin.distance_to(tp) < 30.0:
		_smooth = xf

# 駕駛艙框（遮光罩與窗框，只在駕駛艙視角顯示）
func build_cockpit(parent: Node3D) -> void:
	cockpit_frame = Node3D.new()
	cockpit_frame.visible = false
	parent.add_child(cockpit_frame)
	var dark := Color(0.1, 0.11, 0.13)
	# 遮光罩（畫面下緣）與細窗框
	M.box(cockpit_frame, Vector3(3.0, 0.35, 0.9), Vector3(0, 0.55, -26.2), dark)
	M.box(cockpit_frame, Vector3(3.2, 0.9, 0.2), Vector3(0, 0.05, -25.95), Color(0.16, 0.17, 0.2))
	M.box(cockpit_frame, Vector3(3.0, 0.08, 0.3), Vector3(0, 2.05, -26.0), dark)
	# 小儀表螢幕的光
	for x in [-1.1, -0.4, 0.4, 1.1]:
		var s := M.box(cockpit_frame, Vector3(0.5, 0.36, 0.02), Vector3(x, 0.45, -25.85), Color(0.1, 0.25, 0.4))
		s.material_override = M.mat(Color(0.12, 0.3, 0.5), 1.3)
	for ch in cockpit_frame.get_children():
		(ch as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
