extends Node
## 音樂、音效、引擎與環境循環聲、角色語音（預先產生的臺灣華語語音＋字幕佇列）與瀏覽器語音合成。

signal line_started(id: String, speaker: String, text: String)
signal line_finished(id: String)

const TRACKS := ["sky_theme", "cruise", "tension"]
const SFX := ["click", "chime", "seatbelt", "ding", "caution", "stall", "radio", "gear", "flaps", "touchdown", "crash", "applause", "siren", "fanfare", "fail", "baby", "beep", "whoop", "thunder"]
const LOOPS := ["engine", "whine", "wind", "rain", "rumble", "stall"]

var music := AudioStreamPlayer.new()
var voice := AudioStreamPlayer.new()
var callout_p := AudioStreamPlayer.new()
var pool: Array = []
var streams: Dictionary = {}
var loops: Dictionary = {}
var music_vol := 0.5
var sfx_vol := 0.8
var voice_vol := 1.0
var auto_voice := true
var tts_on := true
var _duck := 0.0
var _queue: Array = []
var _cur := ""
var _cur_end := 0.0
var _tts_voice := ""
var _music_name := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(music)
	add_child(voice)
	add_child(callout_p)
	voice.finished.connect(_voice_done)
	music.finished.connect(func(): if _music_name != "": play_music(_music_name))
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	for s in SFX + LOOPS:
		var path := "res://assets/sfx/%s.wav" % s
		if ResourceLoader.exists(path):
			streams[s] = load(path)
	for s in LOOPS:
		if not streams.has(s):
			continue
		var st: AudioStreamWAV = (streams[s] as AudioStreamWAV).duplicate()
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.get_length() * st.mix_rate) - 1
		var ap := AudioStreamPlayer.new()
		ap.stream = st
		ap.volume_db = -80.0
		add_child(ap)
		loops[s] = ap
	_load_settings()
	_pick_tts()

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		music_vol = float(cf.get_value("audio", "music", 0.5))
		sfx_vol = float(cf.get_value("audio", "sfx", 0.8))
		voice_vol = float(cf.get_value("audio", "voice", 1.0))
		auto_voice = bool(cf.get_value("audio", "auto_voice", true))
		tts_on = bool(cf.get_value("audio", "tts", true))
	_apply()

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "music", music_vol)
	cf.set_value("audio", "sfx", sfx_vol)
	cf.set_value("audio", "voice", voice_vol)
	cf.set_value("audio", "auto_voice", auto_voice)
	cf.set_value("audio", "tts", tts_on)
	cf.save("user://settings.cfg")

func _apply() -> void:
	music.volume_db = linear_to_db(maxf(music_vol, 0.001)) - 8.0 - _duck
	music.stream_paused = music_vol <= 0.001

func play_music(name: String) -> void:
	_music_name = name
	var path := "res://assets/music/%s.ogg" % name
	if not ResourceLoader.exists(path):
		return
	music.stream = load(path)
	_apply()
	music.play()

func stop_music() -> void:
	_music_name = ""
	music.stop()

func play(name: String, vol := 1.0, pitch := 1.0) -> void:
	if sfx_vol <= 0.001 or not streams.has(name):
		return
	for p in pool:
		var ap := p as AudioStreamPlayer
		if not ap.playing:
			ap.stream = streams[name]
			ap.volume_db = linear_to_db(maxf(sfx_vol * vol, 0.001))
			ap.pitch_scale = pitch
			ap.play()
			return

func set_loop(name: String, vol: float, pitch := 1.0) -> void:
	var ap: AudioStreamPlayer = loops.get(name, null)
	if ap == null:
		return
	var v := vol * sfx_vol
	if v < 0.005:
		if ap.playing:
			ap.stop()
		return
	ap.volume_db = linear_to_db(v)
	ap.pitch_scale = clampf(pitch, 0.3, 3.0)
	if not ap.playing:
		ap.play()

func stop_loops() -> void:
	for k in loops:
		(loops[k] as AudioStreamPlayer).stop()

