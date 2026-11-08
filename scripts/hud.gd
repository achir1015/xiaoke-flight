class_name Hud
extends CanvasLayer
## 全部介面（繁體中文）：標題、任務關卡、自由飛行、飛行畫面（儀表、操縱桿、油門、按鈕、地圖、小柯、客艙、事件）、結算、說明、設定。

const BG := Color(0.07, 0.1, 0.17, 0.86)
const BG2 := Color(0.12, 0.16, 0.25, 0.97)
const ACC := Color(1.0, 0.68, 0.22)
const TXT := Color(0.95, 0.96, 0.98)
const DIM := Color(0.66, 0.72, 0.82)
const GOOD := Color(0.45, 0.9, 0.55)
const BAD := Color(1.0, 0.42, 0.38)
const SKYB := Color(0.25, 0.55, 0.95)

var main
var root: Control
var title_box: Control
var game_box: Control
var modal: Control
var update_bar: PanelContainer
var pfd: PFD
var minimap: MiniMap
var map_big := false
var map_holder: PanelContainer
var level_lbl: Label
var mission_lbl: Label
var sub_panel: PanelContainer
var sub_portrait: Portrait
var sub_name: Label
var sub_text: Label
var xk_btn: Button
var xk_portrait: Portrait
var xk_panel: PanelContainer
var xk_log: RichTextLabel
var xk_input: LineEdit
var mic_btn: Button
var event_box: VBoxContainer
var event_panels: Dictionary = {}
var cabin_panel: PanelContainer
var cabin_view: CabinView
var alert_lbl: Label
var throttle_slider: VSlider
var n1_lbl: Label
var info_lbl: Label
var btns: Dictionary = {}
var yoke: Control
var yoke_vec := Vector2.ZERO
var pad_vec := Vector2.ZERO
var brake_held := false
var seatbelt := false
var squawk := "2000"
var divert_box: PanelContainer
var _help_page := -1
var _voice_btn: Button
var _sub_hide := 0.0
var _alert_t := 0.0
var portrait_hint: PanelContainer
var right_panel: PanelContainer
var clock_lbl: RichTextLabel
var check_panel: PanelContainer
var check_lbl: RichTextLabel
var title_clock: Label
var _last_vp := Vector2.ZERO

func _ready() -> void:
	layer = 5
	M.init_fonts()
	root = Control.new()
	var th := Theme.new()
	th.default_font = M.font_ui
	th.default_font_size = 16
	th.set_font("bold_font", "RichTextLabel", M.font_bold)
	th.set_font("normal_font", "RichTextLabel", M.font_ui)
	root.theme = th
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	update_bar = _panel(Color(0.12, 0.35, 0.2, 0.95), 10, 10)
	update_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	update_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	update_bar.position.y = 6
	update_bar.visible = false
	Updater.update_available.connect(_on_update)
	Snd.line_started.connect(_on_line)
	Snd.line_finished.connect(func(_id): _sub_hide = 1.2)
	portrait_hint = _panel(Color(0.05, 0.08, 0.14, 0.96), 14, 18)
	portrait_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	portrait_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	portrait_hint.grow_vertical = Control.GROW_DIRECTION_BOTH
	var ph := _lbl("請把手機橫放\n飛行畫面會比較好操作", 34, ACC)
	ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_hint.add_child(ph)
	portrait_hint.visible = false
	get_viewport().size_changed.connect(_check_portrait)

func _check_portrait() -> void:
	var s := root.get_viewport_rect().size
	portrait_hint.visible = s.y > s.x * 1.1
	if portrait_hint.get_parent() == null:
		root.add_child(portrait_hint)
	root.move_child(portrait_hint, root.get_child_count() - 1)

# ── 小工具 ──
func _sb(c: Color, r := 10, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.7
	s.content_margin_bottom = pad * 0.7
	return s

func _panel(c := BG, r := 12, pad := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(c, r, pad))
	return p

func _lbl(t: String, size := 16, c := TXT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	if size >= 19:
		l.add_theme_font_override("font", M.font_bold)
	return l

func _btn(t: String, cb: Callable, accent := false, size := 16, col := Color(0.22, 0.28, 0.4)) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	var base := ACC if accent else col
	b.add_theme_stylebox_override("normal", _sb(base, 8, 12))
	b.add_theme_stylebox_override("hover", _sb(base.lightened(0.12), 8, 12))
	b.add_theme_stylebox_override("pressed", _sb(base.darkened(0.15), 8, 12))
	b.add_theme_stylebox_override("disabled", _sb(Color(0.2, 0.22, 0.28), 8, 12))
	var fc := Color(0.08, 0.08, 0.1) if accent else TXT
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, fc)
	b.add_theme_color_override("font_disabled_color", DIM)
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(func():
		Snd.play("click", 0.5)
		cb.call())
	return b

func _toggle_style(b: Button, on: bool, on_col := Color(0.2, 0.62, 0.35)) -> void:
	var base := on_col if on else Color(0.22, 0.28, 0.4)
	b.add_theme_stylebox_override("normal", _sb(base, 8, 8))
	b.add_theme_stylebox_override("hover", _sb(base.lightened(0.12), 8, 8))

func _clear(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()

# ══════════════ 標題畫面 ══════════════
func show_title() -> void:
	if game_box:
		game_box.visible = false
	if title_box:
		title_box.queue_free()
	title_box = Control.new()
	title_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_box)
	root.move_child(title_box, 0)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.06, 0.12, 0.92))
	g.set_color(1, Color(0.03, 0.06, 0.12, 0.0))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(0.62, 0.5)
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.add_child(grad)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	v.position = Vector2(64, -300)
	v.add_theme_constant_override("separation", 10)
	title_box.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	var ic := TextureRect.new()
	ic.texture = load("res://icon.svg")
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(76, 76)
	top.add_child(ic)
	var sl := _lbl("小柯機器人系列", 18, Color(0.55, 0.85, 1.0))
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(sl)
	var t := _lbl("小柯機器人3D真實飛行", 50, ACC)
	t.add_theme_constant_override("outline_size", 8)
	t.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.08))
	v.add_child(t)
	v.add_child(_lbl("駕駛客機翱翔臺灣上空：起飛、降落、天氣與機上突發狀況，AI 小柯陪你飛", 17, DIM))
	var sp := Control.new()
	sp.custom_minimum_size.y = 12
	v.add_child(sp)
	var bw := 280
	var b0 := _btn("任務關卡", show_levels, true, 21)
	b0.custom_minimum_size = Vector2(bw, 54)
	v.add_child(b0)
	var items: Array = [["自由飛行", show_free], ["遊戲說明", func(): show_help(0)], ["設定", show_settings], ["更新紀錄", show_changelog]]
	if not G.is_ios():
		items.append(["建立捷徑", show_install])
	if OS.has_feature("web") and G.is_touch():
		items.append(["全螢幕", func(): G.go_fullscreen()])
	for it in items:
		var b := _btn(it[0], it[1], false, 17)
		b.custom_minimum_size = Vector2(bw, 44)
		v.add_child(b)
	title_clock = _lbl(clock_text(), 16, TXT)
	title_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_clock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	title_clock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	title_clock.position = Vector2(-330, 20)
	title_clock.custom_minimum_size.x = 310
	title_clock.add_theme_constant_override("outline_size", 6)
	title_clock.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title_box.add_child(title_clock)
	var foot := _lbl("v%s　・　開發者：吳玉柱 先生與 Claude AI Opus 5.5" % G.APP_VERSION, 14, DIM)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(24, -36)
	title_box.add_child(foot)
	var credit := _lbl("地形、機場與客機：程序生成原創模型　字型：Noto Sans TC（OFL）　音樂音效：原創合成　語音：臺灣華語神經語音", 12, Color(0.55, 0.6, 0.68))
	credit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	credit.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	credit.position = Vector2(-credit.get_minimum_size().x - 24, -32)
	title_box.add_child(credit)
	if update_bar.get_parent() == null:
		root.add_child(update_bar)
	_check_portrait()

