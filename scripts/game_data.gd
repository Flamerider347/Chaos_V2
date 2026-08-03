extends Node

signal dedicated_server_setup
signal upgrade_purchased(upgrade_name, new_level)

var score: int = 0
var power: int = 0
var current_plates: int = 0
var is_night: bool = false
var closed_lobby: bool = false
var paused: bool = false
var lost: bool = false

var username: String = ""
var room_code: String = ""
var connected: bool = false
var is_joining: bool = false
var in_game: bool = false
var join_error = null
var using_computer: bool = false

const SPOOLER_PORT := 13500
var spooler_ip := ""
var next_available_port := 13501
var game_port: int = 0
var peer = ENetMultiplayerPeer.new()
var difficulty = "easy"

const DIFFICULTY_MULTIPLIERS: Dictionary = {
	"medium_rare": 0.6, # Easy (0.6x multiplier)
	"easy": 0.6,
	"well_done": 1.0,   # Normal (1.0x multiplier)
	"normal": 1.0,
	"medium": 1.0,
	"charred": 2.0,     # Hard (2.0x multiplier)
	"hard": 2.0
}

const UPGRADES_DB: Dictionary = {
	"drop_chance": {
		"id": "drop_chance",
		"max_level": 5,
		"base_cost": 250,
		"cost_multiplier": 1.4,
		"base_value": 0.0,
		"increment": 0.10
	},
	"chop_chance": {
		"id": "chop_chance",
		"max_level": 5,
		"base_cost": 250,
		"cost_multiplier": 1.4,
		"base_value": 0.0,
		"increment": 0.10
	},
	"stack_size": {
		"id": "stack_size",
		"max_level": 7,
		"base_cost": 150,
		"cost_multiplier": 1.3,
		"base_value": 3.0,
		"increment": 1.0
	},
	"daily_recipe_buff": {
		"id": "daily_recipe_buff",
		"max_level": 4,
		"base_cost": 600,
		"cost_multiplier": 1.6,
		"base_value": 2.0,
		"increment": 0.5
	},
	"sun_stage": {
		"id": "sun_stage",
		"max_level": 3,
		"stage_costs": [500, 1500, 3000], # Easy Base Costs
		"base_value": 1.0,
		"increment": 1.0
	}
}

var upgrade_levels: Dictionary = {
	"drop_chance": 0,
	"chop_chance": 0,
	"stack_size": 0,
	"daily_recipe_buff": 0,
	"sun_stage": 0
}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game() -> void:
	peer = ENetMultiplayerPeer.new()
	
	var cmdline_user_args = OS.get_cmdline_user_args()
	if "--port" in cmdline_user_args:
		var port = int(cmdline_user_args[cmdline_user_args.find("--port") + 1])
		game_port = port
		peer.create_server(port, 4)
		dedicated_server_setup.emit()
	else:
		var port = find_port(next_available_port)
		game_port = port
		next_available_port = port + 1
		var error = peer.create_server(port, 3)
		if error != OK:
			_update_status_ui("Failed to host on port " + str(port))
			return

	multiplayer.multiplayer_peer = peer
	connected = true
	in_game = true
	room_code = get_local_ip()
	_update_status_ui("Hosting! IP: " + room_code)


func join_game(target_ip: String, port: int) -> void:
	if target_ip.strip_edges() == "":
		target_ip = "127.0.0.1" 

	is_joining = true
	_update_status_ui("Connecting...")
	
	peer = ENetMultiplayerPeer.new()
	
	var error = peer.create_client(target_ip, port)
	if error != OK:
		_on_connection_failed()
		return
	game_port = port
	multiplayer.multiplayer_peer = peer


func _on_player_connected(id: int) -> void:
	print("Player connected with network ID: ", id)


func _on_player_disconnected(id: int) -> void:
	print("Player disconnected: ", id)


func _on_connected_to_server() -> void:
	connected = true
	is_joining = false
	in_game = true
	join_error = null
	_update_status_ui("Connected!")
	
	var join_btn = get_node_or_null("/root/main_menu/menu_UI/join_button")
	if join_btn: 
		join_btn.disabled = false


func _on_connection_failed() -> void:
	peer.close()
	connected = false
	is_joining = false
	join_error = "Could not connect to host"
	_update_status_ui("Unable to join lobby :(")
	get_tree().change_scene_to_file("res://Prefabs/main_menu.tscn")


func _on_server_disconnected() -> void:
	peer.close()
	connected = false
	in_game = false
	_update_status_ui("Server disconnected.")
	get_tree().change_scene_to_file("res://Prefabs/main_menu.tscn")


func _update_status_ui(text_message: String) -> void:
	var status_node = get_node_or_null("/root/main_menu/menu_UI/status")
	if status_node: 
		status_node.text = text_message


func get_local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.contains(".") and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			return ip
	return "127.0.0.1"


func find_port(starting_port: int) -> int:
	var tester = TCPServer.new()
	var current_port = starting_port

	while current_port <= starting_port + 256:
		var error = tester.listen(current_port, "0.0.0.0")

		if error == OK:
			tester.stop()
			return current_port
		else:
			print("Port in use: " + str(current_port))
		current_port += 1
	return starting_port


