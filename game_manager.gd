extends Node

signal match_started
signal match_finished

const FACE_ORDER := [
	"Paddle_PosZ", "Paddle_NegZ", "Paddle_PosX",
	"Paddle_NegX", "Paddle_PosY", "Paddle_NegY",
]
const FACE_COLORS := {
	"Paddle_PosZ": Color(0.91, 0.08, 0.12), # red
	"Paddle_NegZ": Color(1.0, 0.32, 0.035), # orange
	"Paddle_PosX": Color(0.035, 0.29, 0.96), # blue
	"Paddle_NegX": Color(0.035, 0.72, 0.22), # green
	"Paddle_PosY": Color(0.94, 0.95, 1.0), # white
	"Paddle_NegY": Color(1.0, 0.82, 0.025), # yellow
}
const OPPOSITE_FACES := {
	"Paddle_PosZ": "Paddle_NegZ",
	"Paddle_NegZ": "Paddle_PosZ",
	"Paddle_PosX": "Paddle_NegX",
	"Paddle_NegX": "Paddle_PosX",
	"Paddle_PosY": "Paddle_NegY",
	"Paddle_NegY": "Paddle_PosY",
}
const WALL_SURFACE_SHADER = preload("res://scenes/wall_surface.gdshader")

@export var time_limit_seconds: float = 180.0
@export var starting_lives: int = 1
@export_range(1, 10, 1) var fire_streak_threshold: int = 3

var match_active := false
var solo_player_face: StringName = &"Paddle_PosZ"
var last_result := ""
var round_number := 1
var time_remaining := 180.0
var lives: Dictionary = {}
var _face_scoring_streaks: Dictionary = {}
var _paddles: Dictionary = {}
var _wall_materials: Array[ShaderMaterial] = []
var _score_lock := false
var _hud_layer: CanvasLayer
var _timer_label: Label
var _timer_label_settings: LabelSettings
var _face_score_labels: Dictionary = {}
var _face_score_circles: Dictionary = {}
var _score_column: VBoxContainer
var _last_displayed_second := -1
var _timer_glow_tween: Tween
var _sound_players: Array[AudioStreamPlayer] = []
var _sound_index := 0
var _publish_timer := 0.0
var _defeat_transition_active := false
var _defeat_started_usec := 0
var _defeat_duration_seconds := 3.2
var _defeat_overlay: ColorRect
var _defeat_title: Label
var _defeat_button: Button
var _duel_started := false
var _duel_layer: CanvasLayer
var _duel_backdrop: ColorRect
var _duel_title: Label
var _duel_left_face: Label
var _duel_right_face: Label


func _ready() -> void:
	time_remaining = time_limit_seconds
	var ball := get_node_or_null("../Ball")
	if ball != null and ball.has_signal("bounced"):
		ball.bounced.connect(_on_ball_bounced)
	for paddle in get_tree().get_nodes_in_group("paddles"):
		_paddles[paddle.name] = paddle
		lives[paddle.name] = starting_lives
		_face_scoring_streaks[paddle.name] = 0
		_create_score_area(paddle)
	_build_wall_surfaces()
	_build_hud()
	_build_duel_screen()
	_build_defeat_screen()
	_build_sounds()
	_publish_state("")


func _process(delta: float) -> void:
	_update_wall_proximity()
	if _defeat_transition_active:
		_update_defeat_transition()
		return
	if not match_active or not _is_authoritative():
		return
	time_remaining = maxf(0.0, time_remaining - delta)
	_publish_timer += delta
	if _publish_timer >= 0.35:
		_publish_timer = 0.0
		_publish_state("")
	if time_remaining <= 0.0:
		_end_by_lives()


func _build_wall_surfaces() -> void:
	for face_name in FACE_ORDER:
		var face_suffix: String = face_name.trim_prefix("Paddle_")
		var wall := get_node_or_null("../Wall_" + face_suffix) as MeshInstance3D
		if wall == null:
			continue
		var material := ShaderMaterial.new()
		material.shader = WALL_SURFACE_SHADER
		material.set_shader_parameter("side_color", FACE_COLORS[face_name])
		material.set_shader_parameter("ball_world_position", Vector3.ZERO)
		wall.material_override = material
		# The shader handles transparency so the outline can stay bright while
		# the colored face itself remains translucent.
		wall.transparency = 0.0
		_wall_materials.append(material)


