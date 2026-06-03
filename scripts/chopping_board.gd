extends StaticBody3D

const CHOPPED_SCENES = {
	"cheese": ["cheese_chopped"],
	"tomato": ["tomato_chopped"],
	"meat_chopped": ["meat_chopped"],
	"bun": ["bun_bottom_chopped", "bun_top_chopped"]
}

@onready var item_spawner: MultiplayerSpawner = get_node("/root/main/game/spawners/item_spawner")

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body.is_in_group("choppable"):
		if not multiplayer.is_server():
			rpc_id(1, "server_chop", body.get_path())
		else:
			server_chop(body.get_path())

@rpc("any_peer", "reliable")
func server_chop(body_path: NodePath) -> void:
	if not multiplayer.is_server(): return
	
	var body = get_node_or_null(body_path)
	if not is_instance_valid(body) or not "type" in body: return
	
	var body_type = body.type
	body.queue_free() # Safely delete the un-chopped food on the server
	
	if CHOPPED_SCENES.has(body_type):
		for spawn_name in CHOPPED_SCENES[body_type]:
			# Define exactly where the chopped item should land
			var spawn_pos = global_position + Vector3(0, 1.2, 0)
			
			# Match your custom spawn function configuration array exactly:
			# [0] = item_type_string, [1] = network_owner_id, [2] = target_global_position
			item_spawner.spawn([spawn_name, 1, spawn_pos])
