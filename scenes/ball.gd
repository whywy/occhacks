extends CharacterBody3D

@export var speed: float = 5.0

func _ready() -> void:
	# Start by moving along the Z axis.
	velocity = Vector3(0.0, 0.0, speed)

func _physics_process(_delta: float) -> void:
	var collision := move_and_collide(velocity * _delta)

	if collision:
		# Bounce away from the surface we hit.
		velocity = velocity.bounce(collision.get_normal())
