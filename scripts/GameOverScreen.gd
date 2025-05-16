# File: res://scripts/GameOverScreen.gd
extends Control

@onready var title_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TitleLabel
@onready var outcome_message_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/OutcomeMessageLabel
@onready var leaderboard_title_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/LeaderboardTitleLabel
@onready var leaderboard_vbox: VBoxContainer = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/LeaderboardVBox
@onready var play_again_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/PlayAgainButton
@onready var main_menu_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/MainMenuButton
@onready var background_texture_rect: TextureRect = $BackgroundTexture

# Define colors for background modulation based on outcome
const COLOR_COOP_WIN = Color(0.7, 1.0, 0.7, 1.0)         # Light green tint
const COLOR_SHUTDOWN = Color(1.0, 0.6, 0.6, 1.0)         # Reddish tint
const COLOR_MELTDOWN = Color(1.0, 0.4, 0.4, 1.0)         # Stronger red tint
const COLOR_INDIVIDUAL_WIN = Color(1.0, 0.85, 0.5, 1.0)  # Golden tint
const COLOR_ALL_ELIMINATED = Color(0.6, 0.6, 0.6, 1.0)   # Dark grey tint (desaturation effect)
const COLOR_LAST_PLAYER_STANDING = Color(1.0, 0.75, 0.5, 1.0) # Orange tint
const COLOR_DEFAULT_OUTCOME = Color(1.0, 1.0, 1.0, 1.0)    # No tint / default (white)

# Removed: var game_over_background_textures: Dictionary


func _ready():
	play_again_button.pressed.connect(_on_play_again_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)

	play_again_button.text = TextDB.GO_PLAY_AGAIN_BUTTON
	main_menu_button.text = TextDB.GO_MAIN_MENU_BUTTON
	title_label.text = TextDB.GO_TITLE_GAME_OVER_DEFAULT
	
	if is_instance_valid(leaderboard_title_label):
		leaderboard_title_label.text = TextDB.GO_LEADERBOARD_TITLE
		leaderboard_title_label.hide() 
	if is_instance_valid(leaderboard_vbox):
		for child in leaderboard_vbox.get_children():
			child.queue_free()

	# Set initial background modulation to default (no tint)
	if is_instance_valid(background_texture_rect):
		background_texture_rect.modulate = COLOR_DEFAULT_OUTCOME

	var outcome_data_from_profile: Dictionary
	if PlayerProfiles:
		outcome_data_from_profile = PlayerProfiles.get_temp_game_outcome_data()
	else:
		printerr("GameOverScreen Error: PlayerProfiles autoload not found.")
		outcome_message_label.text = TextDB.GO_OUTCOME_UNKNOWN_NO_DATA
		# Background modulation will remain COLOR_DEFAULT_OUTCOME
		return

	if outcome_data_from_profile.is_empty():
		outcome_message_label.text = TextDB.GO_OUTCOME_UNKNOWN_NO_DATA
		printerr("GameOverScreen: No game_outcome_data received from PlayerProfiles!")
		# Background modulation will remain COLOR_DEFAULT_OUTCOME
	else:
		_display_outcome(outcome_data_from_profile)
		if outcome_data_from_profile.has("leaderboard_data"):
			_populate_leaderboard(outcome_data_from_profile.get("leaderboard_data"))
		elif is_instance_valid(leaderboard_title_label):
			leaderboard_title_label.hide()


func _display_outcome(current_game_outcome_data: Dictionary):
	var reason = current_game_outcome_data.get("reason", "unknown")
	var winner_id = current_game_outcome_data.get("winner_id", 0)
	var message = TextDB.GO_OUTCOME_MESSAGE_DEFAULT_PREFIX + reason.capitalize()
	
	var target_modulate_color = COLOR_DEFAULT_OUTCOME # Default modulation

	match reason:
		"coopWin":
			message = TextDB.GO_MSG_COOP_WIN
			title_label.text = TextDB.GO_TITLE_COOP_WIN
			title_label.self_modulate = Color.LIGHT_GREEN
			target_modulate_color = COLOR_COOP_WIN
		"shutdown":
			message = TextDB.GO_MSG_SHUTDOWN
			title_label.text = TextDB.GO_TITLE_SHUTDOWN
			title_label.self_modulate = Color.ORANGE_RED
			target_modulate_color = COLOR_SHUTDOWN
		"meltdown":
			message = TextDB.GO_MSG_MELTDOWN
			title_label.text = TextDB.GO_TITLE_MELTDOWN
			title_label.self_modulate = Color.DARK_RED
			target_modulate_color = COLOR_MELTDOWN
		"individualWin":
			if winner_id > 0 and PlayerProfiles:
				var winner_char_details = PlayerProfiles.get_selected_character_details(winner_id)
				var winner_name = winner_char_details.get("name", TextDB.GENERIC_PLAYER_LABEL_FORMAT % winner_id)
				message = TextDB.GO_MSG_INDIVIDUAL_WIN_PLAYER % winner_name
				title_label.text = TextDB.GO_TITLE_INDIVIDUAL_WIN_PLAYER % winner_name.to_upper()
				title_label.self_modulate = Color.GOLD
				target_modulate_color = COLOR_INDIVIDUAL_WIN
			else:
				message = TextDB.GO_MSG_INDIVIDUAL_WIN_UNKNOWN
				title_label.text = TextDB.GO_TITLE_INDIVIDUAL_WIN_UNKNOWN
				# target_modulate_color remains COLOR_DEFAULT_OUTCOME or you can set a specific one
		"allEliminated":
			message = TextDB.GO_MSG_ALL_ELIMINATED
			title_label.text = TextDB.GO_TITLE_ALL_ELIMINATED
			title_label.self_modulate = Color.DARK_RED
			target_modulate_color = COLOR_ALL_ELIMINATED
		"lastPlayerStanding":
			if winner_id > 0 and PlayerProfiles:
				var winner_char_details = PlayerProfiles.get_selected_character_details(winner_id)
				var winner_name = winner_char_details.get("name", TextDB.GENERIC_PLAYER_LABEL_FORMAT % winner_id)
				message = TextDB.GO_MSG_LAST_PLAYER_STANDING % winner_name
				title_label.text = TextDB.GO_TITLE_LAST_PLAYER_STANDING % winner_name.to_upper()
				title_label.self_modulate = Color.ORANGE
				target_modulate_color = COLOR_LAST_PLAYER_STANDING
			else:
				message = TextDB.GO_MSG_LAST_PLAYER_STANDING_UNKNOWN
				title_label.text = TextDB.GO_TITLE_LAST_PLAYER_STANDING_UNKNOWN
				# target_modulate_color remains COLOR_DEFAULT_OUTCOME or you can set a specific one
		_: # Handles "unknown" or any other reason
			message = TextDB.GO_MSG_CONCLUDED_REASON_PREFIX % reason.capitalize()
			title_label.text = TextDB.GO_TITLE_GAME_OVER_DEFAULT
			# target_modulate_color remains COLOR_DEFAULT_OUTCOME

	outcome_message_label.text = message
	if is_instance_valid(background_texture_rect):
		background_texture_rect.modulate = target_modulate_color


