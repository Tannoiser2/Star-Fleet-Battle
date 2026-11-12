extends RefCounted
## Intelligenza artificiale per Star Fleet Battles.
## Livello 1 (Cadetto): semplice e un po' avventato. Livello 2 (Capitano): gestisce gittate e scudi.
## Livello 3 (Ammiraglio): sovraccarichi, rinforzi mirati, occultamento, difesa dalle armi autoguidate.
## Le stesse funzioni servono all'interfaccia per la ripartizione automatica e il pilota automatico.

const D = preload("res://scripts/data/sfb_data.gd")
const H = preload("res://scripts/core/hexgrid.gd")

var level := 2
var last_dist := {}


func decide(eng, side: int, req: Dictionary):
	match req["type"]:
		"energy":
			var out := {}
			for u in eng.ships_of(side):
				out[u["uid"]] = energy_for(eng, u)
			return out
		"move":
			var out2 := {}
			for uid in req["uids"]:
				out2[uid] = move_for(eng, eng.units[uid])
			return out2
		"fire":
			return fire_for(eng, side)
	return null


func nearest_enemy(eng, u: Dictionary):
	var best = null
	var bd := 9999
	for e in eng.live_ships():
		if eng.enemies(u["side"], e["side"]):
			var d := H.dist(u["pos"], e["pos"])
			if d < bd:
				bd = d
				best = e
	return best


func _has(u: Dictionary, pred: Callable) -> bool:
	for w in u["weapons"]:
		if w["ok"] and pred.call(w):
			return true
	return false


# ---------------------------------------------------------------- energia

func energy_for(eng, u: Dictionary) -> Dictionary:
	var d: Dictionary = eng.data(u)
	var p: Dictionary = eng.power(u)
	var e = nearest_enemy(eng, u)
	var r: int = H.dist(u["pos"], e["pos"]) if e != null else 40
	var a := {"spd": 0, "ph": 0.0, "sh": true, "gr": 0, "sr": [0, 0, 0, 0, 0, 0], "w": {}, "ov": {}, "cl": false, "fc": true}
	var left: float = float(p["total"]) - float(d["ls"]) - 1.0 - float(d["sc"])
	var warp_left: float = float(p["warp"]) + (1.0 if p["imp"] > 0 else 0.0)
	if d.get("sublight", false):
		warp_left = float(p["imp"])
	# armi pesanti
	for i in u["weapons"].size():
		var w: Dictionary = u["weapons"][i]
		if not w["ok"]:
			continue
		var need: Array = eng.weapon_need(w)
		if need.size() < 2:
			continue
		var c := float(need[1])
		if w["t"] == "DISR" and r <= 10 and level >= 2 and left > 20:
			c = 4.0
		if w["t"] == "PHOT":
			if w["st"] >= 1 and r <= 10 and level >= 2 and left > 16 and warp_left > 10:
				c += 2.0
			if c > warp_left:
				continue
			warp_left -= c
		if c <= left:
			a["w"][i] = c
			left -= c
	# phaser: riempire i condensatori
	var ph: float = eng.cap_max(u) - float(u["cap"])
	ph = minf(ph, maxf(0.0, left))
	a["ph"] = ph
	left -= ph
	# velocità
	var want := 16
	if r > 20:
		want = 24
	elif r < 8:
		want = 12
	if level == 1:
		want = 20
	var mc := float(d["mc"])
	var spd := mini(want, int(floor(minf(warp_left, left) / mc)))
	spd = clampi(spd, 0, eng.max_speed(u))
	a["spd"] = spd
	left -= spd * mc
	# occultamento (romulani e orioni) mentre i plasma si caricano
	if d.has("cloak") and level >= 3 and r < 20 and left >= float(d["cloak"]) + 2:
		var arming := false
		var ready := false
		for w in u["weapons"]:
			if w["ok"] and D.is_plasma(w["t"]):
				if w["st"] < 2:
					arming = true
				else:
					ready = true
		if arming and not ready:
			a["cl"] = true
			left -= float(d["cloak"])
	# rinforzi: lo scudo verso il nemico
	if e != null and left >= 1:
		var rel := H.rel_bearing(u["pos"], u["face"], e["pos"])
		var s: int = H.shields_for(rel)[0]
		var spec := int(floor(left * (0.6 if level >= 2 else 0.3)))
		a["sr"][s] = spec
		left -= spec
		if level >= 3 and left >= 4:
			a["gr"] = int(floor(left / 4.0))
			left -= a["gr"] * 2
	return a