func show_levels() -> void:
	close_modal()
	var v := _modal("任務關卡", 860)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	for i in G.LEVELS.size():
		var L: Dictionary = G.LEVELS[i]
		var locked := i >= G.unlocked
		var p := _panel(Color(0.17, 0.22, 0.33) if not locked else Color(0.14, 0.15, 0.2), 10, 10)
		p.custom_minimum_size = Vector2(266, 0)
		grid.add_child(p)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 3)
		p.add_child(cv)
		var st := int(G.stars.get(str(i), 0))
		cv.add_child(_lbl("第 %d 關　%s" % [i + 1, "★".repeat(st) + "☆".repeat(3 - st)], 14, ACC))
		cv.add_child(_lbl(L.title, 19, TXT if not locked else DIM))
		var route: String = G.airport(L.from).short
		if L.to != "" and L.to != L.from:
			route += " → " + G.airport(L.to).short
		var evn := ""
		for e in L.events:
			evn += G.EVENT_NAMES[e] + " "
		cv.add_child(_lbl("%s・%s・%s" % [route, G.TIME_NAMES[L.time], G.WEATHER_NAMES[L.weather]], 13, DIM))
		if evn != "":
			cv.add_child(_lbl("狀況：" + evn, 13, Color(1, 0.6, 0.5)))
		var d := _lbl(L.desc, 13, TXT)
		d.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		d.custom_minimum_size.x = 240
		cv.add_child(d)
		var ii := i
		var b := _btn("先完成上一關" if locked else "出發", func(): close_modal(); main.start_level(ii), not locked, 15)
		b.disabled = locked
		cv.add_child(b)
	_modal_buttons(v, [["返回", func(): close_modal(), false]])

func show_free() -> void:
	close_modal()
	var v := _modal("自由飛行", 560)
	var opts := {}
	var rows := [["出發機場", "from", G.AIRPORTS.map(func(a): return a.name)], ["目的地", "to", G.AIRPORTS.map(func(a): return a.name)],
		["時段", "time", ["白天", "黃昏", "夜晚"]], ["天氣", "weather", ["晴朗", "多雲", "下雨", "雷雨", "颱風", "下雪"]],
		["突發狀況", "event", ["無", "孕婦臨盆", "高血壓", "心臟病發", "劫機"]]]
	for r in rows:
		var h := HBoxContainer.new()
		var l := _lbl(r[0], 16)
		l.custom_minimum_size.x = 110
		h.add_child(l)
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.custom_minimum_size = Vector2(300, 38)
		for it in r[2]:
			ob.add_item(it)
		h.add_child(ob)
		v.add_child(h)
		opts[r[1]] = ob
	(opts.to as OptionButton).select(3)
	v.add_child(_lbl("提示：起飛後也可以從小柯的對話視窗觸發狀況。", 13, DIM))
	_modal_buttons(v, [["起飛", func():
		var wx: String = ["clear", "cloudy", "rain", "storm", "typhoon", "snow"][(opts.weather as OptionButton).selected]
		var tm: String = ["day", "dusk", "night"][(opts.time as OptionButton).selected]
		var ev: String = ["", "labor", "hypertension", "cardiac", "hijack"][(opts.event as OptionButton).selected]
		var evs: Array = []
		if ev != "": evs.append(ev)
		if wx in ["rain", "storm", "typhoon", "snow"]: evs.append(wx)
		var fa: String = G.AIRPORTS[(opts.from as OptionButton).selected].id
		var ta: String = G.AIRPORTS[(opts.to as OptionButton).selected].id
		if ta == fa: ta = ""
		close_modal()
		main.start_flight({"title": "自由飛行", "from": fa, "to": ta, "mode": "route" if ta != "" else "free", "time": tm, "weather": wx, "events": evs}, -1), true], ["返回", func(): close_modal(), false]])

