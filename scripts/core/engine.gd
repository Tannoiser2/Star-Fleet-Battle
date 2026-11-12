class_name SFBEngine
extends Node
## Motore delle regole di Star Fleet Battles (Captain's Basic Set, livello «Assume Command»),
## senza dipendenze dalla grafica.
##
## Ogni turno: 1) ripartizione dell'energia (segreta e simultanea), 2) annuncio delle velocità e
## aggancio dei sensori, 3) 32 impulsi: movimento (navi secondo la tabella degli impulsi, armi
## autoguidate), impatti, lanci e fuoco diretto simultaneo, 4) fine turno.
##
## Ogni scelta passa da decide()/decide_all(): l'IA risponde subito; per le persone viene emesso
## decision_requested e si attende provide_decision(). Online le scelte viaggiano nel registro di
## mosse (OnlineSession): con lo stesso seme ogni dispositivo gioca la stessa partita, e un
## salvataggio è semplicemente configurazione + registro delle scelte.
##
## Richieste (req["type"]):
##  - "energy": {side, turn} -> {uid: {spd, ph, sh, gr, sr[6], w{idx: energia}, ov{idx: bool}, cl, fc}}
##  - "move":   {side, imp, uids} -> {uid: "F" | "L" | "R" | "SL" | "SR"}
##  - "fire":   {side, imp} -> {"shots": [[uid, widx, tuid, ov]], "launch": [[uid, kind, tuid]]}

const D = preload("res://scripts/data/sfb_data.gd")
const H = preload("res://scripts/core/hexgrid.gd")
const AI = preload("res://scripts/core/ai.gd")

signal changed
signal log_added(text: String)
signal decision_requested(req: Dictionary)
signal decision_provided(result)
signal game_ended(result: Dictionary)
signal fx(kind: String, data: Dictionary)

var config := {}
var sides: Array = []            # [{name, ai, level, team, col}]
var ais: Array = []
var online = null
var headless := false
var anim := 1.0
var abort := false
var replay_queue: Array = []     # decisioni da riapplicare (caricamento di un salvataggio)
var history: Array = []          # tutte le decisioni prese, in ordine
var rng := RandomNumberGenerator.new()

var units := {}                  # uid -> unità
var next_uid := 1
var turn := 0
var imp := 0
var phase := ""
var over := false
var result := {}
var log_lines: Array = []
var max_turns := 12
var events: Array = []           # eventi del turno per la vista (colpi, esplosioni)
var waiting_side := -1


func pname(s: int) -> String:
	return str(sides[s]["name"])


func log_msg(t: String) -> void:
	log_lines.append(t)
	if log_lines.size() > 400:
		log_lines.pop_front()
	log_added.emit(t)


# ---------------------------------------------------------------- impostazione

## config: {seed, turns, sides: [{name, ai, level, team, col, ships: [{id, hex: Vector2i, face}]}]}
func setup(cfg: Dictionary) -> void:
	config = cfg
	rng.seed = int(cfg.get("seed", 1))
	max_turns = int(cfg.get("turns", 12))
	sides.clear()
	ais.clear()
	units.clear()
	next_uid = 1
	for i in cfg["sides"].size():
		var sd: Dictionary = cfg["sides"][i]
		sides.append({"name": sd.get("name", "Giocatore %d" % (i + 1)), "ai": bool(sd.get("ai", false)),
			"level": int(sd.get("level", 2)), "team": int(sd.get("team", i)), "col": int(sd.get("col", i)), "vp": 0})
		var a = AI.new()
		a.level = int(sd.get("level", 2))
		ais.append(a)
		for sh in sd.get("ships", []):
			_add_ship(i, str(sh["id"]), sh["hex"], int(sh.get("face", 0)), int(sh.get("speed", 0)))


func _add_ship(side: int, id: String, hex: Vector2i, face: int, speed := 0) -> int:
	var d: Dictionary = D.ship(id)
	var u := {"uid": next_uid, "kind": "ship", "id": id, "side": side, "pos": hex, "face": face, "speed": speed,
		"name": str(d["n"]), "race": str(d["r"]), "alive": true, "gone": "", "straight": 99, "slip_ok": true,
		"moved": 0, "sys": {}, "max": {}, "sh_max": [], "sh": [], "sh_on": true, "gr": 0, "sr": [0, 0, 0, 0, 0, 0],
		"sen": 0, "scan": 0, "dc": 0, "ex": 0, "ex_max": int(d["ex"]), "batt": 0.0, "cap": 0.0,
		"weapons": [], "lock": true, "fc": true, "cloak": 0, "cloak_want": false, "cloak_t": 0,
		"shuttles": 0, "fighters": 0, "fig_kind": "", "dmg_taken": 0, "alloc": {}, "fired_any": false}
	for k in d["sys"]:
		u["sys"][k] = int(d["sys"][k])
		u["max"][k] = int(d["sys"][k])
	for v in d["s"]:
		u["sh"].append(int(v))
		u["sh_max"].append(int(v))
	u["batt"] = float(u["sys"].get("bt", 0))
	u["shuttles"] = int(u["sys"].get("sh", 0))
	if d.has("fig"):
		u["fighters"] = int(d["fig"][1])
		u["fig_kind"] = str(d["fig"][0])
	for a in d["arm"]:
		for n in int(a[2]):
			var w := {"t": str(a[0]), "arc": str(a[1]), "ok": true, "st": 0, "ov": 0, "fired": false, "ready": false}
			if w["t"] == "DRN":
				w["n"] = D.DRONES_PER_RACK
			if D.is_plasma(w["t"]):
				w["pt"] = w["t"].substr(2, 1)
			u["weapons"].append(w)
	# all'inizio della partita le armi pesanti sono scariche, i condensatori dei phaser pieni
	u["cap"] = cap_max(u)
	units[next_uid] = u
	next_uid += 1
	return int(u["uid"])


func data(u: Dictionary) -> Dictionary:
	return D.ship(str(u["id"]))


