extends Node3D
## 主流程：標題畫面、任務設定、輸入、聲音、提示、落地與結算、測試旗標。

var world: World
var plane: Aircraft
var cam: FlightCam
var hud: Hud
var director: Director
var xiaoke: Xiaoke
var cabin: CabinView
var flight: Dictionary = {}
var level := -1
var dest_id := ""
var dest_rw: Dictionary = {}
var dep_rw: Dictionary = {}
var from_pos := Vector3.ZERO
var total_dist := 1.0
var time_mult := 1.0
var paused := false
var state := "boot"
var _said: Dictionary = {}
var _warn_prev := ""
var _warn_cd := 0.0
var _t := 0.0
var _land := {}
var _smoke: CPUParticles3D
var _shots: Array = []
var _quit_t := -1.0
var _loading: Label
var _manual_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	M.init_fonts()
	if G.is_touch():
		# 手機螢幕小：介面放大一點
		get_window().content_scale_size = Vector2i(1120, 630)
	hud = Hud.new()
	hud.main = self
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	# 載入畫面
	_loading = Label.new()
	_loading.text = "小柯機器人3D真實飛行\n正在建立臺灣地形……"
	_loading.add_theme_font_override("font", M.font_bold)
	_loading.add_theme_font_size_override("font_size", 30)
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_loading.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading.grow_vertical = Control.GROW_DIRECTION_BOTH
	hud.root.add_child(_loading)
	await get_tree().process_frame
	await get_tree().process_frame
	world = World.new()
	add_child(world)
	world.setup("day", "clear", G.quality)
	plane = Aircraft.new()
	add_child(plane)
	plane.setup(world)
	cam = FlightCam.new()
	cam.target = plane
	add_child(cam)
	cam.build_cockpit(plane.model)
	hud.build_game()
	cabin = hud.cabin_view
	director = Director.new()
	add_child(director)
	director.changed.connect(func(): hud.refresh_events())
	director.divert_requested.connect(divert)
	xiaoke = Xiaoke.new()
	xiaoke.main = self
	xiaoke.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(xiaoke)
	xiaoke.chat.connect(func(w, t): if w != "xiaoke" or not Snd.busy(): hud.add_chat(w, t))
	xiaoke.listening.connect(func(on): hud.set_listening(on))
	Snd.line_started.connect(_on_line)
	plane.touchdown.connect(_on_touchdown)
	plane.crashed.connect(_on_crash)
	plane.callout.connect(_on_callout)
	plane.stopped_on_runway.connect(_on_stopped)
	plane.ap_changed.connect(func(on): if not on and state == "flying": Snd.play("caution", 0.5); hud.alert("自動駕駛解除", 1.5))
	_loading.queue_free()
	if G.args.has("level"):
		start_level(int(G.arg("level")) - 1)
	elif G.args.has("free"):
		var f := G.arg("free").split(",")
		start_flight({"title": "自由飛行", "from": f[0], "to": f[1] if f.size() > 1 else "", "mode": "route", "time": G.arg("time", "day"), "weather": G.arg("weather", "clear"), "events": Array(G.arg("events", "").split(",", false))}, -1)
	else:
		to_title()
	_test_setup()

# ── 標題 ──
func to_title() -> void:
	get_tree().paused = false
	paused = false
	state = "title"
	hud.close_modal()
	Snd.clear_queue()
	world.set_time("dusk" if randf() < 0.3 else "day")
	world.set_weather_look("clear", 0.0)
	world.set_precip(0.0)
	var a := G.airport("TPE")
	var p := G.apt_pos(a) + Vector3(-6000, 700, 4000)
	plane.crashed_flag = false
	plane.global_position = p
	plane.yaw = -deg_to_rad(205.0)
	plane.global_basis = Basis(Vector3.UP, plane.yaw)
	plane.v = G.hdg_dir(205.0) * 120.0
	plane.on_ground = false
	plane.gear_down = false
	plane.gear_pos = 0.0
	plane.flaps = 0
	plane.flap_pos = 0.0
	plane.wind = Vector3.ZERO
	plane.turb = 0.0
	plane.time_scale = 1.0
	plane.ap_cruise_alt = 700.0
	plane.ap_engage("hold")
	plane.ap_alt = 700.0
	plane.ap_spd = 120.0
	plane.ap_hdg = 205.0
	cam.title_mode = true
	cam.set_mode("chase")
	hud.show_title()
	hud.game_box.visible = false
	Snd.stop_loops()
	Snd.play_music("sky_theme")

