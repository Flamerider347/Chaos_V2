extends Node

const DEFAULT_PORT = 25565

func start_server() -> void:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, 4) # Max 4 players
	
	if error != OK:
		print("Cannot host: ", error)
		return
		
	# Hand the functional peer over to your persistent GameData singleton
	GameData.set_network_peer(peer, true)

func start_client() -> void:
	# Grab the target IP from the join_code LineEdit field
	var target_ip = get_node("../menu_UI/join_code").text.strip_edges()
	if target_ip == "":
		target_ip = "127.0.0.1" # Default to localhost if left blank
		
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(target_ip, DEFAULT_PORT)
	
	if error != OK:
		print("Cannot connect: ", error)
		return
		
	# Hand the peer over to GameData
	GameData.set_network_peer(peer, false)