func cap_max(u: Dictionary) -> float:
	var c := 0.0
	for w in u["weapons"]:
		if w["ok"] and D.is_phaser(w["t"]):
			c += D.phaser_cost(w["t"])
	return c


func ships_of(side: int, alive_only := true) -> Array:
	var out := []
	for id in units:
		var u: Dictionary = units[id]
		if u["kind"] == "ship" and int(u["side"]) == side and (not alive_only or u["alive"]):
			out.append(u)
	return out


func live_ships() -> Array:
	var out := []
	for id in units:
		var u: Dictionary = units[id]
		if u["kind"] == "ship" and u["alive"]:
			out.append(u)
	return out


func enemies(a: int, b: int) -> bool:
	return int(sides[a]["team"]) != int(sides[b]["team"])


# ---------------------------------------------------------------- energia

func power(u: Dictionary) -> Dictionary:
	var warp := int(u["sys"].get("lw", 0)) + int(u["sys"].get("rw", 0)) + int(u["sys"].get("cw", 0))
	var impl := int(u["sys"].get("imp", 0))
	var apr := int(u["sys"].get("apr", 0))
	var bt := minf(float(u["batt"]), float(u["sys"].get("bt", 0)))
	return {"warp": warp, "imp": impl, "apr": apr, "batt": bt, "total": warp + impl + apr + bt}


func move_cost(u: Dictionary, spd: int) -> float:
	return spd * float(data(u)["mc"])


func max_speed(u: Dictionary) -> int:
	var p := power(u)
	var d := data(u)
	if d.get("sublight", false):
		return mini(int(floor(p["imp"] / float(d["mc"]))), 10)
	return mini(31, int(floor(p["warp"] / float(d["mc"]))) + (1 if p["imp"] > 0 else 0))


## Costo di un'arma pesante nel turno, data l'energia assegnata
func weapon_need(w: Dictionary) -> Array:
	# restituisce le energie ammesse per quest'arma nel turno: [scarica, standard, (sovraccarico...)]
	var t: String = w["t"]
	if t == "PHOT":
		if w["st"] == 0:
			return [0, 2]
		if w["st"] == 1:
			return [0, 2, 3, 4, 5, 6]
		return [0, 1, 2, 3, 4, 5]
	if t == "DISR":
		return [0, 2, 4]
	if D.is_plasma(t):
		var pt: String = w["pt"]
		if w["st"] >= 3:
			return [0, D.PL_HOLD[pt]] if D.PL_HOLD[pt] > 0 else [0]
		return [0, D.PL_ARM[pt][w["st"]]]
	return [0]


## Calcola il costo di una ripartizione; restituisce {tot, warp_need, ok}
func alloc_cost(u: Dictionary, a: Dictionary) -> Dictionary:
	var d := data(u)
	var tot := float(d["ls"])
	if a.get("fc", true):
		tot += 1.0
	if a.get("sh", true):
		tot += float(d["sc"])
	tot += 2.0 * int(a.get("gr", 0))
	for v in a.get("sr", []):
		tot += float(v)
	var mv := move_cost(u, int(a.get("spd", 0)))
	tot += mv
	tot += float(a.get("ph", 0.0))
	var phot := 0.0
	var wa: Dictionary = a.get("w", {})
	for k in wa:
		var w: Dictionary = u["weapons"][int(k)]
		tot += float(wa[k])
		if w["t"] == "PHOT":
			phot += float(wa[k])
	if a.get("cl", false) and d.has("cloak"):
		tot += float(d["cloak"])
	var p := power(u)
	var warp_need := phot + mv
	var warp_av := float(p["warp"]) + (1.0 if p["imp"] > 0 else 0.0)
	if d.get("sublight", false):
		warp_av = float(p["imp"])
	return {"tot": tot, "warp_need": warp_need, "ok": tot <= p["total"] + 0.001 and warp_need <= warp_av + 0.001,
		"avail": p["total"], "warp_av": warp_av}


