class_name OnlineSession
extends Node
## Partita online in lockstep. Ogni decisione del motore (piani di spostamento, ripartizioni del
## combattimento, piani tattici) diventa una mossa numerata nel database: acts/0, acts/1, …
## Tutti i dispositivi fanno girare lo stesso motore con lo stesso seme e applicano le stesse mosse
## nello stesso ordine, quindi la partita è identica ovunque e sul database viaggiano solo le scelte.
## - le decisioni simultanee (piani segreti) hanno un numero per posto: ognuno pubblica la sua senza
##   aspettare gli altri, e il motore procede quando ci sono tutte;
## - i posti IA li gioca il dispositivo di chi ha creato la stanza;
## - se un giocatore tace per più di un minuto, al suo posto gioca l'IA finché non rientra.

var net: Net
var code := ""
var seat := -1
var role := "guest"
var n := 0
var backlog: Array = []
var catchup := false
var away := {}
var alive := true
var view
var _pending_mine := false


func setup(p_net: Net, p_code: String, p_seat: int, p_role: String, p_backlog: Array) -> void:
	net = p_net
	code = p_code
	seat = p_seat
	role = p_role
	backlog = p_backlog
	catchup = not backlog.is_empty()


func _exit_tree() -> void:
	alive = false


func _val(a: Dictionary):
	return str_to_var(str(a.get("v", "null")))


func decide(eng, s: int, req: Dictionary):
	var rr: Array = await decide_all(eng, [s], [req])
	return rr[0]


func decide_all(eng, seats: Array, reqs: Array) -> Array:
	# i posti dell'IA scelti alla partenza: l'IA è deterministica, quindi ogni dispositivo calcola da sé
	# la stessa decisione e nel registro viaggiano solo le scelte delle persone
	var ai_res := {}
	var hs := []
	var hr := []
	for i in seats.size():
		if eng.sides[seats[i]]["ai"]:
			ai_res[i] = eng.ais[seats[i]].decide(eng, seats[i], reqs[i])
		else:
			hs.append(seats[i])
			hr.append(reqs[i])
	var hres: Array = await _decide_people(eng, hs, hr) if not hs.is_empty() else []
	var out := []
	var k := 0
	for i in seats.size():
		if ai_res.has(i):
			out.append(ai_res[i])
		else:
			out.append(hres[k])
			k += 1
	return out


func _decide_people(eng, seats: Array, reqs: Array) -> Array:
	var base := n
	var res := []
	var done := []
	for i in seats.size():
		res.append(null)
		done.append(false)
		var idx := base + i
		if idx < backlog.size():
			res[i] = _val(backlog[idx])
			done[i] = true
	var all_done := not done.has(false)
	if not all_done and catchup:
		catchup = false
		if view != null:
			view.online_caught_up()
	# 1. le proprie decisioni e quelle dell'IA (solo chi ha creato la stanza)
	for i in seats.size():
		if done[i]:
			continue
		var s: int = seats[i]
		var idx := base + i
		var r = null
		var mine := false
		if s == seat:
			mine = true
			# forse è già stata scritta (rientro dopo un ricaricamento della pagina)
			var ex := await net.get_act(code, idx)
			if not ex.is_empty() and not ex.has("_err"):
				res[i] = _val(ex)
				done[i] = true
				continue
			_pending_mine = true
			r = await eng.ask_human(reqs[i])
			_pending_mine = false
			if r == null:
				r = eng.ais[s].decide(eng, s, reqs[i])
		elif role == "host" and (eng.sides[s]["ai"] or away.has(s)):
			r = eng.ais[s].decide(eng, s, reqs[i])
		else:
			continue
		res[i] = await _publish(s, idx, r)
		done[i] = true
		if not alive:
			break
	# 2. le decisioni degli altri dispositivi
	for i in seats.size():
		if done[i] or not alive:
			continue
		res[i] = await _wait(eng, seats[i], base + i, reqs[i])
		done[i] = true
	n = base + seats.size()
	for i in seats.size():
		if res[i] == null:
			res[i] = eng.ais[seats[i]].decide(eng, seats[i], reqs[i])
	return res


## Pubblica la decisione e la restituisce. Se la mossa c'è già (l'ha scritta prima un altro
## dispositivo) vale quella.
func _publish(s: int, idx: int, r):
	var a := {"s": s, "k": "d", "v": var_to_str(r)}
	while alive:
		if await net.post_act(code, idx, a):
			return r
		var ex := await net.get_act(code, idx)
		if not ex.is_empty() and not ex.has("_err"):
			return _val(ex)
		if view != null:
			view.online_status("Rete non raggiungibile, riprovo... (%s)" % net.last_error)
		await get_tree().create_timer(2.0).timeout
	return r


func _wait(eng, s: int, idx: int, req: Dictionary):
	var t0 := Time.get_ticks_msec()
	var last_seen = null
	var seen_t := t0
	var polls := 0
	var slow := false
	if view != null:
		view.online_waiting(s, false)
	while alive:
		var a := await net.get_act(code, idx)
		if not alive:
			break
		if not a.is_empty() and not a.has("_err"):
			if view != null:
				view.online_waiting(-1, false)
			return _val(a)
		var now := Time.get_ticks_msec()
		if role == "host" and not eng.sides[s]["ai"] and polls % 4 == 0:
			var st := await net.seat(code, s)
			if not alive:
				break
			if not st.is_empty():
				var seen = st.get("seen", null)
				if seen != last_seen:
					last_seen = seen
					seen_t = now
				if st.get("away", false) or (now - seen_t > 45000 and now - t0 > 60000):
					await net.set_away(code, s, true)
					away[s] = true
					if view != null:
						view.online_waiting(-1, false)
						view.online_status("%s non risponde: per ora gioca l'IA." % eng.pname(s))
					var r = eng.ais[s].decide(eng, s, req)
					return await _publish(s, idx, r)
		var sl := now - t0 > 60000
		if sl != slow:
			slow = sl
			if view != null:
				view.online_waiting(s, slow)
		polls += 1
		await get_tree().create_timer(0.7).timeout
	return null


func heartbeat_loop() -> void:
	while alive:
		net.heartbeat(code, seat)
		await get_tree().create_timer(5.0).timeout


func finish() -> void:
	if role == "host":
		net.set_status(code, "over")
	net.remember_room("")
