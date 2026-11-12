extends RefCounted
## Dati fissi di Star Fleet Battles (Captain's Basic Set): tabelle delle armi, tabella di
## assegnazione dei danni (D4.21), modi di virata, razze e navi (data/navi.json, trascritte dalle
## SSD del modulo «Fleet Builder»).

const RACES := {
	"fed": {"nome": "Federazione", "col": Color(0.55, 0.75, 0.95), "scafo": Color(0.86, 0.88, 0.92)},
	"kli": {"nome": "Impero Klingon", "col": Color(0.85, 0.25, 0.2), "scafo": Color(0.42, 0.5, 0.45)},
	"rom": {"nome": "Impero Romulano", "col": Color(0.35, 0.8, 0.45), "scafo": Color(0.62, 0.7, 0.62)},
	"gor": {"nome": "Confederazione Gorn", "col": Color(0.8, 0.7, 0.3), "scafo": Color(0.6, 0.58, 0.45)},
	"kzi": {"nome": "Egemonia Kzinti", "col": Color(0.95, 0.6, 0.2), "scafo": Color(0.72, 0.62, 0.5)},
	"tho": {"nome": "Assemblea Tholiana", "col": Color(0.95, 0.4, 0.75), "scafo": Color(0.85, 0.55, 0.35)},
	"ori": {"nome": "Pirati di Orione", "col": Color(0.65, 0.65, 0.7), "scafo": Color(0.38, 0.38, 0.42)},
}

## Colori dei giocatori (come i sacchetti del modulo: rosso, arancio, giallo, verde acqua, verde, viola, blu, bianco)
const PCOLORS := [Color(0.9, 0.2, 0.2), Color(0.25, 0.5, 1.0), Color(0.95, 0.85, 0.2), Color(0.2, 0.85, 0.3),
	Color(1.0, 0.55, 0.1), Color(0.7, 0.35, 0.95), Color(0.2, 0.85, 0.85), Color(0.95, 0.95, 0.95)]
const PCOL_NAMES := ["Rosso", "Blu", "Giallo", "Verde", "Arancio", "Viola", "Turchese", "Bianco"]

const SYS_NAMES := {
	"br": "Ponte", "fl": "Ponte di bandiera", "em": "Ponte d'emergenza", "aux": "Controllo ausiliario",
	"lab": "Laboratori", "tr": "Teletrasporti", "trac": "Raggi traenti", "sh": "Navette", "prb": "Sonde",
	"lw": "Motore warp sinistro", "rw": "Motore warp destro", "cw": "Motore warp centrale",
	"imp": "Motore a impulso", "apr": "Reattori ausiliari", "bt": "Batterie",
	"fh": "Scafo prodiero", "ah": "Scafo poppiero", "ch": "Scafo centrale", "cargo": "Stive", "armor": "Corazza",
}
const SYS_ORDER := ["armor", "br", "fl", "em", "aux", "lw", "rw", "cw", "imp", "apr", "bt", "fh", "ah", "ch",
	"lab", "tr", "trac", "sh", "prb", "cargo"]

const WNAMES := {
	"PH1": "Phaser-1", "PH2": "Phaser-2", "PH3": "Phaser-3", "PHOT": "Siluro fotonico", "DISR": "Disgregatore",
	"PLR": "Plasma R", "PLS": "Plasma S", "PLG": "Plasma G", "PLF": "Plasma F", "DRN": "Rampa droni",
}
const WSHORT := {"PH1": "PH-1", "PH2": "PH-2", "PH3": "PH-3", "PHOT": "FOTON", "DISR": "DISR",
	"PLR": "PL-R", "PLS": "PL-S", "PLG": "PL-G", "PLF": "PL-F", "DRN": "DRONI"}

## Archi di tiro: intervalli di rilevamento (gradi in senso orario dalla prua, prua = 0).
const ARCS := {
	"FA": [[-60, 60]], "FX": [[-120, 120]], "FH": [[-90, 90]], "RA": [[120, 240]], "RX": [[60, 300]],
	"RH": [[90, 270]], "LS": [[180, 360]], "RS": [[0, 180]], "LF": [[-60, 0]], "RF": [[0, 60]],
	"L": [[-120, -60]], "R": [[60, 120]], "LP": [[-120, 60]], "RP": [[-60, 120]], "FP": [[-90, 90]], "360": [[0, 360]],
}
const ARC_NAMES := {"FA": "frontale", "FX": "frontale esteso", "FH": "emisfero anteriore", "RA": "posteriore",
	"RX": "posteriore esteso", "RH": "emisfero posteriore", "LS": "lato sinistro", "RS": "lato destro",
	"LF": "avanti a sinistra", "RF": "avanti a destra", "L": "sinistra", "R": "destra",
	"LP": "lanciatore sinistro", "RP": "lanciatore destro", "FP": "lanciatore anteriore", "360": "tutto intorno"}

