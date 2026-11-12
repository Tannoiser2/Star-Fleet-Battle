class_name UI
extends RefCounted
## Helper grafici condivisi. Tema «console di plancia»: fondo nero, cornici a pillola nei colori
## arancio, pesca, lilla e azzurro delle consolle delle astronavi, scritte strette e maiuscole.
## Caratteri liberi (OFL): Antonio per titoli e comandi (lettere alte e strette da consolle),
## Oxanium per i testi lunghi, Share Tech Mono per numeri e coordinate.

const BG := Color("#000000")
const PANEL := Color("#05070d")
const ORANGE := Color("#ff9c00")
const PEACH := Color("#ffcc99")
const LILAC := Color("#cc99cc")
const BLUE := Color("#9999ff")
const SKY := Color("#99ccff")
const TAN := Color("#ffcc66")
const RED := Color("#ff5555")
const RUST := Color("#cc6666")
const GREEN := Color("#88dd88")
const TEXT := Color("#f2ecff")
const MUTED := Color("#8f8aa6")
const DIM := Color("#33304a")

static var font_title: Font
static var font_head: Font
static var font_body: Font
static var font_bold: Font
static var font_mono: Font
static var _tex := {}


static func init_fonts() -> void:
	if font_title != null:
		return
	var ant: FontFile = load("res://assets/fonts/Antonio.ttf")
	var ft := FontVariation.new()
	ft.base_font = ant
	ft.variation_opentype = {"wght": 700}
	font_title = ft
	var fh := FontVariation.new()
	fh.base_font = ant
	fh.variation_opentype = {"wght": 600}
	font_head = fh
	var oxa: FontFile = load("res://assets/fonts/Oxanium.ttf")
	var fb := FontVariation.new()
	fb.base_font = oxa
	fb.variation_opentype = {"wght": 450}
	font_body = fb
	var fbb := FontVariation.new()
	fbb.base_font = oxa
	fbb.variation_opentype = {"wght": 700}
	font_bold = fbb
	font_mono = load("res://assets/fonts/ShareTechMono-Regular.ttf")


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


