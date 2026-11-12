class_name SSD3D
extends Node3D
## Scheda SSD in 3D di una nave, sincronizzata con lo stato del motore.
## La scheda originale è ritagliata come un cartoncino; su ogni casella di sistema c'è un cubetto
## che si disintegra quando quella parte viene colpita, lasciando la casella vuota. Gli scudi sono
## strati semitrasparenti attorno al modello, a cipolla: ogni casella persa toglie lo strato più esterno.
## Va messa dentro un SubViewport con mondo proprio (vedi SSD3D.window()).
## Dati delle caselle: assets/ssd3d/<id>.json (+ .png), creati da tools/ssd3d_caselle.py.

const D = preload("res://scripts/data/sfb_data.gd")

const PX := 0.01
const MAX_LAYERS := 24

const SYS_COL := {
	"br": Color("#cc99ff"), "em": Color("#cc99ff"), "aux": Color("#cc99ff"), "fl": Color("#cc99ff"),
	"lw": Color("#5fa8ff"), "rw": Color("#5fa8ff"), "cw": Color("#5fa8ff"), "imp": Color("#7fd4ff"),
	"apr": Color("#ffd166"), "bt": Color("#ffd166"),
	"fh": Color("#b8bcc8"), "ah": Color("#9aa0ad"), "ch": Color("#b8bcc8"), "armor": Color("#8c8c8c"),
	"lab": Color("#88dd88"), "tr": Color("#66ccaa"), "trac": Color("#66ccaa"), "sh": Color("#ff9c00"),
	"prb": Color("#66ccaa"), "cargo": Color("#c8a070"),
}

var eng
var uid := -1
var data := {}
var card: Node3D
var ship: Node3D
var ship_pos := Vector3.ZERO
var cam: Camera3D
var pivot: Node3D
var yaw := 0.0
var pitch := -0.82
var dist := 19.5
var target := Vector3(-0.2, 0.5, 1.6)
var sys_cubes := {}      # chiave -> Array di MeshInstance3D (null = distrutto)
var weap_cubes := {}      # tipo d'arma -> Array
var sh_tiles := {}       # "i" -> Array
var layers := {}         # i -> Array di MeshInstance3D
var _t := 0.0
var _touches := {}
var _drag := 0
var _mat_cache := {}
var _stm: StandardMaterial3D
var _dead := false
var animate := true
var part := "all"         # "all" scheda e nave, "ship" solo nave con gli scudi, "card" solo la scheda


static func has_data(id: String) -> bool:
	return ResourceLoader.exists("res://assets/ssd3d/%s.png" % id)


## Finestra pronta da mettere nell'interfaccia: SubViewportContainer con la scheda 3D
static func window(e, u_id: int, what := "all") -> SubViewportContainer:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_STOP
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_2X
	sv.handle_input_locally = true
	svc.add_child(sv)
	var s = load("res://scripts/ui/ssd3d.gd").new()
	s.name = "scheda"
	s.part = what
	sv.add_child(s)
	s.setup(e, u_id)
	return svc


func setup(e, u_id: int) -> void:
	eng = e
	uid = u_id
	var u: Dictionary = eng.units[uid]
	var f := FileAccess.open("res://assets/ssd3d/%s.json" % u["id"], FileAccess.READ)
	data = JSON.parse_string(f.get_as_text())
	var w := float(data["w"]) * PX
	var h := float(data["h"]) * PX
	# la nave accanto alla scheda, a destra; la telecamera inquadra tutte e due
	ship_pos = Vector3(w * 0.5 + 3.2, 2.0, -h * 0.1)
	target = Vector3((w * 0.5 + 3.2) * 0.42, 0.6, h * 0.04)
	dist = (w + 6.4) * 0.92 + 1.0
	pitch = -0.92
	if part == "ship":
		ship_pos = Vector3.ZERO
		target = Vector3(0, 0.0, 0)
		dist = 9.5
		pitch = -0.62
	elif part == "card":
		target = Vector3(0, 0, 0.1)
		dist = maxf(w * 0.85, h * 0.98) + 0.6
		pitch = -1.32
	_build_env()
	if part != "ship":
		_build_card(u)
	if part != "card":
		_build_ship(u)
	animate = false
	sync()
	animate = true
	if eng.has_signal("changed"):
		eng.changed.connect(sync)


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
	add_child(we)
	var l := DirectionalLight3D.new()
	l.rotation = Vector3(-0.95, 0.5, 0)
	l.light_energy = 1.2
	add_child(l)
	var l2 := DirectionalLight3D.new()
	l2.rotation = Vector3(-0.35, -2.3, 0)
	l2.light_energy = 0.4
	l2.light_color = Color("#9fb4ff")
	add_child(l2)
	pivot = Node3D.new()
	add_child(pivot)
	cam = Camera3D.new()
	cam.fov = 42
	cam.far = 300
	pivot.add_child(cam)
	cam.current = true
	_update_cam()


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


