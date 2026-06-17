extends Node

@onready var menu_ui = $menu_UI
@onready var username_input: LineEdit = $menu_UI/username
@onready var join_code_input: LineEdit = $menu_UI/LAN_menu/join_code
@onready var status_label: Label = $menu_UI/status
@onready var lobby_error_label: Label = $"menu_UI/lobby error"

# --- Sky Shader & Lighting Additions ---
@export var day_length_seconds: float = 30.0
@onready var sun_light: DirectionalLight3D = $DirectionalLight3D
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var night_light: OmniLight3D = $nightlight

var current_time: float = 0.25
# --------------------------------------

func _ready() -> void:
	$Camera3D.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	lobby_error_label.text = ""
	for i in $menu_UI.get_children():
		if not i.is_in_group("donthide"):
			i.hide()
	$menu_UI/start_menu.show()
	# TESTING QUALITY OF LIFE: Automatically fill IP with localhost loopback
	#join_code_input.text = "127.0.0.1"
	
	# Connect to GameData's native signals to listen for live updates
	GameData.multiplayer.connected_to_server.connect(_on_network_join_success)
	GameData.multiplayer.connection_failed.connect(_on_network_join_fail)
	
	if GameData.lost:
		status_label.text = "Game lost! Please relaunch the game to host a new match."
		
	# Initial background shader frame setup
	update_sky_and_lighting()

# --- Process Loop for Menu Sky Shader ---
func _process(delta: float) -> void:
	# Advance time smoothly for the menu preview loop
	current_time += delta / day_length_seconds
	if current_time > 1.0:
		current_time = 0.0
		
	update_sky_and_lighting()

func _on_lan_check_toggled(toggled_on: bool) -> void:
	if toggled_on:
		status_label.text = "LAN Mode Active. Enter Host IP to Join."
		join_code_input.placeholder_text = "Enter Host IP (e.g. 192.168.1.5)"
	else:
		status_label.text = "Online Mode Active. Enter Room Code to Join."
		join_code_input.placeholder_text = "Enter Online Room Code"


func _on_LAN_pressed() -> void:
	$menu_UI/LAN_menu.show()
	$menu_UI/start_menu.hide()


func _on_play_pressed() -> void:
	_assign_username()
	
	$LAN_starter.start_server()
	get_tree().change_scene_to_file("res://Prefabs/main.tscn")

func _on_join_pressed() -> void:
	_assign_username()
	status_label.text = "Connecting to lobby..."
	$menu_UI/LAN_menu/join_button.disabled = true
	$timeout_timer.start(15)

	$LAN_starter.start_client($menu_UI/LAN_menu/port.text.strip_edges(),$menu_UI/LAN_menu/join_code.text.strip_edges())

# --- Network Callback Triggers ---

func _on_network_join_success() -> void:
	# Stop the timer so it doesn't trigger a failure after we successfully connect
	$timeout_timer.stop()
	status_label.text = "Connected! Loading world..."
	get_tree().change_scene_to_file("res://Prefabs/main.tscn")

func _on_network_join_fail() -> void:
	$timeout_timer.stop()
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

func _on_spool_server_pressed():
	var target_code_node = $menu_UI/LLAN_menu/join_code
	if not target_code_node: return

	var target_ip: String = target_code_node.text.strip_edges()
	print(target_ip)
	GameData.request_spooled_instance(target_ip)
	
# --- Background Sky/Lighting Driver Function ---
func update_sky_and_lighting() -> void:
	if not is_instance_valid(sun_light) or not is_instance_valid(world_env): return

	var sun_angle = current_time * TAU + (TAU / 4.0)
	sun_light.rotation.x = sun_angle
	sun_light.rotation.y = deg_to_rad(25.0) 
	
	var sun_fade: float = 0.0
	var sunset_blend: float = 0.0
	
	if current_time >= 0.25 and current_time < 0.3333:
		sun_fade = smoothstep(0.25, 0.3333, current_time) * 0.4
		sunset_blend = 1.0
	elif current_time >= 0.3333 and current_time < 0.4167:
		sun_fade = lerp(0.4, 1.2, smoothstep(0.3333, 0.4167, current_time))
		sunset_blend = smoothstep(0.4167, 0.3333, current_time)
	elif current_time >= 0.4167 and current_time < 0.6667:
		sun_fade = 1.2
		sunset_blend = 0.0
	elif current_time >= 0.6667 and current_time < 0.75:
		sun_fade = 1.2
		sunset_blend = smoothstep(0.6667, 0.75, current_time)
	elif current_time >= 0.75 and current_time < 0.9167:
		sun_fade = smoothstep(0.9167, 0.75, current_time) * 0.3
		sunset_blend = smoothstep(0.9167, 0.75, current_time)

	var is_night_preview = (current_time >= 0.8333333 or current_time < 0.25)
	sun_light.light_energy = sun_fade
	sun_light.light_color = Color(0.05, 0.05, 0.15) if is_night_preview else Color(1.0, 0.95, 0.85).lerp(Color(0.95, 0.45, 0.15), sunset_blend)

	var env = world_env.environment
	if env:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		var night_weight = 1.0 - (sun_fade / 1.2)
		env.ambient_light_color = Color(0.6, 0.7, 0.8).lerp(Color(0.2, 0.25, 0.35), night_weight)
		env.ambient_light_energy = lerp(1.0, 0.6, night_weight)

	if is_instance_valid(night_light):
		night_light.light_energy = (1.0 - (sun_fade / 1.2)) * 2.0


func _on_timeout_timer_timeout() -> void:
	# Clear multiplayer peer to cleanly kill the pending connection loop
	if is_instance_valid(multiplayer) and multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
		
	$menu_UI/join_button.disabled = false
	status_label.text = "Connection failed."
	lobby_error_label.text = "Connection timed out after 15 seconds."


func start_menu() -> void:
	$menu_UI/LAN_menu.hide()
	$menu_UI/LLAN_menu.hide()
	$menu_UI/start_menu.show()


func _on_LLAN_pressed() -> void:
	$menu_UI/LLAN_menu.show()
	$menu_UI/start_menu.hide()


func _on_copy_code_text_changed(new_text: String) -> void:
	# 1. Clean up any accidental trailing spaces or newlines
	var clean_text = new_text.strip_edges()
	
	# 2. Only attempt to parse if the text actually contains your custom separator
	if clean_text.contains("///"):
		# This splits the string into an array. 
		# e.g., "192.168.1.5///25565" becomes ["192.168.1.5", "25565"]
		var parts: PackedStringArray = clean_text.split("///")
		
		# 3. Double check that we successfully got exactly two pieces
		if parts.size() == 2:
			var target_ip: String = parts[0]
			var target_port: int = int(parts[1]) # Convert the port string back to an integer
			$menu_UI/LAN_menu/join_code.text = target_ip
			$menu_UI/LAN_menu/port.text = str(target_port)
			$menu_UI/enter.show()
	else:
		$menu_UI/copy_code.text = ""
		$menu_UI/copy_code.placeholder_text = "Please paste the code in"
		$menu_UI/enter.hide()
