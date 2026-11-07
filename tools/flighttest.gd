extends Node3D
# 無頭飛行測試：godot --headless --fixed-fps 60 --path . res://tools/flighttest.tscn -- --from=TPE --to=KHH
var world: World
var plane: Aircraft
var t := 0.0
var last_phase := ""
var log_t := 0.0
var done := false

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	world = World.new()
	add_child(world)
	world.setup("day", "clear", 0)
	print("world built ms=", Time.get_ticks_msec() - t0)
	plane = Aircraft.new()
	add_child(plane)
	plane.setup(world)
	var fa := G.airport(G.arg("from", "TPE"))
	var ta := G.airport(G.arg("to", "KHH"))
	var dep := G.runway(fa, G.best_dir(fa, world.terrain, true))
	var dst := G.runway(ta, G.best_dir(ta, world.terrain))
	dst["apt_short"] = ta.short
	if G.arg("mode") == "final":
		plane.place_on_final(dst, float(G.arg("dist", "9000")))
		plane.ap_engage("auto", dst)
		plane.ap_phase = "approach"
	else:
		plane.place_on_runway(dep)
		plane.ap_engage("auto", dst)
	plane.time_scale = float(G.arg("ts", "1"))
	plane.crashed.connect(func(r): print("CRASH t=%.0f %s" % [t, r]); done = true)
	plane.touchdown.connect(func(vs, info): print("TOUCHDOWN t=%.0f vs=%.2f info=%s" % [t, vs, info]))
	plane.callout.connect(func(id): print("callout ", id, " t=%.0f" % t))

func _physics_process(delta: float) -> void:
	if done or plane == null:
		return
	t += delta * plane.time_scale
	log_t += delta * plane.time_scale
	if plane.ap_phase != last_phase:
		last_phase = plane.ap_phase
		print("PHASE ", last_phase, " t=%.0f" % t)
	var dbg := G.arg("dbg", "")
	if dbg != "" and t >= float(dbg.split(",")[0]) and t <= float(dbg.split(",")[1]):
		print("  dbg t=%.2f gnd=%s agl=%.1f vs=%.1f pitch=%.1f bank=%.1f hdg=%.0f alpha=%.1f beta=%.1f w=%s ias=%.0f" % [t, plane.on_ground, plane.agl, plane.vs, rad_to_deg(plane.pitch), rad_to_deg(plane.bank), plane.heading, rad_to_deg(plane.alpha), rad_to_deg(plane.beta), plane.w, plane.ias*G.MS2KT])
	if log_t > 15.0:
		log_t = 0.0
		var p := plane.global_position
		print("t=%4.0f %s pos=(%.0f,%.0f) alt=%.0fm agl=%.0f ias=%.0fkt vs=%.1f hdg=%.0f pitch=%.1f bank=%.1f thr=%.2f fl=%d gear=%s alpha=%.1f note=%s" % [t, plane.ap_phase, p.x, p.z, p.y, plane.agl, plane.ias * G.MS2KT, plane.vs, plane.heading, rad_to_deg(plane.pitch), rad_to_deg(plane.bank), plane.throttle, plane.flaps, plane.gear_down, rad_to_deg(plane.alpha), plane.ap_note])
	if plane.ap_phase == "done" or t > float(G.arg("max", "900")):
		print("END t=%.0f phase=%s" % [t, plane.ap_phase])
		done = true
		get_tree().quit()
