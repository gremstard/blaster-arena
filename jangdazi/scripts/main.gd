extends Node3D
# Scene root: lobby flow, map hand-off, spawning, and the round manager (host).

const PLAYER_SCENE := preload("res://objects/player.tscn")
const LOOT_SCENE := preload("res://objects/loot.tscn")
const WARMUP_RESPAWN := 3.0
const DROP_HEIGHT := 45.0
const RING_DAMAGE := 6
const RING_DAMAGE_INTERVAL := 1.0

@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var loot_spawner: MultiplayerSpawner = $LootSpawner
@onready var players_root: Node3D = $Players
@onready var loot_root: Node3D = $Loot
@onready var level: LevelBuilder = $Level
@onready var lobby: CanvasLayer = $Lobby
@onready var hud: CanvasLayer = $HUD
@onready var editor: Node3D = $Editor
@onready var menu_camera: Camera3D = $MenuCamera
@onready var ring_mesh: MeshInstance3D = $Ring

var _ring_damage_clock := 0.0
var _capture_sync_clock := 0.0
var _round_had_team := [false, false]
var _loot_counter := 0


func _ready() -> void:
	spawner.spawn_function = _spawn_player
	loot_spawner.spawn_function = _spawn_loot
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	lobby.host_requested.connect(host_game)
	lobby.join_requested.connect(join_game)
	lobby.editor_requested.connect(open_editor)
	editor.closed.connect(close_editor)
	editor.play_requested.connect(func(map): host_game_with(map))
	hud.visible = false
	ring_mesh.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	level.build(LevelBuilder.default_map())
	_handle_cmdline()


func _process(delta: float) -> void:
	if menu_camera.current:
		menu_camera.rotate_y(delta * 0.04)
		menu_camera.look_at(Vector3(0, 2, 0))
	_update_ring_visual()
	if multiplayer.is_server() and Game.is_online():
		_host_tick(delta)


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
	_set_phase(Game.Phase.LOBBY, 0)


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
	level.build(level.data)
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
	for l in loot_root.get_children():
		l.queue_free()
	level.build(LevelBuilder.default_map())
	hud.visible = false
	ring_mesh.visible = false
	lobby.visible = true
	lobby.set_busy(false)
	lobby.set_status(message)
	menu_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- Connection events ---

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


# --- Map hand-off ---

@rpc("authority", "reliable")
func receive_map(json: String, host_name: String) -> void:
	var map := LevelBuilder.parse(json)
	level.build(map)
	_keep_copy(map, host_name)
	_enter_arena()
	map_ready.rpc_id(1)


func _keep_copy(map: Dictionary, host_name: String = Game.name_of(1)) -> void:
	var map_name: String = map.get("name", "")
	if map_name.is_empty() or map_name == "City":
		return
	var copy_name := LevelBuilder.safe_name(map_name + " (from " + host_name + ")")
	if not LevelBuilder.list_maps().has(copy_name):
		LevelBuilder.save_map(copy_name, map.duplicate(true))
		Game.kill_feed.emit("Saved a copy of map '%s'" % map_name)


@rpc("any_peer", "reliable")
func map_ready() -> void:
	if multiplayer.is_server():
		var id := multiplayer.get_remote_sender_id()
		_spawn_for(id)
		if Game.phase != Game.Phase.LOBBY:
			var p := players_root.get_node_or_null(str(id))
			if p:
				p.spectate.rpc()


func change_map(map_name: String) -> void:
	if not multiplayer.is_server() or Game.phase != Game.Phase.LOBBY:
		return
	switch_map.rpc(JSON.stringify(LevelBuilder.load_map(map_name)))


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
				p.reset_for_round.rpc(_spawn_point_for(p.peer_id(), false), false)


# --- Spawning (host) ---

func _spawn_for(id: int) -> void:
	spawner.spawn({"id": id, "pos": _spawn_point_for(id, false)})


func _spawn_player(data: Dictionary) -> Node:
	var p: Player = PLAYER_SCENE.instantiate()
	p.name = str(data.id)
	p.set_multiplayer_authority(data.id)
	p.position = data.pos
	p.died.connect(_on_player_died)
	print("[net] spawned player %d (%s)" % [data.id, "local" if data.id == multiplayer.get_unique_id() else "remote"])
	return p


func _spawn_loot(data: Dictionary) -> Node:
	var l := LOOT_SCENE.instantiate()
	l.name = "loot_%d" % data.n
	l.position = data.pos
	return l


func _spawn_point_for(id: int, drop: bool) -> Vector3:
	var team := Game.team_of(id)
	var list: Array[Vector3] = level.spawn_def if team == Game.TEAM_DEF else level.spawn_att
	if list.is_empty():
		list = level.spawn_def if not level.spawn_def.is_empty() else level.spawn_att
	var pos := Vector3(0, 5, 0) if list.is_empty() else list[randi() % list.size()]
	if drop:
		pos.y += DROP_HEIGHT
	return pos


