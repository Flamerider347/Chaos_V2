extends Node

signal dedicated_server_setup

# --- Core Gameplay States ---
var score: int = 0
var power: int = 0
var current_plates: int = 0
var is_night: bool = false
var closed_lobby: bool = false
var paused: bool = false
var lost: bool = false

# --- Network & Identity States ---
var username: String = ""
var room_code: String = ""
var connected: bool = false
var is_joining: bool = false
var in_game: bool = false
var join_error = null

# --- Native LAN Configuration ---
const SPOOLER_PORT := 13500
var spooler_ip := ""
var next_available_port := 13501
var game_port: int = 0
var peer = ENetMultiplayerPeer.new()

func _ready() -> void:
	# Bind native Godot multiplayer signals to handle connections
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# --- Host Logic (Creating the Lobby) ---
func host_game() -> void:
	# CRITICAL: Always instantiate a clean peer instance before creating a server
	peer = ENetMultiplayerPeer.new()
	
	var cmdline_user_args = OS.get_cmdline_user_args()
	print(cmdline_user_args)
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

# --- Client Logic (Joining the Lobby) ---
func join_game(target_ip: String, port: int) -> void:
	if target_ip.strip_edges() == "":
		target_ip = "127.0.0.1" 
	if port == 0:
		port = 13501
		
	is_joining = true
	_update_status_ui("Connecting...")
	
	# CRITICAL: Always instantiate a clean peer instance before creating a client
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
	if join_btn: join_btn.disabled = false

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

# --- Helper Functions ---

func _update_status_ui(text_message: String) -> void:
	var status_node = get_node_or_null("/root/main_menu/menu_UI/status")
	if status_node: 
		status_node.text = text_message

# Helper function to grab the Host's IPv4 address automatically for LAN connection
func get_local_ip() -> String:
	for ip in IP.get_local_addresses():
		# Filter out IPv6 loops and local virtual adaptors
		if ip.contains(".") and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			return ip
	return "127.0.0.1"

func find_port(starting_port):
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

func request_spooled_instance(ip):
	print("request found")
	peer = ENetMultiplayerPeer.new()
	spooler_ip = ip if ip != "0" else "127.0.0.1"
	peer.create_client(spooler_ip, SPOOLER_PORT)
	multiplayer.multiplayer_peer = peer


@rpc("any_peer", "reliable")
func recieve_redirect(target_port):
	if OS.has_feature("server_spooler"):
		return
	print("Recived Redirect! Going to port: " + str(target_port))

	multiplayer.multiplayer_peer = null
	peer.close()
	await get_tree().process_frame
	GameData.join_game(spooler_ip, target_port)