func _update_wall_proximity() -> void:
	if _wall_materials.is_empty():
		return
	var ball := get_node_or_null("../Ball") as Node3D
	if ball == null:
		return
	for material in _wall_materials:
		material.set_shader_parameter("ball_world_position", ball.global_position)


func _create_score_area(paddle: Node) -> void:
	var anchor := paddle.get_parent() as Node3D
	if anchor == null:
		return
	var goal := Area3D.new()
	goal.name = "ScoringBox_" + String(paddle.name)
	goal.collision_layer = 0
	goal.collision_mask = 1
	goal.monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(9.9, 9.9, 0.25)
	shape.shape = box
	goal.add_child(shape)
	var outward := anchor.global_position.normalized()
	var local_outward := anchor.global_basis.inverse() * outward
	# Put the trigger on the wall plane, beyond the paddle, so a clean paddle
	# hit bounces first while a miss passes through this non-solid Area3D.
	goal.position = Vector3(0.0, 0.0, 0.30 if local_outward.z >= 0.0 else -0.30)
	anchor.add_child(goal)
	goal.body_entered.connect(_on_scoring_box_entered.bind(String(paddle.name)))


func _on_scoring_box_entered(body: Node3D, face_name: String) -> void:
	if not match_active or not _is_authoritative() or _score_lock:
		return
	if not body.is_in_group("ball") or int(lives.get(face_name, 0)) <= 0:
		return
	_score_lock = true
	var ball := get_node_or_null("../Ball")
	if ball != null:
		_show_crater_impact(face_name, body.global_position)
		ball.call_deferred("stop_ball")
	call_deferred("_apply_score", face_name, body.global_position)


func _apply_score(face_name: String, impact_position: Vector3 = Vector3.ZERO) -> void:
	lives[face_name] = maxi(0, int(lives[face_name]) - 1)
	var defeated_face := StringName(face_name)
	_reset_face_scoring_streak(defeated_face)
	var ball := get_node_or_null("../Ball")
	if ball != null:
		var scoring_face := StringName(ball.get("last_paddle_hit_name"))
		if scoring_face != &"" and scoring_face != defeated_face:
			_record_face_score(scoring_face)
	var is_eliminated := int(lives[face_name]) == 0
	if is_eliminated:
		_broadcast_face_eliminated(face_name, true, impact_position, true)
	round_number += 1
	if ball != null:
		ball.increase_speed_for_round()
		ball.increase_size_for_round()
	_broadcast_sound("score")
	_publish_state("%s lost a life" % face_name)
	if face_name == String(solo_player_face) and is_eliminated:
		if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
			_begin_defeat_transition("DEFEAT: The bots took your last life.")
		else:
			_finish_match("Bots win! You were eliminated.")
		return
	if _active_face_count() <= 1:
		var winner_face := _last_active_face()
		var result := "You win! Last face standing." if winner_face == String(solo_player_face) else "Bots win: %s survived." % winner_face.trim_prefix("Paddle_")
		_finish_match(result)
		return
	if _active_face_count() == 2 and not _duel_started:
		_duel_started = true
		_prepare_duel_faces()
		_publish_state("DUEL! Final two face off across the cube.")
		await _play_duel_transition()
	if match_active and ball != null:
		await ball.prepare_serve()
	_score_lock = false


