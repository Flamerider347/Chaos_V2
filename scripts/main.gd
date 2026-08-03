extends Node3D

# Base costs mapped for each item type
const ITEM_PRICES: Dictionary = {
	"Meat": 15,
	"Carrot": 10,
	"Tomato": 10,
	"Lettuce": 10,
	"Cheese": 10,
	"Bun": 15,
	"Flashlight": 20
}

const ITEM_DB: Dictionary = {
	"Meat": [5, "meat"],
	"Carrot": [5, "carrot"],
	"Tomato": [5, "tomato"],
	"Lettuce": [3, "lettuce"],
	"Cheese": [4, "cheese"],
	"Bun": [4, "bun"],
	"Flashlight": [5, "flashlight"]
}

var current_stocks: Dictionary = {}

@onready var score_label: Label = get_node_or_null("/root/main/UI/score_label")
@onready var day_timer_label: Label = get_node_or_null("/root/main/UI/day_timer")
@onready var current_day_label: Label = get_node_or_null("/root/main/UI/current_day")
@onready var status_label: Label = $UI/status
@onready var pause_ui = $Pause_UI
@onready var pause_room_label: Label = $Pause_UI/roomcode
@onready var main_ui = $UI
@onready var thing_ui_panel: Label3D = get_node_or_null("game/world/kitchen/thing_placement/thing_UI")

@onready var tree_spawner: MultiplayerSpawner = get_node_or_null("game/spawners/tree_spawner")
@onready var item_spawner: MultiplayerSpawner = get_node_or_null("game/spawners/item_spawner")
@onready var power_toggle = get_node_or_null("/root/main/computer_UI/power_toggle")

var min_spawn_bound: Vector2 = Vector2(-40, -40)
var max_spawn_bound: Vector2 = Vector2(35, 35)

var score: int = GameData.score
var power: float = GameData.power
var current_day: int = 0
var paused: bool = false


func _ready() -> void:
	GameData.score = 0
	GameData.power = 100
	$Pause_UI/roomcode.text = "Port: " + str(GameData.game_port)
	$Pause_UI/host_ip.text = "IP:" + str(GameData.room_code)
	GameData.in_game = true
	GameData.lost = false
	paused = false
	GameData.paused = false
	$computer_UI.hide()
	
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

	if is_instance_valid(power_toggle):
		if not power_toggle.toggled.is_connected(_on_power_toggle_toggled):
			power_toggle.toggled.connect(_on_power_toggle_toggled)

	_setup_shop_ui_connections()
	_setup_upgrade_ui_connections()


func _on_power_toggle_toggled(_button_pressed: bool) -> void:
	update_UI()


func get_effective_power() -> int:
	if is_instance_valid(power_toggle) and power_toggle.button_pressed:
		var tonight_tax: int = calculate_daily_power_cost(current_day + 1)
		return max(0, GameData.power - tonight_tax)
	return GameData.power


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB and not $computer_UI.visible:
			paused = !paused
			GameData.paused = paused
			if is_instance_valid(pause_ui): pause_ui.visible = paused
			if is_instance_valid(main_ui): main_ui.visible = !paused
			
			if paused:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func leave_computer() -> void:
	$computer_UI.hide()
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


func _setup_shop_ui_connections() -> void:
	var items_container = get_node_or_null("computer_UI/shop_container/UI_margins/Items_UI")
	if not items_container:
		return

	for item_node in items_container.get_children():
		var node_name = item_node.name
		if ITEM_DB.has(node_name):
			var button = item_node.get_node_or_null("cost")
			if button and button is Button:
				if not button.pressed.is_connected(_on_buy_button_pressed.bind(node_name)):
					button.pressed.connect(_on_buy_button_pressed.bind(node_name))


func _setup_upgrade_ui_connections() -> void:
	var upgrades_container = get_node_or_null("computer_UI/shop_container/UI_margins/Upgrades_UI")

	if not upgrades_container:
		return

	for upgrade_node in upgrades_container.get_children():
		var node_name = upgrade_node.name
		if GameData.UPGRADES_DB.has(node_name):
			var button = upgrade_node.get_node_or_null("cost")
			if button and button is Button:
				if not button.pressed.is_connected(_on_upgrade_button_pressed.bind(node_name)):
					button.pressed.connect(_on_upgrade_button_pressed.bind(node_name))


