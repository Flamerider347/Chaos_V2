extends Label

func _process(_delta: float) -> void:
	if self.name == "score":
		self.text = "Current Power: " + str(GameData.power)
