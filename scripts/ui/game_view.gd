extends Control
## Vista della partita: mappa 3D, consolle di plancia (stato della nave, registro) e pannelli delle
## decisioni: ripartizione dell'energia, movimento impulso per impulso, fuoco e lanci.

const D = preload("res://scripts/data/sfb_data.gd")
const H = preload("res://scripts/core/hexgrid.gd")
const Board3D = preload("res://scripts/ui/board3d.gd")
const AIClass = preload("res://scripts/core/ai.gd")

var main
var config := {}
var eng: SFBEngine
var board
var online: OnlineSession
var save_code := ""
var helper_ai

var top_lbl: Label
var phase_lbl: Label
var fleet_box: HFlowContainer
var left_panel: PanelContainer
var head_box: VBoxContainer
var view_box: VBoxContainer
var mode_btns: Array = []
var zoom_btn: Button
var view_mode := 0          # 0 testo, 1 SSD 2D, 2 SSD 3D
var view_key := ""
var info_col: VBoxContainer
var shield_box: VBoxContainer
var shield_uid := -1
const LEFT_W := [440, 500, 560]
var log_rich: RichTextLabel
var act_panel: PanelContainer
var act_box: VBoxContainer
var say_lbl: Label
var wait_lbl: Label
var ssd_overlay: Control
var ssd_win: Control
var ssd_win_uid := -1

var selected := -1
var req := {}
var viewer := -1            # lato che guarda (-1 = più umani sullo stesso dispositivo)
var humans: Array = []

# movimento
var move_queue: Array = []
var move_res := {}
var autopilot := {}         # uid -> "" | "rotta" | "auto"
var plan := {}              # uid -> [mosse in coda]
# fuoco
var fire_sel := {}          # "uid:widx" -> tuid
var skip_fire_until := {}   # lato -> (turno*100 + impulso)
var fire_ai := {}           # lato -> true: l'IA spara per questo lato
# energia
var alloc := {}
var alloc_tab := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	helper_ai = AIClass.new()
	helper_ai.level = 3
	eng = SFBEngine.new()
	var cfg := config.duplicate(true)
	cfg.erase("online")
	cfg.erase("preload")
	eng.setup(cfg)
	eng.anim = float(config.get("anim", 1.0))
	if config.has("preload"):
		eng.replay_queue = config["preload"].duplicate()
		save_code = str(config.get("save_code", ""))
	add_child(eng)
	online = config.get("online", null)
	if online != null:
		add_child(online)
		online.view = self
		eng.online = online
	for i in eng.sides.size():
		if not eng.sides[i]["ai"]:
			humans.append(i)
	if online != null:
		viewer = online.seat
	elif humans.size() == 1:
		viewer = humans[0]
	elif humans.is_empty():
		viewer = -2
	board = Board3D.new()
	add_child(board)
	board.audio = main.audio
	board.setup(eng)
	board.unit_clicked.connect(_on_unit_clicked)
	board.hex_clicked.connect(_on_hex_clicked)
	_build_ui()
	eng.decision_requested.connect(_on_request)
	eng.changed.connect(_refresh)
	eng.log_added.connect(_on_log)
	eng.game_ended.connect(_on_end)
	var first := _my_ships()
	if not first.is_empty():
		_select(int(first[0]["uid"]))
		board.focus_hex(first[0]["pos"])
	_refresh()
	if online != null and online.role != "host":
		online.heartbeat_loop()
	await get_tree().process_frame
	eng.run()


func _my_ships() -> Array:
	var out := []
	if viewer >= 0:
		return eng.ships_of(viewer)
	for s in humans:
		out += eng.ships_of(s)
	if out.is_empty():
		out = eng.live_ships()
	return out


func _mine(u: Dictionary) -> bool:
	if u.is_empty():
		return false
	if viewer >= 0:
		return int(u["side"]) == viewer
	return int(u["side"]) in humans


# ================================================================ interfaccia

func _build_ui() -> void:
	# barra superiore
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0.85), Color(0, 0, 0, 0), 0, 0, 6))
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 64
	add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	top.add_child(hb)
	var cap := ColorRect.new()
	cap.color = UI.ORANGE
	cap.custom_minimum_size = Vector2(60, 40)
	hb.add_child(cap)
	hb.add_child(UI.title("Star Fleet Battles", 34, UI.ORANGE))
	top_lbl = UI.head("", 26, UI.PEACH)
	top_lbl.custom_minimum_size.x = 330
	hb.add_child(top_lbl)
	phase_lbl = UI.head("", 22, UI.SKY)
	phase_lbl.custom_minimum_size.x = 260
	phase_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phase_lbl.clip_text = true
	hb.add_child(phase_lbl)
	var b2 := UI.button("Vista 2D", 140, 44, 20, UI.LILAC)
	b2.toggle_mode = true
	b2.toggled.connect(func(on):
		board.set_top_view(on)
		b2.text = "VISTA 3D" if on else "VISTA 2D")
	hb.add_child(b2)
	var br := UI.button("Regole", 120, 44, 20, UI.BLUE)
	br.pressed.connect(_show_rules)
	hb.add_child(br)
	if online == null:
		var bs := UI.button("Salva", 110, 44, 20, UI.TAN)
		bs.pressed.connect(_save)
		hb.add_child(bs)
	var bmu := UI.button("Musica", 110, 44, 20, UI.LILAC if Audio.music_on else UI.DIM)
	bmu.pressed.connect(func():
		main.audio.toggle_music()
		UI.tint(bmu, UI.LILAC if Audio.music_on else UI.DIM))
	hb.add_child(bmu)
	var bfx := UI.button("Effetti", 110, 44, 20, UI.LILAC if Audio.sfx_on else UI.DIM)
	bfx.pressed.connect(func():
		main.audio.toggle_sfx()
		UI.tint(bfx, UI.LILAC if Audio.sfx_on else UI.DIM))
	hb.add_child(bfx)
	var bm := UI.button("Menu", 110, 44, 20, UI.RUST)
	bm.pressed.connect(_quit)
	hb.add_child(bm)

	# pannello sinistro: una scheda per ogni astronave, con tre viste (testo, SSD 2D, SSD 3D)
	left_panel = UI.panel(UI.ORANGE, 0.9)
	left_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_panel.offset_top = 74
	left_panel.offset_bottom = -10
	left_panel.offset_left = 8
	left_panel.offset_right = 8 + LEFT_W[0]
	add_child(left_panel)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left_panel.add_child(lv)
	fleet_box = HFlowContainer.new()
	fleet_box.add_theme_constant_override("h_separation", 5)
	fleet_box.add_theme_constant_override("v_separation", 5)
	lv.add_child(fleet_box)
	head_box = VBoxContainer.new()
	head_box.add_theme_constant_override("separation", 2)
	lv.add_child(head_box)
	# dati della nave su una colonna, a destra gli scudi in 3D sempre visibili
	var ir := HBoxContainer.new()
	ir.add_theme_constant_override("separation", 8)
	lv.add_child(ir)
	info_col = VBoxContainer.new()
	info_col.add_theme_constant_override("separation", 1)
	info_col.custom_minimum_size.x = 212
	ir.add_child(info_col)
	shield_box = VBoxContainer.new()
	shield_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shield_box.custom_minimum_size = Vector2(170, 210)
	ir.add_child(shield_box)
	var mr := HBoxContainer.new()
	mr.add_theme_constant_override("separation", 6)
	lv.add_child(mr)
	for i in 3:
		var bt := UI.button(["Testo", "SSD 2D", "SSD 3D"][i], 96, 38, 17, UI.DIM)
		bt.pressed.connect(func(): _set_view(i))
		mr.add_child(bt)
		mode_btns.append(bt)
	zoom_btn = UI.button("Ingrandisci", 130, 38, 17, UI.SKY)
	zoom_btn.pressed.connect(func():
		if view_mode == 2 and selected >= 0:
			_open_ssd_window(selected)
		else:
			_show_ssd())
	mr.add_child(zoom_btn)
	lv.add_child(UI.bar([UI.ORANGE, UI.PEACH, UI.LILAC], 5))
	view_box = VBoxContainer.new()
	view_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(view_box)

	# pannello destro: diario di bordo
	var right := UI.panel(UI.LILAC, 0.88)
	right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_top = 74
	right.offset_bottom = -10
	right.offset_left = -400
	right.offset_right = -8
	add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	rv.add_child(UI.head("Diario di bordo", 22, UI.LILAC))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(sc)
	log_rich = UI.rich(16)
	log_rich.custom_minimum_size.x = 330
	log_rich.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(log_rich)
	log_rich.resized.connect(func(): sc.scroll_vertical = int(log_rich.size.y))

	# pannello delle azioni (in basso al centro)
	act_panel = UI.panel(UI.TAN, 0.95)
	act_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	act_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	act_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	act_panel.offset_bottom = -12
	act_panel.custom_minimum_size = Vector2(1040, 0)
	act_panel.offset_left = -501
	act_panel.offset_right = 539
	act_panel.visible = false
	add_child(act_panel)
	get_viewport().size_changed.connect(_place_act)
	act_box = VBoxContainer.new()
	act_box.add_theme_constant_override("separation", 8)
	act_panel.add_child(act_box)
	_set_view(0)

	say_lbl = UI.head("", 26, UI.TAN)
	say_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	say_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	say_lbl.offset_top = 80
	say_lbl.offset_left = -500
	say_lbl.offset_right = 500
	say_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	say_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	say_lbl.add_theme_constant_override("outline_size", 8)
	say_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(say_lbl)
	wait_lbl = UI.head("", 22, UI.SKY)
	wait_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	wait_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	wait_lbl.offset_top = 118
	wait_lbl.offset_left = -500
	wait_lbl.offset_right = 500
	wait_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wait_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wait_lbl)


var _say_id := 0


func _say(t: String, secs := 3.0) -> void:
	_say_id += 1
	var my := _say_id
	say_lbl.text = t
	await get_tree().create_timer(secs).timeout
	if my == _say_id and is_instance_valid(say_lbl):
		say_lbl.text = ""


func _on_log(t: String) -> void:
	var col := "#f2ecff"
	if t.begins_with("***"):
		col = "#ff7766"
	elif t.begins_with("Turno"):
		col = "#ffcc66"
	elif "danni interni" in t:
		col = "#ffaa77"
	elif "mancato" in t:
		col = "#8f8aa6"
	log_rich.append_text("[color=%s]%s[/color]\n" % [col, t])


