extends Node3D

var item_children = []
var max_item_left = 4
var item_left: int = 4
var item_type_cached: String = ""

@onready var item_spawner: MultiplayerSpawner = get_node_or_null("/root/main/game/spawners/item_spawner")

func _ready() -> void:
	if self.name.contains("_"):
		var parts = self.name.split("_")
		if parts.size() >= 2:
			item_type_cached = parts[1]
	else:
		item_type_cached = self.name.substr(5).left(-1)
	
	var main_node = get_node_or_null("/root/main")
	if main_node and main_node.current_trees.has(item_type_cached):
		if not main_node.current_trees[item_type_cached].has(self):
			main_node.current_trees[item_type_cached].append(self)

	for i in self.get_children():
		if i.is_in_group("tree_item"):
			item_children.append(i)
			i.show()
			
	max_item_left = item_children.size()
	item_left = max_item_left
	
	if has_node("Label3D"):
		$Label3D.text = str(item_left)

func _on_punched() -> void:
	if not multiplayer.is_server():
		rpc_id(1, "server_handle_punch", multiplayer.get_unique_id())
		return
	server_handle_punch(1)

func _on_item_timer_timeout() -> void:
	if not multiplayer.is_server(): return
		
	item_left = min(max_item_left, item_left + 1)
	var visual_node = self.find_child(str(self.name.left(-1)) + str(item_left))
	if visual_node:
		visual_node.show()
		
	if item_left < max_item_left:
		if has_node("item_timer"):
			$item_timer.start(10)

@rpc("any_peer", "reliable")
func server_handle_punch(sender_id: int) -> void:
	if not multiplayer.is_server() or item_left <= 0: return

	# FIX: Instead of hunting by node string names, hide by index directly from our array!
	if item_left <= item_children.size():
		item_children[item_left - 1].hide()

	item_left -= 1
	var item_name_prefix: String = item_type_cached.to_lower()
	var angle: float = randf_range(0, 2 * PI)
	var spawn_pos: Vector3 = global_position + Vector3(sin(angle), 0.2, cos(angle)) * randf_range(1, 3)
	var unique_name: String = item_name_prefix + "_" + str(randi() % 100000)
	var package: Array = [item_name_prefix, sender_id, spawn_pos, unique_name]
	
	if is_instance_valid(item_spawner):
		item_spawner.spawn(package)
	
	if item_left <= 0:
		if has_node("AnimationPlayer"):
			$AnimationPlayer.play("chopped")
		
		# Disconnect tracking references completely before freeing
		var main_node = get_node_or_null("/root/main")
		if main_node and main_node.current_trees.has(item_type_cached):
			main_node.current_trees[item_type_cached].erase(self)
			
		await get_tree().create_timer(1.0).timeout
		self.queue_free()

func _on_custom_item_spawn(data: Array) -> Node:
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
