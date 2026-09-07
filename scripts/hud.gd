extends CanvasLayer
# In-match HUD. Built in code; the local Player drives it through the "hud" group.

const FONT := preload("res://fonts/lilita_one_regular.ttf")
const FEED_LIFETIME := 5.0
const EFFECT_NAMES := {Player.Pickup.SPEED: "SPEED", Player.Pickup.DAMAGE: "2x DAMAGE"}
const EFFECT_COLORS := {Player.Pickup.SPEED: Color(0.4, 0.95, 1.0), Player.Pickup.DAMAGE: Color(1.0, 0.45, 0.35)}

var crosshair: TextureRect
var health_label: Label
var health_bar: ProgressBar
var shield_bar: ProgressBar
var weapon_label: Label
var effects_box: VBoxContainer
var feed_box: VBoxContainer
var scoreboard: PanelContainer
var scoreboard_box: VBoxContainer
var death_panel: CenterContainer
var death_label: Label
var banner: Label
var announcer: Label
var timer_label: Label
var leave_button: Button
var map_box: HBoxContainer
var map_select: OptionButton
var vignette: ColorRect
var pickup_toast: Label

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
	Game.match_ended.connect(_on_match_ended)
	Game.match_reset.connect(_on_match_reset)
	Game.announce.connect(announce_text)


func _process(_delta: float) -> void:
	scoreboard.visible = Input.is_action_pressed("scoreboard") or Game.match_over
	leave_button.visible = Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	map_box.visible = leave_button.visible and multiplayer.is_server()
	var s := Game.seconds_left()
	timer_label.text = "%d:%02d" % [s / 60, s % 60]
	timer_label.modulate = Color(1, 0.4, 0.4) if s <= 30 and not Game.match_over else Color.WHITE
	_refresh_effects()


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


func _bar(color: Color, max_value: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = max_value
	bar.value = max_value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(260, 18)
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
	health_bar = _bar(Color(0.4, 0.9, 0.45), Player.MAX_HEALTH)
	hp_box.add_child(health_bar)
	shield_bar = _bar(Color(0.4, 0.75, 1.0), Player.MAX_OVERSHIELD - Player.MAX_HEALTH)
	shield_bar.custom_minimum_size = Vector2(260, 8)
	shield_bar.value = 0
	hp_box.add_child(shield_bar)

	# Bottom-right: weapon
	weapon_label = _label("", 30)
	weapon_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	weapon_label.position = Vector2(-372, -80)
	weapon_label.custom_minimum_size = Vector2(340, 0)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(weapon_label)

	# Left: active effects
	effects_box = VBoxContainer.new()
	effects_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	effects_box.position = Vector2(32, 40)
	add_child(effects_box)

	# Top-right: feed
	feed_box = VBoxContainer.new()
	feed_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	feed_box.position = Vector2(-340, 24)
	feed_box.custom_minimum_size = Vector2(320, 0)
	add_child(feed_box)

	# Top-center: timer, banner, announcer
	timer_label = _label("5:00", 30)
	timer_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	timer_label.position = Vector2(-100, 16)
	timer_label.custom_minimum_size = Vector2(200, 0)
	add_child(timer_label)

	banner = _label("", 48)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.position = Vector2(-400, 60)
	banner.custom_minimum_size = Vector2(800, 0)
	banner.visible = false
	add_child(banner)

	announcer = _label("", 34)
	announcer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	announcer.position = Vector2(-400, 120)
	announcer.custom_minimum_size = Vector2(800, 0)
	announcer.modulate.a = 0
	add_child(announcer)

	pickup_toast = _label("", 28)
	pickup_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pickup_toast.position = Vector2(-300, 60)
	pickup_toast.custom_minimum_size = Vector2(600, 0)
	pickup_toast.modulate.a = 0
	add_child(pickup_toast)

	death_panel = CenterContainer.new()
	death_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	death_panel.add_child(vb)
	death_label = _label("", 40)
	vb.add_child(death_label)
	vb.add_child(_label("Respawning...", 28))
	death_panel.visible = false
	add_child(death_panel)

	scoreboard = PanelContainer.new()
	scoreboard.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	scoreboard.custom_minimum_size = Vector2(460, 0)
	scoreboard.position = Vector2(-230, -160)
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
	map_select.add_item("Arena (built-in)")
	for m in LevelBuilder.list_maps():
		map_select.add_item(m)
	for c in feed_box.get_children():
		c.queue_free()
	hide_death()
	banner.visible = false
	crosshair.modulate = Color.WHITE
	vignette.color.a = 0
	set_health(Player.MAX_HEALTH)
	set_effects({})


func set_health(value: int) -> void:
	health_label.text = str(value)
	health_bar.value = min(value, Player.MAX_HEALTH)
	shield_bar.value = max(0, value - Player.MAX_HEALTH)
	var fill: StyleBoxFlat = health_bar.get_theme_stylebox("fill")
	fill.bg_color = Color(0.4, 0.9, 0.45) if value > 35 else Color(1, 0.35, 0.3)


func set_crosshair(texture: Texture2D) -> void:
	crosshair.texture = texture


func set_weapon(weapon_name: String, mode: String) -> void:
	weapon_label.text = "%s  ·  %s" % [weapon_name.to_upper(), mode]


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


func pickup_flash(type: Player.Pickup) -> void:
	var names := {Player.Pickup.HEALTH: "+50 HEALTH", Player.Pickup.SHIELD: "OVERSHIELD", Player.Pickup.SPEED: "SPEED BOOST", Player.Pickup.DAMAGE: "DOUBLE DAMAGE"}
	pickup_toast.text = names.get(type, "")
	if _toast_tween:
		_toast_tween.kill()
	pickup_toast.modulate.a = 1
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.0)
	_toast_tween.tween_property(pickup_toast, "modulate:a", 0.0, 0.5)


func announce_text(text: String) -> void:
	announcer.text = text
	if _announce_tween:
		_announce_tween.kill()
	announcer.modulate.a = 1
	_announce_tween = create_tween()
	_announce_tween.tween_interval(2.5)
	_announce_tween.tween_property(announcer, "modulate:a", 0.0, 0.6)


func show_death(killer_name: String, environmental: bool) -> void:
	death_label.text = "You fell" if environmental else "Killed by " + killer_name
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
	var header := HBoxContainer.new()
	scoreboard_box.add_child(header)
	_add_row(header, ["Player", "Kills", "Deaths", "Streak"], 24, Color.WHITE)
	for id in Game.sorted_ids():
		var p: Dictionary = Game.players[id]
		var row := HBoxContainer.new()
		scoreboard_box.add_child(row)
		_add_row(row, [p.name, str(p.kills), str(p.deaths), str(p.get("streak", 0))], 22, Game.color_of(id))
		if id == multiplayer.get_unique_id():
			row.modulate = Color(1, 0.95, 0.7)


func _add_row(row: HBoxContainer, cells: Array, size: int, first_color: Color) -> void:
	for i in cells.size():
		var l := _label(cells[i], size)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_CENTER
		if i == 0:
			l.modulate = first_color
		row.add_child(l)


func _on_match_ended(winner_id: int) -> void:
	banner.text = "%s wins!" % Game.name_of(winner_id)
	banner.visible = true


func _on_match_reset() -> void:
	banner.visible = false
	_refresh_scoreboard()
