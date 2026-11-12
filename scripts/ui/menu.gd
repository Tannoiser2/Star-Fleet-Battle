extends Control
## Menu principale: scelta dello scenario, composizione delle flotte, partita locale o online,
## caricamento dei salvataggi, regolamento.

const D = preload("res://scripts/data/sfb_data.gd")
const H = preload("res://scripts/core/hexgrid.gd")
const SC = preload("res://scripts/data/scenarios.gd")

var main
var st := {}
var setup_box: VBoxContainer
var desc_lbl: Label
var on_panel: Control
var on_name: LineEdit
var on_code: LineEdit
var on_lbl: Label
var on_start: Button
var host_side := 0
var on_join := false

const CTRL := ["Umano", "IA cadetto", "IA capitano", "IA ammiraglio"]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	st = main.menu_state
	if st.is_empty():
		_load_scenario(0)
	_build()


func _load_scenario(i: int) -> void:
	var sc: Dictionary = SC.LIST[i]
	st["scen"] = i
	st["turns"] = int(sc["turni"])
	st["sides"] = []
	for j in sc["lati"].size():
		var l: Dictionary = sc["lati"][j]
		st["sides"].append({"name": l["nome"], "ctrl": 0 if j == 0 else 2, "team": j, "col": j, "ships": l["navi"].duplicate()})
	main.menu_state = st


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 30
	root.offset_right = -30
	root.offset_top = 24
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 22)
	add_child(root)
	# colonna sinistra: titolo e scenari
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 560
	left.add_theme_constant_override("separation", 10)
	root.add_child(left)
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 14)
	var cap := ColorRect.new()
	cap.color = UI.ORANGE
	cap.custom_minimum_size = Vector2(26, 110)
	tb.add_child(cap)
	var tv := VBoxContainer.new()
	tv.add_child(UI.title("Star Fleet Battles", 74, UI.ORANGE))
	tv.add_child(UI.head("Captain's Basic Set - versione digitale", 24, UI.PEACH))
	tb.add_child(tv)
	left.add_child(tb)
	left.add_child(UI.bar([UI.ORANGE, UI.PEACH, UI.LILAC, UI.SKY, UI.TAN], 12))
	left.add_child(UI.head("Scenari", 26, UI.LILAC))
	var lsc := ScrollContainer.new()
	lsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(lsc)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lsc.add_child(lv)
	for i in SC.LIST.size():
		var k: int = i
		var b := UI.button(SC.LIST[i]["nome"], 520, 52, 23, UI.TAN if i == int(st["scen"]) else UI.LILAC)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func():
			_load_scenario(k)
			_build())
		lv.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	left.add_child(row)
	var br := UI.button("Regolamento", 250, 52, 22, UI.BLUE)
	br.pressed.connect(func(): main.show_rules())
	row.add_child(br)
	var bl := UI.button("Carica una partita", 260, 52, 22, UI.SKY)
	bl.pressed.connect(_load_panel)
	row.add_child(bl)
	var rmu := HBoxContainer.new()
	rmu.add_theme_constant_override("separation", 10)
	left.add_child(rmu)
	var bmu := UI.button("Musica", 255, 44, 20, UI.LILAC if Audio.music_on else UI.DIM)
	bmu.pressed.connect(func():
		main.audio.toggle_music()
		UI.tint(bmu, UI.LILAC if Audio.music_on else UI.DIM))
	rmu.add_child(bmu)
	var bfx := UI.button("Effetti sonori", 255, 44, 20, UI.LILAC if Audio.sfx_on else UI.DIM)
	bfx.pressed.connect(func():
		main.audio.toggle_sfx()
		UI.tint(bfx, UI.LILAC if Audio.sfx_on else UI.DIM))
	rmu.add_child(bfx)
	var bp := UI.button("Prova: scheda SSD in 3D", 520, 48, 21, UI.PEACH)
	bp.pressed.connect(func(): main.show_prova())
	left.add_child(bp)

	# colonna destra: impostazione della battaglia
	var right := UI.panel(UI.ORANGE, 0.9)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right.add_child(rv)
	var sc: Dictionary = SC.LIST[int(st["scen"])]
	rv.add_child(UI.head(sc["nome"], 34, UI.ORANGE))
	desc_lbl = UI.wrap(UI.label(sc["desc"], 19, UI.TEXT), 700)
	rv.add_child(desc_lbl)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 10)
	rv.add_child(trow)
	trow.add_child(UI.label("Turni al massimo:", 19, UI.MUTED))
	var ot := OptionButton.new()
	ot.focus_mode = Control.FOCUS_NONE
	ot.custom_minimum_size = Vector2(110, 42)
	var turns := [6, 8, 10, 12, 15, 20]
	for t in turns:
		ot.add_item(str(t))
	ot.select(maxi(0, turns.find(int(st["turns"]))))
	ot.item_selected.connect(func(j): st["turns"] = turns[j])
	trow.add_child(ot)
	if st["sides"].size() < 8:
		var ba := UI.button("Aggiungi un giocatore", 260, 42, 19, UI.SKY)
		ba.pressed.connect(func():
			var n: int = st["sides"].size()
			st["sides"].append({"name": "Giocatore %d" % (n + 1), "ctrl": 2, "team": n, "col": n % 8, "ships": ["fed_ca"]})
			_build())
		trow.add_child(ba)
	var ssc := ScrollContainer.new()
	ssc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ssc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(ssc)
	setup_box = VBoxContainer.new()
	setup_box.add_theme_constant_override("separation", 12)
	setup_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ssc.add_child(setup_box)
	for i in st["sides"].size():
		_side_row(i)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 12)
	rv.add_child(brow)
	var bs := UI.primary(UI.button("Inizia la battaglia", 320, 60, 26))
	bs.pressed.connect(_on_start)
	brow.add_child(bs)
	var bc := UI.button("Online: crea una stanza", 330, 60, 22, UI.PEACH)
	bc.pressed.connect(func():
		on_join = false
		_online_panel())
	brow.add_child(bc)
	var bj := UI.button("Online: entra", 220, 60, 22, UI.PEACH)
	bj.pressed.connect(func():
		on_join = true
		_online_panel())
	brow.add_child(bj)


