class_name ModelTextures
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
			var prefix: String = mapping.get(mname, mname).to_lower()
			var t: Dictionary = _best_match(files, prefix)
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


# Returns {slot: Texture2D} for files whose stem starts with prefix (longest prefix wins)
static func _best_match(files: Dictionary, prefix: String) -> Dictionary:
	if prefix.is_empty():
		return {}
	var out := {}
	for stem in files:
		if stem.begins_with(prefix):
			var rest: String = stem.substr(prefix.length())
			var slot := _slot(rest)
			if not slot.is_empty() and not out.has(slot):
				out[slot] = files[stem]
	return out


static func _slot(rest: String) -> String:
	var r := rest.to_lower()
	if r.contains("albedo") or r.contains("base") or r.contains("color") or r.contains("diffuse"):
		return "albedo"
	if r.contains("normal"):
		return "normal"
	if r.contains("rough"):
		return "roughness"
	if r.contains("metal"):
		return "metallic"
	if r.contains("ao"):
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
		var tex = load(texture_dir.path_join(f))
		if tex is Texture2D:
			out[f.get_basename().to_lower()] = tex
	return out
