extends Node3D

# Redirect local scene tracking directly to our updated global variables
var score: int:
	get: return GameData.score
	set(val): 
		GameData.score = val
		thing_ui_update()

var power: int:
	get: return GameData.power
	set(val): GameData.power = val

func _ready() -> void:
	thing_ui_update()

# Refreshes the score display on the user interface screen
func thing_ui_update() -> void:
	var score_lbl = get_node_or_null("/root/main/UI/score_label") # Update to match your actual UI node name
	if score_lbl:
		score_lbl.text = "Score: " + str(GameData.score)