func _side_row(i: int) -> void:
	var sd: Dictionary = st["sides"][i]
	var col: Color = D.PCOLORS[int(sd["col"]) % 8]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.frame(col, 0.6))
	setup_box.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 10)
	vb.add_child(r1)
	var le := LineEdit.new()
	le.text = str(sd["name"])
	le.max_length = 20
	le.custom_minimum_size = Vector2(230, 44)
	le.add_theme_font_size_override("font_size", 20)
	le.text_changed.connect(func(t): sd["name"] = t)
	r1.add_child(le)
	var oc := _opt(CTRL, int(sd["ctrl"]), 200)
	oc.item_selected.connect(func(j): sd["ctrl"] = j)
	r1.add_child(oc)
	var teams := []
	for t in 8:
		teams.append("Squadra %d" % (t + 1))
	var otm := _opt(teams, int(sd["team"]), 170)
	otm.item_selected.connect(func(j): sd["team"] = j)
	r1.add_child(otm)
	var ocol := _opt(D.PCOL_NAMES, int(sd["col"]), 150)
	ocol.item_selected.connect(func(j):
		sd["col"] = j
		_build())
	r1.add_child(ocol)
	if st["sides"].size() > 2:
		var bx := UI.button("Togli", 100, 44, 18, UI.RUST)
		bx.pressed.connect(func():
			st["sides"].remove_at(i)
			_build())
		r1.add_child(bx)
	# navi
	var r2 := HFlowContainer.new()
	r2.add_theme_constant_override("h_separation", 8)
	r2.add_theme_constant_override("v_separation", 8)
	vb.add_child(r2)
	var bpv := 0
	for j in sd["ships"].size():
		var id: String = sd["ships"][j]
		var d: Dictionary = D.ship(id)
		bpv += int(d["bpv"])
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 4)
		var tr := TextureRect.new()
		tr.texture = load("res://assets/counters/%s.png" % id)
		tr.custom_minimum_size = Vector2(40, 40)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.add_child(tr)
		var l := UI.label("%s (%d)" % [d["n"], int(d["bpv"])], 17, UI.TEXT)
		l.custom_minimum_size.x = 210
		chip.add_child(l)
		var k: int = j
		if sd["ships"].size() > 1:
			var bx2 := UI.button("x", 40, 36, 16, UI.RUST)
			bx2.custom_minimum_size.x = 44
			bx2.pressed.connect(func():
				sd["ships"].remove_at(k)
				_build())
			chip.add_child(bx2)
		r2.add_child(chip)
	var r3 := HBoxContainer.new()
	r3.add_theme_constant_override("separation", 10)
	vb.add_child(r3)
	var add := OptionButton.new()
	add.focus_mode = Control.FOCUS_NONE
	add.custom_minimum_size = Vector2(420, 42)
	add.add_theme_font_size_override("font_size", 18)
	add.add_item("Aggiungi una nave...")
	var ids := [""]
	var by: Dictionary = D.ship_ids_by_race()
	for r in D.RACES:
		add.add_separator(D.RACES[r]["nome"])
		ids.append("")
		for id in by[r]:
			add.add_item("%s - %s (%d)" % [D.RACES[r]["nome"], D.ship(id)["n"], int(D.ship(id)["bpv"])])
			ids.append(id)
	add.item_selected.connect(func(j):
		if ids[j] != "" and sd["ships"].size() < 6:
			sd["ships"].append(ids[j])
		_build())
	r3.add_child(add)
	r3.add_child(UI.mono("Valore della flotta (BPV): %d" % bpv, 18, UI.TAN))


