extends CharacterBody3D
## The host simulates the ball. Its MultiplayerSynchronizer sends position and
## velocity to clients. Offline F6 uses the same simulation locally.

signal bounced

@export var start_speed: float = 8.0
@export var speed_increase_per_round: float = 1.0
@export var max_speed: float = 20.0
@export var lock_z: bool = false
@export var plane_z: float = 0.0
@export var countdown_seconds: int = 3

@onready var countdown_label: Label = $CanvasLayer/CountdownLabel

var launched: bool = false

@onready var sparks: GPUParticles3D = get_node_or_null("Sparks") as GPUParticles3D

var speed: float = 0.0
var is_running := false
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("ball")
	rng.randomize()
	if lock_z:
		global_position.z = plane_z
	speed = maxf(start_speed, 0.1)
	velocity = Vector3.ZERO

	await get_tree().create_timer(0.6).timeout
	countdown_label.text = ""

func serve() -> void:
	if not _simulates_ball():
		return
	global_position = Vector3(0.0, 0.0, 0.0)
	if lock_z:
		global_position.z = plane_z
	var direction: Vector3
	if lock_z:
		var angle := rng.randf_range(0.0, TAU)
		direction = Vector3(cos(angle), sin(angle), 0.0)
	else:
		var y_component := rng.randf_range(-0.7, 0.7)
		var angle := rng.randf_range(0.0, TAU)
		var horizontal := sqrt(1.0 - y_component * y_component)
		direction = Vector3(cos(angle) * horizontal, y_component, sin(angle) * horizontal)
	velocity = direction.normalized() * speed
	is_running = true


func stop_ball() -> void:
	if _simulates_ball():
		is_running = false
		velocity = Vector3.ZERO


func reset_to_center() -> void:
	if not _simulates_ball():
		return
	is_running = false
	velocity = Vector3.ZERO
	global_position = Vector3.ZERO
	if lock_z:
		global_position.z = plane_z


func increase_speed_for_round() -> void:
	if not _simulates_ball():
		return
	speed = minf(speed + speed_increase_per_round, max_speed)
	if not velocity.is_zero_approx():
		velocity = velocity.normalized() * speed


func _physics_process(delta: float) -> void:
	if not _simulates_ball() or not is_running:
		return
	var collision := move_and_collide(velocity * delta)
	if collision:
		var normal := collision.get_normal()
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
