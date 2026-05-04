extends Node3D

@export var player_scene: PackedScene
var spawned_players: Dictionary = {}

func _ready() -> void:
	GDSync.client_left.connect(client_left)
	GDSync.client_joined.connect(client_joined)
	GDSync.lobby_joined.connect(_on_lobby_joined)
	
	var player = player_scene.instantiate()
	player.name = "local"
	spawned_players["local"] = player
	add_child(player)

func _on_lobby_joined(lobby_name: String) -> void:
	var local = spawned_players.get("local")
	if local:
		local.name = str(GDSync.get_client_id())
		spawned_players.erase("local")
		spawned_players[GDSync.get_client_id()] = local
		GDSync.set_gdsync_owner(local, GDSync.get_client_id())
	
	for client_id in GDSync.lobby_get_all_clients():
		if not spawned_players.has(client_id):
			client_joined(client_id)

func client_joined(client_id: int) -> void:
	if spawned_players.has(client_id):
		return
	var player = player_scene.instantiate()
	player.name = str(client_id)
	spawned_players[client_id] = player
	add_child(player)
	GDSync.set_gdsync_owner(player, client_id)

func client_left(client_id: int) -> void:
	if spawned_players.has(client_id):
		spawned_players[client_id].queue_free()
		spawned_players.erase(client_id)