## Applica la ripartizione (già validata e, se serve, ridotta)
func _apply_alloc(u: Dictionary, a: Dictionary) -> void:
	var d := data(u)
	a = a.duplicate(true)
	# riduzioni se si sfora: prima i rinforzi, poi la velocità, poi le armi
	var guard := 0
	while not alloc_cost(u, a)["ok"] and guard < 200:
		guard += 1
		var sr: Array = a.get("sr", [0, 0, 0, 0, 0, 0])
		var cut := false
		for i in 6:
			if int(sr[i]) > 0:
				sr[i] = int(sr[i]) - 1
				cut = true
				break
		a["sr"] = sr
		if cut:
			continue
		if int(a.get("gr", 0)) > 0:
			a["gr"] = int(a["gr"]) - 1
			continue
		if float(a.get("ph", 0.0)) > 0.0:
			a["ph"] = maxf(0.0, float(a["ph"]) - 1.0)
			continue
		if int(a.get("spd", 0)) > 0:
			a["spd"] = int(a["spd"]) - 1
			continue
		var wa: Dictionary = a.get("w", {})
		var cutw := false
		for k in wa:
			if float(wa[k]) > 0:
				wa.erase(k)
				cutw = true
				break
		if cutw:
			continue
		if a.get("cl", false):
			a["cl"] = false
			continue
		if a.get("sh", true):
			a["sh"] = false
			continue
		break
	var cost := alloc_cost(u, a)
	var p := power(u)
	# l'energia non usata ricarica le batterie; se si sfora la generazione si attinge alle batterie
	var gen := float(p["warp"] + p["imp"] + p["apr"])
	var batt := float(u["batt"])
	if cost["tot"] > gen:
		batt -= cost["tot"] - gen
	else:
		batt = minf(float(u["sys"].get("bt", 0)), batt + (gen - cost["tot"]))
	u["batt"] = maxf(0.0, batt)
	u["speed"] = clampi(int(a.get("spd", 0)), 0, max_speed(u))
	u["sh_on"] = bool(a.get("sh", true))
	u["gr"] = int(a.get("gr", 0)) if u["sh_on"] else 0
	var sr2: Array = a.get("sr", [0, 0, 0, 0, 0, 0])
	u["sr"] = [0, 0, 0, 0, 0, 0]
	if u["sh_on"]:
		for i in 6:
			u["sr"][i] = int(sr2[i]) if i < sr2.size() else 0
	u["fc"] = bool(a.get("fc", true))
	u["cap"] = minf(cap_max(u), float(u["cap"]) + float(a.get("ph", 0.0)))
	var want_cloak := bool(a.get("cl", false)) and d.has("cloak")
	if want_cloak != (u["cloak"] > 0):
		u["cloak_t"] = 5
	u["cloak_want"] = want_cloak
	var wa: Dictionary = a.get("w", {})
	for i in u["weapons"].size():
		var w: Dictionary = u["weapons"][i]
		w["fired"] = false
		w["ready"] = false
		if not w["ok"]:
			continue
		var e := float(wa.get(i, wa.get(str(i), 0)))
		match w["t"]:
			"PHOT":
				if w["st"] == 0:
					w["st"] = 1 if e >= 2 else 0
					w["ov"] = 0
				elif w["st"] == 1:
					if e >= 2:
						w["st"] = 2
						w["ov"] = int(e) - 2
						w["ready"] = true
					else:
						w["st"] = 0
				else:
					if e >= 1:
						w["ov"] = int(e) - 1
						w["ready"] = true
					else:
						w["st"] = 0
						w["ov"] = 0
			"DISR":
				w["ov"] = 1 if e >= 4 else 0
				w["ready"] = e >= 2
			"DRN":
				w["ready"] = int(w.get("n", 0)) > 0
			_:
				if D.is_plasma(w["t"]):
					var pt: String = w["pt"]
					if w["st"] >= 3:
						if e >= D.PL_HOLD[pt]:
							w["ready"] = true
						else:
							w["st"] = 0
					else:
						if e >= D.PL_ARM[pt][w["st"]] and e > 0:
							w["st"] += 1
							w["ready"] = w["st"] >= 3
						else:
							w["st"] = 0
				elif D.is_phaser(w["t"]):
					w["ready"] = true


# ---------------------------------------------------------------- decisioni

var _got := false
var _got_val = null


func provide_decision(r) -> void:
	_got = true
	_got_val = r
	decision_provided.emit(r)


## Chiede una decisione alla persona: la risposta può arrivare anche subito, durante l'emissione
func ask_human(r: Dictionary):
	_got = false
	_got_val = null
	decision_requested.emit(r)
	if not _got:
		await decision_provided
	_got = false
	return _got_val


func decide(side: int, req: Dictionary):
	var rr: Array = await decide_all([side], [req])
	return rr[0]


func decide_all(ss: Array, reqs: Array) -> Array:
	var res := []
	if not replay_queue.is_empty():
		for i in ss.size():
			var r = replay_queue.pop_front() if not replay_queue.is_empty() else null
			if r == null:
				r = ais[ss[i]].decide(self, ss[i], reqs[i])
			res.append(r)
			history.append(r)
		return res
	if online != null:
		res = await online.decide_all(self, ss, reqs)
		for r in res:
			history.append(r)
		return res
	for i in ss.size():
		var s: int = ss[i]
		var r = null
		if sides[s]["ai"] or headless:
			r = ais[s].decide(self, s, reqs[i])
		else:
			waiting_side = s
			r = await ask_human(reqs[i])
			waiting_side = -1
			if r == null:
				r = ais[s].decide(self, s, reqs[i])
		res.append(r)
		history.append(r)
	return res


func _pace(sec: float) -> void:
	if headless or not replay_queue.is_empty() or (online != null and online.catchup):
		return
	await get_tree().create_timer(sec / maxf(0.1, anim)).timeout


# ---------------------------------------------------------------- partita

func run() -> void:
	log_msg("Inizia la battaglia: %d turni al massimo." % max_turns)
	changed.emit()
	for t in range(1, max_turns + 1):

		turn = t
		await _turn()
		if over or abort:
			return
	_finish("limite")


func _turn() -> void:
	events.clear()
	# 1. ripartizione dell'energia
	phase = "energia"
	imp = 0
	changed.emit()
	var ss := []
	var reqs := []
	for s in sides.size():
		if not ships_of(s).is_empty():
			ss.append(s)
			reqs.append({"type": "energy", "side": s, "turn": turn})
	var rr: Array = await decide_all(ss, reqs)
	if abort:
		return
	for i in ss.size():
		var al = rr[i]
		if not (al is Dictionary):
			al = {}
		for u in ships_of(ss[i]):
			var a = al.get(u["uid"], al.get(str(u["uid"]), null))
			if a == null:
				a = ais[ss[i]].energy_for(self, u)
			u["alloc"] = a
			_apply_alloc(u, a)
	# 2. velocità e aggancio dei sensori
	phase = "velocita"
	for u in live_ships():
		var sv := _track(u, "sen")
		u["lock"] = sv >= 6 or rng.randi_range(1, 6) <= sv
		if not u["fc"]:
			u["lock"] = false
	var txt := []
	for u in live_ships():
		txt.append("%s %d" % [u["name"], u["speed"]])
	log_msg("Turno %d - velocità: %s" % [turn, ", ".join(txt)])
	changed.emit()
	await _pace(0.6)
	# 3. impulsi
	phase = "impulsi"
	for i in range(1, 33):
		imp = i
		await _impulse()
		if over or abort:
			return
	# 4. fine del turno
	phase = "fine"
	for id in units.keys():
		var u: Dictionary = units.get(id, {})
		if u.is_empty():
			continue
		if u["kind"] == "drone":
			u["end"] -= 1
			if u["end"] <= 0:
				_remove(id, "esaurito")
		elif u["kind"] == "ship" and u["alive"]:
			for w in u["weapons"]:
				if w["t"] == "DISR":
					w["ready"] = false
				if w["t"] == "PHOT" and w["st"] == 2 and not w["fired"]:
					pass
	_check_end()
	changed.emit()


