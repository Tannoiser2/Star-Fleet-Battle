extends Control
## Radice dell'applicazione: alterna menu, partita e regole.

var current: Control
var net: Net
var lobby := {}
var menu_state := {}
var stars: Control


func get_net() -> Net:
	if net == null:
		net = Net.new()
		add_child(net)
	return net


func _ready() -> void:
	theme = UI.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# la radice non deve catturare il mouse, altrimenti trascinare sulla mappa 3D non arriva alla telecamera
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars = UI.Starfield.new()
	add_child(stars)
	show_menu()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_F11:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _clear() -> void:
	if current != null:
		current.queue_free()
		current = null


func show_menu() -> void:
	_clear()
	stars.visible = true
	var m := preload("res://scripts/ui/menu.gd").new()
	m.main = self
	add_child(m)
	current = m


func start_game(config: Dictionary) -> void:
	_clear()
	stars.visible = false
	var g := preload("res://scripts/ui/game_view.gd").new()
	g.main = self
	g.config = config
	add_child(g)
	current = g


func show_rules() -> void:
	_clear()
	stars.visible = true
	var t := preload("res://scripts/ui/rules_view.gd").new()
	t.main = self
	add_child(t)
	current = t