func _show_crater_impact(face_name: String, world_position: Vector3) -> void:
	var paddle: Node3D = _paddles.get(face_name) as Node3D
	if paddle == null:
		return
	var anchor := paddle.get_parent() as Node3D
	if anchor == null:
		return
	var local_hit := anchor.to_local(world_position)
	var local_outward := anchor.global_basis.inverse() * anchor.global_position.normalized()
	var outward_sign := 1.0 if local_outward.z >= 0.0 else -1.0
	var impact := Node3D.new()
	impact.name = "CraterImpact"
	impact.position = Vector3(local_hit.x, local_hit.y, outward_sign * 0.31)
	anchor.add_child(impact)

	var face_colors := {
		"Paddle_PosZ": Color(0.91, 0.08, 0.12),
		"Paddle_NegZ": Color(1.0, 0.32, 0.035),
		"Paddle_PosX": Color(0.035, 0.29, 0.96),
		"Paddle_NegX": Color(0.035, 0.72, 0.22),
		"Paddle_PosY": Color(0.94, 0.95, 1.0),
		"Paddle_NegY": Color(1.0, 0.82, 0.025),
	}
	var face_color: Color = face_colors.get(face_name, Color.WHITE)

	var crater := MeshInstance3D.new()
	var crater_mesh := SphereMesh.new()
	crater_mesh.radius = 0.45
	crater_mesh.height = 0.9
	crater.mesh = crater_mesh
	crater.scale = Vector3(1.0, 1.0, 0.07)
	var crater_material := StandardMaterial3D.new()
	crater_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	crater_material.albedo_color = Color(0.025, 0.025, 0.04, 1.0)
	crater_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crater_material.albedo_color.a = 0.82
	crater.material_override = crater_material
	impact.add_child(crater)

	var ripple := MeshInstance3D.new()
	var ripple_mesh := TorusMesh.new()
	ripple_mesh.inner_radius = 0.55
	ripple_mesh.outer_radius = 0.72
	ripple.mesh = ripple_mesh
	ripple.rotation.x = PI * 0.5
	var ripple_material := StandardMaterial3D.new()
	ripple_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ripple_material.albedo_color = face_color.lightened(0.2)
	ripple_material.emission_enabled = true
	ripple_material.emission = face_color
	ripple_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ripple.material_override = ripple_material
	impact.add_child(ripple)

	impact.scale = Vector3(0.12, 0.12, 0.12)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(impact, "scale", Vector3(1.45, 1.45, 1.45), 0.48).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(crater_material, "albedo_color:a", 0.0, 0.85)
	tween.tween_property(ripple_material, "albedo_color:a", 0.0, 0.62)
	tween.chain().tween_callback(impact.queue_free)


func get_face_lives(face_name: String) -> int:
	return int(lives.get(StringName(face_name), starting_lives))


func _active_face_count() -> int:
	var count := 0
	for face_name in lives:
		if int(lives[face_name]) > 0:
			count += 1
	return count


func _last_active_face() -> String:
	for face_name in lives:
		if int(lives[face_name]) > 0:
			return String(face_name)
	return "No one"


func _prepare_duel_faces() -> void:
	# In solo mode, keep the human on their chosen face and move the last bot
	# to the directly opposite face so the final round plays like classic Pong.
	if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	var player_face := String(solo_player_face)
	var opposite_face: String = OPPOSITE_FACES.get(player_face, "")
	if opposite_face == "" or int(lives.get(player_face, 0)) <= 0:
		return
	var challenger_face := ""
	for face_name in lives:
		var candidate := String(face_name)
		if candidate != player_face and int(lives[face_name]) > 0:
			challenger_face = candidate
			break
	if challenger_face == "":
		return
	var duel_bot: Node = _paddles.get(opposite_face)
	var player_paddle: Node = _paddles.get(player_face)
	if duel_bot == null or player_paddle == null:
		return
	var ball := get_node_or_null("../Ball")
	var player_anchor := player_paddle.get_parent() as Node3D
	if ball != null and player_anchor != null:
		ball.set_duel_serve_axis(player_anchor.global_position.normalized())
	# If the final bot is already on the opposite face, keep it there; the
	# duel-only serve axis still applies.
	if challenger_face == opposite_face:
		return
	_reset_face_scoring_streak(StringName(challenger_face))
	_reset_face_scoring_streak(StringName(opposite_face))
	lives[challenger_face] = 0
	lives[opposite_face] = starting_lives
	_broadcast_face_eliminated(challenger_face, true)
	_broadcast_face_eliminated(opposite_face, false)
	duel_bot.set_bot_mode(true)
	duel_bot.set_player_visual(false)
	duel_bot.position = Vector3.ZERO
	player_paddle.position = Vector3.ZERO


func _end_by_lives() -> void:
	var winner_face := "No one"
	var best := -1
	for face_name in lives:
		if int(lives[face_name]) > best:
			best = int(lives[face_name])
			winner_face = String(face_name)
	var result := "You win! You survived the timer." if winner_face == String(solo_player_face) else "Bots win: %s had the most lives." % winner_face.trim_prefix("Paddle_")
	_finish_match(result)


func _finish_match(winner: String) -> void:
	last_result = winner
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		end_match(winner)
	else:
		rpc("end_match", winner)


