extends Resource
class_name Weapon

@export_subgroup("Model")
@export var model: PackedScene # Model of the weapon
@export var position: Vector3 # On-screen position
@export var rotation: Vector3 # On-screen rotation
@export var muzzle_position: Vector3 # On-screen position of muzzle flash
@export var tint: Color = Color.WHITE # Multiplied over the model (lets two weapons share a model)
@export var model_scale: float = 1.0 # Uniform scale that brings the model to real-world size
@export var view_scale: float = 2.0 # Extra scale for the first-person viewmodel only
@export var texture_dir: String = "" # Folder with <material>_albedo/normal/roughness/metallic textures to apply by material name
@export var texture_map: Dictionary = {} # Optional material name -> file prefix (or {slot: file}) overrides
@export var auto_center: bool = true # Shift the model so its bounding box center sits at the origin

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
	var inner: Node3D = model.instantiate()
	inner.scale = Vector3.ONE * model_scale
	ModelTextures.apply(inner, texture_dir, texture_map, tint)
	var holder := Node3D.new()
	holder.add_child(inner)
	if auto_center:
		var aabb := AABB()
		var first := true
		for m in inner.find_children("*", "MeshInstance3D"):
			var a: AABB = m.transform * m.get_aabb()
			var p := m.get_parent()
			while p and p != holder:
				a = p.transform * a
				p = p.get_parent()
			aabb = a if first else aabb.merge(a)
			first = false
		if not first:
			inner.position = -aabb.get_center()
	return holder
