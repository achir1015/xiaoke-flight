class_name HelpAnim
extends Control
## 遊戲說明的動畫插圖（程式繪製）：起飛、操縱桿、儀表、降落、自動駕駛、小柯、天氣、客艙、劫機、地圖、按鍵、捷徑。

var kind := "takeoff"
var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(500, 190)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _plane(p: Vector2, ang: float, s: float, col := Color.WHITE) -> void:
	var xf := Transform2D(ang, p)
	var body := PackedVector2Array([Vector2(-40, -5), Vector2(36, -5), Vector2(46, 0), Vector2(36, 5), Vector2(-40, 5)])
	var wing := PackedVector2Array([Vector2(-6, 2), Vector2(8, 2), Vector2(-14, 26), Vector2(-22, 26)])
	var tail := PackedVector2Array([Vector2(-40, -4), Vector2(-30, -4), Vector2(-40, -20), Vector2(-46, -20)])
	for poly in [wing, body, tail]:
		var q := PackedVector2Array()
		for v in poly:
			q.append(xf * (v * s))
		draw_colored_polygon(q, col if poly != tail else Color(0.18, 0.43, 0.82))
	draw_line(xf * (Vector2(-34, 1) * s), xf * (Vector2(34, 1) * s), Color(0.95, 0.53, 0.2), 2.0 * s)

func _txt(p: Vector2, s: String, size := 15, c := Color.WHITE) -> void:
	draw_string(M.font_bold, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)

