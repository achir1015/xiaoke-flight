class_name Aircraft
extends Node3D
## 客機飛行模型：推力、升力（攻角、襟翼、失速、結冰）、阻力、側滑、地面效應、地面滑行與煞車、
## 電傳飛控（放開桿子保持航跡角與坡度）、起落與墜毀判定，以及 AI 自動駕駛（起飛→巡航→進場→落地）。

signal touchdown(vs: float, info: Dictionary)
signal crashed(reason: String)
signal callout(id: String)
signal ap_changed(on: bool)
signal stopped_on_runway()

const MASS0 := 165000.0
const AREA := 360.0
const TMAX := 640000.0
const G0 := 9.81
const FLAP_DEG := [0.0, 5.0, 15.0, 30.0]
const FLAP_CL := [0.0, 0.3, 0.6, 0.95]
const FLAP_CD := [0.0, 0.005, 0.018, 0.045]
const FLAP_VMAX := [999.0, 235.0, 205.0, 180.0]
const VR := 74.0          # 抬輪速度 m/s（約 144 節）
const VAPP := 72.0        # 進場速度 m/s（約 140 節）
const CRUISE_SPD := 150.0 # 巡航速度 m/s（約 290 節）

var model: Node3D
var world: World
var v := Vector3.ZERO
var w := Vector3.ZERO           # 機體角速度：x 俯仰（抬頭＋）、y 偏航（右＋）、z 滾轉（右＋）
var throttle := 0.0
var n1 := 0.0
var flaps := 0
var flap_pos := 0.0
var gear_down := true
var gear_pos := 1.0
var brakes := 0.0
var parking := false
var spoilers := false
var spoiler_pos := 0.0
var reverse := false
var on_ground := true
var crashed_flag := false
var in_pitch := 0.0
var in_roll := 0.0
var in_yaw := 0.0
var wind := Vector3.ZERO
var turb := 0.0
var ice := 0.0
var anti_ice := false
var icing_rate := 0.0
var fuel := 15000.0
var lights_on := true
var gamma_hold := 0.0
var bank_hold := 0.0
var theta := 0.0                # 地面時機頭仰角
var yaw := 0.0                  # 地面時航向（弧度，Godot 旋轉）
var alpha := 0.0
var beta := 0.0
var ias := 0.0
var agl := 0.0
var vs := 0.0
var gamma := 0.0
var pitch := 0.0
var bank := 0.0
var heading := 0.0
var stall := false
var mu := 1.0                   # 跑道摩擦係數倍率（濕 0.65、雪 0.35）
var tailstrike := false
var max_g := 1.0
var gload := 1.0
var _gust := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _said: Dictionary = {}
var _air_time := 0.0
var _ground_time := 0.0
var last_touch := {}
var time_scale := 1.0

# 自動駕駛
var ap_on := false
var ap_mode := "auto"           # auto（全程）或 hold（保持航向、高度、速度）
var ap_phase := ""
var ap_hdg := 0.0
var ap_alt := 900.0
var ap_spd := CRUISE_SPD
var ap_dest: Dictionary = {}    # G.runway() 結果
var ap_cruise_alt := 2400.0
var ap_note := ""
var _ap_i := 0.0
var ap_dep_hdg := 0.0

func _ready() -> void:
	_rng.randomize()
	model = M.airliner(0)
	add_child(model)

func setup(w0: World) -> void:
	world = w0

# ── 擺放 ──
func place_on_runway(rw: Dictionary) -> void:
	var p: Vector3 = rw.thr + rw.dir * 60.0
	yaw = -deg_to_rad(rw.hdg)
	theta = 0.0
	global_position = Vector3(p.x, rw.thr.y + M.GEAR_H, p.z)
	global_basis = Basis(Vector3.UP, yaw)
	v = Vector3.ZERO
	w = Vector3.ZERO
	on_ground = true
	gear_down = true
	gear_pos = 1.0
	flaps = 2
	flap_pos = 2.0
	throttle = 0.0
	n1 = 0.2
	brakes = 0.0
	parking = false
	heading = rw.hdg

func place_on_final(rw: Dictionary, dist: float) -> void:
	var gs := deg_to_rad(3.0)
	var p: Vector3 = rw.thr - rw.dir * dist
	var h: float = rw.thr.y + dist * tan(gs) + 15.0
	global_position = Vector3(p.x, h, p.z)
	yaw = -deg_to_rad(rw.hdg)
	theta = deg_to_rad(2.0)
	global_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, theta)
	v = rw.dir * (VAPP + 4.0) + Vector3(0, -(VAPP + 4.0) * tan(gs), 0)
	on_ground = false
	gear_down = true
	gear_pos = 1.0
	flaps = 3
	flap_pos = 3.0
	throttle = 0.48
	n1 = 0.48
	gamma_hold = -gs
	bank_hold = 0.0
	heading = rw.hdg