func _broadcast_face_eliminated(
	face_name: String,
	value: bool,
	impact_position: Vector3 = Vector3.ZERO,
	play_suction: bool = false
) -> void:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		set_face_eliminated(face_name, value, impact_position, play_suction)
	else:
		rpc("set_face_eliminated", face_name, value, impact_position, play_suction)


func begin_local_test() -> void:
	if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	_begin_match_local()


@rpc("authority", "call_local", "reliable")
func begin_match() -> void:
	_begin_match_local()


@rpc("authority", "call_remote", "reliable")
func sync_active_match(seconds_left: float, round_value: int, lives_state: Dictionary) -> void:
	# A player joining late gets the current match state from the host.
	match_active = true
	time_remaining = seconds_left
	round_number = round_value
	lives = lives_state.duplicate(true)
	_arrange_score_circles()
	for face_name in _paddles:
		var face := String(face_name)
		set_face_eliminated(face, int(lives.get(face, 0)) <= 0)
		_paddles[face_name].set_match_active(true)
	receive_hud_state(time_remaining, round_number, lives, "Joined current match", true)
	match_started.emit()


func _begin_match_local() -> void:
	Engine.time_scale = 1.0
	_defeat_transition_active = false
	if _defeat_overlay != null:
		_defeat_overlay.hide()
	# Keep scoring and paddle input disabled while the menu preview is handed
	# back to the match. A goal event queued by the preview is ignored here.
	match_active = false
	_score_lock = false
	round_number = 1
	time_remaining = time_limit_seconds
	_duel_started = false
	_last_displayed_second = -1
	if _timer_glow_tween != null and _timer_glow_tween.is_running():
		_timer_glow_tween.kill()
	if _timer_label_settings != null:
		_timer_label_settings.shadow_color = Color(1.0, 0.015, 0.02, 0.0)
	for face_name in _paddles:
		lives[face_name] = starting_lives
		_face_scoring_streaks[face_name] = 0
		_paddles[face_name].set_on_fire(false)
		set_face_eliminated(String(face_name), false)
		_paddles[face_name].set_match_active(false)
	_arrange_score_circles()
	var ball := get_node_or_null("../Ball")
	if ball != null:
		ball.set_duel_serve_axis(Vector3.ZERO)
		ball.stop_ball()
		ball.speed = ball.start_speed
		ball.reset_size()
		ball.reset_to_center()
	# Clear any collision/goal callbacks queued by the menu cinematic before
	# allowing this match to score or move its paddles.
	await get_tree().physics_frame
	if ball != null:
		ball.stop_ball()
		ball.reset_to_center()
	match_active = true
	for paddle in _paddles.values():
		paddle.set_match_active(true)
	_publish_state("Get ready")
	_broadcast_sound("serve")
	match_started.emit()
	if ball != null:
		await ball.prepare_serve()


@rpc("authority", "call_local", "reliable")
func end_match(winner: String) -> void:
	match_active = false
	_score_lock = false
	var ball := get_node_or_null("../Ball")
	if ball != null:
		ball.stop_ball()
	for paddle in _paddles.values():
		paddle.set_match_active(false)
	_publish_state("Winner: %s" % winner)
	_broadcast_sound("game_over")
	match_finished.emit()


func _build_defeat_screen() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DefeatScreen"
	layer.layer = 10
	add_child(layer)
	_defeat_overlay = ColorRect.new()
	_defeat_overlay.name = "DefeatOverlay"
	_defeat_overlay.color = Color(0.008, 0.012, 0.025, 0.0)
	_defeat_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_defeat_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(_defeat_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_defeat_overlay.add_child(center)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 18)
	center.add_child(stack)
	_defeat_title = Label.new()
	_defeat_title.text = "DEFEAT"
	_defeat_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_defeat_title.add_theme_font_size_override("font_size", 56)
	_defeat_title.modulate.a = 0.0
	stack.add_child(_defeat_title)
	var message := Label.new()
	message.text = "Your face has been eliminated."
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size", 20)
	message.modulate.a = 0.0
	stack.add_child(message)
	_defeat_button = Button.new()
	_defeat_button.text = "Return to menu"
	_defeat_button.custom_minimum_size = Vector2(220, 48)
	_defeat_button.modulate.a = 0.0
	_defeat_button.disabled = true
	_defeat_button.pressed.connect(_dismiss_defeat_screen)
	stack.add_child(_defeat_button)
	_defeat_overlay.hide()


