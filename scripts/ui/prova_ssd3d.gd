extends Control
## PROVA: scheda SSD in 3D.
## La scheda originale dell'incrociatore pesante della Federazione è ritagliata come un cartoncino;
## su ogni casella di sistema c'è un cubetto che si disintegra quando quella parte viene colpita,
## lasciando la casella vuota. Gli scudi sono strati semitrasparenti attorno al modello, a cipolla:
## uno strato per ogni casella di scudo, e ogni casella persa toglie lo strato più esterno.
## I danni passano dalle vere regole del motore (scudi, tabella di assegnazione dei danni).

const D = preload("res://scripts/data/sfb_data.gd")
const H = preload("res://scripts/core/hexgrid.gd")

const PX := 0.01            # metri di mondo per pixel della scheda
const CARD_POS := Vector3(-4.6, 0, 0.6)
const SHIP_POS := Vector3(4.6, 2.0, -0.6)
const SHIP_SCALE := 3.0

var main
var eng: SFBEngine
var u: Dictionary
var data := {}
var root3d: Node3D
var cam: Camera3D
var pivot: Node3D
var yaw := 0.0
var pitch := -0.82
var dist := 19.5
var target := Vector3(-0.2, 0.5, 1.6)
var card: Node3D
var ship: Node3D
var cubes := {}            # "sys:k:i" | "w:i" | "s:i:j" -> MeshInstance3D
var layers := {}           # "i:j" -> MeshInstance3D
var log_lbl: RichTextLabel
var stat_lbl: Label
var _touches := {}
var _drag := 0
var _t := 0.0
var _mat_cache := {}

const SYS_COL := {
	"br": Color("#cc99ff"), "em": Color("#cc99ff"), "aux": Color("#cc99ff"), "fl": Color("#cc99ff"),
	"lw": Color("#5fa8ff"), "rw": Color("#5fa8ff"), "cw": Color("#5fa8ff"), "imp": Color("#7fd4ff"),
	"apr": Color("#ffd166"), "bt": Color("#ffd166"),
	"fh": Color("#b8bcc8"), "ah": Color("#9aa0ad"), "ch": Color("#b8bcc8"),
	"lab": Color("#88dd88"), "tr": Color("#66ccaa"), "trac": Color("#66ccaa"), "sh": Color("#ff9c00"),
	"prb": Color("#66ccaa"), "cargo": Color("#c8a070"),
}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := FileAccess.open("res://assets/prova/fed_ca_caselle.json", FileAccess.READ)
	data = JSON.parse_string(f.get_as_text())
	eng = SFBEngine.new()
	eng.headless = true
	add_child(eng)
	eng.setup({"seed": randi() % 100000, "turns": 1, "sides": [
		{"name": "Federazione", "ai": true, "team": 0, "ships": [{"id": "fed_ca", "hex": Vector2i(10, 5), "face": 0}]},
		{"name": "Bersaglio", "ai": true, "team": 1, "ships": []}]})
	u = eng.units[1]
	u["sh_on"] = true
	root3d = Node3D.new()
	add_child(root3d)
	_build_env()
	_build_card()
	_build_ship()
	_build_ui()
	_update_cam()


# ================================================================ scena

func _build_env() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#02030a")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#8a90b0")
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_hdr_threshold = 1.1
	we.environment = e
	root3d.add_child(we)
	var l := DirectionalLight3D.new()
	l.rotation = Vector3(-0.95, 0.5, 0)
	l.light_energy = 1.2
	l.shadow_enabled = true
	root3d.add_child(l)
	var l2 := DirectionalLight3D.new()
	l2.rotation = Vector3(-0.35, -2.3, 0)
	l2.light_energy = 0.4
	l2.light_color = Color("#9fb4ff")
	root3d.add_child(l2)
	# campo stellare di sfondo: un disco scuro con puntini
	var g := RandomNumberGenerator.new()
	g.seed = 7
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	sm.radial_segments = 4
	sm.rings = 2
	mm.mesh = sm
	mm.instance_count = 500
	for i in 500:
		var d := Vector3(g.randf_range(-1, 1), g.randf_range(-0.2, 1), g.randf_range(-1, 1)).normalized() * 60.0
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * g.randf_range(1, 3)), d))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _unshaded(Color(0.9, 0.92, 1.0))
	root3d.add_child(mi)
	pivot = Node3D.new()
	root3d.add_child(pivot)
	cam = Camera3D.new()
	cam.fov = 42
	cam.far = 300
	pivot.add_child(cam)
	cam.current = true


