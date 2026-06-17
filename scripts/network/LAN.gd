extends Node

func start_server() -> void:
	GameData.host_game()

func start_client(port,join_code) -> void:
	if port == "":
		port = 13501
	else:
		port = int(port)
	if join_code == "":
		join_code = "127.0.0.1" # Standard local loopback fallback
	GameData.room_code = join_code
	GameData.join_game(join_code, port)
