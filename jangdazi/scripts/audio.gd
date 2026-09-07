extends Node

# Code adapted from KidsCanCode

var num_players = 12
var bus = "master"

var available = []  # The available players.
var queue = []  # The queue of sounds to play.

func _ready():
	for i in num_players:
		var p = AudioStreamPlayer.new()
		add_child(p)

		available.append(p)

		p.volume_db = -10
		p.finished.connect(_on_stream_finished.bind(p))
		p.bus = bus

func _on_stream_finished(stream):
	available.append(stream)

func play(sound_path):  # Path (or multiple, separated by commas)
	var sounds = sound_path.split(",")
	queue.append("res://" + sounds[randi() % sounds.size()].strip_edges())

# Play a sound positioned in the 3D world (used for other players' actions)
func play_3d(sound_path: String, world_position: Vector3, volume_db: float = -5.0) -> void:
	var sounds = sound_path.split(",")
	var stream = load("res://" + sounds[randi() % sounds.size()].strip_edges())
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.9, 1.1)
	p.max_distance = 60.0
	p.bus = bus
	p.finished.connect(p.queue_free)
	get_tree().current_scene.add_child(p)
	p.global_position = world_position
	p.play()

func _process(_delta):
	if not queue.is_empty() and not available.is_empty():
		available[0].stream = load(queue.pop_front())
		available[0].play()
		available[0].pitch_scale = randf_range(0.9, 1.1)

		available.pop_front()
