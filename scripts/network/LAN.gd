extends Node

const IP_ADDRESS = "127.0.0.1"

var port = 8081 # Past start of Unity range
var peer = ENetMultiplayerPeer.new()

func start_server():
	peer.create_server(port)
	multiplayer.multiplayer_peer = peer

func start_client():
	peer.create_client(IP_ADDRESS, port)
	multiplayer.multiplayer_peer = peer