# ── 開始飛行 ──
func start_level(i: int) -> void:
	start_flight(G.LEVELS[i], i)

func restart_flight() -> void:
	start_flight(flight, level)

func start_flight(cfg: Dictionary, li: int) -> void:
	if G.is_touch() and not G.test_mode:
		G.go_fullscreen()
	get_tree().paused = false
	paused = false
	flight = cfg
	level = li
	hud.close_modal()
	Snd.clear_queue()
	_said.clear()
	_land = {}
	if _smoke:
		_smoke.queue_free()
		_smoke = null
	world.set_time(cfg.time)
	world.set_weather_look(cfg.weather, 1.0)
	var fa := G.airport(cfg.from)
	plane.crashed_flag = false
	plane.ap_disengage()
	plane.ap_on = false
	plane.reset_callouts(false)
	plane.fuel = 15000.0
	plane.tailstrike = false
	plane.max_g = 1.0
	plane.last_touch = {}
	plane.spoilers = false
	plane.reverse = false
	plane.lights_on = true
	plane.time_scale = 1.0
	plane.ap_cruise_alt = 2400.0
	plane.ap_wps.clear()
	plane.anti_ice = false
	plane.ice = 0.0
	time_mult = 1.0
	dest_id = ""
	dest_rw = {}
	match String(cfg.mode):
		"landing":
			dest_id = cfg.from
			dest_rw = _rw(fa, false)
			plane.place_on_final(dest_rw, 9000.0)
			from_pos = plane.global_position
		_:
			dep_rw = _rw(fa, true)
			plane.place_on_runway(dep_rw)
			from_pos = plane.global_position
			if String(cfg.get("to", "")) != "":
				dest_id = cfg.to
				dest_rw = _rw(G.airport(dest_id), false)
	plane.ap_dest = dest_rw
	if not dest_rw.is_empty():
		plane._plan_route()
	total_dist = maxf(1.0, from_pos.distance_to(dest_rw.thr if not dest_rw.is_empty() else from_pos))
	director.setup(self, cfg.weather, cfg.get("events", []), from_pos, dest_rw.thr if not dest_rw.is_empty() else from_pos)
	cam.title_mode = false
	cam.set_mode("chase")
	cam.reset_view()
	cam._smooth = Transform3D()
	hud.show_game()
	hud.level_lbl.text = ("LEVEL %d　%s" % [li + 1, cfg.title]) if li >= 0 else "自由飛行"
	state = "flying"
	_t = 0.0
	Snd.play_music("cruise")
	match String(cfg.mode):
		"takeoff":
			Snd.say_all(["co_hello", "x_hello", "x_takeoff_brief", "t_to_" + fa.id])
		"landing":
			Snd.say_all(["x_landing_brief", "t_land_" + fa.id])
		_:
			if dest_id != "":
				_captain_intro(fa.id, dest_id)
				Snd.say_all(["f_demo1", "f_demo_belt", "f_demo_oxy", "f_demo_vest", "f_demo_exit", "f_demo_end"])
				hud.show_cabin(true)
			else:
				Snd.say("f_welcome")
			Snd.say_all(["x_hello", "x_route_brief", "t_to_" + fa.id])
	_test_after_start()

# 機長廣播：自我介紹、航線、預計抵達時間（依目前時間加上預估飛行時間）
func eta_dict() -> Dictionary:
	var mins := 4.0 + total_dist / 120.0 / 60.0 + 3.0
	return Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system() + _tz_offset() + mins * 60.0))

func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 480)) * 60

func _captain_intro(from_id: String, to_id: String) -> void:
	var eta := eta_dict()
	var h: int = eta.hour
	var m: int = eta.minute
	var fa := G.airport(from_id)
	var ta := G.airport(to_id)
	var hm := "%s %02d:%02d" % ["上午" if h < 12 else "下午", h if h <= 12 else h - 12, m]
	var text := "各位旅客您好，我是本班機機長，歡迎搭乘小柯航空八八八班機。本班機由%s起飛，飛往%s，預計抵達時間是%s。飛行途中如果遇到亂流，請繫好安全帶。接下來請注意空服員的安全示範，祝各位旅途愉快。" % [fa.name, ta.name, hm]
	Snd.play("chime", 0.7)
	Snd.say_combo(["cap_intro", "cap_from_" + from_id, "cap_to_" + to_id, "cap_eta", "cap_h_%d" % h, "cap_m_%d" % m, "cap_intro_end"], "captain", text)

