extends CharacterBody3D
## Bouncing ball for a 3D arena, with a separate spark burst on every hit.
## Requires a GPUParticles3D child named "Sparks" (it acts as a template).

@export var start_speed: float = 8.0
@export var speed_gain_per_hit: float = 0.2  # set to 0 for constant speed
@export var max_speed: float = 20.0
@export var lock_z: bool = false  # true = flat XY plane, false = free in 3D
@export var plane_z: float = 0.0

@onready var sparks: GPUParticles3D = $Sparks

var speed: float


func _ready() -> void:
	if lock_z:
		global_position.z = plane_z
	speed = start_speed
	launch()


func launch() -> void:
	# Random direction, kept away from straight up/down so it travels sideways
	var angle := randf_range(-PI / 4.0, PI / 4.0)
	var side := 1.0 if randf() > 0.5 else -1.0
	var z_angle := 0.0 if lock_z else randf_range(-0.5, 0.5)
	var direction := Vector3(cos(angle) * side, sin(angle), z_angle)
	velocity = direction.normalized() * speed


func _physics_process(delta: float) -> void:
	var collision := move_and_collide(velocity * delta)

	if collision:
		var normal := collision.get_normal()
		velocity = velocity.bounce(normal)

		#speed = min(speed + speed_gain_per_hit, max_speed)
		_emit_sparks(collision.get_position(), normal)

	if lock_z:
		velocity.z = 0.0
		global_position.z = plane_z

	# Keep the speed constant after bounces
	#velocity = velocity.normalized() * speed


func _emit_sparks(hit_position: Vector3, normal: Vector3) -> void:
	print("sparks fired at ", hit_position)  # delete once sparks work

	var burst := sparks.duplicate() as GPUParticles3D
	get_tree().current_scene.add_child(burst)
	burst.global_position = hit_position
	# Point the sparks' "up" direction away from the surface
	burst.global_basis = Basis(Quaternion(Vector3.UP, normal))
	burst.restart()
	# Delete the copy once its sparks have finished
	get_tree().create_timer(burst.lifetime + 0.5).timeout.connect(burst.queue_free)