func _box_pos(b: Array) -> Vector3:
	var w := float(data["w"])
	var h := float(data["h"])
	var cx := float(b[0]) + float(b[2]) / 2.0
	var cy := float(b[1]) + float(b[3]) / 2.0
	return card.position + Vector3((cx - w / 2.0) * PX, 0, (cy - h / 2.0) * PX)


func _build_card(u: Dictionary) -> void:
	card = Node3D.new()
	add_child(card)
	var w := float(data["w"]) * PX
	var h := float(data["h"]) * PX
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, h)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/ssd3d/%s.png" % u["id"])
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 0.9
	m.albedo_color = Color(0.78, 0.78, 0.8)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var top := MeshInstance3D.new()
	top.mesh = pm
	top.material_override = m
	top.position.y = 0.06
	card.add_child(top)
	var m2: StandardMaterial3D = m.duplicate()
	m2.albedo_color = Color(0.05, 0.05, 0.08)
	for dy in [0.0, 0.015, 0.03, 0.045]:
		var mid := MeshInstance3D.new()
		mid.mesh = pm
		mid.material_override = m2
		mid.position.y = dy
		card.add_child(mid)
	for k in data["sys"]:
		var arr := []
		for b in data["sys"][k]:
			arr.append(_cube(b, SYS_COL.get(k, Color.WHITE), 0.16))
		sys_cubes[k] = arr
	for t in data.get("weapt", {}):
		var col := Color("#ff5555") if t == "PHOT" or t == "DISR" else (Color("#ff8a3d") if D.is_phaser(t) else (Color("#55ee88") if D.is_plasma(t) else Color("#ff5577")))
		var arr := []
		for b in data["weapt"][t]:
			arr.append(_cube(b, col, 0.2))
		weap_cubes[t] = arr
	for si in data["shield"]:
		var arr2 := []
		for b in data["shield"][si]:
			var c := _cube(b, Color(0.35, 0.7, 1.0), 0.06)
			c.material_override = _shield_tile_mat()
			arr2.append(c)
		sh_tiles[si] = arr2


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
	add_child(mi)
	mi.position = _box_pos(b) + Vector3(0, 0.06 + hgt / 2.0, 0)
	return mi


func _build_ship(u: Dictionary) -> void:
	ship = Node3D.new()
	ship.position = ship_pos
	add_child(ship)
	var p := "res://assets/ships/%s.glb" % u["id"]
	if ResourceLoader.exists(p):
		var mdl: Node3D = load(p).instantiate()
		var sz: int = int(D.ship(u["id"])["sz"])
		mdl.scale = Vector3.ONE * (3.6 if sz <= 2 else (3.0 if sz == 3 else 2.4))
		var hm := StandardMaterial3D.new()
		hm.albedo_color = (D.RACES[u["race"]]["scafo"] as Color).lightened(0.05)
		hm.metallic = 0.6
		hm.roughness = 0.4
		hm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_apply_mat(mdl, hm)
		ship.add_child(mdl)
	for i in 6:
		var n := mini(int(u["sh_max"][i]), MAX_LAYERS)
		var arr := []
		for j in n:
			var lay := MeshInstance3D.new()
			lay.mesh = _sector_mesh(i, 1.9 + j * 0.06)
			lay.material_override = _layer_mat(j, n)
			ship.add_child(lay)
			arr.append(lay)
		layers[i] = arr


