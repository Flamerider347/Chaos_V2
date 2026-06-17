extends Node

var players: Array = []

func _ready():
	if not OS.has_feature("dedicated_server"): # Only runs with multi instancing
		queue_free()
		return

	GameData.dedicated_server_setup.connect(init_player_register)

	print("Server Optimizer Active: Intercepting game visuals...")
	
	get_tree().node_added.connect(_on_node_added) # Triggers on every node

	# Autoclose the server if no one has joined for 10 minutes
	await get_tree().create_timer(600).timeout
	if len(players) == 0:
		get_tree().quit()


func _on_node_added(node: Node):
	if node is AnimationPlayer:
		node.active = false
		
	elif node is AnimationTree:
		node.active = false
		
	elif node is GPUParticles3D or node is CPUParticles3D:
		node.emitting = false
		node.set_process(false)
		
	elif node is Sprite3D or node is MeshInstance3D:
		node.set_process(false)
		node.set_physics_process(false)
		
	elif node is Light3D:
		node.visible = false 
		node.set_process(false)

func init_player_register():
	multiplayer.peer_connected.connect(add_player_to_register)
	multiplayer.peer_disconnected.connect(remove_player_from_register)

func add_player_to_register(peer_id):
	players.append(peer_id)

func remove_player_from_register(peer_id):
	players.erase(peer_id)
	if len(players) == 0:
		get_tree().quit()
