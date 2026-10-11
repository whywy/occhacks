extends CharacterBody3D

@export var speed: float = 6.0
@export var side_limit: float = 4.0
@export var offline_test_paddle_name: StringName = &"Paddle_PosZ"
@export_range(0.0, 1.0, 0.05) var bot_accuracy: float = 0.78
@export_range(0.0, 1.0, 0.01) var bot_miss_chance: float = 0.08
@export var bot_reaction_time: float = 0.22
@export var camera_smoothing: float = 7.0
@export_range(0.0, 0.5, 0.01) var camera_follow_amount: float = 0.18
@export var camera_follow_limit: float = 1.4
@export_range(1.0, 2.0, 0.05) var boost_speed_multiplier: float = 1.4
@export var boost_fuel_max: float = 2.5
@export var boost_drain_per_second: float = 1.0
@export var boost_recharge_per_second: float = 0.65
@export_range(0.0005, 0.02, 0.0005) var mouse_tilt_sensitivity: float = 0.012
@export_range(5.0, 35.0, 1.0) var max_paddle_tilt_degrees: float = 20.0
@export_range(0.5, 10.0, 0.5) var tilt_return_speed: float = 1.5

var bot_enabled := true
var match_active := false
var eliminated := false
var _rng := RandomNumberGenerator.new()
var _bot_timer := 0.0
var _bot_target := Vector2.ZERO
var _bot_speed_multiplier := 0.9
var _bot_approach_active := false
var _bot_current_approach_misses := false
var _bot_mistake_offset := Vector2.ZERO
var _camera_base_position := Vector3.ZERO
var _is_human_paddle := false
var _boost_fuel := 2.5
var _base_rotation := Vector3.ZERO
var _paddle_tilt := Vector2.ZERO
var _pending_mouse_motion := Vector2.ZERO
var _face_material: StandardMaterial3D
var _face_color := Color.WHITE
var _on_fire := false
var _fire_time := 0.0
var _fire_light: OmniLight3D
var _boost_layer: CanvasLayer
var _boost_bar: ProgressBar

const FACE_COLORS := {
	"PosZ": Color(0.91, 0.08, 0.12), # red
	"NegZ": Color(1.0, 0.32, 0.035), # orange
	"PosX": Color(0.035, 0.29, 0.96), # blue
	"NegX": Color(0.035, 0.72, 0.22), # green
	"PosY": Color(0.94, 0.95, 1.0), # white
	"NegY": Color(1.0, 0.82, 0.025), # yellow
}


func _ready() -> void:
	_boost_fuel = boost_fuel_max
	_apply_face_color()
	_rng.randomize()
	_base_rotation = rotation
	var camera := _get_face_camera()
	if camera != null:
		_camera_base_position = camera.position
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer and name == offline_test_paddle_name:
		bot_enabled = false
		if camera != null:
			camera.make_current()


func _apply_face_color() -> void:
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null:
		return
	var face_key := String(name).trim_prefix("Paddle_")
	var face_color: Color = FACE_COLORS.get(face_key, Color.WHITE)
	_face_color = face_color
	_face_material = StandardMaterial3D.new()
	_face_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_face_material.albedo_color = face_color
	_face_material.emission_enabled = true
	_face_material.emission = face_color
	_face_material.emission_energy_multiplier = 0.12
	mesh.material_override = _face_material
	_apply_paddle_transparency()


func set_player_visual(is_player: bool) -> void:
	_is_human_paddle = is_player
	_apply_paddle_transparency()
	if _boost_layer != null:
		_boost_layer.visible = is_player and match_active and _is_local_human()


func _apply_paddle_transparency() -> void:
	if _face_material == null:
		return
	var color := _face_material.albedo_color
	color.a = 0.78 if _is_human_paddle else 1.0
	_face_material.albedo_color = color
	_face_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if _is_human_paddle else BaseMaterial3D.TRANSPARENCY_DISABLED


