extends Label

func _process(_delta: float) -> void:
	self.text = "Power Left: " + str(GameData.power)
