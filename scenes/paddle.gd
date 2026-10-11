extends CharacterBody3D

@export var speed: float = 6.0
@export var side_limit: float = 4.0
@export var offline_test_paddle_name: StringName = &"Paddle_PosZ"
@export_range(0.0, 1.0, 0.05) var bot_accuracy: float = 0.78
@export var bot_reaction_time: float = 0.22
@export var mouse_sensitivity: float = 0.003

var bot_enabled := true
var match_active := false
var eliminated := false
var _rng := RandomNumberGenerator.new()
var _bot_timer := 0.0
var _bot_target := Vector2.ZERO
var _camera_base_rotation := Vector3.ZERO
var _camera_base_position := Vector3.ZERO
var _look_yaw := 0.0
var _look_pitch := 0.0


func _ready() -> void:
	_rng.randomize()
	var camera := _get_face_camera()
	if camera != null:
		_camera_base_rotation = camera.rotation
		_camera_base_position = camera.position
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer and name == offline_test_paddle_name:
		bot_enabled = false
		if camera != null:
			camera.make_current()


func _physics_process(delta: float) -> void:
	if not match_active or eliminated:
		return
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		if name == offline_test_paddle_name and not bot_enabled:
			_move_from_keyboard(delta)
		else:
			_run_bot(delta)
		return
	if multiplayer.is_server() and bot_enabled:
		_run_bot(delta)
	elif is_multiplayer_authority() and not bot_enabled:
		_move_from_keyboard(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not match_active or not _is_local_human():
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_yaw = clampf(_look_yaw - event.relative.x * mouse_sensitivity, -PI * 0.5, PI * 0.5)
		_look_pitch = clampf(_look_pitch - event.relative.y * mouse_sensitivity, -PI / 4.0, PI / 4.0)
		var camera := _get_face_camera()
		if camera != null:
			camera.rotation = _camera_base_rotation + Vector3(_look_pitch, _look_yaw, 0.0)
			var yaw_orbit := Basis(Vector3.UP, _look_yaw)
			var pitch_orbit := Basis(Vector3.RIGHT, _look_pitch)
			camera.position = yaw_orbit * pitch_orbit * _camera_base_position


func _move_from_keyboard(delta: float) -> void:
	var x := Input.get_axis("paddle_left", "paddle_right")
	var y := Input.get_axis("paddle_down", "paddle_up")
	var input_vector := Vector2(x, y).limit_length(1.0)
	var face_direction := input_vector
	var anchor := get_parent() as Node3D
	var camera := _get_face_camera()
	if camera != null and anchor != null:
		var camera_right := anchor.global_basis.inverse() * camera.global_basis.x
		var camera_up := anchor.global_basis.inverse() * camera.global_basis.y
		face_direction = Vector2(
			camera_right.x * input_vector.x + camera_up.x * input_vector.y,
			camera_right.y * input_vector.x + camera_up.y * input_vector.y
		)
		if face_direction.length_squared() > 0.0:
			face_direction = face_direction.normalized()
	position.x = clampf(position.x + face_direction.x * speed * delta, -side_limit, side_limit)
	position.y = clampf(position.y + face_direction.y * speed * delta, -side_limit, side_limit)
	position.z = 0.0


func _run_bot(delta: float) -> void:
	if not multiplayer.is_server() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	var ball := get_tree().get_first_node_in_group("ball") as Node3D
	var anchor := get_parent() as Node3D
	if ball == null or anchor == null:
		return
	_bot_timer += delta
	if _bot_timer >= bot_reaction_time:
		_bot_timer = 0.0
		var local_ball := anchor.to_local(ball.global_position)
		var miss_margin := (1.0 - bot_accuracy) * 3.5
		_bot_target = Vector2(
			local_ball.x + _rng.randf_range(-miss_margin, miss_margin),
			local_ball.y + _rng.randf_range(-miss_margin, miss_margin)
		).clamp(Vector2(-side_limit, -side_limit), Vector2(side_limit, side_limit))
	var difference := _bot_target - Vector2(position.x, position.y)
	var bot_speed := speed * lerpf(0.55, 1.0, bot_accuracy)
	var step := difference.limit_length(bot_speed * delta)
	position.x = clampf(position.x + step.x, -side_limit, side_limit)
	position.y = clampf(position.y + step.y, -side_limit, side_limit)
	position.z = 0.0


func _is_local_human() -> bool:
	if bot_enabled or eliminated:
		return false
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return name == offline_test_paddle_name
	return is_multiplayer_authority()


func set_match_active(active: bool) -> void:
	match_active = active
	if not active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif _is_local_human():
		var camera := _get_face_camera()
		if camera != null:
			camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_bot_mode(enabled: bool) -> void:
	bot_enabled = enabled


func set_eliminated(value: bool) -> void:
	eliminated = value
	visible = not value
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		shape.set_deferred("disabled", value)


@rpc("any_peer", "call_local", "reliable")
func assign_network_owner(peer_id: int, use_bot: bool) -> void:
	# Ownership changes are issued by the server; reject client attempts to
	# assign a face to themselves or another peer.
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != 1:
		return
	set_multiplayer_authority(peer_id, true)
	bot_enabled = use_bot
	if peer_id == multiplayer.get_unique_id() and not use_bot:
		var camera := _get_face_camera()
		if camera != null:
			camera.make_current()


func _get_face_camera() -> Camera3D:
	var anchor := get_parent() as Node3D
	if anchor == null:
		return null
	for child in anchor.get_children():
		if child is Camera3D:
			return child as Camera3D
	return null
