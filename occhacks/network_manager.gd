extends Node3D

const GAME_PORT := 8910
const DISCOVERY_PORT := 8911
const MAX_PLAYERS := 6
const DISCOVERY_MESSAGE := "CUBE_PONG_HOST"

var available_paddles: Array[Node] = []
var assigned_paddles: Dictionary = {}

var discovery_listener: PacketPeerUDP
var beacon_sender: PacketPeerUDP
var beacon_timer := 0.0


func _ready() -> void:
	# All six paddles must be in the "paddles" group.
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
		start_discovery()


func start_host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(GAME_PORT, MAX_PLAYERS - 1)

	if error != OK:
		push_error("Could not start host. Error code: %s" % error)
		return

	multiplayer.multiplayer_peer = peer
	print("Hosting on port ", GAME_PORT)

	# Peer 1 is the host.
	_assign_next_paddle(1)
	_start_host_beacon()


func start_discovery() -> void:
	if discovery_listener != null:
		return

	discovery_listener = PacketPeerUDP.new()
	var error := discovery_listener.bind(DISCOVERY_PORT)

	if error != OK:
		push_error("Could not listen for LAN games. Error code: %s" % error)
		discovery_listener = null
		return

	print("Searching for a LAN host...")


func join_host(host_ip: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(host_ip, GAME_PORT)

	if error != OK:
		push_error("Could not connect to host. Error code: %s" % error)
		return

	multiplayer.multiplayer_peer = peer
	print("Connecting to ", host_ip, ":", GAME_PORT)


func _start_host_beacon() -> void:
	beacon_sender = PacketPeerUDP.new()
	beacon_sender.set_broadcast_enabled(true)

	var error := beacon_sender.set_dest_address(
		"255.255.255.255",
		DISCOVERY_PORT
	)

	if error != OK:
		push_error("Could not set LAN broadcast address. Error code: %s" % error)
		beacon_sender = null
		return

	_send_host_beacon()


func _process(delta: float) -> void:
	# Announce the host once per second.
	if beacon_sender != null:
		beacon_timer += delta
		if beacon_timer >= 1.0:
			beacon_timer = 0.0
			_send_host_beacon()

	# Check for a host announcement.
	if discovery_listener != null:
		while discovery_listener.get_available_packet_count() > 0:
			var message := discovery_listener.get_packet().get_string_from_utf8()

			if message == DISCOVERY_MESSAGE:
				var host_ip := discovery_listener.get_packet_ip()
				print("Found host at ", host_ip)

				discovery_listener.close()
				discovery_listener = null

				join_host(host_ip)
				return


func _send_host_beacon() -> void:
	if beacon_sender != null:
		beacon_sender.put_packet(DISCOVERY_MESSAGE.to_utf8_buffer())


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		print("Peer connected: ", peer_id)
		_assign_next_paddle(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	print("Peer disconnected: ", peer_id)

	if assigned_paddles.has(peer_id):
		var paddle: Node = assigned_paddles[peer_id]

		# Return the paddle to server authority and make it available again.
		paddle.rpc("assign_network_owner", 1)
		available_paddles.append(paddle)
		assigned_paddles.erase(peer_id)


func _assign_next_paddle(peer_id: int) -> void:
	if available_paddles.is_empty():
		print("No paddle available for peer ", peer_id)
		return

	var paddle: Node = available_paddles.pop_front()
	assigned_paddles[peer_id] = paddle

	# Assign this paddle on the host and all connected computers.
	paddle.rpc("assign_network_owner", peer_id)
	print("Assigned ", paddle.name, " to peer ", peer_id)