# ══════════════ 飛行畫面 ══════════════
func build_game() -> void:
	game_box = Control.new()
	game_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_box.visible = false
	root.add_child(game_box)
	# 左上：暫停、視角、截圖、地圖
	var tl := VBoxContainer.new()
	tl.position = Vector2(12, 12)
	tl.add_theme_constant_override("separation", 6)
	game_box.add_child(tl)
	var tools: Array = [["暫停", func(): main.toggle_pause()], ["視角", func(): alert(main.cam.next_mode(), 1.2)], ["截圖", screenshot], ["地圖", func(): open_map(not map_big)], ["客艙", func(): show_cabin(not cabin_panel.visible)]]
	if G.is_ios():
		tools = tools.filter(func(e): return e[0] != "截圖")  # iOS 用系統截圖即可
	for it in tools:
		var b := _btn(it[0], it[1], false, 14, Color(0.1, 0.2, 0.38, 0.9))
		b.custom_minimum_size = Vector2(92, 36)
		tl.add_child(b)
	# 當地日期時間
	clock_lbl = RichTextLabel.new()
	clock_lbl.fit_content = true
	clock_lbl.scroll_active = false
	clock_lbl.bbcode_enabled = true
	clock_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	clock_lbl.custom_minimum_size = Vector2(100, 0)
	clock_lbl.position = Vector2(8, 234)
	clock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_lbl.add_theme_font_size_override("normal_font_size", 13)
	clock_lbl.add_theme_constant_override("outline_size", 6)
	clock_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	game_box.add_child(clock_lbl)
	# 上方：任務列
	var mp := _panel(BG, 10, 10)
	mp.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	mp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mp.position.y = 10
	mp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_box.add_child(mp)
	mission_lbl = _lbl("", 15)
	mission_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mp.add_child(mission_lbl)
	# 字幕（說話的人）
	sub_panel = _panel(Color(0.04, 0.06, 0.12, 0.88), 12, 10)
	sub_panel.position = Vector2(470, 88)
	sub_panel.custom_minimum_size.x = 494
	sub_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_panel.visible = false
	game_box.add_child(sub_panel)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 10)
	sub_panel.add_child(sh)
	sub_portrait = Portrait.new()
	sub_portrait.custom_minimum_size = Vector2(58, 58)
	sh.add_child(sub_portrait)
	var sv := VBoxContainer.new()
	sh.add_child(sv)
	sub_name = _lbl("", 14, ACC)
	sv.add_child(sub_name)
	sub_text = _lbl("", 17)
	sub_text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	sub_text.custom_minimum_size.x = 400
	sv.add_child(sub_text)
	# 右上：關卡、小地圖、小柯
	level_lbl = _lbl("", 15, Color(0.5, 0.85, 1.0))
	level_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	level_lbl.position = Vector2(-330, 12)
	game_box.add_child(level_lbl)
	map_holder = _panel(Color(0, 0, 0, 0.5), 8, 3)
	map_holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	map_holder.position = Vector2(-222, 40)
	game_box.add_child(map_holder)
	minimap = MiniMap.new()
	minimap.custom_minimum_size = Vector2(210, 170)
	minimap.airport_clicked.connect(_map_airport)
	map_holder.add_child(minimap)
	xk_btn = Button.new()
	xk_btn.flat = true
	xk_btn.focus_mode = Control.FOCUS_NONE
	xk_btn.custom_minimum_size = Vector2(86, 86)
	xk_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	xk_btn.position = Vector2(-318, 40)
	xk_btn.pressed.connect(func(): toggle_xk())
	xk_btn.tooltip_text = "小柯 AI 助理"
	game_box.add_child(xk_btn)
	xk_portrait = Portrait.new()
	xk_portrait.who = "xiaoke"
	xk_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	xk_btn.add_child(xk_portrait)
	var xl := _lbl("小柯", 13, ACC)
	xl.position = Vector2(24, 86)
	xk_btn.add_child(xl)
	_build_xk_panel()
	# 左側：事件面板與客艙
	var lv := VBoxContainer.new()
	lv.position = Vector2(116, 12)
	lv.add_theme_constant_override("separation", 8)
	game_box.add_child(lv)
	event_box = VBoxContainer.new()
	event_box.add_theme_constant_override("separation", 6)
	lv.add_child(event_box)
	cabin_panel = _panel(Color(0, 0, 0, 0.6), 8, 4)
	cabin_panel.visible = false
	lv.add_child(cabin_panel)
	var cv := VBoxContainer.new()
	cabin_panel.add_child(cv)
	var chd := HBoxContainer.new()
	cv.add_child(chd)
	var ct := _lbl("客艙即時畫面", 13, ACC)
	ct.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chd.add_child(ct)
	var vb := _btn("切換視角", func(): alert(cabin_view.toggle_view(), 1.0), false, 12)
	vb.custom_minimum_size = Vector2(0, 26)
	chd.add_child(vb)
	var xb := _btn("×", func(): show_cabin(false), false, 12)
	xb.custom_minimum_size = Vector2(28, 26)
	chd.add_child(xb)
	cabin_view = CabinView.new()
	cabin_view.custom_minimum_size = Vector2(300, 169)
	cabin_view.clicked.connect(_cabin_talk)
	cv.add_child(cabin_view)
	# 降落檢查表
	check_panel = _panel(Color(0.05, 0.12, 0.2, 0.9), 10, 10)
	check_panel.visible = false
	check_panel.custom_minimum_size.x = 250
	check_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	lv.add_child(check_panel)
	var ckv := VBoxContainer.new()
	ckv.add_theme_constant_override("separation", 2)
	check_panel.add_child(ckv)
	ckv.add_child(_lbl("降落檢查表", 16, ACC))
	check_lbl = RichTextLabel.new()
	check_lbl.bbcode_enabled = true
	check_lbl.fit_content = true
	check_lbl.custom_minimum_size = Vector2(240, 0)
	check_lbl.add_theme_font_size_override("normal_font_size", 14)
	ckv.add_child(check_lbl)
	# 左下：方向鍵
	_build_pad()
	# 下方：主飛行儀表與操縱桿
	pfd = PFD.new()
	pfd.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	pfd.custom_minimum_size = Vector2(420, 210)
	pfd.size = Vector2(420, 210)
	pfd.position = Vector2(-310, -218)
	game_box.add_child(pfd)
	yoke = Control.new()
	yoke.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	yoke.size = Vector2(170, 170)
	yoke.position = Vector2(122, -186)
	yoke.mouse_filter = Control.MOUSE_FILTER_STOP
	yoke.gui_input.connect(_yoke_input)
	yoke.draw.connect(_yoke_draw)
	game_box.add_child(yoke)
	# 右側：油門與系統按鈕
	var rp := _panel(BG, 10, 8)
	right_panel = rp
	game_box.add_child(rp)
	var rh := HBoxContainer.new()
	rh.add_theme_constant_override("separation", 8)
	rp.add_child(rh)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	rh.add_child(col)
	for it in [["gear", "起落架 ▼", func(): main.toggle_gear()], ["flapup", "襟翼 收", func(): main.flaps_step(-1)], ["flapdn", "襟翼 放", func(): main.flaps_step(1)],
			["spl", "減速板", func(): main.plane.spoilers = not main.plane.spoilers], ["rev", "反推力", func(): main.plane.reverse = not main.plane.reverse],
			["park", "停機煞車", func(): main.plane.parking = not main.plane.parking], ["ap", "自動駕駛", func(): main.toggle_ap()], ["time", "時間 1×", func(): main.cycle_time()]]:
		var b := _btn(it[1], it[2], false, 14)
		b.custom_minimum_size = Vector2(112, 33)
		b.add_theme_font_size_override("font_size", 13)
		col.add_child(b)
		btns[it[0]] = b
	var brake := Button.new()
	brake.text = "煞車（按住）"
	brake.focus_mode = Control.FOCUS_NONE
	brake.add_theme_font_size_override("font_size", 13)
	brake.add_theme_stylebox_override("normal", _sb(Color(0.55, 0.2, 0.18), 8, 8))
	brake.add_theme_stylebox_override("pressed", _sb(Color(0.85, 0.3, 0.25), 8, 8))
	brake.add_theme_stylebox_override("hover", _sb(Color(0.62, 0.24, 0.2), 8, 8))
	brake.custom_minimum_size = Vector2(108, 40)
	brake.button_down.connect(func(): brake_held = true)
	brake.button_up.connect(func(): brake_held = false)
	col.add_child(brake)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	rh.add_child(tv)
	tv.add_child(_lbl("油門", 14, ACC))
	throttle_slider = VSlider.new()
	throttle_slider.min_value = 0.0
	throttle_slider.max_value = 1.0
	throttle_slider.step = 0.01
	throttle_slider.custom_minimum_size = Vector2(60, 250)
	throttle_slider.focus_mode = Control.FOCUS_NONE
	var grab := _sb(ACC, 6, 14)
	throttle_slider.add_theme_stylebox_override("slider", _sb(Color(0.15, 0.17, 0.22), 6, 10))
	throttle_slider.add_theme_stylebox_override("grabber_area", _sb(Color(0.3, 0.75, 0.45), 6, 10))
	throttle_slider.add_theme_stylebox_override("grabber_area_highlight", _sb(Color(0.35, 0.85, 0.5), 6, 10))
	throttle_slider.add_theme_icon_override("grabber", _grab_icon())
	throttle_slider.add_theme_icon_override("grabber_highlight", _grab_icon())
	throttle_slider.value_changed.connect(func(x):
		if not main.plane.ap_on or absf(x - main.plane.throttle) > 0.02:
			if main.plane.ap_on and absf(x - main.plane.throttle) > 0.08:
				main.plane.ap_disengage()
			main.plane.throttle = x)
	tv.add_child(throttle_slider)
	n1_lbl = _lbl("N1 0%", 13)
	tv.add_child(n1_lbl)
	# 下方資訊列
	info_lbl = _lbl("", 13, TXT)
	info_lbl.add_theme_constant_override("outline_size", 5)
	info_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	info_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	info_lbl.position = Vector2(-310, -240)
	game_box.add_child(info_lbl)
	# 中央警示
	alert_lbl = _lbl("", 26, ACC)
	alert_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	alert_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	alert_lbl.position.y = -90
	alert_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alert_lbl.add_theme_constant_override("outline_size", 8)
	alert_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	alert_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_box.add_child(alert_lbl)
	divert_box = _panel(BG2, 10, 10)
	divert_box.visible = false
	divert_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	divert_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	divert_box.position = Vector2(-560, -40)
	game_box.add_child(divert_box)