func mass() -> float:
	return MASS0 + fuel

func ground_h() -> float:
	var h := world.terrain.height_at(global_position.x, global_position.z)
	return maxf(h, 0.0)

# 機輪所在的地面種類：runway（跑道）、paved（機場範圍）、land、water
func surface_kind(p: Vector3) -> String:
	for a in G.AIRPORTS:
		var c := G.apt_pos(a)
		var u := G.hdg_dir(a.hdg)
		var rel := p - c
		var du := absf(rel.dot(u))
		var dv := absf(rel.dot(Vector3(-u.z, 0, u.x)))
		if du <= a.len * 0.5 + 70.0 and dv <= 36.0:
			return "runway"
		if du <= a.len * 0.5 + 650.0 and dv <= 520.0:
			return "paved"
	return "water" if world.terrain.height_at(p.x, p.z) <= 0.3 else "land"

# ── 物理 ──
func _physics_process(delta: float) -> void:
	if crashed_flag or world == null:
		return
	var steps := 2 if time_scale <= 1.0 else int(2 * time_scale)
	var dt := delta * time_scale / steps
	for i in steps:
		if ap_on:
			_autopilot(dt)
		_step(dt)
		if crashed_flag:
			return
	_t += delta * time_scale

func _step(dt: float) -> void:
	var b := global_basis.orthonormalized()
	var fwd := -b.z
	var up := b.y
	var right := b.x
	var pos := global_position
	var gh := ground_h()
	agl = pos.y - M.GEAR_H - gh
	var rho := 1.225 * exp(-pos.y / 9000.0)
	# 陣風與亂流
	if turb > 0.0:
		_gust = _gust.lerp(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1) * 0.8, _rng.randf_range(-1, 1)) * turb * 9.0, minf(1.0, dt * 1.5))
	else:
		_gust = _gust.lerp(Vector3.ZERO, minf(1.0, dt))
	var air := v - (wind + _gust)
	var V := air.length()
	var vb := b.inverse() * air
	var u := -vb.z
	alpha = atan2(-vb.y, maxf(u, 0.5))
	beta = atan2(vb.x, maxf(u, 0.5)) if V > 5.0 else 0.0
	ias = V * sqrt(rho / 1.225)
	var q := 0.5 * rho * V * V
	# 引擎
	var tgt := throttle if fuel > 0.0 else 0.0
	n1 = move_toward(n1, maxf(tgt, 0.2 if fuel > 0.0 else 0.0), dt * (0.22 if tgt > n1 else 0.32))
	var thrust := TMAX * (0.03 + 0.97 * pow(maxf(0.0, (n1 - 0.18) / 0.82), 1.15)) * (1.0 - 0.22 * minf(V / 250.0, 1.0))
	if reverse and on_ground:
		thrust = -TMAX * 0.42 * n1
	fuel = maxf(0.0, fuel - (0.35 + 2.1 * n1) * dt)
	# 結冰
	if anti_ice:
		ice = maxf(0.0, ice - dt * 0.05)
	else:
		ice = clampf(ice + icing_rate * dt, 0.0, 1.0)
	# 氣動力
	flap_pos = move_toward(flap_pos, float(flaps), dt * 0.25)
	gear_pos = move_toward(gear_pos, 1.0 if gear_down else 0.0, dt * 0.16)
	spoiler_pos = move_toward(spoiler_pos, 1.0 if spoilers else 0.0, dt * 2.0)
	var fi := int(floor(flap_pos))
	var ff := flap_pos - fi
	var fi2 := mini(fi + 1, 3)
	var cl_f: float = lerpf(FLAP_CL[fi], FLAP_CL[fi2], ff)
	var cd_f: float = lerpf(FLAP_CD[fi], FLAP_CD[fi2], ff)
	var cl0 := 0.22 + cl_f
	var a_st := deg_to_rad(15.0 + flap_pos * 0.8) - ice * deg_to_rad(5.0)
	var CL := 0.0
	if alpha < a_st:
		CL = cl0 + 5.2 * alpha
	else:
		var clmax := cl0 + 5.2 * a_st
		CL = maxf(clmax - (alpha - a_st) * 4.0, clmax * 0.5)
	CL = clampf(CL, -1.2, 2.7)
	CL *= 1.0 - ice * 0.15
	if on_ground and spoiler_pos > 0.0:
		CL *= 1.0 - 0.7 * spoiler_pos
	stall = alpha > a_st and not on_ground and V > 20.0
	var ge := clampf(agl / 35.0, 0.0, 1.0)
	var CD := 0.021 + 0.042 * CL * CL * (0.55 + 0.45 * ge) + gear_pos * 0.016 + cd_f + spoiler_pos * 0.06 + ice * 0.035
	if alpha > a_st:
		CD += (alpha - a_st) * 1.4
	var adir := air / V if V > 1.0 else fwd
	var ldir := right.cross(adir).normalized()
	var m := mass()
	var lift := ldir * CL * q * AREA
	var F := lift - adir * CD * q * AREA + fwd * thrust - right * (beta * q * AREA * 0.45) + Vector3(0, -G0 * m, 0)
	gload = lift.dot(up) / (m * G0)
	max_g = maxf(max_g, absf(gload)) if not on_ground else max_g
	# 姿態
	pitch = asin(clampf(fwd.y, -1.0, 1.0))
	bank = atan2(-right.y, up.y)
	gamma = asin(clampf(v.y / maxf(v.length(), 1.0), -1.0, 1.0))
	var eff := clampf(q / 9000.0, 0.06, 1.0)
	if on_ground:
		_ground_step(dt, F, m, q, eff, gh)
	else:
		_air_step(dt, F, m, q, eff, a_st, b)
	heading = fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
	vs = v.y
	_warnings()

