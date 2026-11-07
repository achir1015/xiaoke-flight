class_name Portrait
extends Control
## 角色頭像（程式繪製）：小柯機器人、副機長、空服員、塔台、乘客……說話時嘴巴會動。

var who := "xiaoke"
var talking := false
var _t := 0.0
var blink := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var k := s / 100.0
	var mouth := (0.5 + 0.5 * sin(_t * 18.0)) if talking else 0.0
	var eye_open := 0.15 if fmod(_t, 3.7) < 0.12 else 1.0
	draw_circle(c, s * 0.5, Color(0.13, 0.18, 0.28))
	match who:
		"xiaoke":
			_robot(c, k, mouth, eye_open)
		"tower", "police", "medlink", "radio_cap":
			_radio(c, k, who)
		"gpws":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -32) * k, c + Vector2(34, 28) * k, c + Vector2(-34, 28) * k]), Color(1, 0.75, 0.15))
			draw_string(M.font_bold, c + Vector2(-8, 22) * k, "!", HORIZONTAL_ALIGNMENT_CENTER, 16 * k, int(40 * k), Color(0.1, 0.1, 0.1))
		_:
			_person(c, k, mouth, eye_open)

func _robot(c: Vector2, k: float, mouth: float, eo: float) -> void:
	draw_line(c + Vector2(0, -30) * k, c + Vector2(0, -42) * k, Color(0.85, 0.88, 0.92), 3 * k)
	draw_circle(c + Vector2(0, -44) * k, 5 * k, Color(1, 0.4, 0.3) if fmod(_t, 1.0) < 0.5 else Color(1, 0.65, 0.5))
	_rrect(Rect2(c + Vector2(-36, -32) * k, Vector2(72, 60) * k), 22 * k, Color(0.96, 0.97, 0.99))
	_rrect(Rect2(c + Vector2(-27, -21) * k, Vector2(54, 36) * k), 13 * k, Color(0.08, 0.12, 0.22))
	var ec := Color(0.38, 0.94, 1.0)
	for ex in [-11.0, 11.0]:
		draw_rect(Rect2(c + Vector2(ex - 5, -9 - 5 * eo) * k, Vector2(10, 10 * eo) * k), ec)
	var mw := 14.0
	draw_rect(Rect2(c + Vector2(-mw * 0.5, 6) * k, Vector2(mw, 2 + mouth * 6) * k), ec)
	_rrect(Rect2(c + Vector2(-26, 30) * k, Vector2(52, 22) * k), 8 * k, Color(0.29, 0.55, 0.94))

func _radio(c: Vector2, k: float, kind: String) -> void:
	var col := Color(0.25, 0.55, 0.9)
	if kind == "police":
		col = Color(0.2, 0.25, 0.35)
	elif kind == "medlink":
		col = Color(0.9, 0.95, 1.0)
	draw_circle(c, 34 * k, col)
	if kind == "medlink":
		draw_rect(Rect2(c + Vector2(-7, -22) * k, Vector2(14, 44) * k), Color(0.9, 0.15, 0.15))
		draw_rect(Rect2(c + Vector2(-22, -7) * k, Vector2(44, 14) * k), Color(0.9, 0.15, 0.15))
		return
	if kind == "tower":
		draw_rect(Rect2(c + Vector2(-5, -6) * k, Vector2(10, 32) * k), Color(0.92, 0.94, 0.96))
		draw_colored_polygon(PackedVector2Array([c + Vector2(-16, -10) * k, c + Vector2(16, -10) * k, c + Vector2(12, -22) * k, c + Vector2(-12, -22) * k]), Color(0.1, 0.2, 0.3))
		draw_rect(Rect2(c + Vector2(-14, -10) * k, Vector2(28, 4) * k), Color(0.92, 0.94, 0.96))
		draw_arc(c + Vector2(0, -16) * k, 24 * k, -2.4, -0.7, 10, Color(1, 1, 1, 0.8), 2 * k)
		draw_arc(c + Vector2(0, -16) * k, 31 * k, -2.4, -0.7, 10, Color(1, 1, 1, 0.5), 2 * k)
	elif kind == "police":
		draw_string(M.font_bold, c + Vector2(-30, 8) * k, "特勤", HORIZONTAL_ALIGNMENT_CENTER, 60 * k, int(22 * k), Color(1, 0.85, 0.3))
	else:
		_person(c, k, 0.0, 1.0, "captain")