func _unshaded(c: Color, e := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c * e
	return m


func _cube_mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = 0.25
		m.roughness = 0.35
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.25
		_mat_cache[key] = m
	return _mat_cache[key]


## Centro di una casella della scheda nel mondo (la scheda giace sul piano XZ)
func _box_pos(b: Array) -> Vector3:
	var w := float(data["w"])
	var h := float(data["h"])
	var cx := float(b[0]) + float(b[2]) / 2.0
	var cy := float(b[1]) + float(b[3]) / 2.0
	return card.to_global(Vector3((cx - w / 2.0) * PX, 0, (cy - h / 2.0) * PX))


func _build_card() -> void:
	card = Node3D.new()
	card.position = CARD_POS
	card.rotation.y = 0.0
	root3d.add_child(card)
	var w := float(data["w"]) * PX
	var h := float(data["h"]) * PX
	# cartoncino ritagliato: immagine con trasparenza sul piano, più un'ombra scura sotto
	var top := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, h)
	top.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/prova/fed_ca_ssd.png")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 0.9
	m.albedo_color = Color(0.78, 0.78, 0.8)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	top.material_override = m
	top.position.y = 0.06
	card.add_child(top)
	var under := MeshInstance3D.new()
	under.mesh = pm
	var m2 := m.duplicate()
	m2.albedo_color = Color(0.05, 0.05, 0.08)
	under.material_override = m2
	under.position.y = 0.0
	card.add_child(under)
	for dy in [0.015, 0.03, 0.045]:
		var mid := MeshInstance3D.new()
		mid.mesh = pm
		mid.material_override = m2
		mid.position.y = dy
		card.add_child(mid)
	# cubetti dei sistemi
	for k in data["sys"]:
		var col: Color = SYS_COL.get(k, Color.WHITE)
		var i := 0
		for b in data["sys"][k]:
			cubes["sys:%s:%d" % [k, i]] = _cube(b, col, 0.16)
			i += 1
	for wi in data["weap"]:
		var t: String = u["weapons"][int(wi)]["t"]
		var col2 := Color("#ff5555") if t == "PHOT" else (Color("#ff8a3d") if D.is_phaser(t) else Color("#ff5577"))
		cubes["w:%s" % wi] = _cube(data["weap"][wi], col2, 0.2)
	# tessere degli scudi sulla scheda: sottili e azzurre
	for si in data["shield"]:
		var j := 0
		for b in data["shield"][si]:
			var c := _cube(b, Color(0.35, 0.7, 1.0), 0.06)
			c.material_override = _shield_tile_mat()
			cubes["s:%s:%d" % [si, j]] = c
			j += 1


var _stm: StandardMaterial3D


func _shield_tile_mat() -> StandardMaterial3D:
	if _stm == null:
		_stm = StandardMaterial3D.new()
		_stm.albedo_color = Color(0.35, 0.75, 1.0, 0.75)
		_stm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_stm.emission_enabled = true
		_stm.emission = Color(0.3, 0.6, 1.0)
		_stm.emission_energy_multiplier = 0.8
	return _stm