func _grab_icon() -> Texture2D:
	var img := Image.create(56, 26, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(3, 23):
		for x in range(2, 54):
			img.set_pixel(x, y, Color(0.95, 0.65, 0.2) if (y > 11 and y < 15) or y < 6 or y > 19 else Color(0.85, 0.87, 0.9))
	return ImageTexture.create_from_image(img)

func _build_pad() -> void:
	var pad := Control.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	pad.position = Vector2(20, -190)
	pad.size = Vector2(170, 170)
	game_box.add_child(pad)
	var dirs := [["▲\n爬升", Vector2(0, 1), Vector2(55, 0)], ["▼\n下降", Vector2(0, -1), Vector2(55, 116)], ["◀\n左", Vector2(-1, 0), Vector2(0, 58)], ["▶\n右", Vector2(1, 0), Vector2(110, 58)]]
	for d in dirs:
		var b := Button.new()
		b.text = d[0]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_stylebox_override("normal", _sb(Color(0.12, 0.3, 0.6, 0.85), 30, 4))
		b.add_theme_stylebox_override("pressed", _sb(Color(0.95, 0.6, 0.2, 0.95), 30, 4))
		b.add_theme_stylebox_override("hover", _sb(Color(0.16, 0.36, 0.7, 0.9), 30, 4))
		b.size = Vector2(58, 56)
		b.position = d[2]
		var dv: Vector2 = d[1]
		b.button_down.connect(func(): pad_vec += dv)
		b.button_up.connect(func(): pad_vec -= dv)
		pad.add_child(b)

var _yoke_drag := false
func _yoke_input(e: InputEvent) -> void:
	var c := yoke.size * 0.5
	var r := yoke.size.x * 0.42
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_yoke_drag = mb.pressed
			if mb.pressed:
				yoke_vec = ((mb.position - c) / r).limit_length(1.0)
			else:
				yoke_vec = Vector2.ZERO
	elif e is InputEventMouseMotion and _yoke_drag:
		yoke_vec = (((e as InputEventMouseMotion).position - c) / r).limit_length(1.0)
	elif e is InputEventScreenTouch:
		var st := e as InputEventScreenTouch
		_yoke_drag = st.pressed
		yoke_vec = ((st.position - c) / r).limit_length(1.0) if st.pressed else Vector2.ZERO
	elif e is InputEventScreenDrag:
		yoke_vec = (((e as InputEventScreenDrag).position - c) / r).limit_length(1.0)
	yoke.queue_redraw()

func _yoke_draw() -> void:
	var c := yoke.size * 0.5
	var r := yoke.size.x * 0.42
	yoke.draw_circle(c, r + 8, Color(0.05, 0.08, 0.14, 0.55))
	yoke.draw_arc(c, r + 8, 0, TAU, 40, Color(1, 1, 1, 0.25), 2.0)
	var p := c + yoke_vec * r
	# 操縱桿造型：中柱＋雙握把
	yoke.draw_line(c + Vector2(0, 30), p, Color(0.2, 0.22, 0.26), 10.0)
	var bank := yoke_vec.x * 0.6
	var xf := Transform2D(bank, p)
	var pts := PackedVector2Array([Vector2(-46, -6), Vector2(46, -6), Vector2(46, 20), Vector2(34, 20), Vector2(30, 4), Vector2(-30, 4), Vector2(-34, 20), Vector2(-46, 20)])
	var q := PackedVector2Array()
	for v in pts:
		q.append(xf * v)
	yoke.draw_colored_polygon(q, Color(0.16, 0.17, 0.2))
	yoke.draw_circle(p, 13, Color(0.22, 0.24, 0.28))
	yoke.draw_circle(p, 9, Color(0.3, 0.85, 0.45))
	yoke.draw_string(M.font_bold, Vector2(0, yoke.size.y + 4), "操縱桿：拖曳控制", HORIZONTAL_ALIGNMENT_CENTER, yoke.size.x, 12, DIM)

func stick() -> Vector2:
	# x：坡度（右＋）、y：俯仰（抬頭＋）
	var y := yoke_vec.y + pad_vec.y
	var x := yoke_vec.x + pad_vec.x
	return Vector2(clampf(x, -1, 1), clampf(y, -1, 1))

func show_game() -> void:
	if title_box:
		title_box.queue_free()
		title_box = null
	game_box.visible = true
	for k in event_panels:
		(event_panels[k] as Node).queue_free()
	event_panels.clear()
	show_cabin(false)
	open_map(false)
	divert_box.visible = false
	xk_panel.visible = false
	show_checklist(false)
	seatbelt = false
	squawk = "2000"
	_clear(xk_log)
	xk_log.text = ""
	minimap.plane = main.plane
	minimap.terrain = main.world.terrain
	pfd.plane = main.plane
	if update_bar.get_parent() == null:
		root.add_child(update_bar)
	_check_portrait()

func _process(delta: float) -> void:
	if _sub_hide > 0.0:
		_sub_hide -= delta
		if _sub_hide <= 0.0 and sub_panel:
			sub_panel.visible = false
			sub_portrait.talking = false
	_clock_t -= delta
	if _clock_t <= 0.0:
		_clock_t = 1.0
		var c := clock_text()
		if clock_lbl:
			clock_lbl.text = "[center]" + clock_short() + "[/center]"
		if title_clock and is_instance_valid(title_clock):
			title_clock.text = c
	if _alert_t > 0.0:
		_alert_t -= delta
		alert_lbl.modulate.a = clampf(_alert_t, 0.0, 1.0)
	if game_box == null or not game_box.visible or main.plane == null:
		return
	var vps := root.get_viewport_rect().size
	if vps != _last_vp:
		_last_vp = vps
		_layout()
	var p: Aircraft = main.plane
	xk_portrait.talking = Snd.voice.playing and sub_portrait.who == "xiaoke"
	if not throttle_slider.has_focus():
		throttle_slider.set_value_no_signal(p.throttle)
	n1_lbl.text = "N1 %d%%" % int(p.n1 * 100.0)
	(btns.gear as Button).text = "起落架 ▼" if p.gear_down else "起落架 ▲"
	_toggle_style(btns.gear, p.gear_down)
	(btns.flapup as Button).text = "襟翼 收（%d）" % p.flaps
	(btns.flapdn as Button).text = "襟翼 放（%d）" % p.flaps
	_toggle_style(btns.spl, p.spoilers, Color(0.75, 0.5, 0.15))
	_toggle_style(btns.rev, p.reverse, Color(0.75, 0.5, 0.15))
	_toggle_style(btns.park, p.parking, Color(0.65, 0.22, 0.2))
	_toggle_style(btns.ap, p.ap_on)
	(btns.time as Button).text = "時間 %d×" % int(main.time_mult)
	mission_lbl.text = main.mission_text()
	var flapdeg: float = Aircraft.FLAP_DEG[p.flaps]
	info_lbl.text = "襟翼 %d°　燃油 %s 公斤　%s%s　應答機 %s　%s" % [int(flapdeg), G.fmt_int(int(p.fuel)), "防冰開 " if p.anti_ice else "", ("結冰 %d%% " % int(p.ice * 100)) if p.ice > 0.02 else "", squawk, "安全帶燈亮" if seatbelt else ""]
	pfd.target_hdg = main.target_hdg()
	var rw: Dictionary = main.dest_rw
	if not rw.is_empty() and main.dist_to_dest() < 20000.0:
		pfd.ils = p.ils_dev(rw)
		if absf(pfd.ils.x) > 12.0:
			pfd.ils = Vector2(99, 99)
	else:
		pfd.ils = Vector2(99, 99)
	if check_panel.visible:
		_update_checklist(p)
	minimap.route = main.route_points()
	minimap.dest_id = main.dest_id
	minimap.closed = main.director.closed
	minimap.storms = main.director.storms
	yoke.queue_redraw()

func _layout() -> void:
	var vs := root.get_viewport_rect().size
	if sub_panel:
		sub_panel.position.x = clampf(vs.x * 0.5 - 170.0, 470.0, vs.x - 330.0 - 494.0)
	if right_panel:
		right_panel.reset_size()
		right_panel.position = vs - right_panel.size - Vector2(10, 10)
	if not map_big:
		open_map(false)

var _clock_t := 0.0
func clock_text() -> String:
	var u := Time.get_unix_time_from_system() + int(Time.get_time_zone_from_system().get("bias", 480)) * 60
	var d := Time.get_datetime_dict_from_unix_time(int(u))
	var wd: String = ["日", "一", "二", "三", "四", "五", "六"][int(d.weekday)]
	return "當地時間 %d/%d/%d（%s）%02d:%02d:%02d" % [d.year, d.month, d.day, wd, d.hour, d.minute, d.second]

func clock_short() -> String:
	var u := Time.get_unix_time_from_system() + int(Time.get_time_zone_from_system().get("bias", 480)) * 60
	var d := Time.get_datetime_dict_from_unix_time(int(u))
	var wd: String = ["日", "一", "二", "三", "四", "五", "六"][int(d.weekday)]
	return "當地時間
%d/%d（%s）
%02d:%02d:%02d" % [d.month, d.day, wd, d.hour, d.minute, d.second]

# ── 字幕與提示 ──
func _on_line(_id: String, speaker: String, text: String) -> void:
	if sub_panel == null:
		return
	sub_panel.visible = game_box != null and game_box.visible
	sub_portrait.who = speaker
	sub_portrait.talking = true
	sub_name.text = Texts.SPEAKERS.get(speaker, [speaker])[0]
	sub_text.text = text
	_sub_hide = 0.0
	if speaker == "xiaoke":
		add_chat("xiaoke", text)

func alert(t: String, secs := 3.0) -> void:
	if alert_lbl == null:
		return
	alert_lbl.text = t
	alert_lbl.modulate.a = 1.0
	_alert_t = secs

# ── 小柯對話視窗 ──
func _build_xk_panel() -> void:
	xk_panel = _panel(BG2, 12, 10)
	xk_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	xk_panel.position = Vector2(-590, 186)
	xk_panel.custom_minimum_size = Vector2(360, 0)
	xk_panel.visible = false
	game_box.add_child(xk_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	xk_panel.add_child(v)
	var hd := HBoxContainer.new()
	v.add_child(hd)
	var tt := _lbl("小柯 AI 助理", 18, ACC)
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hd.add_child(tt)
	var cb := _btn("×", func(): xk_panel.visible = false, false, 13)
	cb.custom_minimum_size = Vector2(32, 30)
	hd.add_child(cb)
	xk_log = RichTextLabel.new()
	xk_log.bbcode_enabled = true
	xk_log.scroll_following = true
	xk_log.custom_minimum_size = Vector2(340, 170)
	xk_log.add_theme_font_size_override("normal_font_size", 14)
	xk_log.add_theme_font_size_override("bold_font_size", 14)
	v.add_child(xk_log)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for q in [["聯絡塔台", "聯絡塔台"], ["最近機場", "最近的機場在哪"], ["目的地天氣", "目的地天氣"], ["自動駕駛", "自動駕駛"], ["打開地圖", "打開地圖"], ["客艙畫面", "看客艙乘客"]]:
		var text: String = q[1]
		var b := _btn(q[0], func(): main.xiaoke.ask(text), false, 13)
		b.custom_minimum_size = Vector2(110, 32)
		grid.add_child(b)
	var ih := HBoxContainer.new()
	ih.add_theme_constant_override("separation", 4)
	v.add_child(ih)
	xk_input = LineEdit.new()
	xk_input.placeholder_text = "打字問小柯……"
	xk_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xk_input.text_submitted.connect(func(t): _send_chat())
	ih.add_child(xk_input)
	var sb := _btn("送出", _send_chat, true, 14)
	sb.custom_minimum_size = Vector2(56, 36)
	ih.add_child(sb)
	mic_btn = _btn("麥克風", func(): main.xiaoke.listen(), false, 14, Color(0.2, 0.45, 0.75))
	mic_btn.custom_minimum_size = Vector2(80, 36)
	ih.add_child(mic_btn)

func toggle_xk(force := -1) -> void:
	xk_panel.visible = (not xk_panel.visible) if force < 0 else force == 1
	if xk_panel.visible:
		Snd.play("ding", 0.6)

func _send_chat() -> void:
	var t := xk_input.text.strip_edges()
	if t == "":
		return
	xk_input.text = ""
	main.xiaoke.ask(t)

func add_chat(who: String, text: String) -> void:
	if xk_log == null:
		return
	var nm := "小柯" if who == "xiaoke" else "機長"
	var col := "#ffb347" if who == "xiaoke" else "#7fd0ff"
	xk_log.append_text("[color=%s][b]%s：[/b][/color]%s\n" % [col, nm, text])

func set_listening(on: bool) -> void:
	mic_btn.text = "● 聆聽中" if on else "麥克風"

# ── 地圖 ──
func open_map(big: bool) -> void:
	map_big = big
	minimap.big = big
	if big:
		map_holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		var vs := root.get_viewport_rect().size
		var hgt := minf(vs.y - 120.0, 640.0)
		minimap.custom_minimum_size = Vector2(hgt * 0.72, hgt)
		map_holder.size = minimap.custom_minimum_size + Vector2(6, 6)
		map_holder.position = (vs - map_holder.size) * 0.5
	else:
		minimap.custom_minimum_size = Vector2(210, 170)
		map_holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		map_holder.size = Vector2(216, 176)
		map_holder.position = Vector2(root.get_viewport_rect().size.x - 222, 40)

func _map_airport(id: String) -> void:
	var a := G.airport(id)
	show_dialog("改降 %s？" % a.name, "把目的地改成 %s。自動駕駛會重新規劃航線。" % a.name, [["改降這裡", func(): main.divert(id), true], ["取消", func(): pass, false]])

func offer_divert(lst: Array) -> void:
	_clear(divert_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	divert_box.add_child(v)
	v.add_child(_lbl("最近的機場", 16, ACC))
	for i in mini(3, lst.size()):
		var n: Dictionary = lst[i]
		var id: String = n.a.id
		var b := _btn("%s　%.1f 公里　%03d°%s" % [n.a.short, n.dist / 1000.0, int(n.brg), "（關閉）" if n.closed else ""], func(): main.divert(id); divert_box.visible = false, false, 14)
		b.disabled = n.closed
		v.add_child(b)
	v.add_child(_btn("關閉", func(): divert_box.visible = false, false, 13))
	divert_box.visible = true

func show_checklist(on: bool) -> void:
	if check_panel:
		check_panel.visible = on

func _update_checklist(p: Aircraft) -> void:
	var rw: Dictionary = main.dest_rw
	var dev := p.ils_dev(rw) if not rw.is_empty() else Vector2.ZERO
	var kt := p.ias * G.MS2KT
	var items := [
		["安全帶指示燈", seatbelt],
		["落地燈", p.lights_on],
		["起落架放下（三綠燈）", p.gear_pos > 0.98],
		["襟翼 30°", p.flaps == 3],
		["速度 130～155 節", kt > 130.0 and kt < 155.0],
		["對準跑道中心線", absf(dev.x) < 1.0],
		["在 3° 下滑道上", absf(dev.y) < 0.5],
		["減速板收起（落地後再開）", not p.spoilers or p.on_ground],
	]
	var t := ""
	for it in items:
		t += ("[color=#7fe08a]● [/color]" if it[1] else "[color=#ff8a70]○ [/color]") + String(it[0]) + "
"
	check_lbl.text = t.strip_edges()

# ── 客艙 ──
func show_cabin(on: bool) -> void:
	cabin_panel.visible = on

func _cabin_talk() -> void:
	var opts: Array = []
	for ev in main.director.events:
		for a in ev.actions:
			if a.id in ["talk", "talk_calm"]:
				var e: Dictionary = ev
				var aid: String = a.id
				opts.append([a.label, func(): main.director.do_action(e, aid), false])
	if opts.is_empty():
		Snd.say("f_welcome")
		alert("乘客們都很好，正在享受飛行", 2.0)
		return
	opts.append(["關閉", func(): pass, false])
	show_dialog("跟客艙說話", "選擇要說的話：", opts, 420)

# ── 事件面板 ──
func show_event(ev: Dictionary) -> void:
	var p: PanelContainer = event_panels.get(ev.id, null)
	if p == null:
		p = _panel(Color(0.25, 0.08, 0.08, 0.9) if ev.id in ["cardiac", "hijack"] else Color(0.18, 0.12, 0.05, 0.9), 10, 10)
		p.custom_minimum_size = Vector2(310, 0)
		p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		event_box.add_child(p)
		event_panels[ev.id] = p
		Snd.play("caution", 0.6)
		alert("突發狀況：" + ev.title)
	_clear(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var st: String = {"active": "處理中", "resolved": "已解決", "failed": "失敗"}[ev.status]
	v.add_child(_lbl("！%s（%s）" % [ev.title, st], 17, ACC if ev.status == "active" else (GOOD if ev.status == "resolved" else BAD)))
	if ev.meter >= 0.0:
		var bar := ProgressBar.new()
		bar.name = "Bar"
		bar.min_value = 0
		bar.max_value = 100
		bar.value = ev.meter
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(210, 16)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var good: bool = (ev.meter < 60.0) if ev.bad_high else (ev.meter > 40.0)
		bar.add_theme_stylebox_override("fill", _sb(GOOD if good else BAD, 4, 0))
		bar.add_theme_stylebox_override("background", _sb(Color(0.15, 0.15, 0.18), 4, 0))
		var hb := HBoxContainer.new()
		hb.add_child(_lbl(ev.meter_name, 13))
		hb.add_child(bar)
		v.add_child(hb)
	if ev.note != "":
		var n := _lbl(ev.note, 13, DIM)
		n.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		n.custom_minimum_size.x = 280
		v.add_child(n)
	if ev.status == "active":
		var g := HFlowContainer.new()
		g.add_theme_constant_override("h_separation", 4)
		g.add_theme_constant_override("v_separation", 4)
		g.custom_minimum_size.x = 290
		g.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(g)
		for a in ev.actions:
			var aid: String = a.id
			var e := ev
			var b := _btn(("已" if a.done and a.once else "") + a.label, func(): main.director.do_action(e, aid), false, 13, Color(0.35, 0.22, 0.12))
			b.custom_minimum_size = Vector2(0, 30)
			b.add_theme_stylebox_override("normal", _sb(Color(0.35, 0.22, 0.12), 8, 7))
			b.add_theme_stylebox_override("hover", _sb(Color(0.45, 0.3, 0.16), 8, 7))
			b.disabled = a.done and a.once
			g.add_child(b)

func refresh_events() -> void:
	for ev in main.director.events:
		var p: PanelContainer = event_panels.get(ev.id, null)
		if p == null:
			continue
		var bar := p.find_child("Bar", true, false) as ProgressBar
		if bar:
			bar.value = ev.meter
			var good: bool = (ev.meter < 60.0) if ev.bad_high else (ev.meter > 40.0)
			bar.add_theme_stylebox_override("fill", _sb(GOOD if good else BAD, 4, 0))

# ── 截圖 ──
func screenshot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var buf := img.save_png_to_buffer()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(buf, "小柯飛行截圖_%d.png" % Time.get_unix_time_from_system(), "image/png")
	else:
		var path := "user://screenshot_%d.png" % Time.get_unix_time_from_system()
		img.save_png(path)
		alert("截圖已存到 " + ProjectSettings.globalize_path(path), 3.0)
	Snd.play("click")

# iOS 版沒有「建立捷徑」，說明頁也拿掉那一頁
func _help() -> Array:
	if G.is_ios():
		return Texts.HELP.filter(func(e): return e[1] != "install")
	return Texts.HELP

# ══════════════ 對話框 ══════════════
func _modal(title: String, width := 460) -> VBoxContainer:
	close_modal()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(cc)
	var p := _panel(BG2, 16, 18)
	p.custom_minimum_size.x = width
	cc.add_child(p)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	p.add_child(outer)
	outer.add_child(_lbl(title, 22, ACC))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(sc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	_fit_scroll(sc, v)
	modal.set_meta("outer", outer)
	return v

func _modal_buttons(v: VBoxContainer, buttons: Array) -> void:
	var outer: VBoxContainer = modal.get_meta("outer")
	var h := HFlowContainer.new()
	h.alignment = FlowContainer.ALIGNMENT_END
	h.add_theme_constant_override("h_separation", 8)
	outer.add_child(h)
	var m := modal
	for b in buttons:
		var cb: Callable = b[1]
		h.add_child(_btn(b[0], func():
			if modal == m:
				close_modal()
			cb.call(), bool(b[2])))

func _fit_scroll(sc: ScrollContainer, content: Control, reserve := 200.0) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(sc) or not is_instance_valid(content):
		return
	var vp_h := root.get_viewport_rect().size.y
	sc.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, maxf(140.0, vp_h - reserve))

func show_dialog(title: String, body: String, buttons: Array, width := 460) -> VBoxContainer:
	var v := _modal(title, width)
	if body != "":
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		rt.text = body
		rt.custom_minimum_size = Vector2(width - 50, 0)
		rt.add_theme_font_size_override("normal_font_size", 16)
		rt.add_theme_font_size_override("bold_font_size", 17)
		v.add_child(rt)
	_modal_buttons(v, buttons)
	return v

func close_modal() -> void:
	if _help_page >= 0:
		Snd.voice.stop()
		_help_page = -1
	if modal:
		modal.queue_free()
		modal = null

func has_modal() -> bool:
	return modal != null

# ── 遊戲說明（語音＋文字＋動畫）──
func show_help(page := 0) -> void:
	var was := _help_page
	close_modal()
	_help_page = page
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(cc)
	var p := _panel(BG2, 16, 16)
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var tt := _lbl("遊戲說明", 22, ACC)
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tt)
	_voice_btn = _btn("■ 停止朗讀" if Snd.voice.playing else "▶ 播放語音", func(): _toggle_help_voice(page), true, 14)
	_voice_btn.custom_minimum_size = Vector2(120, 34)
	top.add_child(_voice_btn)
	var ac := CheckBox.new()
	ac.text = "自動朗讀"
	ac.button_pressed = Snd.auto_voice
	ac.focus_mode = Control.FOCUS_NONE
	ac.toggled.connect(func(on): Snd.auto_voice = on; Snd.save_settings())
	top.add_child(ac)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	var area_h := minf(440.0, maxf(180.0, root.get_viewport_rect().size.y - 200.0))
	var tsc := ScrollContainer.new()
	tsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tsc.custom_minimum_size = Vector2(150, area_h)
	h.add_child(tsc)
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	tsc.add_child(tabs)
	var sel: Button = null
	for i in _help().size():
		var ii := i
		var b := _btn(_help()[i][0], func(): show_help(ii), i == page, 14)
		b.custom_minimum_size = Vector2(136, 32)
		tabs.add_child(b)
		if i == page:
			sel = b
	if sel:
		tsc.ensure_control_visible.call_deferred(sel)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(540, area_h)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(sc)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 8)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(tv)
	tv.add_child(_lbl(_help()[page][0], 20))
	var anim := HelpAnim.new()
	anim.kind = _help()[page][1]
	anim.custom_minimum_size = Vector2(520, 180)
	tv.add_child(anim)
	var body := _lbl(_help()[page][2], 15)
	body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	body.custom_minimum_size.x = 515
	tv.add_child(body)
	var bh := HBoxContainer.new()
	bh.alignment = BoxContainer.ALIGNMENT_END
	bh.add_theme_constant_override("separation", 8)
	v.add_child(bh)
	if page > 0:
		bh.add_child(_btn("上一頁", func(): show_help(page - 1), false, 15))
	if page < _help().size() - 1:
		bh.add_child(_btn("下一頁", func(): show_help(page + 1), false, 15))
	bh.add_child(_btn("關閉", func(): close_modal(), true, 15))
	if Snd.auto_voice and (was != page or not Snd.voice.playing):
		_play_help(page)

func _play_help(page: int) -> void:
	var path := "res://assets/voice/help_%02d.ogg" % page
	Snd.clear_queue()
	if ResourceLoader.exists(path):
		Snd.voice.stream = load(path)
		Snd.voice.volume_db = linear_to_db(maxf(Snd.voice_vol, 0.001))
		Snd.voice.play()
	if _voice_btn:
		_voice_btn.text = "■ 停止朗讀"

func _toggle_help_voice(page: int) -> void:
	if Snd.voice.playing:
		Snd.voice.stop()
		_voice_btn.text = "▶ 播放語音"
	else:
		_play_help(page)

# ── 結算 ──
func show_result(r: Dictionary) -> void:
	var s := ""
	if r.crash != "":
		s += "[color=#ff6b60][b]事故：%s[/b][/color]\n\n" % r.crash
	else:
		s += "落地下降率：[b]%d[/b] 英尺／分（%s）\n" % [r.fpm, r.land_word]
		s += "偏離中心線：[b]%.1f[/b] 公尺\n" % r.center
		s += "落地機場：[b]%s[/b]\n" % r.apt
	for e in r.events:
		s += "%s %s：%s（%+d 分）\n" % ["[color=#7fe08a]成功[/color]" if e.ok else "[color=#ff6b60]失敗[/color]", e.title, e.note, e.pts]
	s += "\n總分：[b]%d[/b]　%s" % [r.score, "★".repeat(r.stars) + "☆".repeat(3 - r.stars)]
	var btns_a: Array = []
	if r.stars > 0 and r.level >= 0 and r.level + 1 < G.LEVELS.size():
		btns_a.append(["下一關", func(): main.start_level(r.level + 1), true])
	btns_a.append(["再飛一次", func(): main.restart_flight(), r.stars == 0])
	btns_a.append(["回主選單", func(): main.to_title(), false])
	show_dialog("任務完成！" if r.stars > 0 else "任務失敗", s, btns_a, 520)

# ── 設定 ──
func show_settings() -> void:
	var v := _modal("設定", 500)
	for it in [["音樂音量", Snd.music_vol, func(x): Snd.music_vol = x; Snd._apply()], ["音效音量", Snd.sfx_vol, func(x): Snd.sfx_vol = x], ["語音音量", Snd.voice_vol, func(x): Snd.voice_vol = x]]:
		var h := HBoxContainer.new()
		var l := _lbl(it[0], 16)
		l.custom_minimum_size.x = 110
		h.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = it[1]
		s.custom_minimum_size = Vector2(280, 32)
		var cb: Callable = it[2]
		s.value_changed.connect(func(x): cb.call(x))
		h.add_child(s)
		v.add_child(h)
	var qh := HBoxContainer.new()
	var ql := _lbl("畫面品質", 16)
	ql.custom_minimum_size.x = 110
	qh.add_child(ql)
	var qo := OptionButton.new()
	qo.focus_mode = Control.FOCUS_NONE
	for q in ["低（手機）", "中", "高"]:
		qo.add_item(q)
	qo.select(G.quality)
	qo.item_selected.connect(func(i): G.quality = i; G.save_progress(); alert("畫面品質會在重新整理網頁後生效" if OS.has_feature("web") else "畫面品質會在重新開啟遊戲後生效", 3.0))
	qh.add_child(qo)
	v.add_child(qh)
	for it in [["俯仰反向（往上推＝抬頭）", G.invert_pitch, func(on): G.invert_pitch = on], ["說明頁自動朗讀", Snd.auto_voice, func(on): Snd.auto_voice = on], ["小柯用系統語音朗讀即時資訊", Snd.tts_on, func(on): Snd.tts_on = on]]:
		var c := CheckBox.new()
		c.text = it[0]
		c.button_pressed = it[1]
		c.focus_mode = Control.FOCUS_NONE
		var cb: Callable = it[2]
		c.toggled.connect(func(on): cb.call(on))
		v.add_child(c)
	v.add_child(_lbl("ChatGPT 金鑰（選填，讓小柯回答更多問題）", 15, ACC))
	var key := LineEdit.new()
	key.secret = true
	key.placeholder_text = "sk-……（只存在這個瀏覽器）" if OS.has_feature("web") else "sk-……（只存在這台裝置）"
	key.text = G.api_key
	key.custom_minimum_size.x = 440
	v.add_child(key)
	var mo := LineEdit.new()
	mo.text = G.ai_model
	mo.placeholder_text = "模型名稱"
	v.add_child(mo)
	var tts := _lbl("系統語音：" + ("已找到臺灣華語聲音" if Snd.has_tts() else "這台裝置沒有臺灣華語系統聲音（固定台詞仍有語音）"), 13, DIM)
	tts.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	tts.custom_minimum_size.x = 440
	v.add_child(tts)
	var note := _lbl("填入金鑰後，你問小柯的話和目前飛行狀態會直接傳送到 OpenAI 產生回答；不填金鑰則只用內建回答，不會連網。", 13, DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	note.custom_minimum_size.x = 440
	v.add_child(note)
	_modal_buttons(v, [["儲存", func():
		var k := key.text.strip_edges()
		G.ai_model = mo.text.strip_edges() if mo.text.strip_edges() != "" else "gpt-5.4-mini"
		Snd.save_settings()
		if k == "" or (k == G.api_key and G.ai_consent):
			G.api_key = k
			G.save_progress()
			return
		show_dialog("使用 ChatGPT 前請確認", "啟用後，你在小柯對話框輸入的文字，以及目前的飛行狀態（高度、速度、目的地、天氣、機上狀況），會用你自己的金鑰傳送到 [b]OpenAI[/b] 產生回答。

小柯機器人不會收集或保存這些內容；OpenAI 如何處理資料請參考 OpenAI 的隱私權政策。

你可以隨時在設定裡清空金鑰來停用。", [["同意並啟用", func():
			G.api_key = k
			G.ai_consent = true
			G.save_progress()
			alert("已啟用 ChatGPT 回答", 2.5), true], ["不要", func():
			G.api_key = ""
			G.ai_consent = false
			G.save_progress(), false]], 520), true]])

func show_changelog() -> void:
	var s := "目前版本：[b]v%s[/b]\n" % G.APP_VERSION
	if Updater.latest != "":
		s += "[color=#7fe08a]有新版本 v%s 可以更新！[/color]\n" % Updater.latest
	for e in Texts.CHANGELOG:
		s += "\n[b]v%s[/b]　%s\n%s\n" % [e[0], e[1], e[2]]
	var b: Array = [["關閉", func(): pass, true]]
	if G.is_ios():
		s += "
[color=#9fb3c8]新版本會透過 App Store 自動更新。[/color]"
	elif Updater.latest != "":
		b.push_front(["立即更新", func(): Updater.apply(), true])
	else:
		b.push_front(["檢查更新", func(): Updater.check(), false])
	show_dialog("更新紀錄", s, b, 540)

func show_install() -> void:
	match Updater.install_state():
		"prompt":
			Updater.install_prompt()
		"installed":
			show_dialog("建立捷徑", "你現在就是從捷徑開啟的，已經安裝好了！", [["好", func(): pass, true]])
		"ios":
			show_dialog("建立捷徑（iPhone／iPad）", "用 [b]Safari[/b] 開啟這個網頁，然後：\n\n① 點「分享」按鈕（方框加向上箭頭）\n② 往下滑，點「[b]加入主畫面[/b]」\n③ 右上角按「新增」\n\n主畫面就會出現小柯機長的圖示，點它就能全螢幕飛行。", [["知道了", func(): pass, true]], 500)
		"android":
			show_dialog("建立捷徑（Android）", "用 [b]Chrome[/b] 開啟這個網頁，然後：\n\n① 點右上角的選單（三個點）\n② 點「[b]加到主畫面[/b]」或「[b]安裝應用程式[/b]」\n③ 按「安裝」", [["知道了", func(): pass, true]], 500)
		"desktop":
			show_dialog("建立捷徑", "線上版網址：%s\n用 Chrome 或 Edge 開啟後可以安裝成應用程式。" % Updater.SITE, [["開啟網站", func(): OS.shell_open(Updater.SITE), true], ["關閉", func(): pass, false]], 500)
		_:
			show_dialog("建立捷徑（電腦）", "用 [b]Chrome[/b] 或 [b]Edge[/b] 開啟這個網頁，然後：\n\n① 點網址列右邊的「安裝」小圖示\n　或右上角選單 →「投放、儲存與分享」→「[b]安裝網頁為應用程式[/b]」\n② 按「安裝」\n\n桌面和開始選單就會出現小柯真實飛行的捷徑。", [["知道了", func(): pass, true]], 520)

func _on_update(v: String, notes: String) -> void:
	_clear(update_bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	update_bar.add_child(h)
	h.add_child(_lbl("有新版本 v%s%s" % [v, ("：" + notes) if notes != "" else ""], 15))
	h.add_child(_btn("立即更新", func(): Updater.apply(), true, 14))
	h.add_child(_btn("稍後", func(): update_bar.visible = false, false, 14))
	update_bar.visible = true
	if update_bar.get_parent() == null:
		root.add_child(update_bar)
	root.move_child(update_bar, root.get_child_count() - 1)

func pause_menu() -> void:
	var b: Array = [["繼續飛行", func(): main.toggle_pause(), true], ["重新開始", func(): main.restart_flight(), false], ["遊戲說明", func(): show_help(0), false], ["設定", show_settings, false], ["全螢幕", func(): G.go_fullscreen(), false], ["回主選單", func(): main.to_title(), false]]
	if G.is_ios():
		b = b.filter(func(e): return e[0] != "全螢幕")
	show_dialog("暫停", "", b, 460)
