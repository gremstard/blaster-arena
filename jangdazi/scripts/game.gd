extends Node
# Autoload "Game": connection, player registry, teams/classes, round state, settings.
# The host (peer 1) is authoritative for everything here.

const PORT := 7777
const MAX_PLAYERS := 10
const SETTINGS_PATH := "user://settings.cfg"

const TEAM_DEF := 0
const TEAM_ATT := 1
const TEAM_NAMES := ["Defenders", "Attackers"]
const TEAM_COLORS := [Color(0.35, 0.6, 1.0), Color(1.0, 0.45, 0.3)]

# Character classes. "model" is loaded if the file exists, otherwise a colored capsule is shown.
# "textures" + "map" apply PBR textures by material name; "hide" lists mesh names to drop
# (e.g. a gun baked into the character); "scale" fits the model to ~1.75 m.
const CLASSES := {
	"FSB Operator": {"team": TEAM_DEF, "color": Color(0.3, 0.5, 0.9),
		"model": "res://assets/fsb-operator/fsb.glb", "scale": 1.15, "yaw": 180.0,
		"textures": "res://assets/fsb-operator/textures",
		"map": {"uniform": "scp_operator_uniform", "helmet": "scp_operator_helmet", "mask": "scp_operator_mask",
			"gloves": "scp_operator_glove", "night vis goggles": "scp_operator_goggles", "pouch.002": "scp_operator_pouch",
			"boots": "boot", "face": "swat_face", "eyes": "254264-brown-eye", "fsb patch": "fsb_patch",
			"Krinkov": "krinkov_sketchfab_krinkov", "Magazine": "krinkov_sketchfab_magazine"},
		"hide": ["Gun", "Magazine", "Magazine_001", "Magazine_002", "Magazine_003", "Magazine_004", "Stock", "Plane", "Plane_001"]},
	"Free Modular": {"team": TEAM_DEF, "color": Color(0.45, 0.7, 0.95),
		"model": "res://assets/FBX/SKM_Character.fbx", "scale": 0.95, "yaw": 180.0, "textures": "", "map": {}, "hide": []},
	"Insurgent 2": {"team": TEAM_ATT, "color": Color(0.9, 0.4, 0.25),
		"model": "res://assets/characters/insurgent_2.glb", "scale": 1.0, "yaw": 180.0, "textures": "", "map": {}, "hide": []},
	"Insurgent 7": {"team": TEAM_ATT, "color": Color(0.85, 0.3, 0.45),
		"model": "res://assets/characters/insurgent_7.glb", "scale": 1.0, "yaw": 180.0, "textures": "", "map": {}, "hide": []},
}
const PRESET_NAMES := ["Ace", "Blaze", "Comet", "Dash", "Echo", "Frost", "Ghost", "Havoc", "Ion", "Jinx",
	"Karma", "Lynx", "Maverick", "Nova", "Onyx", "Pixel", "Quake", "Rogue", "Spark", "Titan", "Vortex", "Zed"]

enum Phase { LOBBY, SETUP, SIEGE, ROUND_END, MATCH_END }
const PHASE_NAMES := ["Warmup", "Setup", "Siege", "Round over", "Match over"]
var SETUP_SECONDS := 40
var SIEGE_SECONDS := 240
var ROUND_END_SECONDS := 8
var MATCH_END_SECONDS := 15
const ROUNDS_TO_WIN := 3
const CAPTURE_SECONDS := 25.0

signal players_changed
signal kill_feed(text: String)
signal announce(text: String)
signal phase_changed(phase: int)
signal round_ended(winner_team: int)
signal match_ended(winner_team: int)

var local_name := "Player"
var local_class := "FSB Operator"
var last_ip := "127.0.0.1"
var fall_y := -30.0

var players := {} # id -> {name, cls, team, alive, kills, deaths}
var phase: int = Phase.LOBBY
var round_number := 0
var wins := [0, 0]
var phase_end_msec := 0
var capture := 0.0 # 0..1 attackers' capture progress
var ring_start_msec := 0
var ring_end_msec := 0
var ring_from := 100.0
var ring_to := 12.0


func _ready() -> void:
	load_settings()
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


# --- Settings ---

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		local_name = cfg.get_value("player", "name", PRESET_NAMES[randi() % PRESET_NAMES.size()])
		local_class = cfg.get_value("player", "class", CLASSES.keys()[randi() % CLASSES.size()])
		last_ip = cfg.get_value("net", "last_ip", "127.0.0.1")
	else:
		local_name = PRESET_NAMES[randi() % PRESET_NAMES.size()]
		local_class = CLASSES.keys()[randi() % CLASSES.size()]
	if not CLASSES.has(local_class):
		local_class = CLASSES.keys()[0]


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", local_name)
	cfg.set_value("player", "class", local_class)
	cfg.set_value("net", "last_ip", last_ip)
	cfg.save(SETTINGS_PATH)


# --- Connection ---

func host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players = {1: _entry(local_name, local_class)}
	_reset_match_state()
	players_changed.emit()
	return OK


