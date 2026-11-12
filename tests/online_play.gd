extends SceneTree
## Prova del gioco online: due istanze giocano una partita sul finto Firebase (tests/firebase_mock.py)
## con le decisioni prese dall'IA. SF_ROLE=host|guest, SF_CODEFILE=file per il codice della stanza.
## Alla fine ognuno stampa l'impronta della partita: devono coincidere.

const AIClass = preload("res://scripts/core/ai.gd")

var main
var t0 := 0
var ai

func _init() -> void:
	ai = AIClass.new()
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	t0 = Time.get_ticks_msec()
	_run()

func _wait(s: float) -> void:
	await create_timer(s).timeout

func _run() -> void:
	await _wait(0.5)
	var role := OS.get_environment("SF_ROLE")
	var cf := OS.get_environment("SF_CODEFILE")
	var menu = main.current
	menu._load_scenario(7)
	menu.st["turns"] = 2
	menu.st["sides"][1]["ctrl"] = 0
	menu.on_join = role != "host"
	menu._online_panel()
	menu.on_name.text = "Host" if role == "host" else "Ospite"
	if role == "host":
		menu.host_side = 0
		await menu._online_create()
		var code: String = main.lobby.get("code", "")
		print("SFTEST stanza ", code)
		var f := FileAccess.open(cf, FileAccess.WRITE)
		f.store_string(code)
		f.close()
		while true:
			var room: Dictionary = await main.net.room(code)
			if Net._as_dict(room.get("seats", {})).size() >= 2:
				break
			await _wait(0.5)
		await menu._online_start()
	else:
		var code := ""
		while code == "":
			if FileAccess.file_exists(cf):
				code = FileAccess.get_file_as_string(cf).strip_edges()
			await _wait(0.3)
		print("SFTEST ospite entra in ", code)
		menu.on_code.text = code
		await menu._online_join()
	while true:
		await process_frame
		if Time.get_ticks_msec() - t0 > 900000:
			print("SFTEST tempo scaduto")
			quit(2)
			return
		var view = main.current
		if view == null or not ("eng" in view) or view.eng == null:
			continue
		var e = view.eng
		e.anim = 50.0
		var req: Dictionary = view.req
		if not req.is_empty() and view.online != null and view.online._pending_mine:
			view._provide(ai.decide(e, int(req["side"]), req))
		if e.over:
			await _wait(0.5)
			print("SFTEST impronta ", view.online.n, " | ", e.fingerprint())
			quit(0)
			return
