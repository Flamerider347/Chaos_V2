extends StaticBody3D

const CHOPPED_SCENES = {
	"cheese": ["cheese_chopped"],
	"tomato": ["tomato_chopped"],
	"meat_chopped": ["meat_chopped"],
	"carrot": ["carrot_chopped"],
	"lettuce": ["lettuce_chopped"],
	"bun": ["bun_bottom_chopped", "bun_top_chopped"]
}

@onready var item_spawner: MultiplayerSpawner = get_node("/root/main/game/spawners/item_spawner")


func _on_area_3d_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
		
	if not is_instance_valid(body) or not "type" in body: 
		return

	if body.is_in_group("choppable"):
		chop_item(body)


func chop_item(body: Node3D) -> void:
	var body_type = body.type
	body.call_deferred("queue_free")
	
	if not CHOPPED_SCENES.has(body_type):
		return

	# Roll for double chop bonus
	var bonus_chop: bool = randf() < GameData.get_upgrade_value("chop_chance")
	var spawn_list = CHOPPED_SCENES[body_type].duplicate()

	# Duplicate chopped yield if double chop rolls successfully
	if bonus_chop:
		spawn_list.append_array(CHOPPED_SCENES[body_type])

	for spawn_name in spawn_list:
		var spawn_pos = global_position + Vector3(0, 1.2, 0)
		if is_instance_valid(item_spawner):
			item_spawner.spawn([spawn_name, 1, spawn_pos])
