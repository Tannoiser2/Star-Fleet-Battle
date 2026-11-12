extends Node3D
## Mappa 3D: il campo stellare esagonale del modulo, le pedine originali delle astronavi con sopra il
## modello 3D, droni, siluri al plasma, navette e gli effetti di fuoco.
## Telecamera: trascinare = spostare la vista; tasto destro (o due dita che ruotano) = girare;
## rotella (o pizzico) = zoom. Vista dall'alto 2D con le sole pedine.

const H = preload("res://scripts/core/hexgrid.gd")
const D = preload("res://scripts/data/sfb_data.gd")

signal hex_clicked(h: Vector2i)
signal unit_clicked(uid: int)
signal hex_hovered(h: Vector2i)

const MAP_W := 7377.0 / 116.0
const MAP_H := 6101.0 / 116.0
const MAP_X0 := -115.0 / 116.0
const MAP_Z0 := -100.0 / 116.0
const DIST_MIN := 6.0
const DIST_MAX := 90.0
const PITCH_MIN := -1.45
const PITCH_MAX := -0.35

var eng
var cam: Camera3D
var pivot: Node3D
var target := Vector3(31, 0, 26)
var target_goal := Vector3(31, 0, 26)
var yaw := 0.0
var pitch := -0.9
var dist := 26.0
var top_view := false
var input_locked := false
var units_root: Node3D
var fx_root: Node3D
var over_root: Node3D
var unit_nodes := {}
var unit_goal := {}
var unit_rot := {}
var selected := -1
var _t := 0.0
var _drag := false
var _drag_btn := 0
var _moved := 0.0
var _touches := {}
var _touch_moved := 0.0
var _model_cache := {}
var _mat_cache := {}
var ghosts: Array = []      # [[hex, label, act]]
var sel_ring: MeshInstance3D
var arc_mesh: MeshInstance3D
var light_dir: DirectionalLight3D
var show_models := true


func setup(e) -> void:
	eng = e
	_build_env()
	_build_camera()
	_build_map()
	units_root = Node3D.new()
	add_child(units_root)
	fx_root = Node3D.new()
	add_child(fx_root)
	over_root = Node3D.new()
	add_child(over_root)
	_build_selection()
	eng.fx.connect(_on_fx)
	refresh()
	# inquadra le navi
	var c := Vector3.ZERO
	var n := 0
	for u in eng.live_ships():
		c += H.world(u["pos"])
		n += 1
	if n > 0:
		target = c / n
		target_goal = target


func _build_env() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#000004")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#8a90b0")
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_hdr_threshold = 1.2
	e.glow_bloom = 0.15
	we.environment = e
	add_child(we)
	light_dir = DirectionalLight3D.new()
	light_dir.rotation = Vector3(-0.9, 0.6, 0)
	light_dir.light_energy = 1.25
	light_dir.light_color = Color("#fff4e6")
	add_child(light_dir)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.4, -2.4, 0)
	fill.light_energy = 0.45
	fill.light_color = Color("#9fb4ff")
	add_child(fill)


func _build_camera() -> void:
	pivot = Node3D.new()
	add_child(pivot)
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.far = 1000.0
	cam.near = 0.1
	pivot.add_child(cam)
	cam.current = true
	_update_cam()


func _build_map() -> void:
	var m := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(MAP_W, MAP_H)
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/board/mappa.jpg")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.92, 0.92, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.material_override = mat
	m.position = Vector3(MAP_X0 + MAP_W / 2.0, -0.02, MAP_Z0 + MAP_H / 2.0)
	add_child(m)
	# bordo luminoso della mappa
	var edge := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	edge.mesh = im
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color(1.0, 0.6, 0.0, 0.8)
	edge.material_override = em
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in [Vector3(MAP_X0, 0, MAP_Z0), Vector3(MAP_X0 + MAP_W, 0, MAP_Z0), Vector3(MAP_X0 + MAP_W, 0, MAP_Z0 + MAP_H), Vector3(MAP_X0, 0, MAP_Z0 + MAP_H), Vector3(MAP_X0, 0, MAP_Z0)]:
		im.surface_add_vertex(p)
	im.surface_end()
	add_child(edge)


