extends Node
## 全域狀態：版本、機場、任務關卡、設定與進度存檔、單位換算。

signal toast(text: String, kind: String)

const APP_VERSION := "1.0.0"
const CALLSIGN := "小柯八八八"

# 經緯度 → 世界座標（公尺）。水平約 1:8 縮小台灣，北方是 -Z、東方是 +X。
const LON0 := 121.0
const LAT0 := 23.6
const KX := 12750.0
const KZ := 13875.0

const MS2KT := 1.94384
const M2FT := 3.28084

# 機場：跑道中心、跑道方向（度）、長度、標高（公尺）
const AIRPORTS := [
	{"id": "TPE", "name": "桃園國際機場", "short": "桃園", "lon": 121.233, "lat": 25.077, "hdg": 53.0, "len": 3000.0, "elev": 30.0, "rwy": ["05", "23"]},
	{"id": "TSA", "name": "臺北松山機場", "short": "松山", "lon": 121.552, "lat": 25.069, "hdg": 100.0, "len": 2600.0, "elev": 6.0, "rwy": ["10", "28"]},
	{"id": "RMQ", "name": "臺中國際機場", "short": "臺中", "lon": 120.621, "lat": 24.264, "hdg": 3.0, "len": 3000.0, "elev": 60.0, "rwy": ["36", "18"]},
	{"id": "KHH", "name": "高雄國際機場", "short": "高雄", "lon": 120.350, "lat": 22.577, "hdg": 92.0, "len": 3000.0, "elev": 9.0, "rwy": ["09", "27"]},
	{"id": "HUN", "name": "花蓮機場", "short": "花蓮", "lon": 121.617, "lat": 24.023, "hdg": 28.0, "len": 2700.0, "elev": 16.0, "rwy": ["03", "21"]},
	{"id": "TTT", "name": "臺東豐年機場", "short": "臺東", "lon": 121.102, "lat": 22.755, "hdg": 41.0, "len": 2400.0, "elev": 44.0, "rwy": ["04", "22"]},
	{"id": "MZG", "name": "澎湖馬公機場", "short": "澎湖", "lon": 119.628, "lat": 23.569, "hdg": 20.0, "len": 3000.0, "elev": 31.0, "rwy": ["02", "20"]},
]

# 城市（地圖標示與建築群）：經度、緯度、半徑（公尺）、大樓數
const CITIES := [
	["臺北", 121.52, 25.04, 2600.0, 900], ["新北", 121.46, 25.01, 1600.0, 300], ["基隆", 121.74, 25.13, 700.0, 120],
	["桃園", 121.30, 24.99, 1400.0, 260], ["新竹", 120.97, 24.80, 1100.0, 200], ["臺中", 120.67, 24.15, 2000.0, 520],
	["彰化", 120.54, 24.08, 800.0, 120], ["嘉義", 120.45, 23.48, 900.0, 140], ["臺南", 120.20, 23.00, 1500.0, 300],
	["高雄", 120.31, 22.63, 2100.0, 560], ["屏東", 120.49, 22.67, 800.0, 100], ["宜蘭", 121.75, 24.75, 800.0, 100],
	["花蓮", 121.60, 23.98, 700.0, 110], ["臺東", 121.14, 22.76, 700.0, 100], ["馬公", 119.57, 23.57, 500.0, 60],
]

# 關卡：from/to 機場、時段、天氣、事件
const LEVELS := [
	{"title": "起飛訓練", "desc": "在桃園機場起飛，爬升到 3,000 英尺。", "from": "TPE", "to": "", "mode": "takeoff", "time": "day", "weather": "clear", "events": [], "goal_alt": 3000},
	{"title": "降落訓練", "desc": "從高雄五邊進場開始，對準跑道平穩落地並停下來。", "from": "KHH", "to": "KHH", "mode": "landing", "time": "day", "weather": "clear", "events": []},
	{"title": "東部航線", "desc": "松山飛花蓮，越過中央山脈，欣賞太平洋海岸。", "from": "TSA", "to": "HUN", "mode": "route", "time": "day", "weather": "clear", "events": []},
	{"title": "雨中進場", "desc": "桃園飛高雄，目的地正在下大雨，能見度低、跑道濕滑。", "from": "TPE", "to": "KHH", "mode": "route", "time": "dusk", "weather": "rain", "events": ["rain"]},
	{"title": "雷雨胞", "desc": "臺中飛澎湖，海峽上空有雷雨胞，要繞過去。", "from": "RMQ", "to": "MZG", "mode": "route", "time": "day", "weather": "storm", "events": ["storm"]},
	{"title": "機上臨盆", "desc": "高雄飛松山，一位孕婦乘客可能要生了。", "from": "KHH", "to": "TSA", "mode": "route", "time": "day", "weather": "clear", "events": ["labor"]},
	{"title": "高血壓急症", "desc": "花蓮飛高雄，有長輩乘客血壓飆高。", "from": "HUN", "to": "KHH", "mode": "route", "time": "dusk", "weather": "cloudy", "events": ["hypertension"]},
	{"title": "寒流下雪", "desc": "臺東飛桃園，寒流來襲，高空結冰、桃園下雪。", "from": "TTT", "to": "TPE", "mode": "route", "time": "day", "weather": "snow", "events": ["snow"]},
	{"title": "心臟急救", "desc": "桃園飛臺東，一位乘客突然胸痛倒下。", "from": "TPE", "to": "TTT", "mode": "route", "time": "night", "weather": "clear", "events": ["cardiac"]},
	{"title": "颱風改降", "desc": "松山飛澎湖，颱風逼近，目的地可能關閉。", "from": "TSA", "to": "MZG", "mode": "route", "time": "day", "weather": "typhoon", "events": ["typhoon"]},
	{"title": "劫機危機", "desc": "高雄飛松山，機上有人企圖劫機。", "from": "KHH", "to": "TSA", "mode": "route", "time": "night", "weather": "clear", "events": ["hijack"]},
	{"title": "終極考驗", "desc": "桃園飛高雄，雷雨加上乘客急症，所有能力一次考驗。", "from": "TPE", "to": "KHH", "mode": "route", "time": "dusk", "weather": "storm", "events": ["storm", "cardiac"]},
]

