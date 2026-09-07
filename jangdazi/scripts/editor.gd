extends Node3D
# In-game map editor: fly camera, piece palette, place/remove, save/load.
# Works on the shared LevelBuilder node so the edited map can be played directly.

signal closed
signal play_requested(map: Dictionary)

const FONT := preload("res://fonts/lilita_one_regular.ttf")
const MOVE_SPEED := 12.0
const LOOK_SENS := 0.0025

var level: LevelBuilder
var active := false
var piece_types: Array = LevelBuilder.PIECES.keys()
var piece_index := 0
var rot_deg := 0.0
var ghost: Node3D
var looking := false
var yaw := 0.0
var pitch := -0.4

var ui: CanvasLayer
var piece_label: Label
var name_edit: LineEdit
var map_select: OptionButton
var status: Label
var info_label: Label

@onready var camera: Camera3D = $Camera


func _ready() -> void:
	_build_ui()
	ui.visible = false


func activate(target_level: LevelBuilder) -> void:
	level = target_level
	active = true
	ui.visible = true
	camera.current = true
	camera.position = Vector3(0, 12, 22)
	yaw = 0.0
	pitch = -0.45
	_apply_look()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	name_edit.text = level.data.get("name", "Untitled")
	_refresh_maps()
	_make_ghost()
	set_status("Editing. Right-drag to look, WASD/QE to fly.")


func deactivate() -> void:
	active = false
	ui.visible = false
	looking = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if ghost:
		ghost.queue_free()
		ghost = null


func set_status(text: String) -> void:
	status.text = text


func _typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit


