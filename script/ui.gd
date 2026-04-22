extends CanvasLayer


func _on_host_button_pressed():
	$UI.hide()
	Main.host()  # or however you reference Main

func _on_join_button_pressed():
	$UI.hide()
	Main.join("SERVER_IP_HERE")

func _on_join_pressed() -> void:
	pass # Replace with function body.


func _on_host_pressed() -> void:
	pass # Replace with function body.
