extends Control
var current_text = 0
var max_text = 10
var texts = [
	"Welcome to Kitchen Chaos V2! 
	Controls:
	WASD/ARROW KEYS - Move
	SPACE - JUMP
	LEFT CLICK - PICKUP
	RIGHT - CLICK
	TAB - OPEN/CLOSE MENU",
	"You can alter your sensitivity
	 in the menu (Press TAB)",
	"John is a nice name",
	
]
func _ready() -> void:
	max_text = texts.size() -1
func _physics_process(_delta: float) -> void:
	
	if Input.is_action_just_pressed("close_tutorial"):
		if not self.visible:
			self.show()
		else:
			self.hide()
			
	if self.get_parent().name == "menu_UI":
		return
		
	if Input.is_action_just_pressed("previous_tutorial") and current_text > 0:
		current_text -= 1
		
	if Input.is_action_just_pressed("next_tutorial") and current_text < max_text:
		current_text += 1
	$Label.text = texts[current_text]