func _process(delta: float) -> void:
	if not active:
		return
	if not _typing():
		var dir := Vector3.ZERO
		if Input.is_action_pressed("move_forward"): dir.z -= 1
		if Input.is_action_pressed("move_back"): dir.z += 1
		if Input.is_action_pressed("move_left"): dir.x -= 1
		if Input.is_action_pressed("move_right"): dir.x += 1
		if Input.is_key_pressed(KEY_E): dir.y += 1
		if Input.is_key_pressed(KEY_Q): dir.y -= 1
		var speed := MOVE_SPEED * (2.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		var local := camera.basis * Vector3(dir.x, 0, dir.z)
		camera.position += (Vector3(local.x, 0, local.z).normalized() * (1.0 if dir.x != 0 or dir.z != 0 else 0.0) + Vector3(0, dir.y, 0)) * speed * delta
	_update_ghost()
	info_label.text = "%d pieces  ·  %d def spawns  ·  %d att spawns  ·  %d/%d loot spots" % [level.data.pieces.size(), level.spawn_def.size(), level.spawn_att.size(), level.loot_center.size(), level.loot_outer.size()]


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			looking = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not looking:
			_place()
		elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			_remove()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_select_piece(piece_index - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_select_piece(piece_index + 1)
	elif event is InputEventMouseMotion and looking:
		yaw -= event.relative.x * LOOK_SENS
		pitch = clamp(pitch - event.relative.y * LOOK_SENS, -1.5, 1.5)
		_apply_look()
	elif event is InputEventKey and event.pressed and not event.echo and not _typing():
		match event.keycode:
			KEY_R: rot_deg = fmod(rot_deg + (90.0 if event.shift_pressed else 15.0), 360.0)
			KEY_X, KEY_DELETE, KEY_BACKSPACE: _remove()
			KEY_BRACKETLEFT: _select_piece(piece_index - 1)
			KEY_BRACKETRIGHT: _select_piece(piece_index + 1)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				_select_piece(event.keycode - KEY_1)
			KEY_ESCAPE: _close()


func _apply_look() -> void:
	camera.rotation = Vector3(pitch, yaw, 0)


func _select_piece(i: int) -> void:
	piece_index = wrapi(i, 0, piece_types.size())
	piece_label.text = "[%d] %s" % [piece_index + 1, LevelBuilder.PIECES[piece_types[piece_index]].label]
	_make_ghost()


func _make_ghost() -> void:
	if ghost:
		ghost.queue_free()
	var type: String = piece_types[piece_index]
	var info: Dictionary = LevelBuilder.PIECES[type]
	if info.has("scene"):
		ghost = load(info.scene).instantiate()
		for c in ghost.find_children("*", "CollisionShape3D", true, false):
			c.disabled = true
		for m in ghost.find_children("*", "MeshInstance3D", true, false):
			m.transparency = 0.55
	else:
		var size: Vector3 = info.box if info.has("box") else info.size
		var tint: Color = info.get("color", info.get("marker", Color(0.7, 0.7, 0.7)))
		ghost = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		ghost.mesh = box
		ghost.position.y = size.y / 2
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(tint, 0.45)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost.material_override = mat
		var holder := Node3D.new()
		holder.add_child(ghost)
		ghost = holder
	add_child(ghost)


func _cursor_ray() -> Dictionary:
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		# Fall back to the y = 0 plane
		if abs(dir.y) > 0.001:
			var t := -from.y / dir.y
			if t > 0:
				return {"position": from + dir * t, "normal": Vector3.UP, "collider": null}
		return {}
	return hit


func _snapped_position(hit: Dictionary) -> Vector3:
	var p: Vector3 = hit.position + hit.normal * 0.01
	return Vector3(snappedf(p.x, LevelBuilder.GRID), snappedf(p.y, LevelBuilder.GRID), snappedf(p.z, LevelBuilder.GRID))


func _update_ghost() -> void:
	if ghost == null:
		return
	var hit := _cursor_ray()
	ghost.visible = not hit.is_empty() and not looking
	if not hit.is_empty():
		ghost.position = _snapped_position(hit)
		ghost.rotation_degrees.y = rot_deg


func _place() -> void:
	var hit := _cursor_ray()
	if hit.is_empty():
		return
	level.add_piece(piece_types[piece_index], _snapped_position(hit), rot_deg)


func _remove() -> void:
	var hit := _cursor_ray()
	if hit.is_empty() or hit.collider == null:
		return
	var root := level.piece_root_of(hit.collider)
	if root:
		level.remove_piece(root)


# --- UI ---

func _label(text: String, size := 20) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = FONT
	ls.font_size = size
	ls.outline_size = int(size / 3)
	ls.outline_color = Color(0, 0, 0, 0.6)
	l.label_settings = ls
	return l


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 4
	add_child(ui)

	var top := VBoxContainer.new()
	top.position = Vector2(24, 20)
	ui.add_child(top)
	top.add_child(_label("MAP EDITOR", 34))
	piece_label = _label("", 24)
	top.add_child(piece_label)
	info_label = _label("", 18)
	top.add_child(info_label)
	var help := _label("LMB place  ·  X / middle click remove  ·  R rotate (Shift+R 90°)  ·  scroll or [ ] change piece  ·  1-9 pick piece\nRight-drag look  ·  WASD fly  ·  Q/E down/up  ·  Shift fast  ·  Esc back", 16)
	help.modulate = Color(1, 1, 1, 0.75)
	top.add_child(help)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-300, 20)
	panel.custom_minimum_size = Vector2(280, 0)
	ui.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	vb.add_child(_label("Map name", 18))
	name_edit = LineEdit.new()
	name_edit.max_length = 24
	vb.add_child(name_edit)
	var save := Button.new()
	save.text = "Save map"
	save.pressed.connect(_save)
	vb.add_child(save)

	vb.add_child(_label("Load", 18))
	map_select = OptionButton.new()
	vb.add_child(map_select)
	var load_btn := Button.new()
	load_btn.text = "Load selected"
	load_btn.pressed.connect(_load)
	vb.add_child(load_btn)

	var row := HBoxContainer.new()
	vb.add_child(row)
	var new_btn := Button.new()
	new_btn.text = "New (empty)"
	new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_btn.pressed.connect(func():
		level.build({"name": "Untitled", "pieces": [{"t": "ground", "p": [0, -1, 0], "r": 0}, {"t": "zone", "p": [0, 0, 0], "r": 0}, {"t": "spawn_def", "p": [0, 1, 0], "r": 0}, {"t": "spawn_att", "p": [9, 1, 9], "r": 0}]}, true)
		name_edit.text = "Untitled"
		set_status("New map"))
	row.add_child(new_btn)
	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_btn.pressed.connect(func():
		level.build({"name": name_edit.text, "pieces": []}, true)
		set_status("Cleared"))
	row.add_child(clear_btn)

	var play := Button.new()
	play.text = "Host game on this map"
	play.pressed.connect(func():
		if level.spawn_def.is_empty() or level.spawn_att.is_empty():
			set_status("Add a defender spawn and an attacker spawn first")
			return
		level.data.name = LevelBuilder.safe_name(name_edit.text)
		play_requested.emit(level.data.duplicate(true)))
	vb.add_child(play)

	var back := Button.new()
	back.text = "Back to menu"
	back.pressed.connect(_close)
	vb.add_child(back)

	status = _label("", 16)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(250, 0)
	vb.add_child(status)
	_select_piece(0)


func _refresh_maps() -> void:
	map_select.clear()
	map_select.add_item("City (built-in)")
	for m in LevelBuilder.list_maps():
		map_select.add_item(m)


func _save() -> void:
	if level.spawn_def.is_empty() or level.spawn_att.is_empty():
		set_status("Add a defender spawn and an attacker spawn before saving")
		return
	var map_name := LevelBuilder.safe_name(name_edit.text)
	name_edit.text = map_name
	var err := LevelBuilder.save_map(map_name, level.data)
	if err == OK:
		set_status("Saved '%s' to %s" % [map_name, ProjectSettings.globalize_path(LevelBuilder.MAPS_DIR)])
		_refresh_maps()
	else:
		set_status("Save failed: " + error_string(err))


func _load() -> void:
	var map_name := map_select.get_item_text(map_select.selected)
	var map := LevelBuilder.load_map("" if map_select.selected == 0 else map_name)
	level.build(map, true)
	name_edit.text = map.get("name", "Untitled")
	set_status("Loaded '%s'" % map.get("name", "Untitled"))


func _close() -> void:
	closed.emit()
