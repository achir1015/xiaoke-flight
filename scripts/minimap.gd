class_name MiniMap
extends Control
## 地圖：小地圖（以飛機為中心、北朝上）與全臺大地圖（可點選機場改降）。

signal airport_clicked(id: String)

var plane: Aircraft
var terrain: Terrain
var big := false
var route: Array = []          # 世界座標 Vector3（紫色航線）
var dest_id := ""
var closed: Array = []
var storms: Array = []         # [Vector3 中心, 半徑]
var zoom_m := 24000.0           # 小地圖顯示的寬度（公尺）
var font: Font

func _ready() -> void:
	font = M.font_bold
	clip_contents = true

func _process(_d: float) -> void:
	queue_redraw()

func _w2m(p: Vector3, center: Vector3, scale: float) -> Vector2:
	return size * 0.5 + Vector2(p.x - center.x, p.z - center.z) * scale

func _gui_input(e: InputEvent) -> void:
	if not big:
		return
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var center := _center()
		var scale := _scale()
		for a in G.AIRPORTS:
			var mp := _w2m(G.apt_pos(a), center, scale)
			if mp.distance_to((e as InputEventMouseButton).position) < 26.0:
				airport_clicked.emit(a.id)
				accept_event()
				return

func _center() -> Vector3:
	if big:
		return Vector3(Terrain.X0 + Terrain.W * 0.5 - 2000.0, 0, Terrain.Z0 + Terrain.H * 0.5)
	return plane.global_position if plane else Vector3.ZERO

func _scale() -> float:
	if big:
		return minf(size.x / (Terrain.W + 2000.0), size.y / (Terrain.H - 2000.0))
	return size.x / zoom_m

func _draw() -> void:
	if terrain == null:
		return
	var center := _center()
	var scale := _scale()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.11, 0.3, 0.5))
	# 地形圖
	var tl := _w2m(Vector3(Terrain.X0, 0, Terrain.Z0), center, scale)
	var br := _w2m(Vector3(Terrain.X0 + (terrain.NX - 1) * terrain.S, 0, Terrain.Z0 + (terrain.NZ - 1) * terrain.S), center, scale)
	draw_texture_rect(terrain.map_tex, Rect2(tl, br - tl), false)
	# 城市名稱（大地圖）
	if big:
		for c in G.CITIES:
			var wp := Vector3(G.geo(c[1], c[2]).x, 0, G.geo(c[1], c[2]).y)
			var near_apt := false
			for a in G.AIRPORTS:
				if Vector2(G.apt_pos(a).x - wp.x, G.apt_pos(a).z - wp.z).length() < 3500.0:
					near_apt = true
			if near_apt:
				continue
			var p := _w2m(wp, center, scale)
			draw_string(font, p + Vector2(-20, 4), c[0], HORIZONTAL_ALIGNMENT_CENTER, 40, 12, Color(1, 1, 1, 0.75))
	# 雷雨胞
	for s in storms:
		var p := _w2m(s[0], center, scale)
		draw_circle(p, s[1] * scale, Color(1, 0.15, 0.1, 0.28))
		draw_arc(p, s[1] * scale, 0, TAU, 32, Color(1, 0.3, 0.2, 0.9), 2.0)
	# 航線
	if route.size() >= 2:
		var pts := PackedVector2Array()
		for r in route:
			pts.append(_w2m(r, center, scale))
		draw_polyline(pts, Color(0.95, 0.35, 0.95), 3.0 if big else 2.5)
	# 機場
	for a in G.AIRPORTS:
		var ap := G.apt_pos(a)
		var p := _w2m(ap, center, scale)
		if p.x < -40 or p.y < -40 or p.x > size.x + 40 or p.y > size.y + 40:
			continue
		var d: Vector3 = G.hdg_dir(a.hdg) * a.len * 0.5 * scale
		var col := Color(0.3, 1.0, 0.45)
		if a.id in closed:
			col = Color(1, 0.3, 0.25)
		draw_line(p - Vector2(d.x, d.z), p + Vector2(d.x, d.z), Color(0.1, 0.1, 0.1), 5.0 if big else 4.0)
		draw_circle(p, 6.0 if big else 4.5, col)
		if a.id == dest_id:
			draw_arc(p, 12.0, 0, TAU, 24, Color(0.95, 0.35, 0.95), 2.5)
		var nm: String = a.short + ("（關閉）" if a.id in closed else "")
		draw_string(font, p + Vector2(8, -6), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14 if big else 11, Color.WHITE)
	# 飛機
	if plane:
		var pp := _w2m(plane.global_position, center, scale)
		var a := deg_to_rad(plane.heading)
		var f := Vector2(sin(a), -cos(a))
		var r := Vector2(-f.y, f.x)
		var s := 9.0 if big else 8.0
		draw_colored_polygon(PackedVector2Array([pp + f * s * 1.4, pp + r * s - f * s, pp - f * s * 0.4, pp - r * s - f * s]), Color(1, 0.85, 0.15))
		draw_polyline(PackedVector2Array([pp + f * s * 1.4, pp + r * s - f * s, pp - f * s * 0.4, pp - r * s - f * s, pp + f * s * 1.4]), Color(0.1, 0.1, 0.1), 1.5)
	# 方位與比例尺
	draw_string(font, Vector2(size.x - 22, 18), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	draw_line(Vector2(size.x - 15, 22), Vector2(size.x - 15, 34), Color.WHITE, 2.0)
	var km := 5.0 if not big else 10.0
	var bl := km * 1000.0 * scale
	draw_line(Vector2(8, size.y - 10), Vector2(8 + bl, size.y - 10), Color.WHITE, 2.0)
	draw_string(font, Vector2(8, size.y - 14), "%d 公里" % int(km), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.4), false, 1.5)
