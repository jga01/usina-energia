# File: res://scripts/GameOverScreen.gd
extends Control

@onready var title_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TitleLabel
@onready var outcome_message_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/OutcomeMessageLabel
@onready var play_again_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/PlayAgainButton
@onready var main_menu_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/MainMenuButton
@onready var background_texture_rect: TextureRect = $BackgroundTexture

# Define background textures based on game outcome
var game_over_background_textures: Dictionary = {
	"default": preload("res://assets/background.png"), # Fallback generic background
	"coopWin": preload("res://assets/usina-normal.jpeg"), # Victory/Stable
	"shutdown": preload("res://assets/usina-danger-shutdown.jpeg"), # Defeat - shutdown
	"meltdown": preload("res://assets/usina-danger-meltdown.jpeg"), # Defeat - meltdown
	"individualWin": preload("res://assets/usina-normal.jpeg"), # Victory/Stable (can be specific)
	"allEliminated": preload("res://assets/usina-gameover.jpeg"), # Defeat - all players out
	"lastPlayerStanding": preload("res://assets/usina-normal.jpeg"), # Victory/Stable (can be specific)
	"unknown_defeat": preload("res://assets/usina-gameover.jpeg") # For other generic defeat cases
}


func _ready():
	play_again_button.pressed.connect(_on_play_again_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)

	# Set button texts from TextDB
	play_again_button.text = TextDB.GO_PLAY_AGAIN_BUTTON
	main_menu_button.text = TextDB.GO_MAIN_MENU_BUTTON
	title_label.text = TextDB.GO_TITLE_GAME_OVER_DEFAULT # Default title

	var outcome_data_from_profile: Dictionary
	if PlayerProfiles:
		outcome_data_from_profile = PlayerProfiles.get_temp_game_outcome_data()
	else:
		printerr("GameOverScreen Error: PlayerProfiles autoload not found. Cannot retrieve game outcome data.")
		outcome_message_label.text = TextDB.GO_OUTCOME_UNKNOWN_NO_DATA
		if is_instance_valid(background_texture_rect) and game_over_background_textures.has("default"):
			background_texture_rect.texture = game_over_background_textures["default"]
		return

	if outcome_data_from_profile.is_empty():
		outcome_message_label.text = TextDB.GO_OUTCOME_UNKNOWN_NO_DATA
		printerr("GameOverScreen: No game_outcome_data received from PlayerProfiles!")
		if is_instance_valid(background_texture_rect) and game_over_background_textures.has("default"):
			background_texture_rect.texture = game_over_background_textures["default"]
	else:
		_display_outcome(outcome_data_from_profile)

func _display_outcome(current_game_outcome_data: Dictionary):
	var reason = current_game_outcome_data.get("reason", "unknown")
	var winner_id = current_game_outcome_data.get("winner_id", 0)
	var message = TextDB.GO_OUTCOME_MESSAGE_DEFAULT_PREFIX + reason.capitalize() # Fallback message
	var selected_background = game_over_background_textures.get("default")

	match reason:
		"coopWin":
			message = TextDB.GO_MSG_COOP_WIN
			title_label.text = TextDB.GO_TITLE_COOP_WIN
			title_label.self_modulate = Color.LIGHT_GREEN
			if game_over_background_textures.has("coopWin"):
				selected_background = game_over_background_textures["coopWin"]
		"shutdown":
			message = TextDB.GO_MSG_SHUTDOWN
			title_label.text = TextDB.GO_TITLE_SHUTDOWN
			title_label.self_modulate = Color.ORANGE_RED
			if game_over_background_textures.has("shutdown"):
				selected_background = game_over_background_textures["shutdown"]
		"meltdown":
			message = TextDB.GO_MSG_MELTDOWN if TextDB.has_constant("GO_MSG_MELTDOWN") else "DEFEAT!\n\nThe grid suffered a catastrophic meltdown due to high energy."
			title_label.text = TextDB.GO_TITLE_MELTDOWN if TextDB.has_constant("GO_TITLE_MELTDOWN") else "GRID MELTDOWN"
			title_label.self_modulate = Color.DARK_RED
			if game_over_background_textures.has("meltdown"):
				selected_background = game_over_background_textures["meltdown"]
		"individualWin":
			if winner_id > 0 and PlayerProfiles:
				var winner_char_details = PlayerProfiles.get_selected_character_details(winner_id)
				var winner_name = winner_char_details.get("name", TextDB.GENERIC_PLAYER_LABEL_FORMAT % winner_id)
				message = TextDB.GO_MSG_INDIVIDUAL_WIN_PLAYER % winner_name
				title_label.text = TextDB.GO_TITLE_INDIVIDUAL_WIN_PLAYER % winner_name.to_upper()
				title_label.self_modulate = Color.GOLD
				if game_over_background_textures.has("individualWin"):
					selected_background = game_over_background_textures["individualWin"]
			else:
				message = TextDB.GO_MSG_INDIVIDUAL_WIN_UNKNOWN
				title_label.text = TextDB.GO_TITLE_INDIVIDUAL_WIN_UNKNOWN
				if game_over_background_textures.has("unknown_defeat"):
					selected_background = game_over_background_textures["unknown_defeat"]
		"allEliminated":
			message = TextDB.GO_MSG_ALL_ELIMINATED
			title_label.text = TextDB.GO_TITLE_ALL_ELIMINATED
			title_label.self_modulate = Color.DARK_RED
			if game_over_background_textures.has("allEliminated"):
				selected_background = game_over_background_textures["allEliminated"]
		"lastPlayerStanding":
			if winner_id > 0 and PlayerProfiles:
				var winner_char_details = PlayerProfiles.get_selected_character_details(winner_id)
				var winner_name = winner_char_details.get("name", TextDB.GENERIC_PLAYER_LABEL_FORMAT % winner_id)
				message = TextDB.GO_MSG_LAST_PLAYER_STANDING % winner_name
				title_label.text = TextDB.GO_TITLE_LAST_PLAYER_STANDING % winner_name.to_upper()
				title_label.self_modulate = Color.ORANGE
				if game_over_background_textures.has("lastPlayerStanding"):
					selected_background = game_over_background_textures["lastPlayerStanding"]
			else:
				message = TextDB.GO_MSG_LAST_PLAYER_STANDING_UNKNOWN
				title_label.text = TextDB.GO_TITLE_LAST_PLAYER_STANDING_UNKNOWN
				if game_over_background_textures.has("unknown_defeat"):
					selected_background = game_over_background_textures["unknown_defeat"]
		_:
			message = TextDB.GO_MSG_CONCLUDED_REASON_PREFIX % reason.capitalize()
			title_label.text = TextDB.GO_TITLE_GAME_OVER_DEFAULT
			if game_over_background_textures.has("unknown_defeat"):
				selected_background = game_over_background_textures["unknown_defeat"]

	outcome_message_label.text = message
	if is_instance_valid(background_texture_rect) and selected_background:
		background_texture_rect.texture = selected_background

func _on_play_again_pressed():
	print("GameOverScreen: Play Again pressed. Transitioning to CharacterSelection.")
	get_tree().change_scene_to_file("res://scenes/CharacterSelection.tscn")

func _on_main_menu_pressed():
	print("GameOverScreen: Main Menu pressed. Transitioning to MainMenu.")
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
