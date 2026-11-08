class_name Xiaoke
extends Node
## AI 機器人小柯：理解機長的話（內建關鍵字，或使用者自備 OpenAI 金鑰）、執行動作、語音辨識（瀏覽器）。

signal chat(who: String, text: String)
signal listening(on: bool)

var main
var http: HTTPRequest
var busy := false
var _cb_res
var _cb_err
var _cb_end

func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = 25.0
	add_child(http)
	http.request_completed.connect(_ai_done)

# ── 語音辨識（Chrome／Edge）──
func can_listen() -> bool:
	if not OS.has_feature("web"):
		return false
	var r = JavaScriptBridge.eval("!!(window.SpeechRecognition||window.webkitSpeechRecognition)", true)
	return bool(r)

func listen() -> void:
	if not can_listen():
		chat.emit("xiaoke", "這個瀏覽器不支援語音辨識，請改用 Chrome 或 Edge，或直接打字給我。")
		return
	JavaScriptBridge.eval("""
window.xkListen=function(ok,err,end){var R=window.SpeechRecognition||window.webkitSpeechRecognition;try{if(window.__xkSR){window.__xkSR.abort();}}catch(e){}
var r=new R();r.lang='zh-TW';r.interimResults=false;r.maxAlternatives=1;
r.onresult=function(e){ok(e.results[0][0].transcript);};r.onerror=function(e){err(e.error||'error');};r.onend=function(){end('');};
window.__xkSR=r;r.start();};
window.xkStop=function(){try{if(window.__xkSR){window.__xkSR.stop();}}catch(e){}};
""", true)
	_cb_res = JavaScriptBridge.create_callback(_on_sr)
	_cb_err = JavaScriptBridge.create_callback(_on_sr_err)
	_cb_end = JavaScriptBridge.create_callback(func(_a): listening.emit(false))
	var win = JavaScriptBridge.get_interface("window")
	win.xkListen(_cb_res, _cb_err, _cb_end)
	listening.emit(true)
	Snd.say("x_listen", true)

func stop_listen() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.xkStop)window.xkStop();", true)
	listening.emit(false)

func _on_sr(args: Array) -> void:
	listening.emit(false)
	var text := String(args[0]) if args.size() > 0 else ""
	if text.strip_edges() != "":
		ask(text)

func _on_sr_err(args: Array) -> void:
	listening.emit(false)
	var e := String(args[0]) if args.size() > 0 else ""
	if e == "not-allowed" or e == "service-not-allowed":
		chat.emit("xiaoke", "麥克風被封鎖了。請在網址列左邊允許使用麥克風，再按一次。")
	elif e == "no-speech":
		chat.emit("xiaoke", "我沒聽到聲音，請再說一次。")

# ── 理解 ──
func ask(text: String) -> void:
	chat.emit("captain", text)
	var t := text.replace(" ", "")
	var hit := _intent(t)
	if hit != "":
		_do(hit, t)
	elif G.api_key != "" and G.ai_consent:
		_ai(text)
	else:
		_reply("x_unknown")

func _has(t: String, words: Array) -> bool:
	for w in words:
		if t.contains(w):
			return true
	return false

func _intent(t: String) -> String:
	if _has(t, ["解除自動", "我來飛", "手動", "關閉自動", "取消自動"]): return "ap_off"
	if _has(t, ["自動駕駛", "幫我飛", "接手", "自動降落", "自動起飛", "你來飛"]): return "ap_on"
	if _has(t, ["塔台", "聯絡", "呼叫", "管制"]): return "tower"
	if _has(t, ["最近", "附近", "備降", "改降", "迫降", "哪裡降落", "醫院"]): return "nearest"
	if _has(t, ["天氣", "下雨", "颱風", "風向", "能見度"]): return "weather"
	if _has(t, ["地圖", "導航", "航線", "路線"]): return "map"
	if _has(t, ["客艙", "乘客", "機艙", "空服"]): return "cabin"
	if _has(t, ["醫生", "醫師", "護士", "護理"]): return "doctor"
	if _has(t, ["救護車", "救護"]): return "ambulance"
	if _has(t, ["燃油", "油量", "汽油", "油夠"]): return "fuel"
	if _has(t, ["高度", "速度", "多高", "多快", "還有多遠", "多久", "距離"]): return "status"
	if _has(t, ["怎麼降落", "降落", "落地", "進場"]): return "landing"
	if _has(t, ["起飛", "怎麼飛"]): return "takeoff"
	if _has(t, ["你是誰", "你好", "介紹", "哈囉", "嗨"]): return "who"
	if _has(t, ["防冰", "結冰"]): return "antiice"
	if _has(t, ["7500", "七五", "劫機"]): return "hijack"
	return ""

func _reply(line_id: String, extra := "") -> void:
	var ln: Array = Texts.LINES.get(line_id, ["xiaoke", extra])
	chat.emit("xiaoke", String(ln[1]) + (("\n" + extra) if extra != "" else ""))
	Snd.say(line_id, true)

