extends SceneTree
## Partite automatiche fra IA: verifica che il motore arrivi in fondo senza errori.
## Uso: godot --headless --path . -s tests/autoplay.gd   (variabile N = numero di partite)

const E = preload("res://scripts/core/engine.gd")
const H = preload("res://scripts/core/hexgrid.gd")
const D = preload("res://scripts/data/sfb_data.gd")

func _init() -> void:
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 6
	var ids: Array = D.ships().keys()
	ids.sort()
	var stats := {"fine": 0, "vittoria": 0, "turni": 0}
	for g in n:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + g
		var a: String = ids[rng.randi() % ids.size()]
		var b: String = ids[rng.randi() % ids.size()]
		if g == 0:
			a = "fed_ca"; b = "kli_d7"
		var cfg := {"seed": 77 + g, "turns": 10, "sides": [
			{"name": "Alfa", "ai": true, "level": 3, "team": 0, "ships": [{"id": a, "hex": H.from_label(6, 15), "face": 2, "speed": 10}]},
			{"name": "Beta", "ai": true, "level": 2, "team": 1, "ships": [{"id": b, "hex": H.from_label(36, 15), "face": 5, "speed": 10}]}]}
		if g % 3 == 2:
			cfg["sides"].append({"name": "Gamma", "ai": true, "level": 2, "team": 2, "ships": [{"id": ids[(g * 7) % ids.size()], "hex": H.from_label(21, 3), "face": 3}, {"id": "kzi_cs", "hex": H.from_label(23, 3), "face": 3}]})
		var eng = E.new()
		eng.headless = true
		root.add_child(eng)
		eng.setup(cfg)
		print("avvio ", g); await eng.run()
		var line := "partita %d: %s vs %s -> %s (turno %d) " % [g, a, b, str(eng.result.get("winners", [])), eng.turn]
		for u in eng.units.values():
			if u["kind"] == "ship":
				line += " | %s %s ex=%d dmg=%d" % [u["id"], u["gone"] if u["gone"] != "" else "attiva", u["ex"], u["dmg_taken"]]
		print(line)
		stats["fine"] += 1
		if eng.result.get("why", "") == "vittoria":
			stats["vittoria"] += 1
		stats["turni"] += eng.turn
		eng.queue_free()
	print("RISULTATO ", stats)
	quit()