func _on_line(id: String, _sp: String, _tx: String) -> void:
	if state != "flying":
		return
	match id:
		"f_demo1": cabin.set_state("demo")
		"f_demo_belt": cabin.set_state("demo_belt")
		"f_demo_oxy": cabin.set_state("demo_oxy")
		"f_demo_vest": cabin.set_state("demo_vest")
		"f_demo_exit": cabin.set_state("demo_exit")
		"f_demo_end": cabin.set_state("demo_end")

func _rw(a: Dictionary, takeoff: bool) -> Dictionary:
	var r := G.runway(a, G.best_dir(a, world.terrain, takeoff))
	r["apt_short"] = a.short
	r["apt_id"] = a.id
	return r

# ── 每格 ──
func _physics_process(delta: float) -> void:
	if state == "boot" or plane == null:
		return
	if state == "title":
		world.update(cam.global_position, cam.global_position, delta, 40.0)
		if plane.global_position.z > 20000.0:
			to_title()
		return
	if paused:
		return
	_t += delta * time_mult
	_input_controls(delta)
	plane.time_scale = time_mult
	var p := progress()
	if state == "flying":
		director.tick(delta * time_mult, p)
	world.update(cam.global_position, cam.global_position, delta, rad_to_deg(atan2(-plane.wind.x, plane.wind.z)) if plane.wind.length() > 0.5 else 40.0)
	_sounds()
	_checks(delta)
	_test_tick()

func _input_controls(delta: float) -> void:
	if state != "flying" or plane.crashed_flag:
		return
	var kp := 0.0
	var kr := 0.0
	var ky := 0.0
	if not hud.xk_input.has_focus():
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): kp -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): kp += 1.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): kr -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): kr += 1.0
		if Input.is_physical_key_pressed(KEY_Q): ky -= 1.0
		if Input.is_physical_key_pressed(KEY_E): ky += 1.0
	var st := hud.stick()
	var pitch := clampf(st.y + kp, -1.0, 1.0)
	if G.invert_pitch:
		pitch = -pitch
	var roll := clampf(st.x + kr, -1.0, 1.0)
	var manual := absf(pitch) > 0.15 or absf(roll) > 0.15 or absf(ky) > 0.2
	var thr_d := 0.0
	if not hud.xk_input.has_focus():
		if Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_PAGEUP) or Input.is_physical_key_pressed(KEY_EQUAL): thr_d += 1.0
		if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_PAGEDOWN) or Input.is_physical_key_pressed(KEY_MINUS): thr_d -= 1.0
	_manual_t = (_manual_t + delta) if (manual or thr_d != 0.0) else 0.0
	if plane.ap_on and _manual_t > 0.25 and plane.ap_phase != "done":
		plane.ap_disengage()
		Snd.say("x_ap_off")
	if not plane.ap_on:
		plane.in_pitch = pitch
		plane.in_roll = roll
		plane.in_yaw = ky
		if thr_d != 0.0:
			plane.throttle = clampf(plane.throttle + thr_d * delta * 0.5, 0.0, 1.0)
		plane.brakes = 1.0 if (hud.brake_held or Input.is_physical_key_pressed(KEY_SPACE)) else 0.0

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or (e as InputEventKey).echo:
		return
	if hud.xk_input and hud.xk_input.has_focus():
		return
	var k := (e as InputEventKey).physical_keycode
	if state == "flying":
		match k:
			KEY_G: toggle_gear()
			KEY_BRACKETLEFT: flaps_step(-1)
			KEY_BRACKETRIGHT: flaps_step(1)
			KEY_B: plane.parking = not plane.parking
			KEY_X: plane.spoilers = not plane.spoilers
			KEY_R: plane.reverse = not plane.reverse
			KEY_Z: toggle_ap()
			KEY_C: hud.alert(cam.next_mode(), 1.2)
			KEY_M: hud.open_map(not hud.map_big)
			KEY_T: cycle_time()
			KEY_L: plane.lights_on = not plane.lights_on
			KEY_P, KEY_ESCAPE: toggle_pause()
			KEY_V: hud.toggle_xk()
	elif k == KEY_ESCAPE:
		hud.close_modal()

func progress() -> float:
	if dest_rw.is_empty():
		return clampf(_t / 300.0, 0.0, 1.0)
	return clampf(1.0 - dist_to_dest() / maxf(total_dist, 1.0), 0.0, 1.0)

func dist_to_dest() -> float:
	if dest_rw.is_empty():
		return 0.0
	var d: Vector3 = dest_rw.thr - plane.global_position
	return Vector2(d.x, d.z).length()

func dest_name() -> String:
	return G.airport(dest_id).name if dest_id != "" else "（自由飛行）"