func join(ip: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	last_ip = ip
	save_settings()
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	_reset_match_state()
	players_changed.emit()


func _reset_match_state() -> void:
	phase = Phase.LOBBY
	round_number = 0
	wins = [0, 0]
	capture = 0.0
	phase_end_msec = 0


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


# --- Lookups ---

func name_of(id: int) -> String:
	if id == -2:
		return "the ring"
	if id <= 0:
		return "the void"
	if players.has(id):
		return players[id].name
	return "Player %d" % id


func class_of(id: int) -> String:
	return players[id].cls if players.has(id) else CLASSES.keys()[0]


func team_of(id: int) -> int:
	return players[id].team if players.has(id) else TEAM_DEF


func color_of(id: int) -> Color:
	var cls := class_of(id)
	return CLASSES[cls].color if CLASSES.has(cls) else Color.WHITE


func local_team() -> int:
	return team_of(multiplayer.get_unique_id())


func team_ids(team: int) -> Array:
	var out := []
	for id in players:
		if players[id].team == team:
			out.append(id)
	return out


func alive_count(team: int) -> int:
	var n := 0
	for id in players:
		if players[id].team == team and players[id].alive:
			n += 1
	return n


func seconds_left() -> int:
	return max(0, int(ceil((phase_end_msec - Time.get_ticks_msec()) / 1000.0)))


func ring_radius() -> float:
	if ring_end_msec <= ring_start_msec:
		return ring_from
	var t: float = clamp(float(Time.get_ticks_msec() - ring_start_msec) / float(ring_end_msec - ring_start_msec), 0.0, 1.0)
	return lerp(ring_from, ring_to, t)


func sorted_ids() -> Array:
	var ids := players.keys()
	ids.sort_custom(func(a, b):
		if players[a].team != players[b].team:
			return players[a].team < players[b].team
		if players[a].kills != players[b].kills:
			return players[a].kills > players[b].kills
		return players[a].deaths < players[b].deaths)
	return ids


func _entry(pname: String, cls: String) -> Dictionary:
	return {"name": pname, "cls": cls, "team": CLASSES[cls].team, "alive": true, "kills": 0, "deaths": 0}


func _on_connected_to_server() -> void:
	register.rpc_id(1, local_name, local_class)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and players.has(id):
		var gone: String = name_of(id)
		players.erase(id)
		sync_players.rpc(players)
		feed.rpc("%s left" % gone)


# --- Client -> host ---

@rpc("any_peer", "reliable")
func register(pname: String, cls: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	pname = pname.strip_edges().left(16)
	if pname.is_empty():
		pname = "Player %d" % id
	if not CLASSES.has(cls):
		cls = CLASSES.keys()[0]
	players[id] = _entry(pname, cls)
	if phase != Phase.LOBBY:
		players[id].alive = false # joined mid-round: spectate until next round
	sync_players.rpc(players)
	sync_phase.rpc(phase, seconds_left(), round_number, wins, ring_from, ring_to, max(0, ring_end_msec - Time.get_ticks_msec()))
	feed.rpc("%s joined as %s" % [pname, cls])


# --- Host only: teams, kills ---

# Balance teams while honoring class choice where possible
func assign_teams() -> void:
	var ids := players.keys()
	ids.shuffle()
	var counts := [0, 0]
	for id in ids:
		var want: int = CLASSES[players[id].cls].team
		var other := 1 - want
		var team := want
		if counts[want] > counts[other]: # would unbalance: send to the other side
			team = other
		players[id].team = team
		counts[team] += 1
		_fix_class_for_team(id)
	sync_players.rpc(players)


func swap_teams() -> void:
	for id in players:
		players[id].team = 1 - players[id].team
		_fix_class_for_team(id)
	sync_players.rpc(players)


func _fix_class_for_team(id: int) -> void:
	if CLASSES[players[id].cls].team != players[id].team:
		for cls in CLASSES:
			if CLASSES[cls].team == players[id].team:
				players[id].cls = cls
				break


func set_all_alive(alive: bool) -> void:
	for id in players:
		players[id].alive = alive
		players[id].kills = 0 if round_number == 1 else players[id].kills
	sync_players.rpc(players)


func record_kill(killer_id: int, victim_id: int) -> void:
	if not multiplayer.is_server():
		return
	if players.has(victim_id):
		players[victim_id].deaths += 1
		players[victim_id].alive = false
	var text: String
	if killer_id > 0 and killer_id != victim_id and players.has(killer_id):
		players[killer_id].kills += 1
		text = "%s killed %s" % [name_of(killer_id), name_of(victim_id)]
	elif killer_id == -2:
		text = "%s was caught outside the ring" % name_of(victim_id)
	else:
		text = "%s fell out of the city" % name_of(victim_id)
	sync_players.rpc(players)
	feed.rpc(text)


# --- Host -> everyone ---

@rpc("authority", "call_local", "reliable")
func sync_players(data: Dictionary) -> void:
	players = data
	players_changed.emit()


@rpc("authority", "call_local", "reliable")
func feed(text: String) -> void:
	kill_feed.emit(text)


@rpc("authority", "call_local", "reliable")
func shout(text: String) -> void:
	announce.emit(text)


@rpc("authority", "call_local", "reliable")
func sync_phase(new_phase: int, seconds: int, round_no: int, win_counts: Array, r_from: float, r_to: float, ring_msec_left: int) -> void:
	phase = new_phase
	round_number = round_no
	wins = win_counts.duplicate()
	phase_end_msec = Time.get_ticks_msec() + seconds * 1000
	ring_from = r_from
	ring_to = r_to
	ring_start_msec = Time.get_ticks_msec()
	ring_end_msec = ring_start_msec + ring_msec_left
	if new_phase != Phase.SIEGE:
		capture = 0.0
	print("[game] phase %s, round %d, wins %s" % [PHASE_NAMES[phase], round_number, wins])
	phase_changed.emit(phase)


@rpc("authority", "call_local", "unreliable")
func sync_capture(value: float) -> void:
	capture = value


@rpc("authority", "call_local", "reliable")
func end_round(winner_team: int) -> void:
	round_ended.emit(winner_team)


@rpc("authority", "call_local", "reliable")
func end_match(winner_team: int) -> void:
	match_ended.emit(winner_team)