func _apply_mat(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		n.material_override = m
	for c in n.get_children():
		_apply_mat(c, m)


func _layer_mat(j: int, n: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var c := Color(0.25, 0.6, 1.0).lerp(Color(0.5, 0.85, 1.0), float(j) / maxf(1.0, float(n)))
	m.albedo_color = Color(c, 0.022 + 0.02 * float(j == n - 1))
	return m


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
			st.add_vertex(pts[ie][ia])
			st.add_vertex(pts[ie + 1][ia])
			st.add_vertex(pts[ie + 1][ia + 1])
			st.add_vertex(pts[ie][ia])
			st.add_vertex(pts[ie + 1][ia + 1])
			st.add_vertex(pts[ie][ia + 1])
	return st.commit()


# ================================================================ stato

## Quante caselle disegnate devono risultare perse, in proporzione ai danni del sistema
func _lost(n_boxes: int, cur: int, mx: int) -> int:
	if mx <= 0:
		return 0
	return clampi(int(round(n_boxes * (1.0 - float(cur) / float(mx)))), 0, n_boxes)


## Allinea cubetti e strati allo stato attuale della nave; i nuovi danni esplodono
func sync() -> void:
	if not eng.units.has(uid) or _dead:
		return
	var u: Dictionary = eng.units[uid]
	var delay := 0.0
	for k in sys_cubes:
		var arr: Array = sys_cubes[k]
		var lost := _lost(arr.size(), int(u["sys"].get(k, 0)), int(u["max"].get(k, 0)))
		for n in lost:
			var idx := arr.size() - 1 - n
			if arr[idx] != null:
				_kill(arr[idx], delay)
				arr[idx] = null
				delay += 0.1
	# armi: per ogni tipo, caselle perse in proporzione alle armi di quel tipo distrutte
	for t in weap_cubes:
		var tot := 0
		var ok := 0
		for w in u["weapons"]:
			if w["t"] == t:
				tot += 1
				if w["ok"]:
					ok += 1
		var arrw: Array = weap_cubes[t]
		var lostw := _lost(arrw.size(), ok, tot)
		for n in lostw:
			var idw := arrw.size() - 1 - n
			if arrw[idw] != null:
				_kill(arrw[idw], delay)
				arrw[idw] = null
				delay += 0.1
	for si in sh_tiles:
		var i2 := int(si)
		var arr2: Array = sh_tiles[si]
		var lost2 := _lost(arr2.size(), int(u["sh"][i2]), int(u["sh_max"][i2]))
		for n in lost2:
			var idx2 := arr2.size() - 1 - n
			if arr2[idx2] != null:
				_kill(arr2[idx2], 0.0, Color(0.4, 0.75, 1.0))
				arr2[idx2] = null
	_weapon_colors(u)
	for i in 6:
		if not layers.has(i):
			continue
		var arr3: Array = layers[i]
		var keep := arr3.size() - _lost(arr3.size(), int(u["sh"][i]), int(u["sh_max"][i]))
		# sotto il 20% lo scudo diventa rosso, sotto metà giallo
		var f := float(u["sh"][i]) / maxf(1.0, float(u["sh_max"][i]))
		var tint := Color(1.0, 0.15, 0.1) if f <= 0.2 else (Color(1.0, 0.75, 0.2) if f <= 0.5 else Color())
		for j in keep:
			if arr3[j] != null:
				var lm: StandardMaterial3D = arr3[j].material_override
				var base := Color(0.25, 0.6, 1.0).lerp(Color(0.5, 0.85, 1.0), float(j) / maxf(1.0, float(arr3.size())))
				var cc := base if tint == Color() else tint
				var a := 0.022 + 0.02 * float(j == keep - 1)
				if tint != Color():
					a *= 1.8
				lm.albedo_color = Color(cc, a)
		for j in range(arr3.size() - 1, keep - 1, -1):
			if arr3[j] != null:
				_pop_layer(arr3[j])
				arr3[j] = null
	if not u["alive"] and u["gone"] == "distrutta" and is_instance_valid(ship):
		_dead = true
		_boom(delay + 0.3)


## Caselle delle armi colorate secondo lo stato: rosso sparata, verde pronta, grigio scarica
const W_FIRED := Color(1.0, 0.22, 0.16)
const W_READY := Color(0.25, 0.95, 0.35)
const W_IDLE := Color(0.42, 0.43, 0.48)


static func weapon_color(u: Dictionary, w: Dictionary) -> Color:
	var t: String = w["t"]
	if w["fired"]:
		return W_FIRED
	var ready := false
	if D.is_phaser(t):
		ready = float(u["cap"]) >= D.phaser_cost(t)
	elif t == "PHOT":
		ready = int(w["st"]) == 2 and w["ready"]
	elif t == "DISR":
		ready = w["ready"]
	elif D.is_plasma(t):
		ready = int(w["st"]) >= 3 and w["ready"]
	elif t == "DRN":
		ready = int(w.get("n", 0)) > 0
	return W_READY if ready else W_IDLE


## Colore di ogni casella d'arma del tipo t (le armi distrutte sono le ultime caselle, già esplose)
static func weapon_box_colors(u: Dictionary, t: String, n_boxes: int) -> Array:
	var sts := []
	for w in u["weapons"]:
		if w["t"] == t and w["ok"]:
			sts.append(weapon_color(u, w))
	var out := []
	var tot := 0
	for w in u["weapons"]:
		if w["t"] == t:
			tot += 1
	for i in n_boxes:
		var k := int(float(i) * float(tot) / float(maxi(1, n_boxes)))
		out.append(sts[k] if k < sts.size() else null)
	return out


func _weapon_colors(u: Dictionary) -> void:
	for t in weap_cubes:
		var arr: Array = weap_cubes[t]
		var cols := weapon_box_colors(u, t, arr.size())
		for i in arr.size():
			if arr[i] != null and cols[i] != null:
				arr[i].material_override = _cube_mat(cols[i])


func _kill(c: MeshInstance3D, delay: float, col = null) -> void:
	if not animate:
		c.queue_free()
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_instance_valid(c):
		return
	var cc: Color = col if col != null else (c.material_override as StandardMaterial3D).albedo_color
	_shatter(c, cc)


func _shatter(c: MeshInstance3D, col: Color) -> void:
	var p := c.position
	var s := (c.mesh as BoxMesh).size
	c.queue_free()
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.6, 0.25)
	fl.light_energy = 2.5
	fl.omni_range = 1.2
	add_child(fl)
	fl.position = p + Vector3(0, 0.2, 0)
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
		add_child(f)
		f.position = p
		var dir := Vector3(randf_range(-1, 1), randf_range(0.6, 1.6), randf_range(-1, 1)).normalized()
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(f, "position", p + dir * randf_range(0.4, 0.9) + Vector3(0, -0.1, 0), 0.7).set_ease(Tween.EASE_OUT)
		tw.tween_property(f, "rotation", Vector3(randf() * 6, randf() * 6, randf() * 6), 0.7)
		tw.tween_property(m, "albedo_color:a", 0.0, 0.7)
		tw.tween_property(f, "scale", Vector3.ONE * 0.2, 0.7)
		tw.chain().tween_callback(f.queue_free)


func _pop_layer(lay: MeshInstance3D) -> void:
	if not animate:
		lay.queue_free()
		return
	var m: StandardMaterial3D = lay.material_override
	m.albedo_color = Color(0.7, 0.9, 1.0, 0.5)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lay, "scale", Vector3.ONE * 1.25, 0.5)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.5)
	tw.chain().tween_callback(lay.queue_free)


