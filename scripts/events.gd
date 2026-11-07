class_name Director
extends Node
## 天氣與機上突發狀況導演：觸發事件、處置選項、病人狀態條、雷雨胞、亂流、結冰、改降、評分。

signal changed()
signal divert_requested(apt_id: String)

var main
var plane: Aircraft
var world: World
var cabin: CabinView
var events: Array = []          # 進行中與已結束的事件
var pending: Array = []         # 尚未觸發的事件 id
var weather := "clear"
var storms: Array = []          # [中心, 半徑]
var closed: Array = []
var wind := Vector3.ZERO
var base_turb := 0.0
var rain_zone: Dictionary = {}  # {c, r}
var in_storm := false
var storm_time := 0.0
var _bolt_t := 3.0
var _rng := RandomNumberGenerator.new()
var _said: Dictionary = {}
var finished := false
var landed_apt := ""
var t := 0.0

func setup(m, wx: String, evs: Array, route_from: Vector3, route_to: Vector3) -> void:
	main = m
	plane = m.plane
	world = m.world
	cabin = m.cabin
	weather = wx
	_rng.randomize()
	pending = evs.duplicate()
	events.clear()
	storms.clear()
	closed.clear()
	_said.clear()
	finished = false
	in_storm = false
	storm_time = 0.0
	plane.anti_ice = false
	plane.ice = 0.0
	plane.icing_rate = 0.0
	plane.mu = 1.0
	match wx:
		"cloudy":
			wind = G.hdg_dir(60.0) * -5.0
			base_turb = 0.08
		"rain":
			wind = G.hdg_dir(200.0) * -7.0
			base_turb = 0.18
			rain_zone = {"c": route_to, "r": 15000.0}
		"storm":
			wind = G.hdg_dir(230.0) * -9.0
			base_turb = 0.15
			_place_storms(route_from, route_to)
		"typhoon":
			wind = G.hdg_dir(70.0) * -17.0
			base_turb = 0.45
		"snow":
			wind = G.hdg_dir(20.0) * -8.0
			base_turb = 0.12
		_:
			wind = G.hdg_dir(40.0) * -3.0
			base_turb = 0.0
	plane.wind = wind
	plane.turb = base_turb

