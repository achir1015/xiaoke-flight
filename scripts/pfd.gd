class_name PFD
extends Control
## 主飛行儀表：姿態儀、空速帶、高度帶、升降率、航向羅盤、盲降菱形、自動駕駛模式與警告。

var plane: Aircraft
var target_hdg := -1.0
var ils := Vector2(99, 99)     # 航向道／下滑道偏差（度），99＝不顯示
var font: Font
var _blink := 0.0

const SKY := Color(0.18, 0.45, 0.82)
const GND := Color(0.55, 0.36, 0.2)
const BG := Color(0.04, 0.06, 0.1, 0.82)
const W := Color(0.95, 0.96, 0.98)
const MAG := Color(0.95, 0.4, 0.95)
const GRN := Color(0.35, 0.95, 0.45)
const AMB := Color(1.0, 0.75, 0.2)
const RED := Color(1.0, 0.3, 0.25)

func _ready() -> void:
	font = M.font_bold
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_blink += delta
	queue_redraw()

func _txt(p: Vector2, s: String, size: int, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, p, s, align, w, size, c)

func _draw() -> void:
	if plane == null:
		return
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), BG)
	var sc := sz.y / 220.0
	# 版面：空速帶 | 姿態儀 | 高度帶 | 升降率
	var tape_w := 62.0 * sc
	var vsi_w := 26.0 * sc
	var ai_w := sz.x - tape_w * 2 - vsi_w - 16.0 * sc
	var top := 6.0 * sc
	var ai_h := sz.y - 52.0 * sc
	var ai := Rect2(tape_w + 6.0 * sc, top, ai_w, ai_h)
	_attitude(ai, sc)
	_speed(Rect2(2.0 * sc, top, tape_w, ai_h), sc)
	_alt(Rect2(ai.end.x + 6.0 * sc, top, tape_w, ai_h), sc)
	_vsi(Rect2(sz.x - vsi_w - 2.0 * sc, top, vsi_w, ai_h), sc)
	_heading(Rect2(tape_w, sz.y - 42.0 * sc, sz.x - tape_w * 2, 40.0 * sc), sc)

