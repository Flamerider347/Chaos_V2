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

var current_trees = {
	"Tomato" : [],
	"Cheese" : [],
	"Bun" : [],
	"Meat" : [],
	"Carrot" : [],
	"Lettuce" : []
}

# Mapping types to their distinct variations
var tree_prefabs = {
	"Tomato" : ["res://Prefabs/tree_1_tomato.tscn", "res://Prefabs/tree_2_tomato.tscn", "res://Prefabs/tree_3_tomato.tscn"],
	"Cheese" : ["res://Prefabs/tree_1_cheese.tscn"],
	"Bun" : ["res://Prefabs/tree_1_bun.tscn","res://Prefabs/tree_2_bun_2.tscn"],
	"Meat" : ["res://Prefabs/tree_1_meat.tscn"],
	"Carrot" : ["res://Prefabs/tree_1_carrot_1.tscn"],
	"Lettuce" : ["res://Prefabs/tree_1_lettuce_1.tscn"]
}

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
	if is_instance_valid(tree_spawner):
		tree_spawner.spawn_function = _on_tree_spawn_custom
		
	# FIX: Bind the item spawner callable here so it is valid on frame one for everyone
	if is_instance_valid(item_spawner):
		item_spawner.spawn_function = _on_custom_item_spawn_shared
		
	if multiplayer.is_server():
		grow_a_garden()
	
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
		else:
			# Automatically regenerate fallen trees at the start of a new day
			grow_a_garden()

func grow_a_garden() -> void:
	if not multiplayer.is_server(): return
	
	# Define your kitchen boundaries (Adjust these vectors to fit your kitchen's size!)
	var kitchen_min: Vector2 = Vector2(-15.0, -12.0)
	var kitchen_max: Vector2 = Vector2(15.0, 12.0)
	
	for type in current_trees.keys():
		var current_count = current_trees[type].size()
		
		while current_count < 4:
			var variations = tree_prefabs[type]
			var chosen_prefab_path = variations[randi() % variations.size()]
			
			var spawn_pos: Vector3 = Vector3.ZERO
			var valid_position: bool = false
			
			# Keep picking a position until it lands outside the kitchen bounds
			while not valid_position:
				var rand_x = randf_range(min_spawn_bound.x, max_spawn_bound.x)
				var rand_z = randf_range(min_spawn_bound.y, max_spawn_bound.y)
				
				# Check if the picked coordinate is inside the kitchen zone
				if rand_x >= kitchen_min.x and rand_x <= kitchen_max.x and rand_z >= kitchen_min.y and rand_z <= kitchen_max.y:
					continue # It's in the kitchen! Loop again to try a different spot.
				
				spawn_pos = Vector3(rand_x, 0.0, rand_z)
				valid_position = true
			
			var unique_name = "Tree_" + type + "_" + str(randi() % 100000)
			var data_packet = [chosen_prefab_path, spawn_pos, unique_name, type]
			
			if is_instance_valid(tree_spawner):
				tree_spawner.spawn(data_packet)
				
			current_count += 1

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
	item_instance.add_to_group("plate_stackable")
	item_instance.add_to_group("pickupable")
	
	return item_instance
func _on_tree_spawn_custom(data: Array) -> Node:
	var path = data[0]
	var pos = data[1]
	var node_name = data[2]
	var type = data[3]
	
	if not ResourceLoader.exists(path):
		return null
		
	var tree_instance = load(path).instantiate()
	tree_instance.name = node_name
	
	# FIXED: Changing this to local .position stops the "!is_inside_tree()" engine error
	tree_instance.position = pos
	
	if not current_trees[type].has(tree_instance):
		current_trees[type].append(tree_instance)
		
	return tree_instance

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
