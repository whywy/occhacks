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
var discovered_host_ip := ""
var lobby_overlay: ColorRect
var status_label: Label
var roster_label: Label
var host_button: Button
var join_button: Button
var start_button: Button
var local_button: Button
var game_manager: Node


func _ready() -> void:
	game_manager = get_node_or_null("GameManager")
	var paddles := get_tree().get_nodes_in_group("paddles")
	paddles.sort_custom(func(a: Node, b: Node) -> bool: return a.name < b.name)
	available_paddles.assign(paddles)
	for paddle in available_paddles:
		if paddle.has_method("set_bot_mode"):
			paddle.set_bot_mode(true)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_build_lobby_ui()
	if game_manager != null and game_manager.has_signal("match_started"):
		game_manager.match_started.connect(_on_match_started)
		game_manager.match_finished.connect(_on_match_finished)
	_update_lobby_display()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start_host"):
		start_host()
	elif event.is_action_pressed("join_host"):
		start_discovery()


func _build_lobby_ui() -> void:
	lobby_overlay = ColorRect.new()
	lobby_overlay.name = "LobbyOverlay"
	lobby_overlay.color = Color(0.015, 0.025, 0.06, 0.94)
	lobby_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 640)
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.text = "CUBE PONG"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Six faces. One ball. Keep yours alive."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status_label)
	host_button = Button.new()
	host_button.text = "Host LAN game"
	host_button.pressed.connect(start_host)
	box.add_child(host_button)
	join_button = Button.new()
	join_button.text = "Find a host on this LAN"
	join_button.pressed.connect(start_discovery)
	box.add_child(join_button)
	start_button = Button.new()
	start_button.text = "Start match (host)"
	start_button.pressed.connect(_start_match_pressed)
	box.add_child(start_button)
	local_button = Button.new()
	local_button.text = "Local test (WASD + bots)"
	local_button.pressed.connect(_start_local_test)
	box.add_child(local_button)
	var roster_title := Label.new()
	roster_title.text = "Players and face assignments"
	roster_title.add_theme_font_size_override("font_size", 20)
	box.add_child(roster_title)
	roster_label = Label.new()
	roster_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	roster_label.custom_minimum_size = Vector2(0, 170)
	roster_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	box.add_child(roster_label)
	var footer := Label.new()
	footer.text = "WASD moves · Mouse looks · Esc releases mouse · F1 host · F2 find host"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 13)
	box.add_child(footer)
	add_child(lobby_overlay)


func start_host() -> void:
	if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(GAME_PORT, MAX_PLAYERS - 1)
	if error != OK:
		_set_status("Could not host. Error %s" % error)
		return
	multiplayer.multiplayer_peer = peer
	_assign_next_paddle(1)
	_start_host_beacon()
	_set_status("Hosting on port %d. Waiting for players." % GAME_PORT)
	_push_roster()
	_update_lobby_display()


func start_discovery() -> void:
	if discovery_listener != null:
		return
	discovery_listener = PacketPeerUDP.new()
	var error := discovery_listener.bind(DISCOVERY_PORT)
	if error != OK:
		discovery_listener = null
		_set_status("Could not listen for LAN games. Error %s" % error)
		return
	_set_status("Searching for a host on your LAN…")


func join_host(host_ip: String) -> void:
	if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(host_ip, GAME_PORT)
	if error != OK:
		_set_status("Could not connect to %s. Error %s" % [host_ip, error])
		return
	discovered_host_ip = host_ip
	multiplayer.multiplayer_peer = peer
	_set_status("Connecting to %s…" % host_ip)
	_update_lobby_display()


func _start_host_beacon() -> void:
	beacon_sender = PacketPeerUDP.new()
	beacon_sender.set_broadcast_enabled(true)
	var error := beacon_sender.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	if error != OK:
		beacon_sender = null
		_set_status("Hosting; LAN discovery could not broadcast (UDP %d)." % DISCOVERY_PORT)
		return
	_send_host_beacon()


func _process(delta: float) -> void:
	if beacon_sender != null:
		beacon_timer += delta
		if beacon_timer >= 1.0:
			beacon_timer = 0.0
			_send_host_beacon()
	if discovery_listener != null:
		while discovery_listener.get_available_packet_count() > 0:
			var message := discovery_listener.get_packet().get_string_from_utf8()
			if message == DISCOVERY_MESSAGE:
				discovered_host_ip = discovery_listener.get_packet_ip()
				discovery_listener.close()
				discovery_listener = null
				join_host(discovered_host_ip)
				return