func _opt(items: Array, sel: int, w: int) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.custom_minimum_size = Vector2(w, 44)
	o.add_theme_font_size_override("font_size", 19)
	for t in items:
		o.add_item(str(t))
	o.select(clampi(sel, 0, items.size() - 1))
	return o


## Configurazione della partita: posizioni di partenza disposte attorno al centro della mappa
func _config() -> Dictionary:
	var n: int = st["sides"].size()
	var sides := []
	var center := H.from_label(21, 15)
	for i in n:
		var sd: Dictionary = st["sides"][i]
		var ang := PI + TAU * i / n
		var cc := 21.5 + cos(ang) * 16.0
		var rr := 15.5 + sin(ang) * 10.5
		var ships := []
		var m: int = sd["ships"].size()
		for j in m:
			var off := (j - (m - 1) / 2.0) * 2.0
			var c2 := int(round(cc - sin(ang) * off))
			var r2 := int(round(rr + cos(ang) * off))
			var h := H.from_label(clampi(c2, 3, 40), clampi(r2, 3, 28))
			ships.append({"id": sd["ships"][j], "hex": h, "face": H.dir_toward(h, center), "speed": 8})
		var ctrl := int(sd["ctrl"])
		sides.append({"name": str(sd["name"]).strip_edges() if str(sd["name"]).strip_edges() != "" else "Giocatore %d" % (i + 1),
			"ai": ctrl > 0, "level": maxi(1, ctrl), "team": int(sd["team"]), "col": int(sd["col"]), "ships": ships})
	return {"seed": 1 + randi() % 2000000000, "turns": int(st["turns"]), "sides": sides}


func _valid() -> String:
	var teams := {}
	for sd in st["sides"]:
		teams[int(sd["team"])] = true
		if sd["ships"].is_empty():
			return "Ogni giocatore deve avere almeno una nave."
	if teams.size() < 2:
		return "Servono almeno due squadre diverse."
	return ""


func _on_start() -> void:
	var err := _valid()
	if err != "":
		desc_lbl.text = err
		desc_lbl.add_theme_color_override("font_color", UI.RED)
		return
	main.menu_state = st
	main.start_game(_config())


# ================================================================ caricamento

func _overlay() -> Control:
	var p := Control.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.85)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.add_child(shade)
	var box := UI.panel(UI.PEACH, 0.98)
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.custom_minimum_size = Vector2(880, 0)
	box.offset_left = -440
	box.offset_right = 440
	box.offset_top = 110
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	box.add_child(vb)
	p.set_meta("vb", vb)
	return p


func _line(ph: String, maxlen: int) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = ph
	le.max_length = maxlen
	le.custom_minimum_size = Vector2(0, 56)
	le.add_theme_font_size_override("font_size", 24)
	return le


func _load_panel() -> void:
	var p := _overlay()
	var vb: VBoxContainer = p.get_meta("vb")
	vb.add_child(UI.title("Carica una partita", 46))
	vb.add_child(UI.wrap(UI.label("Scrivi il codice di sei lettere che hai ricevuto quando hai salvato.", 19), 780))
	var le := _line("Codice", 6)
	le.text_changed.connect(func(t):
		le.text = t.to_upper()
		le.caret_column = t.length())
	vb.add_child(le)
	var msg := UI.wrap(UI.label("", 19, UI.TAN), 780)
	vb.add_child(msg)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 12)
	vb.add_child(r)
	var bo := UI.primary(UI.button("Carica", 240, 56, 22))
	r.add_child(bo)
	var bc := UI.button("Indietro", 200, 56, 20, UI.LILAC)
	bc.pressed.connect(func(): p.queue_free())
	r.add_child(bc)
	bo.pressed.connect(func():
		var code := le.text.strip_edges().to_upper()
		if code.length() < 4:
			msg.text = "Codice non valido."
			return
		msg.text = "Carico..."
		var net: Net = main.get_net()
		var d: Dictionary = await net.load_game(code)
		if d.is_empty():
			msg.text = "Partita %s non trovata. %s" % [code, net.last_error]
			return
		var cfg = str_to_var(str(d.get("cfg", "")))
		var acts = str_to_var(str(d.get("acts", "")))
		if not (cfg is Dictionary) or not (acts is Array):
			msg.text = "Salvataggio non leggibile."
			return
		cfg["preload"] = acts
		cfg["save_code"] = code
		main.start_game(cfg))


