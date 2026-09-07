extends CanvasLayer
# In-match HUD. Built in code; the local Player drives it through the "hud" group.

const FONT := preload("res://fonts/lilita_one_regular.ttf")
const FEED_LIFETIME := 5.0
const EFFECT_NAMES := {Player.Pickup.SPEED: "SPEED", Player.Pickup.DAMAGE: "DAMAGE UP"}
const EFFECT_COLORS := {Player.Pickup.SPEED: Color(0.4, 0.95, 1.0), Player.Pickup.DAMAGE: Color(1.0, 0.45, 0.35)}

var crosshair: TextureRect
var health_label: Label
var health_bar: ProgressBar
var shield_bar: ProgressBar
var weapon_label: Label
var inventory_label: Label
var effects_box: VBoxContainer
var feed_box: VBoxContainer
var scoreboard: PanelContainer
var scoreboard_box: VBoxContainer
var death_panel: CenterContainer
var death_label: Label
var death_sub: Label
var banner: Label
var announcer: Label
var phase_label: Label
var timer_label: Label
var team_label: Label
var alive_label: Label
var capture_box: VBoxContainer
var capture_bar: ProgressBar
var capture_label: Label
var ring_warning: Label
var drop_label: Label
var leave_button: Button
var start_button: Button
var map_box: HBoxContainer
var map_select: OptionButton
var vignette: ColorRect
var pickup_label: Label

var _hit_tween: Tween
var _vignette_tween: Tween
var _announce_tween: Tween
var _toast_tween: Tween
var _effects := {}


func _ready() -> void:
	add_to_group("hud")
	_build()
	Game.kill_feed.connect(add_feed)
	Game.players_changed.connect(_refresh_scoreboard)
	Game.players_changed.connect(_refresh_team)
	Game.phase_changed.connect(_on_phase_changed)
	Game.round_ended.connect(_on_round_ended)
	Game.match_ended.connect(_on_match_ended)
	Game.announce.connect(announce_text)


func _process(_delta: float) -> void:
	var over := Game.phase == Game.Phase.ROUND_END or Game.phase == Game.Phase.MATCH_END
	scoreboard.visible = Input.is_action_pressed("scoreboard") or over
	var menu := Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	leave_button.visible = menu
	map_box.visible = menu and multiplayer.is_server() and Game.phase == Game.Phase.LOBBY
	start_button.visible = multiplayer.is_server() and Game.phase == Game.Phase.LOBBY
	var s := Game.seconds_left()
	phase_label.text = Game.PHASE_NAMES[Game.phase] + ("" if Game.round_number == 0 else "  ·  Round %d" % Game.round_number)
	timer_label.text = "%d:%02d" % [s / 60, s % 60] if Game.phase != Game.Phase.LOBBY else "waiting for host to start"
	timer_label.modulate = Color(1, 0.4, 0.4) if s <= 30 and Game.phase == Game.Phase.SIEGE else Color.WHITE
	alive_label.text = "DEF %d alive   ·   ATT %d alive" % [Game.alive_count(0), Game.alive_count(1)]
	alive_label.visible = Game.phase != Game.Phase.LOBBY
	capture_box.visible = Game.phase == Game.Phase.SIEGE
	capture_bar.value = Game.capture
	capture_label.text = "ATTACKERS CAPTURING  %d%%" % int(Game.capture * 100) if Game.capture > 0 else "CONTROL ZONE"
	_update_ring_warning()
	_refresh_effects()


func _update_ring_warning() -> void:
	var me: Player = null
	var root := get_tree().current_scene
	if root and root.has_node("Players/" + str(multiplayer.get_unique_id())):
		me = root.get_node("Players/" + str(multiplayer.get_unique_id()))
	var outside := false
	if me and not me.dead and Game.phase == Game.Phase.SIEGE:
		var zc: Vector3 = root.level.zone_center
		outside = Vector2(me.position.x - zc.x, me.position.z - zc.z).length() > Game.ring_radius()
	ring_warning.visible = outside
	if outside:
		ring_warning.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 150.0)