func _phase_text() -> String:
	match eng.phase:
		"energia":
			return "Ripartizione dell'energia"
		"velocita":
			return "Velocità e sensori"
		"impulsi":
			return "Impulso %d di 32" % eng.imp
		"fine":
			return "Fine del turno"
	return ""


func _refresh() -> void:
	if not is_instance_valid(board):
		return
	top_lbl.text = "TURNO %d / %d" % [maxi(1, eng.turn), eng.max_turns]
	phase_lbl.text = _phase_text().to_upper()
	board.refresh()
	_refresh_status()
	_refresh_fleet()


func _select(uid: int) -> void:
	selected = uid
	board.select(uid)
	_refresh_status()
	_refresh_fleet()


const SYS_SHORT := {"fl": "Ponte band.", "em": "Ponte emerg.", "aux": "Contr. ausil.", "lw": "Warp sinistro",
	"rw": "Warp destro", "cw": "Warp centrale", "imp": "Impulso", "apr": "Reattori aus.", "fh": "Scafo prua",
	"ah": "Scafo poppa", "ch": "Scafo centr.", "trac": "Raggi traenti", "tr": "Teletrasp."}


## Linguette delle astronavi in cima al pannello: una per nave, nel colore del giocatore
func _refresh_fleet() -> void:
	for c in fleet_box.get_children():
		c.queue_free()
	for s in eng.sides.size():
		for u in eng.ships_of(s, false):
			var b := Button.new()
			b.custom_minimum_size = Vector2(60, 60)
			b.focus_mode = Control.FOCUS_NONE
			var col: Color = D.PCOLORS[int(eng.sides[s]["col"]) % 8]
			var sel: bool = u["uid"] == selected
			var st := UI.box(Color(0, 0, 0, 0.6) if not sel else col.darkened(0.55), col if u["alive"] else UI.DIM, 4 if sel else 1, 6, 3)
			b.add_theme_stylebox_override("normal", st)
			b.add_theme_stylebox_override("hover", UI.box(Color(0.15, 0.12, 0.2), col, 3, 6, 3))
			b.add_theme_stylebox_override("pressed", st)
			b.tooltip_text = "%s - %s" % [D.ship(u["id"])["n"], eng.pname(s)]
			var tr := TextureRect.new()
			tr.texture = load("res://assets/counters/%s.png" % u["id"])
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tr.offset_left = 6
			tr.offset_top = 6
			tr.offset_right = -6
			tr.offset_bottom = -6
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if not u["alive"]:
				tr.modulate = Color(0.35, 0.35, 0.35)
			b.add_child(tr)
			var uid: int = u["uid"]
			b.pressed.connect(func():
				_select(uid)
				if eng.units[uid]["alive"]:
					board.focus_hex(eng.units[uid]["pos"]))
			fleet_box.add_child(b)


## Cambia la vista della scheda: 0 testo, 1 SSD originale, 2 SSD 3D
func _set_view(m: int) -> void:
	view_mode = m
	view_key = ""
	for i in mode_btns.size():
		UI.tint(mode_btns[i], UI.ORANGE if i == m else UI.DIM)
	zoom_btn.visible = m > 0
	left_panel.offset_right = 8 + LEFT_W[m]
	_place_act()
	_refresh_status()


## Il pannello delle azioni si sposta a destra quanto basta a non coprire la scheda
func _place_act() -> void:
	if not is_instance_valid(act_panel) or not is_instance_valid(left_panel):
		return
	var vw := get_viewport_rect().size.x
	var ol := maxf(-501.0, left_panel.offset_right + 10.0 - vw * 0.5)
	ol = minf(ol, vw * 0.5 - 1040.0 - 8.0)
	act_panel.offset_left = ol
	act_panel.offset_right = ol + 1040.0


func _kv(parent: Control, k: String, v: String, col := UI.TEXT) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var a := UI.label(k, 15, UI.MUTED)
	a.custom_minimum_size.x = 82
	hb.add_child(a)
	var b := UI.mono(v, 15, col)
	b.custom_minimum_size.x = 118
	hb.add_child(b)
	parent.add_child(hb)


func _sect(parent: Control, t: String, col: Color) -> void:
	parent.add_child(UI.head(t, 18, col))


func weapon_state(u: Dictionary, w: Dictionary) -> String:
	if not w["ok"]:
		return "distrutta"
	var t: String = w["t"]
	if D.is_phaser(t):
		return "sparato" if w["fired"] else ("pronto" if float(u["cap"]) >= D.phaser_cost(t) else "senza energia")
	if t == "PHOT":
		if w["fired"]:
			return "sparato"
		if w["st"] == 1:
			return "in carica 1/2"
		if w["st"] == 2:
			return ("pronto" + (" +%d" % int(w["ov"]) if int(w["ov"]) > 0 else "")) if w["ready"] else "armato"
		return "scarico"
	if t == "DISR":
		if w["fired"]:
			return "sparato"
		return ("pronto" + (" sovr." if int(w["ov"]) > 0 else "")) if w["ready"] else "scarico"
	if D.is_plasma(t):
		if w["fired"]:
			return "lanciato"
		if w["st"] >= 3:
			return "pronto" if w["ready"] else "armato"
		return "in carica %d/3" % int(w["st"])
	if t == "DRN":
		return "%d droni%s" % [int(w.get("n", 0)), ", lanciato" if w["fired"] else ""]
	return ""


func _refresh_status() -> void:
	if not is_instance_valid(head_box):
		return
	for c in head_box.get_children():
		c.queue_free()
	var u: Dictionary = eng.units.get(selected, {})
	for c in info_col.get_children():
		c.queue_free()
	if u.is_empty() or u.get("kind", "") != "ship":
		head_box.add_child(UI.head("Scegli una nave", 22))
		_clear_view()
		_shield_view(-1)
		return
	var d: Dictionary = D.ship(u["id"])
	var col: Color = D.PCOLORS[int(eng.sides[u["side"]]["col"]) % 8]
	var t := UI.head(str(d["n"]), 24, UI.ORANGE)
	t.clip_text = true
	t.custom_minimum_size.x = 300
	head_box.add_child(t)
	head_box.add_child(UI.label("%s  -  %s" % [D.RACES[d["r"]]["nome"], eng.pname(u["side"])], 16, col))
	# dati principali: in tutte e tre le viste
	_info_grid(u, d)
	var key := "%d:%d" % [selected, view_mode]
	if view_mode == 0:
		_clear_view()
		view_key = key
		_text_view(u, d)
		return
	if key == view_key:
		return
	_clear_view()
	view_key = key
	if not u["alive"] or not SSD3D.has_data(u["id"]):
		view_box.add_child(UI.label("Scheda non disponibile per questa nave." if u["alive"] else "Nave " + str(u["gone"]), 16, UI.MUTED))
		return
	if view_mode == 1:
		var s2 := SSD2D.new()
		s2.size_flags_vertical = Control.SIZE_EXPAND_FILL
		s2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s2.custom_minimum_size = Vector2(200, 300)
		view_box.add_child(s2)
		s2.setup(eng, selected)
		view_box.add_child(_legend())
	else:
		view_box.add_child(UI.head("Armi e sistemi", 18, UI.TAN))
		var sv2: SubViewportContainer = SSD3D.window(eng, selected, "card")
		sv2.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sv2.custom_minimum_size = Vector2(200, 250)
		view_box.add_child(sv2)
		view_box.add_child(_legend())


## Scudi in 3D accanto ai dati: si ricostruiscono solo quando cambia la nave
func _shield_view(id: int) -> void:
	if id == shield_uid:
		return
	shield_uid = id
	for c in shield_box.get_children():
		shield_box.remove_child(c)
		c.queue_free()
	if id < 0:
		return
	var sv: SubViewportContainer = SSD3D.window(eng, id, "ship")
	sv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.custom_minimum_size = Vector2(170, 200)
	shield_box.add_child(sv)


func _legend() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	for it in [[SSD3D.W_FIRED, "sparata"], [SSD3D.W_READY, "pronta"], [SSD3D.W_IDLE, "scarica"]]:
		var c := ColorRect.new()
		c.color = it[0]
		c.custom_minimum_size = Vector2(16, 16)
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(c)
		var l := UI.label(it[1], 14, UI.MUTED)
		l.custom_minimum_size.x = 64
		hb.add_child(l)
	return hb


func _clear_view() -> void:
	view_key = ""
	for c in view_box.get_children():
		view_box.remove_child(c)
		c.queue_free()


func _info_grid(u: Dictionary, d: Dictionary) -> void:
	if not u["alive"]:
		info_col.add_child(UI.head("Nave " + str(u["gone"]), 20, UI.RED))
		_shield_view(-1)
		return
	var g := info_col
	_shield_view(selected if SSD3D.has_data(u["id"]) else -1)
	var p: Dictionary = eng.power(u)
	_kv(g, "Posizione", "%s prua %s" % [H.label(u["pos"]), H.DIR_LETTERS[u["face"]]])
	_kv(g, "Velocità", "%d virata %d" % [u["speed"], eng.turn_mode_of(u)])
	_kv(g, "Energia", "W%d I%d R%d" % [p["warp"], p["imp"], p["apr"]])
	_kv(g, "Batterie", "%.1f / %d" % [u["batt"], int(u["sys"].get("bt", 0))])
	_kv(g, "Condens.", "%.1f / %.1f" % [u["cap"], eng.cap_max(u)])
	_kv(g, "Sensori", "%d  scan +%d" % [eng._track(u, "sen"), eng._track(u, "scan")], UI.TEXT if u["lock"] else UI.RED)
	_kv(g, "Aggancio", "sì" if u["lock"] else "no", UI.TEXT if u["lock"] else UI.RED)
	_kv(g, "Danni ecc.", "%d / %d" % [u["ex"], u["ex_max"]], UI.RED if int(u["ex"]) > 0 else UI.TEXT)
	if d.has("cloak"):
		_kv(g, "Occultam.", ("attivo" if u["cloak"] > 0 else "spento") + (" ..." if u["cloak_t"] > 0 else ""))
	if int(u["shuttles"]) > 0 or int(u["fighters"]) > 0:
		_kv(g, "Navette", "%d  caccia %d" % [u["shuttles"], u["fighters"]])


