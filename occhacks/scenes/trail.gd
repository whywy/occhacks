extends MeshInstance3D
## Ribbon trail that follows its parent (the Ball).
## Attach to a MeshInstance3D child of the Ball. Leave its Mesh empty.

@export var max_points: int = 30  # more points = longer trail
@export var width: float = 0.3
@export var color: Color = Color(1.0, 0.7, 0.1)

var points: Array[Vector3] = []
var imesh := ImmediateMesh.new()
var target: Node3D


func _ready() -> void:
	top_level = true  # don't move or rotate with the ball
	global_transform = Transform3D.IDENTITY
	target = get_parent() as Node3D
	mesh = imesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat


func _physics_process(_delta: float) -> void:
	points.push_front(target.global_position)
	if points.size() > max_points:
		points.pop_back()
	_rebuild()


func _rebuild() -> void:
	imesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if points.size() < 2 or cam == null:
		return

	imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in points.size():
		var t := float(i) / float(points.size() - 1)  # 0 at the ball, 1 at the tail

		var direction: Vector3
		if i < points.size() - 1:
			direction = points[i] - points[i + 1]
		else:
			direction = points[i - 1] - points[i]

		# Widen the ribbon sideways, facing the camera, and taper toward the tail
		var to_camera := cam.global_position - points[i]
		var side := direction.cross(to_camera).normalized() * width * 0.5 * (1.0 - t)

		var c := color
		c.a = 1.0 - t  # fade out toward the tail

		imesh.surface_set_color(c)
		imesh.surface_add_vertex(points[i] + side)
		imesh.surface_set_color(c)
		imesh.surface_add_vertex(points[i] - side)
	imesh.surface_end()