# ================================================================ online

func _human_sides() -> Array:
	var out := []
	for i in st["sides"].size():
		if int(st["sides"][i]["ctrl"]) == 0:
			out.append(i)
	return out


func _online_panel() -> void:
	if is_instance_valid(on_panel):
		on_panel.queue_free()
	on_panel = _overlay()
	var vb: VBoxContainer = on_panel.get_meta("vb")
	vb.add_child(UI.title("Entra in una partita online" if on_join else "Crea una partita online", 44))
	if on_join:
		vb.add_child(UI.wrap(UI.label("Scrivi il tuo nome e il codice di quattro lettere che ti ha mandato chi ha creato la stanza. Scenario e flotte li ha già scelti lui.", 19, UI.MUTED), 820))
	else:
		vb.add_child(UI.wrap(UI.label("Scenario: %s. I giocatori impostati come «Umano» sono i posti per gli amici; quelli impostati come IA li gioca il computer. Scegli il tuo posto e crea la stanza: riceverai un codice da mandare agli altri. I posti rimasti liberi alla partenza li gioca l'IA." % SC.LIST[int(st["scen"])]["nome"], 19, UI.MUTED), 820))
	var ses: Dictionary = main.get_net().load_session()
	on_name = _line("Il tuo nome", 20)
	on_name.text = str(ses.get("name", ""))
	vb.add_child(on_name)
	if not on_join:
		var hs := _human_sides()
		if hs.is_empty():
			vb.add_child(UI.label("Imposta almeno un giocatore come «Umano».", 19, UI.RED))
		else:
			if not (host_side in hs):
				host_side = hs[0]
			var r0 := HBoxContainer.new()
			r0.add_theme_constant_override("separation", 8)
			vb.add_child(r0)
			r0.add_child(UI.label("Tu giochi:", 19))
			for i in hs:
				var k: int = i
				var b := UI.button(str(st["sides"][i]["name"]), 0, 44, 18, UI.TAN if host_side == i else UI.LILAC)
				b.pressed.connect(func():
					host_side = k
					_online_panel())
				r0.add_child(b)
			var b_create := UI.primary(UI.button("Crea una stanza", 0, 56, 22))
			b_create.pressed.connect(_online_create)
			vb.add_child(b_create)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	on_code = _line("Codice", 4)
	on_code.custom_minimum_size.x = 220
	on_code.text_changed.connect(func(t):
		on_code.text = t.to_upper()
		on_code.caret_column = t.length())
	row.add_child(on_code)
	var b_join := UI.button("Entra", 200, 56, 22)
	b_join.pressed.connect(_online_join)
	row.add_child(b_join)
	row.visible = on_join
	vb.add_child(row)
	on_lbl = UI.wrap(UI.label("", 20, UI.TEXT), 800)
	on_lbl.custom_minimum_size.y = 100
	vb.add_child(on_lbl)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	on_start = UI.primary(UI.button("Inizia online", 380, 60, 24))
	on_start.pressed.connect(_online_start)
	on_start.visible = main.lobby.get("role", "") == "host"
	row2.add_child(on_start)
	var b_close := UI.button("Indietro", 260, 60, 22, UI.LILAC)
	b_close.pressed.connect(func(): on_panel.queue_free())
	row2.add_child(b_close)
	vb.add_child(row2)
	if not main.lobby.is_empty():
		on_code.text = main.lobby["code"]
		on_lbl.text = "Stanza %s..." % main.lobby["code"]
	elif str(ses.get("room", "")) != "":
		on_code.text = str(ses["room"])
		on_lbl.text = "Eri nella stanza %s: premi Entra per rientrare." % ses["room"]


func _say(t: String) -> void:
	if is_instance_valid(on_lbl):
		on_lbl.text = t


func _seats_text(room: Dictionary) -> String:
	var seats := Net._as_dict(room.get("seats", {}))
	var parts := []
	for idx in room.get("open", []):
		var k := str(int(idx))
		var w := str(seats[k].get("name", "?")) if seats.has(k) and seats[k] is Dictionary else "libero (IA)"
		var nm := str(st["sides"][int(idx)]["name"]) if int(idx) < st["sides"].size() else "Posto %d" % (int(idx) + 1)
		parts.append("%s: %s" % [nm, w])
	return ", ".join(parts)