func _track(u: Dictionary, k: String) -> int:
	var arr: Array = data(u)[k]
	return int(arr[mini(int(u[k]), arr.size() - 1)])


func moves_this_impulse(spd: int, i: int) -> bool:
	if spd <= 0:
		return false
	return int(floor(i * spd / 32.0)) > int(floor((i - 1) * spd / 32.0))


func _impulse() -> void:
	# occultamento: dissolvenza in 5 impulsi
	for u in live_ships():
		if u["cloak_t"] > 0:
			u["cloak_t"] -= 1
			if u["cloak_t"] == 0:
				u["cloak"] = 1 if u["cloak_want"] else 0
				log_msg("%s %s." % [u["name"], "scompare sotto l'occultamento" if u["cloak"] else "riappare dall'occultamento"])
	# A. movimento delle navi
	var by_side := {}
	for u in live_ships():
		if moves_this_impulse(int(u["speed"]), imp):
			if not by_side.has(u["side"]):
				by_side[u["side"]] = []
			by_side[u["side"]].append(u["uid"])
	var moved := false
	if not by_side.is_empty():
		var ss := []
		var reqs := []
		for s in by_side:
			ss.append(s)
			reqs.append({"type": "move", "side": s, "imp": imp, "uids": by_side[s]})
		var rr: Array = await decide_all(ss, reqs)
		if abort:
			return
		for i in ss.size():
			var mv = rr[i] if rr[i] is Dictionary else {}
			for uid in reqs[i]["uids"]:
				var act = mv.get(uid, mv.get(str(uid), "F"))
				_move_ship(units[uid], str(act))
		moved = true
	# navette e caccia: si muovono da sole
	for id in units.keys():
		var u: Dictionary = units.get(id, {})
		if u.get("kind", "") == "shut" and moves_this_impulse(int(u["speed"]), imp):
			_move_shuttle(u)
			moved = true
	# armi autoguidate
	for id in units.keys():
		var u: Dictionary = units.get(id, {})
		if u.get("kind", "") in ["drone", "plasma"] and moves_this_impulse(int(u["speed"]), imp):
			_move_seeker(u)
			moved = true
	if moved:
		changed.emit()
		await _pace(0.12)
	# B. impatti
	await _impacts()
	if over:
		return
	# C. fuoco (lanci e fuoco diretto), simultaneo
	var fs := []
	var freqs := []
	for s in sides.size():
		if _can_act(s):
			fs.append(s)
			freqs.append({"type": "fire", "side": s, "imp": imp})
	if not fs.is_empty():
		var fr: Array = await decide_all(fs, freqs)
		if abort:
			return
		var all_shots := []
		for i in fs.size():
			var f = fr[i] if fr[i] is Dictionary else {}
			for l in f.get("launch", []):
				_launch(fs[i], l)
			for sh in f.get("shots", []):
				all_shots.append([fs[i], sh])
		_shuttle_fire(all_shots)
		if not all_shots.is_empty():
			await _resolve_fire(all_shots)
	else:
		var auto := []
		_shuttle_fire(auto)
		if not auto.is_empty():
			await _resolve_fire(auto)
	_check_end()


## Il lato ha qualcosa di sensato da fare in questo impulso? (un colpo con danni attesi, un lancio a
## portata, una minaccia vicina). Solo allora si chiede la decisione: meno attese, anche online.
func _can_act(s: int) -> bool:
	for u in ships_of(s):
		if not u["fc"] or u["cloak"] > 0 or u["cloak_t"] > 0:
			continue
		for x in units.values():
			if x.get("kind", "") in ["drone", "plasma"] and int(x["target"]) == int(u["uid"]) and H.dist(x["pos"], u["pos"]) <= 4:
				return true
		if can_launch_shuttle(u):
			for e in live_ships():
				if enemies(s, e["side"]) and H.dist(u["pos"], e["pos"]) <= 15:
					return true
		for i in u["weapons"].size():
			if not weapon_usable(u, i):
				continue
			var w: Dictionary = u["weapons"][i]
			for tid in targets_for(u, i):
				var t: Dictionary = units[tid]
				if t["kind"] != "ship":
					if D.is_phaser(w["t"]) and H.dist(u["pos"], t["pos"]) <= 3:
						return true
					continue
				var er := eff_range(u, t)
				var r := H.dist(u["pos"], t["pos"])
				if D.is_phaser(w["t"]) and D.phaser_damage(w["t"], 1, er) > 0 and (er <= 10 or imp >= 30):
					return true
				if w["t"] == "PHOT" and (er <= 12 or imp >= 31):
					return true
				if w["t"] == "DISR" and (er <= 22 or imp >= 32):
					return true
				if (D.is_plasma(w["t"]) or w["t"] == "DRN") and r <= 16:
					return true
	return false


func can_launch_shuttle(u: Dictionary) -> bool:
	return u["alive"] and (int(u["fighters"]) > 0 or (int(u["shuttles"]) > 0 and int(u["sys"].get("sh", 0)) > 0)) and u["cloak"] == 0


func weapon_usable(u: Dictionary, i: int) -> bool:
	var w: Dictionary = u["weapons"][i]
	if not w["ok"] or w["fired"] or not w["ready"]:
		return false
	if D.is_phaser(w["t"]) and float(u["cap"]) < D.phaser_cost(w["t"]) - 0.001:
		return false
	if w["t"] == "DRN" and int(w.get("n", 0)) <= 0:
		return false
	return true


## Distanza effettiva (scanner, aggancio, occultamento)
func eff_range(u: Dictionary, t: Dictionary) -> int:
	var r := H.dist(u["pos"], t["pos"])
	var lock: bool = u["lock"]
	if t.get("kind", "") == "ship" and (t["cloak"] > 0 or t["cloak_t"] > 0):
		lock = false
		r += 5
	if not lock:
		r *= 2
	return r + _track(u, "scan")