func calculate_daily_power_cost(day: int) -> int:
	if day <= 1:
		return 0 # Day 1 Grace Period
	
	var diff_str: String = GameData.difficulty.to_lower()
	
	var base_cost: float = 150.0
	var growth_rate: float = 1.32
	
	# Custom exponential growth rate curves per difficulty
	match diff_str:
		"medium_rare", "easy":
			base_cost = 100.0
			growth_rate = 1.22  # Grows gently (~600 power by Day 10)
		"well_done", "normal", "medium":
			base_cost = 150.0
			growth_rate = 1.35  # Moderate curve (~2,200 power by Day 10)
		"charred", "hard":
			base_cost = 220.0
			growth_rate = 1.48  # Aggressive exponential curve (~5,000 power by Day 10)
	
	var raw_tax: float = base_cost * pow(growth_rate, float(day - 2))
	var player_mult: float = 1.0 + ((GameData.get_player_count() - 1) * 0.50)
	
	return int(raw_tax * player_mult)


func _on_environment_controller_new_day(day: int) -> void:
	current_day = day
	if is_instance_valid(current_day_label):
		current_day_label.text = "Day: " + str(current_day)
		
	var todays_tax: int = calculate_daily_power_cost(day)
	GameData.power -= todays_tax
	
	if multiplayer.is_server():
		var new_stocks: Dictionary = {}
		for item_key in ITEM_DB.keys():
			var max_stock: int = ITEM_DB[item_key][0]
			new_stocks[item_key] = randi_range(1, max_stock)
		
		rpc("sync_daily_stock", new_stocks)
		
		if day > 1 and GameData.power < 0:
			rpc("burn_it_all_down")
	
	thing_ui_update()
	update_UI()


@rpc("authority", "call_local", "reliable")
func sync_daily_stock(new_stocks: Dictionary) -> void:
	current_stocks = new_stocks
	update_UI()


func _on_buy_button_pressed(item_node_name: String) -> void:
	var restrict_to_spare: bool = is_instance_valid(power_toggle) and power_toggle.button_pressed
	rpc_id(1, "request_purchase", item_node_name, restrict_to_spare)


@rpc("any_peer", "call_local", "reliable")
func request_purchase(item_node_name: String, restrict_to_spare: bool = false) -> void:
	if not multiplayer.is_server():
		return
		
	if not ITEM_DB.has(item_node_name):
		return

	var item_cost: int = ITEM_PRICES.get(item_node_name, 10)
	var stock_available: int = current_stocks.get(item_node_name, 0)
	
	var available_funds: int = GameData.power
	if restrict_to_spare:
		var tonight_tax: int = calculate_daily_power_cost(current_day + 1)
		available_funds = max(0, GameData.power - tonight_tax)
	
	if available_funds >= item_cost and stock_available > 0:
		current_stocks[item_node_name] -= 1
		GameData.power -= item_cost
		
		var item_spawn_type: String = ITEM_DB[item_node_name][1]
		spawn_supply_drop(item_spawn_type)
		
		rpc("sync_purchase_result", item_node_name, current_stocks[item_node_name], GameData.power)


@rpc("authority", "call_local", "reliable")
func sync_purchase_result(item_node_name: String, new_stock: int, new_power: int) -> void:
	current_stocks[item_node_name] = new_stock
	GameData.power = new_power
	update_UI()


func _on_upgrade_button_pressed(upgrade_node_name: String) -> void:
	var restrict_to_spare: bool = is_instance_valid(power_toggle) and power_toggle.button_pressed
	rpc_id(1, "request_upgrade_purchase", upgrade_node_name, restrict_to_spare)


@rpc("any_peer", "call_local", "reliable")
func request_upgrade_purchase(upgrade_node_name: String, restrict_to_spare: bool = false) -> void:
	if not multiplayer.is_server():
		return

	if not GameData.UPGRADES_DB.has(upgrade_node_name):
		return

	var current_lvl: int = GameData.upgrade_levels.get(upgrade_node_name, 0)
	var max_lvl: int = GameData.UPGRADES_DB[upgrade_node_name]["max_level"]

	if current_lvl >= max_lvl:
		return

	var cost: int = GameData.get_upgrade_cost(upgrade_node_name)
	
	var available_funds: int = GameData.power
	if restrict_to_spare:
		var tonight_tax: int = calculate_daily_power_cost(current_day + 1)
		available_funds = max(0, GameData.power - tonight_tax)

	if available_funds >= cost:
		GameData.power -= cost
		GameData.upgrade_levels[upgrade_node_name] += 1
		rpc("sync_upgrade_result", upgrade_node_name, GameData.upgrade_levels[upgrade_node_name], GameData.power)


