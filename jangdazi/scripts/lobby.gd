extends CanvasLayer
# Host / join menu shown over the city until a connection is made.

signal host_requested(map_name: String)
signal join_requested(ip: String)
signal editor_requested

const FONT := preload("res://fonts/lilita_one_regular.ttf")

var name_select: OptionButton
var name_edit: LineEdit
var class_select: OptionButton
var class_hint: Label
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
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(500, 0)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "JANGDAZI"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font = FONT
	ls.font_size = 48
	ls.outline_size = 12
	ls.outline_color = Color(0, 0, 0, 0.5)
	title.label_settings = ls
	vb.add_child(title)
	var sub := _caption("Siege the city. Attackers who win become its defenders.")
	sub.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(sub)

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

	vb.add_child(_caption("Operator"))
	class_select = OptionButton.new()
	var idx := 0
	for cls in Game.CLASSES:
		var info: Dictionary = Game.CLASSES[cls]
		class_select.add_item("%s  (%s)" % [cls, Game.TEAM_NAMES[info.team]])
		class_select.set_item_metadata(idx, cls)
		var swatch := GradientTexture2D.new()
		swatch.width = 18
		swatch.height = 18
		var g := Gradient.new()
		g.set_color(0, info.color)
		g.set_color(1, info.color)
		swatch.gradient = g
		class_select.set_item_icon(idx, swatch)
		if cls == Game.local_class:
			class_select.select(idx)
		idx += 1
	class_select.item_selected.connect(func(_i): _remember())
	vb.add_child(class_select)
	class_hint = _caption("Your operator sets your preferred side. The host balances teams if needed.")
	class_hint.modulate = Color(1, 1, 1, 0.6)
	class_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(class_hint)

	vb.add_child(HSeparator.new())

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

	var controls := _caption("WASD move · Space double jump · LMB shoot · RMB fire mode · E / 1-4 weapons · Tab scores · Esc menu")
	controls.modulate = Color(1, 1, 1, 0.6)
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(controls)


func _remember() -> void:
	Game.local_name = name_edit.text.strip_edges()
	Game.local_class = class_select.get_item_metadata(class_select.selected)
	Game.save_settings()


func refresh_maps() -> void:
	var previous := map_select.get_item_text(map_select.selected) if map_select.item_count > 0 else ""
	map_select.clear()
	map_select.add_item("City (built-in)")
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
