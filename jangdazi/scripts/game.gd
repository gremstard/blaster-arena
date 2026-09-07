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

# Operator classes, available to both sides. The model is tinted by team (blue = defenders).
# "model" is loaded if the file exists, otherwise a colored capsule is shown.
const CLASSES := {
	"Special Op": {"desc": "+30 HP, standard speed", "max_health": 130, "speed": 1.0,
		"model": "res://assets/fsb-operator/fsb.glb", "scale": 1.15, "yaw": 180.0,
		"textures": "res://assets/fsb-operator/textures",
		"map": {"uniform": "scp_operator_uniform", "helmet": "scp_operator_helmet", "mask": "scp_operator_mask",
			"gloves": "scp_operator_glove", "night vis goggles": "scp_operator_goggles", "pouch.002": "scp_operator_pouch",
			"boots": "boot", "face": "swat_face", "eyes": "254264-brown-eye", "fsb patch": "fsb_patch",
			"Krinkov": "krinkov_sketchfab_krinkov", "Magazine": "krinkov_sketchfab_magazine"},
		"hide": ["Gun", "Magazine", "Magazine_001", "Magazine_002", "Magazine_003", "Magazine_004", "Stock", "Plane", "Plane_001"]},
	"Basic Op": {"desc": "100 HP, +20% speed", "max_health": 100, "speed": 1.2,
		"model": "res://assets/FBX/SKM_Character.fbx", "scale": 0.95, "yaw": 180.0, "textures": "", "map": {}, "hide": []},
}
const TEAM_PREFS := ["Auto", "Defenders", "Attackers"]
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
var local_class := "Special Op"
var local_pref := 0 # 0 auto, 1 defenders, 2 attackers
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
		local_pref = int(cfg.get_value("player", "pref", 0))
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
	cfg.set_value("player", "pref", local_pref)
	cfg.set_value("net", "last_ip", last_ip)
	cfg.save(SETTINGS_PATH)


# --- Connection ---

func host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players = {1: _entry(local_name, local_class, local_pref)}
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
	return TEAM_COLORS[team_of(id)]


func max_health_of(id: int) -> int:
	return int(CLASSES[class_of(id)].max_health)


func speed_of(id: int) -> float:
	return float(CLASSES[class_of(id)].speed)


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


func _entry(pname: String, cls: String, pref: int) -> Dictionary:
	var team := TEAM_ATT if pref == 2 else TEAM_DEF
	return {"name": pname, "cls": cls, "pref": pref, "team": team, "alive": true, "kills": 0, "deaths": 0}


func _on_connected_to_server() -> void:
	register.rpc_id(1, local_name, local_class, local_pref)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and players.has(id):
		var gone: String = name_of(id)
		players.erase(id)
		sync_players.rpc(players)
		feed.rpc("%s left" % gone)


# --- Client -> host ---

@rpc("any_peer", "reliable")
func register(pname: String, cls: String, pref: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	pname = pname.strip_edges().left(16)
	if pname.is_empty():
		pname = "Player %d" % id
	if not CLASSES.has(cls):
		cls = CLASSES.keys()[0]
	players[id] = _entry(pname, cls, clampi(pref, 0, 2))
	if phase != Phase.LOBBY:
		players[id].alive = false # joined mid-round: spectate until next round
	sync_players.rpc(players)
	sync_phase.rpc(phase, seconds_left(), round_number, wins, ring_from, ring_to, max(0, ring_end_msec - Time.get_ticks_msec()))
	feed.rpc("%s joined as %s" % [pname, cls])


# --- Host only: teams, kills ---

# Balance teams while honoring side preference where possible
func assign_teams() -> void:
	var ids := players.keys()
	ids.shuffle()
	# Players with a preference go first, "Auto" players fill the gaps
	ids.sort_custom(func(a, b): return players[a].pref != 0 and players[b].pref == 0)
	var counts := [0, 0]
	for id in ids:
		var pref: int = players[id].pref
		var team: int
		if pref == 0:
			team = TEAM_DEF if counts[TEAM_DEF] <= counts[TEAM_ATT] else TEAM_ATT
		else:
			team = TEAM_DEF if pref == 1 else TEAM_ATT
			if counts[team] > counts[1 - team]: # would unbalance by 2: send to the other side
				team = 1 - team
		players[id].team = team
		counts[team] += 1
	sync_players.rpc(players)


func swap_teams() -> void:
	for id in players:
		players[id].team = 1 - players[id].team
	sync_players.rpc(players)


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
