extends Node3D

var valid_food_types := ["cheese", "toamto", "bun", "meat_raw"]

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass


func _on_input_body_entered(body):
	var type = body.get("type")
	if type != null:
		if body.is_class("RigidBody3D"):
			print("fun")
			body.linear_velocity.y = 4
			body.linear_velocity.x = randf_range(-3, 3)
			body.linear_velocity.z = randf_range(-3, 3)
		else:
			print("static")
