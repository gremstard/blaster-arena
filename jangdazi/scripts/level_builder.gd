extends Node3D
class_name LevelBuilder
# Builds a level from map data (a Dictionary, saved as JSON). Used by the game
# on every peer and by the map editor. Piece node names are deterministic so
# RPC paths match across peers.

const MAPS_DIR := "user://maps"
const DEFAULT_MAP := "res://maps/city.json"
const GRID := 0.5

const PIECES := {
	"city": {"label": "City (FBX)", "asset": "res://assets/City Map/City.fbx", "size": Vector3(400, 100, 400)},
	"building_small": {"label": "Building small", "box": Vector3(6, 6, 6), "color": Color(0.62, 0.6, 0.58)},
	"building_mid": {"label": "Building mid", "box": Vector3(8, 10, 8), "color": Color(0.55, 0.57, 0.6)},
	"building_tall": {"label": "Building tall", "box": Vector3(8, 16, 8), "color": Color(0.45, 0.47, 0.52)},
	"building_wide": {"label": "Building wide", "box": Vector3(12, 5, 8), "color": Color(0.66, 0.6, 0.52)},
	"block": {"label": "Block 2m", "box": Vector3(2, 2, 2), "color": Color(0.5, 0.5, 0.5)},
	"ground": {"label": "Ground 20x20", "box": Vector3(20, 1, 20), "color": Color(0.22, 0.22, 0.24)},
	"platform_large": {"label": "Grass platform 5x5", "scene": "res://objects/platform_large_grass.tscn", "size": Vector3(5.2, 0.5, 5.2)},
	"platform": {"label": "Platform 2x2", "scene": "res://objects/platform.tscn", "size": Vector3(2.2, 0.5, 2.2)},
	"wall_low": {"label": "Low wall", "scene": "res://objects/wall_low.tscn", "size": Vector3(2.2, 0.8, 0.7)},
	"wall_high": {"label": "High wall", "scene": "res://objects/wall_high.tscn", "size": Vector3(1.5, 1.7, 0.7)},
	"zone": {"label": "Control zone", "size": Vector3(14, 3, 14), "marker": Color(1, 0.9, 0.3)},
	"spawn_def": {"label": "Defender spawn", "size": Vector3(1, 2, 1), "marker": Color(0.35, 0.6, 1.0)},
	"spawn_att": {"label": "Attacker spawn", "size": Vector3(1, 2, 1), "marker": Color(1.0, 0.45, 0.3)},
	"loot_center": {"label": "Loot spot (center)", "size": Vector3(1, 1, 1), "marker": Color(1, 0.85, 0.2)},
	"loot_outer": {"label": "Loot spot (outer)", "size": Vector3(1, 1, 1), "marker": Color(0.9, 0.6, 0.9)},
}

var data := {"name": "Untitled", "pieces": []}
var spawn_def: Array[Vector3] = []
var spawn_att: Array[Vector3] = []
var loot_center: Array[Vector3] = []
var loot_outer: Array[Vector3] = []
var zone_center := Vector3.ZERO
var zone_radius := 7.0
var map_radius := 60.0
var min_y := 0.0
var editor_mode := false
var _counter := 0
var _scene_cache := {}
var _materials := {}


func build(map: Dictionary, in_editor := false) -> void:
	clear()
	editor_mode = in_editor
	data = {"name": map.get("name", "Untitled"), "pieces": []}
	for piece in map.get("pieces", []):
		if PIECES.has(piece.get("t", "")):
			_instance(piece)
	_recompute()
	print("[map] built '%s' (%d pieces, %d def / %d att spawns)" % [data.name, data.pieces.size(), spawn_def.size(), spawn_att.size()])


func clear() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	data = {"name": data.get("name", "Untitled"), "pieces": []}
	_counter = 0


func add_piece(type: String, pos: Vector3, rot_deg: float) -> Node3D:
	var node := _instance({"t": type, "p": [pos.x, pos.y, pos.z], "r": rot_deg})
	_recompute()
	return node


func remove_piece(node: Node3D) -> void:
	if node.has_meta("piece"):
		data.pieces.erase(node.get_meta("piece"))
	remove_child(node)
	node.queue_free()
	_recompute()


func piece_root_of(node: Node) -> Node3D:
	var n := node
	while n and n.get_parent() != self:
		n = n.get_parent()
	return n as Node3D


func _instance(src: Dictionary) -> Node3D:
	var type: String = src.t
	var info: Dictionary = PIECES[type]
	var pos := _to_vec(src.get("p", [0, 0, 0]))
	var piece := {"t": type, "p": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)], "r": float(src.get("r", 0))}
	if src.has("s"):
		piece["s"] = src.s
	if src.has("c"):
		piece["c"] = src.c
	data.pieces.append(piece)

	var node: Node3D
	if info.has("asset"):
		node = _asset_piece(type, info)
	elif info.has("scene"):
		if not _scene_cache.has(type):
			_scene_cache[type] = load(info.scene)
		node = _scene_cache[type].instantiate()
	elif info.has("box"):
		var size: Vector3 = _to_vec(piece.s) if piece.has("s") else info.box
		var color: Color = Color.html(piece.c) if piece.has("c") else info.color
		node = _box(size, color)
	else:
		node = Node3D.new()
		if type == "zone":
			node.add_child(_zone_visual())
		if editor_mode:
			node.add_child(_marker(info))
			node.add_child(_editor_collider(info.size))
	_counter += 1
	node.name = "%s_%d" % [type, _counter]
	node.set_meta("piece", piece)
	node.set_meta("type", type)
	add_child(node)
	node.position = pos
	node.rotation_degrees.y = piece.r
	return node


