extends Area3D

@onready var smoke_particle: PackedScene = preload("res://Prefabs/smoke_particle.tscn")
@onready var game: Node = $"../../.."
var scores: Dictionary = {
	"cheese": 5,
	"cheese_chopped": 10,
	"tomato": 6,
	"tomato_chopped": 12,
	"bun": 50,
	"bun_bottom_chopped": 40,
	"bun_top_chopped": 30,
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
		var item_nodes: Array = body.stacked_items
		var items: Array = []
		for item in item_nodes:
			items.append(item.type)
		
		var valid_burger := false
		if items:
			if items[0] == "bun_bottom_chopped" and items[-1] == "bun_top_chopped":
				valid_burger = true
		
		# Breaks item order information
		items.sort()
		var parsed_key := ""
		for item in items:
			parsed_key += item + ","
		parsed_key = parsed_key.rstrip(",")
		if parsed_key in RecipeManager.recipes:
			print(RecipeManager.recipes[parsed_key].recipe_internal	)
			if RecipeManager.recipes[parsed_key].is_burger:
				if valid_burger:
					game.score += RecipeManager.recipes[parsed_key].value
					body.queue_free()
					return
			else:
				game.score += RecipeManager.recipes[parsed_key].value
				body.queue_free()
				return
		
		for item_name in items:
			if scores.has(item_name):
				game.score += scores[item_name]
		print(items)
		body.queue_free()
	elif body.is_in_group("pickupable"):
		if scores.has(body.type):
			game.score += scores[body.type]
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
