extends RigidBody3D

var type = "plate"
var stacked_items: Array = []
var is_two_handed: bool = false

func _ready() -> void:
	pass

func stack_item(item: Node) -> void:
	if not is_instance_valid(item): return
	var offset = calculate_stack_height()
	var item_state = item.state if "state" in item else ""
	var item_cookedness = item.cookedness if "cookedness" in item else 0.0
	var item_path = str(item.get_path())
	
	# 1. Execute locally immediately
	execute_stack(item, offset, item_state, item_cookedness)
	
	# 2. Tell the network
	if multiplayer.is_server():
		rpc("client_sync_stack", item_path, offset, item_state, item_cookedness, multiplayer.get_unique_id())
	else:
		rpc_id(1, "request_stack_on_server", item_path, offset, item_state, item_cookedness, multiplayer.get_unique_id())

@rpc("any_peer", "reliable")
func request_stack_on_server(item_path: String, offset: float, forced_state: String, forced_cookedness: float, sender_id: int) -> void:
	if not multiplayer.is_server(): return
		
	var item = get_node_or_null(item_path)
	if is_instance_valid(item):
		execute_stack(item, offset, forced_state, forced_cookedness)
	
	rpc("client_sync_stack", item_path, offset, forced_state, forced_cookedness, sender_id)

@rpc("authority", "reliable")
func client_sync_stack(item_path: String, offset: float, forced_state: String, forced_cookedness: float, sender_id: int) -> void:
	if multiplayer.get_unique_id() == sender_id: return
		
	var item = get_node_or_null(item_path)
	if not is_instance_valid(item): return
		
	execute_stack(item, offset, forced_state, forced_cookedness)

func execute_stack(item: Node, offset: float, forced_state: String, forced_cookedness: float) -> void:
	if "state" in item: item.state = forced_state
	if "cookedness" in item: item.cookedness = forced_cookedness
	
	if item.has_method("update_mesh_visibility_by_state"):
		item.update_mesh_visibility_by_state()
	
	if item is RigidBody3D: 
		item.freeze = true
		
	var col = item.find_child("CollisionShape3D")
	if col:
		col.set_deferred("disabled", true)
	
	if not stacked_items.has(item): stacked_items.append(item)
	is_two_handed = stacked_items.size() > 0
	
	var binder_name = "bind_" + item.name
	var remote_transform = get_node_or_null(binder_name)
	if not remote_transform:
		remote_transform = RemoteTransform3D.new()
		remote_transform.name = binder_name
		remote_transform.use_global_coordinates = true
		remote_transform.update_scale = false
		add_child(remote_transform)
	
	remote_transform.remote_path = item.get_path()
	remote_transform.position = Vector3(0, offset, 0)
	remote_transform.rotation = Vector3.ZERO
	
	item.show() 
	
	var p = get_tree().get_first_node_in_group("player")
	if p:
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