func targets_for(u: Dictionary, i: int) -> Array:
	var w: Dictionary = u["weapons"][i]
	var out := []
	var arcs: Array = D.ARCS.get(w["arc"], D.ARCS["360"])
	var seeking: bool = w["t"] == "DRN" or D.is_plasma(w["t"])
	for id in units:
		var t: Dictionary = units[id]
		if id == u["uid"] or not t.get("alive", true):
			continue
		if not enemies(u["side"], t["side"]):
			continue
		var k: String = t["kind"]
		if seeking and k != "ship" and k != "shut":
			continue
		if (k == "drone" or k == "plasma") and not D.is_phaser(w["t"]):
			continue
		if k == "ship" and seeking and (t["cloak"] > 0 or not u["lock"]):
			continue
		var rel := H.rel_bearing(u["pos"], u["face"], t["pos"])
		if t["pos"] != u["pos"] and not H.in_arc(arcs, rel):
			continue
		var r := H.dist(u["pos"], t["pos"])
		if seeking:
			if r > (30 if D.is_plasma(w["t"]) else 40):
				continue
		else:
			var er := eff_range(u, t)
			var ov := int(w.get("ov", 0)) > 0
			if w["t"] == "PHOT" and r == 0 and not ov:
				continue
			if w["t"] == "DISR" and r == 0 and not ov:
				continue
			if ov and r > 8:
				continue
			if er > D.max_range(w["t"]) and not (ov and r <= 8):
				continue
		out.append(id)
	return out


# ---------------------------------------------------------------- movimento

func turn_mode_of(u: Dictionary) -> int:
	return D.turn_mode(str(data(u)["tm"]), int(u["speed"]))


func legal_moves(u: Dictionary) -> Array:
	var out := ["F"]
	if int(u["straight"]) >= turn_mode_of(u):
		out += ["L", "R"]
	if u["slip_ok"]:
		out += ["SL", "SR"]
	return out


func _move_ship(u: Dictionary, act: String) -> void:
	if not u["alive"]:
		return
	if not (act in legal_moves(u)):
		act = "F"
	var f: int = u["face"]
	var dirn := f
	match act:
		"L":
			f = posmod(f - 1, 6)
			dirn = f
			u["straight"] = 0
			u["slip_ok"] = true
		"R":
			f = posmod(f + 1, 6)
			dirn = f
			u["straight"] = 0
			u["slip_ok"] = true
		"SL":
			dirn = posmod(f - 1, 6)
			u["straight"] = int(u["straight"]) + 1
			u["slip_ok"] = false
		"SR":
			dirn = posmod(f + 1, 6)
			u["straight"] = int(u["straight"]) + 1
			u["slip_ok"] = false
		_:
			u["straight"] = int(u["straight"]) + 1
			u["slip_ok"] = true
	u["prev"] = u["pos"]
	u["pos"] = H.neighbor(u["pos"], dirn)
	u["face"] = f
	u["moved"] = int(u["moved"]) + 1
	if not H.on_map(u["pos"]):
		u["alive"] = false
		u["gone"] = "disimpegnata"
		log_msg("%s (%s) esce dalla mappa e si disimpegna." % [u["name"], pname(u["side"])])
		fx.emit("gone", {"uid": u["uid"]})
		_drop_seekers_on(u["uid"])


func _move_seeker(s: Dictionary) -> void:
	var t: Dictionary = units.get(s["target"], {})
	if t.is_empty() or not t.get("alive", false):
		_remove(s["uid"], "senza bersaglio")
		return
	s["prev"] = s["pos"]
	if s["pos"] == t["pos"]:
		return
	var d := H.step_toward(s["pos"], s["face"], t["pos"], true)
	s["face"] = d
	s["pos"] = H.neighbor(s["pos"], d)
	s["dist"] = int(s["dist"]) + 1
	if s["kind"] == "plasma":
		if D.plasma_strength(s["pt"], int(s["dist"])) - int(s["red"]) <= 0:
			_remove(s["uid"], "dissolto")


func _move_shuttle(s: Dictionary) -> void:
	var best = null
	var bd := 9999
	for e in live_ships():
		if enemies(s["side"], e["side"]) and e["cloak"] == 0:
			var dd := H.dist(s["pos"], e["pos"])
			if dd < bd:
				bd = dd
				best = e
	if best == null:
		return
	var tgt: Vector2i = best["pos"]
	# resta a 2 esagoni dal bersaglio, girandogli attorno
	if bd <= 2:
		var away := posmod(H.dir_toward(best["pos"], s["pos"]) + 1, 6)
		tgt = H.neighbor(H.neighbor(best["pos"], away), away)
	var d := H.step_toward(s["pos"], s["face"], tgt, true)
	s["face"] = d
	s["prev"] = s["pos"]
	s["pos"] = H.neighbor(s["pos"], d)
	if not H.on_map(s["pos"]):
		_remove(s["uid"], "fuori mappa")


func _drop_seekers_on(uid: int) -> void:
	for id in units.keys():
		var x: Dictionary = units.get(id, {})
		if x.get("kind", "") in ["drone", "plasma"] and int(x["target"]) == uid:
			_remove(id, "senza bersaglio")


func _remove(id: int, why := "") -> void:
	if units.has(id):
		var x: Dictionary = units[id]
		if x["kind"] == "ship":
			return
		units.erase(id)
		fx.emit("remove", {"uid": id, "why": why})


# ---------------------------------------------------------------- lanci