func _air_step(dt: float, F: Vector3, m: float, q: float, eff: float, a_st: float, b: Basis) -> void:
	_air_time += dt
	var pi := in_pitch
	var ri := in_roll
	var yi := in_yaw
	var V := maxf(v.length(), 30.0)
	var om := G0 * tan(clampf(bank, -1.3, 1.3)) / V
	var qt := 0.0
	var pt := 0.0
	if ap_on:
		qt = _ap_q
		pt = _ap_p
	else:
		if absf(pi) > 0.03:
			qt = pi * 0.2 * eff
			gamma_hold = gamma
		else:
			qt = clampf((gamma_hold - gamma) * 1.1, -0.07, 0.07)
		if absf(ri) > 0.03:
			pt = ri * 0.45 * eff
			bank_hold = bank
		else:
			var tb := clampf(bank_hold, -0.58, 0.58)
			if absf(tb) < deg_to_rad(4.0):
				tb = 0.0
			pt = clampf((tb - bank) * 1.4, -0.25, 0.25)
	qt += om * sin(bank) * cos(bank) * 0.9
	# 電傳保護：失速、坡度、俯仰限制
	if alpha > a_st - deg_to_rad(2.5) and not stall_prot_off:
		qt = minf(qt, -(alpha - (a_st - deg_to_rad(2.5))) * 2.5)
	if pitch > deg_to_rad(28.0):
		qt = minf(qt, 0.0)
	if pitch < deg_to_rad(-18.0):
		qt = maxf(qt, 0.0)
	if absf(bank) > deg_to_rad(66.0):
		pt = -signf(bank) * 0.2
	var rt := yi * 0.06 * eff + beta * 1.8 + om * cos(bank)
	var target := Vector3(qt, rt, pt)
	w = w.lerp(target, 1.0 - exp(-dt / 0.32))
	if turb > 0.0:
		w += Vector3(_rng.randf_range(-1, 1) * 0.06, _rng.randf_range(-1, 1) * 0.02, _rng.randf_range(-1, 1) * 0.12) * turb * dt * 4.0
	var nb := b * Basis(Vector3.RIGHT, w.x * dt) * Basis(Vector3.DOWN, w.y * dt) * Basis(Vector3.FORWARD, w.z * dt)
	global_basis = nb.orthonormalized()
	v += F / m * dt
	global_position += v * dt
	# 觸地
	var gh := ground_h()
	var a2 := global_position.y - M.GEAR_H - gh
	if a2 <= 0.0:
		_contact(gh)