func target_hdg() -> float:
	if dest_rw.is_empty():
		return -1.0
	if plane.ap_wps.size() > 0 and dist_to_dest() > 14000.0:
		return G.bearing(plane.global_position, plane.ap_wps[0])
	return G.bearing(plane.global_position, dest_rw.thr) if dist_to_dest() > 3000.0 else float(dest_rw.hdg)

func route_points() -> Array:
	var pts: Array = [plane.global_position]
	if dest_rw.is_empty():
		return pts
	if dist_to_dest() > 14000.0:
		for w in plane.ap_wps:
			pts.append(w)
	pts.append(dest_rw.thr)
	pts.append(dest_rw.end)
	return pts

func mission_text() -> String:
	var s := ""
	match String(flight.get("mode", "")):
		"takeoff":
			var goal := G.apt_pos(G.airport(flight.from)).y + 914.0
			s = "任務：起飛並爬升到 3,000 英尺（還差 %s 英尺）" % G.fmt_int(maxi(0, int((goal - plane.global_position.y) * G.M2FT)))
		_:
			if dest_id != "":
				s = "目的地：%s　跑道 %s　剩 %.1f 公里" % [dest_name(), dest_rw.name, dist_to_dest() / 1000.0]
			else:
				s = "自由飛行：開啟地圖點機場，就能設定目的地"
	if plane.on_ground and plane.ias < 5.0 and plane.throttle < 0.1 and _t < 30.0 and String(flight.get("mode", "")) != "landing":
		s += "\n把油門推到底開始起飛，或按「自動駕駛」交給小柯"
	elif plane.ap_on and plane.ap_note != "":
		s += "\n小柯自動駕駛：" + plane.ap_note
	return s

func _sounds() -> void:
	var n1 := plane.n1
	var inside := cam.mode == "cockpit"
	var k := 0.55 if inside else 1.0
	if plane.crashed_flag or state == "title":
		Snd.set_loop("engine", 0.0)
		Snd.set_loop("whine", 0.0)
		Snd.set_loop("wind", 0.0)
		Snd.set_loop("rumble", 0.0)
		Snd.set_loop("stall", 0.0)
		return
	Snd.set_loop("engine", (0.22 + n1 * 0.55) * k, 0.65 + n1 * 0.55)
	Snd.set_loop("whine", n1 * 0.22 * k, 0.75 + n1 * 0.45)
	Snd.set_loop("wind", clampf(plane.ias / 160.0, 0.0, 1.0) * 0.35, 0.8 + plane.ias / 300.0)
	Snd.set_loop("rumble", clampf(plane.ias / 60.0, 0.0, 1.0) * 0.5 if plane.on_ground else 0.0, 0.8 + plane.ias / 120.0)
	Snd.set_loop("stall", 0.6 if plane.stall else 0.0)

func _say_once(id: String) -> void:
	if _said.has(id):
		return
	_said[id] = true
	Snd.say(id)

func _checks(delta: float) -> void:
	if state != "flying" or plane.crashed_flag:
		return
	# 警告語音
	_warn_cd -= delta
	if plane.warn != "" and (plane.warn != _warn_prev or _warn_cd <= 0.0):
		var gid: String = {"stall": "g_stall", "pullup": "g_pullup", "terrain": "g_terrain", "gear": "g_gear", "overspeed": "g_overspeed", "flapspeed": "g_flapspeed"}.get(plane.warn, "")
		if gid != "":
			Snd.callout(gid)
			if plane.warn in ["pullup", "terrain"]:
				Snd.play("whoop", 0.7)
			_warn_cd = 3.0
		if plane.warn == "stall": _say_once("x_stall")
		if plane.warn == "flapspeed": _say_once("x_flaps")
		if plane.warn == "gear": _say_once("x_gear")
	_warn_prev = plane.warn
	var mode := String(flight.get("mode", ""))
	# 起飛訓練完成
	if mode == "takeoff" and not plane.on_ground and plane.global_position.y > G.apt_pos(G.airport(flight.from)).y + 914.0:
		_finish_takeoff()
		return
	if dest_rw.is_empty():
		return
	var d := dist_to_dest()
	if d < 16000.0 and not plane.on_ground:
		_say_once("t_land_" + dest_id)
		if director.weather == "snow" and dest_id == "TPE":
			_say_once("t_snow")
		if dest_id in director.closed:
			_say_once("x_closed")
	if d < 9000.0 and plane.gear_pos > 0.9 and plane.flaps >= 3 and not plane.on_ground and plane.agl < 700.0:
		_say_once("co_landing_check")
	if d < 5000.0 and plane.agl < 300.0 and plane.gear_pos < 0.5 and plane.vs < -1.0 and not plane.ap_on:
		_say_once("x_gear")
	_landing_advice(delta, d)

