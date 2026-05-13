extends Area3D

@onready var smoke_particle = preload("res://Prefabs/smoke_particle.tscn")
func _ready() -> void:
	GDSync.expose_func(_spawn_smoke)
func _on_body_entered(body) -> void:
	if body.is_in_group("player"):
		GDSync.call_func_all(_spawn_smoke, [body.global_position])
		body.position = Vector3(0, 5, 0)
	elif body.is_in_group("plate"):
		print(body.stacked_items)
	elif body.is_in_group("pickupable"):
		print(body.type)

func _spawn_smoke(pos: Vector3) -> void:
	var p = smoke_particle.instantiate()
	get_node("/root/main/game/items").add_child(p)
	p.global_position = pos
	p.emitting = true
	# Auto-free after particles finish
	await get_tree().create_timer(p.lifetime + 0.5).timeout
	p.queue_free()
