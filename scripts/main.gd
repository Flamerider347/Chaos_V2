extends Node3D

# --- UI Onready Variables ---
@onready var score_label: Label = get_node_or_null("/root/main/UI/score_label")
@onready var day_timer_label: Label = get_node_or_null("/root/main/UI/day_timer")
@onready var current_day_label: Label = get_node_or_null("/root/main/UI/current_day")
@onready var status_label: Label = $UI/status
@onready var pause_ui = $Pause_UI
@onready var pause_room_label: Label = $Pause_UI/roomcode
@onready var main_ui = $UI
@onready var thing_ui_panel: Label3D = get_node_or_null("game/world/kitchen/thing_placement/thing_UI")

# --- Gameplay Core Variables ---
var score: int = 0:
	set(val):
		score = val
		GameData.score = val
		thing_ui_update()

var power: float = 100.0:
	set(val):
		power = val
		GameData.power = round(val)
		thing_ui_update()

var total_power_cost: int = 0
var current_day: int = 0
var paused: bool = false

func _ready() -> void:
	GameData.in_game = true
	GameData.lost = false
	
	# 1. Force the game state variables to be completely unpaused on boot
	paused = false
	GameData.paused = false
	
	# 2. Visually hide the pause menu and show the primary gameplay HUD
	if is_instance_valid(pause_ui):
		pause_ui.visible = false
	if is_instance_valid(main_ui):
		main_ui.visible = true
		
	# 3. CRITICAL: Explicitly trap the mouse cursor immediately so movement works on frame one
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Connect to environment controller if it exists in your scene tree
	var env_controller = get_node_or_null("environment_controller")
	if env_controller:
		env_controller.new_day.connect(_on_environment_controller_new_day)
	
	# Initialize Networking Display text safely
	if multiplayer.multiplayer_peer and multiplayer.get_unique_id() != 0:
		if is_instance_valid(status_label): status_label.text = "Match Active"
		if is_instance_valid(pause_room_label): pause_room_label.text = "Online Session"
	else:
		if is_instance_valid(status_label): status_label.text = "Local Match"
		
	# Fallback data sync on load
	score = GameData.score
	power = GameData.power
	thing_ui_update()
	
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			paused = !paused
			GameData.paused = paused
			if is_instance_valid(pause_ui): pause_ui.visible = paused
			if is_instance_valid(main_ui): main_ui.visible = !paused
			
			if paused:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if not GameData.paused:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(_delta: float) -> void:
	if has_node("fps"):
		$fps.text = "FPS: " +str(Engine.get_frames_per_second())

# --- Day Cycle & Survival Math Logic ---

func _on_environment_controller_new_day(day: int) -> void:
	current_day = day
	
	# Match display label if tracked by this script
	if is_instance_valid(current_day_label):
		current_day_label.text = "Day: " + str(current_day)
		
	if day != 1:
		total_power_cost += 10 * day 
	
	# Base baseline power recovery/calculation adjustments 
	power = 100 + score - total_power_cost
	thing_ui_update()
	
	# Server validates resources and handles game over synchronization
	if multiplayer.is_server():
		if power < 0:
			rpc("burn_it_all_down")

func thing_ui_update() -> void:
	# 1. Update general score tracking UI element
	if is_instance_valid(score_label):
		score_label.text = "Score: " + str(score)
		
	# 2. Update dynamic survival display readout text box
	if is_instance_valid(thing_ui_panel):
		var next_night_cost = 10 * (current_day + 1)
		var power_req = power - next_night_cost
		
		if power_req < 0:
			power_req = abs(power_req)
		else:
			power_req = 0
			
		thing_ui_panel.text = "\nScore: " + str(score) + \
							 "\nPower left: " + str(power) + \
							 "\nPower needed to survive next night: " + str(next_night_cost) + \
							 "\nYou need " + str(power_req) + " more Power to survive tonight"

# --- Host Native Defeat Protocol ---

@rpc("authority", "call_local", "reliable")
func burn_it_all_down() -> void:
	GameData.lost = true
	GameData.in_game = false
	
	# Tear down network connection cleanly
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		
	get_tree().change_scene_to_file("res://Prefabs/main_menu.tscn")