func _launch(side: int, l: Array) -> void:
	var u: Dictionary = units.get(int(l[0]), {})
	if u.is_empty() or not u["alive"] or int(u["side"]) != side:
		return
	var kind := str(l[1])
	if kind == "shut":
		if not can_launch_shuttle(u):
			return
		var fig := int(u["fighters"]) > 0
		if fig:
			u["fighters"] = int(u["fighters"]) - 1
		else:
			u["shuttles"] = int(u["shuttles"]) - 1
		var s := {"uid": next_uid, "kind": "shut", "side": side, "pos": u["pos"], "face": u["face"],
			"speed": 15 if fig else 6, "hp": 8 if fig else 6, "alive": true, "from": u["uid"],
			"name": ("Caccia " + str(u["fig_kind"])) if fig else "Navetta d'assalto", "fired": -1, "race": u["race"]}
		units[next_uid] = s
		next_uid += 1
		log_msg("%s lancia %s." % [u["name"], "un caccia" if fig else "una navetta d'assalto"])
		fx.emit("launch", {"uid": s["uid"], "from": u["uid"]})
		return
	var wi := int(kind)
	if wi < 0 or wi >= u["weapons"].size() or not weapon_usable(u, wi):
		return
	var tid := int(l[2])
	if not (tid in targets_for(u, wi)):
		return
	var w: Dictionary = u["weapons"][wi]
	var s2 := {"uid": next_uid, "side": side, "pos": u["pos"], "face": H.dir_toward(u["pos"], units[tid]["pos"]),
		"target": tid, "dist": 0, "alive": true, "from": u["uid"], "prev": u["pos"], "race": u["race"]}
	if w["t"] == "DRN":
		s2.merge({"kind": "drone", "speed": D.DRONE_SPEED, "hp": D.DRONE_HP, "end": D.DRONE_END, "name": "Drone"})
		w["n"] = int(w["n"]) - 1
	else:
		s2.merge({"kind": "plasma", "speed": 32, "pt": w["pt"], "red": 0, "name": "Plasma " + str(w["pt"])})
		w["st"] = 0
	w["fired"] = true
	units[next_uid] = s2
	next_uid += 1
	log_msg("%s lancia %s contro %s." % [u["name"], "un drone" if w["t"] == "DRN" else "un siluro al plasma " + str(w["pt"]), units[tid]["name"]])
	fx.emit("launch", {"uid": s2["uid"], "from": u["uid"]})


func _shuttle_fire(shots: Array) -> void:
	for id in units.keys():
		var s: Dictionary = units.get(id, {})
		if s.get("kind", "") != "shut" or int(s["fired"]) == turn:
			continue
		var best = null
		var bd := 4
		for t in units.values():
			if t.get("alive", true) and t["kind"] in ["ship", "shut", "drone"] and enemies(s["side"], t["side"]):
				if t["kind"] == "ship" and (t["cloak"] > 0 or t["cloak_t"] > 0):
					continue
				var dd := H.dist(s["pos"], t["pos"])
				if dd < bd:
					bd = dd
					best = t
		if best != null and (bd <= 2 or imp >= 30):
			s["fired"] = turn
			shots.append([s["side"], [id, -1, best["uid"], false]])


# ---------------------------------------------------------------- fuoco diretto

func _die() -> int:
	return rng.randi_range(1, 6)


func _resolve_fire(shots: Array) -> void:
	# volley: [bersaglio, lato che spara] -> {scudo: danni}
	var volleys := {}
	var lines := []
	for e in shots:
		var side: int = e[0]
		var sh: Array = e[1]
		var u: Dictionary = units.get(int(sh[0]), {})
		var tid := int(sh[2])
		var t: Dictionary = units.get(tid, {})
		if u.is_empty() or t.is_empty():
			continue
		var dmg := 0
		var wname := ""
		var hit := false
		if u["kind"] == "shut":
			var rr := H.dist(u["pos"], t["pos"])
			dmg = D.phaser_damage("PH3", _die(), rr)
			wname = "PH-3"
			hit = dmg > 0
		else:
			var wi := int(sh[1])
			if wi < 0 or wi >= u["weapons"].size() or not weapon_usable(u, wi) or not (tid in targets_for(u, wi)):
				continue
			if not u["alive"] or u["cloak"] > 0 or not u["fc"]:
				continue
			var w: Dictionary = u["weapons"][wi]
			var er := eff_range(u, t)
			var tr := H.dist(u["pos"], t["pos"])
			wname = str(D.WSHORT[w["t"]])
			w["fired"] = true
			if D.is_phaser(w["t"]):
				u["cap"] = float(u["cap"]) - D.phaser_cost(w["t"])
				dmg = D.phaser_damage(w["t"], _die(), er)
				hit = dmg > 0
			elif w["t"] == "PHOT":
				var ov := int(w["ov"]) > 0
				var c := D.col_index(D.PHOT_COLS, er if not ov else mini(er, tr if er > 8 else er))
				var need: int = (D.PHOT_HIT_OV[c] if ov else D.PHOT_HIT[c]) if c >= 0 else 0
				hit = _die() <= need
				dmg = (8 + 2 * int(w["ov"])) if hit else 0
				w["st"] = 0
				w["ov"] = 0
				w["ready"] = false
			elif w["t"] == "DISR":
				var ov2 := int(w["ov"]) > 0
				var r2 := er if not ov2 or er <= 8 else tr
				var c2 := D.col_index(D.DISR_COLS, r2)
				if c2 >= 0:
					var need2: int = D.DISR_HIT_OV[c2] if ov2 else D.DISR_HIT[c2]
					hit = _die() <= need2
					dmg = (D.DISR_DMG_OV[c2] if ov2 else D.DISR_DMG[c2]) if hit else 0
				w["ready"] = false
		if t["kind"] in ["drone", "plasma", "shut"]:
			lines.append("%s %s -> %s: %s" % [u["name"], wname, t["name"], ("%d" % dmg) if hit else "mancato"])
			fx.emit("shot", {"from": u["uid"], "to": tid, "w": wname, "hit": hit, "dmg": dmg})
			if not hit:
				continue
			if t["kind"] == "plasma":
				t["red"] = int(t["red"]) + (dmg / 2 if wname.begins_with("PH") else dmg)
				if D.plasma_strength(t["pt"], int(t["dist"])) - int(t["red"]) <= 0:
					_remove(tid, "abbattuto")
					lines.append("%s dissolto." % t["name"])
			else:
				t["hp"] = int(t["hp"]) - dmg
				if t["hp"] <= 0:
					_remove(tid, "abbattuto")
					lines.append("%s distrutto." % t["name"])
			continue
		fx.emit("shot", {"from": u["uid"], "to": tid, "w": wname, "hit": hit, "dmg": dmg})
		lines.append("%s %s -> %s: %s" % [u["name"], wname, t["name"], ("%d danni" % dmg) if hit else "mancato"])
		if not hit or dmg <= 0:
			continue
		var key := "%d|%d" % [tid, side]
		if not volleys.has(key):
			volleys[key] = {}
		var sh_i := _shield_hit(t, u["pos"])
		volleys[key][sh_i] = int(volleys[key].get(sh_i, 0)) + dmg
	for l in lines:
		log_msg(l)
	changed.emit()
	await _pace(0.5)
	for key in volleys:
		var tid2 := int(key.split("|")[0])
		var t2: Dictionary = units.get(tid2, {})
		if t2.is_empty() or not t2["alive"]:
			continue
		var once := {}
		for shi in volleys[key]:
			_damage(t2, int(shi), int(volleys[key][shi]), once)
	changed.emit()


