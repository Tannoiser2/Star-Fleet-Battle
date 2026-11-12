extends SceneTree
## Salvataggio e caricamento su Firebase (o sul finto Firebase di tests/firebase_mock.py).
func _init() -> void:
	var net := Net.new()
	root.add_child(net)
	await process_frame
	var data := {"cfg": var_to_str({"seed": 3, "turns": 2}), "acts": var_to_str([{1: {"spd": 4}}, null]), "turn": 1}
	var code := await net.save_game(data)
	print("CODICE ", code, " ", net.last_error)
	var back := await net.load_game(code)
	print("RILETTO ", back == data)
	quit()