func _online_create() -> void:
	var nm := on_name.text.strip_edges()
	if nm == "":
		_say("Scrivi il tuo nome.")
		return
	var err := _valid()
	if err != "":
		_say(err)
		return
	var seats := [host_side]
	for i in _human_sides():
		if i != host_side:
			seats.append(i)
	_say("Creo la stanza...")
	var net: Net = main.get_net()
	var code := await net.create_room(nm, seats)
	if code == "":
		_say("Non riesco a creare la stanza.\n%s" % net.last_error)
		return
	main.lobby = {"role": "host", "code": code, "seat": host_side}
	net.remember_room(code, host_side)
	net._save({"name": nm})
	if is_instance_valid(on_code):
		on_code.text = code
	if is_instance_valid(on_start):
		on_start.visible = true
	_lobby_poll(code)


func _online_join() -> void:
	var code := on_code.text.strip_edges().to_upper()
	var nm := on_name.text.strip_edges()
	if nm == "" or code.length() != 4:
		_say("Scrivi il tuo nome e il codice di 4 lettere.")
		return
	_say("Entro nella stanza %s..." % code)
	var net: Net = main.get_net()
	var s := await net.join_room(code, nm)
	if s == -2:
		_say("Stanza %s non trovata, oppure la partita è già iniziata.%s" % [code, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	if s == -1:
		_say("Nella stanza %s non ci sono posti liberi." % code)
		return
	var room: Dictionary = net.last_room
	main.lobby = {"role": "host" if room.get("host", "") == net.uid else "guest", "code": code, "seat": s}
	net.remember_room(code, s)
	net._save({"name": nm})
	if room.get("status", "") in ["playing", "over"] and room.has("game"):
		_say("Rientro nella partita della stanza %s..." % code)
		_begin(room["game"], true)
		return
	if is_instance_valid(on_start):
		on_start.visible = main.lobby["role"] == "host"
	_lobby_poll(code)


func _lobby_poll(code: String) -> void:
	var net: Net = main.get_net()
	while is_inside_tree() and main.lobby.get("code", "") == code:
		var room := await net.room(code)
		if not is_inside_tree() or main.lobby.get("code", "") != code:
			return
		if room.is_empty():
			_say("La stanza %s non esiste più." % code)
			main.lobby = {}
			return
		if main.lobby["role"] == "host":
			_say("Stanza [ %s ]: dai il codice ai tuoi amici.\nPosti: %s.\nQuando ci sono tutti premi Inizia online." % [code, _seats_text(room)])
		else:
			if room.get("status", "") == "playing" and room.has("game"):
				_begin(room["game"], false)
				return
			_say("Sei nella stanza [ %s ] (posto %d).\nAspetta che chi l'ha creata avvii la partita." % [code, int(main.lobby["seat"]) + 1])
		await get_tree().create_timer(2.0).timeout


func _online_start() -> void:
	var code: String = main.lobby["code"]
	var net: Net = main.get_net()
	var room := await net.room(code)
	if room.is_empty():
		_say("La stanza %s non esiste più." % code)
		main.lobby = {}
		return
	var seats_db := Net._as_dict(room.get("seats", {}))
	var cfg := _config()
	for i in cfg["sides"].size():
		var k := str(i)
		if seats_db.has(k) and seats_db[k] is Dictionary:
			cfg["sides"][i]["name"] = str(seats_db[k].get("name", ""))
			cfg["sides"][i]["ai"] = false
		else:
			cfg["sides"][i]["ai"] = true
			cfg["sides"][i]["level"] = maxi(2, int(cfg["sides"][i]["level"]))
	var g := {"cfg": var_to_str(cfg)}
	if not await net.start_room(code, g):
		_say("Non riesco ad avviare la partita (%s)." % net.last_error)
		return
	_begin(g, false)


func _begin(g: Dictionary, rejoin: bool) -> void:
	var net: Net = main.get_net()
	var lob: Dictionary = main.lobby
	var backlog: Array = []
	if rejoin:
		backlog = await net.get_acts(lob["code"])
		net.set_away(lob["code"], int(lob["seat"]), false)
	var cfg = str_to_var(str(g.get("cfg", "")))
	if not (cfg is Dictionary):
		_say("Configurazione della partita non valida.")
		return
	var ses := OnlineSession.new()
	ses.setup(net, lob["code"], int(lob["seat"]), lob["role"], backlog)
	cfg["online"] = ses
	main.lobby = {}
	main.start_game(cfg)