func _do(intent: String, _t: String) -> void:
	match intent:
		"ap_on":
			main.engage_ap()
			_reply("x_ap_on")
		"ap_off":
			main.plane.ap_disengage()
			_reply("x_ap_off")
		"tower":
			chat.emit("xiaoke", "好的，我幫您聯絡塔台。")
			Snd.say_all(["x_tower_call", "cap_contact", "t_contact"])
			main.tower_context()
		"nearest":
			var lst: Array = G.nearest_airports(main.plane.global_position, main.director.closed)
			var s := ""
			for i in mini(3, lst.size()):
				var n: Dictionary = lst[i]
				s += "%s：%.1f 公里，航向 %03d°%s\n" % [n.a.name, n.dist / 1000.0, int(n.brg), "（關閉）" if n.closed else ""]
			main.hud.open_map(true)
			main.hud.offer_divert(lst)
			_reply("x_nearest", s.strip_edges())
			Snd.speak("最近的是" + String(lst[0].a.name) + "，距離" + str(int(lst[0].dist / 1000.0)) + "公里。")
		"weather":
			_reply("x_weather_good" if main.director.weather in ["clear", "cloudy"] else "x_weather_bad")
		"map":
			main.hud.open_map(true)
			_reply("x_map")
		"cabin":
			main.hud.show_cabin(true)
			_reply("x_cabin")
		"doctor":
			var ok: bool = main.event_action("doctor")
			if not ok:
				_reply("x_ok", "目前沒有需要醫師的乘客。")
		"ambulance":
			_reply("x_ambulance")
		"fuel":
			_reply("x_fuel", "剩餘燃油 %s 公斤。" % G.fmt_int(int(main.plane.fuel)))
		"status":
			var p: Aircraft = main.plane
			var s := "高度 %s 英尺，速度 %d 節，航向 %03d°，距離目的地 %.1f 公里。" % [G.fmt_int(int(p.global_position.y * G.M2FT / 10.0) * 10), int(p.ias * G.MS2KT), int(p.heading), main.dist_to_dest() / 1000.0]
			chat.emit("xiaoke", s)
			Snd.speak(s)
		"landing":
			_reply("x_landing_brief")
		"takeoff":
			_reply("x_takeoff_brief")
		"who":
			_reply("x_who")
		"antiice":
			main.plane.anti_ice = true
			_reply("co_antiice")
		"hijack":
			if not main.event_action("squawk"):
				_reply("x_ok", "應答機維持 2000，目前沒有異常。")

# ── ChatGPT（使用者自備金鑰）──
func _ai(text: String) -> void:
	if busy:
		return
	busy = true
	chat.emit("xiaoke", "（思考中……）")
	var p: Aircraft = main.plane
	var ctx := "飛機狀態：高度 %d 英尺、速度 %d 節、航向 %d 度、%s；目的地 %s，距離 %.1f 公里；天氣 %s；機上狀況：%s。" % [int(p.global_position.y * G.M2FT), int(p.ias * G.MS2KT), int(p.heading), "自動駕駛中" if p.ap_on else "手動飛行", main.dest_name(), main.dist_to_dest() / 1000.0, G.WEATHER_NAMES.get(main.director.weather, ""), main.event_summary()]
	var sys := "你是「小柯」，小柯航空客機上的 AI 飛行助理機器人，正在協助機長（玩家）。請用臺灣繁體中文、口語、60 字以內回答，語氣親切專業。若需要執行動作，在最後加上一個標籤：[動作:塔台] [動作:最近機場] [動作:自動駕駛] [動作:地圖] [動作:客艙]。" + ctx
	var body := {"model": G.ai_model, "input": [{"role": "system", "content": sys}, {"role": "user", "content": text}], "max_output_tokens": 300}
	var err := http.request("https://api.openai.com/v1/responses", ["Content-Type: application/json", "Authorization: Bearer " + G.api_key], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		busy = false
		_reply("x_unknown")

func _ai_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		chat.emit("xiaoke", "連不上 ChatGPT（代碼 %d），請檢查設定裡的金鑰。我先用內建功能幫你。" % code)
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	var out := ""
	if typeof(d) == TYPE_DICTIONARY:
		if d.has("output_text"):
			out = String(d.output_text)
		for o in d.get("output", []):
			if typeof(o) == TYPE_DICTIONARY and o.get("type", "") == "message":
				for c in o.get("content", []):
					if typeof(c) == TYPE_DICTIONARY and c.get("type", "") == "output_text":
						out += String(c.text)
	if out == "":
		_reply("x_unknown")
		return
	var act := ""
	var re := RegEx.create_from_string("\\[動作[:：](.+?)\\]")
	var m := re.search(out)
	if m:
		act = m.get_string(1)
		out = out.replace(m.get_string(0), "").strip_edges()
	chat.emit("xiaoke", out)
	Snd.speak(out)
	match act:
		"塔台": _do("tower", "")
		"最近機場": _do("nearest", "")
		"自動駕駛": main.engage_ap()
		"地圖": main.hud.open_map(true)
		"客艙": main.hud.show_cabin(true)
