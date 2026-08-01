extends Node3D

# --- Tileable Shop Item Database ---
# Format: "UI_Node_Name": [max_daily_stock, "prefab_item_type"]
# Easily add new items here when you duplicate nodes in your UI!
const ITEM_DB: Dictionary = {
	"Carrot": [5, "carrot"],
	"Tomato": [5, "tomato"],
	# "Potato1": [3, "potato"],
	# "Radish1": [4, "radish"],
}

# Runtime tracking for stock quantities across clients
var current_stocks: Dictionary = {}

# --- UI Onready Variables ---
@onready var score_label: Label = get_node_or_null("/root/main/UI/score_label")
@onready var day_timer_label: Label = get_node_or_null("/root/main/UI/day_timer")
@onready var current_day_label: Label = get_node_or_null("/root/main/UI/current_day")
@onready var status_label: Label = $UI/status
@onready var pause_ui = $Pause_UI
@onready var pause_room_label: Label = $Pause_UI/roomcode
@onready var main_ui = $UI
@onready var thing_ui_panel: Label3D = get_node_or_null("game/world/kitchen/thing_placement/thing_UI")

# Dedicated MultiplayerSpawners
@onready var tree_spawner: MultiplayerSpawner = get_node_or_null("game/spawners/tree_spawner")
@onready var item_spawner: MultiplayerSpawner = get_node_or_null("game/spawners/item_spawner")

# Defined boundaries for map positions
var min_spawn_bound: Vector2 = Vector2(-40, -40)
var max_spawn_bound: Vector2 = Vector2(35, 35)

# --- Gameplay Core Variables ---
var score: int = GameData.score
var power: float = GameData.power

var total_power_cost: int = 0
var current_day: int = 0
var paused: bool = false


func _ready() -> void:
	GameData.score = 0
	GameData.power = 20
	$Pause_UI/roomcode.text = "Port: " + str(GameData.game_port)
	$Pause_UI/host_ip.text = "IP:" + str(GameData.room_code)
	GameData.in_game = true
	GameData.lost = false
	paused = false
	GameData.paused = false
	$Computer_UI.hide()
	
	if is_instance_valid(pause_ui):
		pause_ui.visible = false
	if is_instance_valid(main_ui):
		main_ui.visible = true
		
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	var env_controller = get_node_or_null("environment_controller")
	if env_controller:
		env_controller.new_day.connect(_on_environment_controller_new_day)
	
	if multiplayer.multiplayer_peer and multiplayer.get_unique_id() != 0:
		if is_instance_valid(status_label): 
			status_label.text = "Match Active \nPort: " + str(GameData.game_port)
	else:
		if is_instance_valid(status_label): 
			status_label.text = "Local Match"

	if is_instance_valid(item_spawner):
		item_spawner.spawn_function = _on_custom_item_spawn_shared

	_setup_shop_ui_connections()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB and not $Computer_UI.visible:
			paused = !paused
			GameData.paused = paused
			if is_instance_valid(pause_ui): pause_ui.visible = paused
			if is_instance_valid(main_ui): main_ui.visible = !paused
			
			if paused:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func leave_computer() -> void:
	$Computer_UI.hide()
	$UI.show()
	GameData.using_computer = false
	
	var player_id_str: String = str(multiplayer.get_unique_id())
	var player = $players.get_node_or_null(player_id_str)
	
	if is_instance_valid(player):
		if player.has_method("leave_computer_UI"):
			player.leave_computer_UI()

	rpc("broadcast_free_computer")


@rpc("any_peer", "call_local", "reliable")
func broadcast_free_computer() -> void:
	GameData.using_computer = false
	get_node("/root/main/game/world/kitchen/main_kitchen/appliances/Computer/in_use").hide()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if not GameData.paused:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(_delta: float) -> void:
	if has_node("fps"):
		$UI/fps.text = "FPS: " + str(Engine.get_frames_per_second())


# --- Shop UI Signal Connections ---

func _setup_shop_ui_connections() -> void:
	var items_container = $Computer_UI/PanelContainer/Items_UI
	
	for item_node in items_container.get_children():
		var node_name = item_node.name
		if ITEM_DB.has(node_name):
			var button = item_node.get_node_or_null("cost")
			if button and button is Button:
				if not button.pressed.is_connected(_on_buy_button_pressed.bind(node_name)):
					button.pressed.connect(_on_buy_button_pressed.bind(node_name))


# --- Day Cycle & Survival Math Logic ---

