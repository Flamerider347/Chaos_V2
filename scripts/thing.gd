extends Area3D

@onready var smoke_particle: PackedScene = preload("res://Prefabs/smoke_particle.tscn")
@onready var score: Node = $"../../.."
var scores: Dictionary = {
	"cheese": 5,
	"cheese_chopped": 10,
	"tomato": 6,
	"tomato_chopped": 12,
}


func _ready() -> void:
	GDSync.expose_func(_spawn_smoke)
	
func _on_body_entered(body: Node) -> void:
	if GameData.connected:
		GDSync.call_func_all(_spawn_smoke, [body.global_position])
		_spawn_smoke(body.global_position)
	if body.is_in_group("player"):
		body.position = Vector3(0, 5, 0)
	elif body.is_in_group("plate"):
		var items: Array = body.stacked_items
		if len(items) > 1:
			for item_name in items:
				if scores.has(item_name):
					score.score += scores[item_name]
		print(body.stacked_items)
		body.queue_free()
	elif body.is_in_group("pickupable"):
		if scores.has(body.type):
			score.score += scores[body.type]
		print(body.type)
		body.queue_free()

func _spawn_smoke(pos: Vector3) -> void:
	var p = smoke_particle.instantiate()
	get_node("/root/main/game/items").add_child(p)
	p.global_position = pos
	p.emitting = true
	# Auto-free after particles finish
	await get_tree().create_timer(p.lifetime + 0.5).timeout
	p.queue_free()
