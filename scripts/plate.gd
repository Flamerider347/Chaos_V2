extends RigidBody3D

var type = "plate"
var stacked_items: Array = []

var is_two_handed: bool:
	get:
		return stacked_items.size() > 0

func _ready() -> void:
	GDSync.expose_node(self)
	GDSync.expose_func(sync_stack)

func stack_item(item: Node) -> void:
	if not is_instance_valid(item): return
	var offset = calculate_stack_height()
	
	var item_state = item.state if "state" in item else ""
	var item_cookedness = item.cookedness if "cookedness" in item else 0.0

	if GameData.connected:
		GDSync.call_func_all(sync_stack, [item.get_path(), offset, item_state, item_cookedness])
	else:
		execute_stack(item, offset, item_state, item_cookedness)

func sync_stack(params: Array) -> void:
	var item = get_node_or_null(params[0])
	if is_instance_valid(item): 
		execute_stack(item, params[1], params[2], params[3])

func execute_stack(item: Node, offset: float, forced_state: String, forced_cookedness: float) -> void:
	if "state" in item: item.state = forced_state
	if "cookedness" in item: item.cookedness = forced_cookedness
	
	if item.has_method("update_mesh_visibility_by_state"):
		item.update_mesh_visibility_by_state()
	
	if item is RigidBody3D: 
		item.freeze = true
		
	# REMOVED: Hitbox duplication that allowed players to steal from the plate
	var col = item.find_child("CollisionShape3D")
	if col:
		col.disabled = true
	
	if not stacked_items.has(item): stacked_items.append(item)
	if item.get_parent() != self: item.reparent(self)
	
	item.position = Vector3(0, offset, 0)
	item.rotation = Vector3.ZERO
	item.show() 
	
	var p = get_tree().get_first_node_in_group("player")
	if p:
		if p.has_method("check_two_handed_status"): p.check_two_handed_status()
		if p.has_method("update_inventory_ui"): p.update_inventory_ui()

func calculate_stack_height() -> float:
	var h: float = 0.05
	for node in stacked_items:
		if not is_instance_valid(node): continue
		var col = node.find_child("CollisionShape3D")
		if col and col.shape:
			if col.shape is BoxShape3D: h += col.shape.size.y
			elif col.shape is CylinderShape3D or col.shape is CapsuleShape3D: h += col.shape.height
			elif col.shape is SphereShape3D: h += col.shape.radius * 2.0
		else: h += 0.1
	return h
