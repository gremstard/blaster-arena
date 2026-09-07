extends SceneTree
# Renders every weapon viewmodel in a grid the way the player sees it and saves a PNG.
# Usage: Godot --path . --script tools/weapon_gallery.gd -- /path/out.png
func _init():
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/gallery.png"
	var weapons: Array = []
	for f in ["nagant", "pp19", "blaster-repeater", "ak47", "ar15", "type81", "aks74u", "sks", "sks-scoped", "marksman", "sv98"]:
		weapons.append(load("res://weapons/%s.tres" % f))
	var root_node := Node3D.new()
	root.add_child(root_node)
	var env := WorldEnvironment.new()
	env.environment = load("res://scenes/main-environment.tres")
	root_node.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	root_node.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 55
	root_node.add_child(cam)
	cam.current = true
	var cols := 4
	for i in weapons.size():
		var w: Weapon = weapons[i]
		var m: Node3D = w.build_model()
		root_node.add_child(m)
		var col := i % cols
		var row := i / cols
		m.position = Vector3((col - 1.5) * 2.3, 1.5 - row * 1.6, -6.0)
		m.rotation_degrees = Vector3(0, w.rotation.y + 90, 0) # side view: muzzle should point LEFT
		var label := Label3D.new()
		label.text = "%d %s" % [i, w.display_name]
		label.font_size = 40
		label.outline_size = 10
		label.pixel_size = 0.006
		label.position = m.position + Vector3(0, -0.6, 0)
		root_node.add_child(label)
	create_timer(2.0).timeout.connect(func():
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		quit())