func _person(c: Vector2, k: float, mouth: float, eo: float, force := "") -> void:
	var kind := force if force != "" else who
	var skin := Color(0.97, 0.83, 0.7)
	var hair := Color(0.1, 0.08, 0.08)
	var cloth := Color(0.3, 0.45, 0.7)
	match kind:
		"copilot", "captain": cloth = Color(0.95, 0.96, 0.98)
		"fa": cloth = Color(0.13, 0.2, 0.42)
		"elder": hair = Color(0.82, 0.82, 0.84); cloth = Color(0.55, 0.45, 0.35)
		"pregnant": cloth = Color(0.95, 0.65, 0.72)
		"wife": cloth = Color(0.7, 0.35, 0.45); hair = Color(0.3, 0.18, 0.1)
		"doctor": cloth = Color(0.95, 0.96, 0.98)
		"hijacker": cloth = Color(0.15, 0.15, 0.17); skin = Color(0.88, 0.72, 0.58)
	# 身體
	draw_colored_polygon(PackedVector2Array([c + Vector2(-34, 50) * k, c + Vector2(-28, 22) * k, c + Vector2(28, 22) * k, c + Vector2(34, 50) * k]), cloth)
	if kind == "fa":
		draw_colored_polygon(PackedVector2Array([c + Vector2(-10, 22) * k, c + Vector2(10, 22) * k, c + Vector2(0, 34) * k]), Color(0.95, 0.53, 0.2))
	if kind == "copilot" or kind == "captain":
		draw_colored_polygon(PackedVector2Array([c + Vector2(-4, 22) * k, c + Vector2(4, 22) * k, c + Vector2(3, 40) * k, c + Vector2(-3, 40) * k]), Color(0.12, 0.15, 0.3))
		for sx in [-1.0, 1.0]:
			draw_rect(Rect2(c + Vector2(sx * 22 - 6, 26) * k, Vector2(12, 4) * k), Color(0.95, 0.78, 0.25))
	if kind == "doctor":
		draw_arc(c + Vector2(0, 30) * k, 12 * k, 0.2, PI - 0.2, 12, Color(0.2, 0.2, 0.25), 2.5 * k)
	if kind == "hijacker":
		draw_circle(c + Vector2(0, -4) * k, 30 * k, Color(0.15, 0.15, 0.17))
	# 頭
	draw_circle(c + Vector2(0, -4) * k, 24 * k, skin)
	# 頭髮
	if kind in ["fa", "pregnant", "wife"]:
		draw_arc(c + Vector2(0, -6) * k, 25 * k, PI, TAU, 20, hair, 10 * k)
		if kind == "fa":
			draw_circle(c + Vector2(0, -32) * k, 9 * k, hair)
		else:
			draw_rect(Rect2(c + Vector2(-29, -8) * k, Vector2(8, 30) * k), hair)
			draw_rect(Rect2(c + Vector2(21, -8) * k, Vector2(8, 30) * k), hair)
	elif kind != "hijacker":
		draw_arc(c + Vector2(0, -8) * k, 23 * k, PI + 0.2, TAU - 0.2, 20, hair, 9 * k)
	# 帽子
	if kind == "copilot" or kind == "captain":
		draw_colored_polygon(PackedVector2Array([c + Vector2(-28, -18) * k, c + Vector2(28, -18) * k, c + Vector2(22, -36) * k, c + Vector2(-22, -36) * k]), Color(0.1, 0.13, 0.25))
		draw_rect(Rect2(c + Vector2(-30, -20) * k, Vector2(60, 6) * k), Color(0.06, 0.08, 0.15))
		draw_circle(c + Vector2(0, -28) * k, 4 * k, Color(0.95, 0.78, 0.25))
	if kind == "hijacker":
		draw_rect(Rect2(c + Vector2(-26, -26) * k, Vector2(52, 10) * k), Color(0.08, 0.08, 0.1))
	# 眼睛、嘴巴
	for ex in [-8.0, 8.0]:
		draw_rect(Rect2(c + Vector2(ex - 2.5, -6 - 2.5 * eo) * k, Vector2(5, 5 * eo) * k), Color(0.1, 0.08, 0.08))
	if kind == "elder":
		for ex in [-8.0, 8.0]:
			draw_arc(c + Vector2(ex, -5) * k, 6 * k, 0, TAU, 12, Color(0.3, 0.3, 0.3), 1.5 * k)
	var mc := Color(0.6, 0.25, 0.25)
	if kind in ["pregnant", "elder"] and not talking:
		draw_arc(c + Vector2(0, 12) * k, 5 * k, PI + 0.3, TAU - 0.3, 8, mc, 2 * k)
	else:
		draw_rect(Rect2(c + Vector2(-5, 7) * k, Vector2(10, 2 + mouth * 5) * k), mc)

func _rrect(r: Rect2, rad: float, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(rad))
	draw_style_box(sb, r)