func _build_duel_screen() -> void:
	_duel_layer = CanvasLayer.new()
	_duel_layer.name = "DuelTransition"
	_duel_layer.layer = 8
	add_child(_duel_layer)
	_duel_backdrop = ColorRect.new()
	_duel_backdrop.name = "DuelBackdrop"
	_duel_backdrop.color = Color(0.005, 0.008, 0.02, 0.0)
	_duel_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_duel_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_duel_layer.add_child(_duel_backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_duel_backdrop.add_child(center)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(stack)
	var announcement := Label.new()
	announcement.text = "FINAL TWO"
	announcement.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announcement.add_theme_font_size_override("font_size", 20)
	announcement.add_theme_color_override("font_color", Color(0.82, 0.86, 1.0))
	stack.add_child(announcement)
	_duel_title = Label.new()
	_duel_title.text = "DUEL"
	_duel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_duel_title.add_theme_font_size_override("font_size", 96)
	_duel_title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.72))
	_duel_title.add_theme_color_override("font_shadow_color", Color(1.0, 0.12, 0.035, 0.95))
	_duel_title.add_theme_constant_override("shadow_offset_x", 2)
	_duel_title.add_theme_constant_override("shadow_offset_y", 2)
	_duel_title.add_theme_constant_override("shadow_outline_size", 14)
	stack.add_child(_duel_title)
	var face_row := HBoxContainer.new()
	face_row.alignment = BoxContainer.ALIGNMENT_CENTER
	face_row.add_theme_constant_override("separation", 22)
	stack.add_child(face_row)
	_duel_left_face = Label.new()
	_duel_left_face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_duel_left_face.add_theme_font_size_override("font_size", 26)
	face_row.add_child(_duel_left_face)
	var versus := Label.new()
	versus.text = "VS"
	versus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	versus.add_theme_font_size_override("font_size", 20)
	versus.add_theme_color_override("font_color", Color(0.72, 0.75, 0.84))
	face_row.add_child(versus)
	_duel_right_face = Label.new()
	_duel_right_face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_duel_right_face.add_theme_font_size_override("font_size", 26)
	face_row.add_child(_duel_right_face)
	var message := Label.new()
	message.text = "ONE FACE LEFT STANDING"
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size", 14)
	message.add_theme_color_override("font_color", Color(0.68, 0.72, 0.82))
	stack.add_child(message)
	_duel_layer.hide()