# ---------------------------------------------------------------- movimento

func _want_range(eng, u: Dictionary) -> int:
	var ready := 0
	var plasma := false
	var heavy := false
	for w in u["weapons"]:
		if not w["ok"]:
			continue
		if D.is_plasma(w["t"]):
			plasma = true
			if w["ready"] and not w["fired"]:
				ready += 2
		elif w["t"] == "PHOT" or w["t"] == "DISR":
			heavy = true
			if w["ready"] and not w["fired"]:
				ready += 1
	if plasma:
		return 6 if ready > 0 else 18
	if heavy:
		if ready > 0:
			return 4 if level >= 2 else 2
		return 12
	return 5


func move_for(eng, u: Dictionary) -> String:
	var e = nearest_enemy(eng, u)
	if e == null:
		return "F"
	var want := _want_range(eng, u)
	# minacce in arrivo: allontanarsi se un plasma forte è vicino e non è ancora a segno
	var threat := false
	for x in eng.units.values():
		if x.get("kind", "") == "plasma" and int(x["target"]) == int(u["uid"]) and H.dist(x["pos"], u["pos"]) < 8:
			threat = true
	if threat and level >= 2:
		want = 30
	var best := "F"
	var bs := 1e9
	for m in eng.legal_moves(u):
		var f: int = u["face"]
		var dirn := f
		match m:
			"L":
				f = posmod(f - 1, 6)
				dirn = f
			"R":
				f = posmod(f + 1, 6)
				dirn = f
			"SL":
				dirn = posmod(f - 1, 6)
			"SR":
				dirn = posmod(f + 1, 6)
		var n := H.neighbor(u["pos"], dirn)
		var d := H.dist(n, e["pos"])
		var sc := absf(d - want) * 2.0
		var rel := H.rel_bearing(n, f, e["pos"])
		var off := absf(angle_difference(0.0, deg_to_rad(rel))) / PI   # 0 = nemico davanti, 1 = dietro
		if want < d:
			sc += off * 4.0
		elif want > d + 2:
			sc += (1.0 - off) * 3.0
		else:
			# alla distanza giusta: tenere il nemico negli archi delle armi, di fianco se si ha solo phaser laterali
			sc += off * 2.0
		# bordo della mappa
		var cr := H.to_colrow(n)
		var edge := mini(mini(cr.x - 1, H.COLS - cr.x), mini(cr.y - 1, H.ROWS - cr.y))
		if edge < 0:
			sc += 1000
		elif edge < 3:
			sc += (3 - edge) * 6.0
		# guardare avanti: con il modo di virata servono esagoni liberi davanti per girare in tempo
		var ahead := 0
		var hh := n
		while ahead < 14 and H.on_map(H.neighbor(hh, f)):
			hh = H.neighbor(hh, f)
			ahead += 1
		var need: int = eng.turn_mode_of(u) * 2 + 2
		if ahead < need:
			sc += float(need - ahead) * 5.0
		if m.begins_with("S"):
			sc += 0.4
		if level == 1:
			sc += float(hash([u["uid"], eng.turn, eng.imp, m]) % 1000) / 1000.0 * 1.5
		if sc < bs:
			bs = sc
			best = m
	return best


# ---------------------------------------------------------------- fuoco

