extends Resource
class_name Weapon

@export_subgroup("Model")
@export var model: PackedScene # Model of the weapon
@export var position: Vector3 # On-screen position
@export var rotation: Vector3 # On-screen rotation
@export var muzzle_position: Vector3 # On-screen position of muzzle flash
@export var tint: Color = Color.WHITE # Multiplied over the model (lets two weapons share a model)
@export var model_scale: float = 1.0 # Uniform scale applied to the model
@export var texture_dir: String = "" # Folder with <material>_albedo/normal/roughness/metallic textures to apply by material name

@export_subgroup("Properties")
@export var display_name: String = "Blaster"
@export var mode_name: String = "Primary"
@export_range(0.05, 3) var cooldown: float = 0.1 # Firerate
@export_range(1, 200) var max_distance: int = 40 # Fire distance
@export_range(0, 200) var damage: float = 25 # Damage per hit
@export_range(0, 5) var spread: float = 0 # Spread of each shot
@export_range(1, 8) var shot_count: int = 1 # Amount of shots
@export_range(0, 50) var knockback: int = 20 # Amount of knockback

@export_subgroup("Alternate mode (right click toggles)")
@export var alt_mode_name: String = "Alt"
@export_range(0.05, 3) var alt_cooldown: float = 0.5
@export_range(0, 200) var alt_damage: float = 40
@export_range(0, 5) var alt_spread: float = 0
@export_range(1, 8) var alt_shot_count: int = 1
@export_range(0, 120) var alt_fov: float = 0 # Camera zoom while in alt mode (0 = no zoom)

@export var min_knockback: Vector2 = Vector2(0.001, 0.001) # x for vertical knockback, y for horizontal knockback
@export var max_knockback: Vector2 = Vector2(0.0025, 0.002) # x for vertical knockback, y for horizontal knockback

@export_subgroup("Sounds")
@export var sound_shoot: String # Sound path

@export_subgroup("Crosshair")
@export var crosshair: Texture2D # Image of crosshair on-screen


# Instantiates the model, applying scale, tint and any textures found in texture_dir.
func build_model() -> Node3D:
	var node: Node3D = model.instantiate()
	node.scale = Vector3.ONE * model_scale
	var textures := _scan_textures()
	for child in node.find_children("*", "MeshInstance3D"):
		if child.mesh == null:
			continue
		for i in child.mesh.get_surface_count():
			var base: Material = child.mesh.surface_get_material(i)
			var mat: StandardMaterial3D = base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
			var mname := base.resource_name.to_lower() if base else ""
			if textures.has(mname):
				var t: Dictionary = textures[mname]
				if t.has("albedo"):
					mat.albedo_texture = t.albedo
					mat.albedo_color = Color.WHITE
				if t.has("normal"):
					mat.normal_enabled = true
					mat.normal_texture = t.normal
				if t.has("roughness"):
					mat.roughness_texture = t.roughness
				if t.has("metallic"):
					mat.metallic_texture = t.metallic
					mat.metallic = 1.0
				if t.has("ao"):
					mat.ao_enabled = true
					mat.ao_texture = t.ao
			if tint != Color.WHITE:
				mat.albedo_color = mat.albedo_color * tint
			child.set_surface_override_material(i, mat)
	return node


func _scan_textures() -> Dictionary:
	var out := {}
	if texture_dir.is_empty():
		return out
	var dir := DirAccess.open(texture_dir)
	if dir == null:
		return out
	for f in dir.get_files():
		var lower := f.to_lower()
		if lower.ends_with(".import"):
			continue
		var stem := lower.get_basename()
		var us := stem.find("_")
		if us < 0:
			continue
		var mat_name := stem.substr(0, us)
		var kind := stem.substr(us + 1)
		var slot := ""
		if kind.contains("albedo") or kind.contains("base") or kind.contains("color"):
			slot = "albedo"
		elif kind.contains("normal"):
			slot = "normal"
		elif kind.contains("rough"):
			slot = "roughness"
		elif kind.contains("metal"):
			slot = "metallic"
		elif kind == "ao":
			slot = "ao"
		if slot.is_empty():
			continue
		var tex = load(texture_dir.path_join(f))
		if tex is Texture2D:
			if not out.has(mat_name):
				out[mat_name] = {}
			out[mat_name][slot] = tex
	return out
