extends Node3D
# Arena scene root: lobby flow, map distribution, player spawning/respawning, editor.
# The spawner and Players container exist from startup so replication paths
# match on every peer before anyone connects.

const PLAYER_SCENE := preload("res://objects/player.tscn")
const RESPAWN_DELAY := 3.0

@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var players_root: Node3D = $Players
@onready var level: LevelBuilder = $Level
@onready var lobby: CanvasLayer = $Lobby
@onready var hud: CanvasLayer = $HUD
@onready var editor: Node3D = $Editor
@onready var menu_camera: Camera3D = $MenuCamera


func _ready() -> void:
	spawner.spawn_function = _spawn_player
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	lobby.host_requested.connect(host_game)
	lobby.join_requested.connect(join_game)
	lobby.editor_requested.connect(open_editor)
	editor.closed.connect(close_editor)
	editor.play_requested.connect(func(map): host_game_with(map))
	Game.match_reset.connect(_on_match_reset)
	hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	level.build(LevelBuilder.default_map())
	_handle_cmdline()


func _process(delta: float) -> void:
	if menu_camera.current:
		menu_camera.rotate_y(delta * 0.05) # slow orbit behind the menu
		menu_camera.look_at(Vector3(0, -1, 0))


# --- Lobby actions ---

func host_game(map_name: String) -> void:
	host_game_with(LevelBuilder.load_map(map_name))


func host_game_with(map: Dictionary) -> void:
	var err := Game.host()
	if err != OK:
		lobby.set_status("Could not host: " + error_string(err))
		lobby.visible = true
		return
	editor.deactivate()
	level.build(map)
	_enter_arena()
	_spawn_for(1)


func join_game(ip: String) -> void:
	if ip.is_empty():
		lobby.set_status("Enter the host's IP")
		return
	var err := Game.join(ip)
	if err != OK:
		lobby.set_status("Could not connect: " + error_string(err))
		return
	lobby.set_status("Connecting to %s..." % ip)
	lobby.set_busy(true)


func leave_match() -> void:
	_leave_arena("Left the match")


func open_editor() -> void:
	lobby.visible = false
	menu_camera.current = false
	level.build(level.data, true)
	editor.activate(level)


func close_editor() -> void:
	editor.deactivate()
	level.build(level.data) # rebuild without editor helpers
	menu_camera.current = true
	lobby.refresh_maps()
	lobby.visible = true


func _enter_arena() -> void:
	lobby.visible = false
	lobby.set_busy(false)
	hud.reset()
	hud.visible = true
	menu_camera.current = false


func _leave_arena(message: String) -> void:
	Game.leave()
	for p in players_root.get_children():
		p.queue_free()
	level.build(LevelBuilder.default_map())
	hud.visible = false
	lobby.visible = true
	lobby.set_busy(false)
	lobby.set_status(message)
	menu_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- Connection events ---

func _on_connected_to_server() -> void:
	lobby.set_status("Connected, loading map...")


func _on_connection_failed() -> void:
	Game.leave()
	lobby.set_busy(false)
	lobby.set_status("Connection failed. Check the IP and that the host is running.")


func _on_server_disconnected() -> void:
	_leave_arena("Host disconnected")


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		receive_map.rpc_id(id, JSON.stringify(level.data), Game.local_name)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		var p := players_root.get_node_or_null(str(id))
		if p:
			p.queue_free()


# --- Map hand-off: host sends the map, client builds it, then asks to be spawned ---

@rpc("authority", "reliable")
func receive_map(json: String, host_name: String) -> void:
	var map := LevelBuilder.parse(json)
	level.build(map)
	_keep_copy(map, host_name)
	_enter_arena()
	map_ready.rpc_id(1)


# Clients keep a copy of maps the host shares, so they can host them later
func _keep_copy(map: Dictionary, host_name: String = Game.name_of(1)) -> void:
	var map_name: String = map.get("name", "")
	if map_name.is_empty() or map_name == "Arena":
		return
	var copy_name := LevelBuilder.safe_name(map_name + " (from " + host_name + ")")
	if not LevelBuilder.list_maps().has(copy_name):
		LevelBuilder.save_map(copy_name, map.duplicate(true))
		Game.kill_feed.emit("Saved a copy of map '%s'" % map_name)


# Host switches the map mid-match: everyone rebuilds and respawns
func change_map(map_name: String) -> void:
	if not multiplayer.is_server():
		return
	var map := LevelBuilder.load_map(map_name)
	switch_map.rpc(JSON.stringify(map))


