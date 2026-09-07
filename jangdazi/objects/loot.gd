extends Area3D
class_name LootCrate
# Loot crate spawned by the host at round start. First alive player to touch it
# gets a random item; the host then removes the crate (replicated by the spawner).

const ITEMS := { # item -> weight
	"weapon:1": 3, # Repeater
	"weapon:2": 3, # AK-47
	"weapon:3": 2, # Marksman
	"shield": 3,
	"health": 2,
	"damage": 1,
	"speed": 1,
}

var _time := randf() * TAU
@onready var mesh: MeshInstance3D = $Mesh
@onready var label: Label3D = $Label


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	mesh.rotation.y += delta
	mesh.position.y = 0.6 + sin(_time * 2.0) * 0.1


func _on_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if body is Player and not body.dead:
		body.give_loot.rpc(roll())
		queue_free()


static func roll() -> String:
	var total := 0
	for k in ITEMS:
		total += ITEMS[k]
	var r := randi() % total
	for k in ITEMS:
		r -= ITEMS[k]
		if r < 0:
			return k
	return "health"