const TIME_NAMES := {"day": "白天", "dusk": "黃昏", "night": "夜晚"}
const WEATHER_NAMES := {"clear": "晴朗", "cloudy": "多雲", "rain": "下雨", "storm": "雷雨", "typhoon": "颱風", "snow": "下雪"}
const EVENT_NAMES := {"rain": "大雨低能見度", "storm": "雷雨胞", "typhoon": "颱風改降", "snow": "寒流結冰", "labor": "孕婦臨盆", "hypertension": "高血壓", "cardiac": "心臟病發", "hijack": "劫機"}

# 本次飛行設定（由標題選單填入）
var flight: Dictionary = {}
var level_index := -1

# 設定
var quality := 1            # 0 低、1 中、2 高
var invert_pitch := false
var show_cabin := true
var api_key := ""
var ai_model := "gpt-5.4-mini"
var unlocked := 1
var stars: Dictionary = {}
var best: Dictionary = {}
var test_mode := false
var args: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	test_mode = args.has("test")
	load_progress()
	if args.has("unlock"):
		unlocked = LEVELS.size()

func arg(k: String, d := "") -> String:
	return String(args.get(k, d))

# ── 地理 ──
func geo(lon: float, lat: float) -> Vector2:
	return Vector2((lon - LON0) * KX, -(lat - LAT0) * KZ)

func airport(id: String) -> Dictionary:
	for a in AIRPORTS:
		if a.id == id:
			return a
	return {}

func apt_pos(a: Dictionary) -> Vector3:
	var p := geo(a.lon, a.lat)
	return Vector3(p.x, a.elev, p.y)

static func hdg_dir(h: float) -> Vector3:
	var r := deg_to_rad(h)
	return Vector3(sin(r), 0, -cos(r))

static func bearing(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)

static func angdiff(a: float, b: float) -> float:
	return fposmod(a - b + 180.0, 360.0) - 180.0

# 跑道兩端：落地方向 dir_i（0＝hdg 方向、1＝反方向）的跑道頭位置與方向
func runway(a: Dictionary, dir_i := 0) -> Dictionary:
	var h: float = a.hdg if dir_i == 0 else fposmod(a.hdg + 180.0, 360.0)
	var d := hdg_dir(h)
	var c := apt_pos(a)
	return {"hdg": h, "dir": d, "thr": c - d * a.len * 0.5, "end": c + d * a.len * 0.5, "center": c, "name": a.rwy[dir_i], "len": a.len}

# 依地形選跑道方向：進場（或起飛爬升）路徑上地形較低的那一端
func best_dir(a: Dictionary, terrain, takeoff := false) -> int:
	var best := 0
	var best_c := -1e9
	for i in 2:
		var rw := runway(a, i)
		var worst := 1e9
		for k in range(1, 15):
			var d := k * 1000.0
			var p: Vector3 = (rw.end + rw.dir * d) if takeoff else (rw.thr - rw.dir * d)
			var allow: float = rw.thr.y + (d * 0.07 if takeoff else d * tan(deg_to_rad(3.0)))
			worst = minf(worst, allow - terrain.height_at(p.x, p.z))
		if worst > best_c:
			best_c = worst
			best = i
	return best

func nearest_airports(p: Vector3, closed: Array = []) -> Array:
	var out: Array = []
	for a in AIRPORTS:
		var ap := apt_pos(a)
		out.append({"a": a, "dist": Vector2(ap.x - p.x, ap.z - p.z).length(), "brg": bearing(p, ap), "closed": a.id in closed})
	out.sort_custom(func(x, y): return x.dist < y.dist)
	return out

# ── 進度與設定 ──
func load_progress() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://progress.cfg") == OK:
		unlocked = int(cf.get_value("p", "unlocked", 1))
		stars = cf.get_value("p", "stars", {})
		best = cf.get_value("p", "best", {})
		quality = int(cf.get_value("s", "quality", 1))
		invert_pitch = bool(cf.get_value("s", "invert", false))
		show_cabin = bool(cf.get_value("s", "cabin", true))
		api_key = String(cf.get_value("s", "api_key", ""))
		ai_model = String(cf.get_value("s", "ai_model", "gpt-5.4-mini"))
	elif OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		quality = 0

func save_progress() -> void:
	var cf := ConfigFile.new()
	cf.set_value("p", "unlocked", unlocked)
	cf.set_value("p", "stars", stars)
	cf.set_value("p", "best", best)
	cf.set_value("s", "quality", quality)
	cf.set_value("s", "invert", invert_pitch)
	cf.set_value("s", "cabin", show_cabin)
	cf.set_value("s", "api_key", api_key)
	cf.set_value("s", "ai_model", ai_model)
	cf.save("user://progress.cfg")

func finish_level(i: int, st: int, score: int) -> void:
	if i < 0:
		return
	var k := str(i)
	stars[k] = maxi(int(stars.get(k, 0)), st)
	best[k] = maxi(int(best.get(k, 0)), score)
	if st > 0:
		unlocked = maxi(unlocked, mini(i + 2, LEVELS.size()))
	save_progress()

func is_touch() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") or args.has("touch")

func fmt_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
