extends StaticBody3D

var current_cooking_item: RigidBody3D = null
var cookedness: float = 0.0

@onready var item_spawner: MultiplayerSpawner = get_node("/root/main/game/spawners/item_spawner")


func _on_area_3d_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
		
	if body.is_in_group("pickupable") and "state" in body:
		current_cooking_item = body


func _on_area_3d_body_exited(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
		
	if body == current_cooking_item:
		current_cooking_item = null
		cookedness = 0.0
		rpc("sync_cooking_text", "Empty")


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not is_instance_valid(current_cooking_item):
		return

	var state = current_cooking_item.state
	if state != "burnt":
		cookedness += delta
		rpc("sync_cooking_text", str(snapped(cookedness, 0.1)))
		
		if state == "raw" and cookedness > 5.0:
			cook_swap("meat_cooked", "cooked")
		elif state == "cooked" and cookedness > 10.0:
			cook_swap("meat_burnt", "burnt")


func cook_swap(spawn_name: String, new_state_string: String) -> void:
	if not is_instance_valid(current_cooking_item):
		return
		
	var old_pos: Vector3 = current_cooking_item.global_position
	
	# Force removal of old item first so it clears network paths safely
	current_cooking_item.queue_free()
	current_cooking_item = null
	cookedness = 0.0 
	
	# Generate a secure network identity name string
	var unique_name: String = spawn_name + "_ck_" + str(randi() % 100000)
	
	# FIX: Match your global 4-argument custom spawner schema:
	# [item_type, owner_id, target_pos, exact_name]
	var package: Array = [spawn_name, 1, old_pos, unique_name]
	
	if is_instance_valid(item_spawner):
		# Let the spawner handle creation and location setup internally.
		# This prevents the null instance error entirely.
		var new_item = item_spawner.spawn(package)
		
		# Guard check just in case network delays happen
		if is_instance_valid(new_item):
			new_item.state = new_state_string 
			new_item.type = spawn_name
			current_cooking_item = new_item


@rpc("any_peer", "call_local", "unreliable")
func sync_cooking_text(text_val: String) -> void:
	if has_node("time_left"):
		$time_left.text = text_val
