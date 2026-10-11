extends Node

signal match_started
signal match_finished

@export var time_limit_seconds: float = 180.0
@export var starting_lives: int = 3

var match_active := false
var round_number := 1
var time_remaining := 180.0
var lives: Dictionary = {}
var _paddles: Dictionary = {}
var _score_lock := false
var _hud_layer: CanvasLayer
var _hud_label: Label
var _sound_players: Array[AudioStreamPlayer] = []
var _sound_index := 0
var _publish_timer := 0.0


func _ready() -> void:
	time_remaining = time_limit_seconds
	var ball := get_node_or_null("../Ball")
	if ball != null and ball.has_signal("bounced"):
		ball.bounced.connect(_on_ball_bounced)
	for paddle in get_tree().get_nodes_in_group("paddles"):
		_paddles[paddle.name] = paddle
		lives[paddle.name] = starting_lives
		_create_score_area(paddle)
	_build_hud()
	_build_sounds()
	_publish_state("")


func _process(delta: float) -> void:
	if not match_active or not _is_authoritative():
		return
	time_remaining = maxf(0.0, time_remaining - delta)
	_publish_timer += delta
	if _publish_timer >= 0.35:
		_publish_timer = 0.0
		_publish_state("")
	if time_remaining <= 0.0:
		_end_by_lives()


func _create_score_area(paddle: Node) -> void:
	var anchor := paddle.get_parent() as Node3D
	if anchor == null:
		return
	var goal := Area3D.new()
	goal.name = "ScoringBox_" + String(paddle.name)
	goal.collision_layer = 0
	goal.collision_mask = 1
	goal.monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(9.9, 9.9, 0.25)
	shape.shape = box
	goal.add_child(shape)
	var outward := anchor.global_position.normalized()
	var local_outward := anchor.global_basis.inverse() * outward
	# Put the trigger on the wall plane, beyond the paddle, so a clean paddle
	# hit bounces first while a miss passes through this non-solid Area3D.
	goal.position = Vector3(0.0, 0.0, 0.30 if local_outward.z >= 0.0 else -0.30)
	anchor.add_child(goal)
	goal.body_entered.connect(_on_scoring_box_entered.bind(String(paddle.name)))


func _on_scoring_box_entered(body: Node3D, face_name: String) -> void:
	if not match_active or not _is_authoritative() or _score_lock:
		return
	if not body.is_in_group("ball") or int(lives.get(face_name, 0)) <= 0:
		return
	_score_lock = true
	var ball := get_node_or_null("../Ball")
	if ball != null:
		ball.call_deferred("stop_ball")
	call_deferred("_apply_score", face_name)


func _apply_score(face_name: String) -> void:
	lives[face_name] = maxi(0, int(lives[face_name]) - 1)
	var is_eliminated := int(lives[face_name]) == 0
	if is_eliminated:
		_broadcast_face_eliminated(face_name, true)
	round_number += 1
	var ball := get_node_or_null("../Ball")
	if ball != null:
		ball.increase_speed_for_round()
	_broadcast_sound("score")
	_publish_state("%s lost a life" % face_name)
	if _active_face_count() <= 1:
		var winner := _last_active_face()
		_finish_match(winner)
		return
	await get_tree().create_timer(0.8).timeout
	if match_active and ball != null:
		ball.reset_to_center()
		ball.serve()
	_score_lock = false


func _active_face_count() -> int:
	var count := 0
	for face_name in lives:
		if int(lives[face_name]) > 0:
			count += 1
	return count


func _last_active_face() -> String:
	for face_name in lives:
		if int(lives[face_name]) > 0:
			return String(face_name)
	return "No one"


func _end_by_lives() -> void:
	var winner := "No one"
	var best := -1
	for face_name in lives:
		if int(lives[face_name]) > best:
			best = int(lives[face_name])
			winner = String(face_name)
	_finish_match(winner)


func _finish_match(winner: String) -> void:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		end_match(winner)
	else:
		rpc("end_match", winner)


func _broadcast_face_eliminated(face_name: String, value: bool) -> void:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		set_face_eliminated(face_name, value)
	else:
		rpc("set_face_eliminated", face_name, value)


func begin_local_test() -> void:
	if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	_begin_match_local()


@rpc("authority", "call_local", "reliable")
func begin_match() -> void:
	_begin_match_local()


@rpc("authority", "call_remote", "reliable")
func sync_active_match(seconds_left: float, round_value: int, lives_state: Dictionary) -> void:
	# A player joining late gets the current match state from the host.
	match_active = true
	time_remaining = seconds_left
	round_number = round_value
	lives = lives_state.duplicate(true)
	for face_name in _paddles:
		var face := String(face_name)
		set_face_eliminated(face, int(lives.get(face, 0)) <= 0)
		_paddles[face_name].set_match_active(true)
	receive_hud_state(time_remaining, round_number, lives, "Joined current match", true)
	match_started.emit()


