extends SceneTree
## Un salvataggio ricaricato deve rigiocare la stessa partita: si gioca IA contro IA registrando le
## decisioni, poi si rigioca con le decisioni precaricate (dopo var_to_str/str_to_var, come nel
## salvataggio su Firebase) e si confrontano le impronte.

const E = preload("res://scripts/core/engine.gd")
const SC = preload("res://scripts/data/scenarios.gd")
const H = preload("res://scripts/core/hexgrid.gd")

func _init() -> void:
	var ok := true
	for k in [0, 1, 2, 4, 7]:
		var menu = load("res://scripts/ui/menu.gd").new()
		menu.main = {"menu_state": {}}
		var sc: Dictionary = SC.LIST[k]
		var cfg := {"seed": 5 + k, "turns": 6, "sides": []}
		var i := 0
		for l in sc["lati"]:
			var ships := []
			var j := 0
			for id in l["navi"]:
				var h := H.from_label(6 + 28 * (i % 2), 8 + 6 * j + 10 * (i / 2))
				ships.append({"id": id, "hex": h, "face": 2 if i % 2 == 0 else 5, "speed": 8})
				j += 1
			cfg["sides"].append({"name": l["nome"], "ai": true, "level": 1 + (i % 3), "team": i, "ships": ships})
			i += 1
		var a = E.new()
		a.headless = true
		root.add_child(a)
		a.setup(cfg)
		await a.run()
		var acts = str_to_var(var_to_str(a.history))
		var cfg2 = str_to_var(var_to_str(cfg))
		var b = E.new()
		b.headless = true
		root.add_child(b)
		b.setup(cfg2)
		b.replay_queue = acts
		await b.run()
		var same: bool = a.fingerprint() == b.fingerprint()
		ok = ok and same
		print("SALVA %s: %s / %s %s" % [sc["id"], a.fingerprint(), b.fingerprint(), "UGUALI" if same else "DIVERSE"])
		menu.free()
	print("RISULTATO ", "OK" if ok else "ERRORE")
	quit()
