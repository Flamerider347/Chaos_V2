extends Node3D

@export var player_scene: PackedScene = preload("res://Prefabs/player.tscn")
@onready var player_spawner: MultiplayerSpawner = $player_spawner

func _ready() -> void:
	# CRITICAL FIX: Every single machine (host AND client) MUST register 
	# the spawn function, or the engine cannot unpack incoming network players!
	player_spawner.spawn_function = _on_player_custom_spawn
	
	if not multiplayer.is_server(): return
	
	multiplayer.peer_connected.connect(_spawn_player)
	multiplayer.peer_disconnected.connect(_remove_player)
	
	if not OS.has_feature("dedicated_server"):
		_spawn_player(1)

func _spawn_player(id: int) -> void:
	if has_node(str(id)): return
	player_spawner.spawn(id)

func _remove_player(id: int) -> void:
	if has_node(str(id)):
		get_node(str(id)).queue_free()

func _on_player_custom_spawn(id: int) -> Node:
	var player_instance = player_scene.instantiate()
	player_instance.name = str(id)
	return player_instance