func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.14, 0.24))
	var t := _t
	match kind:
		"takeoff":
			draw_rect(Rect2(0, h * 0.62, w, h * 0.38), Color(0.3, 0.48, 0.25))
			draw_rect(Rect2(0, h * 0.7, w, 18), Color(0.22, 0.22, 0.24))
			for i in 12:
				draw_rect(Rect2(fposmod(i * 60.0 - t * 160.0, w + 60) - 30, h * 0.7 + 8, 30, 3), Color.WHITE)
			var ph := fmod(t, 6.0)
			var lift := maxf(0.0, ph - 3.0)
			var ang := -minf(lift * 0.25, 0.22)
			var p := Vector2(w * 0.25 + ph * 40.0, h * 0.68 - lift * lift * 9.0)
			_plane(p, ang, 1.4)
			var kt := int(minf(ph / 3.0, 1.0) * 144.0 + lift * 15.0)
			_txt(Vector2(14, 26), "速度 %d 節" % kt, 18, Color(1, 0.85, 0.3))
			_txt(Vector2(14, 50), "油門全開 → 144 節抬輪 → 收起落架" if ph < 3.0 else "抬輪！正爬升率", 15)
			draw_rect(Rect2(w - 60, 20, 30, 120), Color(0.15, 0.17, 0.22))
			draw_rect(Rect2(w - 60, 20 + 120 * (1.0 - minf(ph / 1.0, 1.0)), 30, 120 * minf(ph / 1.0, 1.0)), Color(0.35, 0.85, 0.45))
			_txt(Vector2(w - 70, 160), "油門", 14)
		"yoke":
			var c := Vector2(w * 0.3, h * 0.55)
			draw_circle(c, 58, Color(0.15, 0.17, 0.22))
			var k := Vector2(sin(t * 1.3), sin(t * 0.9)) * 38.0
			draw_circle(c + k, 22, Color(0.95, 0.53, 0.2))
			_txt(c + Vector2(-20, -66), "往上推", 13)
			_txt(c + Vector2(-20, 80), "往下拉", 13)
			var bank := -k.x / 38.0 * 0.6
			var pitch := k.y / 38.0 * 0.4
			var p := Vector2(w * 0.72, h * 0.5)
			draw_rect(Rect2(p.x - 120, p.y - 80, 240, 160), Color(0.18, 0.45, 0.82))
			draw_set_transform(p, bank, Vector2.ONE)
			draw_rect(Rect2(-200, pitch * 120.0, 400, 200), Color(0.55, 0.36, 0.2))
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			draw_rect(Rect2(p.x - 40, p.y - 3, 30, 6), Color(1, 0.85, 0.1))
			draw_rect(Rect2(p.x + 10, p.y - 3, 30, 6), Color(1, 0.85, 0.1))
			_txt(Vector2(p.x - 110, p.y + 100), "左右＝傾斜轉彎　上下＝機頭俯仰", 14)
		"pfd":
			var r := Rect2(w * 0.2, 20, w * 0.6, h - 40)
			draw_rect(r, Color(0.18, 0.45, 0.82))
			draw_rect(Rect2(r.position.x, r.get_center().y + sin(t) * 12.0, r.size.x, r.size.y * 0.5 - sin(t) * 12.0), Color(0.55, 0.36, 0.2))
			draw_rect(Rect2(r.position.x - 70, 20, 60, h - 40), Color(0.1, 0.12, 0.16))
			draw_rect(Rect2(r.end.x + 10, 20, 70, h - 40), Color(0.1, 0.12, 0.16))
			_txt(Vector2(r.position.x - 64, h * 0.5 + 6), "%d" % int(250 + sin(t) * 20), 18)
			_txt(Vector2(r.end.x + 14, h * 0.5 + 6), "%d" % int(5000 + sin(t * 0.7) * 400), 18)
			_txt(Vector2(r.position.x - 66, 40), "空速", 13, Color(0.7, 0.8, 0.9))
			_txt(Vector2(r.end.x + 14, 40), "高度", 13, Color(0.7, 0.8, 0.9))
			var d := Vector2(r.get_center().x + sin(t * 1.5) * 40.0, r.end.y - 10)
			draw_colored_polygon(PackedVector2Array([d + Vector2(0, -7), d + Vector2(7, 0), d + Vector2(0, 7), d + Vector2(-7, 0)]), Color(0.95, 0.4, 0.95))
			_txt(Vector2(r.position.x + 8, r.position.y + 20), "姿態儀", 14)
		"landing":
			draw_rect(Rect2(0, h * 0.75, w, h * 0.25), Color(0.3, 0.48, 0.25))
			draw_rect(Rect2(w * 0.55, h * 0.75, w * 0.45, 10), Color(0.22, 0.22, 0.24))
			draw_line(Vector2(0, h * 0.75 - w * 0.55 * 0.12), Vector2(w * 0.6, h * 0.75), Color(0.95, 0.4, 0.95, 0.6), 2.0)
			var f := fmod(t * 0.2, 1.0)
			var x := f * w * 0.62
			var y := h * 0.75 - (w * 0.6 - x) * 0.12 - 8
			if x > w * 0.56:
				y = h * 0.75 - 8
			_plane(Vector2(x, y), 0.03, 0.9)
			for i in 4:
				var white := i < 2
				draw_circle(Vector2(w * 0.62 + i * 14, h * 0.72), 5, Color.WHITE if white else Color(1, 0.15, 0.1))
			_txt(Vector2(w * 0.6, h * 0.65), "PAPI：兩白兩紅＝剛好", 13)
			_txt(Vector2(14, 26), "3° 下滑道・140 節・放起落架與襟翼", 16, Color(1, 0.85, 0.3))
		"autopilot":
			var steps := ["自動起飛", "爬升", "巡航", "進場", "自動落地", "煞停"]
			var cur := int(t * 0.8) % steps.size()
			for i in steps.size():
				var p := Vector2(30 + i * (w - 60) / 5.0, h * 0.5)
				draw_circle(p, 16, Color(0.35, 0.85, 0.45) if i <= cur else Color(0.3, 0.33, 0.4))
				_txt(p + Vector2(-30, 40), steps[i], 14)
				if i < steps.size() - 1:
					draw_line(p + Vector2(18, 0), p + Vector2((w - 60) / 5.0 - 18, 0), Color(0.6, 0.65, 0.75), 2)
			_txt(Vector2(14, 28), "按「自動駕駛」，小柯全程幫你飛", 17, Color(1, 0.85, 0.3))
		"xiaoke":
			var c := Vector2(w * 0.22, h * 0.5)
			draw_rect(Rect2(c + Vector2(-45, -40), Vector2(90, 76)), Color(0.96, 0.97, 0.99))
			draw_rect(Rect2(c + Vector2(-34, -28), Vector2(68, 44)), Color(0.08, 0.12, 0.22))
			draw_rect(Rect2(c + Vector2(-20, -16), Vector2(12, 12)), Color(0.38, 0.94, 1.0))
			draw_rect(Rect2(c + Vector2(8, -16), Vector2(12, 12)), Color(0.38, 0.94, 1.0))
			draw_rect(Rect2(c + Vector2(-9, 4), Vector2(18, 3 + absf(sin(t * 12)) * 6)), Color(0.38, 0.94, 1.0))
			var msgs := ["幫我聯絡塔台", "最近的機場在哪？", "交給你自動駕駛", "打開地圖"]
			var m: String = msgs[int(t * 0.5) % msgs.size()]
			draw_rect(Rect2(w * 0.42, h * 0.3, w * 0.52, 40), Color(0.25, 0.35, 0.55))
			_txt(Vector2(w * 0.44, h * 0.3 + 27), "機長：" + m, 15)
			for i in 5:
				var a := absf(sin(t * 6 + i)) * 18 + 4
				draw_rect(Rect2(w * 0.44 + i * 12, h * 0.72 - a, 8, a), Color(0.35, 0.85, 0.45))
			_txt(Vector2(w * 0.44 + 70, h * 0.72), "按住麥克風說話", 14)
		"weather":
			for i in 40:
				var x := fposmod(i * 37.0 + t * 60.0, w)
				var y := fposmod(i * 53.0 + t * 260.0, h)
				draw_line(Vector2(x, y), Vector2(x - 4, y + 14), Color(0.75, 0.82, 0.95, 0.7), 1.5)
			draw_circle(Vector2(w * 0.7, h * 0.45), 50, Color(1, 0.2, 0.1, 0.3))
			draw_arc(Vector2(w * 0.7, h * 0.45), 50, 0, TAU, 32, Color(1, 0.3, 0.2), 2)
			if fmod(t, 2.2) < 0.15:
				draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.35))
				draw_polyline(PackedVector2Array([Vector2(w * 0.7, 10), Vector2(w * 0.68, 50), Vector2(w * 0.72, 70), Vector2(w * 0.69, 120)]), Color(0.9, 0.95, 1), 3)
			_plane(Vector2(w * 0.25 + sin(t) * 6, h * 0.5 + sin(t * 7) * 4), sin(t * 5) * 0.06, 0.9)
			_txt(Vector2(14, 26), "紅圈＝雷雨胞，繞過去！", 16, Color(1, 0.85, 0.3))
		"cabin":
			for r in 5:
				for cc in 6:
					var p := Vector2(w * 0.25 + cc * 40 + (20 if cc >= 3 else 0), 30 + r * 30)
					draw_rect(Rect2(p, Vector2(30, 22)), Color(0.16, 0.3, 0.58))
					draw_circle(p + Vector2(15, 8), 7, Color(0.95, 0.8, 0.65))
			draw_circle(Vector2(w * 0.25 + 140, 120), 9, Color(1, 0.3, 0.3, 0.5 + 0.5 * sin(t * 6)))
			var bw := 160.0 * (0.5 + 0.4 * sin(t * 0.5))
			draw_rect(Rect2(14, h - 30, 170, 14), Color(0.2, 0.2, 0.25))
			draw_rect(Rect2(14, h - 30, bw, 14), Color(0.35, 0.85, 0.45))
			_txt(Vector2(14, h - 36), "病人狀況", 13)
		"hijack":
			var digits := "7500"
			for i in 4:
				draw_rect(Rect2(w * 0.3 + i * 52, h * 0.3, 44, 60), Color(0.05, 0.06, 0.08))
				if t * 1.5 > i:
					_txt(Vector2(w * 0.3 + i * 52 + 10, h * 0.3 + 44), digits[i], 34, Color(1, 0.6, 0.2))
			_txt(Vector2(w * 0.3, h * 0.3 - 10), "應答機", 14)
			_txt(Vector2(14, h - 20), "冷靜 → 7500 通知塔台 → 平穩談判 → 落地", 15, Color(1, 0.85, 0.3))
		"map":
			draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, 14), Vector2(w * 0.58, 40), Vector2(w * 0.6, 110), Vector2(w * 0.52, h - 14), Vector2(w * 0.42, 120), Vector2(w * 0.44, 40)]), Color(0.35, 0.55, 0.3))
			draw_polyline(PackedVector2Array([Vector2(w * 0.5, 30), Vector2(w * 0.47, 100), Vector2(w * 0.49, h - 30)]), Color(0.95, 0.35, 0.95), 3)
			for p in [Vector2(w * 0.5, 30), Vector2(w * 0.49, h - 30), Vector2(w * 0.57, 90)]:
				draw_circle(p, 6, Color(0.3, 1.0, 0.45))
			var f := fmod(t * 0.15, 1.0)
			_plane(Vector2(w * 0.5, 30).lerp(Vector2(w * 0.49, h - 30), f), PI / 2, 0.35, Color(1, 0.85, 0.15))
		"keys":
			var keys := [["W", "機頭下"], ["S", "機頭上"], ["A", "左傾"], ["D", "右傾"], ["Shift", "加油門"], ["G", "起落架"], ["Z", "自動駕駛"], ["C", "視角"]]
			for i in keys.size():
				var p := Vector2(20 + (i % 4) * (w - 20) / 4.0, 40 + (i / 4) * 80)
				var on := int(t * 2.0) % keys.size() == i
				draw_rect(Rect2(p, Vector2(64, 44)), Color(0.95, 0.53, 0.2) if on else Color(0.25, 0.3, 0.4))
				_txt(p + Vector2(10, 30), keys[i][0], 18)
				_txt(p + Vector2(0, 64), keys[i][1], 13)
		_:
			var c := Vector2(w * 0.5, h * 0.5)
			draw_rect(Rect2(c - Vector2(36, 36), Vector2(72, 72)), Color(0.15, 0.45, 0.85))
			draw_rect(Rect2(c - Vector2(24, 18), Vector2(48, 30)), Color(0.96, 0.97, 0.99))
			var yy := c.y + 70 + sin(t * 3) * 6
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - 12, yy), Vector2(c.x + 12, yy), Vector2(c.x, yy - 16)]), Color(1, 0.85, 0.3))
			_txt(Vector2(c.x - 70, h - 12), "加入主畫面，一點就開", 14)