func _build_selection() -> void:
	sel_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.02
	tm.rings = 48
	tm.ring_segments = 6
	sel_ring.mesh = tm
	sel_ring.material_override = _emissive(Color(1.0, 0.75, 0.2), 2.0)
	sel_ring.visible = false
	add_child(sel_ring)
	arc_mesh = MeshInstance3D.new()
	arc_mesh.mesh = ImmediateMesh.new()
	var am := StandardMaterial3D.new()
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	am.vertex_color_use_as_albedo = true
	am.cull_mode = BaseMaterial3D.CULL_DISABLED
	arc_mesh.material_override = am
	add_child(arc_mesh)


func _emissive(col: Color, e := 1.5, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col, alpha)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = e
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


# ---------------------------------------------------------------- telecamera

func _update_cam() -> void:
	pivot.position = target
	pivot.rotation = Vector3(pitch if not top_view else -PI / 2.0, yaw, 0)
	if top_view:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = dist * 0.83
		cam.position = Vector3(0, 0, 60.0)
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.position = Vector3(0, 0, dist)


func focus_hex(h: Vector2i) -> void:
	# il pannello delle azioni copre la parte bassa dello schermo: la nave va un po' più in alto
	target_goal = H.world(h) + Vector3(sin(yaw), 0, cos(yaw)) * dist * (0.0 if top_view else 0.28)


func set_top_view(on: bool) -> void:
	top_view = on
	show_models = not on
	if on:
		dist = maxf(dist, 44.0)
	for id in unit_nodes:
		var n: Node3D = unit_nodes[id]
		var mdl := n.get_node_or_null("modello")
		if mdl != null:
			mdl.visible = show_models
	refresh()


func _process(dt: float) -> void:
	_t += dt
	target = target.lerp(target_goal, minf(1.0, dt * 5.0))
	_update_cam()
	for id in unit_nodes.keys():
		var n: Node3D = unit_nodes[id]
		if not is_instance_valid(n):
			unit_nodes.erase(id)
			continue
		var goal: Vector3 = unit_goal.get(id, n.position)
		n.position = n.position.lerp(goal, minf(1.0, dt * 9.0))
		var rg: float = unit_rot.get(id, 0.0)
		n.rotation.y = lerp_angle(n.rotation.y, rg, minf(1.0, dt * 9.0))
		var mdl := n.get_node_or_null("modello")
		if mdl != null:
			mdl.position.y = 1.2 + sin(_t * 1.4 + float(id % 11)) * 0.06
		var pl := n.get_node_or_null("sfera")
		if pl != null:
			var k := 1.0 + 0.15 * sin(_t * 9.0 + id)
			pl.scale = Vector3(k, k, k)
	if sel_ring.visible:
		sel_ring.rotation.y += dt * 0.8


