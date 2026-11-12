extends SceneTree
## Screenshot (serve un display: xvfb-run).
## godot --path . -s tests/shot.gd -- modo secondi file.png [scenario] [larghezza] [altezza]
## modo: menu | ia (partita fra IA) | umano (il primo lato è umano) | regole | ssd | 2d

const H = preload("res://scripts/core/hexgrid.gd")
const SC = preload("res://scripts/data/scenarios.gd")

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var mode := a[0] if a.size() > 0 else "menu"
	var secs := float(a[1]) if a.size() > 1 else 4.0
	var out := a[2] if a.size() > 2 else "/tmp/shot.png"
	var scn := int(a[3]) if a.size() > 3 else 0
	var w := int(a[4]) if a.size() > 4 else 1920
	var h := int(a[5]) if a.size() > 5 else 1080
	DisplayServer.window_set_size(Vector2i(w, h))
	root.size = Vector2i(w, h)
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	if mode in ["ia", "umano", "ssd", "2d"]:
		var m = main.current
		m._load_scenario(scn)
		if mode != "ia":
			m.st["sides"][0]["ctrl"] = 0
		else:
			m.st["sides"][0]["ctrl"] = 3
		var cfg: Dictionary = m._config()
		cfg["seed"] = 11
		cfg["anim"] = 4.0
		main.start_game(cfg)
	elif mode == "regole":
		main.show_rules()
	await create_timer(secs).timeout
	var g = main.current
	if mode == "ssd":
		g._show_ssd()
		await create_timer(1.0).timeout
	if mode == "2d":
		g.board.set_top_view(true)
		await create_timer(1.0).timeout
	if a.size() > 6 and g != null and g.get("eng") != null:
		# avanza la partita fino alla richiesta voluta ("move" o "fire"), confermando il resto
		var want := a[6]
		var guard := 0
		while guard < 4000:
			guard += 1
			var t: String = g.req.get("type", "")
			if guard % 20 == 0: print("passo ", guard, " ", t, " ", g.eng.phase, " imp ", g.eng.imp, " fps ", Engine.get_frames_per_second())
			if t == want:
				break
			if t == "energy":
				g._provide(g.helper_ai.energy_for_side(g.eng, int(g.req["side"])) if false else g.helper_ai.decide(g.eng, int(g.req["side"]), g.req))
			elif t == "move":
				g._do_move("F")
			elif t == "fire":
				g._provide({"shots": [], "launch": []})
			await create_timer(0.05).timeout
		await create_timer(1.2).timeout
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out)
	print("SALVATO ", out, " ", img.get_size())
	quit()
