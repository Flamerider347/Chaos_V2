extends Node3D

func _ready() -> void:
	GDSync.connected.connect(connected)
	GDSync.connection_failed.connect(connection_failed)
	GDSync.lobby_created.connect(lobby_created)
	GDSync.lobby_creation_failed.connect(lobby_creation_failed)
	GDSync.lobby_joined.connect(lobby_joined)
	GDSync.start_multiplayer()

func connected() -> void:
	print("Connected")
	GDSync.lobby_create("Test_lobby")

func connection_failed(error: int) -> void:
	match error:
		ENUMS.CONNECTION_FAILED.INVALID_PUBLIC_KEY:
			push_error("Invalid key")
		ENUMS.CONNECTION_FAILED.TIMEOUT:
			push_error("Internet is cooked")

func lobby_created(lobby_name: String) -> void:
	print("Lobby created: ", lobby_name)
	GDSync.lobby_join(lobby_name)

func lobby_creation_failed(lobby_name: String, error: int) -> void:
	if error == ENUMS.LOBBY_CREATION_ERROR.LOBBY_ALREADY_EXISTS:
		GDSync.lobby_join(lobby_name)

func lobby_joined(lobby_name: String) -> void:
	print("Joined: ", lobby_name)