func _shield_hit(t: Dictionary, from: Vector2i) -> int:
	if from == t["pos"]:
		return 0
	var rel := H.rel_bearing(t["pos"], t["face"], from)
	var opts := H.shields_for(rel)
	if opts.size() > 1 and int(t["sh"][opts[1]]) > int(t["sh"][opts[0]]):
		return int(opts[1])
	return int(opts[0])


## Danni a una nave sullo scudo shi: rinforzi, scudo, poi danni interni
func _damage(t: Dictionary, shi: int, dmg: int, once: Dictionary) -> void:
	var start := dmg
	if t["sh_on"] and not (t["cloak"] > 0):
		var a := mini(int(t["sr"][shi]), dmg)
		t["sr"][shi] = int(t["sr"][shi]) - a
		dmg -= a
		var b := mini(int(t["gr"]), dmg)
		t["gr"] = int(t["gr"]) - b
		dmg -= b
		var c := mini(int(t["sh"][shi]), dmg)
		t["sh"][shi] = int(t["sh"][shi]) - c
		dmg -= c
	if dmg > 0:
		log_msg("%s: %d danni allo scudo #%d, %d danni interni." % [t["name"], start - dmg, shi + 1, dmg])
		fx.emit("internal", {"uid": t["uid"], "n": dmg})
		_internal(t, dmg, once)
	else:
		log_msg("%s: lo scudo #%d assorbe %d danni." % [t["name"], shi + 1, start])
		fx.emit("shield", {"uid": t["uid"], "s": shi, "n": start})
	t["dmg_taken"] = int(t["dmg_taken"]) + dmg


func _sys_hit(t: Dictionary, k: String) -> bool:
	if int(t["sys"].get(k, 0)) > 0:
		t["sys"][k] = int(t["sys"][k]) - 1
		if k == "sh" and int(t["shuttles"]) > int(t["sys"]["sh"]):
			t["shuttles"] = int(t["sys"]["sh"])
		if k == "bt":
			t["batt"] = minf(float(t["batt"]), float(t["sys"]["bt"]))
		return true
	return false


func _weapon_hit(t: Dictionary, pred: Callable) -> bool:
	# il difensore sceglie: prima i phaser-3, poi droni, poi le armi meno preziose
	var order := ["PH3", "DRN", "PH2", "PH1", "PLF", "DISR", "PLG", "PHOT", "PLS", "PLR"]
	for ty in order:
		for w in t["weapons"]:
			if w["ok"] and w["t"] == ty and pred.call(w):
				w["ok"] = false
				w["ready"] = false
				t["cap"] = minf(float(t["cap"]), cap_max(t))
				return true
	return false


func _internal(t: Dictionary, n: int, once: Dictionary) -> void:
	for p in n:
		if not t["alive"]:
			return
		if _sys_hit(t, "armor"):
			continue
		var roll := _die() + _die()
		var row: Array = D.DAC[roll]
		var done := false
		for ci in row.size():
			var key: String = row[ci]
			var ok_once := true
			if D.DAC_ONCE.has(roll) and ci in D.DAC_ONCE[roll]:
				var ok_key := "%d-%d" % [roll, ci]
				if once.has(ok_key):
					ok_once = false
				else:
					ok_once = true
			if not ok_once:
				continue
			var hit := false
			match key:
				"br", "fl", "aux", "em", "tr", "trac", "sh", "lab", "imp", "apr", "bt", "prb", "cargo":
					hit = _sys_hit(t, key)
				"FH":
					hit = _sys_hit(t, "fh") or _sys_hit(t, "ch")
				"AH":
					hit = _sys_hit(t, "ah") or _sys_hit(t, "ch")
				"LW":
					hit = _sys_hit(t, "lw") or _sys_hit(t, "cw")
				"RW":
					hit = _sys_hit(t, "rw") or _sys_hit(t, "cw")
				"CW":
					hit = _sys_hit(t, "cw")
				"warp":
					hit = _sys_hit(t, "lw") or _sys_hit(t, "rw") or _sys_hit(t, "cw")
				"sensor", "scanner", "dc":
					var k2 := "sen" if key == "sensor" else ("scan" if key == "scanner" else "dc")
					var arr: Array = data(t)[k2]
					if int(t[k2]) < arr.size() - 1:
						t[k2] = int(t[k2]) + 1
						hit = true
				"phaser":
					hit = _weapon_hit(t, func(w): return D.is_phaser(w["t"]))
				"torp":
					hit = _weapon_hit(t, func(w): return D.is_torp(w["t"]))
				"drone":
					hit = _weapon_hit(t, func(w): return w["t"] == "DRN")
				"weapon":
					hit = _weapon_hit(t, func(w): return true)
				"ex":
					t["ex"] = int(t["ex"]) + 1
					hit = true
					if int(t["ex"]) > int(t["ex_max"]):
						_destroy(t)
			if hit:
				if D.DAC_ONCE.has(roll) and ci in D.DAC_ONCE[roll]:
					once["%d-%d" % [roll, ci]] = true
				done = true
				break
		if not done:
			t["ex"] = int(t["ex"]) + 1
			if int(t["ex"]) > int(t["ex_max"]):
				_destroy(t)
	# senza nessun controllo la nave non può più sparare
	if t["alive"] and int(t["sys"].get("br", 0)) + int(t["sys"].get("em", 0)) + int(t["sys"].get("aux", 0)) + int(t["sys"].get("fl", 0)) == 0:
		t["fc"] = false


