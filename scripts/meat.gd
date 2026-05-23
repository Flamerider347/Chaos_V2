extends RigidBody3D

@export var type: String = "meat"
@export var state: String = "raw" # Set this to "cooked" or "burnt" in their respective scenes

func _ready() -> void:
	GDSync.expose_node(self)
	
	# Ensure it belongs to the proper groups based on its saved scene file
	add_to_group("pickupable")
	if state == "cooked":
		add_to_group("plate_stackable")