func _cube(b: Array, col: Color, hgt: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(float(b[2]) * PX * 0.8, hgt, float(b[3]) * PX * 0.8)
	mi.mesh = bm
	mi.material_override = _cube_mat(col)
	root3d.add_child(mi)
	mi.global_position = _box_pos(b) + Vector3(0, 0.06 + hgt / 2.0, 0)
	return mi


func _build_ship() -> void:
	ship = Node3D.new()
	ship.position = SHIP_POS
	root3d.add_child(ship)
	var mdl: Node3D = load("res://assets/ships/fed_ca.glb").instantiate()
	mdl.scale = Vector3.ONE * SHIP_SCALE
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.68, 0.7, 0.75)
	hm.metallic = 0.6
	hm.roughness = 0.4
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_apply_mat(mdl, hm)
	ship.add_child(mdl)
	# scudi a cipolla: per ogni lato un settore, uno strato per casella
	for i in 6:
		var n: int = u["sh_max"][i]
		for j in n:
			var lay := MeshInstance3D.new()
			lay.mesh = _sector_mesh(i, 1.9 + j * 0.06)
			lay.material_override = _layer_mat(i, j, n)
			ship.add_child(lay)
			layers["%d:%d" % [i, j]] = lay


func _apply_mat(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		n.material_override = m
	for c in n.get_children():
		_apply_mat(c, m)


func _layer_mat(i: int, j: int, n: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var c := Color(0.25, 0.6, 1.0).lerp(Color(0.5, 0.85, 1.0), float(j) / maxf(1.0, float(n)))
	m.albedo_color = Color(c, 0.022 + 0.02 * float(j == n - 1))
	return m


## Settore di sfera (60 gradi attorno alla direzione dello scudo), schiacciato in altezza
func _sector_mesh(i: int, r: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a0 := deg_to_rad(i * 60.0 - 29.0)
	var a1 := deg_to_rad(i * 60.0 + 29.0)
	var e0 := deg_to_rad(-40.0)
	var e1 := deg_to_rad(50.0)
	var na := 8
	var ne := 6
	var pts := []
	for ie in ne + 1:
		var row := []
		var e := lerpf(e0, e1, float(ie) / ne)
		for ia in na + 1:
			var a := lerpf(a0, a1, float(ia) / na)
			row.append(Vector3(sin(a) * cos(e) * r, sin(e) * r * 0.55, -cos(a) * cos(e) * r))
		pts.append(row)
	for ie in ne:
		for ia in na:
			var p00: Vector3 = pts[ie][ia]
			var p01: Vector3 = pts[ie][ia + 1]
			var p10: Vector3 = pts[ie + 1][ia]
			var p11: Vector3 = pts[ie + 1][ia + 1]
			st.add_vertex(p00)
			st.add_vertex(p10)
			st.add_vertex(p11)
			st.add_vertex(p00)
			st.add_vertex(p11)
			st.add_vertex(p01)
	return st.commit()


# ================================================================ interfaccia

func _build_ui() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 20
	top.offset_top = 14
	top.add_theme_constant_override("separation", 14)
	add_child(top)
	var cap := ColorRect.new()
	cap.color = UI.ORANGE
	cap.custom_minimum_size = Vector2(26, 60)
	top.add_child(cap)
	var tv := VBoxContainer.new()
	tv.add_child(UI.title("Prova: scheda SSD in 3D", 40))
	tv.add_child(UI.label("Incrociatore pesante della Federazione - i danni seguono le vere regole del gioco", 18, UI.PEACH))
	top.add_child(tv)
	var p := UI.panel(UI.TAN, 0.92)
	p.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	p.offset_left = 16
	p.offset_right = -16
	p.offset_bottom = -12
	p.offset_top = -150
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
		var k: int = i
		var b := UI.button("#%d" % (i + 1), 80, 46, 20, UI.SKY)
		b.pressed.connect(func(): _hit(k))
		r1.add_child(b)
	var sp := Control.new()
	sp.custom_minimum_size.x = 20
	r1.add_child(sp)
	var bv := UI.button("Bordata di fotoni sullo scudo 1", 360, 46, 19, UI.ORANGE)
	bv.pressed.connect(func():
		for n in 4:
			_hit(0, 8)
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


# ================================================================ colpi

func _snapshot() -> Dictionary:
	var w := []
	for x in u["weapons"]:
		w.append(x["ok"])
	return {"sys": u["sys"].duplicate(), "w": w, "sh": u["sh"].duplicate()}


func _hit(shi: int, dmg := -1) -> void:
	if not u["alive"]:
		return
	if dmg < 0:
		dmg = randi_range(5, 12)
	var before := _snapshot()
	var lines0: int = eng.log_lines.size()
	eng._damage(u, shi, dmg, {})
	_beam_to(shi)
	for k in range(lines0, eng.log_lines.size()):
		log_lbl.append_text(str(eng.log_lines[k]) + "\n")
	# scudo: via gli strati e le tessere perse
	for j in range(int(u["sh"][shi]), int(before["sh"][shi])):
		_pop_layer(shi, j)
		var c = cubes.get("s:%d:%d" % [shi, j], null)
		if c != null:
			_shatter(c, Color(0.4, 0.75, 1.0))
			cubes.erase("s:%d:%d" % [shi, j])
	# sistemi: i cubetti delle caselle perse (dall'ultima casella in ordine di lettura)
	var lost := []
	for k in before["sys"]:
		var dlt := int(before["sys"][k]) - int(u["sys"][k])
		for n in dlt:
			var idx := int(before["sys"][k]) - 1 - n
			lost.append("sys:%s:%d" % [k, idx])
	for i in u["weapons"].size():
		if before["w"][i] and not u["weapons"][i]["ok"]:
			lost.append("w:%d" % i)
	var delay := 0.25
	for key in lost:
		var c2 = cubes.get(key, null)
		if c2 != null:
			cubes.erase(key)
			_later(delay, c2)
			delay += 0.12
	_status()
	if not u["alive"]:
		await get_tree().create_timer(delay + 0.3).timeout
		_boom()


func _later(d: float, c: MeshInstance3D) -> void:
	await get_tree().create_timer(d).timeout
	if is_instance_valid(c):
		var m: StandardMaterial3D = c.material_override
		_shatter(c, m.albedo_color)


## Il cubetto si disintegra in frammenti, la casella resta vuota
func _shatter(c: MeshInstance3D, col: Color) -> void:
	var p := c.global_position
	var bm: BoxMesh = c.mesh
	var s := bm.size
	c.queue_free()
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.6, 0.25)
	fl.light_energy = 2.5
	fl.omni_range = 1.2
	root3d.add_child(fl)
	fl.global_position = p + Vector3(0, 0.2, 0)
	var tw0 := create_tween()
	tw0.tween_property(fl, "light_energy", 0.0, 0.5)
	tw0.tween_callback(fl.queue_free)
	for n in 8:
		var f := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = s * randf_range(0.2, 0.42)
		f.mesh = fm
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.emission_enabled = true
		m.emission = col.lerp(Color(1.0, 0.5, 0.1), 0.6)
		m.emission_energy_multiplier = 2.5
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		f.material_override = m
		root3d.add_child(f)
		f.global_position = p
		var dir := Vector3(randf_range(-1, 1), randf_range(0.6, 1.6), randf_range(-1, 1)).normalized()
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(f, "global_position", p + dir * randf_range(0.4, 0.9) + Vector3(0, -0.1, 0), 0.7).set_ease(Tween.EASE_OUT)
		tw.tween_property(f, "rotation", Vector3(randf() * 6, randf() * 6, randf() * 6), 0.7)
		tw.tween_property(m, "albedo_color:a", 0.0, 0.7)
		tw.tween_property(f, "scale", Vector3.ONE * 0.2, 0.7)
		tw.chain().tween_callback(f.queue_free)


func _pop_layer(i: int, j: int) -> void:
	var lay = layers.get("%d:%d" % [i, j], null)
	if lay == null:
		return
	layers.erase("%d:%d" % [i, j])
	var m: StandardMaterial3D = lay.material_override
	m.albedo_color = Color(0.7, 0.9, 1.0, 0.5)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lay, "scale", Vector3.ONE * 1.25, 0.5)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.5)
	tw.chain().tween_callback(lay.queue_free)


func _beam_to(shi: int) -> void:
	var a := deg_to_rad(shi * 60.0)
	var dir := Vector3(sin(a), 0.25, -cos(a)).normalized()
	var to := ship.global_position + dir * 2.4
	var from := ship.global_position + dir * 14.0
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.06
	cm.height = from.distance_to(to)
	m.mesh = cm
	m.material_override = _unshaded(Color(1.0, 0.55, 0.15), 6.0)
	root3d.add_child(m)
	m.global_position = (from + to) * 0.5
	m.look_at_from_position(m.global_position, to, Vector3.UP)
	m.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var tw := create_tween()
	tw.tween_property(m, "scale", Vector3(0.1, 1, 0.1), 0.4)
	tw.tween_callback(m.queue_free)
	var fl := OmniLight3D.new()
	fl.light_color = Color(0.5, 0.8, 1.0)
	fl.light_energy = 4.0
	fl.omni_range = 4.0
	root3d.add_child(fl)
	fl.global_position = to
	var tw2 := create_tween()
	tw2.tween_property(fl, "light_energy", 0.0, 0.5)
	tw2.tween_callback(fl.queue_free)


func _boom() -> void:
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	s.mesh = sm
	var m := _unshaded(Color(1.0, 0.6, 0.2), 5.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s.material_override = m
	root3d.add_child(s)
	s.global_position = ship.global_position
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "scale", Vector3.ONE * 5.0, 1.0)
	tw.tween_property(m, "albedo_color:a", 0.0, 1.0)
	tw.tween_property(ship, "scale", Vector3.ONE * 0.01, 0.8)


# ================================================================ telecamera

func _update_cam() -> void:
	pivot.position = target
	pivot.rotation = Vector3(pitch, yaw, 0)
	cam.position = Vector3(0, 0, dist)


func _process(dt: float) -> void:
	_t += dt
	if is_instance_valid(ship):
		ship.rotation.y = sin(_t * 0.3) * 0.25
		ship.position.y = SHIP_POS.y + sin(_t * 0.9) * 0.12
	_update_cam()


func _over_gui(sp: Vector2) -> bool:
	var c := get_viewport().gui_get_hovered_control()
	return c != null and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.get_global_rect().has_point(sp)


func _pan(rel: Vector2) -> void:
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	target += (-right * rel.x + fwd * rel.y) * dist * 0.0016


func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed and not _over_gui(ev.position):
			_touches[ev.index] = ev.position
		else:
			_touches.erase(ev.index)
		return
	if ev is InputEventScreenDrag and _touches.has(ev.index):
		if _touches.size() == 1:
			_pan(ev.relative)
		else:
			var old: Vector2 = _touches[ev.index]
			var other := Vector2.ZERO
			for k in _touches:
				if k != ev.index:
					other = _touches[k]
			var d0 := old.distance_to(other)
			var d1: float = ev.position.distance_to(other)
			if d0 > 1 and d1 > 1:
				dist = clampf(dist * d0 / d1, 5.0, 40.0)
			var a0 := (old - other).angle()
			var a1: float = (ev.position - other).angle()
			yaw -= angle_difference(a0, a1)
			pitch = clampf(pitch - (ev.position.y - old.y) * 0.002, -1.45, -0.15)
			_touches[ev.index] = ev.position
		return
	if ev is InputEventMouseButton:
		if ev.pressed and _over_gui(ev.position):
			return
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = clampf(dist * 0.9, 5.0, 40.0)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = clampf(dist * 1.1, 5.0, 40.0)
		elif ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_drag = ev.button_index if ev.pressed else 0
	elif ev is InputEventMouseMotion and _drag != 0:
		if _drag == MOUSE_BUTTON_RIGHT:
			yaw -= ev.relative.x * 0.006
			pitch = clampf(pitch - ev.relative.y * 0.005, -1.45, -0.15)
		else:
			_pan(ev.relative)
	elif ev is InputEventMagnifyGesture:
		dist = clampf(dist / ev.factor, 5.0, 40.0)