func _populate_leaderboard(leaderboard_data: Array[Dictionary]):
	if not is_instance_valid(leaderboard_vbox) or not is_instance_valid(leaderboard_title_label):
		printerr("GameOverScreen: Leaderboard VBox or TitleLabel not found!")
		return
	
	for child in leaderboard_vbox.get_children():
		child.queue_free()

	if leaderboard_data.is_empty():
		leaderboard_title_label.hide()
		return
	else:
		leaderboard_title_label.show()
		
	var game_reason = ""
	if PlayerProfiles: 
		var outcome_data = PlayerProfiles.get_temp_game_outcome_data() 
		game_reason = outcome_data.get("reason", "")

	if game_reason == "coopWin":
		leaderboard_data.sort_custom(func(a, b):
			if a.generated_energy > b.generated_energy: return true
			if a.generated_energy < b.generated_energy: return false
			if a.score > b.score: return true 
			if a.score < b.score: return false
			return a.player_id < b.player_id
		)
	else:
		leaderboard_data.sort_custom(func(a, b):
			if a.score > b.score: return true
			if a.score < b.score: return false
			if a.generated_energy > b.generated_energy: return true 
			if a.generated_energy < b.generated_energy: return false
			return a.player_id < b.player_id
		)

	var entry_font = preload("res://assets/Daydream.ttf")
	var entry_font_size = 14

	for i in range(leaderboard_data.size()):
		var player_entry_data = leaderboard_data[i]
		
		var entry_hbox = HBoxContainer.new()
		entry_hbox.add_theme_constant_override("separation", 8)

		var rank_label = Label.new()
		rank_label.text = str(i + 1) + "."
		rank_label.custom_minimum_size.x = 35 
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if entry_font: rank_label.add_theme_font_override("font", entry_font)
		rank_label.add_theme_font_size_override("font_size", entry_font_size)
		entry_hbox.add_child(rank_label)

		var name_label = Label.new()
		name_label.text = player_entry_data.get("character_name", "Player " + str(player_entry_data.get("player_id")))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL 
		name_label.clip_text = true
		if entry_font: name_label.add_theme_font_override("font", entry_font)
		name_label.add_theme_font_size_override("font_size", entry_font_size)
		entry_hbox.add_child(name_label)

		var score_label = Label.new()
		score_label.text = TextDB.GO_LEADERBOARD_STASH_PREFIX + str(snapped(player_entry_data.get("score", 0.0), 0.1))
		score_label.custom_minimum_size.x = 130
		score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		if entry_font: score_label.add_theme_font_override("font", entry_font)
		score_label.add_theme_font_size_override("font_size", entry_font_size)
		entry_hbox.add_child(score_label)
		
		var generated_energy_label = Label.new()
		generated_energy_label.text = TextDB.GO_LEADERBOARD_GENERATED_PREFIX + str(snapped(player_entry_data.get("generated_energy", 0.0), 0.1))
		generated_energy_label.custom_minimum_size.x = 110
		generated_energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		if entry_font: generated_energy_label.add_theme_font_override("font", entry_font)
		generated_energy_label.add_theme_font_size_override("font_size", entry_font_size)
		entry_hbox.add_child(generated_energy_label)

		var status_indicator_width = 35
		if player_entry_data.get("is_eliminated", false):
			var status_label = Label.new() 
			status_label.text = "(X)" 
			status_label.self_modulate = Color.RED
			status_label.custom_minimum_size.x = status_indicator_width
			status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			if entry_font: status_label.add_theme_font_override("font", entry_font)
			status_label.add_theme_font_size_override("font_size", entry_font_size)
			entry_hbox.add_child(status_label)
		else: 
			var spacer = Control.new()
			spacer.custom_minimum_size.x = status_indicator_width
			entry_hbox.add_child(spacer)
		
		leaderboard_vbox.add_child(entry_hbox)


func _on_play_again_pressed():
	print("GameOverScreen: Play Again pressed. Transitioning to CharacterSelection.")
	get_tree().change_scene_to_file("res://scenes/CharacterSelection.tscn")

func _on_main_menu_pressed():
	print("GameOverScreen: Main Menu pressed. Transitioning to MainMenu.")
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
