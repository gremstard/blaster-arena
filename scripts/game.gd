extends Node
# Autoload "Game": connection handling, player registry, scores, match timer, settings.
# The host (peer 1) is authoritative for the registry and scores.

const PORT := 7777
const MAX_PLAYERS := 8
const KILL_LIMIT := 15
const MATCH_SECONDS := 300
const RESTART_DELAY := 8.0
const SETTINGS_PATH := "user://settings.cfg"

const PRESET_NAMES := ["Ace", "Blaze", "Comet", "Dash", "Echo", "Frost", "Ghost", "Havoc", "Ion", "Jinx",
	"Karma", "Lynx", "Maverick", "Nova", "Onyx", "Pixel", "Quake", "Rogue", "Spark", "Titan", "Vortex", "Zed"]
const COLORS := {
	"Red": Color(0.95, 0.3, 0.3), "Orange": Color(1.0, 0.6, 0.2), "Yellow": Color(0.98, 0.9, 0.3),
	"Green": Color(0.4, 0.9, 0.45), "Cyan": Color(0.35, 0.9, 0.95), "Blue": Color(0.4, 0.55, 1.0),
	"Purple": Color(0.7, 0.45, 1.0), "Pink": Color(1.0, 0.5, 0.8),
}

signal players_changed
signal kill_feed(text: String)
signal match_ended(winner_id: int)
signal match_reset
signal announce(text: String)

var local_name := "Player"
var local_color := "Green"
var last_ip := "127.0.0.1"
var players := {} # peer_id -> {"name": String, "color": String, "kills": int, "deaths": int, "streak": int}
var match_over := false
var match_end_msec := 0 # Time.get_ticks_msec() when the match ends (local clock)
var fall_y := -14.0 # set by LevelBuilder from the lowest piece


func _ready() -> void:
	load_settings()
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _process(_delta: float) -> void:
	if multiplayer.is_server() and is_online() and not match_over and seconds_left() <= 0 and not players.is_empty():
		_finish(sorted_ids()[0])


# --- Settings ---

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		local_name = cfg.get_value("player", "name", PRESET_NAMES[randi() % PRESET_NAMES.size()])
		local_color = cfg.get_value("player", "color", COLORS.keys()[randi() % COLORS.size()])
		last_ip = cfg.get_value("net", "last_ip", "127.0.0.1")
	else:
		local_name = PRESET_NAMES[randi() % PRESET_NAMES.size()]
		local_color = COLORS.keys()[randi() % COLORS.size()]


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", local_name)
	cfg.set_value("player", "color", local_color)
	cfg.set_value("net", "last_ip", last_ip)
	cfg.save(SETTINGS_PATH)


# --- Connection ---

func host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players = {1: _entry(local_name, local_color)}
	match_over = false
	match_end_msec = Time.get_ticks_msec() + MATCH_SECONDS * 1000
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
	match_over = false
	players_changed.emit()


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func name_of(id: int) -> String:
	if id <= 0:
		return "the void"
	if players.has(id):
		return players[id].name
	return "Player %d" % id


func color_of(id: int) -> Color:
	if players.has(id) and COLORS.has(players[id].color):
		return COLORS[players[id].color]
	return Color.from_hsv(fmod(id * 0.37, 1.0), 0.65, 0.95)


func seconds_left() -> int:
	return max(0, int(ceil((match_end_msec - Time.get_ticks_msec()) / 1000.0)))


func sorted_ids() -> Array:
	var ids := players.keys()
	ids.sort_custom(func(a, b):
		if players[a].kills != players[b].kills:
			return players[a].kills > players[b].kills
		return players[a].deaths < players[b].deaths)
	return ids


func _entry(pname: String, color: String) -> Dictionary:
	return {"name": pname, "color": color, "kills": 0, "deaths": 0, "streak": 0}


func _on_connected_to_server() -> void:
	register.rpc_id(1, local_name, local_color)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and players.has(id):
		var gone: String = name_of(id)
		players.erase(id)
		sync_players.rpc(players)
		feed.rpc("%s left" % gone)


# --- Client -> host ---

@rpc("any_peer", "reliable")
func register(pname: String, color: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	pname = pname.strip_edges().left(16)
	if pname.is_empty():
		pname = "Player %d" % id
	if not COLORS.has(color):
		color = COLORS.keys()[id % COLORS.size()]
	players[id] = _entry(pname, color)
	sync_players.rpc(players)
	set_match_time.rpc_id(id, seconds_left())
	feed.rpc("%s joined" % pname)


# --- Host only ---

func record_kill(killer_id: int, victim_id: int) -> void:
	if not multiplayer.is_server() or match_over:
		return
	if players.has(victim_id):
		players[victim_id].deaths += 1
		players[victim_id].streak = 0
	var text: String
	if killer_id > 0 and killer_id != victim_id and players.has(killer_id):
		players[killer_id].kills += 1
		players[killer_id].streak += 1
		text = "%s killed %s" % [name_of(killer_id), name_of(victim_id)]
		var streak: int = players[killer_id].streak
		if streak == 3:
			shout.rpc("%s is on a killing spree!" % name_of(killer_id))
		elif streak == 5:
			shout.rpc("%s is unstoppable!" % name_of(killer_id))
		elif streak >= 8 and streak % 4 == 0:
			shout.rpc("%s is godlike!" % name_of(killer_id))
	else:
		text = "%s fell off the map" % name_of(victim_id)
	sync_players.rpc(players)
	feed.rpc(text)
	for id in players:
		if players[id].kills >= KILL_LIMIT:
			_finish(id)
			break


func _finish(winner_id: int) -> void:
	end_match.rpc(winner_id)
	get_tree().create_timer(RESTART_DELAY).timeout.connect(_restart)


func _restart() -> void:
	if multiplayer.is_server() and match_over:
		reset_match.rpc()
		set_match_time.rpc(MATCH_SECONDS)


# --- Host -> everyone (call_local so the host runs them too) ---

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
func set_match_time(seconds: int) -> void:
	match_end_msec = Time.get_ticks_msec() + seconds * 1000


@rpc("authority", "call_local", "reliable")
func end_match(winner_id: int) -> void:
	print("[net] match over, winner: ", name_of(winner_id))
	match_over = true
	match_ended.emit(winner_id)


@rpc("authority", "call_local", "reliable")
func reset_match() -> void:
	print("[net] match reset")
	for id in players:
		players[id].kills = 0
		players[id].deaths = 0
		players[id].streak = 0
	match_over = false
	players_changed.emit()
	match_reset.emit()