func _over_gui(sp: Vector2) -> bool:
	var c := get_viewport().gui_get_hovered_control()
	if c == null:
		return false
	return c.get_global_rect().has_point(sp) and c.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _input(ev: InputEvent) -> void:
	if not is_visible_in_tree() or input_locked:
		_drag = false
		return
	# --- tocco: un dito sposta la vista, due dita pizzicano (zoom) e ruotano
	if ev is InputEventScreenTouch:
		if ev.pressed:
			if _over_gui(ev.position):
				return
			_touches[ev.index] = ev.position
			if _touches.size() == 1:
				_touch_moved = 0.0
		else:
			if _touches.has(ev.index):
				_touches.erase(ev.index)
				if _touches.is_empty() and _touch_moved < 12.0:
					_click(ev.position)
				_touch_moved = 99.0 if not _touches.is_empty() else _touch_moved
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventScreenDrag:
		if not _touches.has(ev.index):
			return
		_touch_moved += ev.relative.length()
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
			if d0 > 1.0 and d1 > 1.0:
				dist = clampf(dist * d0 / d1, DIST_MIN, DIST_MAX)
			var a0 := (old - other).angle()
			var a1: float = (ev.position - other).angle()
			yaw += angle_difference(a0, a1) * -1.0
			_pan((ev.position - old) * 0.5)
			_touches[ev.index] = ev.position
			_touch_moved = 99.0
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventMagnifyGesture:
		if not _over_gui(ev.position):
			dist = clampf(dist / ev.factor, DIST_MIN, DIST_MAX)
		return
	if ev is InputEventPanGesture:
		if not _over_gui(ev.position):
			dist = clampf(dist * (1.0 + ev.delta.y * 0.05), DIST_MIN, DIST_MAX)
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var fo := get_viewport().gui_get_focus_owner()
		if fo is LineEdit:
			return
		match ev.keycode:
			KEY_PAGEUP:
				yaw += 0.26
			KEY_PAGEDOWN:
				yaw -= 0.26
			KEY_LEFT:
				_pan(Vector2(80, 0))
			KEY_RIGHT:
				_pan(Vector2(-80, 0))
			KEY_UP:
				_pan(Vector2(0, 80))
			KEY_DOWN:
				_pan(Vector2(0, -80))
			KEY_EQUAL, KEY_KP_ADD:
				dist = clampf(dist * 0.85, DIST_MIN, DIST_MAX)
			KEY_MINUS, KEY_KP_SUBTRACT:
				dist = clampf(dist * 1.18, DIST_MIN, DIST_MAX)
		return
	if ev is InputEventMouseButton:
		if ev.pressed and _over_gui(ev.position):
			return
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			dist = clampf(dist * 0.9, DIST_MIN, DIST_MAX)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			dist = clampf(dist * 1.1, DIST_MIN, DIST_MAX)
		elif ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if ev.pressed:
				_drag = true
				_drag_btn = ev.button_index
				_moved = 0.0
			elif _drag and ev.button_index == _drag_btn:
				_drag = false
				if ev.button_index == MOUSE_BUTTON_LEFT and _moved < 8.0 and not _over_gui(ev.position):
					_click(ev.position)
	elif ev is InputEventMouseMotion:
		if _drag and ev.button_mask == 0:
			_drag = false
		if _drag:
			_moved += ev.relative.length()
			if _moved > 6.0:
				if _drag_btn == MOUSE_BUTTON_RIGHT or (_drag_btn == MOUSE_BUTTON_LEFT and ev.shift_pressed):
					yaw -= ev.relative.x * 0.006
					if not top_view:
						pitch = clampf(pitch - ev.relative.y * 0.005, PITCH_MIN, PITCH_MAX)
				else:
					_pan(ev.relative)
		elif not _over_gui(ev.position):
			var p = _ray_plane(ev.position)
			if p != null:
				hex_hovered.emit(H.from_plane(Vector2(p.x, p.z)))


func _pan(rel: Vector2) -> void:
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var k := dist * 0.0017
	target_goal += (-right * rel.x + fwd * rel.y) * k
	target_goal.y = 0.0
	target_goal.x = clampf(target_goal.x, MAP_X0 - 4, MAP_X0 + MAP_W + 4)
	target_goal.z = clampf(target_goal.z, MAP_Z0 - 4, MAP_Z0 + MAP_H + 4)


func _ray_plane(sp: Vector2, h := 0.0) -> Variant:
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	if absf(d.y) < 1e-4:
		return null
	var t := (h - o.y) / d.y
	if t < 0:
		return null
	return o + d * t


func _click(sp: Vector2) -> void:
	# prima i modelli (sono sopra il piano), poi l'esagono
	var best := -1
	var bd := 40.0
	for id in unit_nodes:
		var n: Node3D = unit_nodes[id]
		if not is_instance_valid(n) or not n.visible:
			continue
		var pts := [n.global_position + Vector3(0, 0.1, 0)]
		if show_models:
			pts.append(n.global_position + Vector3(0, 1.0, 0))
		for p in pts:
			if cam.is_position_behind(p):
				continue
			var s := cam.unproject_position(p)
			var dd := s.distance_to(sp)
			if dd < bd:
				bd = dd
				best = id
	var p2 = _ray_plane(sp)
	if p2 != null:
		var h := H.from_plane(Vector2(p2.x, p2.z))
		for g in ghosts:
			if g[0] == h:
				hex_clicked.emit(h)
				return
		if best >= 0:
			unit_clicked.emit(best)
			return
		hex_clicked.emit(h)
	elif best >= 0:
		unit_clicked.emit(best)


# ---------------------------------------------------------------- unità

func _model(id: String) -> PackedScene:
	if not _model_cache.has(id):
		var p := "res://assets/ships/%s.glb" % id
		_model_cache[id] = load(p) if ResourceLoader.exists(p) else null
	return _model_cache[id]


func _hull_mat(race: String) -> StandardMaterial3D:
	if not _mat_cache.has(race):
		var m := StandardMaterial3D.new()
		m.albedo_color = (D.RACES[race]["scafo"] as Color).darkened(0.25)
		m.metallic = 0.6
		m.roughness = 0.42
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.rim_enabled = true
		m.rim = 0.3
		_mat_cache[race] = m
	return _mat_cache[race]


