extends Node3D

@export var player_scene: PackedScene
var spawned_players: Dictionary = {}

func _ready() -> void:
	print("Spawner ready, my client id: ", GDSync.get_client_id())
	GDSync.client_left.connect(client_left)
	
	for client_id in GDSync.lobby_get_all_clients():
		client_joined(client_id)
	
	GDSync.client_joined.connect(client_joined)

func client_joined(client_id: int) -> void:
	if spawned_players.has(client_id):
		print("already spawned, skipping: ", client_id)
		return
	var spawn_pos = Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
	print("spawning: ", client_id, " at ", spawn_pos)
	var player = player_scene.instantiate()
	player.name = str(client_id)
	player.position = spawn_pos
	spawned_players[client_id] = player
	add_child(player)
	GDSync.set_gdsync_owner(player, client_id)
	
	if client_id == GDSync.get_client_id():
		player.get_node("Camera3D").make_current()

func client_left(client_id: int) -> void:
	print("client left: ", client_id)
	if spawned_players.has(client_id):
		spawned_players[client_id].queue_free()
		spawned_players.erase(client_id)