func _on_environment_controller_new_day(day: int) -> void:
	current_day = day
	if is_instance_valid(current_day_label):
		current_day_label.text = "Day: " + str(current_day)
		
	if day != 1:
		total_power_cost += 10 * day 

	GameData.power = 20 + GameData.score - total_power_cost
	
	# Host randomizes daily stock per ITEM_DB max ranges and syncs to all clients
	if multiplayer.is_server():
		var new_stocks: Dictionary = {}
		for item_key in ITEM_DB.keys():
			var max_stock: int = ITEM_DB[item_key][0]
			new_stocks[item_key] = randi_range(0, max_stock)
		
		rpc("sync_daily_stock", new_stocks)
		
		if GameData.power < 0:
			rpc("burn_it_all_down")
	
	thing_ui_update()
	update_UI()


@rpc("authority", "call_local", "reliable")
func sync_daily_stock(new_stocks: Dictionary) -> void:
	current_stocks = new_stocks
	update_UI()


# --- Purchasing & Supply Drop Logic ---

func _on_buy_button_pressed(item_node_name: String) -> void:
	rpc_id(1, "request_purchase", item_node_name)


@rpc("any_peer", "call_local", "reliable")
func request_purchase(item_node_name: String) -> void:
	if not multiplayer.is_server():
		return
		
	if not ITEM_DB.has(item_node_name):
		return

	var item_node = $Computer_UI/PanelContainer/Items_UI.get_node_or_null(item_node_name)
	if not item_node:
		return
		
	var cost_node = item_node.find_child("cost")
	if not cost_node:
		return
		
	var item_cost: int = int(cost_node.text)
	var stock_available: int = current_stocks.get(item_node_name, 0)
	
	# Verify user has required Power and stock is remaining
	if GameData.power >= item_cost and stock_available > 0:
		current_stocks[item_node_name] -= 1
		GameData.power -= item_cost
		
		# Retrieve item prefab string identifier from ITEM_DB array slot 1
		var item_spawn_type: String = ITEM_DB[item_node_name][1]
		
		# Summon Supply Drop Crate on server
		spawn_supply_drop(item_spawn_type)
		
		# Update power and stock on all peers
		rpc("sync_purchase_result", item_node_name, current_stocks[item_node_name], GameData.power)


@rpc("authority", "call_local", "reliable")
func sync_purchase_result(item_node_name: String, new_stock: int, new_power: int) -> void:
	current_stocks[item_node_name] = new_stock
	GameData.power = new_power
	update_UI()


func spawn_supply_drop(item_type: String) -> void:
	var crate_scene = load("res://Prefabs/supply_drop.tscn")
	if not crate_scene:
		push_error("Failed to load res://Prefabs/supply_drop.tscn")
		return
		
	var crate_instance = crate_scene.instantiate()
	crate_instance.contents = [item_type]
	
	get_node("/root/main/game/world").add_child(crate_instance, true)


# --- Custom Spawner Handler ---

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


# --- UI Refresh & Utility Handlers ---

func thing_ui_update() -> void:
	if is_instance_valid(score_label):
		score_label.text = "Score: " + str(GameData.score)
		
	if is_instance_valid(thing_ui_panel):
		var next_night_cost = 10 * (current_day + 1)
		var power_req = GameData.power - next_night_cost
		
		if power_req < 0:
			power_req = abs(power_req)
			thing_ui_panel.text = "\nScore: " + str(GameData.score) + \
			 "\nPower left: " + str(GameData.power) + \
			 "\nPower Requirement for today: " + str(next_night_cost) + \
			 "\nYou need " + str(power_req) + " more Power to survive tonight"
		else:
			power_req = 0
			thing_ui_panel.text = "\nScore: " + str(GameData.score) + \
			 "\nPower left: " + str(GameData.power) + \
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


func _items_pressed() -> void:
	$Computer_UI/computer_tabs.flip_h = true
	$Computer_UI/PanelContainer/Items_UI.show()
	$Computer_UI/PanelContainer/Upgrades_UI.hide()


func _upgrades_pressed() -> void:
	$Computer_UI/computer_tabs.flip_h = false
	$Computer_UI/PanelContainer/Items_UI.hide()
	$Computer_UI/PanelContainer/Upgrades_UI.show()


func update_UI() -> void:
	if has_node("Computer_UI/power"):
		$Computer_UI/power.text = str(GameData.power)
	
	var items_container = $Computer_UI/PanelContainer/Items_UI
	
	for item_node in items_container.get_children():
		var node_name = item_node.name
		if not ITEM_DB.has(node_name):
			continue
			
		var cost_node = item_node.find_child("cost")
		var stock_node = item_node.find_child("stock")
		var button_red = item_node.find_child("ButtonRed")
		var button_green = item_node.find_child("ButtonGreen")
		
		if cost_node:
			var cost: int = int(cost_node.text)
			var stock: int = current_stocks.get(node_name, 0)
			
			if stock_node:
				stock_node.text = "Stock: " + str(stock)
			
			var locked: bool = (cost > GameData.power) or (stock <= 0)
			
			if button_red:
				button_red.visible = locked
			if button_green and button_green is Button:
				button_green.disabled = locked