@rpc("authority", "call_local", "reliable")
func sync_upgrade_result(upgrade_node_name: String, new_level: int, new_power: int) -> void:
	GameData.upgrade_levels[upgrade_node_name] = new_level
	GameData.power = new_power
	
	if upgrade_node_name == "sun_stage" and new_level >= 3:
		_trigger_victory()
	else:
		update_UI()
		_refresh_players_after_upgrade()


func _refresh_players_after_upgrade() -> void:
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		if player.has_method("update_inventory_ui"):
			player.update_inventory_ui()


func _trigger_victory() -> void:
	GameData.in_game = false
	print("Artificial Sun Ignition Complete! Victory!")
	get_tree().change_scene_to_file("res://Prefabs/victory_screen.tscn")


func spawn_supply_drop(item_type: String) -> void:
	if not multiplayer.is_server():
		return

	var drop_position := Vector3(randf_range(-50, -20), 30, randf_range(12, -12))
	var unique_name := "supply_drop_" + str(randi() % 100000)
	var package: Array = ["supply_drop", multiplayer.get_unique_id(), drop_position, unique_name, [item_type]]

	if is_instance_valid(item_spawner):
		item_spawner.spawn(package)
	else:
		push_error("item_spawner is not valid!")


func _on_custom_item_spawn_shared(data: Array) -> Node:
	if data.size() < 3: 
		return null
		
	var item_type = data[0]
	var target_pos = data[2]
	var exact_name: String = str(data[3]) if data.size() >= 4 else str(item_type) + "_fallback_" + str(randi() % 100000)
	
	var item_path: String = "res://Prefabs/" + str(item_type) + ".tscn"
	if not ResourceLoader.exists(item_path): 
		return null
		
	var item_instance = load(item_path).instantiate()
	item_instance.name = exact_name
	item_instance.position = target_pos

	if "type" in item_instance:
		item_instance.type = str(item_type)

	if data.size() >= 5 and "contents" in item_instance:
		item_instance.contents = data[4]
	
	item_instance.set_multiplayer_authority(1)
	return item_instance


func thing_ui_update() -> void:
	if is_instance_valid(score_label):
		score_label.text = "Score: " + str(GameData.score)
		
	if is_instance_valid(thing_ui_panel):
		var next_night_cost = calculate_daily_power_cost(current_day + 1)
		var power_req = GameData.power - next_night_cost
		$UI/power_req.text = "Daily Power Cost: " + str(next_night_cost)
		if power_req < 0:
			power_req = abs(power_req)
			thing_ui_panel.text = "\nScore: " + str(GameData.score) + \
			 "\nPower left: " + str(GameData.power) + \
			 "\nPower Requirement for today: " + str(next_night_cost) + \
			 "\nYou need " + str(power_req) + " more Power to survive tonight"
			$UI/power_needed.show()
			$UI/power_needed.text = "Power Needed: " + str(power_req)
		else:
			thing_ui_panel.text = "\nScore: " + str(GameData.score) + \
			 "\nPower left: " + str(GameData.power) + \
			 "\nPower Requirement for today: " + str(next_night_cost) + \
			 "\nYou will survive tonight"
			$UI/power_needed.hide()


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
	$computer_UI/computer_tabs.flip_h = true
	$computer_UI/shop_container/UI_margins/Items_UI.show()
	$computer_UI/shop_container/UI_margins/Upgrades_UI.hide()


func _upgrades_pressed() -> void:
	$computer_UI/computer_tabs.flip_h = false
	$computer_UI/shop_container/UI_margins/Items_UI.hide()
	$computer_UI/shop_container/UI_margins/Upgrades_UI.show()


func update_UI() -> void:
	if has_node("computer_UI/power"):
		var displayed_power = get_effective_power()
		$computer_UI/power.text = str(displayed_power)
	if $computer_UI/power_toggle.button_pressed:
		$computer_UI/power_type.text = "Spare power:"
	else:
		$computer_UI/power_type.text = "Total power:"
	
	update_items_UI()
	update_upgrades_UI()
	_update_3d_recipe_labels_direct()
	thing_ui_update()


