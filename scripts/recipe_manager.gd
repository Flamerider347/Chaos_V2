extends Node

var recipes: Dictionary[String, RecipeData] = {}

func _ready():
	load_all_recipes_from_folder("res://resources/recipes/")
	print(recipes)
	print(typeof(recipes))
	for recipe in recipes.values():
		print(recipe.recipe_internal)
		print(recipe.recipe_display)
		print(recipe.unlock_day)
		print(recipe.value)
		print(recipe.components)
		print(recipe.is_burger)
		print("-------")

func load_all_recipes_from_folder(path: String) -> void:
	var resources: PackedStringArray = ResourceLoader.list_directory(path)
	for resource in resources:
		if resource.ends_with(".tres"):
			var loaded_resource: RecipeData = ResourceLoader.load(path+resource)
			var key_parsed: String = ""
			var sorted_components = loaded_resource.components.duplicate()
			sorted_components.sort()
			for component in sorted_components:
				key_parsed += component + ","
			key_parsed = key_parsed.rstrip(",")
			recipes[key_parsed] = loaded_resource
			
