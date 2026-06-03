extends Node3D

var item_left: int = 5:
	set(val):
		item_left = val
		$Label3D.text = str(val)

# Path pointing to your native MultiplayerSpawner
@onready var item_spawner: MultiplayerSpawner = get_node("/root/main/game/spawners/item_spawner")

func _ready() -> void:
	$Label3D.text = str(item_left)
	
	# FIX 1: Every machine (Server AND Client) MUST register the spawn function!
	item_spawner.spawn_function = _on_custom_item_spawn

func _on_punched():
	if not multiplayer.is_server():
		rpc_id(1, "server_handle_punch", multiplayer.get_unique_id())
		return
	server_handle_punch(1)

func _on_item_timer_timeout() -> void:
	if not multiplayer.is_server(): return
	item_left = min(5, item_left + 1)
	if item_left < 5: $item_timer.start(10)

@rpc("any_peer", "reliable")
func server_handle_punch(sender_id: int) -> void:
	if not multiplayer.is_server() or item_left <= 0: return
	
	item_left -= 1
	
	var item_name_prefix = self.name.left(-5) # e.g., "meat" or "plate"
	var angle = randf_range(0, 2 * PI)
	var spawn_pos = global_position + Vector3(sin(angle), 0.2, cos(angle)) * randf_range(1, 3)
	
	# CRITICAL FIX: Generate the unique ID on the server and pass it in the array
	var unique_name = item_name_prefix + "_" + str(randi() % 100000)
	
	# Pass all the configuration data through the native spawn function
	item_spawner.spawn([item_name_prefix, sender_id, spawn_pos, unique_name])
	
	$item_timer.start(10)

# --- Native Godot Spawn Routine ---
func _on_custom_item_spawn(data: Array) -> Node:
	var item_type = data[0]
	var owner_id = data[1]
	var target_pos = data[2]
	var exact_name = data[3] # Grab the identical name from the server
	
	var item_path = "res://Prefabs/" + item_type + ".tscn"
	if not ResourceLoader.exists(item_path):
		print("Network error: Cannot find item prefab file at: ", item_path)
		return null
		
	var item_instance = load(item_path).instantiate()
	
	# FIX: Name them identically across the network!
	item_instance.name = exact_name
	item_instance.type = item_type
	item_instance.position = target_pos
	
	item_instance.set_multiplayer_authority(owner_id)
	item_instance.add_to_group("plate_stackable")
	item_instance.add_to_group("pickupable")
	
	return item_instance