func _build_boost_meter() -> void:
	if _boost_layer != null:
		return
	_boost_layer = CanvasLayer.new()
	_boost_layer.name = "PaddleBoostHUD"
	_boost_layer.layer = 3
	add_child(_boost_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boost_layer.add_child(root)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -126.0
	panel.offset_right = 126.0
	panel.offset_top = -78.0
	panel.offset_bottom = -18.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.015, 0.025, 0.06, 0.86)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	root.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	panel.add_child(stack)
	var label := Label.new()
	label.text = "PADDLE BOOST  ·  SHIFT"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	stack.add_child(label)
	_boost_bar = ProgressBar.new()
	_boost_bar.min_value = 0.0
	_boost_bar.max_value = boost_fuel_max
	_boost_bar.value = _boost_fuel
	_boost_bar.show_percentage = false
	_boost_bar.custom_minimum_size = Vector2(218, 16)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.13, 0.16, 0.22, 1.0)
	bar_bg.set_corner_radius_all(5)
	_boost_bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = _face_material.albedo_color
	bar_fill.set_corner_radius_all(5)
	_boost_bar.add_theme_stylebox_override("fill", bar_fill)
	stack.add_child(_boost_bar)


func _process(delta: float) -> void:
	_update_fire_glow(delta)
	if not match_active or not _is_local_human():
		return
	_update_ball_camera(delta)


func set_on_fire(value: bool) -> void:
	_on_fire = value
	if value:
		_ensure_fire_light()
		if _fire_light != null:
			_fire_light.show()
	else:
		if _face_material != null:
			_face_material.emission_energy_multiplier = 0.12
		if _fire_light != null:
			_fire_light.hide()


func _ensure_fire_light() -> void:
	if _fire_light != null:
		return
	_fire_light = OmniLight3D.new()
	_fire_light.name = "OnFireGlow"
	_fire_light.light_color = _face_color
	_fire_light.light_energy = 0.7
	_fire_light.omni_range = 3.2
	_fire_light.shadow_enabled = false
	add_child(_fire_light)


func _update_fire_glow(delta: float) -> void:
	if not _on_fire:
		return
	_fire_time += delta
	var pulse := 0.5 + 0.5 * sin(_fire_time * 7.0)
	if _face_material != null:
		_face_material.emission_energy_multiplier = lerpf(0.9, 2.1, pulse)
	if _fire_light != null:
		_fire_light.light_energy = lerpf(0.45, 1.1, pulse)


func _update_ball_camera(delta: float) -> void:
	var camera := _get_face_camera()
	var anchor := get_parent() as Node3D
	var ball := get_tree().get_first_node_in_group("ball") as Node3D
	if camera == null or anchor == null or ball == null:
		return
	var local_ball := anchor.to_local(ball.global_position)
	var follow_offset := Vector3(
		clampf(local_ball.x * camera_follow_amount, -camera_follow_limit, camera_follow_limit),
		clampf(local_ball.y * camera_follow_amount, -camera_follow_limit, camera_follow_limit),
		0.0
	)
	var blend := 1.0 - exp(-camera_smoothing * delta)
	camera.position = camera.position.lerp(_camera_base_position + follow_offset, blend)
	var face_up := anchor.global_basis.y.normalized()
	var desired_transform := camera.global_transform.looking_at(ball.global_position, face_up)
	var current_rotation := camera.global_basis.get_rotation_quaternion()
	var target_rotation := desired_transform.basis.get_rotation_quaternion()
	camera.global_basis = Basis(current_rotation.slerp(target_rotation, blend))


func _physics_process(delta: float) -> void:
	if not match_active or eliminated:
		return
	if _is_local_human():
		_update_paddle_tilt(delta)
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


