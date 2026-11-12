extends Control
## Regolamento in italiano (assets/regole.md), con indice delle sezioni a sinistra.

var main
var overlay := false
var text: RichTextLabel
var sections := []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0.02, 0.96 if overlay else 1.0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40
	root.offset_right = -40
	root.offset_top = 30
	root.offset_bottom = -30
	root.add_theme_constant_override("separation", 24)
	add_child(root)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(360, 0)
	left.add_theme_constant_override("separation", 6)
	root.add_child(left)
	left.add_child(UI.title("Regolamento", 56))
	var lsc := ScrollContainer.new()
	lsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(lsc)
	var idx := VBoxContainer.new()
	idx.add_theme_constant_override("separation", 6)
	lsc.add_child(idx)
	var f := FileAccess.open("res://assets/regole.md", FileAccess.READ)
	var md := f.get_as_text() if f != null else ""
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.frame(UI.LILAC, 0.9))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(panel)
	text = UI.rich(20)
	text.fit_content = false
	text.scroll_active = true
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(700, 400)
	panel.add_child(text)
	var lines := md.split("\n")
	var n := 0
	for ln in lines:
		var s := ln.strip_edges(false, true)
		if s.begins_with("## "):
			var title := s.substr(3)
			text.append_text("\n[font_size=28][color=#ff9c00]%s[/color][/font_size]\n" % title)
			var b := UI.button(title, 350, 40, 18, UI.LILAC)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var line_no := n
			b.pressed.connect(func(): text.scroll_to_paragraph(line_no))
			idx.add_child(b)
		elif s.begins_with("# "):
			text.append_text("[font_size=40][color=#ff9c00]%s[/color][/font_size]\n" % s.substr(2))
		elif s.begins_with("- "):
			text.append_text("  [color=#cc99cc]-[/color] %s\n" % _inline(s.substr(2)))
		elif s == "":
			text.append_text("\n")
		else:
			text.append_text(_inline(s) + "\n")
		n = text.get_paragraph_count()
	var back := UI.primary(UI.button("Chiudi" if overlay else "Torna al menu", 350, 56, 20))
	back.pressed.connect(func():
		if overlay:
			queue_free()
		else:
			main.show_menu())
	left.add_child(back)


func _inline(s: String) -> String:
	# **grassetto** -> [b]
	var out := ""
	var bold := false
	var parts := s.split("**")
	for i in parts.size():
		if i > 0:
			bold = not bold
			out += "[b][color=#ffcc99]" if bold else "[/color][/b]"
		out += parts[i]
	return out
