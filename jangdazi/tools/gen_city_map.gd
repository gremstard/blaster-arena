extends SceneTree
# Generates maps/city.json for the FBX city: finds street-level points by raycasting
# down through the model, then places the zone, spawns and loot on them.
# Usage: Godot --headless --path . --script tools/gen_city_map.gd

const STEP := 4.0
const SAMPLE_HEIGHT := 150.0
const GROUND_MAX_Y := 1.0

func _init():
	var root_node := Node3D.new()
	root.add_child(root_node)
	var model: Node3D = load("res://assets/City Map/City.fbx").instantiate()
	root_node.add_child(model)
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
	var c := aabb.get_center()
	model.position = Vector3(-c.x, -aabb.position.y, -c.z)
	var half: float = min(aabb.size.x, aabb.size.z) / 2.0 - 4.0
	print("city centered; half extent ", half)
	_generate.call_deferred(root_node, half)

func _generate(root_node: Node3D, half: float) -> void:
	await physics_frame
	await physics_frame
	await physics_frame
	var space := root_node.get_world_3d().direct_space_state
	var street: Array[Vector3] = []
	var raw: Array[Dictionary] = []
	var hits := 0
	var ys := {}
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, SAMPLE_HEIGHT, z), Vector3(x, -20, z))
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				hits += 1
				var key := int(round(hit.position.y))
				ys[key] = ys.get(key, 0) + 1
			if not hit.is_empty() and hit.normal.y > 0.9:
				raw.append(hit)
			z += STEP
		x += STEP
	# ground = most common low height
	var ground_y := INF
	var best := 0
	for k in ys:
		if ys[k] > best:
			best = ys[k]
			ground_y = float(k)
	print("ground y ~ ", ground_y)
	for hit in raw:
		if hit.position.y < ground_y + GROUND_MAX_Y:
			if true:
				# keep points with some clearance from walls: probe 4 directions at 1.5 m height
				var clear := true
				for d in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
					var q2 := PhysicsRayQueryParameters3D.create(hit.position + Vector3(0, 1.2, 0), hit.position + Vector3(0, 1.2, 0) + d * 1.5)
					if not space.intersect_ray(q2).is_empty():
						clear = false
						break
				if clear:
					street.append(hit.position)
	var keys := ys.keys()
	keys.sort()
	var summary := []
	for k in keys.slice(0, 12):
		summary.append("%d:%d" % [k, ys[k]])
	print("hits: ", hits, "  lowest y buckets: ", summary)
	print("street points: ", street.size())
	if street.is_empty():
		quit(1)
		return

	var by_center := street.duplicate()
	by_center.sort_custom(func(a, b): return Vector2(a.x, a.z).length() < Vector2(b.x, b.z).length())
	var zone: Vector3 = by_center[0]
	var pieces := []
	pieces.append({"t": "city", "p": [0, 0, 0], "r": 0})
	pieces.append({"t": "zone", "p": _arr(zone), "r": 0})
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var def_spawns := _ring(street, zone, 10.0, 30.0, 8, rng, 6.0)
	var att_spawns := _ring(street, zone, half * 0.78, half, 12, rng, 25.0)
	var loot_c := _ring(street, zone, 3.0, 45.0, 14, rng, 8.0)
	var loot_o := _ring(street, zone, 90.0, half * 0.95, 32, rng, 14.0)
	for p in def_spawns: pieces.append({"t": "spawn_def", "p": _arr(p + Vector3(0, 0.5, 0)), "r": 0})
	for p in att_spawns: pieces.append({"t": "spawn_att", "p": _arr(p + Vector3(0, 0.5, 0)), "r": 0})
	for p in loot_c: pieces.append({"t": "loot_center", "p": _arr(p), "r": 0})
	for p in loot_o: pieces.append({"t": "loot_outer", "p": _arr(p), "r": 0})
	var f := FileAccess.open("res://maps/city.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": "City", "pieces": pieces}))
	print("zone at ", zone, "  def ", def_spawns.size(), "  att ", att_spawns.size(), "  loot ", loot_c.size(), "/", loot_o.size())
	quit()

static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1)]

# Pick up to n street points with distance from `center` in [r_min, r_max], spread apart by min_gap
static func _ring(points: Array[Vector3], center: Vector3, r_min: float, r_max: float, n: int, rng: RandomNumberGenerator, min_gap: float) -> Array[Vector3]:
	var candidates: Array[Vector3] = []
	for p in points:
		var d := Vector2(p.x - center.x, p.z - center.z).length()
		if d >= r_min and d <= r_max:
			candidates.append(p)
	candidates.shuffle()
	var out: Array[Vector3] = []
	for p in candidates:
		var ok := true
		for q in out:
			if p.distance_to(q) < min_gap:
				ok = false
				break
		if ok:
			out.append(p)
			if out.size() >= n:
				break
	return out
