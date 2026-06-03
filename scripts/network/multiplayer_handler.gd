extends Node

func _ready():
	multiplayer.peer_connected.connect(spawn_player)
