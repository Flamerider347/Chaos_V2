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
			$item_timer.start(96)


@rpc("any_peer", "reliable")
func server_handle_punch(sender_id: int) -> void:
	if not multiplayer.is_server() or item_left <= 0: return

	if item_left <= item_children.size():
		item_children[item_left - 1].hide()

	item_left -= 1
	
	# Determine base spawns + bonus drops from drop_chance
	var drop_count: int = 1
	var bonus_chance: float = GameData.get_upgrade_value("drop_chance")
	if randf() < bonus_chance:
		drop_count += 1

	for i in range(drop_count):
		_spawn_single_item(sender_id)
	if has_node("item_timer") and $item_timer.time_left == 0:
		$item_timer.start(96)


func _spawn_single_item(sender_id: int) -> void:
	var item_name_prefix: String = item_type_cached.to_lower()
	var angle: float = randf_range(0, 2 * PI)
	var spawn_pos: Vector3 = global_position + Vector3(sin(angle), 0.2, cos(angle)) * randf_range(1, 3)
	var unique_name: String = item_name_prefix + "_" + str(randi() % 100000)
	var package: Array = [item_name_prefix, sender_id, spawn_pos, unique_name]
	
	if is_instance_valid(item_spawner):
		item_spawner.spawn(package)
