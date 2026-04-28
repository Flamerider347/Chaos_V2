extends Node3D

func _ready() -> void:
	$UI/roomcode.text = "Room: " + GameData.room_code