func _apply_mat(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		n.material_override = m
	for c in n.get_children():
		_apply_mat(c, m)


func _side_col(s: int) -> Color:
	return D.PCOLORS[int(eng.sides[s]["col"]) % D.PCOLORS.size()]


func _ship_node(u: Dictionary) -> Node3D:
	var root := Node3D.new()
	# pedina originale del modulo, piatta sul campo stellare, con il bordo nel colore del giocatore
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.62, 0.08, 1.62)
	base.mesh = bm
	base.material_override = _emissive(_side_col(u["side"]), 0.8)
	base.position.y = 0.02
	root.add_child(base)
	var tok := MeshInstance3D.new()
	var qm := PlaneMesh.new()
	qm.size = Vector2(1.45, 1.45)
	tok.mesh = qm
	var tm := StandardMaterial3D.new()
	tm.albedo_texture = load("res://assets/counters/%s.png" % u["id"])
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tok.material_override = tm
	tok.position.y = 0.07
	tok.name = "pedina"
	root.add_child(tok)
	# modello 3D sopra la pedina
	var ps := _model(u["id"])
	if ps != null:
		var holder := Node3D.new()
		holder.name = "modello"
		var mdl := ps.instantiate()
		var sz: int = int(D.ship(u["id"])["sz"])
		var k := 2.6 if sz <= 2 else (2.2 if sz == 3 else 1.7)
		mdl.scale = Vector3(k, k, k)
		_apply_mat(mdl, _hull_mat(u["race"]))
		holder.add_child(mdl)
		holder.position.y = 1.2
		holder.visible = show_models
		root.add_child(holder)
		# stelo luminoso fra pedina e modello
		var st := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.025
		cm.bottom_radius = 0.025
		cm.height = 1.1
		st.mesh = cm
		st.material_override = _emissive(_side_col(u["side"]), 1.2, 0.7)
		st.position.y = 0.5
		holder.add_child(st)
		st.position.y = -0.6
	# anelli degli scudi
	var shr := Node3D.new()
	shr.name = "scudi"
	root.add_child(shr)
	for i in 6:
		var seg := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.62, 0.05, 0.08)
		seg.mesh = sm
		var ang := deg_to_rad(i * 60.0)
		seg.position = Vector3(sin(ang) * 1.0, 0.1, -cos(ang) * 1.0)
		seg.rotation.y = -ang
		seg.name = "s%d" % i
		shr.add_child(seg)
	# nome
	var lab := Label3D.new()
	lab.name = "nome"
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.font = UI.font_head
	lab.font_size = 44
	lab.pixel_size = 0.009
	lab.outline_size = 10
	lab.modulate = _side_col(u["side"]).lightened(0.25)
	lab.outline_modulate = Color(0, 0, 0, 0.9)
	lab.position = Vector3(0, 2.4, 0)
	lab.no_depth_test = true
	root.add_child(lab)
	return root


func _small_node(u: Dictionary) -> Node3D:
	var root := Node3D.new()
	var col := _side_col(u["side"])
	match u["kind"]:
		"drone":
			var m := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = 0.16
			c.height = 0.6
			m.mesh = c
			m.rotation.x = -PI / 2.0
			m.material_override = _emissive(col.lightened(0.2), 2.5)
			m.position.y = 0.6
			root.add_child(m)
		"plasma":
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.32
			sm.height = 0.64
			s.mesh = sm
			s.material_override = _emissive(Color(0.4, 1.0, 0.35), 4.0)
			s.position.y = 0.7
			s.name = "sfera"
			root.add_child(s)
			var l := OmniLight3D.new()
			l.light_color = Color(0.5, 1.0, 0.4)
			l.light_energy = 1.4
			l.omni_range = 3.0
			l.position.y = 0.7
			root.add_child(l)
		"shut":
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.28, 0.14, 0.5)
			b.mesh = bm
			b.material_override = _hull_mat(u.get("race", "fed"))
			b.position.y = 0.7
			root.add_child(b)
			var r := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.32
			tm.outer_radius = 0.38
			r.mesh = tm
			r.material_override = _emissive(col, 1.5)
			r.position.y = 0.05
			root.add_child(r)
	var lab := Label3D.new()
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.font = UI.font_head
	lab.font_size = 30
	lab.pixel_size = 0.008
	lab.outline_size = 8
	lab.modulate = col.lightened(0.3)
	lab.text = str(u["name"]).to_upper()
	lab.position = Vector3(0, 1.3, 0)
	lab.no_depth_test = true
	root.add_child(lab)
	return root


