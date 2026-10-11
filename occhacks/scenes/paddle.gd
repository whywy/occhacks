extends CharacterBody3D

@export var speed: float = 6.0
# The paddle's center must stay at least one unit inside each 10-unit face.
@export var side_limit: float = 4.0
# In offline F6 testing, only this paddle responds to the local keyboard.
@export var offline_test_paddle_name: StringName = &"Paddle_PosZ"


func _physics_process(delta: float) -> void:
	if not _can_read_local_input():
		return

	var input_x := Input.get_axis("paddle_left", "paddle_right")
	var input_y := Input.get_axis("paddle_down", "paddle_up")
	var move_input := Vector2(input_x, input_y).limit_length(1.0)
	var face_direction := move_input

	# If this face has its own camera, translate WASD into that camera's
	# screen-right/screen-up directions, then back into the face's local axes.
	# Without a PlayerCamera node (such as the current F6 setup), use face axes.
	var anchor := get_parent() as Node3D
	var camera := _get_face_camera()
	if camera != null:
		var camera_right := anchor.global_basis.inverse() * camera.global_basis.x
		var camera_up := anchor.global_basis.inverse() * camera.global_basis.y
		face_direction = Vector2(
			camera_right.x * move_input.x + camera_up.x * move_input.y,
			camera_right.y * move_input.x + camera_up.y * move_input.y
		)
		if face_direction.length_squared() > 0.0:
			face_direction = face_direction.normalized()

	position.x = clampf(position.x + face_direction.x * speed * delta, -side_limit, side_limit)
	position.y = clampf(position.y + face_direction.y * speed * delta, -side_limit, side_limit)
	position.z = 0.0


func _can_read_local_input() -> bool:
	# F6 runs with OfflineMultiplayerPeer. Limit it to one paddle so all six
	# do not move at once just because offline nodes share peer ID 1.
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return name == offline_test_paddle_name

	# In an ENet game, only the computer assigned this paddle reads input.
	return is_multiplayer_authority()


@rpc("authority", "call_local", "reliable")
func assign_network_owner(peer_id: int) -> void:
	# Recursive so the paddle's MultiplayerSynchronizer uses the same owner.
	set_multiplayer_authority(peer_id, true)
	if peer_id == multiplayer.get_unique_id():
		var camera := _get_face_camera()
		if camera != null:
			camera.make_current()


func _get_face_camera() -> Camera3D:
	# Do not depend on a specific name; each face camera may still be named
	# "Camera3D" in the scene tree.
	var anchor := get_parent() as Node3D
	if anchor == null:
		return null
	for child in anchor.get_children():
		if child is Camera3D:
			return child as Camera3D
	return null
