extends Node

var peer = ENetMultiplayerPeer.new()
var self_ip: String = "" # Variable to store the machine's own IP

func _ready():
	peer.create_server(GameData.SPOOLER_PORT)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_client_connected)
	# Get and store the machine's own local network IP
	self_ip = get_machine_ip()
	$MarginContainer/HBoxContainer/VBoxContainer2/Label.text = "Spooler machine IP identified as: " +str(self_ip)

func _on_client_connected(client_id):
	var allocated_port = GameData.find_port(GameData.next_available_port)
	GameData.next_available_port = allocated_port + 1

	create_new_server_instace(allocated_port)

	GameData.rpc_id(client_id, "recieve_redirect", allocated_port)
	$MarginContainer/HBoxContainer/VBoxContainer2/Label2.text = "Made server on port:" +str(allocated_port)

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

# Helper function to let the machine find its own true network IP
func get_machine_ip() -> String:
	for ip in IP.get_local_addresses():
		# Filter out IPv6 (contains ":"), localhost loopbacks ("127."), and self-assigned IPs ("169.254.")
		if ip.contains(".") and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			return ip
	return "127.0.0.1" # Fallback if offline or unconnected
