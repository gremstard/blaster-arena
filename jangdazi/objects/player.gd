extends CharacterBody3D
class_name Player

# One scene for every player. The owning peer runs input, movement, camera and
# the first-person viewmodel. Everyone else sees the class model (or a colored
# capsule placeholder) with the current weapon in hand.

@export_subgroup("Properties")
@export var movement_speed := 5.5
@export_range(0, 100) var number_of_jumps: int = 2
@export var jump_strength := 8.0

@export_subgroup("Weapons")
@export var weapons: Array[Weapon] = [] # index 0 is the starting pistol

const MAX_HEALTH := 100
const MAX_OVERSHIELD := 150
const HAND_WEAPON_SCALE := 0.45
const BASE_FOV := 80.0
const POWERUP_SECONDS := 15.0
const SPEED_MULT := 1.5
const DAMAGE_MULT := 1.75
const DROP_FALL_SPEED := 5.0 # terminal velocity while dropping in
const DROP_AIR_SPEED := 9.0

enum Pickup { HEALTH, SHIELD, SPEED, DAMAGE }

signal died(player: Player, killer_id: int)

# --- Replicated by the owner (MultiplayerSynchronizer) ---
var sync_position: Vector3
var sync_rotation_y: float
var sync_pitch: float
var weapon_index := 0
var fire_mode := 0

# --- Host-authoritative ---
var health := MAX_HEALTH
var dead := false

var owned: Array[int] = [0]
var effects := {} # Pickup -> expiry msec
var dropping := false

var weapon: Weapon
var mouse_sensitivity := 700.0
var gamepad_sensitivity := 0.075
var mouse_captured := true
var movement_velocity: Vector3
var rotation_target: Vector3
var gravity := 0.0
var previously_floored := false
var jumps_remaining: int
var container_offset := Vector3(1.2, -1.1, -2.75)
var tween: Tween
var hud: Node
var _hand_weapon_index := -1

@onready var camera: Camera3D = $Head/Camera
@onready var raycast: RayCast3D = $Head/Camera/RayCast
@onready var viewmodel: SubViewportContainer = $Head/Camera/SubViewportContainer
@onready var viewmodel_viewport: SubViewport = $Head/Camera/SubViewportContainer/SubViewport
@onready var muzzle: AnimatedSprite3D = $Head/Camera/SubViewportContainer/SubViewport/CameraItem/Muzzle
@onready var container: Node3D = $Head/Camera/SubViewportContainer/SubViewport/CameraItem/Container
@onready var sound_footsteps: AudioStreamPlayer = $SoundFootsteps
@onready var blaster_cooldown: Timer = $Cooldown
@onready var collider: CollisionShape3D = $Collider
@onready var body: Node3D = $Body
@onready var body_mesh: MeshInstance3D = $Body/Mesh
@onready var model_holder: Node3D = $Body/Model
@onready var hand: Node3D = $Body/Hand
@onready var hand_muzzle: AnimatedSprite3D = $Body/Hand/Muzzle
@onready var name_label: Label3D = $Body/NameLabel
@onready var aura: MeshInstance3D = $Body/Aura

const IMPACT := preload("res://objects/impact.tscn")

var _body_material := StandardMaterial3D.new()
var _aura_material := StandardMaterial3D.new()
var _loaded_class := ""


func peer_id() -> int:
	return get_multiplayer_authority()


func is_local() -> bool:
	return is_multiplayer_authority()


func team() -> int:
	return Game.team_of(peer_id())


func _ready() -> void:
	weapon = weapons[0]
	raycast.add_exception(self)
	sync_position = position
	sync_rotation_y = rotation.y

	body_mesh.material_override = _body_material
	_aura_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aura_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aura_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	aura.material_override = _aura_material
	aura.visible = false
	Game.players_changed.connect(_refresh_identity)
	_refresh_identity()

	if is_local():
		hud = get_tree().get_first_node_in_group("hud")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		camera.current = true
		body.visible = false
		initiate_change_weapon(weapon_index)
		face_toward(Vector3.ZERO)
		_push_hud()
	else:
		camera.current = false
		viewmodel.visible = false
		viewmodel_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		sound_footsteps.stop()
		_update_hand_weapon()


func _push_hud() -> void:
	if hud:
		hud.set_health(health)
		hud.set_effects(effects)
		hud.set_inventory(owned, weapon_index, weapons)