# ── 降落叮嚀與注意事項 ──
var _adv_cd := 0.0
func _landing_advice(delta: float, d: float) -> void:
	if String(flight.get("mode", "")) == "takeoff":
		return
	var airborne := not plane.on_ground
	# 開始下降：機長廣播（天氣、當地時間）＋空服員客艙準備
	if airborne and d < 30000.0 and _t > 20.0 and not _said.has("descent"):
		_said["descent"] = true
		var wx: String = {"rain": "cap_wx_rain", "snow": "cap_wx_snow", "storm": "cap_wx_storm", "typhoon": "cap_wx_typhoon"}.get(director.weather, "cap_wx_good")
		var now := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) + _tz_offset())
		var wtxt: String = Texts.LINES[wx][1]
		var text := "各位旅客，這裡是機長廣播。我們已經開始下降，準備降落%s，請回到座位繫好安全帶。%s目的地當地時間是 %02d:%02d。" % [dest_name(), wtxt, now.hour, now.minute]
		Snd.play("seatbelt", 0.8)
		hud.seatbelt = true
		Snd.say_combo(["cap_descent", wx, "cap_now", "cap_h_%d" % int(now.hour), "cap_m_%d" % int(now.minute)], "captain", text)
		Snd.say("f_landing_prep")
		hud.alert("安全帶指示燈已打開，準備降落", 2.5)
	if airborne and d < 17000.0 and not _said.has("lchk"):
		_said["lchk"] = true
		Snd.say("x_land_checklist" if not plane.ap_on else "x_ap_land")
		hud.show_checklist(true)
		if director.weather in ["rain", "snow", "typhoon", "storm"]:
			Snd.say("x_land_wet")
		if absf((plane.wind).dot(Vector3(-dest_rw.dir.z, 0, dest_rw.dir.x))) > 5.0:
			Snd.say("x_land_crosswind")
	if airborne and d < 11000.0:
		_say_once("cap_crew_landing")
		if not plane.lights_on:
			_say_once("x_land_lights")
	# 進場偏差提醒（手動飛行時，每 7 秒最多一次）
	_adv_cd -= delta
	if airborne and not plane.ap_on and d < 11000.0 and plane.agl < 800.0 and _adv_cd <= 0.0 and not Snd.busy():
		var dev := plane.ils_dev(dest_rw)
		var kt := plane.ias * G.MS2KT
		var vapp := Aircraft.VAPP * G.MS2KT
		var id := ""
		if plane.agl < 450.0 and plane.gear_pos < 0.9: id = "x_gear"
		elif plane.agl < 500.0 and plane.flaps < 3: id = "x_land_flaps"
		elif kt > vapp + 22.0: id = "x_land_fast"
		elif kt < vapp - 14.0: id = "x_land_slow"
		elif dev.y > 0.8: id = "x_land_high"
		elif dev.y < -0.8: id = "x_land_low"
		elif dev.x > 1.5: id = "x_land_right"
		elif dev.x < -1.5: id = "x_land_left"
		elif not _said.has("x_land_ok") and plane.agl < 500.0:
			id = "x_land_ok"
			_said["x_land_ok"] = true
			Snd.callout("co_stable")
		if plane.agl < 110.0 and (absf(dev.x) > 3.0 or absf(dev.y) > 1.5 or kt > vapp + 35.0) and not _said.has("ga"):
			_said["ga"] = true
			id = "x_land_goaround"
		if id != "":
			Snd.say(id, true)
			_adv_cd = 7.0
	if airborne and not plane.ap_on and plane.agl < 14.0 and plane.vs < -1.0 and d < 3000.0:
		_say_once("x_land_flare")
	# 落地後
	if plane.on_ground and not _land.is_empty():
		if not _said.has("ldbrake"):
			_said["ldbrake"] = true
			if not plane.ap_on:
				Snd.say("x_land_brake", true)
		if plane.reverse and plane.ias * G.MS2KT > 80.0:
			_say_once("co_reverse")
		if plane.ias * G.MS2KT < 60.0:
			_say_once("co_60kt")

# ── 操作 ──
func toggle_gear() -> void:
	if plane.on_ground and plane.gear_down:
		hud.alert("在地面上不能收起落架！", 2.0)
		return
	plane.gear_down = not plane.gear_down
	Snd.play("gear", 0.7)

