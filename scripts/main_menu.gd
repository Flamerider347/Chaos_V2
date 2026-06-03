extends Node

@onready var menu_ui = $menu_UI
@onready var username_input: LineEdit = $menu_UI/username
@onready var join_code_input: LineEdit = $menu_UI/join_code
@onready var status_label: Label = $menu_UI/status
@onready var lobby_error_label: Label = $"menu_UI/lobby error"
@onready var lan_toggle: CheckButton = $menu_UI/lan_check

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	lobby_error_label.text = ""
	$menu_UI/join_button.disabled = false
	
	# TESTING QUALITY OF LIFE: Automatically fill IP with localhost loopback
	join_code_input.text = "127.0.0.1"
	
	# Connect to GameData's native signals to listen for live updates
	GameData.multiplayer.connected_to_server.connect(_on_network_join_success)
	GameData.multiplayer.connection_failed.connect(_on_network_join_fail)
	
	# Force LAN to be checked by default on boot
	if not lan_toggle.button_pressed:
		lan_toggle.button_pressed = true
	else:
		_on_lan_check_toggled(true)
	
	if GameData.lost:
		status_label.text = "Game lost! Please relaunch the game to host a new match."

func _on_lan_check_toggled(toggled_on: bool) -> void:
	if toggled_on:
		status_label.text = "LAN Mode Active. Enter Host IP to Join."
		join_code_input.placeholder_text = "Enter Host IP (e.g. 192.168.1.5)"
	else:
		status_label.text = "Online Mode Active. Enter Room Code to Join."
		join_code_input.placeholder_text = "Enter Online Room Code"

func _on_play_pressed() -> void:
	_assign_username()
	
	if lan_toggle.button_pressed:
		$LAN_starter.start_server()
	else:
		if has_node("WebRTC_starter"): 
			$WebRTC_starter.start_server()
			
	get_tree().change_scene_to_file("res://Prefabs/main.tscn")

func _on_join_pressed() -> void:
	_assign_username()
	status_label.text = "Connecting to lobby..."
	$menu_UI/join_button.disabled = true
	
	if lan_toggle.button_pressed:
		$LAN_starter.start_client()
	else:
		if has_node("WebRTC_starter"):
			$WebRTC_starter.start_client()

# --- Network Callback Triggers ---

func _on_network_join_success() -> void:
	status_label.text = "Connected! Loading world..."
	get_tree().change_scene_to_file("res://Prefabs/main.tscn")

func _on_network_join_fail() -> void:
	$menu_UI/join_button.disabled = false
	status_label.text = "Connection failed."
	lobby_error_label.text = "Could not reach the host machine. Double-check the IP address."

# --- UI Helpers ---
func _assign_username() -> void:
	var cleaned_name = username_input.text.strip_edges()
	
	# If empty, visually display "Player" in the line edit box and assign it globally
	if cleaned_name == "":
		username_input.text = "Player"
		GameData.username = "Player"
	else:
		GameData.username = cleaned_name
