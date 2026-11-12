extends RefCounted
## Geometria della mappa esagonale di Star Fleet Battles (esagoni a lato piatto in alto, colonne
## verticali). Le direzioni A-F (0-5) puntano ai lati dell'esagono: A in alto, poi in senso orario.
## Coordinate assiali (q, r): q = colonna - 1; la numerazione SFB «CCRR» usa colonne e righe da 1, con
## le colonne pari spostate di mezzo esagono verso il basso.

const COLS := 42
const ROWS := 30
const SQ3 := 1.7320508

## Spostamenti assiali per le direzioni A..F
const DIRS := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]
const DIR_LETTERS := ["A", "B", "C", "D", "E", "F"]


static func from_label(col: int, row: int) -> Vector2i:
	var q := col - 1
	var r0 := row - 1
	return Vector2i(q, r0 - (q - (q & 1)) / 2)


static func to_colrow(h: Vector2i) -> Vector2i:
	var q := h.x
	return Vector2i(q + 1, h.y + (q - (q & 1)) / 2 + 1)


static func label(h: Vector2i) -> String:
	var cr := to_colrow(h)
	return "%02d%02d" % [cr.x, cr.y]


static func on_map(h: Vector2i) -> bool:
	var cr := to_colrow(h)
	return cr.x >= 1 and cr.x <= COLS and cr.y >= 1 and cr.y <= ROWS


static func neighbor(h: Vector2i, d: int) -> Vector2i:
	return h + DIRS[posmod(d, 6)]


static func dist(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


## Posizione nel piano (unità = raggio dell'esagono); y del Vector2 = verso il basso (sud)
static func to_plane(h: Vector2i) -> Vector2:
	return Vector2(1.5 * h.x, SQ3 * (h.y + h.x * 0.5))


static func world(h: Vector2i, y := 0.0) -> Vector3:
	var p := to_plane(h)
	return Vector3(p.x, y, p.y)


## Esagono più vicino a un punto del piano
static func from_plane(p: Vector2) -> Vector2i:
	var q := p.x / 1.5
	var r := p.y / SQ3 - q * 0.5
	var x := q
	var z := r
	var y := -x - z
	var rx := roundf(x)
	var ry := roundf(y)
	var rz := roundf(z)
	var dx := absf(rx - x)
	var dy := absf(ry - y)
	var dz := absf(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))


## Rilevamento assoluto (gradi, 0 = direzione A, in senso orario) da a verso b
static func bearing(a: Vector2i, b: Vector2i) -> float:
	var d := to_plane(b) - to_plane(a)
	return fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)


## Rilevamento relativo alla prua di chi guarda (facing 0-5)
static func rel_bearing(a: Vector2i, face: int, b: Vector2i) -> float:
	return fposmod(bearing(a, b) - face * 60.0, 360.0)


## Il bersaglio è dentro l'arco? (intervalli in gradi relativi, estremi inclusi)
static func in_arc(arcs: Array, rel: float) -> bool:
	for iv in arcs:
		var lo := float(iv[0]) - 0.6
		var hi := float(iv[1]) + 0.6
		if hi - lo >= 359.0:
			return true
		var x := rel
		while x < lo:
			x += 360.0
		while x > lo + 360.0:
			x -= 360.0
		if x <= hi:
			return true
	return false


## Scudo colpito (0-5 = scudi #1-#6) da un colpo che arriva dal rilevamento relativo rel.
## Sullo spigolo fra due scudi restituisce entrambi.
static func shields_for(rel: float) -> Array:
	var x := fposmod(rel + 30.0, 360.0)
	var s := int(floor(x / 60.0)) % 6
	var frac := x - s * 60.0
	if frac < 0.6:
		return [s, posmod(s - 1, 6)]
	if frac > 59.4:
		return [s, (s + 1) % 6]
	return [s]


## Direzione (0-5) più vicina al rilevamento assoluto
static func dir_toward(a: Vector2i, b: Vector2i) -> int:
	return int(roundf(bearing(a, b) / 60.0)) % 6


## Una mossa verso la destinazione: la direzione vicina a face (+-1) che riduce di più la distanza
static func step_toward(h: Vector2i, face: int, target: Vector2i, turn_ok: bool) -> int:
	var best := face
	var bd := 9999.0
	var opts := [face]
	if turn_ok:
		opts = [face, posmod(face - 1, 6), posmod(face + 1, 6)]
	for d in opts:
		var n := neighbor(h, d)
		var dd := float(dist(n, target)) + 0.01 * absf(angle_difference(deg_to_rad(bearing(n, target)), deg_to_rad(d * 60.0)))
		if dd < bd:
			bd = dd
			best = d
	return best