func flaps_step(d: int) -> void:
	var f := clampi(plane.flaps + d, 0, 3)
	if f != plane.flaps:
		plane.flaps = f
		Snd.play("flaps", 0.6)
		hud.alert("襟翼 %d（%d°）" % [f, int(Aircraft.FLAP_DEG[f])], 1.0)

func engage_ap() -> void:
	if plane.crashed_flag:
		return
	if dest_rw.is_empty():
		plane.ap_cruise_alt = maxf(1200.0, plane.global_position.y + 600.0) if plane.on_ground else plane.global_position.y
		plane.ap_engage("auto" if plane.on_ground else "hold")
	else:
		plane.ap_wps.clear()
		plane.ap_engage("auto", dest_rw)
		plane._plan_route()
	Snd.play("ding", 0.6)

func toggle_ap() -> void:
	if plane.ap_on:
		plane.ap_disengage()
		Snd.say("x_ap_off", true)
	else:
		engage_ap()
		if plane.ap_on:
			Snd.say("x_ap_on", true)
			if not dest_rw.is_empty():
				Snd.say("x_ap_land")

func cycle_time() -> void:
	time_mult = {1.0: 2.0, 2.0: 4.0, 4.0: 1.0}.get(time_mult, 1.0)
	hud.alert("時間 %d 倍速" % int(time_mult), 1.0)

func toggle_pause() -> void:
	if state != "flying":
		return
	paused = not paused
	get_tree().paused = paused
	if paused:
		hud.pause_menu()
	else:
		hud.close_modal()

func divert(id: String) -> void:
	var a := G.airport(id)
	if a.is_empty():
		return
	if id in director.closed:
		hud.alert("%s 已經關閉" % a.short, 2.0)
		return
	dest_id = id
	dest_rw = _rw(a, false)
	plane.ap_dest = dest_rw
	plane.ap_wps.clear()
	plane._plan_route()
	if plane.ap_on and plane.ap_phase in ["approach", "enroute", "goaround"]:
		plane.ap_phase = "enroute"
	total_dist = maxf(dist_to_dest(), 1.0) / maxf(1.0 - progress(), 0.3)
	hud.alert("目的地改為 %s" % a.name, 2.5)
	hud.open_map(false)

func add_detour(storms: Array) -> void:
	if dest_rw.is_empty():
		return
	var p := plane.global_position
	var goal: Vector3 = plane.ap_wps[0] if plane.ap_wps.size() > 0 else dest_rw.thr
	var line := goal - p
	line.y = 0
	var perp := Vector3(-line.z, 0, line.x).normalized()
	var extra: Array = []
	for s in storms:
		var c: Vector3 = s[0]
		var rel := c - p
		var t := clampf(rel.dot(line) / line.length_squared(), 0.0, 1.0)
		var closest := p + line * t
		var off := Vector2(c.x - closest.x, c.z - closest.z).length()
		if off < s[1] + 2000.0 and t > 0.0 and t < 1.0:
			var side := -signf(rel.dot(perp))
			if side == 0.0:
				side = 1.0
			var w: Vector3 = c + perp * side * (s[1] + 3500.0)
			w.y = 0.0
			extra.append([t, w])
	extra.sort_custom(func(a, b): return a[0] < b[0])
	for i in range(extra.size() - 1, -1, -1):
		plane.ap_wps.push_front(extra[i][1])
	if not extra.is_empty():
		hud.alert("繞飛航線已更新（%d 個轉彎點）" % extra.size(), 2.5)

func tower_context() -> void:
	for ev in director.events:
		if ev.status != "active":
			continue
		if ev.id in ["labor", "hypertension", "cardiac"]:
			Snd.say("t_medical")
			return
		if ev.id == "hijack" and hud.squawk == "7500":
			Snd.say("t_hijack")
			return
		if ev.id == "storm":
			Snd.say("t_storm_dev")
			return
		if ev.id == "typhoon":
			Snd.say("t_typhoon_closed")
			return
	if dest_id != "" and dist_to_dest() < 20000.0:
		Snd.say("t_land_" + dest_id)
	elif plane.on_ground and flight.has("from"):
		Snd.say("t_to_" + String(flight.from))
	else:
		Snd.say("t_weather")

func event_action(aid: String) -> bool:
	for ev in director.events:
		if ev.status != "active":
			continue
		for a in ev.actions:
			if a.id == aid and not (a.done and a.once):
				director.do_action(ev, aid)
				return true
	return false

