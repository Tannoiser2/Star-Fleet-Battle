class_name Audio
extends Node
## Musica ed effetti. Musica: assets/audio/musica/tema.* nel menu, battaglia*.* durante la partita
## (a rotazione). Effetti: assets/audio/effetti/<nome>.* (phaser, fotone, disgregatore, plasma, drone,
## esplosione, scudo, danni, lancio, clic). I file mancanti vengono semplicemente ignorati.

const EXT := ["ogg", "mp3", "wav"]

static var music_on := true
static var sfx_on := true
static var music_vol := 0.7
static var sfx_vol := 0.8

var player: AudioStreamPlayer
var sfx: Array = []
var mode := ""
var battle: Array = []
var bi := 0
var _cache := {}


func _ready() -> void:
	_load_prefs()
	player = AudioStreamPlayer.new()
	player.bus = "Master"
	add_child(player)
	player.finished.connect(_next)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		sfx.append(p)
	battle = _list("res://assets/audio/musica", "battaglia")
	_apply()


func _list(dir: String, prefix: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		var f2 := f.trim_suffix(".import").trim_suffix(".remap")
		if f2.begins_with(prefix) and f2.get_extension() in EXT and not (dir + "/" + f2) in out:
			out.append(dir + "/" + f2)
	out.sort()
	return out


func _stream(base: String) -> AudioStream:
	if _cache.has(base):
		return _cache[base]
	var s: AudioStream = null
	for e in EXT:
		if ResourceLoader.exists(base + "." + e):
			s = load(base + "." + e)
			break
	if s == null and ResourceLoader.exists(base):
		s = load(base)
	_cache[base] = s
	return s


func play_menu() -> void:
	if mode == "menu":
		return
	mode = "menu"
	var s := _stream("res://assets/audio/musica/tema")
	_play(s)


func play_battle() -> void:
	if mode == "battle":
		return
	mode = "battle"
	if battle.is_empty():
		player.stop()
		return
	bi = randi() % battle.size()
	_play(_stream(battle[bi]))


func _play(s: AudioStream) -> void:
	player.stop()
	if s == null:
		return
	if s is AudioStreamMP3:
		s.loop = mode == "menu"
	elif s is AudioStreamOggVorbis:
		s.loop = mode == "menu"
	player.stream = s
	_apply()
	if music_on:
		player.play()


func _next() -> void:
	if mode == "battle" and not battle.is_empty() and music_on:
		bi = (bi + 1) % battle.size()
		_play(_stream(battle[bi]))


func fx(name: String, vol := 0.0) -> void:
	if not sfx_on:
		return
	var s := _stream("res://assets/audio/effetti/" + name)
	if s == null:
		return
	for p in sfx:
		if not p.playing:
			p.stream = s
			p.volume_db = linear_to_db(sfx_vol) + vol
			p.play()
			return


func _apply() -> void:
	if player == null:
		return
	player.volume_db = linear_to_db(maxf(0.001, music_vol))
	if not music_on:
		player.stop()
	elif player.stream != null and not player.playing:
		player.play()


func toggle_music() -> void:
	music_on = not music_on
	_apply()
	_save_prefs()


func toggle_sfx() -> void:
	sfx_on = not sfx_on
	_save_prefs()


func _save_prefs() -> void:
	var c := ConfigFile.new()
	c.set_value("audio", "musica", music_on)
	c.set_value("audio", "effetti", sfx_on)
	c.save("user://starfleet_audio.cfg")


func _load_prefs() -> void:
	var c := ConfigFile.new()
	if c.load("user://starfleet_audio.cfg") == OK:
		music_on = bool(c.get_value("audio", "musica", true))
		sfx_on = bool(c.get_value("audio", "effetti", true))