## Raggio di un colpo sullo scudo i (solo effetto)
func beam(shi: int) -> void:
	if not is_instance_valid(ship):
		return
	var a := deg_to_rad(shi * 60.0)
	var dir := Vector3(sin(a), 0.25, -cos(a)).normalized()
	var to := ship.position + dir * 2.4
	var from := ship.position + dir * 14.0
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.06
	cm.height = from.distance_to(to)
	m.mesh = cm
	m.material_override = _unshaded(Color(1.0, 0.55, 0.15), 6.0)
	add_child(m)
	m.position = (from + to) * 0.5
	m.look_at_from_position(m.position, to, Vector3.UP)
	m.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var tw := create_tween()
	tw.tween_property(m, "scale", Vector3(0.1, 1, 0.1), 0.4)
	tw.tween_callback(m.queue_free)


func _boom(delay: float) -> void:
	if animate and delay > 0.0:
		await get_tree().create_timer(delay).timeout
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	s.mesh = sm
	var m := _unshaded(Color(1.0, 0.6, 0.2), 5.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s.material_override = m
	add_child(s)
	s.position = ship.position
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
	# finestra stretta (pannello laterale): si inquadra in larghezza, così la scheda resta intera
	var vs := get_viewport().get_visible_rect().size
	if vs.y > 0 and is_instance_valid(cam):
		var narrow := vs.x < vs.y * 1.6
		cam.keep_aspect = Camera3D.KEEP_WIDTH if narrow else Camera3D.KEEP_HEIGHT
		cam.fov = 69.0 if narrow else 42.0
	if is_instance_valid(ship):
		ship.rotation.y = sin(_t * 0.3) * 0.25
		ship.position.y = ship_pos.y + sin(_t * 0.9) * 0.12
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
				dist = clampf(dist * d0 / d1, 4.0, 45.0)
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
			dist = clampf(dist * 0.9, 4.0, 45.0)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = clampf(dist * 1.1, 4.0, 45.0)
		elif ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_drag = ev.button_index if ev.pressed else 0
	elif ev is InputEventMouseMotion and _drag != 0:
		if ev.button_mask == 0:
			_drag = 0
		elif _drag == MOUSE_BUTTON_RIGHT or ev.shift_pressed:
			yaw -= ev.relative.x * 0.006
			pitch = clampf(pitch - ev.relative.y * 0.005, -1.45, -0.15)
		else:
			_pan(ev.relative)
	elif ev is InputEventMagnifyGesture:
		dist = clampf(dist / ev.factor, 4.0, 45.0)
