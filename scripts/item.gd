extends RigidBody3D
var type = "generic thing"
var is_held: bool = false
var item_id: String = ""
@export var item_mesh: Mesh
func _ready() -> void:
	GDSync.expose_node(self)

func owner_changed(_owner_id: int) -> void:
	print("Item owner changed: ", _owner_id)