func _contact(gh: float) -> void:
	var kind := surface_kind(global_position)
	var info := {"vs": v.y, "bank": rad_to_deg(bank), "pitch": rad_to_deg(pitch), "kind": kind, "speed": ias, "gear": gear_pos}
	if kind == "water":
		_crash("飛機迫降在海面上")
		return
	if gear_pos < 0.98:
		_crash("起落架沒有放下，機腹著地")
		return
	if v.y < -4.8:
		_crash("落地太重（下降率 %d 英尺／分），起落架受損" % int(-v.y * G.M2FT * 60.0))
		return
	if absf(bank) > deg_to_rad(11.0):
		_crash("落地時坡度太大，翼尖擦地")
		return
	if pitch < deg_to_rad(-2.0):
		_crash("機頭先著地，鼻輪斷裂")
		return
	if kind == "land" and ias > 25.0:
		_crash("沒有落在跑道上")
		return
	global_position.y = gh + M.GEAR_H
	on_ground = true
	_ground_time = 0.0
	theta = maxf(pitch, 0.0)
	yaw = atan2(-(-global_basis.z).x, -(-global_basis.z).z)
	last_touch = info
	touchdown.emit(v.y, info)
	v.y = 0.0
	w = Vector3.ZERO

func _ground_step(dt: float, F: Vector3, m: float, q: float, eff: float, gh: float) -> void:
	_ground_time += dt
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var speed := Vector2(v.x, v.z).dot(Vector2(fwd.x, fwd.z))
	var L := F.y + G0 * m       # 向上的氣動力（含推力分量）
	var N := maxf(0.0, G0 * m - L)
	var along := F.dot(fwd)
	var br := maxf(brakes, 1.0 if parking else 0.0)
	var fric := (0.015 + br * 0.42 * mu) * N
	if absf(speed) < 0.2 and absf(along) < fric:
		speed = 0.0
	else:
		speed += (along - signf(speed) * fric) / m * dt
	if speed < 0.0 and not reverse:
		speed = maxf(speed, -0.5)
	# 轉向（鼻輪＋方向舵）
	var yi := in_yaw
	var steer := yi * (0.32 if absf(speed) < 12.0 else clampf(5.0 / absf(speed), 0.03, 0.32))
	yaw -= steer * dt * signf(speed if absf(speed) > 0.5 else 1.0) * clampf(absf(speed) / 3.0, 0.0, 1.0)
	# 側風把飛機推偏
	var side := Vector3(-fwd.z, 0, fwd.x)
	var drift := (wind + _gust).dot(side) * 0.0025 * clampf(speed / 40.0, 0.0, 1.0)
	# 抬頭
	var pi := _ap_q * 4.0 if ap_on else in_pitch
	if pi > 0.05 and ias > 52.0:
		theta += pi * 0.055 * dt
	elif theta > 0.0:
		theta -= (0.05 if L < G0 * m * 0.8 else 0.012) * dt
		if pi < -0.05:
			theta -= 0.06 * dt
	theta = clampf(theta, 0.0, deg_to_rad(14.0))
	if theta > deg_to_rad(11.5) and speed > 30.0:
		tailstrike = true
	v = fwd * speed + side * drift * speed
	global_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, theta)
	global_position += v * dt
	global_position.y = gh + M.GEAR_H
	w = Vector3.ZERO
	if L > G0 * m and theta > deg_to_rad(2.0) and speed > 40.0:
		# 離地：之後交給空中物理
		on_ground = false
		v.y = maxf(v.y, 0.8)
		global_position.y += 0.5
		gamma_hold = asin(clampf(v.y / maxf(v.length(), 1.0), -1.0, 1.0))
		bank_hold = 0.0
		_air_time = 0.0
		callout.emit("liftoff")
		return
	# 衝出跑道
	var kind := surface_kind(global_position)
	if (kind == "land" or kind == "water") and absf(speed) > 20.0:
		_crash("衝出跑道")
	if absf(speed) < 0.3 and _ground_time > 2.0 and not _said.has("stopped") and last_touch.size() > 0:
		_said["stopped"] = true
		stopped_on_runway.emit()

var stall_prot_off := false

func _crash(reason: String) -> void:
	if crashed_flag:
		return
	crashed_flag = true
	ap_on = false
	v = Vector3.ZERO
	crashed.emit(reason)