func request_spooled_instance(ip: String) -> void:
	peer = ENetMultiplayerPeer.new()
	spooler_ip = ip if ip != "0" else "127.0.0.1"
	peer.create_client(spooler_ip, SPOOLER_PORT)
	multiplayer.multiplayer_peer = peer


@rpc("any_peer", "reliable")
func recieve_redirect(target_port: int) -> void:
	if OS.has_feature("server_spooler"):
		return

	multiplayer.multiplayer_peer = null
	peer.close()
	await get_tree().process_frame
	join_game(spooler_ip, target_port)


func get_difficulty_multiplier() -> float:
	return DIFFICULTY_MULTIPLIERS.get(difficulty.to_lower(), 1.0)


func get_player_count() -> int:
	var players = get_tree().get_nodes_in_group("player")
	return max(1, players.size())


func get_upgrade_cost(upgrade_name: String) -> int:
	if not UPGRADES_DB.has(upgrade_name):
		return 0
		
	var db_entry: Dictionary = UPGRADES_DB[upgrade_name]
	var current_lvl: int = upgrade_levels.get(upgrade_name, 0)
	var raw_cost: float = 0.0

	# Check for custom stage costs array
	if db_entry.has("stage_costs"):
		if current_lvl < db_entry["stage_costs"].size():
			raw_cost = db_entry["stage_costs"][current_lvl]
	else:
		var base_cost: float = db_entry["base_cost"]
		var mult: float = db_entry["cost_multiplier"]
		raw_cost = base_cost * pow(mult, current_lvl)

	# Multipliers
	var player_mult: float = 1.0 + ((get_player_count() - 1) * 0.50)
	var diff_mult: float = get_difficulty_multiplier()
	
	# Override diff_mult for Sun Stage to scale relative to custom Easy base
	if upgrade_name == "sun_stage":
		match difficulty.to_lower():
			"medium_rare", "easy":
				diff_mult = 1.0
			"well_done", "normal", "medium":
				diff_mult = 1.5
			"charred", "hard":
				diff_mult = 2.0

	return int(raw_cost * player_mult * diff_mult)


func get_upgrade_value(upgrade_name: String) -> float:
	if not UPGRADES_DB.has(upgrade_name):
		return 0.0
	var data: Dictionary = UPGRADES_DB[upgrade_name]
	var level: int = upgrade_levels.get(upgrade_name, 0)
	return data["base_value"] + (level * data["increment"])


func get_upgrade_value_text(upgrade_name: String) -> String:
	if not UPGRADES_DB.has(upgrade_name):
		return ""
		
	var current_lvl: int = upgrade_levels.get(upgrade_name, 0)
	var max_lvl: int = UPGRADES_DB[upgrade_name]["max_level"]
	
	if current_lvl >= max_lvl:
		return get_upgrade_value_at_level(upgrade_name, max_lvl)
	
	var current_val = get_upgrade_value_at_level(upgrade_name, current_lvl)
	var next_val = get_upgrade_value_at_level(upgrade_name, current_lvl + 1)
	
	return "%s -> %s" % [current_val, next_val]


func purchase_upgrade(upgrade_name: String) -> bool:
	if not UPGRADES_DB.has(upgrade_name):
		return false
		
	var cost = get_upgrade_cost(upgrade_name)
	var current_lvl = upgrade_levels.get(upgrade_name, 0)
	var max_lvl = UPGRADES_DB[upgrade_name]["max_level"]
	
	if score >= cost and current_lvl < max_lvl:
		score -= cost
		upgrade_levels[upgrade_name] = current_lvl + 1
		
		upgrade_purchased.emit(upgrade_name, upgrade_levels[upgrade_name])
		refresh_game_ui()
		return true
		
	return false


func refresh_game_ui() -> void:
	var main_node = get_node_or_null("/root/main")
	if is_instance_valid(main_node):
		if main_node.has_method("update_UI"):
			main_node.update_UI()
		if main_node.has_method("thing_ui_update"):
			main_node.thing_ui_update()

	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		if player.is_multiplayer_authority() if player.has_method("is_multiplayer_authority") else true:
			if player.has_method("update_inventory_ui"):
				player.update_inventory_ui()


func get_upgrade_value_at_level(upgrade_name: String, level: int) -> String:
	if not UPGRADES_DB.has(upgrade_name):
		return ""
		
	var db_entry: Dictionary = UPGRADES_DB[upgrade_name]
	var base_val: float = db_entry["base_value"]
	var increment: float = db_entry["increment"]
	var total_val: float = base_val + (level * increment)

	match upgrade_name:
		"drop_chance", "chop_chance":
			return str(int(total_val * 100)) + "%"
		"stack_size":
			return str(int(total_val))
		"daily_recipe_buff":
			return str(total_val) + "x"
		"sun_stage":
			return "Stage " + str(int(total_val))
		_:
			return str(total_val)