# ── 角色語音 ──
func say(id: String, priority := false) -> void:
	if not Texts.LINES.has(id):
		push_warning("缺少台詞 " + id)
		return
	if priority:
		_queue.push_front(id)
		if _cur != "":
			voice.stop()
			_voice_done()
			return
	else:
		_queue.append(id)
	if _cur == "":
		_next()

# 組合播放：多段語音接續，字幕顯示整句
func say_combo(ids: Array, speaker: String, text: String) -> void:
	_queue.append({"ids": ids.duplicate(), "speaker": speaker, "text": text})
	if _cur == "":
		_next()

func say_all(ids: Array) -> void:
	for id in ids:
		say(id)

func clear_queue() -> void:
	_queue.clear()
	_combo.clear()
	voice.stop()
	if _cur != "":
		var c := _cur
		_cur = ""
		line_finished.emit(c)

func busy() -> bool:
	return _cur != "" or not _queue.is_empty()

func _next() -> void:
	if _queue.is_empty():
		_cur = ""
		return
	var item = _queue.pop_front()
	var id := ""
	if item is Dictionary:
		_combo = (item.ids as Array).duplicate()
		id = String(_combo.pop_front())
		_cur = "combo:" + id
		line_started.emit(_cur, item.speaker, item.text)
	else:
		id = String(item)
		_combo.clear()
		_cur = id
		var ln: Array = Texts.LINES[id]
		line_started.emit(id, ln[0], ln[1])
	_play_clip(id)

func _play_clip(id: String) -> void:
	var path := "res://assets/voice/%s.ogg" % id
	if voice_vol > 0.001 and ResourceLoader.exists(path):
		voice.stream = load(path)
		voice.volume_db = linear_to_db(maxf(voice_vol, 0.001))
		voice.play()
		_cur_end = 0.0
	else:
		# 沒有語音檔：依字數停留
		var ln: Array = Texts.LINES.get(id, ["", "　"])
		_cur_end = Time.get_ticks_msec() / 1000.0 + 0.6 + String(ln[1]).length() * 0.16

var _combo: Array = []

func _voice_done() -> void:
	if not _combo.is_empty():
		_play_clip(String(_combo.pop_front()))
		return
	var c := _cur
	_cur = ""
	if c != "":
		line_finished.emit(c)
	_next()

func callout(id: String) -> void:
	var path := "res://assets/voice/%s.ogg" % id
	if voice_vol <= 0.001 or not ResourceLoader.exists(path):
		return
	callout_p.stream = load(path)
	callout_p.volume_db = linear_to_db(maxf(voice_vol, 0.001))
	callout_p.play()

func _process(delta: float) -> void:
	if _cur != "" and _cur_end > 0.0 and Time.get_ticks_msec() / 1000.0 > _cur_end:
		_cur_end = 0.0
		_voice_done()
	var want := 14.0 if (voice.playing or callout_p.playing) else 0.0
	if absf(_duck - want) > 0.05:
		_duck = move_toward(_duck, want, delta * 30.0)
		_apply()

# ── 瀏覽器／系統語音合成（只用臺灣華語聲音）──
func _pick_tts() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	var best := ""
	var score := -1
	for vd in DisplayServer.tts_get_voices():
		var lang := String(vd.get("language", ""))
		var nm := String(vd.get("name", ""))
		var s := -1
		if lang.begins_with("zh_TW") or lang.begins_with("zh-TW") or lang.to_lower().contains("hant"):
			s = 5
			if nm.contains("Natural") or nm.contains("Online"):
				s = 9
			elif nm.contains("Google"):
				s = 8
		if s > score:
			score = s
			best = String(vd.get("id", ""))
	_tts_voice = best

func has_tts() -> bool:
	if _tts_voice == "":
		_pick_tts()
	return _tts_voice != ""

func speak(text: String, pitch := 1.0, rate := 1.0) -> void:
	if not tts_on or voice_vol <= 0.001 or not has_tts():
		return
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(text, _tts_voice, int(voice_vol * 100), pitch, rate)

func stop_speak() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_stop()