func refresh() -> void:
	if eng == null:
		return
	var seen := {}
	# più unità nello stesso esagono: piccolo scostamento
	var stack := {}
	for id in eng.units:
		var u: Dictionary = eng.units[id]
		if u["kind"] == "ship" and not u["alive"]:
			continue
		seen[id] = true
		var n: Node3D = unit_nodes.get(id, null)
		if n == null or not is_instance_valid(n):
			n = _ship_node(u) if u["kind"] == "ship" else _small_node(u)
			units_root.add_child(n)
			unit_nodes[id] = n
			n.position = H.world(u["pos"])
			n.rotation.y = -deg_to_rad(u["face"] * 60.0)
		var key: Vector2i = u["pos"]
		var k := int(stack.get(key, 0))
		stack[key] = k + 1
		var off := Vector3.ZERO
		if k > 0:
			var a := k * 2.1
			off = Vector3(cos(a), 0.02 * k, sin(a)) * (0.35 if u["kind"] == "ship" else 0.5)
		unit_goal[id] = H.world(u["pos"]) + off
		unit_rot[id] = -deg_to_rad(u["face"] * 60.0)
		if u["kind"] == "ship":
			var lab: Label3D = n.get_node("nome")
			var tag: String = str(D.ship(u["id"])["n"]).to_upper()
			if u["cloak"] > 0:
				tag += "  (OCCULTATA)"
			lab.text = tag
			var alpha := 0.35 if u["cloak"] > 0 else 1.0
			var mdl := n.get_node_or_null("modello")
			if mdl != null:
				mdl.visible = show_models and u["cloak"] == 0
			var shr: Node3D = n.get_node("scudi")
			for i in 6:
				var seg: MeshInstance3D = shr.get_node("s%d" % i)
				var mx := maxi(1, int(u["sh_max"][i]))
				var f := float(u["sh"][i]) / mx
				var c := Color(0.3, 0.6, 1.0).lerp(Color(1.0, 0.25, 0.2), 1.0 - f)
				if not u["sh_on"]:
					c = Color(0.3, 0.3, 0.3)
				seg.material_override = _emissive(c, 1.6 if u["sh_on"] else 0.2, alpha)
	for id in unit_nodes.keys():
		if not seen.has(id):
			var n: Node3D = unit_nodes[id]
			if is_instance_valid(n):
				n.queue_free()
			unit_nodes.erase(id)
			unit_goal.erase(id)
	_update_selection()


func select(uid: int) -> void:
	selected = uid
	_update_selection()


func _update_selection() -> void:
	if selected >= 0 and eng.units.has(selected) and eng.units[selected].get("alive", true):
		sel_ring.visible = true
		sel_ring.position = H.world(eng.units[selected]["pos"]) + Vector3(0, 0.12, 0)
	else:
		sel_ring.visible = false


# ---------------------------------------------------------------- sovrapposizioni

func set_ghosts(list: Array) -> void:
	ghosts = list
	for c in over_root.get_children():
		c.queue_free()
	for g in list:
		var h: Vector2i = g[0]
		var n := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.7
		tm.outer_radius = 0.82
		tm.ring_segments = 6
		tm.rings = 6
		n.mesh = tm
		var col: Color = g[3] if g.size() > 3 else UI.SKY
		n.material_override = _emissive(col, 1.8, 0.85)
		n.position = H.world(h) + Vector3(0, 0.06, 0)
		n.rotation.y = PI / 6.0
		over_root.add_child(n)
		var lab := Label3D.new()
		lab.text = str(g[1])
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.font = UI.font_head
		lab.font_size = 40
		lab.pixel_size = 0.011
		lab.outline_size = 8
		lab.modulate = col
		lab.position = H.world(h) + Vector3(0, 0.55, 0)
		lab.no_depth_test = true
		over_root.add_child(lab)


