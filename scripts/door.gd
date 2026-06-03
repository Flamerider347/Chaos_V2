extends StaticBody3D

var is_open: bool = false

func open_door() -> void:
	# If it's already open, do nothing
	if is_open: 
		return
		
	# Fire an RPC to everyone (including ourselves) to execute the opening sequence safely
	rpc("sync_open_door")

@rpc("any_peer", "call_local", "reliable")
func sync_open_door() -> void:
	# Double-check state on all peers to prevent double-triggers
	if is_open: 
		return
		
	is_open = true
	GameData.closed_lobby = true
	
	# Trigger the local animation
	var anim_player = get_node_or_null("../../../../door_animation_player")
	if anim_player:
		anim_player.play("door_open")
	
	# Handle the day cycle initialization
	var env_controller = get_node_or_null("../../../environment_controller")
	if env_controller and env_controller.has_method("start_day_cycle"):
		env_controller.start_day_cycle()
