extends Node
# Autoload "UITheme": builds the JangDazi look (dark tactical panels, amber accent,
# angular corners, Lilita headings) and applies it to every Control in the game.

const FONT := preload("res://fonts/lilita_one_regular.ttf")
const BG := Color(0.07, 0.08, 0.1, 0.9)
const PANEL := Color(0.11, 0.13, 0.16, 0.92)
const PANEL_LIGHT := Color(0.17, 0.2, 0.24, 1.0)
const BORDER := Color(0.32, 0.36, 0.42, 1.0)
const ACCENT := Color(0.96, 0.66, 0.2, 1.0)
const ACCENT_DARK := Color(0.55, 0.35, 0.08, 1.0)
const TEXT := Color(0.93, 0.93, 0.9, 1.0)
const TEXT_DIM := Color(0.62, 0.65, 0.7, 1.0)


func _ready() -> void:
	get_window().theme = build()


static func flat(bg: Color, border := Color(0, 0, 0, 0), border_w := 0, radius := 3, margin := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = 18

	# Panels
	t.set_stylebox("panel", "PanelContainer", flat(PANEL, BORDER, 1, 3, 16))
	t.set_stylebox("panel", "Panel", flat(PANEL, BORDER, 1, 3, 12))

	# Buttons
	var b := flat(PANEL_LIGHT, BORDER, 1, 2, 10)
	var bh := flat(Color(0.24, 0.28, 0.34), ACCENT, 1, 2, 10)
	var bp := flat(ACCENT, ACCENT, 1, 2, 10)
	var bd := flat(Color(0.12, 0.13, 0.15), BORDER, 1, 2, 10)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, b)
		t.set_stylebox("hover", cls, bh)
		t.set_stylebox("pressed", cls, bp)
		t.set_stylebox("focus", cls, bh)
		t.set_stylebox("disabled", cls, bd)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, ACCENT)
		t.set_color("font_pressed_color", cls, Color(0.1, 0.08, 0.04))
		t.set_color("font_disabled_color", cls, TEXT_DIM)
		t.set_font_size("font_size", cls, 19)

	# Popup menus (dropdowns)
	t.set_stylebox("panel", "PopupMenu", flat(PANEL, ACCENT, 1, 2, 6))
	t.set_stylebox("hover", "PopupMenu", flat(Color(0.24, 0.28, 0.34), Color(0, 0, 0, 0), 0, 2, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", ACCENT)

	# Text fields
	t.set_stylebox("normal", "LineEdit", flat(BG, BORDER, 1, 2, 8))
	t.set_stylebox("focus", "LineEdit", flat(BG, ACCENT, 1, 2, 8))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", ACCENT_DARK)

	# Labels and separators
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("separator", "HSeparator", flat(ACCENT_DARK, Color(0, 0, 0, 0), 0, 0, 1))
	t.set_constant("separation", "HSeparator", 10)

	# Progress bars
	t.set_stylebox("background", "ProgressBar", flat(BG, BORDER, 1, 2, 0))
	t.set_stylebox("fill", "ProgressBar", flat(ACCENT, Color(0, 0, 0, 0), 0, 2, 0))
	return t


# Helpers for code-built UI
static func heading(text: String, size := 28, color := ACCENT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font = FONT
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = int(size / 4)
	ls.outline_color = Color(0, 0, 0, 0.6)
	l.label_settings = ls
	return l


static func caption(text: String, dim := true) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if dim:
		l.modulate = TEXT_DIM
	return l


static func card(title: String) -> Array: # [PanelContainer, VBoxContainer]
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var h := heading(title, 22)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vb.add_child(h)
	vb.add_child(HSeparator.new())
	return [panel, vb]
