extends Node3D

## Single-player menu: one local human and five AI opponents.
const FACE_CHOICES := [
	["Front (+Z) — Red", "Paddle_PosZ"], ["Back (−Z) — Orange", "Paddle_NegZ"],
	["Right (+X) — Blue", "Paddle_PosX"], ["Left (−X) — Green", "Paddle_NegX"],
	["Top (+Y) — White", "Paddle_PosY"], ["Bottom (−Y) — Yellow", "Paddle_NegY"],
]

var paddles: Array[Node] = []
var game_manager: Node
var menu_overlay: ColorRect
var status_label: Label
var face_option: OptionButton
var difficulty_option: OptionButton
var play_button: Button

func _ready() -> void:
	game_manager = get_node_or_null("GameManager")
	paddles = get_tree().get_nodes_in_group("paddles")
	paddles.sort_custom(func(a: Node, b: Node) -> bool: return a.name < b.name)
	for paddle in paddles:
		paddle.set_bot_mode(true)
	_build_menu()
	if game_manager != null:
		game_manager.match_started.connect(_on_match_started)
		game_manager.match_finished.connect(_on_match_finished)

func _build_menu() -> void:
	menu_overlay = ColorRect.new()
	menu_overlay.name = "SoloMenu"
	menu_overlay.color = Color(0.015, 0.025, 0.06, 0.94)
	menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	var title := Label.new()
	title.text = "CUBE PONG"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "LAST FACE STANDING"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 22)
	box.add_child(subtitle)
	var description := Label.new()
	description.text = "Protect your face, outlast five bots, and survive as the ball gets faster."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(description)
	var face_label := Label.new()
	face_label.text = "Choose your face"
	box.add_child(face_label)
	face_option = OptionButton.new()
	for choice in FACE_CHOICES:
		face_option.add_item(choice[0])
		face_option.set_item_metadata(face_option.item_count - 1, StringName(choice[1]))
	box.add_child(face_option)
	var difficulty_label := Label.new()
	difficulty_label.text = "Bot difficulty"
	box.add_child(difficulty_label)
	difficulty_option = OptionButton.new()
	difficulty_option.add_item("Relaxed")
	difficulty_option.add_item("Classic")
	difficulty_option.add_item("Fierce")
	difficulty_option.select(1)
	box.add_child(difficulty_option)
	play_button = Button.new()
	play_button.text = "Play against 5 bots"
	play_button.custom_minimum_size = Vector2(0, 48)
	play_button.pressed.connect(_start_solo_match)
	box.add_child(play_button)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)
	var controls := Label.new()
	controls.text = "WASD moves the paddle · Move/flick mouse to aim its angle at the same time · Tilt eases back to center · Hold Shift while moving to boost · 3 lives · 3 minute match"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_theme_font_size_override("font_size", 13)
	box.add_child(controls)
	add_child(menu_overlay)

func _start_solo_match() -> void:
	if game_manager == null:
		status_label.text = "GameManager is missing from the Arena scene."
		return
	var player_face := StringName(face_option.get_item_metadata(face_option.selected))
	var player_found := false
	for paddle in paddles:
		paddle.offline_test_paddle_name = player_face
		var is_player := paddle.name == player_face
		player_found = player_found or is_player
		paddle.set_bot_mode(not is_player)
		paddle.set_player_visual(is_player)
		paddle.set_bot_difficulty(difficulty_option.selected)
	if not player_found:
		status_label.text = "Could not find the selected paddle in the Arena."
		return
	game_manager.solo_player_face = player_face
	game_manager.begin_local_test()

func _on_match_started() -> void:
	menu_overlay.hide()

func _on_match_finished() -> void:
	status_label.text = game_manager.last_result + "\nChoose a face or difficulty and play again."
	play_button.text = "Play again"
	if game_manager.last_result.begins_with("DEFEAT:"):
		menu_overlay.hide()
	else:
		menu_overlay.show()