# --- Tabelle delle armi (Annex #4, Basic Set) ---
## Phaser-1: colonne di distanza 0,1,2,3,4,5,6-8,9-15,16-25,26-50,51-75
const PH1_COLS := [0, 1, 2, 3, 4, 5, 8, 15, 25, 50, 75]
const PH1 := [[9, 8, 7, 6, 5, 5, 4, 3, 2, 1, 1], [8, 7, 6, 5, 5, 4, 3, 2, 1, 1, 0], [7, 5, 5, 4, 4, 4, 3, 1, 0, 0, 0],
	[6, 4, 4, 4, 4, 3, 2, 0, 0, 0, 0], [5, 4, 4, 4, 3, 3, 1, 0, 0, 0, 0], [4, 4, 3, 3, 2, 2, 0, 0, 0, 0, 0]]
const PH2_COLS := [0, 1, 2, 3, 8, 15, 30, 50]
const PH2 := [[6, 5, 5, 4, 3, 2, 1, 1], [6, 5, 4, 4, 2, 1, 1, 0], [6, 4, 4, 4, 1, 1, 0, 0],
	[5, 4, 4, 3, 1, 0, 0, 0], [5, 4, 3, 3, 0, 0, 0, 0], [5, 3, 3, 3, 0, 0, 0, 0]]
const PH3_COLS := [0, 1, 2, 3, 8, 15]
const PH3 := [[4, 4, 4, 3, 1, 1], [4, 4, 4, 2, 1, 0], [4, 4, 4, 1, 0, 0], [4, 4, 3, 0, 0, 0], [4, 3, 2, 0, 0, 0], [3, 3, 1, 0, 0, 0]]
## Siluro fotonico: colonne 0, 1-2, 3-4, 5-8, 9-12, 13-30; numero massimo del dado per colpire
const PHOT_COLS := [0, 2, 4, 8, 12, 30]
const PHOT_HIT := [0, 5, 4, 3, 2, 1]
const PHOT_HIT_OV := [6, 5, 4, 3, 0, 0]
## Disgregatore: colonne 0,1,2,3-4,5-8,9-15,16-22,23-30,31-40
const DISR_COLS := [0, 1, 2, 4, 8, 15, 22, 30, 40]
const DISR_HIT := [0, 5, 5, 4, 4, 4, 3, 2, 2]
const DISR_DMG := [0, 5, 4, 4, 3, 3, 2, 2, 1]
const DISR_HIT_OV := [6, 5, 5, 4, 4, 0, 0, 0, 0]
const DISR_DMG_OV := [10, 10, 8, 8, 6, 0, 0, 0, 0]
## Plasma: forza della testata secondo gli esagoni percorsi
const PL_COLS := [5, 10, 12, 14, 15, 18, 19, 20, 23, 24, 25, 28, 29, 30]
const PL_STR := {
	"R": [50, 50, 35, 35, 35, 25, 25, 25, 20, 20, 20, 10, 5, 1],
	"S": [30, 30, 22, 22, 22, 15, 15, 15, 10, 5, 1, 0, 0, 0],
	"G": [20, 20, 15, 15, 15, 10, 5, 1, 0, 0, 0, 0, 0, 0],
	"F": [20, 15, 10, 5, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0],
}
## Armamento del plasma: energia nei tre turni e costo per tenerlo pronto (FP2.51)
const PL_ARM := {"R": [2, 2, 5], "S": [2, 2, 4], "G": [2, 2, 3], "F": [1, 1, 3]}
const PL_HOLD := {"R": 4, "S": 2, "G": 1, "F": 0}

## Droni (regole dei cadetti, A4.3): velocità 20, 4 punti per distruggerli, 12 di danno, 3 turni di autonomia
const DRONE_SPEED := 20
const DRONE_HP := 4
const DRONE_DMG := 12
const DRONE_END := 3
const DRONES_PER_RACK := 4