func add_mouse_tilt_motion(mouse_delta: Vector2) -> void:
	# The Arena routes mouse motion only to the selected human paddle, avoiding
	# competing input callbacks across the six sibling paddle instances.
	if match_active and _is_local_human():
		_pending_mouse_motion += mouse_delta


func _unhandled_input(event: InputEvent) -> void:
	if not match_active or not _is_local_human():
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _update_paddle_tilt(delta: float) -> void:
	var max_tilt := deg_to_rad(max_paddle_tilt_degrees)
	_paddle_tilt.x = clampf(_paddle_tilt.x + _pending_mouse_motion.y * mouse_tilt_sensitivity, -max_tilt, max_tilt)
	_paddle_tilt.y = clampf(_paddle_tilt.y + _pending_mouse_motion.x * mouse_tilt_sensitivity, -max_tilt, max_tilt)
	_pending_mouse_motion = Vector2.ZERO
	var blend := 1.0 - exp(-tilt_return_speed * delta)
	_paddle_tilt = _paddle_tilt.lerp(Vector2.ZERO, blend)
	rotation = _base_rotation + Vector3(_paddle_tilt.x, _paddle_tilt.y, 0.0)


func _move_from_keyboard(delta: float) -> void:
	var x := Input.get_axis("paddle_left", "paddle_right")
	var y := Input.get_axis("paddle_down", "paddle_up")
	var input_vector := Vector2(x, y).limit_length(1.0)
	var movement_speed := _get_boosted_speed(delta, input_vector.length_squared() > 0.0)
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
	position.x = clampf(position.x + face_direction.x * movement_speed * delta, -side_limit, side_limit)
	position.y = clampf(position.y + face_direction.y * movement_speed * delta, -side_limit, side_limit)
	position.z = 0.0


func _get_boosted_speed(delta: float, is_moving: bool) -> float:
	var boosting := _is_human_paddle and is_moving and _boost_fuel > 0.0 and Input.is_action_pressed("paddle_boost")
	if boosting:
		_boost_fuel = maxf(0.0, _boost_fuel - boost_drain_per_second * delta)
	else:
		_boost_fuel = minf(boost_fuel_max, _boost_fuel + boost_recharge_per_second * delta)
	if _boost_bar != null:
		_boost_bar.value = _boost_fuel
	return speed * boost_speed_multiplier if boosting else speed


func _run_bot(delta: float) -> void:
	if not multiplayer.is_server() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	var ball := get_tree().get_first_node_in_group("ball") as CharacterBody3D
	var anchor := get_parent() as Node3D
	if ball == null or anchor == null:
		return
	_bot_timer += delta
	if _bot_timer >= bot_reaction_time:
		_bot_timer = 0.0
		var local_ball := anchor.to_local(ball.global_position)
		var local_velocity: Vector3 = anchor.global_basis.inverse() * ball.velocity
		var predicted := Vector2(local_ball.x, local_ball.y)
		var intercept_time := -1.0
		# Aim where the ball should reach this paddle's plane.
		if absf(local_velocity.z) > 0.1:
			intercept_time = -local_ball.z / local_velocity.z
			if intercept_time > 0.0:
				predicted += Vector2(local_velocity.x, local_velocity.y) * minf(intercept_time, 1.5)
				if not _bot_approach_active:
					_bot_approach_active = true
					_bot_current_approach_misses = _rng.randf() < bot_miss_chance
					if _bot_current_approach_misses:
						# Make one believable bad read for this approach, then keep it
						# consistent instead of rolling again every reaction tick.
						var miss_axis := Vector2.RIGHT if _rng.randf() < 0.5 else Vector2.UP
						_bot_mistake_offset = miss_axis * _rng.randf_range(1.35, 2.25) * (-1.0 if _rng.randf() < 0.5 else 1.0)
				if _bot_current_approach_misses:
					predicted += _bot_mistake_offset
			else:
				_bot_approach_active = false
				_bot_current_approach_misses = false
		else:
			_bot_approach_active = false
			_bot_current_approach_misses = false
		var miss_margin := (1.0 - bot_accuracy) * 3.5
		_bot_target = Vector2(
			predicted.x + _rng.randf_range(-miss_margin, miss_margin),
			predicted.y + _rng.randf_range(-miss_margin, miss_margin)
		).clamp(Vector2(-side_limit, -side_limit), Vector2(side_limit, side_limit))
	var difference := _bot_target - Vector2(position.x, position.y)
	var bot_speed := speed * _bot_speed_multiplier
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
		_paddle_tilt = Vector2.ZERO
		_pending_mouse_motion = Vector2.ZERO
		rotation = _base_rotation
	if active and _is_human_paddle and _is_local_human():
		# Create the boost HUD only when gameplay is active. The player can be
		# selected from the menu earlier, but that must not show gameplay UI.
		_build_boost_meter()
		_boost_layer.show()
		_boost_fuel = boost_fuel_max
		if _boost_bar != null:
			_boost_bar.max_value = boost_fuel_max
			_boost_bar.value = _boost_fuel
	else:
		if _boost_layer != null:
			_boost_layer.hide()
	if not active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif _is_local_human():
		var camera := _get_face_camera()
		if camera != null:
			camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_bot_mode(enabled: bool) -> void:
	bot_enabled = enabled


