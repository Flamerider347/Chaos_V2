extends Node

var recipes: Dictionary = {}

func _ready():
	load_all_recipes_from_folder("res://recipes/")

func load_all_recipes_from_folder(path: String) -> void:
	pass
