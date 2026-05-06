extends Node3D

@export var player_scene: PackedScene
var spawned_players: Dictionary = {}

func _ready() -> void:
	push_error("SPAWNER READY")
	GDSync.client_left.connect(client_left)
	GDSync.client_joined.connect(client_joined)
	GDSync.lobby_joined.connect(_on_lobby_joined)
	GDSync.expose_func(sync_held_states)
	
	var player = player_scene.instantiate()
	player.name = "local"
	spawned_players["local"] = player
	add_child(player)

func _on_lobby_joined(_lobby_name: String) -> void:
	var local = spawned_players.get("local")
	if local:
		local.name = str(GDSync.get_client_id())
		spawned_players.erase("local")
		spawned_players[GDSync.get_client_id()] = local
		GDSync.set_gdsync_owner(local, GDSync.get_client_id())
	
	for client_id in GDSync.lobby_get_all_clients():
		if client_id != GDSync.get_client_id() and not spawned_players.has(client_id):
			client_joined(client_id)

func client_joined(client_id: int) -> void:
	push_error("client_joined fired for: " + str(client_id) + " | is_host: " + str(GDSync.is_host()))
	if client_id == GDSync.get_client_id():
		return
	if spawned_players.has(client_id):
		return
	var player = player_scene.instantiate()
	player.name = str(client_id)
	spawned_players[client_id] = player
	add_child(player)
	GDSync.set_gdsync_owner(player, client_id)
	
	if GDSync.is_host():
		broadcast_world_state()

func broadcast_world_state() -> void:
	if not GDSync.is_host():
		return
	
	for id in spawned_players:
		var player = spawned_players[id]
		if is_instance_valid(player):
			GDSync.sync_var(player, "global_position")
			GDSync.sync_var(player, "rotation")
	
	var held_data = []
	for id in spawned_players:
		var player = spawned_players[id]
		if is_instance_valid(player) and player.held_item != null:
			held_data.append([player.held_item.item_id, str(player.hand.get_path())])
	
	if held_data.size() > 0:
		GDSync.call_func_all(sync_held_states, [held_data])

func sync_held_states(params: Array) -> void:
	for entry in params[0]:
		var object = GameData.item_registry.get(entry[0])
		var target_hand = get_node_or_null(entry[1])
		if object and target_hand:
			object.is_held = true
			object.freeze = true
			object.reparent(target_hand)
			object.position = Vector3.ZERO

func client_left(client_id: int) -> void:
	if spawned_players.has(client_id):
		spawned_players[client_id].queue_free()
		spawned_players.erase(client_id)
