extends StaticBody3D

var is_open: bool = false

func open_door() -> void:
	# If it's already open, do nothing
	if is_open: 
		return
		
	# Fire an RPC to everyone (including ourselves) to execute the opening sequence safely
	if multiplayer.multiplayer_peer:
		rpc("sync_open_door")
	else:
		# Singleplayer fallback
		sync_open_door()

@rpc("any_peer", "call_local", "reliable")
func sync_open_door() -> void:
	# Double-check state on all peers to prevent double-triggers
	if is_open: 
		return
		
	is_open = true
	GameData.closed_lobby = true
	
	# Trigger the local animation using an absolute path to prevent hierarchy breaks
	var anim_player = get_node_or_null("/root/main/door_animation_player") 
	# Note: If your door_animation_player is inside another folder, update this string path!
	if anim_player:
		anim_player.play("door_open")
	
	# Handle the day cycle initialization from the absolute scene root
	var env_controller = get_node_or_null("/root/main/game/environment_controller")
	if is_instance_valid(env_controller) and env_controller.has_method("start_day_cycle"):
		env_controller.start_day_cycle()
	else:
		print("Error: Could not find environment_controller at /root/main/environment_controller")