func _attitude(r: Rect2, sc: float) -> void:
	var c := r.get_center()
	var ppd := r.size.y / 50.0     # 每度幾像素
	var pitch := rad_to_deg(plane.pitch)
	var bank := plane.bank
	var rad := r.size.length()
	# 用多邊形畫天地（以坡度旋轉）
	var rot := Transform2D(-bank, c)
	var hz := pitch * ppd
	var sky := PackedVector2Array([Vector2(-rad, -rad * 2 + hz), Vector2(rad, -rad * 2 + hz), Vector2(rad, hz), Vector2(-rad, hz)])
	var gnd := PackedVector2Array([Vector2(-rad, hz), Vector2(rad, hz), Vector2(rad, rad * 2 + hz), Vector2(-rad, rad * 2 + hz)])
	draw_set_transform_matrix(Transform2D())
	var clip := Rect2(r.position, r.size)
	_poly_clip(rot, sky, SKY, clip)
	_poly_clip(rot, gnd, GND, clip)
	# 俯仰刻度
	for d in range(-30, 35, 5):
		if d == 0:
			continue
		var y := hz - d * ppd
		var half := (22.0 if d % 10 == 0 else 11.0) * sc
		var a := rot * Vector2(-half, y)
		var b := rot * Vector2(half, y)
		if clip.has_point(a) and clip.has_point(b):
			draw_line(a, b, W, 1.5 * sc)
			if d % 10 == 0:
				_txt(rot * Vector2(half + 3 * sc, y + 4 * sc), str(absi(d)), int(9 * sc), W)
	var hl := [rot * Vector2(-rad, hz), rot * Vector2(rad, hz)]
	_line_clip(hl[0], hl[1], W, 2.0 * sc, clip)
	# 坡度刻度弧
	var ar := r.size.y * 0.42
	for d in [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]:
		var a := deg_to_rad(d) - PI / 2
		var p1 := c + Vector2(cos(a), sin(a)) * ar
		var p2 := c + Vector2(cos(a), sin(a)) * (ar + (8.0 if d % 30 == 0 else 5.0) * sc)
		draw_line(p1, p2, W, 1.5 * sc)
	var ba := -bank - PI / 2
	var tip := c + Vector2(cos(ba), sin(ba)) * ar
	var nrm := Vector2(cos(ba), sin(ba))
	var tg := Vector2(-nrm.y, nrm.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - nrm * 9 * sc + tg * 5 * sc, tip - nrm * 9 * sc - tg * 5 * sc]), W)
	# 飛機符號
	var y0 := c.y
	draw_rect(Rect2(c.x - 48 * sc, y0 - 2.5 * sc, 30 * sc, 5 * sc), Color(1, 0.85, 0.1))
	draw_rect(Rect2(c.x + 18 * sc, y0 - 2.5 * sc, 30 * sc, 5 * sc), Color(1, 0.85, 0.1))
	draw_rect(Rect2(c.x - 3 * sc, y0 - 3 * sc, 6 * sc, 6 * sc), Color(1, 0.85, 0.1))
	# 飛行路徑標記（綠色圓）
	var fpa := rad_to_deg(plane.gamma)
	var drift := G.angdiff(rad_to_deg(atan2(plane.v.x, -plane.v.z)), plane.heading) if Vector2(plane.v.x, plane.v.z).length() > 20.0 else 0.0
	var fpm := c + Vector2(clampf(drift, -10, 10) * ppd, -(fpa - pitch) * ppd)
	if clip.has_point(fpm) and not plane.on_ground:
		draw_arc(fpm, 6 * sc, 0, TAU, 16, GRN, 2.0 * sc)
		draw_line(fpm + Vector2(6 * sc, 0), fpm + Vector2(14 * sc, 0), GRN, 2.0 * sc)
		draw_line(fpm - Vector2(6 * sc, 0), fpm - Vector2(14 * sc, 0), GRN, 2.0 * sc)
		draw_line(fpm - Vector2(0, 6 * sc), fpm - Vector2(0, 11 * sc), GRN, 2.0 * sc)
	# 盲降菱形
	if ils.x < 90.0:
		var lx := c.x + clampf(ils.x / 2.5, -1.0, 1.0) * r.size.x * 0.4
		var gy := c.y + clampf(ils.y / 0.7, -1.0, 1.0) * r.size.y * 0.4
		_diamond(Vector2(lx, r.end.y - 8 * sc), 6 * sc)
		_diamond(Vector2(r.end.x - 8 * sc, gy), 6 * sc)
		for k in [-2, -1, 1, 2]:
			draw_circle(Vector2(c.x + k * r.size.x * 0.2, r.end.y - 8 * sc), 2 * sc, W)
			draw_circle(Vector2(r.end.x - 8 * sc, c.y + k * r.size.y * 0.2), 2 * sc, W)
	# 自動駕駛模式（FMA）
	var fma := "自動駕駛" if plane.ap_on else "手動飛行"
	_txt(Vector2(r.position.x + 6 * sc, r.position.y + 14 * sc), fma, int(11 * sc), GRN if plane.ap_on else W)
	if plane.ap_on:
		var ph: String = {"takeoff": "起飛", "climb": "爬升", "enroute": "巡航", "approach": "進場", "flare": "拉平", "rollout": "減速", "done": "停妥", "goaround": "重飛"}.get(plane.ap_phase, "保持")
		_txt(Vector2(r.position.x + 6 * sc, r.position.y + 27 * sc), ph if plane.ap_mode == "auto" else "保持", int(11 * sc), GRN)
	# 雷達高度
	if plane.agl < 760.0 and not plane.on_ground:
		_txt(Vector2(c.x - 30 * sc, r.end.y - 18 * sc), "%d" % int(plane.agl * G.M2FT), int(13 * sc), W if plane.agl > 60 else AMB, HORIZONTAL_ALIGNMENT_CENTER, 60 * sc)
	# 警告
	var wmsg: String = {"stall": "失速", "pullup": "拉起", "terrain": "地形", "gear": "起落架", "overspeed": "超速", "flapspeed": "襟翼超速"}.get(plane.warn, "")
	if wmsg != "" and fmod(_blink, 0.6) < 0.4:
		var wr := Rect2(c.x - 44 * sc, r.position.y + r.size.y * 0.22, 88 * sc, 24 * sc)
		draw_rect(wr, Color(0, 0, 0, 0.6))
		draw_rect(wr, RED, false, 2 * sc)
		_txt(Vector2(wr.position.x, wr.position.y + 18 * sc), wmsg, int(16 * sc), RED, HORIZONTAL_ALIGNMENT_CENTER, wr.size.x)

