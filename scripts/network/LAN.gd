extends Node

func start_server() -> void:
	GameData.host_game()

func start_client() -> void:
	# Look up the tree into the UI node to grab the input text
	var target_code_node = get_node("../menu_UI/join_code")
	if not target_code_node: return
	var target_port_node = get_node("../menu_UI/port")
	if not target_port_node: return
	
	var target_ip: String = target_code_node.text.strip_edges()
	if target_ip == "":
		target_ip = "127.0.0.1" # Standard local loopback fallback
	var target_port: int = int(target_port_node.text.strip_edges())
	
	GameData.join_game(target_ip, target_port)
