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

# Point this directly to your MultiplayerSpawner dedicated to trees
@onready var tree_spawner: MultiplayerSpawner = get_node_or_null("game/spawners/tree_spawner")
@onready var item_spawner: MultiplayerSpawner = get_node_or_null("game/spawners/item_spawner")

# Defined boundaries for your map positions
var min_spawn_bound: Vector2 = Vector2(-40, -40)
var max_spawn_bound: Vector2 = Vector2(35, 35)

# --- Gameplay Core Variables ---
var score: int = 0
var power: float = 100.0

var total_power_cost: int = 0
var current_day: int = 0
var paused: bool = false

func _ready() -> void:
	GameData.score = 0
	GameData.power = 0
	$Pause_UI/roomcode.text = "Port: " +str(GameData.game_port)
	$Pause_UI/host_ip.text = "IP:" +str(GameData.room_code)
	GameData.in_game = true
	GameData.lost = false
	paused = false
	GameData.paused = false
	
	if is_instance_valid(pause_ui):
		pause_ui.visible = false
	if is_instance_valid(main_ui):
		main_ui.visible = true
		
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	var env_controller = get_node_or_null("environment_controller")
	if env_controller:
		env_controller.new_day.connect(_on_environment_controller_new_day)
	
	if multiplayer.multiplayer_peer and multiplayer.get_unique_id() != 0:
		if is_instance_valid(status_label): status_label.text = "Match Active \nPort: " +str(GameData.game_port)
	else:
		if is_instance_valid(status_label): status_label.text = "Local Match"
		
	score = GameData.score
	power = GameData.power
	
	# Register custom spawner rules for the trees on all peers
# Register custom spawner rules for the trees on all peers
	# FIX: Bind the item spawner callable here so it is valid on frame one for everyone
	if is_instance_valid(item_spawner):
		item_spawner.spawn_function = _on_custom_item_spawn_shared
		
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
		$fps.text = "FPS: " + str(Engine.get_frames_per_second())

# --- Day Cycle & Survival Math Logic ---

func _on_environment_controller_new_day(day: int) -> void:
	current_day = day
	if is_instance_valid(current_day_label):
		current_day_label.text = "Day: " + str(current_day)
		
	if day != 1:
		total_power_cost += 10 * day 
	
	power = 20 + score - total_power_cost
	thing_ui_update()
	
	if multiplayer.is_server():
		if power < 0:
			rpc("burn_it_all_down")


func _on_custom_item_spawn_shared(data: Array) -> Node:
	if data.size() < 3: return null
		
	var item_type = data[0]
	var target_pos = data[2]
	var exact_name: String = str(data[3]) if data.size() >= 4 else str(item_type) + "_fallback_" + str(randi() % 100000)
	
	var item_path: String = "res://Prefabs/" + str(item_type) + ".tscn"
	if not ResourceLoader.exists(item_path): return null
		
	var item_instance = load(item_path).instantiate()
	item_instance.name = exact_name
	item_instance.type = str(item_type)
	item_instance.position = target_pos
	
	item_instance.set_multiplayer_authority(1)
	item_instance.add_to_group("pickupable")
	
	return item_instance

func thing_ui_update() -> void:
	if is_instance_valid(score_label):
		score_label.text = "Score: " + str(score)
		
	if is_instance_valid(thing_ui_panel):
		var next_night_cost = 10 * (current_day + 1)
		var power_req = power - next_night_cost
		
		if power_req < 0:
			power_req = abs(power_req)
			thing_ui_panel.text = "\nScore: " + str(score) + \
			 "\nPower left: " + str(power) + \
			 "\nPower Requirement for today: " + str(next_night_cost) + \
			 "\nYou need " + str(power_req) + " more Power to survive tonight"

		else:
			power_req = 0
			thing_ui_panel.text = "\nScore: " + str(score) + \
			 "\nPower left: " + str(power) + \
			 "\nPower Requirement for today: " + str(next_night_cost) + \
			 "\nYou will survive tonight"

@rpc("authority", "call_local", "reliable")
func burn_it_all_down() -> void:
	GameData.lost = true
	GameData.in_game = false
	
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		
	get_tree().change_scene_to_file("res://Prefabs/main_menu.tscn")


func _on_copybutton_pressed() -> void:
	if GameData.room_code and GameData.game_port:
		var copy_code = str(GameData.room_code) + "///" + str(GameData.game_port)
		DisplayServer.clipboard_set(copy_code)
