extends RigidBody3D

var stacked_items = []

func _ready() -> void:
	GDSync.expose_func(stack_item)

func stack_item(item) -> void:
	item.show()
	if item and not item.is_held:
		stacked_items.append(item)
		item.freeze = true
		item.reparent(self)
		item.position = Vector3(0, 0.1 * stacked_items.size(), 0)
