extends Node3D

@export var player_scene: PackedScene
var spawned_players: Dictionary = {}

func _ready() -> void:
	GDSync.client_left.connect(client_left)
	
	for client_id in GDSync.lobby_get_all_clients():
		client_joined(client_id)
	
	GDSync.client_joined.connect(client_joined)

func client_joined(client_id: int) -> void:
	var username = GDSync.player_get_username(client_id)
	if spawned_players.has(client_id):
		return
	var player = player_scene.instantiate()
	player.name = str(client_id)
	spawned_players[client_id] = player
	add_child(player)
	if str(username) == "H":
		player.find_child("Devhat").show()
	player.find_child("username").text = username
	GDSync.set_gdsync_owner(player, client_id)

func client_left(client_id: int) -> void:
	if spawned_players.has(client_id):
		spawned_players[client_id].queue_free()
		spawned_players.erase(client_id)
