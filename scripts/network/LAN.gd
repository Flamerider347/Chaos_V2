extends Node

func start_server() -> void:
	GameData.host_game()

func start_client(ip: String, port) -> void:
	if port == "" or port == null:
		port = 13501
	else:
		port = int(port)

	if ip == "":
		ip = "127.0.0.1"

	GameData.room_code = ip
	GameData.join_game(ip, port)
