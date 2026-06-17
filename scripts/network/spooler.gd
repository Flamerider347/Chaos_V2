extends Node

var peer = ENetMultiplayerPeer.new()

func _ready():
	peer.create_server(GameData.SPOOLER_PORT)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_client_connected)

func _on_client_connected(client_id):
	var allocated_port = GameData.find_port(GameData.next_available_port)
	GameData.next_available_port = allocated_port + 1

	create_new_server_instace(allocated_port)

	GameData.rpc_id(client_id, "recieve_redirect", allocated_port)

func create_new_server_instace(port):
	var dir = OS.get_executable_path().get_base_dir()
	print(dir)

	var files = DirAccess.get_files_at(dir)
	if not files.has("headless_server.exe"):
		print("Server not found.")
		return
	var path = dir.path_join("headless_server.exe")

	var args = PackedStringArray([
		"--headless",
		"--",
		"--port", str(port)
	])

	OS.create_process(path, args)
