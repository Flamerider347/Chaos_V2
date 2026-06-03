extends Node

# --- Preserved Original State Variables ---
var room_code: String = "" # For LAN, we can repurpose this or use IPs
var username: String = ""
var closed_lobby = false
var paused: bool = false
var connected: bool = false
var is_joining: bool = false
var in_game: bool = false
var join_error = null
var is_night = false
var lost = false
var current_plates = 0

# --- Native LAN Configuration ---
const DEFAULT_PORT = 25565 # Standard game port, usually open on LANs
var peer = ENetMultiplayerPeer.new()

func _ready() -> void:
	# Bind native Godot multiplayer signals
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# --- Host Logic (Creating the "Lobby") ---
func host_game() -> void:
	var error = peer.create_server(DEFAULT_PORT, 4) # Max 4 players
	if error != OK:
		print("Cannot host: ", error)
		_update_status_ui("Failed to host on port " + str(DEFAULT_PORT))
		return
		
	multiplayer.multiplayer_peer = peer
	connected = true
	in_game = true
	room_code = get_local_ip() # Show the host's IP so school friends can type it
	
	print("Hosting LAN game. Tell friends to connect to: ", room_code)
	_update_status_ui("Hosting! IP: " + room_code)

# --- Client Logic (Joining the "Lobby") ---
func join_game(target_ip: String) -> void:
	if target_ip.strip_edges() == "":
		target_ip = "127.0.0.1" # Default to localhost if empty
		
	is_joining = true
	_update_status_ui("Connecting...")
	
	var error = peer.create_client(target_ip, DEFAULT_PORT)
	if error != OK:
		print("Cannot initiate connection: ", error)
		_on_connection_failed()
		return
		
	multiplayer.multiplayer_peer = peer

# --- Godot Network Signal Callbacks ---

# Called on Server AND Clients when a new peer connects
func _on_player_connected(id: int) -> void:
	print("Player connected with network ID: ", id)
	# This replaces your old GDSync room stabilization frame
	if multiplayer.is_server() and closed_lobby:
		# If you want to refuse connections later, you can manage it here
		pass

# Called on Server AND Clients when someone leaves
func _on_player_disconnected(id: int) -> void:
	print("Player disconnected: ", id)

# Called ONLY on Client when they successfully catch the server
func _on_connected_to_server() -> void:
	connected = true
	is_joining = false
	in_game = true
	join_error = null
	_update_status_ui("Connected!")
	
	# Enable your main menu UI buttons if necessary
	var join_btn = get_node_or_null("/root/main_menu/menu_UI/join_button")
	if join_btn: join_btn.disabled = false

# Called ONLY on Client if connection to server fails
func _on_connection_failed() -> void:
	peer.close()
	connected = false
	is_joining = false
	join_error = "Could not connect to host"
	_update_status_ui("Unable to join lobby :(")
	get_tree().change_scene_to_file("res://Prefabs/main_menu.tscn")

# Called ONLY on Client if Host shuts down game
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

# Helper function to grab the Host's IPv4 address automatically
func get_local_ip() -> String:
	for ip in IP.get_local_addresses():
		# Filter out IPv6 loops and local virtual adaptors
		if ip.contains(".") and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			return ip
	return "127.0.0.1"