func _on_player_died(player: Player, _killer_id: int) -> void:
	if Game.phase == Game.Phase.LOBBY:
		get_tree().create_timer(WARMUP_RESPAWN).timeout.connect(func():
			if is_instance_valid(player) and player.is_inside_tree() and Game.phase == Game.Phase.LOBBY:
				player.reset_for_round.rpc(_spawn_point_for(player.peer_id(), false), false))


# --- Round manager (host) ---

func start_match() -> void:
	if not multiplayer.is_server() or Game.phase != Game.Phase.LOBBY:
		return
	Game.round_number = 0
	Game.wins = [0, 0]
	Game.assign_teams()
	_start_round()


func _start_round() -> void:
	Game.round_number += 1
	Game.set_all_alive(true)
	for l in loot_root.get_children():
		l.queue_free()
	_round_had_team = [not Game.team_ids(0).is_empty(), not Game.team_ids(1).is_empty()]
	for p in players_root.get_children():
		if p is Player:
			p.reset_for_round.rpc(_spawn_point_for(p.peer_id(), true), true)
	_spawn_round_loot()
	Game.capture = 0.0
	_set_phase(Game.Phase.SETUP, Game.SETUP_SECONDS)
	Game.shout.rpc("Round %d. Defenders hold the zone, attackers take it." % Game.round_number)


# Center loot grows each round, outer loot shrinks
func _spawn_round_loot() -> void:
	var r := Game.round_number - 1
	var center_n: int = min(2 + 2 * r, level.loot_center.size())
	var outer_n: int = max(3, level.loot_outer.size() - 4 * r)
	outer_n = min(outer_n, level.loot_outer.size())
	for pos in _pick(level.loot_center, center_n):
		_loot_counter += 1
		loot_spawner.spawn({"n": _loot_counter, "pos": pos})
	for pos in _pick(level.loot_outer, outer_n):
		_loot_counter += 1
		loot_spawner.spawn({"n": _loot_counter, "pos": pos})
	print("[round] loot: %d center, %d outer" % [center_n, outer_n])


static func _pick(list: Array[Vector3], n: int) -> Array[Vector3]:
	var copy := list.duplicate()
	copy.shuffle()
	var out: Array[Vector3] = []
	for i in min(n, copy.size()):
		out.append(copy[i])
	return out


func _set_phase(phase: int, seconds: int) -> void:
	var ring_from: float = level.map_radius
	var ring_to: float = level.zone_radius * 2.5
	var ring_msec := 0
	if phase == Game.Phase.SIEGE:
		ring_msec = seconds * 1000
	elif phase == Game.Phase.SETUP:
		ring_to = ring_from
	Game.sync_phase.rpc(phase, seconds, Game.round_number, Game.wins, ring_from, ring_to, ring_msec)


func _host_tick(delta: float) -> void:
	var phase: int = Game.phase
	if phase == Game.Phase.LOBBY or phase == Game.Phase.MATCH_END:
		if phase == Game.Phase.MATCH_END and Game.seconds_left() <= 0:
			_back_to_warmup()
		return
	if phase == Game.Phase.ROUND_END:
		if Game.seconds_left() <= 0:
			_start_round()
		return
	# SETUP or SIEGE: elimination checks
	if _round_had_team[Game.TEAM_ATT] and Game.alive_count(Game.TEAM_ATT) == 0 and _round_had_team[Game.TEAM_DEF]:
		_finish_round(Game.TEAM_DEF, "Attackers eliminated")
		return
	if _round_had_team[Game.TEAM_DEF] and Game.alive_count(Game.TEAM_DEF) == 0 and _round_had_team[Game.TEAM_ATT]:
		_finish_round(Game.TEAM_ATT, "Defenders eliminated")
		return
	if phase == Game.Phase.SETUP:
		if Game.seconds_left() <= 0:
			_set_phase(Game.Phase.SIEGE, Game.SIEGE_SECONDS)
			Game.shout.rpc("Siege! The ring is closing.")
		return
	# SIEGE
	if Game.seconds_left() <= 0:
		_finish_round(Game.TEAM_DEF, "Defenders held out")
		return
	_tick_capture(delta)
	_tick_ring(delta)


func _tick_capture(delta: float) -> void:
	var att := 0
	var def := 0
	for p in players_root.get_children():
		if p is Player and not p.dead and _in_zone(p.sync_position):
			if p.team() == Game.TEAM_ATT:
				att += 1
			else:
				def += 1
	var before := Game.capture
	if att > 0 and def == 0:
		Game.capture = min(1.0, Game.capture + delta / Game.CAPTURE_SECONDS)
	elif att == 0:
		Game.capture = max(0.0, Game.capture - delta / (Game.CAPTURE_SECONDS * 2.0))
	_capture_sync_clock += delta
	if _capture_sync_clock >= 0.2 or (before == 0.0 and Game.capture > 0.0):
		_capture_sync_clock = 0.0
		Game.sync_capture.rpc(Game.capture)
	if Game.capture >= 1.0:
		_finish_round(Game.TEAM_ATT, "Zone captured")


