extends Node3D

## Single-player menu: one local human and five AI opponents.
const FACE_CHOICES := [
	["Front (+Z) — Red", "Paddle_PosZ"], ["Back (−Z) — Orange", "Paddle_NegZ"],
	["Right (+X) — Blue", "Paddle_PosX"], ["Left (−X) — Green", "Paddle_NegX"],
	["Top (+Y) — White", "Paddle_PosY"], ["Bottom (−Y) — Yellow", "Paddle_NegY"],
]

var paddles: Array[Node] = []
var player_paddle: Node
var game_manager: Node
var menu_overlay: ColorRect
var status_label: Label
var face_option: OptionButton
var difficulty_option: OptionButton
var play_button: Button
var _menu_pages: Dictionary = {}
var _menu_page_host: VBoxContainer
var _menu_preview_camera: Camera3D
var _menu_preview_ball: CharacterBody3D
var _menu_preview_paddle_origins: Dictionary = {}
var _menu_preview_running := false
var _menu_preview_elapsed := 0.0
const MENU_PREVIEW_LOOP_SECONDS := 22.0
const MENU_PREVIEW_ORBIT_RADIUS := 17.0

func _ready() -> void:
	game_manager = get_node_or_null("GameManager")
	paddles = get_tree().get_nodes_in_group("paddles")
	paddles.sort_custom(func(a: Node, b: Node) -> bool: return a.name < b.name)
	for paddle in paddles:
		paddle.set_bot_mode(true)
		_menu_preview_paddle_origins[paddle.name] = paddle.position
	_build_menu()
	_start_menu_preview()
	if game_manager != null:
		game_manager.match_started.connect(_on_match_started)
		game_manager.match_finished.connect(_on_match_finished)


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion or game_manager == null or not game_manager.match_active:
		return
	if player_paddle != null and player_paddle.has_method("add_mouse_tilt_motion"):
		player_paddle.add_mouse_tilt_motion(event.screen_relative)


func _process(delta: float) -> void:
	if not _menu_preview_running or menu_overlay == null or not menu_overlay.visible:
		return
	if game_manager != null and game_manager.match_active:
		_stop_menu_preview()
		return
	_update_menu_preview(delta)


func _start_menu_preview() -> void:
	if game_manager != null and game_manager.match_active:
		return
	_menu_preview_ball = get_node_or_null("Ball") as CharacterBody3D
	if _menu_preview_ball == null or not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	if _menu_preview_camera == null:
		_menu_preview_camera = Camera3D.new()
		_menu_preview_camera.name = "MenuCinematicCamera"
		_menu_preview_camera.fov = 90.0
		add_child(_menu_preview_camera)
	_menu_preview_camera.make_current()
	for index in range(paddles.size()):
		var paddle := paddles[index]
		paddle.set_match_active(false)
		paddle.set_eliminated(false)
		paddle.position = _menu_preview_paddle_origins.get(paddle.name, Vector3.ZERO)
		var face_suffix := String(paddle.name).trim_prefix("Paddle_")
		var wall := get_node_or_null("Wall_" + face_suffix + "/WallBody") as StaticBody3D
		if wall != null:
			wall.collision_layer = 1
			wall.collision_mask = 1
	for face_suffix in ["PosZ", "NegZ", "PosX", "NegX", "PosY", "NegY"]:
		var wall := get_node_or_null("Wall_" + face_suffix + "/WallBody") as StaticBody3D
		if wall != null:
			wall.collision_layer = 1
			wall.collision_mask = 1
	_menu_preview_elapsed = 0.0
	_reset_menu_preview_ball()
	_menu_preview_running = true
	_update_menu_preview(0.0)


func _stop_menu_preview() -> void:
	_menu_preview_running = false
	if _menu_preview_ball != null and is_instance_valid(_menu_preview_ball):
		_menu_preview_ball.stop_ball()
	for paddle in paddles:
		if is_instance_valid(paddle):
			paddle.position = _menu_preview_paddle_origins.get(paddle.name, Vector3.ZERO)


func _reset_menu_preview_ball() -> void:
	if _menu_preview_ball == null:
		return
	_menu_preview_ball.speed = _menu_preview_ball.start_speed
	_menu_preview_ball.reset_size()
	_menu_preview_ball.reset_to_center()
	var preview_direction := Vector3(1.0, 0.37, 0.74).normalized()
	_menu_preview_ball.velocity = preview_direction * _menu_preview_ball.speed
	_menu_preview_ball.is_running = true


