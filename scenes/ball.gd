extends CharacterBody3D
## The host simulates the ball. Its MultiplayerSynchronizer sends position and
## velocity to clients. Offline F6 uses the same simulation locally.

signal bounced

@export var start_speed: float = 8.0
@export var speed_increase_per_round: float = 1.0
@export var max_speed: float = 20.0
@export_range(0.0, 0.15, 0.005) var size_increase_per_round: float = 0.035
@export_range(1.0, 2.0, 0.05) var max_size_multiplier: float = 1.5
@export var lock_z: bool = false
@export var plane_z: float = 0.0
@export var countdown_seconds: int = 3

@onready var countdown_label: Label = $CanvasLayer/CountdownLabel

var launched: bool = false
var _ready_overlay: ColorRect

@onready var sparks: GPUParticles3D = get_node_or_null("Sparks") as GPUParticles3D

var speed: float = 0.0
var is_running := false
var rng := RandomNumberGenerator.new()
var last_paddle_hit_name: StringName = &""
var size_multiplier := 1.0
var duel_serve_axis := Vector3.ZERO


func _ready() -> void:
	add_to_group("ball")
	rng.randomize()
	if lock_z:
		global_position.z = plane_z
	speed = maxf(start_speed, 0.1)
	velocity = Vector3.ZERO
	countdown_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	countdown_label.offset_left = -140.0
	countdown_label.offset_top = -90.0
	countdown_label.offset_right = 140.0
	countdown_label.offset_bottom = 90.0
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.35))
	countdown_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	countdown_label.add_theme_constant_override("shadow_offset_x", 4)
	countdown_label.add_theme_constant_override("shadow_offset_y", 4)
	countdown_label.hide()
	_ready_overlay = ColorRect.new()
	_ready_overlay.name = "ReadyOverlay"
	_ready_overlay.color = Color(0.008, 0.014, 0.035, 0.0)
	_ready_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ready_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$CanvasLayer.add_child(_ready_overlay)
	$CanvasLayer.move_child(_ready_overlay, 0)


func prepare_serve() -> void:
	if not _simulates_ball():
		return
	stop_ball()
	reset_to_center()
	_ready_overlay.color.a = 0.72
	_ready_overlay.show()
	countdown_label.text = "READY"
	countdown_label.modulate.a = 0.0
	countdown_label.show()
	var ready_tween := create_tween()
	ready_tween.set_parallel(true)
	ready_tween.tween_property(countdown_label, "modulate:a", 1.0, 0.35)
	ready_tween.tween_property(_ready_overlay, "color:a", 0.48, 0.35)
	await ready_tween.finished
	if not _match_is_active():
		countdown_label.hide()
		_ready_overlay.hide()
		return
	await get_tree().create_timer(0.45).timeout
	var transition_tween := create_tween()
	transition_tween.set_parallel(true)
	transition_tween.tween_property(countdown_label, "modulate:a", 0.0, 0.85)
	transition_tween.tween_property(_ready_overlay, "color:a", 0.0, 0.85)
	await transition_tween.finished
	_ready_overlay.hide()
	countdown_label.modulate.a = 1.0
	for seconds_left in range(countdown_seconds, 0, -1):
		if not _match_is_active():
			countdown_label.hide()
			_ready_overlay.hide()
			return
		countdown_label.text = str(seconds_left)
		await get_tree().create_timer(1.0).timeout
	if not _match_is_active():
		countdown_label.hide()
		_ready_overlay.hide()
		return
	countdown_label.text = "GO!"
	await get_tree().create_timer(0.3).timeout
	countdown_label.hide()
	if _match_is_active():
		serve()


func _match_is_active() -> bool:
	var manager := get_node_or_null("../GameManager")
	return manager != null and bool(manager.get("match_active"))


func serve() -> void:
	if not _simulates_ball():
		return
	global_position = Vector3(0.0, 0.0, 0.0)
	if lock_z:
		global_position.z = plane_z
	var direction: Vector3
	if not duel_serve_axis.is_zero_approx():
		# Duel serves travel directly toward one of the two opposite paddles.
		# Randomize the first receiver each time a duel round is served.
		var serve_sign := 1.0 if rng.randi_range(0, 1) == 0 else -1.0
		direction = duel_serve_axis * serve_sign
	elif lock_z:
		var angle := rng.randf_range(0.0, TAU)
		direction = Vector3(cos(angle), sin(angle), 0.0)
	else:
		var y_component := rng.randf_range(-0.7, 0.7)
		var angle := rng.randf_range(0.0, TAU)
		var horizontal := sqrt(1.0 - y_component * y_component)
		direction = Vector3(cos(angle) * horizontal, y_component, sin(angle) * horizontal)
	velocity = direction.normalized() * speed
	last_paddle_hit_name = &""
	is_running = true




func set_duel_serve_axis(axis: Vector3) -> void:
	duel_serve_axis = axis.normalized() if not axis.is_zero_approx() else Vector3.ZERO


func stop_ball() -> void:
	if _simulates_ball():
		is_running = false
		velocity = Vector3.ZERO


func reset_to_center() -> void:
	if not _simulates_ball():
		return
	is_running = false
	velocity = Vector3.ZERO
	last_paddle_hit_name = &""
	global_position = Vector3.ZERO
	if lock_z:
		global_position.z = plane_z


func increase_speed_for_round() -> void:
	if not _simulates_ball():
		return
	speed = minf(speed + speed_increase_per_round, max_speed)
	if not velocity.is_zero_approx():
		velocity = velocity.normalized() * speed


func increase_size_for_round() -> void:
	if not _simulates_ball():
		return
	size_multiplier = minf(size_multiplier + size_increase_per_round, max_size_multiplier)
	_apply_size_multiplier()


func reset_size() -> void:
	if not _simulates_ball():
		return
	size_multiplier = 1.0
	_apply_size_multiplier()


func _apply_size_multiplier() -> void:
	scale = Vector3.ONE * size_multiplier


func _physics_process(delta: float) -> void:
	if not _simulates_ball() or not is_running:
		return
	var collision := move_and_collide(velocity * delta)
	if collision:
		var normal := collision.get_normal()
		var collider := collision.get_collider()
		if collider is Node and collider.is_in_group("paddles"):
			last_paddle_hit_name = StringName(collider.name)
			speed = clampf(speed * collider.get_hit_force_multiplier(), start_speed * 0.7, max_speed)
		velocity = velocity.bounce(normal).normalized() * speed
		bounced.emit()
		_emit_sparks(collision.get_position(), normal)
	if lock_z:
		velocity.z = 0.0
		global_position.z = plane_z


func _simulates_ball() -> bool:
	return multiplayer.multiplayer_peer is OfflineMultiplayerPeer or multiplayer.is_server()


func _emit_sparks(hit_position: Vector3, normal: Vector3) -> void:
	if sparks == null:
		return
	var burst := sparks.duplicate() as GPUParticles3D
	get_tree().current_scene.add_child(burst)
	burst.global_position = hit_position
	burst.global_basis = Basis(Quaternion(Vector3.UP, normal))
	burst.restart()
	get_tree().create_timer(burst.lifetime + 0.5).timeout.connect(burst.queue_free)
