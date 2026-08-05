extends Node

var recipes: Dictionary[String, Dictionary] = {}
var recipe_key_lookup: Dictionary = {}
var recipe_of_the_day = null
var recipe_of_the_day2 = null

func _ready():
	load_all_recipes_from_folder("res://resources/recipes/")

func get_matching_recipe(components: Array) -> String:
	if components.is_empty():
		return ""

	# 1. Normalize components to match resource formatting (lowercase, snake_case)
	var cleaned_components: Array[String] = []
	for comp in components:
		var raw_name = str(comp).to_lower().replace(" ", "_")
		cleaned_components.append(raw_name)

	# 2. Sort components
	cleaned_components.sort()

	# 3. Build lookup key (e.g. "bun,meat_cooked")
	var key_parsed: String = ",".join(cleaned_components)

	# 4. Look up in dictionary and return display_name
	if recipe_key_lookup.has(key_parsed):
		var internal_name = recipe_key_lookup[key_parsed]
		if recipes.has(internal_name):
			return recipes[internal_name].get("display_name", internal_name)
		return internal_name

	return ""

func load_all_recipes_from_folder(path: String) -> void:
	var resources: PackedStringArray = ResourceLoader.list_directory(path)
	for resource in resources:
		if resource.ends_with(".tres"):
			var loaded_resource: RecipeData = ResourceLoader.load(path + resource)
			
			# Normalize resource components upon loading
			var sorted_components: Array = []
			for comp in loaded_resource.components:
				sorted_components.append(str(comp).to_lower().replace(" ", "_"))
			sorted_components.sort()

			var key_parsed: String = ",".join(sorted_components)
			
			recipe_key_lookup[key_parsed] = loaded_resource.recipe_internal
			recipes[loaded_resource.recipe_internal] = {
				"internal_name": loaded_resource.recipe_internal,
				"display_name": loaded_resource.recipe_display,
				"unlock_day": loaded_resource.unlock_day,
				"value": loaded_resource.value,
				"components": loaded_resource.components,
				"is_burger": loaded_resource.is_burger,
			}