func face_toward(target: Vector3) -> void:
	var d := target - position
	var flat := Vector3(d.x, 0, d.z)
	if flat.length() < 0.01:
		return
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, flat.length())
	rotation.y = yaw
	rotation_target = Vector3(clamp(pitch, deg_to_rad(-90), deg_to_rad(90)), yaw, 0)
	camera.rotation.x = rotation_target.x
	sync_rotation_y = yaw
	sync_pitch = rotation_target.x


func _refresh_identity() -> void:
	var cls := Game.class_of(peer_id())
	name_label.text = "%s\n%s" % [Game.name_of(peer_id()), cls]
	name_label.modulate = Game.TEAM_COLORS[team()]
	_body_material.albedo_color = Game.color_of(peer_id())
	# Show teammates' labels through walls, enemies only in line of sight
	name_label.no_depth_test = not is_local() and team() == Game.local_team()
	if cls != _loaded_class:
		_loaded_class = cls
		_load_class_model(cls)


# Uses a real character model if one has been dropped into assets/characters
func _load_class_model(cls: String) -> void:
	for c in model_holder.get_children():
		c.queue_free()
	var path: String = Game.CLASSES[cls].model
	var has_model := ResourceLoader.exists(path)
	body_mesh.visible = not has_model
	if has_model:
		var scene: PackedScene = load(path)
		if scene:
			var inst := scene.instantiate()
			model_holder.add_child(inst)


func has_effect(type: Pickup) -> bool:
	return effects.has(type) and effects[type] > Time.get_ticks_msec()


func _process(delta: float) -> void:
	var changed := false
	for type in effects.keys():
		if effects[type] <= Time.get_ticks_msec():
			effects.erase(type)
			changed = true
	if changed and is_local() and hud:
		hud.set_effects(effects)
	_update_aura()

	if is_local():
		var target_fov := BASE_FOV
		if fire_mode == 1 and weapon.alt_fov > 0:
			target_fov = weapon.alt_fov
		camera.fov = lerp(camera.fov, target_fov, min(1.0, delta * 12.0))
		return

	var t: float = min(1.0, delta * 15.0)
	position = position.lerp(sync_position, t)
	rotation.y = lerp_angle(rotation.y, sync_rotation_y, t)
	hand.rotation.x = lerp_angle(hand.rotation.x, sync_pitch, t)
	if weapon_index != _hand_weapon_index:
		_update_hand_weapon()


func _update_aura() -> void:
	var show := not dead and (has_effect(Pickup.DAMAGE) or has_effect(Pickup.SPEED))
	aura.visible = show and not is_local()
	if show:
		var c := Color(1, 0.3, 0.2) if has_effect(Pickup.DAMAGE) else Color(0.3, 0.8, 1.0)
		c.a = 0.35 + 0.15 * sin(Time.get_ticks_msec() / 120.0)
		_aura_material.albedo_color = c


func _physics_process(delta: float) -> void:
	if not is_local():
		return
	if dead:
		velocity = Vector3.ZERO
		_handle_mouse_capture()
		return

	handle_controls(delta)
	handle_gravity(delta)

	var applied_velocity: Vector3
	movement_velocity = transform.basis * movement_velocity
	applied_velocity = velocity.lerp(movement_velocity, delta * (4.0 if dropping else 10.0))
	applied_velocity.y = -gravity
	velocity = applied_velocity
	move_and_slide()

	container.position = lerp(container.position, container_offset - (basis.inverse() * applied_velocity / 30), delta * 10)

	sound_footsteps.stream_paused = true
	if is_on_floor():
		if abs(velocity.x) > 1 or abs(velocity.z) > 1:
			sound_footsteps.stream_paused = false

	camera.position.y = lerp(camera.position.y, 0.0, delta * 5)
	if is_on_floor() and gravity > 1 and !previously_floored:
		Audio.play("sounds/land.ogg")
		camera.position.y = -0.1
		if dropping:
			dropping = false
			if hud:
				hud.set_dropping(false)
	previously_floored = is_on_floor()

	sync_position = position
	sync_rotation_y = rotation.y
	sync_pitch = camera.rotation.x

	if position.y < Game.fall_y:
		_request_damage(self, 9999, 0)


func _input(event: InputEvent) -> void:
	if not is_local():
		return
	if event is InputEventMouseMotion and mouse_captured:
		var zoom_factor: float = camera.fov / BASE_FOV
		handle_rotation(event.relative.x * zoom_factor, event.relative.y * zoom_factor, false)


