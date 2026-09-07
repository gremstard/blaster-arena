extends Area3D
class_name PickupPad
# Power-up pad. The host validates pickups and tells everyone; the pad hides
# itself and comes back after respawn_time.

@export var type: Player.Pickup = Player.Pickup.HEALTH
@export var respawn_time := 20.0

const LOOKS := {
	Player.Pickup.HEALTH: {"color": Color(0.35, 0.95, 0.45), "label": "+50 HP"},
	Player.Pickup.SHIELD: {"color": Color(0.4, 0.75, 1.0), "label": "SHIELD"},
	Player.Pickup.SPEED: {"color": Color(0.4, 0.95, 1.0), "label": "SPEED"},
	Player.Pickup.DAMAGE: {"color": Color(1.0, 0.4, 0.3), "label": "2x DAMAGE"},
}

var active := true
var _time := randf() * TAU

@onready var icon: MeshInstance3D = $Icon
@onready var ring: MeshInstance3D = $Ring
@onready var label: Label3D = $Label


func _ready() -> void:
	var look: Dictionary = LOOKS[type]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = look.color
	mat.emission_enabled = true
	mat.emission = look.color
	mat.emission_energy_multiplier = 0.6
	icon.material_override = mat
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(look.color, 0.5)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_mat
	label.text = look.label
	label.modulate = look.color
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	icon.rotation.y += delta * 1.5
	icon.position.y = 0.9 + sin(_time * 2.0) * 0.12


func _on_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server() or not active:
		return
	if body is Player and body.can_pickup(type):
		set_active.rpc(false)
		body.apply_pickup.rpc(type)
		get_tree().create_timer(respawn_time).timeout.connect(func(): set_active.rpc(true))


@rpc("authority", "call_local", "reliable")
func set_active(value: bool) -> void:
	active = value
	icon.visible = value
	label.visible = value
	ring.visible = value
	set_deferred("monitoring", value)