func _play_duel_transition() -> void:
	var remaining_faces: Array[String] = []
	for face_name in lives:
		if int(lives[face_name]) > 0:
			remaining_faces.append(String(face_name))
	if remaining_faces.size() != 2:
		return
	_duel_left_face.text = _face_short_name(remaining_faces[0])
	_duel_right_face.text = _face_short_name(remaining_faces[1])
	_duel_left_face.add_theme_color_override("font_color", FACE_COLORS.get(remaining_faces[0], Color.WHITE))
	_duel_right_face.add_theme_color_override("font_color", FACE_COLORS.get(remaining_faces[1], Color.WHITE))
	_duel_backdrop.color.a = 0.0
	_duel_title.modulate.a = 0.0
	_duel_left_face.modulate.a = 0.0
	_duel_right_face.modulate.a = 0.0
	_duel_layer.show()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_duel_backdrop, "color:a", 0.86, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_duel_title, "modulate:a", 1.0, 0.32).set_delay(0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_duel_left_face, "modulate:a", 1.0, 0.4).set_delay(0.28)
	tween.tween_property(_duel_right_face, "modulate:a", 1.0, 0.4).set_delay(0.28)
	tween.set_parallel(false)
	tween.tween_interval(1.25)
	tween.tween_property(_duel_backdrop, "color:a", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tween.finished
	_duel_layer.hide()


func _face_short_name(face_name: String) -> String:
	var short_names := {
		"Paddle_PosZ": "RED",
		"Paddle_NegZ": "ORANGE",
		"Paddle_PosX": "BLUE",
		"Paddle_NegX": "GREEN",
		"Paddle_PosY": "WHITE",
		"Paddle_NegY": "YELLOW",
	}
	return String(short_names.get(face_name, face_name.trim_prefix("Paddle_").to_upper()))


func _begin_defeat_transition(result: String) -> void:
	if _defeat_transition_active:
		return
	last_result = result
	_defeat_transition_active = true
	_defeat_started_usec = Time.get_ticks_usec()
	_defeat_overlay.color.a = 0.0
	_defeat_title.modulate.a = 0.0
	_defeat_button.modulate.a = 0.0
	_defeat_button.disabled = true
	_defeat_overlay.show()


func _update_defeat_transition() -> void:
	# Wall-clock time keeps this transition moving while Engine.time_scale slows the game.
	var elapsed := float(Time.get_ticks_usec() - _defeat_started_usec) / 1000000.0
	var progress := clampf(elapsed / _defeat_duration_seconds, 0.0, 1.0)
	Engine.time_scale = exp(log(0.12) * progress)
	_defeat_overlay.color.a = smoothstep(0.0, 1.0, progress) * 0.92
	var reveal := clampf((progress - 0.58) / 0.28, 0.0, 1.0)
	_defeat_title.modulate.a = reveal
	for child in _defeat_title.get_parent().get_children():
		if child is Label and child != _defeat_title:
			child.modulate.a = reveal
	_defeat_button.modulate.a = reveal
	if progress >= 1.0:
		_defeat_transition_active = false
		Engine.time_scale = 1.0
		_defeat_button.disabled = false
		_defeat_button.grab_focus()
		_finish_match(last_result)


func _dismiss_defeat_screen() -> void:
	Engine.time_scale = 1.0
	_defeat_overlay.hide()
	var menu_manager := get_parent()
	if menu_manager.has_method("return_to_main_menu"):
		menu_manager.call("return_to_main_menu")


func _exit_tree() -> void:
	Engine.time_scale = 1.0


@rpc("authority", "call_local", "reliable")
func set_face_eliminated(
	face_name: String,
	value: bool,
	impact_position: Vector3 = Vector3.ZERO,
	play_suction: bool = false
) -> void:
	var paddle: Node = _paddles.get(face_name)
	if paddle != null:
		if value and play_suction and paddle.has_method("play_elimination_suction"):
			paddle.play_elimination_suction(impact_position)
		else:
			paddle.set_eliminated(value)
	# Empty faces become solid again so the ball stays inside the cube.
	var face_direction := face_name.trim_prefix("Paddle_")
	var wall := get_node_or_null("../Wall_" + face_direction + "/WallBody") as StaticBody3D
	if wall != null:
		wall.collision_layer = 1 if value else 0
		wall.collision_mask = 1 if value else 0


func _is_authoritative() -> bool:
	return multiplayer.multiplayer_peer is OfflineMultiplayerPeer or multiplayer.is_server()


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "GameHUD"
	_hud_layer.layer = 2
	add_child(_hud_layer)
	var hud_root := Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(hud_root)
	_timer_label = Label.new()
	_timer_label.position = Vector2(22, 12)
	_timer_label.custom_minimum_size = Vector2(190, 52)
	_timer_label.text = _format_time(time_limit_seconds)
	_timer_label_settings = LabelSettings.new()
	_timer_label_settings.font_size = 40
	_timer_label_settings.font_color = Color(1.0, 1.0, 1.0)
	_timer_label_settings.shadow_size = 16
	_timer_label_settings.shadow_offset = Vector2.ZERO
	_timer_label_settings.shadow_color = Color(1.0, 0.015, 0.02, 0.0)
	_timer_label.label_settings = _timer_label_settings
	hud_root.add_child(_timer_label)
	_score_column = VBoxContainer.new()
	_score_column.name = "FaceLifeStack"
	_score_column.position = Vector2(24, 70)
	_score_column.add_theme_constant_override("separation", 8)
	hud_root.add_child(_score_column)
	for face_name in FACE_ORDER:
		var face_color: Color = FACE_COLORS[face_name]
		var circle := PanelContainer.new()
		circle.custom_minimum_size = Vector2(42, 42)
		var circle_style := StyleBoxFlat.new()
		circle_style.bg_color = face_color
		circle_style.set_corner_radius_all(21)
		circle_style.set_border_width_all(2)
		circle_style.border_color = Color(0.04, 0.05, 0.08, 0.9)
		circle.add_theme_stylebox_override("panel", circle_style)
		var center := CenterContainer.new()
		circle.add_child(center)
		var life_label := Label.new()
		life_label.text = str(starting_lives)
		life_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		life_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		life_label.add_theme_font_size_override("font_size", 19)
		var number_color := Color(0.08, 0.08, 0.08) if face_name in ["Paddle_PosY", "Paddle_NegY"] else Color.WHITE
		life_label.add_theme_color_override("font_color", number_color)
		center.add_child(life_label)
		_score_column.add_child(circle)
		_face_score_labels[face_name] = life_label
		_face_score_circles[face_name] = circle
	_arrange_score_circles()
	_hud_layer.hide()


func _arrange_score_circles() -> void:
	if _score_column == null:
		return
	var ordered_faces: Array[String] = [String(solo_player_face)]
	for face_name in FACE_ORDER:
		if face_name != String(solo_player_face):
			ordered_faces.append(face_name)
	for index in range(ordered_faces.size()):
		var circle := _face_score_circles.get(ordered_faces[index]) as Control
		if circle != null:
			_score_column.move_child(circle, index)


func _record_face_score(face_name: StringName) -> void:
	if not _face_scoring_streaks.has(face_name):
		return
	_face_scoring_streaks[face_name] = int(_face_scoring_streaks[face_name]) + 1
	if int(_face_scoring_streaks[face_name]) >= fire_streak_threshold:
		var paddle: Node = _paddles.get(face_name)
		if paddle != null:
			paddle.set_on_fire(true)


func _reset_face_scoring_streak(face_name: StringName) -> void:
	if _face_scoring_streaks.has(face_name):
		_face_scoring_streaks[face_name] = 0
	var paddle: Node = _paddles.get(face_name)
	if paddle != null:
		paddle.set_on_fire(false)


func _publish_state(message: String) -> void:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		receive_hud_state(time_remaining, round_number, lives.duplicate(true), message, match_active)
	elif multiplayer.is_server():
		rpc("receive_hud_state", time_remaining, round_number, lives.duplicate(true), message, match_active)


@rpc("authority", "call_local", "unreliable")
func receive_hud_state(seconds_left: float, round_value: int, lives_state: Dictionary, message: String, active: bool) -> void:
	if _timer_label == null:
		return
	var displayed_second := int(ceil(seconds_left))
	_timer_label.text = _format_time(seconds_left)
	if displayed_second != _last_displayed_second:
		if _last_displayed_second >= 0:
			_pulse_timer_glow()
		_last_displayed_second = displayed_second
	for face_name in FACE_ORDER:
		var label: Label = _face_score_labels.get(face_name) as Label
		if label != null:
			label.text = str(int(lives_state.get(StringName(face_name), starting_lives)))
	_hud_layer.visible = active


func _pulse_timer_glow() -> void:
	if _timer_glow_tween != null and _timer_glow_tween.is_running():
		_timer_glow_tween.kill()
	_timer_glow_tween = create_tween()
	_timer_glow_tween.tween_property(
		_timer_label_settings,
		"shadow_color",
		Color(1.0, 0.015, 0.02, 0.0),
		0.7
	).from(Color(1.0, 0.015, 0.02, 0.95)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _format_time(value: float) -> String:
	var total := int(ceil(value))
	return "%02d:%02d" % [int(total / 60), total % 60]


func _build_sounds() -> void:
	for i in range(5):
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer%d" % i
		player.volume_db = -8.0
		add_child(player)
		_sound_players.append(player)


func _on_ball_bounced() -> void:
	if _is_authoritative() and match_active:
		_broadcast_sound("hit")


func _broadcast_sound(effect: String) -> void:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_play_sfx_local(effect)
	elif multiplayer.is_server():
		rpc("play_sfx", effect)


@rpc("authority", "call_local", "unreliable")
func play_sfx(effect: String) -> void:
	_play_sfx_local(effect)


func _play_sfx_local(effect: String) -> void:
	var frequency := 440.0
	var duration := 0.08
	match effect:
		"hit":
			frequency = 620.0
			duration = 0.045
		"score":
			frequency = 250.0
			duration = 0.22
		"serve":
			frequency = 520.0
			duration = 0.16
		"game_over":
			frequency = 180.0
			duration = 0.35
	var sample_rate := 22050
	var sample_count := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for i in range(sample_count):
		var envelope := minf(1.0, float(i) / 180.0) * (1.0 - float(i) / sample_count)
		var sample := sin(TAU * frequency * float(i) / sample_rate) * envelope * 0.35
		bytes.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = bytes
	var player := _sound_players[_sound_index]
	_sound_index = (_sound_index + 1) % _sound_players.size()
	player.stream = stream
	player.play()