# ── 警告與呼叫 ──
var warn := ""
func _warnings() -> void:
	warn = ""
	if crashed_flag:
		return
	if stall:
		warn = "stall"
	elif not on_ground:
		var sink := -v.y
		var look := global_position + Vector3(v.x, 0, v.z) * 12.0
		var th := world.terrain.height_at(look.x, look.z)
		if agl < 600.0 and sink > 0.0 and (agl / maxf(sink, 0.1) < 18.0) and not (gear_pos > 0.9 and flaps >= 2 and sink < 6.0):
			warn = "pullup"
		elif th > global_position.y - 120.0 and _air_time > 8.0:
			warn = "terrain"
		elif agl < 150.0 and gear_pos < 0.5 and sink > 1.0 and _air_time > 15.0:
			warn = "gear"
		elif ias * G.MS2KT > 360.0:
			warn = "overspeed"
		elif ias * G.MS2KT > FLAP_VMAX[flaps] + 5.0:
			warn = "flapspeed"
	if on_ground:
		var kt := ias * G.MS2KT
		if throttle > 0.6 and _ground_time > 1.0 and last_touch.is_empty():
			if kt > 80.0: _say_once("c80")
			if kt > VR * G.MS2KT - 6.0: _say_once("cv1")
			if kt > VR * G.MS2KT: _say_once("crotate")
	else:
		if _air_time > 2.0 and v.y > 1.5 and agl > 15.0 and last_touch.is_empty():
			_say_once("cposrate")
		var ft := agl * G.M2FT
		if v.y < -1.0 and gear_pos > 0.9:
			for k in [[1000, "c1000"], [500, "c500"], [200, "cmin"], [50, "c50"], [40, "c40"], [30, "c30"], [20, "c20"], [10, "c10"]]:
				if ft < k[0] and ft > k[0] - 40 * (1 if k[0] <= 50 else 4) and not _said.has(k[1]):
					_said[k[1]] = true
					callout.emit(k[1])

func _say_once(id: String) -> void:
	if not _said.has(id):
		_said[id] = true
		callout.emit(id)

func reset_callouts(keep_takeoff := true) -> void:
	for k in ["c1000", "c500", "cmin", "c50", "c40", "c30", "c20", "c10", "stopped"]:
		_said.erase(k)
	if not keep_takeoff:
		_said.clear()

# ── 自動駕駛 ──
var _ap_q := 0.0
var _ap_p := 0.0

func ap_engage(mode: String, dest: Dictionary = {}) -> void:
	ap_mode = mode
	if not dest.is_empty():
		ap_dest = dest
	ap_on = true
	ap_dep_hdg = heading
	ap_hdg = heading
	ap_alt = maxf(global_position.y, ground_h() + 450.0) if not on_ground else ap_cruise_alt
	ap_spd = clampf(ias, 110.0, CRUISE_SPD) if not on_ground else CRUISE_SPD
	_ap_i = 0.0
	if mode == "auto":
		if on_ground:
			ap_phase = "takeoff"
			ap_spd = CRUISE_SPD
		elif ap_dest.is_empty():
			ap_mode = "hold"
		else:
			ap_phase = "enroute"
	ap_changed.emit(true)

func ap_disengage() -> void:
	if ap_on:
		ap_on = false
		gamma_hold = gamma
		bank_hold = bank
		ap_changed.emit(false)

func _ap_speed(target: float, dt: float) -> void:
	var e := target - ias
	_ap_i = clampf(_ap_i + e * dt * 0.015, -0.3, 0.4)
	var base := 0.32 + clampf(gamma * 4.0, -0.3, 0.6) + float(flaps) * 0.06 + (0.06 if gear_down else 0.0)
	throttle = clampf(base + e * 0.05 + _ap_i, 0.0, 1.0)
	# 太快又在下降：打開減速板
	if not on_ground:
		spoilers = e < -6.0 and gamma < 0.01 and agl > 150.0

func _ap_fly(gamma_des: float, bank_des: float) -> void:
	_ap_q = clampf((gamma_des - gamma) * 0.9, -0.06, 0.06)
	_ap_p = clampf((bank_des - bank) * 1.2, -0.2, 0.2)
	in_yaw = 0.0
	if on_ground:
		_ap_q = (gamma_des - gamma) * 0.2

# 以目標升降率控制高度（約 12 秒收斂）
func _alt_gamma(alt_des: float, max_up := 12.0, max_dn := -11.0) -> float:
	var vsd := clampf((alt_des - global_position.y) * 0.08, max_dn, max_up)
	return asin(clampf(vsd / maxf(v.length(), 40.0), -0.3, 0.3))

func _hdg_bank(h_des: float, lim := 25.0) -> float:
	var e := G.angdiff(h_des, heading)
	return clampf(deg_to_rad(e) * 1.4, -deg_to_rad(lim), deg_to_rad(lim))

