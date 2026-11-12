extends SceneTree
func _init():
	root.size = Vector2i(1280, 720)
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var m = main.current
	m._load_scenario(0)
	m.st["sides"][0]["ctrl"] = 3
	var cfg = m._config()
	main.start_game(cfg)
	await create_timer(2.0).timeout
	var g = main.current
	g.act_panel.visible = false
	var b = g.board
	g.eng.abort = true
	var u = g.eng.ships_of(0)[0]
	b.target_goal = b.H.world(u["pos"])
	b.target = b.target_goal
	b.dist = 9.0
	b.yaw = 0.6
	await create_timer(1.0).timeout
	var n = b.unit_nodes[u["uid"]]
	var mdl = n.get_node("modello")
	print("modello ", mdl, " vis ", mdl.visible, " pos ", mdl.global_position, " figli ", mdl.get_child_count())
	root.get_viewport().get_texture().get_image().save_png("/tmp/close.png")
	quit()
