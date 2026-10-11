extends Node3D

const PORT := 8910
const MAX_PLAYERS := 6

# Replace this with the host computer's LAN IPv4 address.
@export var host_ip := "10.0.62.13"

var available_paddles: Array[Node] = []
var assigned_paddles: Dictionary = {}


func _ready() -> void:
	var paddles := get_tree().get_nodes_in_group("paddles")
	paddles.sort_custom(func(a: Node, b: Node) -> bool:
		return a.name < b.name
	)

	available_paddles.assign(paddles)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start_host"):
		start_host()
	elif event.is_action_pressed("join_host"):
		join_host()


func start_host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_PLAYERS - 1)

	if error != OK:
		push_error("Could not start host. Error code: %s" % error)
		return

	multiplayer.multiplayer_peer = peer
	print("Hosting on port ", PORT)

	# The host is peer 1 and gets the first available paddle.
	_assign_next_paddle(1)


func join_host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(host_ip, PORT)

	if error != OK:
		push_error("Could not start client. Error code: %s" % error)
		return

	multiplayer.multiplayer_peer = peer
	print("Connecting to ", host_ip, ":", PORT)


func _on_peer_connected(peer_id: int) -> void:
	# This callback assigns paddles on the host.
	if multiplayer.is_server():
		_assign_next_paddle(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if assigned_paddles.has(peer_id):
		var paddle: Node = assigned_paddles[peer_id]
		paddle.rpc("assign_network_owner", 1)
		available_paddles.append(paddle)
		assigned_paddles.erase(peer_id)


func _assign_next_paddle(peer_id: int) -> void:
	if available_paddles.is_empty():
		print("No paddle available for peer ", peer_id)
		return

	var paddle: Node = available_paddles.pop_front()
	assigned_paddles[peer_id] = paddle

	# Broadcast the assignment; call_local also sets it on the host.
	paddle.rpc("assign_network_owner", peer_id)
	print("Assigned ", paddle.name, " to peer ", peer_id)