func _text_view(u: Dictionary, d: Dictionary) -> void:
	if not u["alive"]:
		return
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	view_box.add_child(sc)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 3)
	sc.add_child(tv)
	# scudi
	_sect(tv, "Scudi" + ("  (spenti)" if not u["sh_on"] else "") + ("  rinforzo gen. %d" % int(u["gr"]) if int(u["gr"]) > 0 else ""), UI.SKY)
	var gs := GridContainer.new()
	gs.columns = 3
	gs.add_theme_constant_override("h_separation", 12)
	gs.add_theme_constant_override("v_separation", 0)
	for i in 6:
		var txt := "#%d %d/%d" % [i + 1, u["sh"][i], u["sh_max"][i]]
		if int(u["sr"][i]) > 0:
			txt += "+%d" % int(u["sr"][i])
		var f := float(u["sh"][i]) / maxf(1.0, float(u["sh_max"][i]))
		var l := UI.mono(txt, 15, (board.shield_color(f).lightened(0.3) if f <= 0.5 else Color(0.6, 0.8, 1.0)) if u["sh_on"] else UI.MUTED)
		l.custom_minimum_size.x = 122
		gs.add_child(l)
	tv.add_child(gs)
	# armi: quelle uguali (tipo, arco e stato) raggruppate
	_sect(tv, "Armi", UI.TAN)
	var groups := []
	for w in u["weapons"]:
		var st := weapon_state(u, w)
		var k: String = "%s|%s|%s" % [w["t"], w["arc"], st]
		if not groups.is_empty() and groups[-1][0] == k:
			groups[-1][1] += 1
		else:
			groups.append([k, 1, w, st])
	var gw := GridContainer.new()
	gw.columns = 2
	gw.add_theme_constant_override("h_separation", 10)
	gw.add_theme_constant_override("v_separation", 0)
	for gr in groups:
		var w: Dictionary = gr[2]
		var st: String = gr[3]
		var cc := UI.TEXT
		if st.begins_with("pronto"):
			cc = UI.GREEN
		elif st == "distrutta":
			cc = UI.RED
		elif st == "sparato" or st == "lanciato":
			cc = UI.MUTED
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		var a := UI.mono("%s%s %s" % ["%dx " % gr[1] if gr[1] > 1 else "", D.WSHORT[w["t"]], w["arc"]], 14, UI.PEACH)
		a.custom_minimum_size.x = 104
		hb.add_child(a)
		var b := UI.label(st, 14, cc)
		b.custom_minimum_size.x = 96
		hb.add_child(b)
		gw.add_child(hb)
	tv.add_child(gw)
	# sistemi
	_sect(tv, "Sistemi", UI.LILAC)
	var g2 := GridContainer.new()
	g2.columns = 2
	g2.add_theme_constant_override("h_separation", 10)
	g2.add_theme_constant_override("v_separation", 0)
	for k in D.SYS_ORDER:
		if not u["max"].has(k) or int(u["max"][k]) == 0:
			continue
		var cur := int(u["sys"][k])
		var mx := int(u["max"][k])
		var hb2 := HBoxContainer.new()
		hb2.add_theme_constant_override("separation", 4)
		var n := UI.label(SYS_SHORT.get(k, D.SYS_NAMES[k]), 14, UI.MUTED)
		n.custom_minimum_size.x = 120
		hb2.add_child(n)
		var v := UI.mono("%d/%d" % [cur, mx], 14, UI.TEXT if cur == mx else (UI.RED if cur == 0 else UI.TAN))
		v.custom_minimum_size.x = 76
		hb2.add_child(v)
		g2.add_child(hb2)
	tv.add_child(g2)


# ================================================================ scheda SSD originale