## Tabella di assegnazione dei danni (D4.21), righe 2-12, colonne A-M.
const DAC := {
	2: ["br", "fl", "sensor", "dc", "AH", "LW", "tr", "trac", "sh", "lab", "FH", "RW", "ex"],
	3: ["drone", "phaser", "imp", "LW", "RW", "AH", "sh", "dc", "CW", "lab", "bt", "phaser", "ex"],
	4: ["phaser", "tr", "RW", "imp", "FH", "AH", "LW", "apr", "lab", "tr", "prb", "CW", "ex"],
	5: ["RW", "AH", "cargo", "bt", "sh", "torp", "LW", "imp", "RW", "trac", "prb", "weapon", "ex"],
	6: ["FH", "imp", "lab", "LW", "sensor", "trac", "sh", "RW", "phaser", "tr", "bt", "weapon", "ex"],
	7: ["cargo", "FH", "bt", "CW", "sh", "apr", "lab", "phaser", "warp", "prb", "AH", "weapon", "ex"],
	8: ["AH", "apr", "sh", "RW", "scanner", "trac", "lab", "LW", "phaser", "tr", "bt", "weapon", "ex"],
	9: ["LW", "FH", "cargo", "bt", "lab", "drone", "RW", "imp", "LW", "trac", "prb", "weapon", "ex"],
	10: ["phaser", "trac", "LW", "imp", "AH", "FH", "RW", "apr", "lab", "tr", "prb", "CW", "ex"],
	11: ["torp", "phaser", "imp", "RW", "LW", "FH", "trac", "dc", "CW", "lab", "bt", "phaser", "ex"],
	12: ["aux", "em", "scanner", "prb", "FH", "RW", "tr", "sh", "trac", "lab", "AH", "LW", "ex"],
}
## Voci in grassetto della tabella: si possono colpire una sola volta per raffica
const DAC_ONCE := {2: [0, 1, 2, 3], 3: [0, 1], 11: [0, 1], 12: [0, 1, 2, 3]}

## Modi di virata (C3.31): per ogni categoria, [velocità minima, massima] -> modo di virata 1, 2, 3...
const TURN_MODES := {
	"AA": [[0, 8], [9, 16], [17, 24], [25, 99]],
	"A": [[0, 6], [7, 12], [13, 19], [20, 26], [27, 99]],
	"B": [[0, 5], [6, 10], [11, 15], [16, 21], [22, 28], [29, 99]],
	"C": [[0, 4], [5, 9], [10, 14], [15, 20], [21, 27], [28, 99]],
	"D": [[0, 4], [5, 8], [9, 12], [13, 17], [18, 24], [25, 99]],
	"E": [[0, 3], [4, 6], [7, 10], [11, 14], [15, 20], [21, 29], [30, 99]],
}

static var _ships := {}


static func ships() -> Dictionary:
	if _ships.is_empty():
		var f := FileAccess.open("res://data/navi.json", FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		_ships = d["ships"]
	return _ships


static func ship(id: String) -> Dictionary:
	return ships().get(id, {})


static func ship_ids_by_race() -> Dictionary:
	var out := {}
	for r in RACES:
		out[r] = []
	for id in ships():
		out[ships()[id]["r"]].append(id)
	for r in out:
		out[r].sort_custom(func(a, b): return int(ships()[a]["bpv"]) > int(ships()[b]["bpv"]))
	return out


static func turn_mode(cat: String, speed: int) -> int:
	var t: Array = TURN_MODES.get(cat, TURN_MODES["D"])
	for i in t.size():
		if speed <= int(t[i][1]):
			return i + 1
	return t.size()


static func col_index(cols: Array, rng: int) -> int:
	for i in cols.size():
		if rng <= int(cols[i]):
			return i
	return -1


static func is_phaser(t: String) -> bool:
	return t.begins_with("PH") and t != "PHOT"


static func is_plasma(t: String) -> bool:
	return t.begins_with("PL")


static func is_torp(t: String) -> bool:
	return t == "PHOT" or t == "DISR" or is_plasma(t)


static func phaser_cost(t: String) -> float:
	return 0.5 if t == "PH3" else 1.0


## Danno di un phaser dato il tiro del dado (1-6) e la distanza effettiva
static func phaser_damage(t: String, die: int, rng: int) -> int:
	var cols: Array = PH1_COLS
	var tab: Array = PH1
	if t == "PH2":
		cols = PH2_COLS
		tab = PH2
	elif t == "PH3":
		cols = PH3_COLS
		tab = PH3
	var c := col_index(cols, rng)
	if c < 0:
		return 0
	return int(tab[die - 1][c])


static func max_range(t: String, ov := false) -> int:
	match t:
		"PH1": return 75
		"PH2": return 50
		"PH3": return 15
		"PHOT": return 8 if ov else 30
		"DISR": return 8 if ov else 40
	if is_plasma(t):
		return 30
	if t == "DRN":
		return 60
	return 0


static func plasma_strength(ptype: String, dist: int) -> int:
	var c := col_index(PL_COLS, dist)
	if c < 0:
		return 0
	return int(PL_STR[ptype][c])
