class_name SSD2D
extends Control
## Scheda SSD ritagliata (solo la nave, senza tabelle), adattata allo spazio disponibile.
## Sopra le caselle: armi colorate per stato (rosso sparata, verde pronta, grigio scarica),
## sistemi e scudi persi anneriti e barrati. Si aggiorna a ogni cambio di stato della partita.

const D = preload("res://scripts/data/sfb_data.gd")

var eng
var uid := -1
var data := {}
var tex: Texture2D


static func has_data(id: String) -> bool:
	return ResourceLoader.exists("res://assets/ssd3d/%s.json" % id) or FileAccess.file_exists("res://assets/ssd3d/%s.json" % id)


func setup(e, u_id: int) -> void:
	eng = e
	uid = u_id
	var u: Dictionary = eng.units[uid]
	tex = load("res://assets/ssd3d/%s.png" % u["id"])
	var f := FileAccess.open("res://assets/ssd3d/%s.json" % u["id"], FileAccess.READ)
	data = JSON.parse_string(f.get_as_text())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if eng.has_signal("changed"):
		eng.changed.connect(queue_redraw)
	resized.connect(queue_redraw)


func _lost(n: int, cur: int, mx: int) -> int:
	if mx <= 0:
		return 0
	return clampi(int(round(n * (1.0 - float(cur) / float(mx)))), 0, n)


func _draw() -> void:
	if tex == null or not eng.units.has(uid):
		return
	var w := float(data["w"])
	var h := float(data["h"])
	var k := minf(size.x / w, size.y / h)
	var off := Vector2((size.x - w * k) * 0.5, 0.0)
	draw_texture_rect(tex, Rect2(off, Vector2(w, h) * k), false)
	var u: Dictionary = eng.units[uid]
	var rect := func(b: Array) -> Rect2:
		return Rect2(off + Vector2(float(b[0]), float(b[1])) * k, Vector2(float(b[2]), float(b[3])) * k)
	var dead := func(r: Rect2) -> void:
		draw_rect(r, Color(0.08, 0.08, 0.1, 0.85))
		draw_line(r.position, r.end, Color(1, 0.3, 0.25), maxf(1.0, k * 2.5))
		draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color(1, 0.3, 0.25), maxf(1.0, k * 2.5))
	for key in data["sys"]:
		var arr: Array = data["sys"][key]
		var lost := _lost(arr.size(), int(u["sys"].get(key, 0)), int(u["max"].get(key, 0)))
		for n in lost:
			dead.call(rect.call(arr[arr.size() - 1 - n]))
	for si in data["shield"]:
		var arr2: Array = data["shield"][si]
		var i := int(si)
		if i < 0 or i > 5:
			continue
		var lost2 := _lost(arr2.size(), int(u["sh"][i]), int(u["sh_max"][i]))
		for n in lost2:
			draw_rect(rect.call(arr2[arr2.size() - 1 - n]), Color(0.1, 0.12, 0.2, 0.8))
	for t in data.get("weapt", {}):
		var arrw: Array = data["weapt"][t]
		var cols: Array = SSD3D.weapon_box_colors(u, t, arrw.size())
		for i2 in arrw.size():
			var r: Rect2 = rect.call(arrw[i2])
			if cols[i2] == null:
				dead.call(r)
			else:
				var c: Color = cols[i2]
				draw_rect(r, Color(c, 0.6))
				draw_rect(r, c.darkened(0.3), false, maxf(1.0, k * 2.0))
