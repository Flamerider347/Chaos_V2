extends Area3D

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		# Set a variable on the player script indicating they are in the kitchen
		body.set("is_in_kitchen", true)

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		body.set("is_in_kitchen", false)
