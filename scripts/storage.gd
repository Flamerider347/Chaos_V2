extends Node3D

var valid_food_types: Array[String] = ["cheese", "tomato", "bun", "meat_raw"]
@export var stocks: Dictionary = {}
var item_spawn_pos: Vector3

@onready var item_spawner: MultiplayerSpawner = get_node("/root/main/game/spawners/item_spawner")


func _ready() -> void:
	for food_type in valid_food_types:
		stocks[food_type] = []
	
	if has_node("output/spawn_point"):
		item_spawn_pos = $output/spawn_point.global_position
	
	# Connect UI buttons dynamically to trigger local request handlers
	for type in valid_food_types:
		var display_node: Node = get_node_or_null("main_display/" + type)
		if display_node:
			display_node.spawn_item.connect(request_spawn_item)
		
	var plate_display: Node = get_node_or_null("main_display/plate")
	if plate_display:
		plate_display.spawn_item.connect(request_spawn_item)


func _on_input_body_entered(body: Node3D) -> void:
	# Only the server registers items entering the storage unit
	if not multiplayer.is_server():
		return
	if not is_instance_valid(body):
		return
	if not "type" in body:
		return
	
	var type = body.type
	if body is RigidBody3D:
		if type in valid_food_types:
			stocks[type].append(body)
			body.position = Vector3(0, -50, 0)
			body.freeze = true
			body.visible = false
			rpc("sync_display_count", type, stocks[type].size())
		elif type == "plate" and "stacked_items" in body and body.stacked_items.size() == 0:
			# Recycle empty plates dropped back into storage
			body.queue_free()
			GameData.current_plates = max(0, GameData.current_plates - 1)
			rpc("sync_display_count", "plate", 20 - GameData.current_plates)
		else:
			# Reject invalid items with physical recoil bounce
			body.linear_velocity = Vector3(randf_range(-3, 3), 4, randf_range(-3, 3))


func request_spawn_item(item_type: String) -> void:
	if not GameData.closed_lobby:
		return
	
	if not multiplayer.is_server():
		rpc_id(1, "server_spawn_item", item_type, multiplayer.get_unique_id())
		return
	server_spawn_item(item_type, 1)


@rpc("any_peer", "reliable")
func server_spawn_item(item_type: String, requester_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	if item_type == "plate":
		if GameData.current_plates < 20:
			GameData.current_plates += 1
			
			# Create a globally unique name for this plate instance
			var unique_name: String = "plate_" + str(randi() % 100000)
			
			# MUST MATCH THE EXACT 4-ELEMENT SCHEMA EXPECTED BY THE SPAWN_FUNCTION:
			# [item_type, owner_id, target_pos, exact_name]
			var package: Array = ["plate", requester_id, item_spawn_pos, unique_name]
			
			if is_instance_valid(item_spawner):
				# Godot registers this node automatically. 
				# Do not try to modify its position or parent after this line!
				item_spawner.spawn(package)
				
			rpc("sync_display_count", "plate", 20 - GameData.current_plates)
		else:
			rpc_id(requester_id, "show_plate_warning")
			
	elif stocks.has(item_type) and stocks[item_type].size() > 0:
		var item_to_spawn: Node3D = stocks[item_type].pop_back()
		if is_instance_valid(item_to_spawn):
			item_to_spawn.freeze = false
			item_to_spawn.visible = true
			item_to_spawn.global_position = item_spawn_pos
			item_to_spawn.set_multiplayer_authority(requester_id)
			rpc("sync_display_count", item_type, stocks[item_type].size())

@rpc("any_peer", "call_local", "reliable")
func sync_display_count(item_type: String, count: int) -> void:
	var display_node: Node = get_node_or_null("main_display/" + item_type)
	if display_node:
		display_node.stored = count


@rpc("any_peer", "reliable")
func show_plate_warning() -> void:
	if has_node("main_display/plate_warning"):
		$main_display/plate_warning.show()
		if has_node("warning_timer"):
			$warning_timer.start(1.5)


func _on_warning_timer_timeout() -> void:
	if has_node("main_display/plate_warning"):
		$main_display/plate_warning.hide()
