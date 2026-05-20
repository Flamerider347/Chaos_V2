extends RigidBody3D

var type = "plate"
var stacked_items: Array = []

func _ready() -> void:
	GDSync.expose_node(self)
	GDSync.expose_func(sync_stack)

func stack_item(item: Node) -> void:
	if not is_instance_valid(item): return
	var offset = calculate_stack_height()
	if GameData.connected:
		GDSync.call_func_all(sync_stack, [item.get_path(), offset])
	else:
		execute_stack(item, offset)

func sync_stack(params: Array) -> void:
	var item = get_node_or_null(params[0])
	if is_instance_valid(item): execute_stack(item, params[1])

func execute_stack(item: Node, offset: float) -> void:
	if item is RigidBody3D: item.freeze = true
	var col = item.find_child("CollisionShape3D")
	if col: col.disabled = true
	
	if not stacked_items.has(item): stacked_items.append(item)
	if item.get_parent() != self: item.reparent(self)
	
	item.position = Vector3(0, offset, 0); item.rotation = Vector3.ZERO; item.show() 
	
	var p = get_tree().get_first_node_in_group("player")
	if p and p.has_method("update_inventory_ui"): p.update_inventory_ui()

func calculate_stack_height() -> float:
	var h: float = 0.1
	for node in stacked_items:
		if not is_instance_valid(node): continue
		var col = node.find_child("CollisionShape3D")
		if col and col.shape:
			if col.shape is BoxShape3D: h += col.shape.size.y
			elif col.shape is CylinderShape3D or col.shape is CapsuleShape3D: h += col.shape.height
			elif col.shape is SphereShape3D: h += col.shape.radius * 2.0
		else: h += 0.1
	return h