func fire_for(eng, side: int) -> Dictionary:
	var shots := []
	var launch := []
	var imp: int = eng.imp
	for u in eng.ships_of(side):
		if not u["fc"] or u["cloak"] > 0 or u["cloak_t"] > 0:
			continue
		# difesa: phaser contro armi autoguidate vicine dirette a noi
		var incoming := []
		for x in eng.units.values():
			if x.get("kind", "") in ["drone", "plasma"] and eng.enemies(side, x["side"]) and int(x["target"]) == int(u["uid"]):
				var dd := H.dist(x["pos"], u["pos"])
				if dd <= (2 if x["kind"] == "drone" else 4):
					incoming.append(x)
		# navette e caccia
		var e = nearest_enemy(eng, u)
		if eng.can_launch_shuttle(u) and e != null:
			var de := H.dist(u["pos"], e["pos"])
			if (int(u["fighters"]) > 0 and de <= 15) or (level >= 2 and int(u["shuttles"]) > 0 and de <= 4 and int(u["ex"]) > 0):
				launch.append([u["uid"], "shut", 0])
		var used_cap := 0.0
		for i in u["weapons"].size():
			if not eng.weapon_usable(u, i):
				continue
			var w: Dictionary = u["weapons"][i]
			var tg: Array = eng.targets_for(u, i)
			if tg.is_empty():
				continue
			if D.is_phaser(w["t"]):
				if float(u["cap"]) - used_cap < D.phaser_cost(w["t"]) - 0.001:
					continue
				# difesa
				var done := false
				for x in incoming:
					if x["uid"] in tg and (level >= 2 or w["t"] == "PH3"):
						shots.append([u["uid"], i, x["uid"]])
						used_cap += D.phaser_cost(w["t"])
						incoming.erase(x)
						done = true
						break
				if done:
					continue
				var best = _best_ship_target(eng, u, tg)
				if best == null:
					continue
				var er: int = eng.eff_range(u, eng.units[best])
				var lim := 8 if w["t"] == "PH1" else 4
				if w["t"] == "PH3":
					lim = 2
				var opening := _opening(u, eng.units[best])
				if er <= lim or (imp >= 29 and er <= lim * 2) or (opening and er <= lim + 3 and level >= 2) or (level == 1 and er <= 10):
					shots.append([u["uid"], i, best])
					used_cap += D.phaser_cost(w["t"])
			elif w["t"] == "PHOT" or w["t"] == "DISR":
				var best2 = _best_ship_target(eng, u, tg)
				if best2 == null:
					continue
				var er2: int = eng.eff_range(u, eng.units[best2])
				var good := er2 <= (8 if level >= 2 else 12)
				if w["t"] == "DISR" and imp >= 31:
					good = true
				if w["t"] == "PHOT" and imp >= 31 and er2 <= 12:
					good = true
				if _opening(u, eng.units[best2]) and er2 <= 10:
					good = true
				if good:
					shots.append([u["uid"], i, best2])
			elif D.is_plasma(w["t"]):
				var best3 = _best_ship_target(eng, u, tg)
				if best3 != null:
					var r3 := H.dist(u["pos"], eng.units[best3]["pos"])
					var lim3 := 12 if w["pt"] in ["R", "S"] else 7
					if r3 <= lim3 or (imp >= 30 and r3 <= lim3 + 5 and level >= 2):
						launch.append([u["uid"], i, best3])
			elif w["t"] == "DRN":
				var best4 = _best_ship_target(eng, u, tg)
				if best4 != null and H.dist(u["pos"], eng.units[best4]["pos"]) <= 16:
					launch.append([u["uid"], i, best4])
		last_dist[u["uid"]] = H.dist(u["pos"], e["pos"]) if e != null else 0
	return {"shots": shots, "launch": launch}


func _opening(u: Dictionary, t: Dictionary) -> bool:
	var d := H.dist(u["pos"], t["pos"])
	return last_dist.has(u["uid"]) and d > int(last_dist[u["uid"]])


func _best_ship_target(eng, u: Dictionary, tg: Array):
	var best = null
	var bs := 1e9
	for id in tg:
		var t: Dictionary = eng.units[id]
		if t["kind"] != "ship" and t["kind"] != "shut":
			continue
		var sc := float(eng.eff_range(u, t))
		if t["kind"] == "ship":
			var shi: int = eng._shield_hit(t, u["pos"])
			sc += float(t["sh"][shi]) * 0.08 if t["sh_on"] else 0.0
		else:
			sc += 6.0
		if sc < bs:
			bs = sc
			best = id
	return best
