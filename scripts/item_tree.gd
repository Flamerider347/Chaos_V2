extends Node3D
var item_children = []
var max_item_left = 4
var item_left: int = 4
# Path pointing to your native MultiplayerSpawner
@onready var item_spawner: MultiplayerSpawner = get_node("/root/main/game/spawners/item_spawner")


func _ready() -> void:
	for i in self.get_children():
		if i.is_in_group("tree_item"):
			item_children.append(i)
			i.show()
	max_item_left = item_children.size()
	item_left = max_item_left
	if has_node("Label3D"):
		$Label3D.text = str(item_left)
	
	# Every machine (Server AND Client) MUST register the spawn function
	if is_instance_valid(item_spawner):
		item_spawner.spawn_function = _on_custom_item_spawn


func _on_punched() -> void:
	if not multiplayer.is_server():
		rpc_id(1, "server_handle_punch", multiplayer.get_unique_id())
		return
	server_handle_punch(1)


func _on_item_timer_timeout() -> void:
	if not multiplayer.is_server():
		return
		
	item_left = min(max_item_left, item_left + 1)
	self.find_child(self.name + str(item_left)).show()
	if item_left < max_item_left:
		if has_node("item_timer"):
			$item_timer.start(10)


@rpc("any_peer", "reliable")
func server_handle_punch(sender_id: int) -> void:
	if not multiplayer.is_server():
		return
	if item_left <= 0:
		return

	var item_name_prefix: String = self.name.substr(5).to_lower()
	var angle: float = randf_range(0, 2 * PI)
	var spawn_pos: Vector3 = global_position + Vector3(sin(angle), 0.2, cos(angle)) * randf_range(1, 3)
	
	self.find_child(self.name + str(item_left)).hide()
	item_left -= 1
	# Generate a secure network-unique identity name string
	var unique_name: String = item_name_prefix + "_" + str(randi() % 100000)
	
	# Build the 4-argument network context package
	var package: Array = [item_name_prefix, sender_id, spawn_pos, unique_name]
	
	# Pass all configuration data through the native spawner node
	if is_instance_valid(item_spawner):
		item_spawner.spawn(package)
	
	if has_node("item_timer"):
		$item_timer.start(10)
		


# --- Native Godot Spawn Routine ---
func _on_custom_item_spawn(data: Array) -> Node:
	# SAFETIES: If data is completely empty or missing elements, stop processing immediately
	if data.size() < 3:
		print("Network Warning: Received incomplete spawn data array.")
		return null
		
	var item_type = data[0]
	var target_pos = data[2]
	
	# ROBUST FALLBACK FOR INDEX 3: If array size is 3 (e.g. from cutting logic), generate a fallback name safely
	var exact_name: String = ""
	if data.size() >= 4:
		exact_name = str(data[3])
	else:
		exact_name = str(item_type) + "_fallback_" + str(randi() % 100000)
	
	var item_path: String = "res://Prefabs/" + str(item_type) + ".tscn"
	if not ResourceLoader.exists(item_path):
		print("Network error: Cannot find item prefab file at: ", item_path)
		return null
		
	var item_instance = load(item_path).instantiate()
	
	# Apply synchronized structural data values
	item_instance.name = exact_name
	item_instance.type = str(item_type)
	item_instance.position = target_pos
	
	item_instance.set_multiplayer_authority(1)
	item_instance.add_to_group("plate_stackable")
	item_instance.add_to_group("pickupable")
	
	return item_instance
