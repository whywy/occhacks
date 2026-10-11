extends CharacterBody3D

@export var speed: float = 6.0
@export var side_limit: float = 4.0


func _physics_process(delta: float) -> void:
	# Only the computer assigned to this paddle can move it.
	if not is_multiplayer_authority():
		return

	var anchor := get_parent() as Node3D
	var camera := anchor.get_node_or_null("PlayerCamera") as Camera3D

	if camera == null:
		push_warning("No PlayerCamera sibling found for " + name)
		return

	var input_x := Input.get_axis("paddle_left", "paddle_right")
	var input_y := Input.get_axis("paddle_down", "paddle_up")
	var input_direction := Vector2(input_x, input_y).limit_length(1.0)

	var camera_right := anchor.global_basis.inverse() * camera.global_basis.x
	var camera_up := anchor.global_basis.inverse() * camera.global_basis.y

	var face_direction := Vector2(
		camera_right.x * input_direction.x + camera_up.x * input_direction.y,
		camera_right.y * input_direction.x + camera_up.y * input_direction.y
	).limit_length(1.0)

	position.x = clampf(
		position.x + face_direction.x * speed * delta,
		-side_limit,
		side_limit
	)
	position.y = clampf(
		position.y + face_direction.y * speed * delta,
		-side_limit,
		side_limit
	)
	position.z = 0.0


@rpc("authority", "call_local", "reliable")
func assign_network_owner(peer_id: int) -> void:
	set_multiplayer_authority(peer_id, true)

	var anchor := get_parent() as Node3D
	var camera := anchor.get_node_or_null("PlayerCamera") as Camera3D

	if camera != null and peer_id == multiplayer.get_unique_id():
		camera.make_current()