# Big imported model: instanced with trimesh collision and re-centered on its footprint
func _asset_piece(type: String, info: Dictionary) -> Node3D:
	var holder := Node3D.new()
	if not ResourceLoader.exists(info.asset):
		push_warning("Asset missing: " + info.asset)
		return holder
	if not _scene_cache.has(type):
		_scene_cache[type] = load(info.asset)
	var model: Node3D = _scene_cache[type].instantiate()
	holder.add_child(model)
	var aabb := AABB()
	var first := true
	for m in model.find_children("*", "MeshInstance3D"):
		m.create_trimesh_collision()
		var a: AABB = m.transform * m.get_aabb()
		var p := m.get_parent()
		while p and p != model:
			a = p.transform * a
			p = p.get_parent()
		aabb = a if first else aabb.merge(a)
		first = false
	if not first:
		var c := aabb.get_center()
		model.position = Vector3(-c.x, -aabb.position.y, -c.z)
	return holder


func _box(size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	shape.position.y = size.y / 2
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position.y = size.y / 2
	var key := color.to_html()
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.9
		_materials[key] = mat
	mesh.material_override = _materials[key]
	body.add_child(mesh)
	return body


func _zone_visual() -> Node3D:
	var holder := Node3D.new()
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 7.0
	cyl.bottom_radius = 7.0
	cyl.height = 0.15
	ring.mesh = cyl
	ring.position.y = 0.08
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.9, 0.3, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(ring)
	var label := Label3D.new()
	label.text = "CONTROL ZONE"
	label.position.y = 4.0
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.01
	label.font_size = 64
	label.outline_size = 16
	label.modulate = Color(1, 0.9, 0.3)
	holder.add_child(label)
	return holder


static func _marker(info: Dictionary) -> Node3D:
	var holder := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(min(info.size.x, 2), min(info.size.y, 2), min(info.size.z, 2))
	mesh.mesh = box
	mesh.position.y = box.size.y / 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(info.marker, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	holder.add_child(mesh)
	var label := Label3D.new()
	label.text = info.label.to_upper()
	label.position.y = box.size.y + 0.6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.005
	label.font_size = 48
	label.outline_size = 12
	label.modulate = info.marker
	holder.add_child(label)
	return holder


static func _editor_collider(size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y / 2
	body.add_child(shape)
	return body


func _recompute() -> void:
	spawn_def.clear()
	spawn_att.clear()
	loot_center.clear()
	loot_outer.clear()
	min_y = INF
	map_radius = 20.0
	var found_zone := false
	for piece in data.pieces:
		var p := _to_vec(piece.p)
		min_y = min(min_y, p.y)
		map_radius = max(map_radius, Vector2(p.x, p.z).length())
		match piece.t:
			"spawn_def": spawn_def.append(p)
			"spawn_att": spawn_att.append(p)
			"loot_center": loot_center.append(p)
			"loot_outer": loot_outer.append(p)
			"zone":
				zone_center = p
				found_zone = true
	if not found_zone:
		zone_center = Vector3.ZERO
	if min_y == INF:
		min_y = 0.0
	Game.fall_y = min_y - 15.0


static func _to_vec(arr) -> Vector3:
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


# --- Files ---

static func default_map() -> Dictionary:
	return parse(FileAccess.get_file_as_string(DEFAULT_MAP))


static func parse(text: String) -> Dictionary:
	var result = JSON.parse_string(text)
	if result is Dictionary and result.has("pieces"):
		return result
	return {"name": "Untitled", "pieces": []}


static func list_maps() -> Array[String]:
	var out: Array[String] = []
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)
	var dir := DirAccess.open(MAPS_DIR)
	if dir:
		for f in dir.get_files():
			if f.ends_with(".json"):
				out.append(f.trim_suffix(".json"))
	out.sort()
	return out


static func load_map(map_name: String) -> Dictionary:
	if map_name.is_empty() or map_name == "City":
		return default_map()
	var path := "%s/%s.json" % [MAPS_DIR, map_name]
	if not FileAccess.file_exists(path):
		return default_map()
	return parse(FileAccess.get_file_as_string(path))


static func save_map(map_name: String, map: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)
	map.name = map_name
	var f := FileAccess.open("%s/%s.json" % [MAPS_DIR, map_name], FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(map, "\t"))
	return OK


static func safe_name(raw: String) -> String:
	var s := raw.strip_edges().validate_filename().left(24)
	return s if not s.is_empty() else "Untitled"
