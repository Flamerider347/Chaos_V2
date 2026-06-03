extends Node

var room_code: String = ""
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

func _ready() -> void:
	# Bind native Godot network signals
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# This function bridges your menu starters to your global network state
func set_network_peer(peer: ENetMultiplayerPeer, is_host: bool) -> void:
	multiplayer.multiplayer_peer = peer
	connected = true
	in_game = true
	
	if is_host:
		room_code = get_local_ip()
		print("Hosting! Friends can join via IP: ", room_code)
	else:
		is_joining = true
		print("Attempting to connect to host...")

# --- Native Godot Network Signals ---

func _on_player_connected(id: int) -> void:
	print("Player connected with network ID: ", id)

func _on_player_disconnected(id: int) -> void:
	print("Player disconnected: ", id)

func _on_connected_to_server() -> void:
	is_joining = false
	join_error = null
	print("Successfully connected to host server!")

func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connected = false
	is_joining = false
	join_error = "Connection failed"
	get_tree().change_scene_to_file("res://Prefabs/main_menu.tscn")

func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	connected = false
	in_game = false
	get_tree().change_scene_to_file("res://Prefabs/main_menu.tscn")

# --- Helper to display local IP automatically ---
func get_local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.contains(".") and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			return ip
	return "127.0.0.1"
