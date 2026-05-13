extends Area3D

@onready var smoke_particle = preload("res://Prefabs/smoke_particle.tscn")
func _on_body_entered(body) -> void:
	if body.is_in_group("player"):
		body.position = Vector3(0,5,0)
		print("PLAYER")
		var spawned_smoke = smoke_particle.instantiate()
		
	elif body.is_in_group("plate"):
		print(body.stacked_items)
	elif body.is_in_group("pickupable"):
		print(body.type)