func set_bot_difficulty(level: int) -> void:
	match level:
		0: # Relaxed
			bot_accuracy = 0.42
			bot_miss_chance = 0.20
			bot_reaction_time = 0.48
			_bot_speed_multiplier = 0.72
		1: # Classic
			bot_accuracy = 0.70
			bot_miss_chance = 0.10
			bot_reaction_time = 0.24
			_bot_speed_multiplier = 0.88
		_: # Fierce
			bot_accuracy = 0.91
			bot_miss_chance = 0.04
			bot_reaction_time = 0.10
			_bot_speed_multiplier = 1.0


func get_hit_force_multiplier() -> float:
	var manager := get_node_or_null("../../GameManager")
	if manager == null:
		return 1.0
	var current_lives := int(manager.call("get_face_lives", String(name)))
	var maximum_lives := int(manager.get("starting_lives"))
	if current_lives <= 0 or maximum_lives <= 1:
		return 1.0
	var life_fraction := clampf(float(current_lives - 1) / float(maximum_lives - 1), 0.0, 1.0)
	# A full-life face returns the ball 4% softer; a face on its last life hits it 4% harder.
	return lerpf(1.04, 0.96, life_fraction)


func set_eliminated(value: bool) -> void:
	var was_eliminated := eliminated
	eliminated = value
	if value:
		visible = false
	else:
		visible = true
		if was_eliminated:
			position = Vector3.ZERO
			rotation = _base_rotation
			scale = Vector3.ONE
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		shape.set_deferred("disabled", value)


func play_elimination_suction(world_impact_position: Vector3) -> void:
	if eliminated:
		return
	eliminated = true
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		shape.set_deferred("disabled", true)
	if _boost_layer != null:
		_boost_layer.hide()
	var anchor := get_parent() as Node3D
	if anchor == null:
		visible = false
		return
	var impact_local := anchor.to_local(world_impact_position)
	var sink_direction := (anchor.global_basis.inverse() * anchor.global_position.normalized()).normalized()
	var target_position := Vector3(impact_local.x, impact_local.y, position.z)
	var target_rotation := rotation + Vector3(0.0, 0.0, TAU * 1.5)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position", target_position, 0.72)
	tween.tween_property(self, "rotation", target_rotation, 0.72)
	tween.tween_property(self, "scale", Vector3(0.08, 0.08, 0.08), 0.72)
	tween.chain().tween_property(self, "position", target_position + sink_direction * 0.32, 0.18)
	tween.tween_callback(func() -> void:
		visible = false
		position = target_position
		scale = Vector3.ONE
	)


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
