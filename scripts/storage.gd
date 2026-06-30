extends Node3D

var valid_food_types: Array[String] = ["cheese", "tomato", "bun", "meat", "carrot", "lettuce"]
@export var stocks: Dictionary = {}

# Keep track of both spawn positions now
var item_spawn_pos1: Vector3
var item_spawn_pos2: Vector3

@onready var item_spawner: MultiplayerSpawner = get_node("/root/main/game/spawners/item_spawner")

func _ready() -> void:
	for food_type in valid_food_types:
		stocks[food_type] = []

	# Cache both spawn points safely
	if has_node("output/spawn_point"):
		item_spawn_pos1 = $output/spawn_point.global_position
	if has_node("output2/spawn_point"):
		item_spawn_pos2 = $output2/spawn_point.global_position

	# Connect Display 1 signals (pass 1 as extra argument)
	for type in valid_food_types:
		var display_node = get_node_or_null("main_display/" + type)
		if display_node:
			display_node.spawn_item.connect(request_spawn_item.bind(1))
	var plate_display = get_node_or_null("main_display/plate")
	if plate_display:
		plate_display.spawn_item.connect(request_spawn_item.bind(1))

	# Connect Display 2 signals (pass 2 as extra argument)
	for type in valid_food_types:
		var display_node = get_node_or_null("main_display2/" + type)
		if display_node:
			display_node.spawn_item.connect(request_spawn_item.bind(2))
	var plate_display2 = get_node_or_null("main_display2/plate")
	if plate_display2:
		plate_display2.spawn_item.connect(request_spawn_item.bind(2))


func _on_input_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if not is_instance_valid(body):
		return
	if not "type" in body:
		return

	var type = body.type
	if body is RigidBody3D:
		if type in valid_food_types:
			if stocks[type].has(body):
				return
				
			body.set_multiplayer_authority(1)
			stocks[type].append(body)
			body.position = Vector3(0, -50, 0)
			body.freeze = true
			body.visible = false
			
			# Broadcasts to update displays globally
			rpc("sync_display_count", type, stocks[type].size())
		elif type == "plate" and "stacked_items" in body and body.stacked_items.size() == 0:
			body.queue_free()
			GameData.current_plates = max(0, GameData.current_plates - 1)
			rpc("sync_display_count", "plate", 20 - GameData.current_plates)
		else:
			body.linear_velocity = Vector3(randf_range(-3, 3), 4, randf_range(-3, 3))


# Added display_id argument to catch who called it (1 or 2)
func request_spawn_item(item_type: String, display_id: int) -> void:
	if not GameData.closed_lobby:
		return
	if not multiplayer.is_server():
		rpc_id(1, "server_spawn_item", item_type, multiplayer.get_unique_id(), display_id)
		return
	server_spawn_item(item_type, 1, display_id)


@rpc("any_peer", "reliable")
func server_spawn_item(item_type: String, requester_id: int, display_id: int) -> void:
	if not multiplayer.is_server():
		return

	# Determine target spawn position based on which display requested it
	var target_spawn_pos: Vector3 = item_spawn_pos1 if display_id == 1 else item_spawn_pos2

	if item_type == "plate":
		if GameData.current_plates < 20:
			GameData.current_plates += 1
			var unique_name: String = "plate_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 10000)
			var package: Array = ["plate", requester_id, target_spawn_pos, unique_name]
			if is_instance_valid(item_spawner):
				item_spawner.spawn(package)
			rpc("sync_display_count", "plate", 20 - GameData.current_plates)
		else:
			rpc_id(requester_id, "show_plate_warning", display_id)

	elif stocks.has(item_type) and stocks[item_type].size() > 0:
		var item_to_spawn: RigidBody3D = stocks[item_type].pop_back()
		
		if is_instance_valid(item_to_spawn):
			item_to_spawn.freeze = false
			item_to_spawn.visible = true
			item_to_spawn.linear_velocity = Vector3.ZERO
			item_to_spawn.angular_velocity = Vector3.ZERO
			item_to_spawn.set_collision_layer_value(3, true)
			item_to_spawn.global_position = target_spawn_pos
			item_to_spawn.set_multiplayer_authority(requester_id)
			
			rpc("sync_display_count", item_type, stocks[item_type].size())
			rpc("sync_recalled_item", str(item_to_spawn.get_path()), target_spawn_pos)
			sync_recalled_item(str(item_to_spawn.get_path()), target_spawn_pos)
		else:
			rpc("sync_display_count", item_type, stocks[item_type].size())


@rpc("any_peer", "reliable")
func sync_recalled_item(item_path: String, pos: Vector3) -> void:
	var item = get_node_or_null(item_path)
	if not is_instance_valid(item):
		return
	item.global_position = pos
	item.visible = true
	item.freeze = false
	item.set_collision_layer_value(3, true)
	var shape: CollisionShape3D = item.find_child("CollisionShape3D")
	if shape:
		shape.disabled = false


@rpc("any_peer", "call_local", "reliable")
func sync_display_count(item_type: String, count: int) -> void:
	# FIX: Update main_display
	var display_node1: Node = get_node_or_null("main_display/" + item_type)
	if display_node1:
		display_node1.stored = count

	# FIX: Simultaneously update main_display2
	var display_node2: Node = get_node_or_null("main_display2/" + item_type)
	if display_node2:
		display_node2.stored = count


@rpc("any_peer", "call_local", "reliable")
func show_plate_warning(display_id: int) -> void:
	var target_display = "main_display" if display_id == 1 else "main_display2"
	if has_node(target_display + "/plate_warning"):
		get_node(target_display + "/plate_warning").show()
		if has_node("warning_timer"):
			$warning_timer.start(1.5)


func _on_warning_timer_timeout() -> void:
	if has_node("main_display/plate_warning"):
		$main_display/plate_warning.hide()
	if has_node("main_display2/plate_warning"):
		$main_display2/plate_warning.hide()

func drop_all(player) -> void:
	if not is_instance_valid(player):
		return
		
	print("Dropping all items for player: ", player.name)
	
	# Loop through every inventory slot
	for slot_key in player.inventory.keys():
		var slot_data = player.inventory[slot_key]
		var item_array: Array = slot_data[3]
		
		# Safely clear out items from back to front
		while item_array.size() > 0:
			# Force the player's active slot to this one so drop_object works correctly
			player.current_slot = slot_key
			
			# Grab the actual item reference before dropping it
			var item_node = item_array[-1] 
			
			if is_instance_valid(item_node):
				# Update player's held item variable so drop_object knows what it's dropping
				player.held_item = item_node
				
				# Let the player's native network-safe function handle the drop physics/sync
				player.drop_object()
				
				# Now pass it into the stocking system input safely
				_on_input_body_entered(item_node)
				
	# Reset slot back to empty hands and refresh UI locally
	player.current_slot = "0"
	player.held_item = null
	player.update_inventory_ui()