func _send_host_beacon() -> void:
	if beacon_sender != null:
		beacon_sender.put_packet(DISCOVERY_MESSAGE.to_utf8_buffer())


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_assign_next_paddle(peer_id)
	if game_manager != null and game_manager.match_active:
		game_manager.rpc_id(peer_id, "sync_active_match", game_manager.time_remaining, game_manager.round_number, game_manager.lives.duplicate(true))
	_push_roster()


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if assigned_paddles.has(peer_id):
		var paddle: Node = assigned_paddles[peer_id]
		paddle.rpc("assign_network_owner", 1, true)
		available_paddles.append(paddle)
		available_paddles.sort_custom(func(a: Node, b: Node) -> bool: return a.name < b.name)
		assigned_paddles.erase(peer_id)
	_push_roster()


func _assign_next_paddle(peer_id: int) -> void:
	if available_paddles.is_empty():
		return
	var paddle: Node = available_paddles.pop_front()
	assigned_paddles[peer_id] = paddle
	paddle.rpc("assign_network_owner", peer_id, false)
	_push_roster()


func _push_roster() -> void:
	if not multiplayer.is_server():
		return
	var rows: Array[String] = []
	var host_ip := _local_ipv4()
	var host_paddle: Node = assigned_paddles.get(1)
	rows.append("HOST  %s  →  %s" % [host_ip, host_paddle.name if host_paddle != null else "No face"])
	var peer_ids := multiplayer.get_peers()
	peer_ids.sort()
	for peer_id in peer_ids:
		var ip := "unknown IPv4"
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if enet != null and enet.get_peer(peer_id) != null:
			ip = enet.get_peer(peer_id).get_remote_address()
		var paddle: Node = assigned_paddles.get(peer_id)
		rows.append("PLAYER  %s  →  %s" % [ip, paddle.name if paddle != null else "Spectating"])
	for paddle in available_paddles:
		rows.append("BOT  %s" % paddle.name)
	rpc("receive_roster", rows)


@rpc("authority", "call_local", "reliable")
func receive_roster(rows: Array[String]) -> void:
	roster_label.text = "\n".join(rows)
	_update_lobby_display()


@rpc("any_peer", "call_remote", "reliable")
func request_lobby_roster() -> void:
	if multiplayer.is_server():
		_push_roster()


func _local_ipv4() -> String:
	var addresses := IP.get_local_addresses()
	var ten_net := ""
	var other_private := ""
	var fallback := ""
	for address in addresses:
		if address.contains(":") or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		if address.begins_with("192.168."):
			return address
		if address.begins_with("10.") and ten_net.is_empty():
			ten_net = address
		elif address.begins_with("172.") and other_private.is_empty():
			var parts := address.split(".")
			if parts.size() > 1 and int(parts[1]) >= 16 and int(parts[1]) <= 31:
				other_private = address
			elif fallback.is_empty():
				fallback = address
		elif fallback.is_empty():
			fallback = address
	if not ten_net.is_empty():
		return ten_net
	if not other_private.is_empty():
		return other_private
	return fallback if not fallback.is_empty() else "127.0.0.1"


func _on_connected_to_server() -> void:
	_set_status("Connected to %s. Waiting for the host to start." % discovered_host_ip)
	rpc_id(1, "request_lobby_roster")
	_update_lobby_display()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	discovered_host_ip = ""
	_set_status("Connection failed. Check that the host is on this LAN and try again.")
	_update_lobby_display()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	discovered_host_ip = ""
	_set_status("Host disconnected. You can search again.")
	_update_lobby_display()


func _start_match_pressed() -> void:
	if multiplayer.is_server() and game_manager != null:
		game_manager.rpc("begin_match")


func _start_local_test() -> void:
	if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer or game_manager == null:
		return
	var test_paddle_name := "Paddle_PosZ"
	for paddle in get_tree().get_nodes_in_group("paddles"):
		if paddle.name == "Paddle_PosZ":
			test_paddle_name = String(paddle.offline_test_paddle_name)
	for paddle in get_tree().get_nodes_in_group("paddles"):
		paddle.set_bot_mode(paddle.name != test_paddle_name)
	game_manager.begin_local_test()


func _on_match_started() -> void:
	lobby_overlay.hide()


func _on_match_finished() -> void:
	_set_status("Match complete. Host may start another match.")
	lobby_overlay.show()
	_update_lobby_display()


func _set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message


func _update_lobby_display() -> void:
	if status_label == null:
		return
	var offline := multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	host_button.disabled = not offline
	join_button.disabled = not offline
	start_button.visible = multiplayer.is_server() and not offline
	local_button.visible = offline
	if offline and roster_label.text.is_empty():
		var rows: Array[String] = []
		for paddle in available_paddles:
			rows.append("BOT  %s" % paddle.name)
		roster_label.text = "\n".join(rows)


func _exit_tree() -> void:
	if discovery_listener != null:
		discovery_listener.close()
	if beacon_sender != null:
		beacon_sender.close()
