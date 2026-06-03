extends StaticBody3D

var current_cooking_item: RigidBody3D = null
var cookedness: float = 0.0

@onready var item_spawner: MultiplayerSpawner = get_node("/root/main/game/spawners/item_spawner")

func _on_area_3d_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server(): return
	if body.is_in_group("pickupable") and "state" in body:
		current_cooking_item = body

func _on_area_3d_body_exited(body: Node3D) -> void:
	if not multiplayer.is_server(): return
	if body == current_cooking_item:
		current_cooking_item = null
		cookedness = 0.0
		rpc("sync_cooking_text", "Empty")

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not is_instance_valid(current_cooking_item): return

	var state = current_cooking_item.state
	if state != "burnt":
		cookedness += delta
		rpc("sync_cooking_text", str(snapped(cookedness, 0.1)))
		
		if state == "raw" and cookedness > 5.0:
			cook_swap("meat_cooked", "cooked")
		elif state == "cooked" and cookedness > 10.0:
			cook_swap("meat_burnt", "burnt")

func cook_swap(spawn_name: String, new_state_string: String) -> void:
	var old_pos = current_cooking_item.global_position
	var old_rot = current_cooking_item.global_rotation
	
	# Native removal auto-replicates deletion to clients
	current_cooking_item.queue_free()
	current_cooking_item = null
	cookedness = 0.0 
	
	# Spawn cooked version via MultiplayerSpawner (1 = server/neutral ownership)
	var new_item = item_spawner.spawn([spawn_name, 1])
	new_item.global_position = old_pos
	new_item.global_rotation = old_rot
	
	new_item.state = new_state_string 
	new_item.type = spawn_name
	
	current_cooking_item = new_item

@rpc("any_peer", "call_local", "unreliable")
func sync_cooking_text(text_val: String) -> void:
	$time_left.text = text_val