func terrain_ahead(dist: float, n := 8) -> float:
	var hm := 0.0
	var hv := Vector3(v.x, 0, v.z)
	if hv.length() < 1.0:
		hv = -global_basis.z
	hv = hv.normalized()
	for i in range(1, n + 1):
		var p := global_position + hv * dist * i / n
		hm = maxf(hm, world.terrain.height_at(p.x, p.z))
	return hm

func _autopilot(dt: float) -> void:
	if crashed_flag:
		return
	if ap_mode == "hold":
		var safe := terrain_ahead(5000.0) + 350.0
		_ap_fly(_alt_gamma(maxf(ap_alt, safe)), _hdg_bank(ap_hdg))
		_ap_speed(ap_spd, dt)
		ap_note = "保持航向 %03d°、高度 %s 英尺、速度 %d 節" % [int(ap_hdg), G.fmt_int(int(ap_alt * G.M2FT / 100.0) * 100), int(ap_spd * G.MS2KT)]
		return
	var rw := ap_dest
	if rw.is_empty():
		if ap_phase not in ["takeoff", "climb"]:
			ap_mode = "hold"
			ap_alt = maxf(ap_cruise_alt, global_position.y)
			ap_hdg = heading
			return
		rw = {"thr": global_position, "dir": -global_basis.z, "hdg": heading, "name": ""}
	var thr: Vector3 = rw.thr
	var dir: Vector3 = rw.dir
	var pos := global_position
	var rel := pos - thr
	var along := rel.dot(dir)                 # 負值＝還沒到跑道頭
	var xtrack := rel.dot(Vector3(-dir.z, 0, dir.x))
	var dist_thr := -along
	var field: float = thr.y
	match ap_phase:
		"takeoff":
			throttle = 1.0
			brakes = 0.0
			parking = false
			flaps = maxi(flaps, 1)
			spoilers = false
			reverse = false
			in_yaw = clampf(G.angdiff(ap_dep_hdg, heading) * 0.15, -1.0, 1.0)
			if ias > VR:
				_ap_q = 0.15
			else:
				_ap_q = 0.0
			ap_note = "自動起飛：推力全開，%d 節抬輪" % int(VR * G.MS2KT)
			if not on_ground:
				ap_phase = "climb"
		"climb":
			if agl > 30.0 and v.y > 1.0:
				gear_down = false
			if agl > 300.0 and ias > 88.0:
				flaps = 0
			spoilers = false
			var tgt := 92.0 if agl < 300.0 else (125.0 if agl < 900.0 else CRUISE_SPD)
			throttle = 0.95
			# 用俯仰控制速度（爬升推力固定）
			var g_des := clampf(0.1 + (ias - tgt) * 0.012, 0.03, 0.2)
			if ias < VR + 4.0:
				g_des = minf(g_des, 0.06)
			var hd: float = ap_dep_hdg if agl < 350.0 else _route_hdg(pos)
			hd = _terrain_avoid(hd)
			if pos.y >= ap_cruise_alt - 150.0:
				g_des = _alt_gamma(ap_cruise_alt)
				_ap_speed(CRUISE_SPD, dt)
			_ap_fly(g_des, _hdg_bank(hd, 22.0 if agl > 350.0 else 8.0))
			ap_note = "爬升到 %s 英尺" % G.fmt_int(int(ap_cruise_alt * G.M2FT / 100.0) * 100)
			if pos.y >= ap_cruise_alt - 60.0:
				ap_phase = "enroute"
				_plan_route()
		"enroute":
			if ap_wps.is_empty():
				_plan_route()
			var wp: Vector3 = ap_wps[0]
			var d_wp := Vector2(wp.x - pos.x, wp.z - pos.z).length()
			if ap_wps.size() > 1 and d_wp < 1500.0:
				ap_wps.pop_front()
				wp = ap_wps[0]
				d_wp = Vector2(wp.x - pos.x, wp.z - pos.z).length()
			var path := d_wp
			for i in range(ap_wps.size() - 1):
				path += Vector2((ap_wps[i + 1] as Vector3).x - (ap_wps[i] as Vector3).x, (ap_wps[i + 1] as Vector3).z - (ap_wps[i] as Vector3).z).length()
			var if_alt := field + 13000.0 * tan(deg_to_rad(3.0)) + 30.0
			var alt_des := minf(ap_cruise_alt, if_alt + maxf(0.0, path - 3000.0) * 0.06)
			alt_des = maxf(alt_des, maxf(terrain_ahead(6000.0), _terrain_to(wp)) + 380.0)
			var hd := G.bearing(pos, wp)
			hd = _terrain_avoid(hd)
			_ap_fly(_alt_gamma(alt_des, 12.0, -11.0), _hdg_bank(hd))
			gear_down = false
			var spd := CRUISE_SPD
			if path < 26000.0: spd = 118.0
			if path < 13000.0: spd = 103.0
			_ap_speed(spd, dt)
			if path < 13000.0 and ias < 118.0:
				flaps = maxi(flaps, 1)
			ap_note = "航向 %03d°，前往 %s，距離 %.1f 公里" % [int(hd), _dest_name(), (path + 13000.0) / 1000.0]
			if (ap_wps.size() == 1 and d_wp < 2000.0) or (dist_thr > 0.0 and dist_thr < 14500.0 and absf(xtrack) < 1500.0 and absf(G.angdiff(rw.hdg, heading)) < 50.0):
				ap_phase = "approach"
		"approach":
			var gs_alt := field + maxf(dist_thr, 0.0) * tan(deg_to_rad(3.0)) + M.GEAR_H
			var vgs := -ias * tan(deg_to_rad(3.0))
			var vsd := clampf(vgs + (gs_alt - pos.y) * 0.12, -12.0, 2.0)
			if pos.y < gs_alt - 20.0:
				vsd = maxf(vsd, 0.0)
			var gsg := asin(clampf(vsd / maxf(v.length(), 40.0), -0.3, 0.3))
			var intercept := clampf(-xtrack * 0.02, -35.0, 35.0)
			var hd: float = fposmod(rw.hdg + intercept, 360.0)
			_ap_fly(gsg, _hdg_bank(hd, 25.0 if absf(xtrack) > 300.0 else 12.0))
			var spd := VAPP if dist_thr < 7000.0 else 92.0
			_ap_speed(spd, dt)
			if ias < 106.0: flaps = maxi(flaps, 2)
			if dist_thr < 8000.0: gear_down = true
			if dist_thr < 6000.0 and ias < 93.0: flaps = 3
			ap_note = "進場：對準 %s 跑道 %s，下滑道 3°" % [_dest_name(), rw.name]
			if agl < 16.0 and dist_thr < 1200.0:
				ap_phase = "flare"
			if dist_thr < -400.0 and not on_ground:
				ap_phase = "goaround"
			if dist_thr > 16000.0 or (dist_thr < 6000.0 and absf(xtrack) > 900.0):
				ap_phase = "goaround"
		"flare":
			var g_des := asin(clampf(-0.9 / maxf(v.length(), 30.0), -0.2, 0.0))
			_ap_fly(g_des, _hdg_bank(rw.hdg + clampf(-xtrack * 0.02, -6.0, 6.0), 3.0))
			throttle = 0.0 if agl < 9.0 else 0.25
			ap_note = "拉平、收油門"
			if on_ground:
				ap_phase = "rollout"
		"rollout":
			throttle = 0.6 if ias > 40.0 else 0.0
			reverse = ias > 30.0
			spoilers = true
			brakes = 0.55 if ias > 8.0 else 1.0
			_ap_q = -0.05
			in_yaw = clampf(G.angdiff(rw.hdg, heading) * 0.08 - xtrack * 0.04, -1.0, 1.0)
			ap_note = "反推力、減速板、自動煞車"
			if ias < 2.0:
				throttle = 0.0
				reverse = false
				parking = true
				ap_phase = "done"
				ap_note = "已安全停妥"
		"goaround":
			throttle = 1.0
			flaps = 2
			_ap_fly(0.1, _hdg_bank(rw.hdg))
			if agl > 60.0: gear_down = false
			ap_note = "重飛！爬升後再進場一次"
			if pos.y > field + 700.0:
				ap_phase = "enroute"
				_plan_route()
		"done":
			throttle = 0.0
			parking = true