func event_summary() -> String:
	var s := ""
	for ev in director.events:
		if ev.status == "active":
			s += ev.title + "（" + ev.meter_name + ("%d" % int(ev.meter) if ev.meter >= 0.0 else "") + "）"
	return s if s != "" else "一切正常"

# ── 起落與結算 ──
func _on_touchdown(vs: float, info: Dictionary) -> void:
	if state != "flying":
		return
	Snd.play("touchdown", clampf(-vs / 3.0, 0.4, 1.2))
	cam.shake = clampf(-vs * 0.35, 0.2, 1.5)
	var rw := _nearest_runway(plane.global_position)
	var xt := 0.0
	if not rw.is_empty():
		var rel: Vector3 = plane.global_position - rw.thr
		xt = absf(rel.dot(Vector3(-rw.dir.z, 0, rw.dir.x)))
	_land = {"fpm": int(-vs * G.M2FT * 60.0), "center": xt, "apt": rw.get("apt_id", "")}
	plane.reset_callouts()

func _nearest_runway(p: Vector3) -> Dictionary:
	var best := {}
	var bd := 1e12
	for a in G.AIRPORTS:
		var d := G.apt_pos(a).distance_to(p)
		if d < bd:
			bd = d
			best = G.runway(a, 0)
			best["apt_id"] = a.id
	return best

func _on_stopped() -> void:
	if state != "flying" or _land.is_empty():
		return
	if plane.surface_kind(plane.global_position) != "runway":
		return
	_landed(String(_land.apt))

func _landed(apt_id: String) -> void:
	state = "done"
	plane.ap_on = false
	plane.parking = true
	plane.throttle = 0.0
	var evr := director.on_landed(apt_id)
	var fpm: int = _land.get("fpm", 0)
	var lscore := 300
	var word := "完美"
	if fpm > 240: lscore = 250; word = "柔和"
	if fpm > 420: lscore = 180; word = "普通"
	if fpm > 600: lscore = 80; word = "重落地"
	var cscore := 100 if _land.center < 5.0 else (60 if _land.center < 12.0 else 20)
	var score := lscore + cscore
	var fails := 0
	for e in evr:
		score += int(e.pts)
		if not e.ok:
			fails += 1
	if plane.tailstrike:
		score -= 100
	var wrong := dest_id != "" and apt_id != dest_id
	if wrong:
		score -= 150
	var maxp := 400 + 250 * evr.size()
	var ratio := float(score) / float(maxp)
	var stars := 3 if ratio > 0.78 else (2 if ratio > 0.5 else 1)
	if fails > 0 or wrong:
		stars = mini(stars, 1)
	if fails > 0 and evr.size() == fails:
		stars = 0
	G.finish_level(level, stars, score)
	hud.show_checklist(false)
	Snd.say_all(["t_landed", "cap_landed"])
	var hr := int(Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) + _tz_offset()).hour)
	Snd.say("cap_bless_night" if (hr >= 19 or hr < 5 or flight.get("time", "") == "night") else "cap_bless_day")
	Snd.say("f_landed_stay")
	Snd.say("f_bless")
	Snd.say("x_good_landing" if fpm < 420 else "x_hard_landing")
	if stars > 0:
		Snd.say_all(["co_bless", "x_bless"])
	if fpm < 600:
		Snd.play("applause", 0.8)
	Snd.play("fanfare" if stars > 0 else "fail", 0.7)
	var res := {"crash": "", "fpm": fpm, "land_word": word, "center": float(_land.center), "apt": G.airport(apt_id).get("name", apt_id) + ("（不是目的地）" if wrong else ""), "events": evr, "score": maxi(score, 0), "stars": stars, "level": level}
	get_tree().create_timer(9.0).timeout.connect(func(): if state == "done": hud.show_result(res))

func _finish_takeoff() -> void:
	state = "done"
	Snd.say("x_goal_alt")
	Snd.play("fanfare", 0.7)
	var score := 600 - (150 if plane.tailstrike else 0) - (100 if plane.gear_down else 0)
	var stars := 3 if score >= 550 else (2 if score >= 400 else 1)
	G.finish_level(level, stars, score)
	plane.ap_engage("hold")
	var res := {"crash": "", "fpm": 0, "land_word": "起飛", "center": 0.0, "apt": "（起飛訓練）", "events": [{"title": "起飛", "ok": true, "pts": score, "note": ("擦到機尾 " if plane.tailstrike else "") + ("起落架沒收" if plane.gear_down else "收起落架")}], "score": score, "stars": stars, "level": level}
	get_tree().create_timer(3.5).timeout.connect(func(): if state == "done": hud.show_result(res))

