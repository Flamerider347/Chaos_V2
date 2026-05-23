extends RigidBody3D

@export var type: String = "meat_raw"
@export var state: String = "raw"

func _ready() -> void:
	GDSync.expose_node(self)