func _dest_name() -> String:
	return String(ap_dest.get("apt_short", ""))

func _route_hdg(pos: Vector3) -> float:
	if ap_dest.is_empty():
		return ap_dep_hdg
	if ap_wps.is_empty():
		_plan_route()
	return G.bearing(pos, ap_wps[0])

# 航路點：必要時先飛到側邊的「轉入點」，讓最後轉向五邊不超過約 90 度
var ap_wps: Array = []
func _plan_route() -> void:
	ap_wps.clear()
	if ap_dest.is_empty():
		return
	var thr: Vector3 = ap_dest.thr
	var dir: Vector3 = ap_dest.dir
	var perp := Vector3(-dir.z, 0, dir.x)
	var fix := thr - dir * 13000.0
	var rel := global_position - fix
	var along := rel.dot(dir)          # >0：在 fix 的跑道那一側
	var side := signf(rel.dot(perp))
	if side == 0.0:
		side = 1.0
	if along > -3000.0:
		ap_wps.append(fix - dir * 5000.0 + perp * side * 5500.0)
		ap_wps.append(fix - dir * 2500.0)
	ap_wps.append(fix)

func _terrain_to(wp: Vector3) -> float:
	var hm := 0.0
	var d := wp - global_position
	d.y = 0.0
	var n := clampi(int(d.length() / 800.0), 1, 30)
	for i in range(1, n + 1):
		var p := global_position + d * float(i) / n
		hm = maxf(hm, world.terrain.height_at(p.x, p.z))
	return hm