func _in_zone(pos: Vector3) -> bool:
	var d := Vector2(pos.x - level.zone_center.x, pos.z - level.zone_center.z)
	return d.length() <= level.zone_radius and abs(pos.y - level.zone_center.y) < 6.0


func _tick_ring(delta: float) -> void:
	_ring_damage_clock += delta
	if _ring_damage_clock < RING_DAMAGE_INTERVAL:
		return
	_ring_damage_clock = 0.0
	var radius := Game.ring_radius()
	for p in players_root.get_children():
		if p is Player and not p.dead:
			var d := Vector2(p.sync_position.x - level.zone_center.x, p.sync_position.z - level.zone_center.z)
			if d.length() > radius:
				p.take_damage(RING_DAMAGE, -2)


func _finish_round(winner: int, reason: String) -> void:
	Game.wins[winner] += 1
	Game.end_round.rpc(winner)
	Game.shout.rpc("%s win the round: %s" % [Game.TEAM_NAMES[winner], reason])
	Game.sync_capture.rpc(0.0)
	if Game.wins[winner] >= Game.ROUNDS_TO_WIN:
		Game.end_match.rpc(winner)
		_set_phase(Game.Phase.MATCH_END, Game.MATCH_END_SECONDS)
		return
	if winner == Game.TEAM_ATT:
		Game.swap_teams() # attackers who win take the city and defend it
	_set_phase(Game.Phase.ROUND_END, Game.ROUND_END_SECONDS)


func _back_to_warmup() -> void:
	for l in loot_root.get_children():
		l.queue_free()
	Game.round_number = 0
	Game.wins = [0, 0]
	Game.set_all_alive(true)
	_set_phase(Game.Phase.LOBBY, 0)
	for p in players_root.get_children():
		if p is Player:
			p.reset_for_round.rpc(_spawn_point_for(p.peer_id(), false), false)


func _update_ring_visual() -> void:
	var show := Game.is_online() and Game.phase == Game.Phase.SIEGE
	ring_mesh.visible = show
	if show:
		var r := Game.ring_radius()
		ring_mesh.position = level.zone_center
		ring_mesh.scale = Vector3(r, 1, r)


# --- Command line helpers (after "--"): --host, --join=IP, --name, --class, --map,
# --editor, --screenshot=PATH, --screenshot-delay=N, --autostart, --test-look, --test-hit ---

func _handle_cmdline() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("name"):
		Game.local_name = args["name"]
		lobby.name_edit.text = args["name"]
	if args.has("class") and Game.CLASSES.has(args["class"]):
		Game.local_class = args["class"]
	if args.has("host"):
		host_game(args.get("map", ""))
	elif args.has("join"):
		join_game(args["join"] if args["join"] != "" else "127.0.0.1")
	elif args.has("editor"):
		open_editor()
	if args.has("fast"): # debug: short phases
		Game.SETUP_SECONDS = 6
		Game.SIEGE_SECONDS = 30
		Game.ROUND_END_SECONDS = 4
		Game.MATCH_END_SECONDS = 5
	if args.has("test-zone"): # debug: stand in the control zone once the siege starts
		Game.phase_changed.connect(func(phase):
			if phase == Game.Phase.SIEGE:
				var me: Player = players_root.get_node_or_null(str(multiplayer.get_unique_id()))
				if me:
					me.position = level.zone_center + Vector3(0, 1, 0)
					me.dropping = false)
	if args.has("autostart"):
		get_tree().create_timer(float(args.get("autostart", "5")) if args["autostart"] != "" else 5.0).timeout.connect(start_match)
	if args.has("test-hit"):
		var t := Timer.new()
		t.wait_time = 4.0
		t.autostart = true
		add_child(t)
		t.timeout.connect(func():
			var me: Player = players_root.get_node_or_null(str(multiplayer.get_unique_id()))
			var host: Player = players_root.get_node_or_null("1")
			if me and host and not host.dead:
				me._request_damage(host, 500, me.peer_id()))
	if args.has("test-look"):
		get_tree().create_timer(2.5).timeout.connect(func():
			var me: Player = players_root.get_node_or_null(str(multiplayer.get_unique_id()))
			var host: Player = players_root.get_node_or_null("1")
			if me and host:
				me.position = host.sync_position + Vector3(1.8, 0.2, 1.8)
				me.face_toward(host.sync_position + Vector3(0, 0.8, 0)))
	if args.has("screenshot"):
		get_tree().create_timer(float(args.get("screenshot-delay", "3.0")), true).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(args["screenshot"])
			print("screenshot saved: ", args["screenshot"]))
