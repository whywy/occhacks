extends CharacterBody3D
## The server simulates the ball; MultiplayerSynchronizer replicates its position
## and velocity to every client. Offline/F6 play uses the same movement locally.

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
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	if lock_z:
		global_position.z = plane_z
	speed = start_speed
	start_round()

func start_round() -> void:
	launched = false
	velocity = Vector3.ZERO

	for i in range(countdown_seconds, 0, -1):
		countdown_label.text = str(i)
		await get_tree().create_timer(1.0).timeout

	countdown_label.text = "GO!"
	launch()
	launched = true

	await get_tree().create_timer(0.6).timeout
	countdown_label.text = ""

func launch() -> void:
	if not _simulates_ball():
		return

	var direction: Vector3
	if lock_z:
		var angle := rng.randf_range(0.0, TAU)
		direction = Vector3(cos(angle), sin(angle), 0.0)
	else:
		# Keep the ball from serving almost straight along the Y axis.
		var y_component := rng.randf_range(-0.7, 0.7)
		var angle := rng.randf_range(0.0, TAU)
		var horizontal := sqrt(1.0 - y_component * y_component)
		direction = Vector3(cos(angle) * horizontal, y_component, sin(angle) * horizontal)

	velocity = direction.normalized() * speed


func increase_speed_for_round() -> void:
	if not _simulates_ball() or velocity.is_zero_approx():
		return
	speed = minf(speed + speed_increase_per_round, max_speed)
	velocity = velocity.normalized() * speed


func _physics_process(delta: float) -> void:
	if not launched:
		return
	if not _simulates_ball():
		return
	if velocity.is_zero_approx():
		launch()
		if velocity.is_zero_approx():
			return

	var collision := move_and_collide(velocity * delta)
	if collision:
		var normal := collision.get_normal()
		velocity = velocity.bounce(normal).normalized() * speed
		_emit_sparks(collision.get_position(), normal)

	if lock_z:
		velocity.z = 0.0
		global_position.z = plane_z


func _simulates_ball() -> bool:
	# F6 uses OfflineMultiplayerPeer; network games simulate on the host only.
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
