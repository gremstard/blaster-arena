extends CanvasLayer
# Host / join menu shown over the city until a connection is made.

signal host_requested(map_name: String)
signal join_requested(ip: String)
signal editor_requested

var name_select: OptionButton
var name_edit: LineEdit
var class_select: OptionButton
var pref_select: OptionButton
var map_select: OptionButton
var ip_edit: LineEdit
var host_button: Button
var join_button: Button
var status_label: Label


func _ready() -> void:
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.05, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(880, 0)
	root.add_theme_constant_override("separation", 14)
	center.add_child(root)

	# Header
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	root.add_child(header)
	header.add_child(UITheme.heading("JANGDAZI", 64))
	var tag := UITheme.caption("CITY SIEGE  ·  DROP IN  ·  LOOT  ·  TAKE THE ZONE", false)
	tag.modulate = UITheme.ACCENT
	header.add_child(tag)
	header.add_child(UITheme.caption("Attackers who win the round become its defenders."))

	# Two cards: operator | deploy
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	root.add_child(row)

	var op := UITheme.card("OPERATOR")
	row.add_child(op[0])
	var ov: VBoxContainer = op[1]
	ov.add_child(_field("Callsign"))
	var name_row := HBoxContainer.new()
	ov.add_child(name_row)
	name_select = OptionButton.new()
	name_select.add_item("Pick...")
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

	ov.add_child(_field("Class"))
	class_select = OptionButton.new()
	var idx := 0
	for cls in Game.CLASSES:
		class_select.add_item("%s  -  %s" % [cls, Game.CLASSES[cls].desc])
		class_select.set_item_metadata(idx, cls)
		if cls == Game.local_class:
			class_select.select(idx)
		idx += 1
	class_select.item_selected.connect(func(_i): _remember())
	ov.add_child(class_select)

	ov.add_child(_field("Side"))
	pref_select = OptionButton.new()
	for i in Game.TEAM_PREFS.size():
		pref_select.add_item(Game.TEAM_PREFS[i])
		if i > 0:
			pref_select.set_item_icon(i, _swatch(Game.TEAM_COLORS[i - 1]))
	pref_select.select(clampi(Game.local_pref, 0, 2))
	pref_select.item_selected.connect(func(_i): _remember())
	ov.add_child(pref_select)
	ov.add_child(UITheme.caption("Both classes fight for either side. Blue defends, red attacks. The host balances teams."))

	var dep := UITheme.card("DEPLOY")
	row.add_child(dep[0])
	var dv: VBoxContainer = dep[1]
	dv.add_child(_field("Map"))
	map_select = OptionButton.new()
	dv.add_child(map_select)
	refresh_maps()
	host_button = Button.new()
	host_button.text = "HOST GAME"
	host_button.pressed.connect(func():
		_remember()
		host_requested.emit(map_select.get_item_text(map_select.selected) if map_select.selected > 0 else ""))
	dv.add_child(host_button)
	dv.add_child(_field("Host IP"))
	ip_edit = LineEdit.new()
	ip_edit.text = Game.last_ip
	ip_edit.placeholder_text = "e.g. 192.168.1.20"
	dv.add_child(ip_edit)
	join_button = Button.new()
	join_button.text = "JOIN GAME"
	join_button.pressed.connect(func():
		_remember()
		join_requested.emit(ip_edit.text.strip_edges()))
	dv.add_child(join_button)
	var editor_button := Button.new()
	editor_button.text = "Map editor"
	editor_button.pressed.connect(func(): editor_requested.emit())
	dv.add_child(editor_button)

	# Footer
	var foot := PanelContainer.new()
	root.add_child(foot)
	var fv := VBoxContainer.new()
	foot.add_child(fv)
	status_label = UITheme.caption("", false)
	status_label.modulate = UITheme.ACCENT
	fv.add_child(status_label)
	fv.add_child(UITheme.caption("Your LAN IP: " + ", ".join(local_ips()) + "   ·   Host shares this, friends paste it.   ·   UDP port %d" % Game.PORT))
	fv.add_child(UITheme.caption("WASD move  ·  Space double jump  ·  LMB shoot  ·  RMB fire mode  ·  E / 1-4 weapons  ·  Tab scores  ·  Esc menu"))


func _field(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.modulate = UITheme.TEXT_DIM
	l.add_theme_font_size_override("font_size", 14)
	return l


static func _swatch(color: Color) -> GradientTexture2D:
	var swatch := GradientTexture2D.new()
	swatch.width = 18
	swatch.height = 18
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, color)
	swatch.gradient = g
	return swatch


func _remember() -> void:
	Game.local_name = name_edit.text.strip_edges()
	Game.local_class = class_select.get_item_metadata(class_select.selected)
	Game.local_pref = pref_select.selected
	Game.save_settings()


func refresh_maps() -> void:
	var previous := map_select.get_item_text(map_select.selected) if map_select.item_count > 0 else ""
	map_select.clear()
	map_select.add_item("City (built-in)")
	for m in LevelBuilder.list_maps():
		map_select.add_item(m)
		if m == previous:
			map_select.select(map_select.item_count - 1)


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