@rpc("authority", "call_local", "reliable")
func switch_map(json: String) -> void:
	var map := LevelBuilder.parse(json)
	level.build(map)
	if not multiplayer.is_server():
		_keep_copy(map)
	Game.kill_feed.emit("Map changed to '%s'" % map.get("name", "Untitled"))
	if multiplayer.is_server():
		for p in players_root.get_children():
			if p is Player:
				p.respawn.rpc(pick_spawn())


@rpc("any_peer", "reliable")
func map_ready() -> void:
	if multiplayer.is_server():
		_spawn_for(multiplayer.get_remote_sender_id())


# --- Spawning (host) ---

func _spawn_for(id: int) -> void:
	spawner.spawn({"id": id, "pos": pick_spawn()})


func _spawn_player(data: Dictionary) -> Node:
	var p: Player = PLAYER_SCENE.instantiate()
	p.name = str(data.id)
	p.set_multiplayer_authority(data.id)
	p.position = data.pos
	p.died.connect(_on_player_died)
	print("[net] spawned player %d (%s)" % [data.id, "local" if data.id == multiplayer.get_unique_id() else "remote"])
	return p


func pick_spawn() -> Vector3:
	if level.spawn_points.is_empty():
		return Vector3(0, 5, 0)
	var best: Vector3 = level.spawn_points[0]
	var best_score := -1.0
	for sp in level.spawn_points:
		var nearest := INF
		for p in players_root.get_children():
			if p is Player and not p.dead:
				nearest = min(nearest, sp.distance_to(p.sync_position))
		var score: float = nearest + randf() * 0.5
		if score > best_score:
			best_score = score
			best = sp
	return best


func _on_player_died(player: Player, _killer_id: int) -> void:
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_respawn.bind(player))


func _respawn(player: Player) -> void:
	if is_instance_valid(player) and player.is_inside_tree() and not Game.match_over:
		player.respawn.rpc(pick_spawn())


func _on_match_reset() -> void:
	if not multiplayer.is_server():
		return
	for p in players_root.get_children():
		if p is Player:
			p.respawn.rpc(pick_spawn())


# --- Command line helpers for testing (after "--"): --host, --join=IP, --name=NAME,
# --map=NAME, --screenshot=PATH, --test-hit, --test-look, --editor ---

func _handle_cmdline() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("name"):
		Game.local_name = args["name"]
		lobby.name_edit.text = args["name"]
	if args.has("host"):
		host_game(args.get("map", ""))
	elif args.has("join"):
		join_game(args["join"] if args["join"] != "" else "127.0.0.1")
	elif args.has("editor"):
		open_editor()
	if args.has("test-hit"): # debug: kill the host every 4 s
		var t := Timer.new()
		t.wait_time = 4.0
		t.autostart = true
		add_child(t)
		t.timeout.connect(func():
			var me: Player = players_root.get_node_or_null(str(multiplayer.get_unique_id()))
			var host: Player = players_root.get_node_or_null("1")
			if me and host and not host.dead:
				me._request_damage(host, 500, me.peer_id()))
	if args.has("test-look"): # debug: stand next to the host and aim at them after 2.5 s
		get_tree().create_timer(2.5).timeout.connect(func():
			var me: Player = players_root.get_node_or_null(str(multiplayer.get_unique_id()))
			var host: Player = players_root.get_node_or_null("1")
			if me and host:
				me.position = host.sync_position + Vector3(1.8, 0.2, 1.8)
				me.face_toward(host.sync_position + Vector3(0, 0.8, 0)))
	if args.has("test-pickup"): # debug: teleport onto the first pickup after 4 s
		get_tree().create_timer(4.0).timeout.connect(func():
			var me: Player = players_root.get_node_or_null(str(multiplayer.get_unique_id()))
			for piece in level.data.pieces:
				if piece.t.begins_with("pickup") and me:
					me.position = LevelBuilder._to_vec(piece.p) + Vector3(0, 0.5, 0)
					break)
	if args.has("test-changemap"): # debug: host switches map after 6 s
		get_tree().create_timer(6.0).timeout.connect(func(): change_map(args["test-changemap"]))
	if args.has("screenshot"):
		get_tree().create_timer(float(args.get("screenshot-delay", "3.0")), true).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(args["screenshot"])
			print("screenshot saved: ", args["screenshot"]))