func _diamond(p: Vector2, s: float) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)]), MAG)

func _poly_clip(xf: Transform2D, poly: PackedVector2Array, col: Color, clip: Rect2) -> void:
	var pts := PackedVector2Array()
	for p in poly:
		pts.append(xf * p)
	var cl := Geometry2D.intersect_polygons(pts, PackedVector2Array([clip.position, Vector2(clip.end.x, clip.position.y), clip.end, Vector2(clip.position.x, clip.end.y)]))
	for q in cl:
		if (q as PackedVector2Array).size() >= 3:
			draw_colored_polygon(q, col)

func _line_clip(a: Vector2, b: Vector2, col: Color, w: float, clip: Rect2) -> void:
	var pts: Array = []
	var edges := [[clip.position, Vector2(clip.end.x, clip.position.y)], [Vector2(clip.end.x, clip.position.y), clip.end], [clip.end, Vector2(clip.position.x, clip.end.y)], [Vector2(clip.position.x, clip.end.y), clip.position]]
	for e in edges:
		var x = Geometry2D.segment_intersects_segment(a, b, e[0], e[1])
		if x != null:
			pts.append(x)
	if pts.size() >= 2:
		draw_line(pts[0], pts[1], col, w)

func _speed(r: Rect2, sc: float) -> void:
	draw_rect(r, Color(0.1, 0.12, 0.16, 0.9))
	var kt := plane.ias * G.MS2KT
	var ppk := r.size.y / 80.0
	var cy := r.get_center().y
	# 失速區與襟翼限速
	var vmax: float = Aircraft.FLAP_VMAX[plane.flaps]
	if vmax < 900.0:
		var y := cy - (vmax - kt) * ppk
		if y > r.position.y:
			draw_rect(Rect2(r.end.x - 6 * sc, r.position.y, 6 * sc, clampf(y - r.position.y, 0, r.size.y)), RED)
	var vs_k := 115.0 + (3 - plane.flaps) * 12.0
	var ys := cy - (vs_k - kt) * ppk
	if ys < r.end.y:
		draw_rect(Rect2(r.end.x - 6 * sc, maxf(ys, r.position.y), 6 * sc, r.end.y - maxf(ys, r.position.y)), Color(0.9, 0.2, 0.2, 0.8))
	var k0 := int(kt / 10.0) * 10 - 50
	for k in range(k0, k0 + 110, 10):
		if k < 0:
			continue
		var y := cy - (k - kt) * ppk
		if y < r.position.y or y > r.end.y:
			continue
		draw_line(Vector2(r.end.x - 12 * sc, y), Vector2(r.end.x - 6 * sc, y), W, 1.5 * sc)
		if k % 20 == 0:
			_txt(Vector2(r.position.x + 2 * sc, y + 4 * sc), str(k), int(10 * sc), W, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 16 * sc)
	# 目標速度
	if plane.ap_on:
		var ts := plane.ap_spd * G.MS2KT
		var y := clampf(cy - (ts - kt) * ppk, r.position.y, r.end.y)
		draw_colored_polygon(PackedVector2Array([Vector2(r.end.x, y), Vector2(r.end.x - 8 * sc, y - 5 * sc), Vector2(r.end.x - 8 * sc, y + 5 * sc)]), MAG)
	var box := Rect2(r.position.x, cy - 12 * sc, r.size.x - 4 * sc, 24 * sc)
	draw_rect(box, Color(0, 0, 0, 0.95))
	draw_rect(box, W, false, 1.5 * sc)
	_txt(Vector2(box.position.x, box.position.y + 18 * sc), "%d" % int(round(kt)), int(16 * sc), W, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	_txt(Vector2(r.position.x, r.position.y - 0 * sc + 12 * sc), "節", int(10 * sc), Color(0.7, 0.75, 0.8))

func _alt(r: Rect2, sc: float) -> void:
	draw_rect(r, Color(0.1, 0.12, 0.16, 0.9))
	var ft := plane.global_position.y * G.M2FT
	var ppf := r.size.y / 800.0
	var cy := r.get_center().y
	var f0 := int(ft / 100.0) * 100 - 500
	for f in range(f0, f0 + 1100, 100):
		var y := cy - (f - ft) * ppf
		if y < r.position.y or y > r.end.y:
			continue
		draw_line(Vector2(r.position.x, y), Vector2(r.position.x + 6 * sc, y), W, 1.5 * sc)
		if f % 200 == 0:
			_txt(Vector2(r.position.x + 8 * sc, y + 4 * sc), str(f), int(10 * sc), W)
	# 地面
	var gy := cy - (plane.ground_h() * G.M2FT - ft) * ppf
	if gy < r.end.y:
		draw_rect(Rect2(r.position.x, maxf(gy, r.position.y), 5 * sc, r.end.y - maxf(gy, r.position.y)), Color(0.8, 0.45, 0.15))
	if plane.ap_on:
		var ta := plane.ap_alt * G.M2FT
		var y := clampf(cy - (ta - ft) * ppf, r.position.y, r.end.y)
		draw_colored_polygon(PackedVector2Array([Vector2(r.position.x, y), Vector2(r.position.x + 8 * sc, y - 5 * sc), Vector2(r.position.x + 8 * sc, y + 5 * sc)]), MAG)
	var box := Rect2(r.position.x + 4 * sc, cy - 12 * sc, r.size.x - 4 * sc, 24 * sc)
	draw_rect(box, Color(0, 0, 0, 0.95))
	draw_rect(box, W, false, 1.5 * sc)
	_txt(Vector2(box.position.x, box.position.y + 18 * sc), "%d" % int(round(ft / 10.0) * 10), int(15 * sc), W, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	_txt(Vector2(r.position.x + 4 * sc, r.position.y + 12 * sc), "英尺", int(10 * sc), Color(0.7, 0.75, 0.8))

func _vsi(r: Rect2, sc: float) -> void:
	draw_rect(r, Color(0.1, 0.12, 0.16, 0.9))
	var fpm := plane.vs * G.M2FT * 60.0
	var cy := r.get_center().y
	for k in [-2000, -1000, 0, 1000, 2000]:
		var y: float = cy - k / 2000.0 * r.size.y * 0.45
		draw_line(Vector2(r.position.x, y), Vector2(r.position.x + 5 * sc, y), W, 1.2 * sc)
	var y := cy - clampf(fpm / 2000.0, -1.0, 1.0) * r.size.y * 0.45
	draw_line(Vector2(r.end.x, cy), Vector2(r.position.x + 4 * sc, y), GRN if absf(fpm) < 1500 else AMB, 3 * sc)
	_txt(Vector2(r.position.x - 4 * sc, (r.position.y + 12 * sc) if fpm >= 0 else (r.end.y - 4 * sc)), "%d" % int(round(fpm / 50.0) * 50), int(9 * sc), W, HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 8 * sc)

func _heading(r: Rect2, sc: float) -> void:
	draw_rect(r, Color(0.1, 0.12, 0.16, 0.9))
	var h := plane.heading
	var ppd := r.size.x / 70.0
	var cx := r.get_center().x
	var names := {0: "北", 90: "東", 180: "南", 270: "西"}
	var d0 := int(h) - 40
	for d in range(d0 - d0 % 5, d0 + 85, 5):
		var dd := fposmod(float(d), 360.0)
		var x := cx + G.angdiff(dd, h) * ppd
		if x < r.position.x or x > r.end.x:
			continue
		var big := int(dd) % 10 == 0
		draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + (8 if big else 4) * sc), W, 1.4 * sc)
		if int(dd) % 30 == 0:
			var lbl: String = names.get(int(dd), str(int(dd) / 10))
			_txt(Vector2(x - 12 * sc, r.position.y + 22 * sc), lbl, int(11 * sc), W, HORIZONTAL_ALIGNMENT_CENTER, 24 * sc)
	if target_hdg >= 0.0:
		var x := clampf(cx + G.angdiff(target_hdg, h) * ppd, r.position.x, r.end.x)
		draw_colored_polygon(PackedVector2Array([Vector2(x, r.position.y + 2 * sc), Vector2(x - 6 * sc, r.position.y + 12 * sc), Vector2(x + 6 * sc, r.position.y + 12 * sc)]), MAG)
	var box := Rect2(cx - 22 * sc, r.end.y - 16 * sc, 44 * sc, 16 * sc)
	draw_rect(box, Color(0, 0, 0, 0.95))
	draw_rect(box, W, false, 1.2 * sc)
	_txt(Vector2(box.position.x, box.end.y - 3 * sc), "%03d" % int(round(h)) , int(12 * sc), W, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