func _update_menu_preview(delta: float) -> void:
	_menu_preview_elapsed += delta
	if _menu_preview_elapsed >= MENU_PREVIEW_LOOP_SECONDS:
		_menu_preview_elapsed = fmod(_menu_preview_elapsed, MENU_PREVIEW_LOOP_SECONDS)
		_reset_menu_preview_ball()
	var orbit_angle := TAU * _menu_preview_elapsed / MENU_PREVIEW_LOOP_SECONDS
	_menu_preview_camera.global_position = Vector3(
		cos(orbit_angle) * MENU_PREVIEW_ORBIT_RADIUS,
		7.5,
		sin(orbit_angle) * MENU_PREVIEW_ORBIT_RADIUS
	)
	_menu_preview_camera.look_at(Vector3.ZERO, Vector3.UP)
	for index in range(paddles.size()):
		var paddle := paddles[index]
		var origin: Vector3 = _menu_preview_paddle_origins.get(paddle.name, Vector3.ZERO)
		var phase := orbit_angle + TAU * float(index) / float(maxi(1, paddles.size()))
		paddle.position = origin + Vector3(sin(phase) * 3.25, sin(phase * 2.0 + 0.8) * 2.75, 0.0)


func return_to_main_menu() -> void:
	_show_menu_page("home")
	menu_overlay.show()
	_start_menu_preview()

func _build_menu() -> void:
	menu_overlay = ColorRect.new()
	menu_overlay.name = "SoloMenu"
	menu_overlay.color = Color(0.008, 0.014, 0.035, 0.28)
	menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_overlay.add_child(center)
	var viewport_size := get_viewport().get_visible_rect().size
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(minf(820.0, viewport_size.x - 36.0), minf(650.0, viewport_size.y - 28.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(scroll)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = scroll.custom_minimum_size.x
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.04, 0.085, 0.62)
	panel_style.border_color = Color(0.0, 0.0, 0.0, 0.0)
	panel_style.set_border_width_all(0)
	panel_style.set_corner_radius_all(18)
	panel.add_theme_stylebox_override("panel", panel_style)
	scroll.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	var title := Label.new()
	title.text = "PING DAT PONG"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "A 3D Cube, Solo-Survival Game"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.42, 0.78, 1.0))
	box.add_child(subtitle)
	_menu_page_host = VBoxContainer.new()
	_menu_page_host.add_theme_constant_override("separation", 8)
	box.add_child(_menu_page_host)
	_build_home_page()
	_build_play_page()
	_build_rules_page()
	_build_controls_page()
	_show_menu_page("home")
	add_child(menu_overlay)


func _build_home_page() -> void:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	_menu_page_host.add_child(page)
	_menu_pages["home"] = page
	var intro := Label.new()
	intro.text = "Choose a page, set up your match, and defend your face."
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color(0.78, 0.84, 0.95))
	page.add_child(intro)
	_add_menu_nav_button(page, "PLAY", "play", Color(0.12, 0.48, 0.78))
	_add_menu_nav_button(page, "RULES", "rules", Color(0.18, 0.27, 0.42))
	_add_menu_nav_button(page, "CONTROLS", "controls", Color(0.18, 0.27, 0.42))


func _build_play_page() -> void:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	_menu_page_host.add_child(page)
	_menu_pages["play"] = page
	var heading := Label.new()
	heading.text = "MATCH SETUP"
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
	page.add_child(heading)
	var face_label := Label.new()
	face_label.text = "YOUR FACE"
	face_label.add_theme_font_size_override("font_size", 12)
	face_label.add_theme_color_override("font_color", Color(0.68, 0.75, 0.9))
	page.add_child(face_label)
	face_option = OptionButton.new()
	for choice in FACE_CHOICES:
		face_option.add_item(choice[0])
		face_option.set_item_metadata(face_option.item_count - 1, StringName(choice[1]))
	page.add_child(face_option)
	var difficulty_label := Label.new()
	difficulty_label.text = "BOT DIFFICULTY"
	difficulty_label.add_theme_font_size_override("font_size", 12)
	difficulty_label.add_theme_color_override("font_color", Color(0.68, 0.75, 0.9))
	page.add_child(difficulty_label)
	difficulty_option = OptionButton.new()
	difficulty_option.add_item("Relaxed")
	difficulty_option.add_item("Classic")
	difficulty_option.add_item("Fierce")
	difficulty_option.select(1)
	page.add_child(difficulty_option)
	play_button = Button.new()
	play_button.text = "Play against 5 bots"
	play_button.custom_minimum_size = Vector2(0, 52)
	play_button.add_theme_font_size_override("font_size", 18)
	_style_menu_button(play_button, Color(0.12, 0.48, 0.78))
	play_button.pressed.connect(_start_solo_match)
	page.add_child(play_button)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color(1.0, 0.56, 0.48))
	page.add_child(status_label)
	_add_menu_nav_button(page, "BACK", "home", Color(0.18, 0.27, 0.42))


func _build_rules_page() -> void:
	var page := _build_menu_card("RULES")
	_menu_page_host.add_child(page)
	_menu_pages["rules"] = page
	_add_rule_row(page, "1", "Each face has one life. A missed shot eliminates that face.", Color(1.0, 0.58, 0.28))
	_add_rule_row(page, "2", "Use your paddle to keep the ball away from your colored wall.", Color(0.35, 0.72, 1.0))
	_add_rule_row(page, "3", "The ball grows and speeds up after every score.", Color(0.9, 0.42, 1.0))
	_add_rule_row(page, "4", "When two faces remain, the match enters DUEL.", Color(1.0, 0.82, 0.27))
	_add_rule_row(page, "★", "Be the last face standing to win.", Color(0.38, 0.95, 0.68))
	_add_menu_nav_button(page, "BACK", "home", Color(0.18, 0.27, 0.42))


