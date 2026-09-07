extends Node3D
class_name LevelBuilder
# Builds a level from map data (a Dictionary, saved as JSON). Used by the game
# on every peer and by the map editor. Piece node names are deterministic so
# RPC paths (pickups) match across peers.

const MAPS_DIR := "user://maps"
const DEFAULT_MAP := "res://maps/arena.json"
const GRID := 0.2

const PIECES := {
	"platform_large": {"label": "Grass platform 5x5", "scene": "res://objects/platform_large_grass.tscn", "size": Vector3(5.2, 0.5, 5.2)},
	"platform": {"label": "Platform 2x2", "scene": "res://objects/platform.tscn", "size": Vector3(2.2, 0.5, 2.2)},
	"wall_low": {"label": "Low wall", "scene": "res://objects/wall_low.tscn", "size": Vector3(2.2, 0.8, 0.7)},
	"wall_high": {"label": "High wall", "scene": "res://objects/wall_high.tscn", "size": Vector3(1.5, 1.7, 0.7)},
	"spawn": {"label": "Spawn point", "size": Vector3(1, 2, 1)},
	"pickup_health": {"label": "Health pickup", "pickup": Player.Pickup.HEALTH, "size": Vector3(1.8, 2, 1.8)},
	"pickup_shield": {"label": "Shield pickup", "pickup": Player.Pickup.SHIELD, "size": Vector3(1.8, 2, 1.8)},
	"pickup_speed": {"label": "Speed pickup", "pickup": Player.Pickup.SPEED, "size": Vector3(1.8, 2, 1.8)},
	"pickup_damage": {"label": "Damage pickup", "pickup": Player.Pickup.DAMAGE, "size": Vector3(1.8, 2, 1.8)},
}
const PICKUP_SCENE := preload("res://objects/pickup.tscn")

var data := {"name": "Untitled", "pieces": []}
var spawn_points: Array[Vector3] = []
var min_y := 0.0
var editor_mode := false
var _counter := 0
var _scene_cache := {}


func build(map: Dictionary, in_editor := false) -> void:
	clear()
	editor_mode = in_editor
	data = {"name": map.get("name", "Untitled"), "pieces": []}
	for piece in map.get("pieces", []):
		if PIECES.has(piece.get("t", "")):
			_instance(piece.get("t"), _to_vec(piece.get("p", [0, 0, 0])), float(piece.get("r", 0)))
	_recompute()
	print("[map] built '%s' (%d pieces, %d spawns)" % [data.name, data.pieces.size(), spawn_points.size()])


func clear() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	data = {"name": data.get("name", "Untitled"), "pieces": []}
	spawn_points.clear()
	_counter = 0


func add_piece(type: String, pos: Vector3, rot_deg: float) -> Node3D:
	var node := _instance(type, pos, rot_deg)
	_recompute()
	return node


func remove_piece(node: Node3D) -> void:
	if node.has_meta("piece"):
		data.pieces.erase(node.get_meta("piece"))
	remove_child(node)
	node.queue_free()
	_recompute()


# Find the piece root for any node hit by a raycast inside the level
func piece_root_of(node: Node) -> Node3D:
	var n := node
	while n and n.get_parent() != self:
		n = n.get_parent()
	return n as Node3D


func _instance(type: String, pos: Vector3, rot_deg: float) -> Node3D:
	var info: Dictionary = PIECES[type]
	var piece := {"t": type, "p": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)], "r": rot_deg}
	data.pieces.append(piece)
	var node: Node3D
	if info.has("scene"):
		if not _scene_cache.has(type):
			_scene_cache[type] = load(info.scene)
		node = _scene_cache[type].instantiate()
	elif info.has("pickup"):
		node = PICKUP_SCENE.instantiate()
		node.type = info.pickup
		if editor_mode:
			node.add_child(_editor_collider(info.size))
	else: # spawn point
		node = Node3D.new()
		if editor_mode:
			var mesh := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.3
			cap.height = 1.0
			mesh.mesh = cap
			mesh.position.y = 0.55
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(1, 1, 0.3, 0.7)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh.material_override = mat
			node.add_child(mesh)
			var label := Label3D.new()
			label.text = "SPAWN"
			label.position.y = 1.4
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.pixel_size = 0.004
			label.font_size = 48
			label.outline_size = 12
			node.add_child(label)
			node.add_child(_editor_collider(info.size))
	_counter += 1
	node.name = "%s_%d" % [type, _counter]
	node.set_meta("piece", piece)
	node.set_meta("type", type)
	add_child(node)
	node.position = pos
	node.rotation_degrees.y = rot_deg
	return node


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
	spawn_points.clear()
	min_y = INF
	for piece in data.pieces:
		var p: Vector3 = _to_vec(piece.p)
		min_y = min(min_y, p.y)
		if piece.t == "spawn":
			spawn_points.append(p)
	if min_y == INF:
		min_y = 0.0
	Game.fall_y = min_y - 12.0


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
	if map_name.is_empty() or map_name == "Arena":
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