static func make_theme() -> Theme:
	init_fonts()
	var t := Theme.new()
	t.default_font = font_body
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)
	for cls in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		t.set_font("font", cls, font_head)
		t.set_color("font_color", cls, Color("#120a00"))
		t.set_color("font_hover_color", cls, Color("#000000"))
		t.set_color("font_pressed_color", cls, Color("#000000"))
		t.set_color("font_focus_color", cls, Color("#120a00"))
		t.set_color("font_disabled_color", cls, Color("#55506a"))
	t.set_stylebox("normal", "Button", pill(ORANGE))
	t.set_stylebox("hover", "Button", pill(PEACH))
	t.set_stylebox("pressed", "Button", pill(TAN))
	t.set_stylebox("disabled", "Button", pill(DIM))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("normal", "OptionButton", pill(LILAC))
	t.set_stylebox("hover", "OptionButton", pill(PEACH))
	t.set_stylebox("pressed", "OptionButton", pill(TAN))
	t.set_stylebox("disabled", "OptionButton", pill(DIM))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", PEACH)
	t.set_color("font_pressed_color", "CheckBox", TAN)
	t.set_color("font_hover_pressed_color", "CheckBox", TAN)
	t.set_stylebox("panel", "PanelContainer", frame(ORANGE))
	t.set_stylebox("normal", "LineEdit", box(Color("#0b0a14"), BLUE, 2, 10))
	t.set_stylebox("focus", "LineEdit", box(Color("#0b0a14"), PEACH, 2, 10))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("panel", "PopupMenu", box(Color("#0b0a14"), LILAC, 2, 8))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.BLACK)
	t.set_stylebox("hover", "PopupMenu", box(PEACH, PEACH, 0, 6))
	t.set_font("font", "PopupMenu", font_head)
	t.set_font_size("font_size", "PopupMenu", 22)
	t.set_stylebox("scroll", "VScrollBar", box(Color("#0b0a14"), Color("#0b0a14"), 0, 4))
	t.set_stylebox("grabber", "VScrollBar", box(LILAC, LILAC, 0, 4))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(PEACH, PEACH, 0, 4))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(TAN, TAN, 0, 4))
	t.set_stylebox("scroll", "HScrollBar", box(Color("#0b0a14"), Color("#0b0a14"), 0, 4))
	t.set_stylebox("grabber", "HScrollBar", box(LILAC, LILAC, 0, 4))
	t.set_stylebox("panel", "TooltipPanel", box(Color("#0b0a14"), PEACH, 2, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 18)
	t.set_color("default_color", "RichTextLabel", TEXT)
	return t


static func box(bg: Color, border: Color, bw := 2, radius := 6, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad + 4
	s.content_margin_right = pad + 4
	s.content_margin_top = pad - 2
	s.content_margin_bottom = pad - 2
	s.anti_aliasing = true
	return s


## Pulsante a pillola delle consolle
static func pill(col: Color) -> StyleBoxFlat:
	var s := box(col, col, 0, 24, 8)
	s.content_margin_left = 22
	s.content_margin_right = 22
	return s


## Cornice dei pannelli: bordo colorato spesso a sinistra e in alto, angolo arrotondato
static func frame(col: Color, alpha := 0.93) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(PANEL, alpha)
	s.border_color = col
	s.border_width_left = 14
	s.border_width_top = 6
	s.border_width_bottom = 2
	s.border_width_right = 2
	s.corner_radius_top_left = 26
	s.corner_radius_bottom_left = 26
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_right = 8
	s.content_margin_left = 24
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	s.anti_aliasing = true
	return s


static func label(t: String, size := 20, col := TEXT, font: Font = null) -> Label:
	init_fonts()
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


## Testo a capo con larghezza minima fissa (mai colonne di una lettera)
static func wrap(l: Label, w: float) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = w
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func title(t: String, size := 56, col := ORANGE) -> Label:
	init_fonts()
	return label(t.to_upper(), size, col, font_title)


static func head(t: String, size := 24, col := PEACH) -> Label:
	init_fonts()
	return label(t.to_upper(), size, col, font_head)


static func mono(t: String, size := 18, col := TEXT) -> Label:
	init_fonts()
	return label(t, size, col, font_mono)


static func button(t: String, w := 0, h := 46, size := 22, col := ORANGE) -> Button:
	var b := Button.new()
	b.text = t.to_upper()
	b.custom_minimum_size = Vector2(maxi(w, 60), h)
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	if col != ORANGE:
		tint(b, col)
	return b


## Pulsantino compatto (+ e - dei controlli)
static func small(t: String, col := ORANGE, w := 38, h := 32) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", 20)
	b.focus_mode = Control.FOCUS_NONE
	for k in ["normal", "hover", "pressed", "disabled"]:
		var c: Color = col if k == "normal" else (col.lightened(0.3) if k == "hover" else (TAN if k == "pressed" else DIM))
		var st := box(c, c, 0, 14, 2)
		st.content_margin_left = 4
		st.content_margin_right = 4
		b.add_theme_stylebox_override(k, st)
	return b


static func tint(b: Button, col: Color) -> Button:
	b.add_theme_stylebox_override("normal", pill(col))
	b.add_theme_stylebox_override("hover", pill(col.lightened(0.3)))
	b.add_theme_stylebox_override("pressed", pill(TAN))
	return b


static func primary(b: Button) -> Button:
	return tint(b, TAN)


static func rich(size := 18) -> RichTextLabel:
	init_fonts()
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_override("normal_font", font_body)
	r.add_theme_font_override("bold_font", font_bold)
	r.add_theme_font_override("mono_font", font_mono)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("mono_font_size", size)
	r.add_theme_color_override("default_color", TEXT)
	return r


## Barra orizzontale da consolle (segmenti colorati)
static func bar(cols: Array, h := 10) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	for i in cols.size():
		var c := ColorRect.new()
		c.color = cols[i]
		c.custom_minimum_size = Vector2(30, h)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_stretch_ratio = [3.0, 1.0, 2.0, 0.6, 1.4][i % 5]
		hb.add_child(c)
	return hb


static func panel(col := ORANGE, alpha := 0.93) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", frame(col, alpha))
	return p


## Sfondo stellato animato per i menu (disegnato, nessun carattere speciale)
class Starfield extends Control:
	var stars: Array = []
	var t := 0.0

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var g := RandomNumberGenerator.new()
		g.seed = 1979
		for i in 300:
			stars.append([Vector2(g.randf(), g.randf()), g.randf_range(0.5, 2.2), g.randf_range(0.2, 1.0), g.randf() * 6.28, g.randf_range(0.002, 0.02)])

	func _process(dt: float) -> void:
		t += dt
		queue_redraw()

	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), Color("#000005"))
		for st in stars:
			var p: Vector2 = st[0]
			p.x = fposmod(p.x - t * float(st[4]), 1.0)
			var a: float = st[2] * (0.7 + 0.3 * sin(t * 0.9 + st[3]))
			draw_circle(p * s, st[1], Color(0.9, 0.92, 1.0, a))
