extends SceneTree
# Renders the raw City.fbx from a few camera angles and saves screenshots.
# Usage: Godot --path . --script tools/preview_city.gd -- out_prefix
var shots := []
var idx := 0
func _init():
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/city"
	var root_node := Node3D.new()
	root.add_child(root_node)
	var env := WorldEnvironment.new()
	env.environment = load("res://scenes/main-environment.tres")
	root_node.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	root_node.add_child(sun)
	var city: Node3D = load("res://assets/City Map/City.fbx").instantiate()
	root_node.add_child(city)
	var cam := Camera3D.new()
	cam.far = 3000
	root_node.add_child(cam)
	cam.current = true
	shots = [
		[Vector3(0, 400, 700), Vector3(0, 0, 0), out + "_aerial.png"],
		[Vector3(-200, 3, -200), Vector3(-160, 3, -160), out + "_street.png"],
		[Vector3(0, 60, 120), Vector3(0, 10, 0), out + "_center.png"],
	]
	_next(cam)

func _next(cam: Camera3D) -> void:
	if idx >= shots.size():
		quit(); return
	var s = shots[idx]
	cam.position = s[0]
	cam.look_at(s[1])
	idx += 1
	create_timer(1.5).timeout.connect(func():
		root.get_texture().get_image().save_png(s[2])
		print("saved ", s[2])
		_next(cam))