func _settings(size: int) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = FONT
	ls.font_size = size
	ls.outline_size = int(size / 3)
	ls.outline_color = Color(0, 0, 0, 0.5)
	return ls


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = _settings(size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _bar(color: Color, max_value: float, height := 18.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = max_value
	bar.value = max_value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(260, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _build() -> void:
	vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(1, 0, 0, 0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	crosshair = TextureRect.new()
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crosshair)

	# Bottom-left: health
	var hp_box := VBoxContainer.new()
	hp_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hp_box.position = Vector2(32, -120)
	add_child(hp_box)
	health_label = _label("100", 36)
	health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hp_box.add_child(health_label)
	health_bar = _bar(Color(0.4, 0.9, 0.45), Player.BASE_HEALTH)
	hp_box.add_child(health_bar)
	shield_bar = _bar(Color(0.4, 0.75, 1.0), Player.OVERSHIELD, 8)
	shield_bar.value = 0
	hp_box.add_child(shield_bar)

	# Bottom-right: weapon + inventory
	var wbox := VBoxContainer.new()
	wbox.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	wbox.position = Vector2(-372, -110)
	wbox.custom_minimum_size = Vector2(340, 0)
	add_child(wbox)
	weapon_label = _label("", 30)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wbox.add_child(weapon_label)
	inventory_label = _label("", 18)
	inventory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inventory_label.modulate = Color(1, 1, 1, 0.8)
	wbox.add_child(inventory_label)

	effects_box = VBoxContainer.new()
	effects_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	effects_box.position = Vector2(32, 40)
	add_child(effects_box)

	feed_box = VBoxContainer.new()
	feed_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	feed_box.position = Vector2(-340, 24)
	feed_box.custom_minimum_size = Vector2(320, 0)
	add_child(feed_box)

	# Top-center: phase, timer, alive, capture
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-260, 12)
	top.custom_minimum_size = Vector2(520, 0)
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(top)
	phase_label = _label("", 24)
	top.add_child(phase_label)
	timer_label = _label("", 34)
	top.add_child(timer_label)
	alive_label = _label("", 20)
	top.add_child(alive_label)
	capture_box = VBoxContainer.new()
	capture_box.visible = false
	top.add_child(capture_box)
	capture_label = _label("CONTROL ZONE", 18)
	capture_label.modulate = Color(1, 0.9, 0.3)
	capture_box.add_child(capture_label)
	capture_bar = _bar(Color(1.0, 0.45, 0.3), 1.0, 12)
	capture_bar.custom_minimum_size = Vector2(520, 12)
	capture_bar.value = 0
	capture_box.add_child(capture_bar)

	team_label = _label("", 22)
	team_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	team_label.position = Vector2(24, 100)
	team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(team_label)

	banner = _label("", 48)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner.position = Vector2(-500, -160)
	banner.custom_minimum_size = Vector2(1000, 0)
	banner.visible = false
	add_child(banner)

	announcer = _label("", 30)
	announcer.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	announcer.position = Vector2(-500, -110)
	announcer.custom_minimum_size = Vector2(1000, 0)
	announcer.modulate.a = 0
	add_child(announcer)

	ring_warning = _label("OUTSIDE THE RING  ·  MOVE TO THE CENTER", 26)
	ring_warning.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ring_warning.position = Vector2(-400, 80)
	ring_warning.custom_minimum_size = Vector2(800, 0)
	ring_warning.modulate = Color(1, 0.4, 0.3)
	ring_warning.visible = false
	add_child(ring_warning)

	drop_label = _label("DROPPING IN  ·  steer with WASD", 24)
	drop_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	drop_label.position = Vector2(-300, 120)
	drop_label.custom_minimum_size = Vector2(600, 0)
	drop_label.visible = false
	add_child(drop_label)

	pickup_label = _label("", 28)
	pickup_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pickup_label.position = Vector2(-300, 60)
	pickup_label.custom_minimum_size = Vector2(600, 0)
	pickup_label.modulate.a = 0
	add_child(pickup_label)

	death_panel = CenterContainer.new()
	death_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	death_panel.add_child(vb)
	death_label = _label("", 40)
	vb.add_child(death_label)
	death_sub = _label("", 24)
	vb.add_child(death_sub)
	death_panel.visible = false
	add_child(death_panel)

	scoreboard = PanelContainer.new()
	scoreboard.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	scoreboard.custom_minimum_size = Vector2(520, 0)
	scoreboard.position = Vector2(-260, -60)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(16)
	scoreboard.add_theme_stylebox_override("panel", style)
	scoreboard_box = VBoxContainer.new()
	scoreboard.add_child(scoreboard_box)
	scoreboard.visible = false
	add_child(scoreboard)

	leave_button = Button.new()
	leave_button.text = "Leave match"
	leave_button.position = Vector2(24, 24)
	leave_button.visible = false
	leave_button.pressed.connect(func(): get_tree().current_scene.leave_match())
	add_child(leave_button)

	start_button = Button.new()
	start_button.text = "START MATCH"
	start_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	start_button.position = Vector2(-90, -170)
	start_button.custom_minimum_size = Vector2(180, 44)
	start_button.visible = false
	start_button.pressed.connect(func(): get_tree().current_scene.start_match())
	add_child(start_button)

	map_box = HBoxContainer.new()
	map_box.position = Vector2(24, 64)
	map_box.visible = false
	add_child(map_box)
	map_select = OptionButton.new()
	map_select.custom_minimum_size = Vector2(200, 0)
	map_box.add_child(map_select)
	var change := Button.new()
	change.text = "Change map"
	change.pressed.connect(func():
		var chosen := map_select.get_item_text(map_select.selected) if map_select.selected > 0 else ""
		get_tree().current_scene.change_map(chosen))
	map_box.add_child(change)


func reset() -> void:
	map_select.clear()
	map_select.add_item("City (built-in)")
	for m in LevelBuilder.list_maps():
		map_select.add_item(m)
	for c in feed_box.get_children():
		c.queue_free()
	hide_death()
	banner.visible = false
	crosshair.modulate = Color.WHITE
	vignette.color.a = 0
	set_health(Player.BASE_HEALTH, Player.BASE_HEALTH)
	set_effects({})
	set_dropping(false)
	_refresh_team()


func set_health(value: int, max_value: int = Player.BASE_HEALTH) -> void:
	health_label.text = str(value)
	health_bar.max_value = max_value
	health_bar.value = min(value, max_value)
	shield_bar.value = max(0, value - max_value)
	var fill: StyleBoxFlat = health_bar.get_theme_stylebox("fill")
	fill.bg_color = Color(0.4, 0.9, 0.45) if value > 35 else Color(1, 0.35, 0.3)


func set_crosshair(texture: Texture2D) -> void:
	crosshair.texture = texture


func set_weapon(weapon_name: String, mode: String) -> void:
	weapon_label.text = "%s  ·  %s" % [weapon_name.to_upper(), mode]


func set_inventory(owned: Array, current: int, weapons: Array) -> void:
	var parts := []
	for n in owned.size():
		var i: int = owned[n]
		parts.append(("[%d] %s" if i == current else "%d %s") % [n + 1, weapons[i].display_name])
	inventory_label.text = "   ".join(parts)


func set_dropping(value: bool) -> void:
	drop_label.visible = value


func set_effects(effects: Dictionary) -> void:
	_effects = effects
	_refresh_effects()


func _refresh_effects() -> void:
	var now := Time.get_ticks_msec()
	var wanted := []
	for type in _effects:
		if _effects[type] > now and EFFECT_NAMES.has(type):
			wanted.append(type)
	while effects_box.get_child_count() > wanted.size():
		var c := effects_box.get_child(effects_box.get_child_count() - 1)
		effects_box.remove_child(c)
		c.queue_free()
	while effects_box.get_child_count() < wanted.size():
		var l := _label("", 24)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		effects_box.add_child(l)
	for i in wanted.size():
		var type = wanted[i]
		var l: Label = effects_box.get_child(i)
		l.text = "%s  %ds" % [EFFECT_NAMES[type], ceili((_effects[type] - now) / 1000.0)]
		l.modulate = EFFECT_COLORS[type]


func _refresh_team() -> void:
	if not Game.is_online():
		return
	var t := Game.local_team()
	team_label.text = "%s  ·  %s" % [Game.TEAM_NAMES[t].to_upper(), Game.class_of(multiplayer.get_unique_id())]
	team_label.modulate = Game.TEAM_COLORS[t]


func hit_marker() -> void:
	if _hit_tween:
		_hit_tween.kill()
	crosshair.modulate = Color(1, 0.3, 0.3)
	crosshair.scale = Vector2(1.3, 1.3)
	_hit_tween = create_tween().set_parallel(true)
	_hit_tween.tween_property(crosshair, "modulate", Color.WHITE, 0.15)
	_hit_tween.tween_property(crosshair, "scale", Vector2.ONE, 0.15)


func damage_flash() -> void:
	if _vignette_tween:
		_vignette_tween.kill()
	vignette.color.a = 0.35
	_vignette_tween = create_tween()
	_vignette_tween.tween_property(vignette, "color:a", 0.0, 0.4)


func pickup_toast(text: String) -> void:
	pickup_label.text = text
	if _toast_tween:
		_toast_tween.kill()
	pickup_label.modulate.a = 1
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.2)
	_toast_tween.tween_property(pickup_label, "modulate:a", 0.0, 0.5)


func pickup_flash(type: Player.Pickup) -> void:
	var names := {Player.Pickup.HEALTH: "+50 HEALTH", Player.Pickup.SHIELD: "OVERSHIELD", Player.Pickup.SPEED: "SPEED BOOST", Player.Pickup.DAMAGE: "DAMAGE UP"}
	pickup_toast(names.get(type, ""))


func announce_text(text: String) -> void:
	announcer.text = text
	if _announce_tween:
		_announce_tween.kill()
	announcer.modulate.a = 1
	_announce_tween = create_tween()
	_announce_tween.tween_interval(3.0)
	_announce_tween.tween_property(announcer, "modulate:a", 0.0, 0.6)


func show_death(killer_name: String, environmental: bool, sub := "") -> void:
	death_label.text = "You died" if environmental else "Killed by " + killer_name
	if sub.is_empty():
		sub = "Respawning..." if Game.phase == Game.Phase.LOBBY else "Spectating until the round ends"
	death_sub.text = sub
	death_panel.visible = true
	crosshair.visible = false


func hide_death() -> void:
	death_panel.visible = false
	crosshair.visible = true


func add_feed(text: String) -> void:
	print("[feed] ", text)
	var l := _label(text, 22)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	feed_box.add_child(l)
	var tw := create_tween()
	tw.tween_interval(FEED_LIFETIME)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


func _refresh_scoreboard() -> void:
	for c in scoreboard_box.get_children():
		c.queue_free()
	var title := _label("Defenders %d  -  %d Attackers" % [Game.wins[0], Game.wins[1]], 26)
	scoreboard_box.add_child(title)
	var header := HBoxContainer.new()
	scoreboard_box.add_child(header)
	_add_row(header, ["Player", "Operator", "Team", "K", "D"], 22, Color.WHITE)
	for id in Game.sorted_ids():
		var p: Dictionary = Game.players[id]
		var row := HBoxContainer.new()
		scoreboard_box.add_child(row)
		var alive := "" if p.alive else " (dead)"
		_add_row(row, [p.name + alive, p.cls, Game.TEAM_NAMES[p.team], str(p.kills), str(p.deaths)], 20, Game.TEAM_COLORS[p.team])
		if id == multiplayer.get_unique_id():
			row.modulate = Color(1, 0.95, 0.7)


func _add_row(row: HBoxContainer, cells: Array, size: int, first_color: Color) -> void:
	for i in cells.size():
		var l := _label(cells[i], size)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_stretch_ratio = 2.0 if i < 2 else 1.0
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i < 2 else HORIZONTAL_ALIGNMENT_CENTER
		if i == 0:
			l.modulate = first_color
		row.add_child(l)


func _on_phase_changed(phase: int) -> void:
	match phase:
		Game.Phase.SETUP:
			banner.visible = false
			var t := Game.local_team()
			announce_text("You are %s. %s" % [Game.TEAM_NAMES[t].to_upper(), "Loot up and hold the zone." if t == 0 else "Loot up, then take the zone."])
		Game.Phase.LOBBY:
			banner.visible = false
			hide_death()
	_refresh_scoreboard()


func _on_round_ended(winner: int) -> void:
	banner.text = "%s win the round" % Game.TEAM_NAMES[winner]
	banner.modulate = Game.TEAM_COLORS[winner]
	banner.visible = true


func _on_match_ended(winner: int) -> void:
	banner.text = "%s WIN THE MATCH" % Game.TEAM_NAMES[winner].to_upper()
	banner.modulate = Game.TEAM_COLORS[winner]
	banner.visible = true