func _on_crash(reason: String) -> void:
	if state != "flying":
		return
	state = "done"
	Snd.clear_queue()
	Snd.play("crash")
	cam.shake = 2.5
	_smoke = CPUParticles3D.new()
	_smoke.amount = 160
	_smoke.lifetime = 6.0
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke.emission_sphere_radius = 8.0
	_smoke.direction = Vector3.UP
	_smoke.spread = 25.0
	_smoke.gravity = Vector3(0, 3, 0)
	_smoke.initial_velocity_min = 4.0
	_smoke.initial_velocity_max = 10.0
	_smoke.scale_amount_min = 6.0
	_smoke.scale_amount_max = 14.0
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 8
	sm.rings = 4
	sm.material = M.mat(Color(0.12, 0.12, 0.13, 0.55))
	_smoke.mesh = sm
	add_child(_smoke)
	_smoke.global_position = plane.global_position
	Snd.say("x_crash")
	var evr := director.on_landed("")
	G.finish_level(level, 0, 0)
	var res := {"crash": reason, "events": evr, "score": 0, "stars": 0, "level": level, "fpm": 0, "land_word": "", "center": 0.0, "apt": ""}
	get_tree().create_timer(4.0).timeout.connect(func(): if state == "done": hud.show_result(res))

func _on_callout(id: String) -> void:
	if id == "liftoff":
		return
	Snd.callout(id)
	if id == "cposrate" and not plane.ap_on:
		get_tree().create_timer(8.0).timeout.connect(func():
			if state == "flying" and plane.gear_down and not plane.on_ground and plane.agl > 60.0:
				hud.alert("記得收起落架（G 鍵）", 2.5))

# ── 測試旗標 ──
func _test_setup() -> void:
	if not G.test_mode:
		return
	if G.args.has("shots"):
		for s in G.arg("shots").split(","):
			_shots.append(float(s))
	_quit_t = float(G.arg("quit", "-1"))
	if G.args.has("help"):
		hud.show_help(int(G.arg("help")))
	if G.args.has("settings"):
		hud.show_settings()
	if G.args.has("levels"):
		hud.show_levels()

func _test_after_start() -> void:
	if not G.test_mode:
		return
	if G.args.has("ap"):
		engage_ap()
	if G.args.has("ts"):
		time_mult = float(G.arg("ts"))
	if G.args.has("cam"):
		cam.set_mode(G.arg("cam"))
	if G.args.has("cabin"):
		hud.show_cabin(true)
	if G.args.has("xk"):
		hud.toggle_xk(1)
	if G.args.has("map"):
		hud.open_map(true)
	if G.args.has("evnow"):
		for e in G.arg("evnow").split(","):
			director.pending.erase(e)
			director._start(e)

var _test_clock := 0.0
var _dbg_t := 0.0
var _acted := false
func _test_tick() -> void:
	if G.args.has("autoact") and not _acted and _t > float(G.arg("autoact")):
		_acted = true
		for ev in director.events:
			for a in ev.actions:
				print("ACT ", ev.id, " ", a.id)
				director.do_action(ev, a.id)
		print("SUMMARY ", event_summary())
		xiaoke.ask("最近的機場在哪")
		xiaoke.ask("聯絡塔台")
		xiaoke.ask("高度多少")
		xiaoke.ask("你是誰")
	if not G.args.has("dbg"):
		return
	_dbg_t += get_physics_process_delta_time()
	if _dbg_t > 1.0:
		_dbg_t = 0.0
		print("t=%.0f ap=%s phase=%s alt=%d ias=%d gnd=%s thr=%.2f note=%s" % [_t, plane.ap_on, plane.ap_phase, int(plane.global_position.y), int(plane.ias*G.MS2KT), plane.on_ground, plane.throttle, plane.ap_note])

func _process(delta: float) -> void:
	if not G.test_mode:
		return
	_test_clock += delta
	if not _shots.is_empty() and _test_clock >= _shots[0]:
		_shots.pop_front()
		var img := get_viewport().get_texture().get_image()
		var out := G.arg("out", "user://shots")
		DirAccess.make_dir_recursive_absolute(out)
		img.save_png(out.path_join("shot_%03d.png" % int(_test_clock)))
		print("SHOT ", int(_test_clock), " state=", state, " phase=", plane.ap_phase if plane else "", " alt=", int(plane.global_position.y) if plane else 0)
	if _quit_t > 0.0 and _test_clock >= _quit_t:
		get_tree().quit()