## Arco di tiro: ventaglio semitrasparente dalla posizione dell'unità
func show_arc(u, arc: String, rng: int, col := Color(1.0, 0.6, 0.0, 0.16)) -> void:
	var im: ImmediateMesh = arc_mesh.mesh
	im.clear_surfaces()
	if u == null:
		return
	var c := H.world(u["pos"], 0.03)
	var r := float(rng) * H.SQ3
	var face: int = u["face"]
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for iv in D.ARCS.get(arc, D.ARCS["360"]):
		var a0 := float(iv[0])
		var a1 := float(iv[1])
		var steps := maxi(4, int((a1 - a0) / 6.0))
		for s in steps:
			var b0 := deg_to_rad(face * 60.0 + a0 + (a1 - a0) * s / steps)
			var b1 := deg_to_rad(face * 60.0 + a0 + (a1 - a0) * (s + 1) / steps)
			im.surface_set_color(Color(col, col.a * 1.6))
			im.surface_add_vertex(c)
			im.surface_set_color(col)
			im.surface_add_vertex(c + Vector3(sin(b0), 0, -cos(b0)) * r)
			im.surface_set_color(col)
			im.surface_add_vertex(c + Vector3(sin(b1), 0, -cos(b1)) * r)
	im.surface_end()


# ---------------------------------------------------------------- effetti

func _pos_of(uid: int, fallback := Vector3.ZERO) -> Vector3:
	var n: Node3D = unit_nodes.get(uid, null)
	if n != null and is_instance_valid(n):
		return n.global_position + Vector3(0, 1.0 if show_models else 0.2, 0)
	if eng.units.has(uid):
		return H.world(eng.units[uid]["pos"], 1.0)
	return fallback


func _on_fx(kind: String, d: Dictionary) -> void:
	if eng.headless:
		return
	match kind:
		"shot":
			var a := _pos_of(int(d["from"]))
			var b := _pos_of(int(d["to"]))
			var w := str(d["w"])
			if not d["hit"]:
				b += Vector3(randf_range(-1.2, 1.2), 0.4, randf_range(-1.2, 1.2))
			if w.begins_with("PH"):
				_beam(a, b, Color(1.0, 0.55, 0.15) if w != "PH-3" else Color(1.0, 0.8, 0.3), 0.06 if w == "PH-1" else 0.04)
			elif w == "FOTON":
				_bolt(a, b, Color(1.0, 0.25, 0.15), 0.28)
			else:
				_bolt(a, b, Color(0.4, 1.0, 0.3), 0.18)
		"impact", "boom":
			var p: Vector3 = _pos_of(int(d.get("to", d.get("uid", -1))))
			if kind == "boom" and d.has("pos"):
				p = H.world(d["pos"], 1.0)
			_explosion(p, 2.4 if kind == "boom" else 1.0, Color(1.0, 0.6, 0.2))
		"shield":
			_explosion(_pos_of(int(d["uid"])), 0.7, Color(0.4, 0.7, 1.0))
		"internal":
			_explosion(_pos_of(int(d["uid"])), 0.9, Color(1.0, 0.4, 0.1))


func _beam(a: Vector3, b: Vector3, col: Color, w: float) -> void:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = w
	cm.bottom_radius = w
	cm.height = a.distance_to(b)
	m.mesh = cm
	m.material_override = _emissive(col, 5.0)
	fx_root.add_child(m)
	m.global_position = (a + b) * 0.5
	m.look_at_from_position(m.global_position, b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	m.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var tw := create_tween()
	tw.tween_property(m, "scale", Vector3(0.1, 1, 0.1), 0.45)
	tw.tween_callback(m.queue_free)


func _bolt(a: Vector3, b: Vector3, col: Color, r: float) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2
	m.mesh = sm
	m.material_override = _emissive(col, 6.0)
	fx_root.add_child(m)
	m.global_position = a
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 2.0
	l.omni_range = 2.5
	m.add_child(l)
	var tw := create_tween()
	tw.tween_property(m, "global_position", b, 0.35)
	tw.tween_callback(m.queue_free)


func _explosion(p: Vector3, size: float, col: Color) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	m.mesh = sm
	var mat := _emissive(col, 4.0, 0.9)
	m.material_override = mat
	fx_root.add_child(m)
	m.global_position = p
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 3.0 * size
	l.omni_range = 3.0 * size
	m.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * size * 2.2, 0.6)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tw.tween_property(l, "light_energy", 0.0, 0.6)
	tw.chain().tween_callback(m.queue_free)
