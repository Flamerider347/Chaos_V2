extends RigidBody3D

var is_held: bool = false
var item_id: String = ""

func _ready() -> void:
	GDSync.expose_node(self)

func _on_reparented() -> void:
	GDSync.expose_node(self)