func _build_controls_page() -> void:
	var page := _build_menu_card("CONTROLS")
	_menu_page_host.add_child(page)
	_menu_pages["controls"] = page
	_add_control_row(page, ["W", "A", "S", "D"], "Move your paddle across your face.")
	_add_control_row(page, ["MOUSE"], "Move or flick to aim hits. The paddle tilt eases back to center.")
	_add_control_row(page, ["SHIFT"], "Hold while moving to boost. Fuel refills over time.")
	_add_control_row(page, ["ESC"], "Release the mouse cursor.")
	_add_menu_nav_button(page, "BACK", "home", Color(0.18, 0.27, 0.42))


func _show_menu_page(page_name: String) -> void:
	for name in _menu_pages:
		var page := _menu_pages[name] as Control
		if page != null:
			page.visible = String(name) == page_name


func _add_menu_nav_button(parent: Control, text: String, page_name: String, color: Color) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 48)
	_style_menu_button(button, color)
	button.pressed.connect(_show_menu_page.bind(page_name))
	parent.add_child(button)


func _style_menu_button(button: Button, color: Color) -> void:
	button.add_theme_font_size_override("font_size", 16)
	button.text = "✦  ◈  " + button.text.to_upper()
	var normal := StyleBoxFlat.new()
	normal.bg_color = color.darkened(0.58)
	normal.border_color = color.lightened(0.22)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.shadow_color = Color(color.r, color.g, color.b, 0.38)
	normal.shadow_size = 9
	normal.shadow_offset = Vector2(0, 2)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = color.darkened(0.38)
	hover.border_color = color.lightened(0.42)
	hover.set_border_width_all(2)
	hover.shadow_color = Color(color.r, color.g, color.b, 0.68)
	hover.shadow_size = 15
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = color.darkened(0.28)
	button.add_theme_stylebox_override("pressed", pressed)


func _build_menu_card(heading_text: String) -> VBoxContainer:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	var heading := Label.new()
	heading.text = heading_text
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
	content.add_child(heading)
	return content


func _add_rule_row(parent: VBoxContainer, marker: String, description: String, tint: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var badge := Label.new()
	badge.text = marker
	badge.custom_minimum_size = Vector2(26, 26)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_color_override("font_color", tint)
	badge.add_theme_font_size_override("font_size", 15)
	row.add_child(badge)
	var text := Label.new()
	text.text = description
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 13)
	row.add_child(text)


func _add_control_row(parent: VBoxContainer, keys: Array[String], description: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)
	var key_group := HBoxContainer.new()
	key_group.add_theme_constant_override("separation", 4)
	key_group.custom_minimum_size.x = 116.0
	key_group.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(key_group)
	for key_text in keys:
		var keycap := PanelContainer.new()
		keycap.custom_minimum_size = Vector2(34 if key_text.length() < 5 else 70, 30)
		var key_style := StyleBoxFlat.new()
		key_style.bg_color = Color(0.11, 0.15, 0.24, 1.0)
		key_style.border_color = Color(0.30, 0.40, 0.57, 1.0)
		key_style.set_border_width_all(1)
		key_style.set_corner_radius_all(6)
		keycap.add_theme_stylebox_override("panel", key_style)
		var key_label := Label.new()
		key_label.text = key_text
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key_label.add_theme_font_size_override("font_size", 11 if key_text.length() >= 5 else 14)
		key_label.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0))
		keycap.add_child(key_label)
		key_group.add_child(keycap)
	var text := Label.new()
	text.text = description
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 12)
	row.add_child(text)

func _start_solo_match() -> void:
	if game_manager == null:
		status_label.text = "GameManager is missing from the Arena scene."
		return
	var player_face := StringName(face_option.get_item_metadata(face_option.selected))
	var player_found := false
	player_paddle = null
	for paddle in paddles:
		paddle.offline_test_paddle_name = player_face
		var is_player := paddle.name == player_face
		player_found = player_found or is_player
		if is_player:
			player_paddle = paddle
		paddle.set_bot_mode(not is_player)
		paddle.set_player_visual(is_player)
		paddle.set_bot_difficulty(difficulty_option.selected)
	if not player_found:
		player_paddle = null
		status_label.text = "Could not find the selected paddle in the Arena."
		return
	_stop_menu_preview()
	game_manager.solo_player_face = player_face
	game_manager.begin_local_test()

func _on_match_started() -> void:
	_menu_preview_running = false
	menu_overlay.hide()

func _on_match_finished() -> void:
	status_label.text = game_manager.last_result + "\nChoose a face or difficulty and play again."
	play_button.text = "✦  ◈  PLAY AGAIN"
	_show_menu_page("home")
	if game_manager.last_result.begins_with("DEFEAT:"):
		menu_overlay.hide()
	else:
		menu_overlay.show()
		_start_menu_preview()
