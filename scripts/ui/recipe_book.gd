extends Node
class_name RecipeUI

var page_template: PackedScene = preload("res://Prefabs/UI/recipe_page.tscn")

@onready var exit_button: TextureButton = get_node_or_null("return") 
@onready var left_button: TextureButton = get_node_or_null("back")
@onready var right_button: TextureButton = get_node_or_null("forward")


var recipe_names = RecipeManager.recipes.keys()
var recipe_pointer: int = 0
var current_page: RecipePage


func _ready() -> void:
	update_display()
	create_page(RecipeManager.recipes[recipe_names[recipe_pointer]])


func toggle() -> void:
	GameData.in_recipe_book = !GameData.in_recipe_book
	self.visible = !self.visible
	exit_button.disabled = !exit_button.disabled
	left_button.disabled = !left_button.disabled
	right_button.disabled = !right_button.disabled
	update_display()
	

func update_display():
	if recipe_pointer == 0:
		left_button.disabled = true
		left_button.visible = false
	else:
		left_button.disabled = false
		left_button.visible = true
	
	if recipe_pointer + 1 == recipe_names.size():
		right_button.disabled = true
		right_button.visible = false
	else:
		right_button.disabled = false
		right_button.visible = true

	
func create_page(recipe_info):
	var page: RecipePage = page_template.instantiate()
	add_child(page)
	page.title.text = recipe_info["display_name"]
	page.value.text = "Value: " + str(recipe_info["value"])

	page.components.text = format_components(recipe_info["components"])
	page.name = str(recipe_pointer)
	if current_page:
		current_page.despawn()
	current_page = page


func format_components(component_list: Array[String]):
	var final_string: String = "Components:\n"
	var component_name_map: Dictionary[String, String] = {
		"bun_bottom_chopped": "Bottom bun",
		"bun_top_chopped": "Top bun",
		"carrot_chopped": "Sliced carrot",
		"tomato_chopped": "Sliced tomato",
		"cheese_chopped": "Sliced cheese",
		"lettuce_chopped": "Lettuce leaves",
		"meat_cooked": "Cooked burger patty",
	}
	component_list.reverse()
	for component in component_list:
		final_string += component_name_map[component] + "\n"
	return final_string




func _previous_recipe():
	print('left')
	current_page.z_index = 1
	recipe_pointer -= 1
	create_page(RecipeManager.recipes[recipe_names[recipe_pointer]])
	update_display()


func _next_recipe():
	print("right")
	current_page.z_index = 1
	recipe_pointer += 1
	create_page(RecipeManager.recipes[recipe_names[recipe_pointer]])
	update_display()


func _close_recipe():
	print("close")
	var player: Player = get_node_or_null("/root/main/players/" + str(multiplayer.get_unique_id()))
	if player:
		player.toggle_recipe_book()
