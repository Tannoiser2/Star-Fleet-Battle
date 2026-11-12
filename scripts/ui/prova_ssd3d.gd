extends Control
## PROVA della scheda SSD in 3D: si sceglie una nave che ha la scheda 3D e la si bersaglia.
## I danni passano dalle vere regole del motore (scudi, tabella di assegnazione dei danni).

const D = preload("res://scripts/data/sfb_data.gd")

var main
var ship_id := "kli_b10"
var eng: SFBEngine
var u: Dictionary
var view
var stat_lbl: Label
var log_lbl: RichTextLabel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	eng = SFBEngine.new()
	eng.headless = true
	add_child(eng)
	eng.setup({"seed": randi() % 100000, "turns": 1, "sides": [
		{"name": "Nave", "ai": true, "team": 0, "ships": [{"id": ship_id, "hex": Vector2i(10, 5), "face": 0}]},
		{"name": "Bersaglio", "ai": true, "team": 1, "ships": []}]})
	u = eng.units[1]
	var svc: SubViewportContainer = SSD3D.window(eng, 1)
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(svc)
	view = svc.get_child(0).get_node("scheda")
	_build_ui()


func _build_ui() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 20
	top.offset_top = 14
	top.add_theme_constant_override("separation", 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var cap := ColorRect.new()
	cap.color = UI.ORANGE
	cap.custom_minimum_size = Vector2(26, 60)
	top.add_child(cap)
	var tv := VBoxContainer.new()
	tv.add_child(UI.title("Prova: scheda SSD in 3D", 40))
	tv.add_child(UI.label("%s - i danni seguono le vere regole del gioco" % D.ship(ship_id)["n"], 18, UI.PEACH))
	top.add_child(tv)
	for id in ["kli_b10", "fed_ca"]:
		var b := UI.button(str(D.ship(id)["n"]), 0, 44, 18, UI.TAN if id == ship_id else UI.LILAC)
		var k: String = id
		b.pressed.connect(func():
			main.prova_ship = k
			main.show_prova())
		top.add_child(b)
	var p := UI.panel(UI.TAN, 0.92)
	p.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	p.offset_left = 16
	p.offset_right = -16
	p.offset_bottom = -12
	p.offset_top = -170
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 8)
	vb.add_child(r1)
	r1.add_child(UI.head("Colpisci lo scudo", 22, UI.TAN))
	for i in 6:
		var k2: int = i
		var b2 := UI.button("#%d" % (i + 1), 80, 46, 20, UI.SKY)
		b2.pressed.connect(func(): _hit(k2))
		r1.add_child(b2)
	var bv := UI.button("Bordata sullo scudo 1", 300, 46, 19, UI.ORANGE)
	bv.pressed.connect(func():
		for n in 4:
			_hit(0, 10)
			await get_tree().create_timer(0.35).timeout)
	r1.add_child(bv)
	var br := UI.button("Ripristina", 170, 46, 20, UI.LILAC)
	br.pressed.connect(func(): main.show_prova())
	r1.add_child(br)
	var bm := UI.button("Menu", 130, 46, 20, UI.RUST)
	bm.pressed.connect(func(): main.show_menu())
	r1.add_child(bm)
	stat_lbl = UI.mono("", 18, UI.TEXT)
	vb.add_child(stat_lbl)
	log_lbl = UI.rich(17)
	log_lbl.custom_minimum_size = Vector2(900, 66)
	log_lbl.fit_content = false
	log_lbl.scroll_following = true
	log_lbl.scroll_active = true
	vb.add_child(log_lbl)
	_status()


func _status() -> void:
	var t := []
	for i in 6:
		t.append("#%d %d/%d" % [i + 1, u["sh"][i], u["sh_max"][i]])
	stat_lbl.text = "Scudi: " + "   ".join(t) + "      Danni in eccesso: %d/%d" % [u["ex"], u["ex_max"]] + ("      NAVE DISTRUTTA" if not u["alive"] else "")


func _hit(shi: int, dmg := -1) -> void:
	if not u["alive"]:
		return
	if dmg < 0:
		dmg = randi_range(5, 12)
	var n0: int = eng.log_lines.size()
	eng._damage(u, shi, dmg, {})
	view.beam(shi)
	for k in range(n0, eng.log_lines.size()):
		log_lbl.append_text(str(eng.log_lines[k]) + "\n")
	view.sync()
	_status()
