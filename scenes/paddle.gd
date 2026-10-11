extends CharacterBody3D

@export var speed: float = 6.0
@export var side_limit: float = 4.0

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	var input_x := Input.get_axis("paddle_left", "paddle_right")
	var input_y := Input.get_axis("paddle_down", "paddle_up")
	var move_input := Vector2(input_x, input_y).limit_length(1.0)

	# The paddle is a child of its rotated face anchor.
	position.x += move_input.x * speed * delta
	position.y += move_input.y * speed * delta

	position.x = clampf(position.x, -side_limit, side_limit)
	position.y = clampf(position.y, -side_limit, side_limit)
	position.z = 0.0


@rpc("authority", "call_local", "reliable")
func assign_network_owner(peer_id: int) -> void:
	set_multiplayer_authority(peer_id, true)
