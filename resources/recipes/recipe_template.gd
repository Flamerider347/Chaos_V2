extends Resource
class_name RecipeData

enum {}

@export var recipe_internal: String = ""
@export var recipe_display: String = ""
@export var unlock_day: int = 1
@export var value: int = 0
@export_enum("bun_bottom_chopped", "bun_top_chopped", "lettuce_chopped", "carrot_chopped", "tomato_chopped", "cheese_chopped", "meat_cooked") var components: Array[String] = []
@export var is_burger: bool
