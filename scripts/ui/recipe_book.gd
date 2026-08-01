extends Node
class_name RecipeUI

@onready var return_btn = get_orphan_node_ids()

func _ready() -> void:
	var btn = get_node_or_null()

func toggle() -> void:
	self.visible = !self.visible
	
	