func _terrain_avoid(hd: float) -> float:
	# 前方 6 公里的山比現在高：先在原地盤旋爬升
	var hv := G.hdg_dir(hd)
	var top := 0.0
	for i in range(1, 9):
		var p := global_position + hv * 750.0 * i
		top = maxf(top, world.terrain.height_at(p.x, p.z))
	if top > global_position.y - 200.0:
		ap_note = "前方有高山，盤旋爬升中"
		return fposmod(heading + 35.0, 360.0)
	return hd

# ── 外觀 ──
var _strobe_t := 0.0
func _process(delta: float) -> void:
	if model == null:
		return
	var dt := delta
	_strobe_t += dt
	var fr: float = FLAP_DEG[0]
	var fi := int(floor(flap_pos))
	fr = lerpf(FLAP_DEG[fi], FLAP_DEG[mini(fi + 1, 3)], flap_pos - fi)
	var roll_c := w.z * 1.6 + (in_roll if not ap_on else _ap_p * 3.0) * 0.4
	var pitch_c := (in_pitch if not ap_on else _ap_q * 6.0)
	_rot("FlapR", deg_to_rad(fr))
	_rot("FlapL", deg_to_rad(fr))
	_rot("AilR", clampf(roll_c, -1, 1) * 0.35)
	_rot("AilL", -clampf(roll_c, -1, 1) * 0.35)
	_rot("ElevR", -clampf(pitch_c, -1, 1) * 0.35)
	_rot("ElevL", -clampf(pitch_c, -1, 1) * 0.35)
	_rot("SplR", -spoiler_pos * 0.8)
	_rot("SplL", -spoiler_pos * 0.8)
	var rud := model.get_node_or_null("Rudder") as Node3D
	if rud:
		rud.rotation = Vector3.ZERO
		rud.rotate_object_local(Vector3.UP, -clampf(in_yaw, -1, 1) * 0.4)
	for g in ["GearN", "GearL", "GearR"]:
		var gn := model.get_node_or_null(g) as Node3D
		if gn:
			gn.visible = gear_pos > 0.04
			if g == "GearN":
				gn.rotation.x = -(1.0 - gear_pos) * PI * 0.5
			else:
				gn.rotation.z = (1.0 if g == "GearL" else -1.0) * (1.0 - gear_pos) * PI * 0.5
	var st := fmod(_strobe_t, 1.2) < 0.06
	for s in ["StrobeR", "StrobeL"]:
		var n := model.get_node_or_null(s) as Node3D
		if n:
			n.visible = st and lights_on
	var bc := fmod(_strobe_t + 0.5, 1.0) < 0.12
	for s in ["BeaconT", "BeaconB"]:
		var n := model.get_node_or_null(s) as Node3D
		if n:
			n.visible = bc
	var ll := model.get_node_or_null("LandLight") as Node3D
	if ll:
		ll.visible = lights_on and gear_pos > 0.5

func _rot(nm: String, a: float) -> void:
	var n := model.get_node_or_null(nm) as Node3D
	if n:
		n.rotation = Vector3.ZERO
		n.rotate_object_local(Vector3.RIGHT, a)

# 抬頭顯示：盲降偏差（度）
func ils_dev(rw: Dictionary) -> Vector2:
	var rel := global_position - (rw.thr as Vector3)
	var along: float = rel.dot(rw.dir)
	var dist := maxf(-along, 50.0)
	var xt := rel.dot(Vector3(-rw.dir.z, 0, rw.dir.x))
	var loc := rad_to_deg(atan2(xt, dist))
	var gs := rad_to_deg(atan2(global_position.y - M.GEAR_H - (rw.thr as Vector3).y, dist)) - 3.0
	return Vector2(loc, gs)
