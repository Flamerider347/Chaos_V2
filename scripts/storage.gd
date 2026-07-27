extends Node3D

var valid_food_types: Array[String] = ["cheese", "tomato", "bun", "meat", "carrot", "lettuce"]
@export var stocks: Dictionary = {}

var item_spawn_pos: Vector3

@onready var item_spawner: MultiplayerSpawner = get_node("/root/main/game/spawners/item_spawner")

func _ready() -> void:
	for food_type in valid_food_types:
		stocks[food_type] = []

	if has_node("spawn_point"):
		item_spawn_pos = $spawn_point.global_position

	# Connect display buttons
	for type in valid_food_types:
		var display_node = get_node_or_null("main_display/" + type)
		if display_node:
			display_node.spawn_item.connect(request_spawn_item)

	var plate_display = get_node_or_null("main_display/plate")
	if plate_display:
		plate_display.spawn_item.connect(request_spawn_item)


func _on_input_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server() or not is_instance_valid(body) or not "type" in body:
		return

	var type = body.type
	if body is RigidBody3D:
		if type in valid_food_types:
			if stocks[type].has(body): return
			
			body.set_multiplayer_authority(1)
			stocks[type].append(body)
			rpc("store_item", body.get_path())
			rpc("sync_display_count", type, stocks[type].size())
		elif type == "plate" and "stacked_items" in body and body.stacked_items.size() == 0:
			body.queue_free()
			GameData.current_plates = max(0, GameData.current_plates - 1)
			rpc("sync_display_count", "plate", 20 - GameData.current_plates)
		else:
			body.linear_velocity = Vector3(randf_range(-3, 3), 4, randf_range(-3, 3))


func request_spawn_item(item_type: String) -> void:
	if not GameData.closed_lobby: return
	if not multiplayer.is_server():
		rpc_id(1, "server_spawn_item", item_type, multiplayer.get_unique_id())
		return
	server_spawn_item(item_type, 1)


@rpc("any_peer", "reliable")
func server_spawn_item(item_type: String, requester_id: int) -> void:
	if not multiplayer.is_server(): return

	if item_type == "plate":
		if GameData.current_plates < 20:
			GameData.current_plates += 1
			var unique_name: String = "plate_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 10000)
			var package: Array = ["plate", requester_id, item_spawn_pos, unique_name]
			if is_instance_valid(item_spawner):
				item_spawner.spawn(package)
			rpc("sync_display_count", "plate", 20 - GameData.current_plates)
		else:
			rpc_id(requester_id, "show_plate_warning")

	elif stocks.has(item_type) and stocks[item_type].size() > 0:
		var item_to_spawn: RigidBody3D = stocks[item_type].pop_back()
		
		if is_instance_valid(item_to_spawn):
			item_to_spawn.freeze = false
			item_to_spawn.visible = true
			item_to_spawn.linear_velocity = Vector3.ZERO
			item_to_spawn.angular_velocity = Vector3.ZERO
			item_to_spawn.set_collision_layer_value(3, true)
			item_to_spawn.global_position = item_spawn_pos
			item_to_spawn.set_multiplayer_authority(1)
			
			rpc("sync_display_count", item_type, stocks[item_type].size())
			rpc("sync_recalled_item", str(item_to_spawn.get_path()), item_spawn_pos)
			sync_recalled_item(str(item_to_spawn.get_path()), item_spawn_pos)
			
			var player = get_node_or_null("/root/main/players/" + str(requester_id))
			if is_instance_valid(player):
				player.rpc_pickup_object.rpc_id(requester_id, item_to_spawn.get_path())


@rpc("any_peer", "reliable")
func sync_recalled_item(item_path: String, pos: Vector3) -> void:
	var item = get_node_or_null(item_path)
	if not is_instance_valid(item): return
	item.global_position = pos
	item.visible = true
	item.freeze = false
	item.set_collision_layer_value(3, true)
	var shape: CollisionShape3D = item.find_child("CollisionShape3D")
	if shape: shape.disabled = false


@rpc("any_peer", "call_local", "reliable")
func sync_display_count(item_type: String, count: int) -> void:
	var display_node: Node = get_node_or_null("main_display/" + item_type)
	if display_node:
		display_node.set("stored", count)


@rpc("any_peer", "call_local", "reliable")
func store_item(item_path: String) -> void:
	var item = get_node_or_null(item_path)
	if is_instance_valid(item):
		item.position = Vector3(0, -50, 0)
		item.freeze = true
		item.visible = false


@rpc("any_peer", "call_local", "reliable")
func show_plate_warning() -> void:
	if has_node("main_display/plate_warning"):
		$main_display/plate_warning.show()
		if has_node("warning_timer"): $warning_timer.start(1.5)


func _on_warning_timer_timeout() -> void:
	if has_node("main_display/plate_warning"):
		$main_display/plate_warning.hide()


func drop_all(player) -> void:
	if not is_instance_valid(player): return
		
	for slot_key in player.inventory.keys():
		var slot_data = player.inventory[slot_key]
		var item_array: Array = slot_data[3]
		
		while item_array.size() > 0:
			player.current_slot = slot_key
			var item_node = item_array[-1] 
			if is_instance_valid(item_node):
				player.held_item = item_node
				player.drop_object()
				
				if item_node.type in valid_food_types:
					rpc_id(1, "server_process_dropped_food", item_node.get_path())
				
	player.current_slot = "0"
	player.held_item = null
	player.update_inventory_ui()


@rpc("any_peer", "call_local", "reliable")
func server_process_dropped_food(item_path: String) -> void:
	if not multiplayer.is_server(): return
	var item = get_node_or_null(item_path)
	if not is_instance_valid(item) or not item is RigidBody3D: return
		
	var type = item.type
	if type in valid_food_types:
		if stocks[type].has(item): return
		item.set_multiplayer_authority(1)
		stocks[type].append(item)
		
		rpc("store_item", item.get_path())
		rpc("sync_display_count", type, stocks[type].size())