func _place_storms(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var perp := Vector3(-d.z, 0, d.x).normalized()
	for f in [0.38, 0.58, 0.74]:
		var c: Vector3 = a + d * f + perp * _rng.randf_range(-1800.0, 1800.0)
		c.y = 0.0
		storms.append([c, _rng.randf_range(3000.0, 4200.0)])

# ── 每格 ──
func tick(delta: float, progress: float) -> void:
	if finished:
		return
	t += delta
	_weather(delta)
	for id in pending.duplicate():
		if _should_start(id, progress):
			pending.erase(id)
			_start(id)
	for ev in events:
		if ev.status == "active":
			_update(ev, delta, progress)

func _should_start(id: String, p: float) -> bool:
	if plane.on_ground:
		return false
	match id:
		"storm": return p > 0.12 or _near_storm(16000.0)
		"rain": return p > 0.45
		"typhoon": return p > 0.1
		"snow": return plane.ice > 0.12 or p > 0.3
		"labor", "hypertension", "cardiac": return p > 0.22 and plane.agl > 600.0
		"hijack": return p > 0.28 and plane.agl > 600.0
	return false

func _near_storm(r: float) -> bool:
	for s in storms:
		if Vector2(plane.global_position.x - s[0].x, plane.global_position.z - s[0].z).length() < r + s[1]:
			return true
	return false

# ── 天氣 ──
func _weather(delta: float) -> void:
	var p := plane.global_position
	var turb := base_turb
	var precip := 0.0
	match weather:
		"rain":
			precip = 0.35
			var d := Vector2(p.x - rain_zone.c.x, p.z - rain_zone.c.z).length()
			if d < rain_zone.r:
				precip = 1.0
				turb = maxf(turb, 0.3)
			plane.mu = 0.65
		"typhoon":
			precip = 0.9
			plane.mu = 0.6
		"storm":
			precip = 0.25
		"snow":
			precip = 0.7 if p.y < 1800.0 else 0.3
			plane.mu = 0.35
			# 雲中而且高度高：結冰
			plane.icing_rate = 0.0 if plane.anti_ice else (0.011 if p.y > 800.0 else 0.0)
	# 雷雨胞
	var inside := false
	for s in storms:
		var d := Vector2(p.x - s[0].x, p.z - s[0].z).length()
		if d < s[1] and p.y < 5500.0:
			inside = true
			turb = maxf(turb, 1.0 - d / s[1] * 0.4)
			precip = 1.0
	if inside:
		storm_time += delta
		if not in_storm:
			_say_once("x_storm_inside")
			main.hud.alert("進入雷雨胞！強烈亂流")
	in_storm = inside
	if p.y > world.cloud_top + 150.0 and weather in ["rain", "storm", "typhoon", "snow"]:
		precip *= 0.1
	plane.turb = turb if not plane.on_ground else turb * 0.3
	plane.wind = wind
	world.set_precip(precip)
	Snd.set_loop("rain", precip * 0.8)
	if turb > 0.35 and not plane.on_ground:
		main.cam.shake = maxf(main.cam.shake, turb * 0.5)
		cabin.shake = turb
	else:
		cabin.shake = 0.0
	# 閃電
	if weather in ["storm", "typhoon"] or inside:
		_bolt_t -= delta
		if _bolt_t <= 0.0:
			_bolt_t = _rng.randf_range(1.5, 4.0) if inside else _rng.randf_range(5.0, 11.0)
			var c := p + Vector3(_rng.randf_range(-6000, 6000), 0, _rng.randf_range(-6000, 6000))
			if not storms.is_empty() and not inside:
				var s: Array = storms[_rng.randi() % storms.size()]
				c = s[0] + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * s[1] * 0.6
			c.y = 2400.0
			world.lightning(c)
			var dist := c.distance_to(p)
			get_tree().create_timer(clampf(dist / 340.0 * 0.3, 0.1, 4.0)).timeout.connect(func(): Snd.play("thunder", clampf(1.4 - dist / 12000.0, 0.25, 1.2)))

# ── 事件 ──
func _ev(id: String) -> Dictionary:
	for e in events:
		if e.id == id:
			return e
	return {}

func _start(id: String) -> void:
	var ev := {"id": id, "title": G.EVENT_NAMES[id], "status": "active", "meter": -1.0, "meter_name": "", "bad_high": false,
		"decay": 0.0, "actions": [], "flags": {}, "t": 0.0, "score": 0, "note": "", "cabin": false}
	match id:
		"storm":
			ev.actions = [_a("deviate", "申請繞飛"), _a("seatbelt", "安全帶燈"), _a("pa_belt", "廣播坐好")]
			ev.note = "地圖上紅色圓圈是雷雨胞，避開它們。"
			Snd.say_all(["co_storm", "x_storm"])
		"rain":
			ev.actions = [_a("wx", "詢問天氣"), _a("autoland", "自動降落"), _a("lights", "落地燈")]
			ev.note = "跑道濕滑，落地後要提早煞車。"
			Snd.say_all(["x_rain"])
		"typhoon":
			if main.dest_id not in closed:
				closed.append(main.dest_id)
			ev.actions = [_a("divert", "改降備降機場"), _a("seatbelt", "安全帶燈"), _a("pa_typhoon", "廣播改降")]
			ev.note = "目的地機場關閉，必須改降。"
			Snd.say_all(["t_typhoon_closed", "x_typhoon", "co_typhoon"])
		"snow":
			ev.actions = [_a("antiice", "打開防冰"), _a("descend", "下降高度"), _a("seatbelt", "安全帶燈")]
			ev.note = "機翼結冰會讓升力下降，要打開防冰。"
			Snd.say_all(["co_ice", "x_snow"])
		"labor":
			ev.meter = 0.0
			ev.meter_name = "產程"
			ev.bad_high = true
			ev.decay = 0.42
			ev.cabin = true
			ev.actions = [_a("doctor", "廣播找醫師"), _a("kit", "準備接生用品"), _a("panpan", "宣告醫療緊急"), _a("divert", "改降最近機場"), _a("talk", "安慰孕婦", false)]
			ev.note = "寶寶隨時會出生，準備好就能在機上接生。"
			cabin.set_state("labor")
			Snd.play("chime")
			Snd.say_all(["co_cabin_call", "f_labor1", "p_1", "x_labor"])
		"hypertension":
			ev.meter = 55.0
			ev.meter_name = "病人狀況"
			ev.decay = 0.07
			ev.cabin = true
			ev.actions = [_a("med", "讓他服藥"), _a("oxygen", "給氧氣"), _a("medlink", "地面醫療顧問"), _a("doctor", "廣播找醫師"), _a("divert", "改降最近機場"), _a("talk", "關心李伯伯", false)]
			cabin.set_state("bp")
			Snd.play("chime")
			Snd.say_all(["co_cabin_call", "f_bp1", "e_1", "x_bp"])
		"cardiac":
			ev.meter = 50.0
			ev.meter_name = "病人狀況"
			ev.decay = 0.15
			ev.cabin = true
			ev.actions = [_a("mayday", "宣告緊急求救"), _a("divert", "改降最近機場"), _a("doctor", "廣播找醫師"), _a("aed", "使用 AED"), _a("cpr", "輪流 CPR"), _a("talk", "安慰張太太", false)]
			cabin.set_state("heart")
			Snd.play("chime")
			Snd.say_all(["co_cabin_call", "f_heart1", "w_1", "x_heart"])
		"hijack":
			ev.meter = 55.0
			ev.meter_name = "緊張指數"
			ev.bad_high = true
			ev.decay = -0.08
			ev.cabin = true
			ev.actions = [_a("squawk", "應答機 7500"), _a("talk_calm", "平穩談判"), _a("ask_xk", "請小柯分析"), _a("firm", "強硬拒絕"), _a("pa_calm", "廣播安撫乘客")]
			ev.note = "保持冷靜，先通知塔台，再跟對方談。"
			cabin.set_state("hijack")
			Snd.play("caution")
			Snd.say_all(["co_hijack", "f_hijack1", "h_1", "x_hijack"])
			Snd.play_music("tension")
	events.append(ev)
	main.hud.show_event(ev)
	if ev.cabin:
		main.hud.show_cabin(true)
	changed.emit()

func _a(id: String, label: String, once := true) -> Dictionary:
	return {"id": id, "label": label, "done": false, "once": once}

func _update(ev: Dictionary, delta: float, progress: float) -> void:
	ev.t += delta
	match ev.id:
		"storm":
			var last: float = 0.0
			for s in storms:
				last = maxf(last, 0.0)
			if progress > 0.8 and not in_storm:
				_resolve(ev, true)
				_say_once("x_storm_clear")
		"snow":
			if plane.ice > 0.5 and not plane.anti_ice:
				_say_once("x_ice_warn")
		"labor":
			ev.meter = minf(100.0, ev.meter + ev.decay * delta)
			if ev.meter >= 100.0 and not ev.flags.has("born"):
				ev.flags["born"] = true
				_birth(ev)
		"hypertension", "cardiac":
			ev.meter = clampf(ev.meter - ev.decay * delta, 0.0, 100.0)
			if ev.id == "cardiac" and ev.t > 28.0 and not ev.flags.has("arrest"):
				ev.flags["arrest"] = true
				ev.meter = minf(ev.meter, 26.0)
				ev.decay = 0.45 if not ev.flags.has("cpr") else 0.22
				cabin.set_state("heart_arrest")
				Snd.play("caution")
				Snd.say_all(["f_heart_worse", "x_heart_critical"])
				main.hud.alert("張先生心跳停止！請使用 AED")
				_mark_new(ev, "aed")
			if ev.id == "hypertension" and ev.meter > 85.0:
				_say_once("f_bp_better")
			if ev.meter < 20.0:
				_say_once("x_patient_worse_" + ev.id, "x_patient_worse")
			if ev.meter <= 0.0:
				_fail(ev, "李伯伯陷入昏迷" if ev.id == "hypertension" else "張先生搶救無效")
		"hijack":
			ev.meter = clampf(ev.meter - ev.decay * delta, 0.0, 100.0)
			if ev.meter >= 100.0:
				_fail(ev, "劫機者情緒失控")
	changed.emit()

func _mark_new(ev: Dictionary, aid: String) -> void:
	for a in ev.actions:
		if a.id == aid:
			a.done = false

func _say_once(key: String, id := "") -> void:
	if _said.has(key):
		return
	_said[key] = true
	Snd.say(id if id != "" else key)

func _birth(ev: Dictionary) -> void:
	var ready: bool = ev.flags.has("kit")
	cabin.set_state("labor_born")
	Snd.say_all(["f_labor_push", "f_baby", "p_baby"])
	get_tree().create_timer(4.0).timeout.connect(func(): Snd.play("baby"); Snd.play("applause", 0.8))
	ev.flags["birth_ok"] = ready
	ev.note = "寶寶在機上平安出生了！" if ready else "寶寶出生了，但沒有準備好用品，要盡快落地送醫。"
	main.hud.alert("機上寶寶誕生！")

func _resolve(ev: Dictionary, ok: bool) -> void:
	ev.status = "resolved" if ok else "failed"
	main.hud.show_event(ev)
	changed.emit()

func _fail(ev: Dictionary, why: String) -> void:
	ev.status = "failed"
	ev.note = why
	Snd.play("fail")
	main.hud.alert(why)
	changed.emit()

# ── 處置 ──
func do_action(ev: Dictionary, aid: String) -> void:
	if ev.status != "active" and aid != "talk":
		return
	var act: Dictionary = {}
	for a in ev.actions:
		if a.id == aid:
			act = a
	if act.is_empty() or (act.done and act.once):
		return
	act.done = true
	var fl: Dictionary = ev.flags
	fl[aid] = true
	match aid:
		"deviate":
			Snd.say_all(["cap_deviate", "t_storm_dev"])
			main.add_detour(storms)
		"seatbelt":
			Snd.play("seatbelt")
			Snd.say("f_seatbelt")
			main.hud.seatbelt = true
		"pa_belt":
			Snd.say("cap_seatbelt")
		"pa_typhoon":
			Snd.say("cap_typhoon")
		"wx":
			Snd.say_all(["cap_weather", "t_rain" if weather == "rain" else "t_weather"])
		"autoland":
			main.engage_ap()
			Snd.say("x_ap_land")
		"lights":
			plane.lights_on = true
			Snd.say("x_ok")
		"antiice":
			plane.anti_ice = true
			Snd.say("co_antiice")
		"descend":
			plane.ap_cruise_alt = 900.0
			plane.ap_alt = 900.0
			Snd.say("x_ok")
			main.hud.alert("請下降到 3,000 英尺左右，避開結冰層")
		"divert":
			var a := _nearest_open()
			if not a.is_empty():
				divert_requested.emit(a.id)
				if ev.id in ["labor", "hypertension", "cardiac"]:
					Snd.say_all(["x_divert_set", "cap_divert", "t_divert_ok"])
					ev.meter = minf(ev.meter + (0.0 if ev.bad_high else 4.0), 100.0)
				else:
					Snd.say_all(["x_divert_set", "t_divert_ok"])
		"doctor":
			Snd.say("cap_doctor")
			var found := _rng.randf() < 0.8
			get_tree().create_timer(9.0).timeout.connect(func():
				if ev.status != "active" and not ev.flags.has("born"):
					return
				if found:
					fl["doc_found"] = true
					cabin.set_state("doctor")
					var dl := {"labor": "d_labor", "hypertension": "d_bp", "cardiac": "d_heart"}
					Snd.say_all(["d_hello", dl.get(ev.id, "d_bp")])
					if ev.id == "cardiac":
						Snd.say("f_aspirin")
						ev.meter = minf(100.0, ev.meter + 8.0)
						ev.decay *= 0.7
					elif ev.id == "hypertension":
						ev.meter = minf(100.0, ev.meter + 10.0)
						ev.decay *= 0.6
					main.hud.alert("找到醫師了！")
				else:
					Snd.say("f_doctor_none"))
		"kit":
			Snd.say("f_labor_kit")
		"panpan":
			Snd.say_all(["cap_panpan", "t_medical"])
		"mayday":
			Snd.say_all(["cap_mayday", "t_mayday_ack", "x_ambulance"])
		"talk":
			var lid: String = {"labor": "p_2", "hypertension": "e_2", "cardiac": "w_2"}.get(ev.id, "")
			if lid != "":
				Snd.say(lid)
			if ev.meter >= 0.0 and not ev.bad_high:
				ev.meter = minf(100.0, ev.meter + 2.0)
		"med":
			Snd.say("f_bp_med")
			ev.meter = minf(100.0, ev.meter + 18.0)
		"oxygen":
			Snd.say("f_bp_oxygen")
			cabin.set_state("bp_oxygen")
			ev.meter = minf(100.0, ev.meter + 12.0)
		"medlink":
			Snd.say("m_bp")
			ev.meter = minf(100.0, ev.meter + 5.0)
			ev.decay *= 0.85
		"aed":
			if fl.has("arrest") and not fl.has("revived"):
				fl["revived"] = true
				Snd.play("beep")
				Snd.say("f_heart_aed")
				ev.meter = 55.0
				ev.decay = 0.1
				cabin.set_state("heart_ok")
				main.hud.alert("電擊成功，恢復心跳！")
			else:
				fl["aed_ready"] = true
				Snd.say("x_ok")
				main.hud.alert("AED 已準備在病人旁邊")
				act.done = not fl.has("arrest")
		"cpr":
			Snd.say("f_heart_cpr")
			if fl.has("arrest") and not fl.has("revived"):
				ev.decay = 0.22
			else:
				ev.decay *= 0.85
		"squawk":
			Snd.say_all(["co_7500", "t_hijack", "x_hijack_land"])
			ev.meter = maxf(0.0, ev.meter - 5.0)
			main.hud.squawk = "7500"
		"talk_calm":
			Snd.say("cap_hijack_talk")
			var good: bool = ev.meter < 70.0 or fl.has("ask_xk")
			if good:
				Snd.say_all(["h_2", "h_3"])
				ev.meter = maxf(0.0, ev.meter - 30.0)
				ev.decay = 0.0
				cabin.set_state("hijack_calm")
				main.hud.alert("對方把刀放下了")
			else:
				Snd.say("h_angry")
				ev.meter = minf(100.0, ev.meter + 8.0)
				act.done = false
		"ask_xk":
			Snd.say("x_hijack_talk")
		"firm":
			Snd.say_all(["cap_hijack_firm", "h_angry"])
			ev.meter = minf(100.0, ev.meter + 22.0)
		"pa_calm":
			Snd.say("cap_calm")
			ev.meter = maxf(0.0, ev.meter - 8.0)
	main.hud.show_event(ev)
	changed.emit()

func _nearest_open() -> Dictionary:
	for n in G.nearest_airports(plane.global_position, closed):
		if not n.closed:
			return n.a
	return {}

# ── 落地結算 ──
func on_landed(apt_id: String) -> Array:
	finished = true
	landed_apt = apt_id
	var results: Array = []
	for ev in events:
		var ok: bool = ev.status != "failed"
		var pts := 0
		var note := ""
		var fl: Dictionary = ev.flags
		match ev.id:
			"storm":
				pts = 150 - int(storm_time * 4.0) + (30 if fl.has("seatbelt") else 0) + (20 if fl.has("deviate") else 0)
				note = "在雷雨胞裡 %d 秒" % int(storm_time)
			"rain":
				pts = 120 + (20 if fl.has("wx") else 0)
				note = "雨中安全落地"
			"typhoon":
				ok = apt_id not in closed
				pts = 200 if ok else -200
				note = "成功改降" if ok else "降落在已關閉的機場"
			"snow":
				pts = 100 + (60 if fl.has("antiice") else -40)
				note = "防冰有開" if fl.has("antiice") else "沒有打開防冰"
			"labor":
				pts = 120 + (40 if fl.has("doc_found") else 0) + (40 if fl.has("kit") else 0) + (30 if fl.has("panpan") else 0)
				if fl.has("born") and not fl.get("birth_ok", false):
					pts -= 80
				note = "母女平安" if fl.has("born") else "落地後由救護車送醫"
				if ok:
					Snd.say("f_ok_landed")
			"hypertension", "cardiac":
				pts = int(ev.meter * 2.0) + (40 if fl.has("divert") else 0) + (30 if fl.has("doc_found") else 0) + (30 if fl.has("mayday") or fl.has("panpan") else 0)
				note = "病人狀況 %d%%" % int(ev.meter) if ok else ev.note
				if ok:
					Snd.say("f_ok_landed")
			"hijack":
				ok = ok and fl.has("squawk")
				pts = 250 - int(ev.meter) + (50 if fl.has("talk_calm") else 0)
				note = "特勤隊順利制伏嫌犯" if ok else ("沒有通知塔台" if not fl.has("squawk") else ev.note)
				if ok:
					cabin.set_state("police")
					Snd.play("siren", 0.6)
					Snd.say("po_1")
		if not ok:
			pts = mini(pts, 0)
		ev.status = "resolved" if ok else "failed"
		results.append({"title": ev.title, "ok": ok, "pts": pts, "note": note})
	# 還沒觸發的事件不計分
	return results