func _show_ssd() -> void:
	if is_instance_valid(ssd_overlay):
		ssd_overlay.queue_free()
		return
	var u: Dictionary = eng.units.get(selected, {})
	if u.is_empty() or u.get("kind", "") != "ship":
		_say("Seleziona prima una nave.")
		return
	ssd_overlay = Control.new()
	ssd_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ssd_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(ssd_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ssd_overlay.add_child(shade)
	var p := UI.panel(UI.SKY, 0.98)
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 60
	p.offset_right = -60
	p.offset_top = 40
	p.offset_bottom = -40
	ssd_overlay.add_child(p)
	var vb := VBoxContainer.new()
	p.add_child(vb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	var t := UI.head("Scheda SSD originale: " + str(D.ship(u["id"])["n"]), 26, UI.SKY)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	var zoom := [1.0]
	var tr := TextureRect.new()
	tr.texture = load("res://assets/ssd/%s.png" % u["id"])
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var base := Vector2(1400, 1400 * float(tr.texture.get_height()) / float(tr.texture.get_width()))
	tr.custom_minimum_size = base
	var bz := UI.button("Zoom +", 120, 44, 20, UI.SKY)
	bz.pressed.connect(func():
		zoom[0] = minf(3.0, zoom[0] * 1.3)
		tr.custom_minimum_size = base * zoom[0])
	hb.add_child(bz)
	var bz2 := UI.button("Zoom -", 120, 44, 20, UI.SKY)
	bz2.pressed.connect(func():
		zoom[0] = maxf(0.5, zoom[0] / 1.3)
		tr.custom_minimum_size = base * zoom[0])
	hb.add_child(bz2)
	var bc := UI.button("Chiudi", 140, 44, 20, UI.RUST)
	bc.pressed.connect(func(): ssd_overlay.queue_free())
	hb.add_child(bc)
	vb.add_child(UI.label("Lo stato attuale (danni, energia, armi) è nel pannello di sinistra.", 17, UI.MUTED))
	sc.add_child(tr)
	vb.add_child(sc)


## Finestra della scheda: in 3D (cubetti e scudi a strati) per le navi che ce l'hanno, altrimenti
## la scheda originale piatta. Non blocca la partita e segue i danni in tempo reale.
func _open_ssd(uid: int) -> void:
	if eng.units.get(uid, {}).get("kind", "") == "ship" and selected != uid:
		_select(uid)


## Finestra grande della scheda 3D (dal tasto "Ingrandisci" del pannello)
func _open_ssd_window(uid: int) -> void:
	var u: Dictionary = eng.units.get(uid, {})
	if u.is_empty() or u.get("kind", "") != "ship":
		return
	if not SSD3D.has_data(u["id"]):
		if not is_instance_valid(ssd_overlay):
			_show_ssd()
		return
	if is_instance_valid(ssd_win) and ssd_win_uid == uid:
		return
	_close_ssd()
	ssd_win_uid = uid
	ssd_win = UI.panel(UI.SKY, 0.97)
	ssd_win.set_anchors_preset(Control.PRESET_CENTER_TOP)
	ssd_win.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ssd_win.offset_left = -470
	ssd_win.offset_right = 510
	ssd_win.offset_top = 78
	ssd_win.custom_minimum_size = Vector2(980, 600)
	add_child(ssd_win)
	move_child(ssd_win, act_panel.get_index())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	ssd_win.add_child(vb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	var col: Color = D.PCOLORS[int(eng.sides[u["side"]]["col"]) % 8]
	var t := UI.head("%s - %s" % [D.ship(u["id"])["n"], eng.pname(u["side"])], 24, col)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.clip_text = true
	t.custom_minimum_size.x = 400
	hb.add_child(t)
	var b2 := UI.button("Scheda originale", 210, 42, 18, UI.LILAC)
	b2.pressed.connect(_show_ssd)
	hb.add_child(b2)
	var bc := UI.button("Chiudi", 120, 42, 18, UI.RUST)
	bc.pressed.connect(_close_ssd)
	hb.add_child(bc)
	var svc: SubViewportContainer = SSD3D.window(eng, uid)
	svc.custom_minimum_size = Vector2(940, 520)
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(svc)
	vb.add_child(UI.label("Trascina per spostare, rotella o due dita per lo zoom e la rotazione.", 15, UI.MUTED))


func _close_ssd() -> void:
	if is_instance_valid(ssd_win):
		ssd_win.queue_free()
	ssd_win = null
	ssd_win_uid = -1


func _show_rules() -> void:
	var rv = preload("res://scripts/ui/rules_view.gd").new()
	rv.overlay = true
	add_child(rv)


# ================================================================ clic sulla mappa

func _on_unit_clicked(uid: int) -> void:
	var t: Dictionary = eng.units.get(uid, {})
	if t.is_empty():
		return
	if req.get("type", "") == "fire" and eng.enemies(int(req["side"]), int(t["side"])):
		if _fire_targets().has(uid):
			_open_tmenu(uid)
		else:
			_say("Nessuna arma pronta può colpire quel bersaglio.")
		return
	if t["kind"] == "ship":
		_select(uid)
		if req.get("type", "") == "fire":
			if int(t["side"]) == int(req["side"]):
				_close_tmenu()
				_update_markers()
				_fire_bar_update()
		else:
			_open_ssd(uid)


func _on_hex_clicked(h: Vector2i) -> void:
	if req.get("type", "") == "move":
		for g in board.ghosts:
			if g[0] == h:
				_do_move(str(g[2]))
				return
	for id in eng.units:
		var u: Dictionary = eng.units[id]
		if u["pos"] == h and u.get("alive", true):
			_on_unit_clicked(id)
			return


# ================================================================ decisioni

func _clear_act() -> void:
	for c in act_box.get_children():
		act_box.remove_child(c)
		c.queue_free()


func _show_act() -> void:
	act_panel.visible = true
	_fit_act()


## Il pannello delle azioni cresce verso l'alto quanto basta al contenuto
func _fit_act() -> void:
	await get_tree().process_frame
	if not is_instance_valid(act_panel):
		return
	var h := act_panel.get_combined_minimum_size().y
	act_panel.offset_top = act_panel.offset_bottom - h


func _on_request(r: Dictionary) -> void:
	req = r
	var s := int(r["side"])
	phase_lbl.text = _phase_text().to_upper()
	top_lbl.text = "TURNO %d / %d" % [maxi(1, eng.turn), eng.max_turns]
	match r["type"]:
		"energy":
			autopilot.clear()
			plan.clear()
			_energy_start()
		"move":
			move_queue = r["uids"].duplicate()
			move_res = {}
			_move_next()
		"fire":
			if fire_ai.get(s, false):
				_provide(helper_ai.fire_for(eng, s))
				return
			if skip_fire_until.get(s, -1) >= eng.turn * 100 + eng.imp or not _fire_interesting(s):
				_provide({"shots": [], "launch": []})
				return
			fire_sel.clear()
			var mine := eng.ships_of(s)
			if not mine.is_empty() and (selected < 0 or not eng.units.has(selected) or int(eng.units[selected]["side"]) != s):
				_select(int(mine[0]["uid"]))
			_focus_fight()
			_fire_panel()


func _provide(r) -> void:
	req = {}
	_close_tmenu()
	board.set_markers({})
	act_panel.visible = false
	board.set_ghosts([])
	board.show_arc(null, "", 0)
	eng.provide_decision(r)


func _who(s: int) -> String:
	if humans.size() > 1 and online == null:
		return "  [%s]" % eng.pname(s)
	return ""


# ---------------------------------------------------------------- energia

func _energy_start() -> void:
	alloc.clear()
	var s := int(req["side"])
	for u in eng.ships_of(s):
		alloc[u["uid"]] = helper_ai.energy_for(eng, u)
	alloc_tab = 0
	_energy_panel()


func _energy_panel() -> void:
	_clear_act()
	var s := int(req["side"])
	var ships: Array = eng.ships_of(s)
	if ships.is_empty():
		_provide({})
		return
	alloc_tab = clampi(alloc_tab, 0, ships.size() - 1)
	var u: Dictionary = ships[alloc_tab]
	_select(int(u["uid"]))
	var a: Dictionary = alloc[u["uid"]]
	var d: Dictionary = D.ship(u["id"])
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	act_box.add_child(head)
	head.add_child(UI.head("Turno %d - ripartizione dell'energia%s" % [eng.turn, _who(s)], 24, UI.TAN))
	if ships.size() > 1:
		var tabs := HBoxContainer.new()
		tabs.add_theme_constant_override("separation", 6)
		act_box.add_child(tabs)
		for i in ships.size():
			var k: int = i
			var b := UI.button(str(D.ship(ships[i]["id"])["n"]).substr(0, 22), 0, 38, 17, UI.TAN if i == alloc_tab else UI.LILAC)
			b.pressed.connect(func():
				alloc_tab = k
				_energy_panel())
			tabs.add_child(b)
	# barra dell'energia: quanto va a ogni voce e quanto resta
	en_bar = Control.new()
	en_bar.custom_minimum_size = Vector2(980, 30)
	en_bar.draw.connect(_draw_energy_bar.bind(u, a))
	act_box.add_child(en_bar)
	en_info = UI.mono("", 16, UI.GREEN)
	en_info.custom_minimum_size.x = 980
	en_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	act_box.add_child(en_info)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 26)
	act_box.add_child(grid)
	var colA := VBoxContainer.new()
	colA.custom_minimum_size.x = 480
	colA.add_theme_constant_override("separation", 2)
	var colB := VBoxContainer.new()
	colB.custom_minimum_size.x = 470
	colB.add_theme_constant_override("separation", 2)
	grid.add_child(colA)
	var bsc := ScrollContainer.new()
	bsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bsc.custom_minimum_size = Vector2(490, 0)
	bsc.add_child(colB)
	grid.add_child(bsc)
	_slider(colA, "Velocità", 0, eng.max_speed(u), 1, int(a["spd"]),
		func(v): return "%d  (%.1f en.)" % [int(v), v * float(d["mc"])],
		func(v): a["spd"] = int(v), u, a, UI.SKY)
	var phmax: float = eng.cap_max(u) - float(u["cap"])
	_slider(colA, "Phaser (cond. %.1f/%.1f)" % [u["cap"], eng.cap_max(u)], 0, phmax, 0.5, float(a["ph"]),
		func(v): return "%.1f" % v,
		func(v): a["ph"] = float(v), u, a, UI.ORANGE)
	_slider(colA, "Rinforzo generale", 0, 10, 1, int(a.get("gr", 0)),
		func(v): return "%d  (%d en.)" % [int(v), int(v) * 2],
		func(v): a["gr"] = int(v), u, a, UI.BLUE)
	var tg := HBoxContainer.new()
	tg.add_theme_constant_override("separation", 8)
	colA.add_child(tg)
	_toggle(tg, "Scudi (%s)" % str(d["sc"]), a.get("sh", true), func(v): a["sh"] = v)
	_toggle(tg, "Fuoco (1)", a.get("fc", true), func(v): a["fc"] = v)
	if d.has("cloak"):
		_toggle(tg, "Occultam. (%s)" % str(d["cloak"]), a.get("cl", false), func(v): a["cl"] = v)
	colB.add_child(UI.label("Armi pesanti", 18, UI.TAN))
	var any := false
	var nrows := 0
	for i in u["weapons"].size():
		var w: Dictionary = u["weapons"][i]
		if not w["ok"]:
			continue
		var opts: Array = eng.weapon_need(w)
		if opts.size() < 2:
			continue
		any = true
		nrows += 1
		var k2: int = i
		var cur := int(a["w"].get(i, 0))
		var idx0 := maxi(0, opts.find(cur))
		_slider(colB, "%s %s" % [D.WSHORT[w["t"]], w["arc"]], 0, opts.size() - 1, 1, idx0,
			func(v): return "%d  %s" % [int(opts[int(v)]), _arm_desc(w, float(opts[int(v)])).trim_prefix("(").trim_suffix(")")],
			func(v):
				if int(opts[int(v)]) == 0:
					a["w"].erase(k2)
				else:
					a["w"][k2] = int(opts[int(v)]), u, a, UI.RED, 92, 215)
	if not any:
		colB.add_child(UI.label("Nessuna arma da caricare.", 16, UI.MUTED))
	var drn := 0
	for w in u["weapons"]:
		if w["ok"] and w["t"] == "DRN":
			drn += int(w.get("n", 0))
	if drn > 0:
		colB.add_child(UI.label("Droni nelle rampe: %d (nessun costo)" % drn, 16, UI.MUTED))
	bsc.custom_minimum_size.y = mini(nrows, 5) * 36 + 50
	act_box.add_child(UI.label("Rinforzo dei singoli scudi (1 energia per punto)", 17, UI.TEXT))
	var srow := GridContainer.new()
	srow.columns = 3
	srow.add_theme_constant_override("h_separation", 16)
	act_box.add_child(srow)
	for i in 6:
		var k: int = i
		var box := VBoxContainer.new()
		box.custom_minimum_size.x = 310
		srow.add_child(box)
		_slider(box, "Scudo #%d" % (i + 1), 0, 10, 1, int(a["sr"][i]),
			func(v): return "+%d" % int(v),
			func(v): a["sr"][k] = int(v), u, a, UI.SKY, 100, 40)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	act_box.add_child(row)
	var ba := UI.button("Ripartizione automatica", 300, 50, 20, UI.LILAC)
	ba.pressed.connect(func():
		alloc[u["uid"]] = helper_ai.energy_for(eng, u)
		_energy_panel())
	row.add_child(ba)
	en_ok = UI.primary(UI.button("Conferma", 240, 50, 22))
	en_ok.pressed.connect(func():
		var out := {}
		for k in alloc:
			out[k] = alloc[k]
		_provide(out))
	row.add_child(en_ok)
	en_warn = UI.label("", 17, UI.RED)
	en_warn.custom_minimum_size.x = 380
	row.add_child(en_warn)
	_energy_refresh(u, a)
	_show_act()


var en_bar: Control
var en_info: Label
var en_ok: Button
var en_warn: Label


func _energy_refresh(u: Dictionary, a: Dictionary) -> void:
	var cost: Dictionary = eng.alloc_cost(u, a)
	var p: Dictionary = eng.power(u)
	if is_instance_valid(en_info):
		en_info.text = "Disponibile %.1f (warp %d, impulso %d, reattori %d, batterie %.1f)   Usata %.1f   Movimento e fotoni dal warp: %.1f su %.1f" % [p["total"], p["warp"], p["imp"], p["apr"], p["batt"], cost["tot"], cost["warp_need"], cost["warp_av"]]
		en_info.add_theme_color_override("font_color", UI.GREEN if cost["ok"] else UI.RED)
	if is_instance_valid(en_ok):
		en_ok.disabled = not cost["ok"]
	if is_instance_valid(en_warn):
		en_warn.text = "" if cost["ok"] else ("Troppa energia dal warp: riduci velocità o fotoni." if cost["warp_need"] > cost["warp_av"] + 0.001 else "Energia insufficiente: riduci qualcosa.")
	if is_instance_valid(en_bar):
		en_bar.queue_redraw()


## Barra segmentata: fissi, movimento, phaser, armi, rinforzi, libera
func _draw_energy_bar(u: Dictionary, a: Dictionary) -> void:
	var d: Dictionary = D.ship(u["id"])
	var tot: float = maxf(1.0, eng.power(u)["total"])
	var fixed := float(d["ls"]) + (1.0 if a.get("fc", true) else 0.0) + (float(d["sc"]) if a.get("sh", true) else 0.0)
	if a.get("cl", false) and d.has("cloak"):
		fixed += float(d["cloak"])
	var weap := 0.0
	for k in a.get("w", {}):
		weap += float(a["w"][k])
	var reinf := 2.0 * int(a.get("gr", 0))
	for v in a.get("sr", []):
		reinf += float(v)
	var parts := [[fixed, UI.LILAC, "SISTEMI"], [float(a["spd"]) * float(d["mc"]), UI.SKY, "MOTORI"], [float(a["ph"]), UI.ORANGE, "PHASER"], [weap, UI.RED, "ARMI"], [reinf, UI.BLUE, "SCUDI"]]
	var w := en_bar.size.x
	var h := en_bar.size.y
	en_bar.draw_rect(Rect2(0, 0, w, h), Color("#14121f"))
	var x := 0.0
	var used := 0.0
	for pt in parts:
		var pw: float = w * float(pt[0]) / tot
		if pw <= 0.5:
			continue
		en_bar.draw_rect(Rect2(x, 0, minf(pw, w - x), h), pt[1])
		if pw > 70:
			en_bar.draw_string(UI.font_head, Vector2(x + 8, h - 8), "%s %.0f" % [pt[2], pt[0]], HORIZONTAL_ALIGNMENT_LEFT, pw - 10, 16, Color("#120a00"))
		x += pw
		used += float(pt[0])
		if x >= w:
			break
	if used > tot + 0.001:
		en_bar.draw_rect(Rect2(w - 8, 0, 8, h), UI.RED)
	elif w - x > 70:
		en_bar.draw_string(UI.font_head, Vector2(x + 8, h - 8), "LIBERA %.1f" % (tot - used), HORIZONTAL_ALIGNMENT_LEFT, w - x - 10, 16, UI.MUTED)


static var _grab_tex: Texture2D


func _grabber() -> Texture2D:
	if _grab_tex == null:
		var img := Image.create(30, 30, false, Image.FORMAT_RGBA8)
		for y in 30:
			for x in 30:
				var dd := Vector2(x - 14.5, y - 14.5).length()
				var c := Color(0, 0, 0, 0)
				if dd < 13.5:
					c = Color("#ffcc99") if dd > 9.5 else Color("#ff9c00")
				elif dd < 14.5:
					c = Color(1, 0.8, 0.6, 14.5 - dd)
				img.set_pixel(x, y, c)
		_grab_tex = ImageTexture.create_from_image(img)
	return _grab_tex


## Cursore a scorrimento: aggiorna subito la ripartizione senza ricostruire il pannello
func _slider(parent: Control, label: String, minv: float, maxv: float, step: float, cur: float, fmt: Callable, setf: Callable, u: Dictionary, a: Dictionary, col: Color, label_w := 170, val_w := 150) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var l := UI.label(label, 17, UI.TEXT)
	l.custom_minimum_size.x = label_w
	l.clip_text = true
	hb.add_child(l)
	var sl := HSlider.new()
	sl.min_value = minv
	sl.max_value = maxf(maxv, minv + step) if maxv > minv else minv + step
	sl.editable = maxv > minv
	sl.step = step
	sl.value = cur
	sl.custom_minimum_size = Vector2(150, 34)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.focus_mode = Control.FOCUS_NONE
	var track := UI.box(Color("#2a2640"), Color("#2a2640"), 0, 6, 0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	sl.add_theme_stylebox_override("slider", track)
	var fill := UI.box(col, col, 0, 6, 0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	sl.add_theme_icon_override("grabber", _grabber())
	sl.add_theme_icon_override("grabber_highlight", _grabber())
	sl.add_theme_icon_override("grabber_disabled", _grabber())
	hb.add_child(sl)
	var v := UI.mono(str(fmt.call(cur)), 17, UI.TAN)
	v.custom_minimum_size.x = val_w
	v.clip_text = true
	hb.add_child(v)
	sl.value_changed.connect(func(x):
		setf.call(x)
		v.text = str(fmt.call(x))
		_energy_refresh(u, a))
	parent.add_child(hb)


func _arm_desc(w: Dictionary, e: float) -> String:
	var t: String = w["t"]
	if t == "PHOT":
		if w["st"] == 0:
			return "(1° turno di carica)" if e >= 2 else "(scarico)"
		if w["st"] == 1:
			return ("(pronto, sovracc. +%d)" % int(e - 2) if e > 2 else "(pronto)") if e >= 2 else "(si scarica!)"
		return ("(tenuto pronto%s)" % (", sovracc. +%d" % int(e - 1) if e > 1 else "")) if e >= 1 else "(si scarica!)"
	if t == "DISR":
		return "(sovraccarico)" if e >= 4 else ("(pronto)" if e >= 2 else "(spento)")
	if D.is_plasma(t):
		if w["st"] >= 3:
			return "(tenuto pronto)" if e > 0 or D.PL_HOLD[w["pt"]] == 0 else "(si scarica!)"
		return "(carica %d/3)" % (int(w["st"]) + 1) if e > 0 else "(spento)"
	return ""


func _stepper(parent: Control, label: String, val: String, fn: Callable) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var l := UI.label(label, 17, UI.TEXT)
	l.custom_minimum_size.x = 320
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	hb.add_child(l)
	var bm := UI.small("-", UI.LILAC)
	bm.pressed.connect(func():
		fn.call(-1)
		_energy_panel())
	hb.add_child(bm)
	var v := UI.mono(val, 19, UI.TAN)
	v.custom_minimum_size.x = 48
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(v)
	var bp := UI.small("+", UI.ORANGE)
	bp.pressed.connect(func():
		fn.call(1)
		_energy_panel())
	hb.add_child(bp)
	parent.add_child(hb)


func _toggle(parent: Control, label: String, on: bool, fn: Callable) -> void:
	var hb := HBoxContainer.new()
	var b := UI.small(label + (": SÌ" if on else ": NO"), UI.GREEN if on else UI.MUTED, 150)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(func():
		fn.call(not on)
		_energy_panel())
	hb.add_child(b)
	parent.add_child(hb)


# ---------------------------------------------------------------- movimento

func _move_next() -> void:
	while not move_queue.is_empty():
		var uid: int = move_queue[0]
		var u: Dictionary = eng.units[uid]
		var mode: String = autopilot.get(uid, "")
		var q: Array = plan.get(uid, [])
		if not q.is_empty():
			var m: String = q.pop_front()
			if m in eng.legal_moves(u):
				move_res[uid] = m
				move_queue.pop_front()
				continue
			plan[uid] = []
		if mode == "auto":
			move_res[uid] = helper_ai.move_for(eng, u)
			move_queue.pop_front()
			continue
		if mode == "rotta":
			move_res[uid] = "F"
			move_queue.pop_front()
			continue
		_move_panel(u)
		return
	_provide(move_res.duplicate())


func _move_targets(u: Dictionary) -> Array:
	var out := []
	var f: int = u["face"]
	var names := {"F": "AVANTI", "L": "VIRA SX", "R": "VIRA DX", "SL": "SCARTO SX", "SR": "SCARTO DX"}
	for m in eng.legal_moves(u):
		var dirn := f
		match m:
			"L":
				dirn = posmod(f - 1, 6)
			"R":
				dirn = posmod(f + 1, 6)
			"SL":
				dirn = posmod(f - 1, 6)
			"SR":
				dirn = posmod(f + 1, 6)
		var h := H.neighbor(u["pos"], dirn)
		var col := UI.SKY if m.begins_with("S") else (UI.TAN if m == "F" else UI.ORANGE)
		if not H.on_map(h):
			col = UI.RED
		var dup := false
		for o in out:
			if o[0] == h:
				o[1] = str(o[1]) + " / " + str(names[m])
				dup = true
		if not dup:
			out.append([h, names[m], m, col])
	return out


func _move_panel(u: Dictionary) -> void:
	_clear_act()
	_select(int(u["uid"]))
	board.focus_hex(u["pos"])
	var gh := _move_targets(u)
	board.set_ghosts(gh)
	_update_markers()
	var s := int(req["side"])
	act_box.add_child(UI.head("Impulso %d - movimento: %s%s" % [eng.imp, D.ship(u["id"])["n"], _who(s)], 24, UI.TAN))
	var tm: int = eng.turn_mode_of(u)
	var info := "Velocità %d, prua %s, modo di virata %d: %s" % [u["speed"], H.DIR_LETTERS[u["face"]], tm, "puoi virare." if int(u["straight"]) >= tm else "hai fatto %d esagoni dritti su %d, non puoi ancora virare." % [u["straight"], tm]]
	if not _fire_targets(int(u["uid"])).is_empty():
		info += " Le frecce indicano i bersagli a tiro di questa nave."
	act_box.add_child(UI.label(info, 17, UI.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	act_box.add_child(row)
	var legal: Array = eng.legal_moves(u)
	for spec in [["SL", "Scarto sx", UI.SKY], ["L", "Vira a sinistra", UI.ORANGE], ["F", "Avanti", UI.TAN], ["R", "Vira a destra", UI.ORANGE], ["SR", "Scarto dx", UI.SKY]]:
		var b := UI.button(spec[1], 150, 54, 21, spec[2])
		b.disabled = not (spec[0] in legal)
		var m: String = spec[0]
		b.pressed.connect(func(): _do_move(m))
		row.add_child(b)
	for g in gh:
		if not H.on_map(g[0]):
			act_box.add_child(UI.label("Attenzione: uscire dalla mappa significa disimpegnarsi (la nave lascia la battaglia).", 16, UI.RED))
			break
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	act_box.add_child(row2)
	var bq := UI.button("Avanti per 4", 170, 44, 18, UI.LILAC)
	bq.pressed.connect(func():
		plan[u["uid"]] = ["F", "F", "F"]
		_do_move("F"))
	row2.add_child(bq)
	var br := UI.button("Mantieni la rotta", 220, 44, 18, UI.LILAC)
	br.pressed.connect(func():
		autopilot[u["uid"]] = "rotta"
		_say("Rotta mantenuta per %s fino al prossimo turno." % D.ship(u["id"])["n"])
		_do_move("F"))
	row2.add_child(br)
	var ba := UI.button("Pilota automatico", 230, 44, 18, UI.BLUE)
	ba.pressed.connect(func():
		autopilot[u["uid"]] = "auto"
		_say("Pilota automatico inserito per %s fino al prossimo turno." % D.ship(u["id"])["n"])
		_do_move(helper_ai.move_for(eng, u)))
	row2.add_child(ba)
	row2.add_child(UI.label("Tasti: A Q W E D", 16, UI.MUTED))
	_show_act()


func _do_move(m: String) -> void:
	if req.get("type", "") != "move" or move_queue.is_empty():
		return
	var uid: int = move_queue.pop_front()
	move_res[uid] = m
	board.set_ghosts([])
	board.set_markers({})
	_move_next()


func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	if req.get("type", "") == "move" and not move_queue.is_empty():
		var u: Dictionary = eng.units[move_queue[0]]
		var legal: Array = eng.legal_moves(u)
		var m := ""
		match ev.keycode:
			KEY_W:
				m = "F"
			KEY_Q:
				m = "L"
			KEY_E:
				m = "R"
			KEY_A:
				m = "SL"
			KEY_D:
				m = "SR"
		if m != "" and m in legal:
			_do_move(m)
	elif req.get("type", "") == "fire" and ev.keycode == KEY_SPACE:
		_provide({"shots": [], "launch": []})


# ---------------------------------------------------------------- fuoco

## Vale la pena fermarsi a chiedere? (un colpo sensato o una minaccia vicina)
func _fire_interesting(s: int) -> bool:
	for u in eng.ships_of(s):
		for x in eng.units.values():
			if x.get("kind", "") in ["drone", "plasma"] and int(x["target"]) == int(u["uid"]) and H.dist(x["pos"], u["pos"]) <= 4:
				return true
		for i in u["weapons"].size():
			if not eng.weapon_usable(u, i):
				continue
			var w: Dictionary = u["weapons"][i]
			for tid in eng.targets_for(u, i):
				var t: Dictionary = eng.units[tid]
				if t["kind"] != "ship":
					continue
				var er: int = eng.eff_range(u, t)
				var r := H.dist(u["pos"], t["pos"])
				if D.is_phaser(w["t"]) and D.phaser_damage(w["t"], 1, er) > 0 and (er <= 12 or eng.imp >= 30):
					return true
				if w["t"] == "PHOT" and (er <= 12 or eng.imp >= 31):
					return true
				if w["t"] == "DISR" and (er <= 15 or eng.imp >= 32):
					return true
				if (D.is_plasma(w["t"]) or w["t"] == "DRN") and r <= 15:
					return true
		if eng.can_launch_shuttle(u):
			for e in eng.live_ships():
				if eng.enemies(s, e["side"]) and H.dist(u["pos"], e["pos"]) <= 6:
					return true
	return false


## Inquadra la nave selezionata e il nemico più vicino
func _focus_fight() -> void:
	var u: Dictionary = eng.units.get(selected, {})
	if u.is_empty():
		return
	var e = helper_ai.nearest_enemy(eng, u)
	if e == null:
		board.focus_hex(u["pos"])
		return
	var a := H.world(u["pos"])
	var b := H.world(e["pos"])
	board.target_goal = (a + b) * 0.5 + Vector3(sin(board.yaw), 0, cos(board.yaw)) * board.dist * 0.25
	board.dist = clampf(a.distance_to(b) * 1.3 + 12.0, 18.0, 70.0)


# ---------------------------------------------------------------- fuoco dalla mappa
## In ogni impulso di fuoco i bersagli a tiro hanno una freccia; toccandola si apre accanto al
## bersaglio un mini menu con le armi che possono colpirlo, con probabilità e danni attesi.

var tmenu: PanelContainer
var tmenu_tid := -1
var fire_bar_lbl: Label
var fire_btn: Button


## Bersagli possibili della nave selezionata: tid -> [[uid, indice arma], ...]. Solo le armi pronte,
## con il bersaglio dentro il loro arco e a una distanza in cui possono fare danni.
func _fire_targets(only := -2) -> Dictionary:
	var out := {}
	if only == -2:
		only = selected
	var u: Dictionary = eng.units.get(only, {})
	if u.is_empty() or u.get("kind", "") != "ship" or not u["alive"]:
		return out
	if not u["fc"] or u["cloak"] > 0 or u["cloak_t"] > 0:
		return out
	for i in u["weapons"].size():
		if not eng.weapon_usable(u, i):
			continue
		for tid in eng.targets_for(u, i):
			if float(_shot_info(u, i, tid)[0]) <= 0.0:
				continue
			if not out.has(tid):
				out[tid] = []
			out[tid].append([u["uid"], i])
	return out


## La prima nave del lato di turno che ha bersagli (se la selezionata non ne ha)
func _pick_firing_ship(s: int) -> void:
	var cur: Dictionary = eng.units.get(selected, {})
	if not cur.is_empty() and int(cur.get("side", -1)) == s and cur["alive"] and not _fire_targets(selected).is_empty():
		return
	for u in eng.ships_of(s):
		if not _fire_targets(int(u["uid"])).is_empty():
			_select(int(u["uid"]))
			return


func _update_markers() -> void:
	var mk := {}
	for tid in _fire_targets():
		var t: Dictionary = eng.units[tid]
		mk[tid] = Color(1.0, 0.3, 0.2) if t["kind"] == "ship" else Color(1.0, 0.75, 0.2)
	board.set_markers(mk)


## Probabilità di colpire (0-1), danni attesi e descrizione breve di un colpo
func _shot_info(u: Dictionary, i: int, tid: int) -> Array:
	var t: Dictionary = eng.units[tid]
	var w: Dictionary = u["weapons"][i]
	var r := H.dist(u["pos"], t["pos"])
	var er: int = eng.eff_range(u, t)
	if D.is_phaser(w["t"]):
		var tot := 0
		var hits := 0
		for dd in range(1, 7):
			var x := D.phaser_damage(w["t"], dd, er)
			tot += x
			if x > 0:
				hits += 1
		return [hits / 6.0, tot / 6.0, ""]
	if w["t"] == "PHOT":
		var ov := int(w["ov"]) > 0
		var c := D.col_index(D.PHOT_COLS, er if (not ov or er <= 8) else r)
		var need: int = (D.PHOT_HIT_OV[c] if ov else D.PHOT_HIT[c]) if c >= 0 else 0
		var dmg := 8 + 2 * int(w["ov"])
		return [need / 6.0, need / 6.0 * dmg, "%d danni" % dmg]
	if w["t"] == "DISR":
		var ov2 := int(w["ov"]) > 0
		var c2 := D.col_index(D.DISR_COLS, er if (not ov2 or er <= 8) else r)
		if c2 < 0:
			return [0.0, 0.0, ""]
		var need2: int = D.DISR_HIT_OV[c2] if ov2 else D.DISR_HIT[c2]
		var dmg2: int = D.DISR_DMG_OV[c2] if ov2 else D.DISR_DMG[c2]
		return [need2 / 6.0, need2 / 6.0 * dmg2, "%d danni" % dmg2]
	if D.is_plasma(w["t"]):
		var st := D.plasma_strength(w["pt"], r)
		return [1.0, float(st), "testata %d, cala con la strada" % st]
	if w["t"] == "DRN":
		return [1.0, float(D.DRONE_DMG), "drone da %d, arriva in %d impulsi" % [D.DRONE_DMG, int(ceil(r * 32.0 / D.DRONE_SPEED))]]
	return [0.0, 0.0, ""]


func _fire_panel() -> void:
	_close_tmenu()
	_clear_act()
	var s := int(req["side"])
	_pick_firing_ship(s)
	_update_markers()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	act_box.add_child(hb)
	var hd := UI.head("Impulso %d - fuoco%s" % [eng.imp, _who(s)], 24, UI.TAN)
	hd.custom_minimum_size.x = 260
	hb.add_child(hd)
	fire_bar_lbl = UI.label("", 17, UI.TEXT)
	fire_bar_lbl.custom_minimum_size.x = 380
	fire_bar_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fire_bar_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hb.add_child(fire_bar_lbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	act_box.add_child(row)
	fire_btn = UI.primary(UI.button("Fuoco!", 170, 52, 22))
	fire_btn.pressed.connect(_fire_send)
	row.add_child(fire_btn)
	var bp := UI.button("Non sparare", 170, 52, 20, UI.LILAC)
	bp.pressed.connect(func(): _provide({"shots": [], "launch": []}))
	row.add_child(bp)
	var bt := UI.button("Attendi 4 impulsi", 190, 52, 18, UI.LILAC)
	bt.pressed.connect(func():
		skip_fire_until[s] = eng.turn * 100 + eng.imp + 3
		_provide({"shots": [], "launch": []}))
	row.add_child(bt)
	var bai := UI.button("Fuoco automatico", 190, 52, 18, UI.BLUE)
	bai.pressed.connect(func(): _provide(helper_ai.fire_for(eng, s)))
	row.add_child(bai)
	var bl := UI.button("Elenco armi", 150, 52, 18, UI.SKY)
	bl.pressed.connect(_fire_list)
	row.add_child(bl)
	for u in eng.ships_of(s):
		if eng.can_launch_shuttle(u):
			var uid: int = u["uid"]
			var bs := UI.button(("Caccia" if int(u["fighters"]) > 0 else "Navetta") + " da " + str(D.ship(u["id"])["n"]).substr(0, 14), 0, 52, 17, UI.SKY)
			bs.pressed.connect(func():
				var shots := _collect_shots()
				shots["launch"].append([uid, "shut", 0])
				_provide(shots))
			row.add_child(bs)
			break
	_fire_bar_update()
	_show_act()


func _fire_bar_update() -> void:
	if not is_instance_valid(fire_bar_lbl):
		return
	var n := fire_sel.size()
	var su: Dictionary = eng.units.get(selected, {})
	var who := ""
	if not su.is_empty() and eng.ships_of(int(req.get("side", -1))).size() > 1:
		who = "Spara: %s (tocca un'altra tua nave per cambiare). " % D.ship(su["id"])["n"]
	var exp := 0.0
	for key in fire_sel:
		var p: PackedStringArray = key.split(":")
		exp += float(_shot_info(eng.units[int(p[0])], int(p[1]), int(fire_sel[key]))[1])
	if n == 0:
		fire_bar_lbl.text = who + ("Tocca una freccia sopra un bersaglio per scegliere le armi." if not _fire_targets().is_empty() else "Questa nave non ha bersagli a tiro.")
	else:
		fire_bar_lbl.text = who + "%d armi pronte a sparare, circa %.0f danni attesi." % [n, exp]
	if is_instance_valid(fire_btn):
		fire_btn.text = ("FUOCO! (%d)" % n) if n > 0 else "FUOCO!"
		fire_btn.disabled = n == 0


func _close_tmenu() -> void:
	if is_instance_valid(tmenu):
		tmenu.queue_free()
	tmenu = null
	tmenu_tid = -1


func _open_tmenu(tid: int) -> void:
	_close_tmenu()
	var tg := _fire_targets()
	if not tg.has(tid):
		return
	tmenu_tid = tid
	var t: Dictionary = eng.units[tid]
	tmenu = PanelContainer.new()
	var fr := UI.frame(UI.RED, 0.94)
	fr.border_width_left = 8
	fr.border_width_top = 3
	fr.corner_radius_top_left = 14
	fr.corner_radius_bottom_left = 14
	fr.content_margin_left = 14
	fr.content_margin_right = 8
	fr.content_margin_top = 6
	fr.content_margin_bottom = 6
	tmenu.add_theme_stylebox_override("panel", fr)
	tmenu.custom_minimum_size = Vector2(300, 0)
	add_child(tmenu)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	tmenu.add_child(vb)
	var nm: String = str(D.ship(t["id"])["n"]) if t["kind"] == "ship" else str(t["name"])
	var title := UI.head(nm, 18, UI.PEACH)
	title.custom_minimum_size.x = 270
	title.clip_text = true
	vb.add_child(title)
	if t["kind"] == "ship":
		var some: Array = tg[tid][0]
		var shooter: Dictionary = eng.units[some[0]]
		var shi: int = eng._shield_hit(t, shooter["pos"])
		var f := float(t["sh"][shi]) / maxf(1.0, float(t["sh_max"][shi]))
		vb.add_child(UI.label("Scudo #%d: %d/%d%s" % [shi + 1, t["sh"][shi], t["sh_max"][shi], " debole!" if f <= 0.2 else ""], 14, board.shield_color(f) if f <= 0.5 else UI.SKY))
	var list: Array = tg[tid]
	list.sort_custom(func(a, b): return _shot_info(eng.units[a[0]], a[1], tid)[1] > _shot_info(eng.units[b[0]], b[1], tid)[1])
	var more := {}
	for e in list:
		var u: Dictionary = eng.units[e[0]]
		var i: int = e[1]
		var w: Dictionary = u["weapons"][i]
		var info: Array = _shot_info(u, i, tid)
		var key := "%d:%d" % [u["uid"], i]
		var on: bool = fire_sel.get(key, -1) == tid
		var other: bool = fire_sel.has(key) and not on
		var txt := "%s %s" % [D.WSHORT[w["t"]], w["arc"]]
		if more.size() > 1:
			txt += " (%s)" % str(D.ship(u["id"])["n"]).substr(0, 10)
		txt += "  %d%%  %.1f danni" % [int(round(info[0] * 100)), info[1]]
		var b := _mini_btn(txt, 270, UI.GREEN if on else (UI.DIM if other else UI.LILAC))
		b.tooltip_text = str(info[2]) + ("  (già puntata su un altro bersaglio)" if other else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func():
			if on:
				fire_sel.erase(key)
			else:
				fire_sel[key] = tid
			_fire_bar_update()
			_open_tmenu(tid))
		vb.add_child(b)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 4)
	vb.add_child(r2)
	var ba := _mini_btn("Tutte", 84, UI.TAN)
	ba.pressed.connect(func():
		for e2 in list:
			if _shot_info(eng.units[e2[0]], e2[1], tid)[0] > 0.0:
				fire_sel["%d:%d" % [e2[0], e2[1]]] = tid
		_fire_bar_update()
		_open_tmenu(tid))
	r2.add_child(ba)
	var bn := _mini_btn("Nessuna", 92, UI.LILAC)
	bn.pressed.connect(func():
		for e3 in list:
			if fire_sel.get("%d:%d" % [e3[0], e3[1]], -1) == tid:
				fire_sel.erase("%d:%d" % [e3[0], e3[1]])
		_fire_bar_update()
		_open_tmenu(tid))
	r2.add_child(bn)
	var bc := _mini_btn("Chiudi", 84, UI.RUST)
	bc.pressed.connect(_close_tmenu)
	r2.add_child(bc)
	_place_tmenu()


## Pulsantino del mini menu delle armi
func _mini_btn(t: String, w: int, col: Color) -> Button:
	var b := Button.new()
	b.text = t.to_upper()
	b.custom_minimum_size = Vector2(w, 28)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	for k in ["normal", "hover", "pressed"]:
		var c: Color = col if k == "normal" else (col.lightened(0.3) if k == "hover" else UI.TAN)
		var st := UI.box(c, c, 0, 14, 2)
		st.content_margin_left = 12
		st.content_margin_right = 12
		b.add_theme_stylebox_override(k, st)
	return b


## Il mini menu segue il bersaglio sullo schermo, restando dentro la vista
func _place_tmenu() -> void:
	if not is_instance_valid(tmenu):
		return
	var sp: Vector2 = board.unit_screen(tmenu_tid)
	var vs := get_viewport_rect().size
	var sz := tmenu.get_combined_minimum_size()
	var pos := sp + Vector2(50, -sz.y * 0.5)
	if pos.x + sz.x > vs.x - 410:
		pos.x = sp.x - 50 - sz.x
	pos.x = clampf(pos.x, 445, maxf(445, vs.x - 410 - sz.x))
	pos.y = clampf(pos.y, 74, vs.y - sz.y - 140)
	tmenu.position = pos
	tmenu.size = sz


func _process(_dt: float) -> void:
	if is_instance_valid(tmenu):
		if not eng.units.has(tmenu_tid):
			_close_tmenu()
		else:
			_place_tmenu()


func _fire_assign(tid: int) -> void:
	var u: Dictionary = eng.units.get(selected, {})
	if u.is_empty() or int(u.get("side", -1)) != int(req["side"]):
		return
	var n := 0
	for i in u["weapons"].size():
		if eng.weapon_usable(u, i) and tid in eng.targets_for(u, i):
			var key := "%d:%d" % [u["uid"], i]
			if fire_sel.has(key) and fire_sel[key] != tid:
				continue
			if not fire_sel.has(key):
				fire_sel[key] = tid
				n += 1
	if n == 0:
		_say("Nessuna arma pronta di questa nave può colpire quel bersaglio.")
	_fire_panel()


func _target_info(u: Dictionary, i: int, tid: int) -> String:
	var t: Dictionary = eng.units[tid]
	var w: Dictionary = u["weapons"][i]
	var r := H.dist(u["pos"], t["pos"])
	if t["kind"] != "ship":
		return "%s a %d" % [t["name"], r]
	var er: int = eng.eff_range(u, t)
	var extra := ""
	if D.is_phaser(w["t"]):
		var tot := 0
		for dd in range(1, 7):
			tot += D.phaser_damage(w["t"], dd, er)
		extra = "~%.1f danni" % (tot / 6.0)
	elif w["t"] == "PHOT":
		var ov := int(w["ov"]) > 0
		var c := D.col_index(D.PHOT_COLS, er if (not ov or er <= 8) else r)
		var need: int = (D.PHOT_HIT_OV[c] if ov else D.PHOT_HIT[c]) if c >= 0 else 0
		extra = "colpisce con 1-%d, %d danni" % [need, 8 + 2 * int(w["ov"])] if need > 0 else "fuori portata"
	elif w["t"] == "DISR":
		var c2 := D.col_index(D.DISR_COLS, er)
		if c2 >= 0:
			extra = "colpisce con 1-%d, %d danni" % [D.DISR_HIT[c2], D.DISR_DMG[c2]]
	elif D.is_plasma(w["t"]):
		extra = "testata %d" % D.plasma_strength(w["pt"], r)
	return "%s  dist %d (eff. %d)  %s" % [str(D.ship(t["id"])["n"]).substr(0, 30), r, er, extra]


func _fire_list() -> void:
	_close_tmenu()
	_clear_act()
	var s := int(req["side"])
	var head := HBoxContainer.new()
	act_box.add_child(head)
	head.add_child(UI.head("Impulso %d - fuoco e lanci%s" % [eng.imp, _who(s)], 24, UI.TAN))
	var u: Dictionary = eng.units.get(selected, {})
	if u.is_empty() or int(u.get("side", -1)) != s or not u["alive"]:
		var mine := eng.ships_of(s)
		if mine.is_empty():
			_provide({"shots": [], "launch": []})
			return
		u = mine[0]
		_select(int(u["uid"]))
	var ships: Array = eng.ships_of(s)
	if ships.size() > 1:
		var tabs := HBoxContainer.new()
		tabs.add_theme_constant_override("separation", 6)
		act_box.add_child(tabs)
		for sh in ships:
			var id: int = sh["uid"]
			var nsel := 0
			for k in fire_sel:
				if k.begins_with("%d:" % id):
					nsel += 1
			var b := UI.button(str(D.ship(sh["id"])["n"]).substr(0, 18) + (" (%d)" % nsel if nsel > 0 else ""), 0, 38, 17, UI.TAN if id == int(u["uid"]) else UI.LILAC)
			b.pressed.connect(func():
				_select(id)
				_fire_list())
			tabs.add_child(b)
	act_box.add_child(UI.label("Scegli le armi e il bersaglio (puoi anche toccare il bersaglio sulla mappa). Tutti sparano insieme.", 16, UI.MUTED))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(940, 0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	act_box.add_child(sc)
	var rows := 0
	for i in u["weapons"].size():
		if not eng.weapon_usable(u, i):
			continue
		var tg: Array = eng.targets_for(u, i)
		if tg.is_empty():
			continue
		tg.sort_custom(func(a, b): return H.dist(u["pos"], eng.units[a]["pos"]) < H.dist(u["pos"], eng.units[b]["pos"]))
		rows += 1
		var w: Dictionary = u["weapons"][i]
		var key := "%d:%d" % [u["uid"], i]
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		var on := fire_sel.has(key)
		var cb := UI.button(("Sì  " if on else "No  ") + str(D.WSHORT[w["t"]]) + " " + str(w["arc"]), 190, 40, 18, UI.GREEN if on else UI.MUTED)
		var wi: int = i
		cb.pressed.connect(func():
			if fire_sel.has(key):
				fire_sel.erase(key)
			else:
				fire_sel[key] = tg[0]
			_fire_list())
		cb.mouse_entered.connect(func(): board.show_arc(u, w["arc"], mini(D.max_range(w["t"]), 30)))
		hb.add_child(cb)
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(700, 40)
		ob.add_theme_font_size_override("font_size", 17)
		ob.focus_mode = Control.FOCUS_NONE
		var cur = fire_sel.get(key, tg[0])
		for j in tg.size():
			ob.add_item(_target_info(u, wi, tg[j]), j)
			if tg[j] == cur:
				ob.select(j)
		ob.item_selected.connect(func(j):
			fire_sel[key] = tg[j]
			_fire_list())
		hb.add_child(ob)
		list.add_child(hb)
	if rows == 0:
		list.add_child(UI.label("Questa nave non ha armi pronte con bersagli negli archi.", 17, UI.MUTED))
	sc.custom_minimum_size.y = mini(rows, 6) * 44 + 8
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	act_box.add_child(row)
	var nsel2 := fire_sel.size()
	var bf := UI.primary(UI.button("Fuoco! (%d)" % nsel2 if nsel2 > 0 else "Fuoco!", 160, 52, 22))
	bf.disabled = nsel2 == 0
	bf.pressed.connect(_fire_send)
	row.add_child(bf)
	var ball := UI.button("Tutte", 120, 52, 20, UI.TAN)
	ball.pressed.connect(func():
		for i2 in u["weapons"].size():
			if eng.weapon_usable(u, i2):
				var tg2: Array = eng.targets_for(u, i2)
				var best = null
				var bd := 9999
				for t2 in tg2:
					if eng.units[t2]["kind"] == "ship" and H.dist(u["pos"], eng.units[t2]["pos"]) < bd:
						bd = H.dist(u["pos"], eng.units[t2]["pos"])
						best = t2
				if best != null:
					fire_sel["%d:%d" % [u["uid"], i2]] = best
		_fire_list())
	row.add_child(ball)
	var bmap := UI.button("Mira sulla mappa", 200, 52, 18, UI.SKY)
	bmap.pressed.connect(_fire_panel)
	row.add_child(bmap)
	var bp := UI.button("Non sparare", 170, 52, 20, UI.LILAC)
	bp.pressed.connect(func(): _provide({"shots": [], "launch": []}))
	row.add_child(bp)
	var bt := UI.button("Attendi 4 impulsi", 190, 52, 18, UI.LILAC)
	bt.pressed.connect(func():
		skip_fire_until[s] = eng.turn * 100 + eng.imp + 3
		_provide({"shots": [], "launch": []}))
	row.add_child(bt)
	var bai := UI.button("Fuoco automatico", 190, 52, 18, UI.BLUE)
	bai.pressed.connect(func():
		_provide(helper_ai.fire_for(eng, s)))
	row.add_child(bai)
	if eng.can_launch_shuttle(u):
		var bl := UI.button("Lancia caccia" if int(u["fighters"]) > 0 else "Lancia navetta", 170, 52, 18, UI.SKY)
		bl.pressed.connect(func():
			var shots := _collect_shots()
			shots["launch"].append([u["uid"], "shut", 0])
			_provide(shots))
		row.add_child(bl)
	_show_act()


func _collect_shots() -> Dictionary:
	var shots := []
	var launch := []
	for key in fire_sel:
		var parts: PackedStringArray = key.split(":")
		var uid := int(parts[0])
		var wi := int(parts[1])
		var w: Dictionary = eng.units[uid]["weapons"][wi]
		if w["t"] == "DRN" or D.is_plasma(w["t"]):
			launch.append([uid, str(wi), fire_sel[key]])
		else:
			shots.append([uid, wi, fire_sel[key]])
	return {"shots": shots, "launch": launch}


func _fire_send() -> void:
	_provide(_collect_shots())


# ================================================================ online

func online_waiting(s: int, slow: bool) -> void:
	if s < 0:
		wait_lbl.text = ""
	else:
		wait_lbl.text = "In attesa di %s%s" % [eng.pname(s), ": è un po' lento..." if slow else "..."]


func online_status(t: String) -> void:
	_say(t, 4.0)


func online_caught_up() -> void:
	_say("Partita ripresa.", 2.0)


# ================================================================ salvataggi, uscita, fine

func _save() -> void:
	if eng.over:
		_say("La battaglia è finita.")
		return
	var cfg := config.duplicate(true)
	cfg.erase("online")
	cfg.erase("preload")
	cfg.erase("save_code")
	var data := {"cfg": var_to_str(cfg), "acts": var_to_str(eng.history), "turn": eng.turn}
	_say("Salvo la partita...", 10.0)
	var net: Net = main.get_net()
	var code := await net.save_game(data, save_code)
	if code == "":
		_say("Salvataggio non riuscito: %s" % net.last_error, 5.0)
		return
	save_code = code
	_say("Partita salvata: codice %s (dal menu: Carica una partita)." % code, 8.0)


func _quit() -> void:
	eng.abort = true
	if online != null:
		online.alive = false
	if not req.is_empty():
		eng.provide_decision(null)
	main.show_menu()


func _on_end(res: Dictionary) -> void:
	act_panel.visible = false
	if online != null:
		online.finish()
	_refresh()
	var p := UI.panel(UI.ORANGE, 0.96)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.custom_minimum_size = Vector2(720, 0)
	p.offset_left = -360
	p.offset_right = 360
	add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	p.add_child(vb)
	vb.add_child(UI.title("Fine della battaglia", 48))
	var w: Array = res.get("winners", [])
	vb.add_child(UI.head(("Vittoria: " + ", ".join(w)) if not w.is_empty() else "Pareggio", 30, UI.TAN))
	for s in eng.sides.size():
		var col: Color = D.PCOLORS[int(eng.sides[s]["col"]) % 8]
		var lost := 0
		for u in eng.ships_of(s, false):
			if u["gone"] == "distrutta":
				lost += 1
		vb.add_child(UI.label("%s: %d punti vittoria, navi perdute %d" % [eng.pname(s), int(eng.sides[s]["vp"]), lost], 20, col))
	var bm := UI.primary(UI.button("Torna al menu", 300, 56, 22))
	bm.pressed.connect(func(): main.show_menu())
	vb.add_child(bm)
	var brp := UI.button("Replay della battaglia", 300, 50, 20, UI.SKY)
	brp.pressed.connect(func():
		p.queue_free()
		_start_replay())
	vb.add_child(brp)
	var bs := UI.button("Guarda la mappa", 300, 50, 20, UI.LILAC)
	bs.pressed.connect(func(): p.queue_free())
	vb.add_child(bs)


# ================================================================ replay finale

var rp_layer: Control
var rp_eng: SFBEngine
var rp_board
var rp_lbl: Label
var rp_speed := 1
var rp_paused := false
var rp_pause_btn: Button
var rp_run := 0
var rp_hidden: Array = []


## Rigioca l'intera battaglia da capo, tutto di seguito e senza pause, ricominciando alla fine
func _start_replay() -> void:
	_close_ssd()
	if is_instance_valid(rp_layer):
		return
	board.visible = false
	board.input_locked = true
	# a tutto schermo: si nascondono i pannelli della partita
	rp_hidden.clear()
	for c in get_children():
		if c is Control and c.visible:
			c.visible = false
			rp_hidden.append(c)
	rp_layer = Control.new()
	rp_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rp_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rp_layer)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UI.frame(UI.SKY, 0.93))
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -12
	bar.offset_left = -520
	bar.offset_right = 520
	rp_layer.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	bar.add_child(hb)
	rp_lbl = UI.head("Replay", 22, UI.SKY)
	rp_lbl.custom_minimum_size.x = 330
	hb.add_child(rp_lbl)
	var bv := UI.button("Velocità x1", 170, 46, 18, UI.LILAC)
	bv.pressed.connect(func():
		rp_speed = 1 if rp_speed == 4 else rp_speed * 2
		bv.text = "VELOCITÀ X%d" % rp_speed
		if rp_eng != null:
			rp_eng.replay_step = 0.09 / rp_speed)
	hb.add_child(bv)
	var bp := UI.button("Pausa", 150, 46, 18, UI.SKY)
	rp_pause_btn = bp
	bp.pressed.connect(func():
		rp_paused = not rp_paused
		bp.text = "RIPRENDI" if rp_paused else "PAUSA"
		if rp_eng != null:
			rp_eng.paused = rp_paused)
	hb.add_child(bp)
	var br := UI.button("Da capo", 140, 46, 18, UI.TAN)
	br.pressed.connect(_replay_once)
	hb.add_child(br)
	var bc := UI.button("Chiudi", 130, 46, 18, UI.RUST)
	bc.pressed.connect(_stop_replay)
	hb.add_child(bc)
	_replay_once()


func _replay_once() -> void:
	rp_run += 1
	var my := rp_run
	if rp_eng != null:
		rp_eng.abort = true
		rp_eng.queue_free()
	if is_instance_valid(rp_board):
		rp_board.queue_free()
	var cfg := config.duplicate(true)
	cfg.erase("online")
	cfg.erase("preload")
	cfg.erase("save_code")
	rp_eng = SFBEngine.new()
	rp_eng.setup(cfg)
	rp_eng.replaying = true
	rp_eng.replay_step = 0.09 / rp_speed
	rp_eng.paused = rp_paused
	rp_eng.replay_queue = eng.history.duplicate()
	add_child(rp_eng)
	rp_board = Board3D.new()
	rp_board.audio = main.audio
	add_child(rp_board)
	move_child(rp_board, 0)
	rp_board.setup(rp_eng)
	rp_board.yaw = board.yaw
	rp_board.pitch = board.pitch
	rp_board.dist = 52.0
	rp_board.pitch = -1.0
	rp_board.target_goal = Vector3(30.8, 0, 25.4)
	rp_board.target = rp_board.target_goal
	rp_eng.changed.connect(func():
		if is_instance_valid(rp_board):
			rp_board.refresh()
		if is_instance_valid(rp_lbl) and rp_eng != null:
			rp_lbl.text = "REPLAY - TURNO %d  IMPULSO %d" % [maxi(1, rp_eng.turn), rp_eng.imp])
	await get_tree().process_frame
	await rp_eng.run()
	if my != rp_run or not is_instance_valid(rp_layer):
		return
	rp_lbl.text = "REPLAY - FINE, RICOMINCIO..."
	await get_tree().create_timer(2.5).timeout
	if my == rp_run and is_instance_valid(rp_layer):
		_replay_once()


func _stop_replay() -> void:
	rp_run += 1
	if rp_eng != null:
		rp_eng.abort = true
		rp_eng.queue_free()
		rp_eng = null
	if is_instance_valid(rp_board):
		rp_board.queue_free()
	if is_instance_valid(rp_layer):
		rp_layer.queue_free()
	board.visible = true
	board.input_locked = false
	board.cam.current = true
	for c in rp_hidden:
		if is_instance_valid(c):
			c.visible = true
	rp_hidden.clear()
