extends CanvasLayer
# Host / join menu shown over the arena until a connection is made.

signal host_requested(map_name: String)
signal join_requested(ip: String)
signal editor_requested

const FONT := preload("res://fonts/lilita_one_regular.ttf")

var name_select: OptionButton
var name_edit: LineEdit
var color_select: OptionButton
var map_select: OptionButton
var ip_edit: LineEdit
var host_button: Button
var join_button: Button
var status_label: Label


func _ready() -> void:
	_build()


func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "BLASTER ARENA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font = FONT
	ls.font_size = 44
	ls.outline_size = 12
	ls.outline_color = Color(0, 0, 0, 0.5)
	title.label_settings = ls
	vb.add_child(title)

	# Identity
	vb.add_child(_caption("Your name"))
	var name_row := HBoxContainer.new()
	vb.add_child(name_row)
	name_select = OptionButton.new()
	name_select.add_item("Pick a name...")
	for n in Game.PRESET_NAMES:
		name_select.add_item(n)
	name_select.item_selected.connect(func(i):
		if i > 0:
			name_edit.text = name_select.get_item_text(i)
			_remember())
	name_row.add_child(name_select)
	name_edit = LineEdit.new()
	name_edit.text = Game.local_name
	name_edit.max_length = 16
	name_edit.placeholder_text = "or type your own"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(_t): _remember())
	name_row.add_child(name_edit)

	var color_row := HBoxContainer.new()
	vb.add_child(color_row)
	color_row.add_child(_caption("Color"))
	color_select = OptionButton.new()
	color_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var idx := 0
	for c in Game.COLORS:
		color_select.add_item(c)
		var swatch := GradientTexture2D.new()
		swatch.width = 18
		swatch.height = 18
		var g := Gradient.new()
		g.set_color(0, Game.COLORS[c])
		g.set_color(1, Game.COLORS[c])
		swatch.gradient = g
		color_select.set_item_icon(idx, swatch)
		if c == Game.local_color:
			color_select.select(idx)
		idx += 1
	color_select.item_selected.connect(func(_i): _remember())
	color_row.add_child(color_select)

	vb.add_child(HSeparator.new())

	# Host
	var map_row := HBoxContainer.new()
	vb.add_child(map_row)
	map_row.add_child(_caption("Map"))
	map_select = OptionButton.new()
	map_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_row.add_child(map_select)
	refresh_maps()
	host_button = Button.new()
	host_button.text = "Host game"
	host_button.pressed.connect(func():
		_remember()
		host_requested.emit(map_select.get_item_text(map_select.selected) if map_select.selected > 0 else ""))
	vb.add_child(host_button)

	# Join
	vb.add_child(_caption("Host IP"))
	ip_edit = LineEdit.new()
	ip_edit.text = Game.last_ip
	ip_edit.placeholder_text = "e.g. 192.168.1.20"
	vb.add_child(ip_edit)
	join_button = Button.new()
	join_button.text = "Join game"
	join_button.pressed.connect(func():
		_remember()
		join_requested.emit(ip_edit.text.strip_edges()))
	vb.add_child(join_button)

	vb.add_child(HSeparator.new())
	var editor_button := Button.new()
	editor_button.text = "Map editor"
	editor_button.pressed.connect(func(): editor_requested.emit())
	vb.add_child(editor_button)

	status_label = _caption("")
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(status_label)

	var ips := _caption("Your LAN IP: " + ", ".join(local_ips()) + "\nHost shares this; friends paste it above. Port %d." % Game.PORT)
	ips.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(ips)

	var controls := _caption("WASD move · Space double jump · LMB shoot · RMB fire mode · E / 1-3 weapons · Tab scores · Esc free mouse")
	controls.modulate = Color(1, 1, 1, 0.6)
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(controls)


func _remember() -> void:
	Game.local_name = name_edit.text.strip_edges()
	Game.local_color = color_select.get_item_text(color_select.selected)
	Game.save_settings()


func refresh_maps() -> void:
	var previous := map_select.get_item_text(map_select.selected) if map_select.item_count > 0 else ""
	map_select.clear()
	map_select.add_item("Arena (built-in)")
	for m in LevelBuilder.list_maps():
		map_select.add_item(m)
		if m == previous:
			map_select.select(map_select.item_count - 1)


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func local_ips() -> Array[String]:
	var out: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			out.append(ip)
	if out.is_empty():
		out.append("unknown")
	return out


func set_status(text: String) -> void:
	status_label.text = text


func set_busy(busy: bool) -> void:
	host_button.disabled = busy
	join_button.disabled = busy