func _update_3d_recipe_labels_direct() -> void:
	var buff_multiplier: float = GameData.get_upgrade_value("daily_recipe_buff")
	if buff_multiplier <= 0.0:
		buff_multiplier = 1.5

	var lbl1 = get_node_or_null("game/world/kitchen/thing_placement/recipe_of_the_day")
	var lbl2 = get_node_or_null("game/world/kitchen/thing_placement/recipe_of_the_day2")

	var r1 = RecipeManager.recipe_of_the_day
	var r2 = RecipeManager.recipe_of_the_day2

	if is_instance_valid(lbl1) and r1 != null and RecipeManager.recipes.has(r1):
		var data1 = RecipeManager.recipes[r1]
		var val1 = int(int(data1.get("value", 0)) * buff_multiplier)
		lbl1.text = "RECIPE OF THE DAY:\n%s ($%d)" % [data1.get("display_name", "Unknown"), val1]

	if is_instance_valid(lbl2) and r2 != null and RecipeManager.recipes.has(r2):
		var data2 = RecipeManager.recipes[r2]
		var val2 = int(int(data2.get("value", 0)) * buff_multiplier)
		lbl2.text = "RECIPE OF THE DAY:\n%s ($%d)" % [data2.get("display_name", "Unknown"), val2]


func update_items_UI() -> void:
	var items_container = get_node_or_null("computer_UI/shop_container/UI_margins/Items_UI")
	if not items_container:
		return
		
	var usable_power = get_effective_power()
	
	for item_node in items_container.get_children():
		var node_name = item_node.name
		if not ITEM_DB.has(node_name):
			continue
			
		var cost_node = item_node.find_child("cost")
		var stock_node = item_node.find_child("stock")
		var button_red = item_node.find_child("ButtonRed")
		var button_green = item_node.find_child("ButtonGreen")
		
		var cost: int = ITEM_PRICES.get(node_name, 10)
		var stock: int = current_stocks.get(node_name, 0)
		
		if stock_node:
			stock_node.text = "Stock: " + str(stock)
			
		var locked: bool = (cost > usable_power) or (stock <= 0)
		
		if cost_node:
			if cost_node is Button:
				cost_node.text = "-" if stock <= 0 else str(cost)
			elif cost_node is Label:
				cost_node.text = "-" if stock <= 0 else str(cost)

		if button_red:
			button_red.visible = locked
		if button_green:
			button_green.visible = not locked


func update_upgrades_UI() -> void:
	var upgrades_container = get_node_or_null("computer_UI/shop_container/UI_margins/Upgrades_UI")
	if not upgrades_container:
		return

	var usable_power = get_effective_power()

	for upgrade_node in upgrades_container.get_children():
		var node_name = upgrade_node.name
		if not GameData.UPGRADES_DB.has(node_name):
			continue

		var current_lvl: int = GameData.upgrade_levels.get(node_name, 0)
		var max_lvl: int = GameData.UPGRADES_DB[node_name]["max_level"]
		var is_maxed: bool = current_lvl >= max_lvl
		var cost: int = GameData.get_upgrade_cost(node_name)

		# Safe node fetching without 'or' expression evaluation bugs
		var cost_button = upgrade_node.get_node_or_null("cost")
		
		var level_label = upgrade_node.get_node_or_null("level")
		if level_label == null:
			level_label = upgrade_node.get_node_or_null("stock")

		var title_label = upgrade_node.get_node_or_null("title")
		if title_label == null:
			title_label = upgrade_node.get_node_or_null("name")

		var stat_label = upgrade_node.get_node_or_null("stat_label")
		if stat_label == null:
			stat_label = upgrade_node.get_node_or_null("value")

		var button_red = upgrade_node.find_child("ButtonRed")
		var button_green = upgrade_node.find_child("ButtonGreen")

		var locked: bool = is_maxed or (cost > usable_power)

		# Title handling
		if title_label and title_label is Label:
			if node_name == "sun_stage":
				title_label.text = "Artificial Sun (%d/%d)" % [current_lvl + 1, max_lvl]

		# Level label handling (Lvl 1, Lvl 2, MAX)
		if level_label and level_label is Label:
			level_label.text = "MAX" if is_maxed else "Lvl " + str(current_lvl)

		# Stat transition formatting (e.g., 10% > 20%)
		if stat_label and stat_label is Label:
			stat_label.text = GameData.get_upgrade_value_text(node_name)

		# Cost button text handling
		if cost_button and cost_button is Button:
			cost_button.text = "MAX" if is_maxed else str(cost)

		# Button UI color toggle
		if button_red:
			button_red.visible = locked
		if button_green:
			button_green.visible = not locked
