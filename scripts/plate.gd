extends RigidBody3D

var type = "plate"
var stacked_items: Array = []

func _ready() -> void:
	GDSync.expose_node(self)
	GDSync.expose_func(sync_stack)

# Fired by the player who interacts with the plate
func stack_item(item: Node) -> void:
	if not is_instance_valid(item): return
	var target_y_offset = calculate_stack_height()
	
	if GameData.connected:
		GDSync.call_func_all(sync_stack, [item.get_path(), target_y_offset])
	else:
		execute_stack(item, target_y_offset)

# Executed across all connected client engines
func sync_stack(params: Array) -> void:
	var item = get_node_or_null(params[0])
	var target_y_offset = params[1]
	if is_instance_valid(item):
		execute_stack(item, target_y_offset)

func execute_stack(item: Node, target_y_offset: float) -> void:
	if item is RigidBody3D: item.freeze = true
	var col = item.find_child("CollisionShape3D")
	if col: col.disabled = true
	
	if not stacked_items.has(item): stacked_items.append(item)
	if item.get_parent() != self: item.reparent(self)
	
	item.position = Vector3(0, target_y_offset, 0)
	item.rotation = Vector3.ZERO
	item.show() 
	
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("update_inventory_ui"): player.update_inventory_ui()

func calculate_stack_height() -> float:
	var current_height: float = 0.0
	for stacked_node in stacked_items:
		if not is_instance_valid(stacked_node): continue
		var col_shape = stacked_node.find_child("CollisionShape3D")
		if col_shape and col_shape.shape:
			var shape = col_shape.shape
			if shape is BoxShape3D: current_height += shape.size.y
			elif shape is CylinderShape3D or shape is CapsuleShape3D: current_height += shape.height
			elif shape is SphereShape3D: current_height += shape.radius * 2.0
			else: current_height += 0.1
		else: current_height += 0.1
	return current_height
