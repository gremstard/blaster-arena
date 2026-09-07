class_name ModelTextures

static var _cache := {} # path -> Texture2D, filled by preload_dir() and _scan()
static var _pending: Array[String] = []


# Queue every texture in a folder for background loading (call at startup)
static func preload_dir(texture_dir: String) -> void:
	if texture_dir.is_empty():
		return
	var dir := DirAccess.open(texture_dir)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".import"):
			continue
		var path := texture_dir.path_join(f)
		if not _cache.has(path) and not _pending.has(path):
			if ResourceLoader.load_threaded_request(path, "Texture2D", true) == OK:
				_pending.append(path)


# Move finished background loads into the cache; returns true when everything is loaded
static func poll() -> bool:
	var still: Array[String] = []
	for path in _pending:
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_cache[path] = ResourceLoader.load_threaded_get(path)
		elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			still.append(path)
	_pending = still
	return _pending.is_empty()


static func _fetch(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	if _pending.has(path):
		var tex = ResourceLoader.load_threaded_get(path) # waits for the thread
		_pending.erase(path)
		if tex is Texture2D:
			_cache[path] = tex
		return tex
	var tex = load(path)
	if tex is Texture2D:
		_cache[path] = tex
	return tex
# Applies PBR textures from a folder to an instanced model, matched by material name.
# Files are classified by keyword: albedo/base/color/diffuse, normal, rough, metal, ao.
# `mapping` overrides the file-stem prefix per material name (e.g. {"uniform": "scp_operator_uniform"}).

static func apply(node: Node3D, texture_dir: String, mapping: Dictionary = {}, tint: Color = Color.WHITE) -> void:
	var files := _scan(texture_dir)
	for child in node.find_children("*", "MeshInstance3D"):
		if child.mesh == null:
			continue
		for i in child.mesh.get_surface_count():
			var base: Material = child.mesh.surface_get_material(i)
			var mat: StandardMaterial3D = base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
			var mname := base.resource_name if base else ""
			var spec = mapping.get(mname, mname)
			var t: Dictionary
			if spec is Dictionary: # explicit {slot: filename}
				t = {}
				for slot in spec:
					var tex = _fetch(texture_dir.path_join(spec[slot]))
					if tex is Texture2D:
						t[slot] = tex
			else:
				t = _best_match(files, String(spec))
			if t.has("albedo"):
				mat.albedo_texture = t.albedo
				mat.albedo_color = Color.WHITE
			if t.has("normal"):
				mat.normal_enabled = true
				mat.normal_texture = t.normal
			if t.has("roughness"):
				mat.roughness_texture = t.roughness
				mat.roughness = 1.0
			if t.has("metallic"):
				mat.metallic_texture = t.metallic
				mat.metallic = 1.0
			if t.has("ao"):
				mat.ao_enabled = true
				mat.ao_texture = t.ao
			if tint != Color.WHITE:
				mat.albedo_color = mat.albedo_color * tint
			child.set_surface_override_material(i, mat)


# Returns {slot: Texture2D} for files matching a material name. A file matches when its
# stem starts with "<name>_" or contains "_<name>_" (Sketchfab exports as <model>_<material>_<slot>).
# Names are compared without Blender's ".001" suffixes and with spaces as underscores.
static func _best_match(files: Dictionary, prefix: String) -> Dictionary:
	var name := _norm(prefix)
	if name.is_empty():
		return {}
	var out := {}
	for stem in files:
		var s: String = _norm(stem)
		var rest := ""
		if s.begins_with(name + "_"):
			rest = s.substr(name.length())
		elif s.contains("_" + name + "_"):
			rest = s.substr(s.find("_" + name + "_") + name.length() + 1)
		else:
			continue
		var slot := _slot(rest)
		if not slot.is_empty() and not out.has(slot):
			out[slot] = files[stem]
	return out


static func _norm(s: String) -> String:
	var n := s.to_lower().replace(" ", "_").replace("+", "_")
	var dot := n.rfind(".")
	if dot > 0 and n.substr(dot + 1).is_valid_int():
		n = n.substr(0, dot)
	return n


static func _slot(rest: String) -> String:
	var r := rest.to_lower()
	if r.contains("albedo") or r.contains("base") or r.contains("color") or r.contains("diffuse"):
		return "albedo"
	if r.contains("normal") or r.contains("bump"):
		return "normal"
	if r.contains("rough") or r.contains("gloss"):
		return "roughness"
	if r.contains("metal"):
		return "metallic"
	if r.contains("_ao") or r.begins_with("ao") or r.contains("mixed_ao"):
		return "ao"
	return ""


static func _scan(texture_dir: String) -> Dictionary:
	var out := {}
	if texture_dir.is_empty():
		return out
	var dir := DirAccess.open(texture_dir)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".import"):
			continue
		var tex = _fetch(texture_dir.path_join(f))
		if tex is Texture2D:
			out[f.get_basename().to_lower()] = tex
	return out