func _handle_mouse_capture() -> void:
	if Input.is_action_just_pressed("mouse_capture"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse_captured = true
	if Input.is_action_just_pressed("mouse_capture_exit"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouse_captured = false


func handle_controls(delta: float) -> void:
	_handle_mouse_capture()

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var speed := movement_speed * (SPEED_MULT if has_effect(Pickup.SPEED) else 1.0)
	if dropping:
		speed = DROP_AIR_SPEED
	movement_velocity = Vector3(input.x, 0, input.y).normalized() * speed

	var rotation_input := Input.get_vector("camera_right", "camera_left", "camera_down", "camera_up")
	if rotation_input:
		handle_rotation(rotation_input.x, rotation_input.y, true, delta)

	if mouse_captured:
		action_shoot()
		if Input.is_action_just_pressed("fire_mode"):
			set_fire_mode(1 - fire_mode)

	if Input.is_action_just_pressed("jump") and not dropping:
		if jumps_remaining:
			action_jump()

	action_weapon_toggle()


func handle_rotation(xRot: float, yRot: float, isController: bool, delta: float = 0.0) -> void:
	if isController:
		rotation_target -= Vector3(-yRot, -xRot, 0).limit_length(1.0) * gamepad_sensitivity
		rotation_target.x = clamp(rotation_target.x, deg_to_rad(-90), deg_to_rad(90))
		camera.rotation.x = lerp_angle(camera.rotation.x, rotation_target.x, delta * 25)
		rotation.y = lerp_angle(rotation.y, rotation_target.y, delta * 25)
	else:
		rotation_target += (Vector3(-yRot, -xRot, 0) / mouse_sensitivity)
		rotation_target.x = clamp(rotation_target.x, deg_to_rad(-90), deg_to_rad(90))
		camera.rotation.x = rotation_target.x
		rotation.y = rotation_target.y


func handle_gravity(delta: float) -> void:
	gravity += 20 * delta
	if dropping:
		gravity = min(gravity, DROP_FALL_SPEED) # slow, steerable descent
	if gravity < 0 and is_on_ceiling():
		gravity = 0
	if gravity > 0 and is_on_floor():
		jumps_remaining = number_of_jumps
		gravity = 0


func action_jump() -> void:
	Audio.play("sounds/jump_a.ogg, sounds/jump_b.ogg, sounds/jump_c.ogg")
	gravity = -jump_strength
	jumps_remaining -= 1


# --- Fire modes ---

func stat(property: String) -> Variant:
	return weapon.get("alt_" + property) if fire_mode == 1 else weapon.get(property)


func mode_name() -> String:
	return weapon.alt_mode_name if fire_mode == 1 else weapon.mode_name


func set_fire_mode(mode: int) -> void:
	fire_mode = mode
	Audio.play("sounds/weapon_change.ogg")
	if hud:
		hud.set_weapon(weapon.display_name, mode_name())


# --- Shooting ---

func action_shoot() -> void:
	if not Input.is_action_pressed("shoot"):
		return
	if not blaster_cooldown.is_stopped():
		return
	blaster_cooldown.start(stat("cooldown"))

	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var hit_player := false
	var spread: float = stat("spread") * (weapon.max_distance / 10.0)
	var damage: int = int(stat("damage") * (DAMAGE_MULT if has_effect(Pickup.DAMAGE) else 1.0))

	for n in stat("shot_count"):
		raycast.target_position.x = randf_range(-spread, spread)
		raycast.target_position.y = randf_range(-spread, spread)
		raycast.force_raycast_update()
		if not raycast.is_colliding():
			continue
		var collider_hit := raycast.get_collider()
		if collider_hit is Player and not collider_hit.dead:
			if collider_hit.team() != team():
				_request_damage(collider_hit, damage, peer_id())
				hit_player = true
		points.append(raycast.get_collision_point())
		normals.append(raycast.get_collision_normal())

	if hit_player and hud:
		hud.hit_marker()

	Audio.play(weapon.sound_shoot)
	muzzle.play("default")
	muzzle.rotation_degrees.z = randf_range(-45, 45)
	muzzle.scale = Vector3.ONE * randf_range(0.40, 0.75)
	muzzle.position = container.position - weapon.muzzle_position
	_spawn_impacts(points, normals)
	fx_shot.rpc(points, normals)

	var knockback := random_vec2(weapon.min_knockback, weapon.max_knockback)
	container.position.z += 0.25
	camera.rotation.x += knockback.x
	rotation.y += knockback.y
	rotation_target.x += knockback.x
	rotation_target.y += knockback.y
	movement_velocity += Vector3(0, 0, weapon.knockback)


func _spawn_impacts(points: PackedVector3Array, normals: PackedVector3Array) -> void:
	var viewer := get_viewport().get_camera_3d()
	for i in points.size():
		var impact := IMPACT.instantiate()
		impact.play("shot")
		get_tree().current_scene.add_child(impact)
		impact.global_position = points[i] + normals[i] / 10
		if viewer:
			impact.look_at(viewer.global_transform.origin, Vector3.UP, true)


@rpc("authority", "unreliable")
func fx_shot(points: PackedVector3Array, normals: PackedVector3Array) -> void:
	if dead:
		return
	Audio.play_3d(weapon.sound_shoot, hand.global_position)
	hand_muzzle.frame = 0
	hand_muzzle.play("default")
	hand_muzzle.rotation_degrees.z = randf_range(-45, 45)
	hand_muzzle.scale = Vector3.ONE * randf_range(0.25, 0.4)
	_spawn_impacts(points, normals)


# --- Damage and death (host decides). No respawn during a round. ---

func _request_damage(victim: Player, amount: int, shooter_id: int) -> void:
	if multiplayer.is_server():
		victim.take_damage(amount, shooter_id)
	else:
		victim.take_damage.rpc_id(1, amount, shooter_id)


@rpc("any_peer", "reliable")
func take_damage(amount: int, shooter_id: int) -> void:
	if not multiplayer.is_server() or dead:
		return
	if shooter_id > 0 and shooter_id != peer_id() and Game.team_of(shooter_id) == team():
		return # friendly fire off
	health = max(health - amount, 0)
	sync_health.rpc(health)
	if health <= 0:
		die.rpc(shooter_id)
		Game.record_kill(shooter_id, peer_id())
		died.emit(self, shooter_id)


@rpc("any_peer", "call_local", "reliable")
func sync_health(value: int) -> void:
	var previous := health
	health = value
	if is_local() and hud:
		hud.set_health(health)
		if value < previous:
			hud.damage_flash()
			Audio.play("sounds/enemy_hurt.ogg")


@rpc("any_peer", "call_local", "reliable")
func die(killer_id: int) -> void:
	dead = true
	health = 0
	dropping = false
	effects.clear()
	collider.set_deferred("disabled", true)
	body.visible = false
	Audio.play_3d("sounds/enemy_destroy.ogg", global_position)
	if is_local():
		velocity = Vector3.ZERO
		viewmodel.visible = false
		if hud:
			hud.set_health(0)
			hud.set_effects(effects)
			hud.set_dropping(false)
			hud.show_death(Game.name_of(killer_id), killer_id <= 0 or killer_id == peer_id())


# Spectator state for players who join mid-round
@rpc("any_peer", "call_local", "reliable")
func spectate() -> void:
	die(0)
	if is_local() and hud:
		hud.show_death("", true, "Joined mid-round. Spectating until the next round.")


# New round (or warmup respawn): full reset at a spawn point, optionally dropping in
@rpc("any_peer", "call_local", "reliable")
func reset_for_round(pos: Vector3, drop: bool) -> void:
	dead = false
	health = MAX_HEALTH
	effects.clear()
	owned = [0]
	weapon_index = 0
	fire_mode = 0
	collider.set_deferred("disabled", false)
	position = pos
	sync_position = pos
	dropping = drop
	if is_local():
		velocity = Vector3.ZERO
		gravity = 0.0
		face_toward(Vector3(0, pos.y, 0))
		viewmodel.visible = true
		initiate_change_weapon(0)
		_push_hud()
		if hud:
			hud.hide_death()
			hud.set_dropping(drop)
	else:
		body.visible = true


# --- Loot and power-ups ---

func can_pickup(type: Pickup) -> bool:
	if dead:
		return false
	match type:
		Pickup.HEALTH:
			return health < MAX_HEALTH
		Pickup.SHIELD:
			return health < MAX_OVERSHIELD
	return true


@rpc("any_peer", "call_local", "reliable")
func give_loot(item: String) -> void:
	if dead:
		return
	if item.begins_with("weapon:"):
		var idx := int(item.trim_prefix("weapon:"))
		if idx >= 0 and idx < weapons.size():
			var is_new := not owned.has(idx)
			if is_new:
				owned.append(idx)
				owned.sort()
			if is_local():
				if is_new:
					initiate_change_weapon(idx)
				else:
					apply_pickup(Pickup.HEALTH if health < MAX_HEALTH else Pickup.SHIELD)
					return
				if hud:
					hud.set_inventory(owned, weapon_index, weapons)
					hud.pickup_toast("Picked up %s" % weapons[idx].display_name)
				Audio.play("sounds/weapon_change.ogg")
		return
	match item:
		"health": apply_pickup(Pickup.HEALTH)
		"shield": apply_pickup(Pickup.SHIELD)
		"speed": apply_pickup(Pickup.SPEED)
		"damage": apply_pickup(Pickup.DAMAGE)


@rpc("any_peer", "call_local", "reliable")
func apply_pickup(type: Pickup) -> void:
	if dead:
		return
	match type:
		Pickup.HEALTH:
			health = min(health + 50, MAX_HEALTH)
		Pickup.SHIELD:
			health = min(health + 50, MAX_OVERSHIELD)
		Pickup.SPEED, Pickup.DAMAGE:
			effects[type] = Time.get_ticks_msec() + int(POWERUP_SECONDS * 1000)
	if is_local():
		Audio.play("sounds/weapon_change.ogg")
		if hud:
			hud.set_health(health)
			hud.set_effects(effects)
			hud.pickup_flash(type)
	else:
		Audio.play_3d("sounds/weapon_change.ogg", global_position, -12.0)


# --- Weapons (only owned ones can be selected) ---

func action_weapon_toggle() -> void:
	var target := -1
	if Input.is_action_just_pressed("weapon_toggle"):
		var i := owned.find(weapon_index)
		target = owned[wrapi(i + 1, 0, owned.size())]
	for slot in weapons.size():
		if Input.is_action_just_pressed("weapon_%d" % (slot + 1)) and owned.has(slot):
			target = slot
	if target >= 0 and target != weapon_index:
		initiate_change_weapon(target)
		Audio.play("sounds/weapon_change.ogg")


func initiate_change_weapon(index: int) -> void:
	weapon_index = index
	fire_mode = 0
	tween = get_tree().create_tween()
	tween.set_ease(Tween.EASE_OUT_IN)
	tween.tween_property(container, "position", container_offset - Vector3(0, 1, 0), 0.1)
	tween.tween_callback(change_weapon)


func change_weapon() -> void:
	weapon = weapons[weapon_index]
	for n in container.get_children():
		container.remove_child(n)
		n.queue_free()
	var weapon_model: Node3D = weapon.model.instantiate()
	container.add_child(weapon_model)
	weapon_model.position = weapon.position
	weapon_model.rotation_degrees = weapon.rotation
	_tint_model(weapon_model, weapon.tint)
	for child in weapon_model.find_children("*", "MeshInstance3D"):
		child.layers = 2
	raycast.target_position = Vector3(0, 0, -1) * weapon.max_distance
	if hud:
		hud.set_crosshair(weapon.crosshair)
		hud.set_weapon(weapon.display_name, mode_name())
		hud.set_inventory(owned, weapon_index, weapons)


func _update_hand_weapon() -> void:
	_hand_weapon_index = weapon_index
	weapon = weapons[weapon_index]
	for n in hand.get_children():
		if n != hand_muzzle:
			n.queue_free()
	var model: Node3D = weapon.model.instantiate()
	hand.add_child(model)
	model.rotation_degrees = weapon.rotation
	model.scale = Vector3.ONE * HAND_WEAPON_SCALE
	_tint_model(model, weapon.tint)


static func _tint_model(model: Node3D, tint: Color) -> void:
	if tint == Color.WHITE:
		return
	for child in model.find_children("*", "MeshInstance3D"):
		for i in child.get_surface_override_material_count():
			var base: Material = child.mesh.surface_get_material(i) if child.mesh else null
			var mat: StandardMaterial3D = base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
			mat.albedo_color = mat.albedo_color * tint
			child.set_surface_override_material(i, mat)


static func random_vec2(_min: Vector2, _max: Vector2) -> Vector2:
	var _sign = -1 if randi() % 2 == 0 else 1
	return Vector2(randf_range(_min.x, _max.x), randf_range(_min.y, _max.y) * _sign)