func _destroy(t: Dictionary) -> void:
	if not t["alive"]:
		return
	t["alive"] = false
	t["gone"] = "distrutta"
	log_msg("*** %s (%s) è distrutta! ***" % [t["name"], pname(t["side"])])
	fx.emit("boom", {"uid": t["uid"], "pos": t["pos"]})
	_drop_seekers_on(t["uid"])
	for id in units.keys():
		var x: Dictionary = units.get(id, {})
		if x.get("kind", "") == "shut" and int(x.get("from", -1)) == int(t["uid"]) and false:
			_remove(id)


# ---------------------------------------------------------------- impatti

func _impacts() -> void:
	var hits := []
	for id in units.keys():
		var s: Dictionary = units.get(id, {})
		if not (s.get("kind", "") in ["drone", "plasma"]):
			continue
		var t: Dictionary = units.get(s["target"], {})
		if t.is_empty() or not t.get("alive", false):
			_remove(id, "senza bersaglio")
			continue
		if s["pos"] == t["pos"]:
			hits.append(id)
	if hits.is_empty():
		return
	for id in hits:
		var s: Dictionary = units.get(id, {})
		if s.is_empty():
			continue
		var t: Dictionary = units.get(s["target"], {})
		if t.is_empty() or not t.get("alive", false):
			_remove(id)
			continue
		var dmg := D.DRONE_DMG if s["kind"] == "drone" else maxi(0, D.plasma_strength(s["pt"], int(s["dist"])) - int(s["red"]))
		log_msg("%s colpisce %s: %d danni." % [s["name"], t["name"], dmg])
		fx.emit("impact", {"uid": id, "to": t["uid"], "dmg": dmg, "kind": s["kind"]})
		var from: Vector2i = s.get("prev", t["pos"])
		if from == t["pos"]:
			from = units[s["from"]]["pos"] if units.has(s["from"]) else from
		units.erase(id)
		fx.emit("remove", {"uid": id, "why": "impatto"})
		if t["kind"] == "shut":
			t["hp"] = int(t["hp"]) - dmg
			if t["hp"] <= 0:
				_remove(t["uid"], "abbattuto")
			continue
		_damage(t, _shield_hit(t, from), dmg, {})
	changed.emit()
	await _pace(0.5)
	_check_end()


# ---------------------------------------------------------------- fine partita

func teams_alive() -> Array:
	var out := []
	for u in live_ships():
		var tm := int(sides[u["side"]]["team"])
		if not (tm in out):
			out.append(tm)
	return out


func _check_end() -> void:
	if over:
		return
	if teams_alive().size() <= 1:
		_finish("vittoria")


func score(side: int) -> int:
	# punti: valore (BPV) delle navi nemiche distrutte, metà per quelle in fuga dopo aver subito
	# danni interni, più una quota per i danni interni inflitti alle altre
	var v := 0.0
	for id in units:
		var u: Dictionary = units[id]
		if u["kind"] != "ship" or not enemies(side, u["side"]):
			continue
		var bpv := float(data(u)["bpv"])
		if u["gone"] == "distrutta":
			v += bpv
		else:
			var boxes := 0
			for k in u["max"]:
				boxes += int(u["max"][k])
			v += bpv * minf(0.75, float(u["dmg_taken"]) / maxf(1.0, float(boxes)))
	return int(round(v))


func _finish(why: String) -> void:
	over = true
	var by_team := {}
	for s in sides.size():
		var tm := int(sides[s]["team"])
		sides[s]["vp"] = score(s)
		by_team[tm] = int(by_team.get(tm, 0)) + int(sides[s]["vp"])
	var alive := teams_alive()
	var win := -1
	if alive.size() == 1:
		win = int(alive[0])
	else:
		var best := -1
		for tm in by_team:
			if int(by_team[tm]) > best:
				best = int(by_team[tm])
				win = int(tm)
			elif int(by_team[tm]) == best:
				win = -2
	var names := []
	for s in sides.size():
		if int(sides[s]["team"]) == win:
			names.append(pname(s))
	result = {"why": why, "team": win, "winners": names, "vp": by_team}
	if win >= 0:
		log_msg("Fine della battaglia: vince %s." % " e ".join(names))
	else:
		log_msg("Fine della battaglia: pareggio.")
	changed.emit()
	game_ended.emit(result)


## Impronta dello stato (per verificare che salvataggi e partite online diano la stessa partita)
func fingerprint() -> String:
	var parts := ["t%d i%d" % [turn, imp]]
	for id in units:
		var u: Dictionary = units[id]
		if u["kind"] == "ship":
			var shs := 0
			for v in u["sh"]:
				shs += int(v)
			parts.append("%d:%s%s f%d ex%d sh%d %s" % [id, H.label(u["pos"]), "", u["face"], u["ex"], shs, u["gone"]])
		else:
			parts.append("%d:%s %s" % [id, u["kind"], H.label(u["pos"])])
	return str(hash("|".join(parts))) + " " + str(result.get("winners", []))
