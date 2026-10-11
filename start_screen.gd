extends Control
## Start screen. Root node is a Control with a VBoxContainer holding
## a Title label, a "StartButton" and a "QuitButton".

@export_file("*.tscn") var game_scene: String = "res://scenes/arena.tscn"

@onready var start_button: Button = $VBoxContainer/Start
@onready var quit_button: Button = $VBoxContainer/Quit


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(get_tree().quit)
	start_button.grab_focus()  # Enter/Space or arrow keys work right away


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(game_scene)
