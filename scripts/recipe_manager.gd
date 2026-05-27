extends Node

var recipes: Dictionary[String, Dictionary] = {}
var recipe_key_lookup: Dictionary[String, String] = {}
var recipe_of_the_day = null
var recipe_of_the_day2 = null
func _ready():
	load_all_recipes_from_folder("res://resources/recipes/")

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
			recipe_key_lookup[key_parsed] = loaded_resource.recipe_internal
			recipes[loaded_resource.recipe_internal] = {
				"internal_name": loaded_resource.recipe_internal,
				"display_name": loaded_resource.recipe_display,
				"unlock_day": loaded_resource.unlock_day,
				"value": loaded_resource.value,
				"components": loaded_resource.components,
				"is_burger": loaded_resource.is_burger,
			}