func _begin_match_local() -> void:
	match_active = true
	_score_lock = false
	round_number = 1
	time_remaining = time_limit_seconds
	for face_name in _paddles:
		lives[face_name] = starting_lives
		set_face_eliminated(String(face_name), false)
		_paddles[face_name].set_match_active(true)
	var ball := get_node_or_null("../Ball")
	if ball != null:
		ball.speed = ball.start_speed
		ball.serve()
	_publish_state("Match started")
	_broadcast_sound("serve")
	match_started.emit()


@rpc("authority", "call_local", "reliable")
func end_match(winner: String) -> void:
	match_active = false
	_score_lock = false
	var ball := get_node_or_null("../Ball")
	if ball != null:
		ball.stop_ball()
	for paddle in _paddles.values():
		paddle.set_match_active(false)
	_publish_state("Winner: %s" % winner)
	_broadcast_sound("game_over")
	match_finished.emit()


@rpc("authority", "call_local", "reliable")
func set_face_eliminated(face_name: String, value: bool) -> void:
	var paddle: Node = _paddles.get(face_name)
	if paddle != null:
		paddle.set_eliminated(value)
	# Empty faces become solid again so the ball stays inside the cube.
	var face_direction := face_name.trim_prefix("Paddle_")
	var wall := get_node_or_null("../Wall_" + face_direction + "/WallBody") as StaticBody3D
	if wall != null:
		wall.collision_layer = 1 if value else 0
		wall.collision_mask = 1 if value else 0


func _is_authoritative() -> bool:
	return multiplayer.multiplayer_peer is OfflineMultiplayerPeer or multiplayer.is_server()


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "GameHUD"
	_hud_layer.layer = 2
	add_child(_hud_layer)
	_hud_label = Label.new()
	_hud_label.position = Vector2(22, 20)
	_hud_label.add_theme_font_size_override("font_size", 20)
	_hud_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_hud_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_hud_label.add_theme_constant_override("shadow_offset_x", 2)
	_hud_label.add_theme_constant_override("shadow_offset_y", 2)
	_hud_layer.add_child(_hud_label)
	_hud_layer.hide()


func _publish_state(message: String) -> void:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		receive_hud_state(time_remaining, round_number, lives.duplicate(true), message, match_active)
	elif multiplayer.is_server():
		rpc("receive_hud_state", time_remaining, round_number, lives.duplicate(true), message, match_active)


@rpc("authority", "call_local", "unreliable")
func receive_hud_state(seconds_left: float, round_value: int, lives_state: Dictionary, message: String, active: bool) -> void:
	if _hud_label == null:
		return
	var lines := ["Time  %s      Round  %d" % [_format_time(seconds_left), round_value]]
	for face_name in lives_state:
		lines.append("%s  %d lives" % [String(face_name).replace("Paddle_", ""), int(lives_state[face_name])])
	if message != "":
		lines.insert(1, message)
	if not active and message.begins_with("Winner:"):
		lines.append("Game over — press Esc to release the mouse")
	_hud_label.text = "\n".join(lines)
	_hud_layer.visible = active or message.begins_with("Winner:")


func _format_time(value: float) -> String:
	var total := int(ceil(value))
	return "%02d:%02d" % [int(total / 60), total % 60]


func _build_sounds() -> void:
	for i in range(5):
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer%d" % i
		player.volume_db = -8.0
		add_child(player)
		_sound_players.append(player)


func _on_ball_bounced() -> void:
	if _is_authoritative() and match_active:
		_broadcast_sound("hit")


func _broadcast_sound(effect: String) -> void:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_play_sfx_local(effect)
	elif multiplayer.is_server():
		rpc("play_sfx", effect)


@rpc("authority", "call_local", "unreliable")
func play_sfx(effect: String) -> void:
	_play_sfx_local(effect)


func _play_sfx_local(effect: String) -> void:
	var frequency := 440.0
	var duration := 0.08
	match effect:
		"hit":
			frequency = 620.0
			duration = 0.045
		"score":
			frequency = 250.0
			duration = 0.22
		"serve":
			frequency = 520.0
			duration = 0.16
		"game_over":
			frequency = 180.0
			duration = 0.35
	var sample_rate := 22050
	var sample_count := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for i in range(sample_count):
		var envelope := minf(1.0, float(i) / 180.0) * (1.0 - float(i) / sample_count)
		var sample := sin(TAU * frequency * float(i) / sample_rate) * envelope * 0.35
		bytes.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = bytes
	var player := _sound_players[_sound_index]
	_sound_index = (_sound_index + 1) % _sound_players.size()
	player.stream = stream
	player.play()
