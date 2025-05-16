# File: res://scripts/CharacterSelection.gd
extends Control

@onready var turn_indicator_label: Label = $VBoxContainer/PanelContainer/TurnIndicatorLabel
@onready var prev_char_button: Button = $VBoxContainer/PanelContainer2/VBoxContainer/HBoxCharacterDisplay/PrevCharButton
@onready var character_name_label: Label = $VBoxContainer/PanelContainer2/VBoxContainer/HBoxCharacterDisplay/CharacterNameLabel
@onready var next_char_button: Button = $VBoxContainer/PanelContainer2/VBoxContainer/HBoxCharacterDisplay/NextCharButton
@onready var character_description_label: Label = $VBoxContainer/PanelContainer2/VBoxContainer/CharacterDescriptionLabel
@onready var confirm_button: Button = $VBoxContainer/PanelContainer3/ConfirmButton
@onready var character_portrait_preview: TextureRect = $VBoxContainer/PanelContainer2/VBoxContainer/CharacterPortraitPreview # Ensure this node exists in your .tscn

var current_player_id_turn: int = 1
var num_players_total: int = Config.NUM_PLAYERS

var available_characters_for_selection: Array[Dictionary] = []
var current_char_index_for_player: int = 0

func _ready():
	prev_char_button.pressed.connect(_on_prev_char_button_pressed)
	next_char_button.pressed.connect(_on_next_char_button_pressed)
	confirm_button.pressed.connect(_on_confirm_button_pressed)

	PlayerProfiles.reset_selections()
	_start_player_turn()

func _start_player_turn():
	turn_indicator_label.text = TextDB.CS_PLAYER_TURN % current_player_id_turn

	var previously_selected_key_for_this_player = PlayerProfiles.get_selected_character_key(current_player_id_turn)

	available_characters_for_selection.clear()
	var globally_taken_keys_by_others: Array[String] = []
	for pid_other in range(1, current_player_id_turn):
		var key_taken_by_other = PlayerProfiles.get_selected_character_key(pid_other)
		if not key_taken_by_other.is_empty():
			globally_taken_keys_by_others.append(key_taken_by_other)

	for char_data in PlayerProfiles.AVAILABLE_CHARACTERS:
		if not globally_taken_keys_by_others.has(char_data.key):
			available_characters_for_selection.append(char_data)

	if available_characters_for_selection.is_empty():
		character_name_label.text = TextDB.CS_NO_CHARACTERS_AVAILABLE
		character_description_label.text = TextDB.CS_ERROR_NOT_ENOUGH_CHARS
		if is_instance_valid(character_portrait_preview): character_portrait_preview.texture = null
		prev_char_button.disabled = true
		next_char_button.disabled = true
		confirm_button.disabled = true
		printerr("CharacterSelection: No characters available for Player %d to choose from!" % current_player_id_turn)
		return

	current_char_index_for_player = 0
	if not previously_selected_key_for_this_player.is_empty():
		for i in range(available_characters_for_selection.size()):
			if available_characters_for_selection[i].key == previously_selected_key_for_this_player:
				current_char_index_for_player = i
				break

	_update_displayed_character()
	_update_confirm_button_state()


func _update_displayed_character():
	if available_characters_for_selection.is_empty() or \
	   current_char_index_for_player < 0 or \
	   current_char_index_for_player >= available_characters_for_selection.size():
		character_name_label.text = "---"
		character_description_label.text = ""
		if is_instance_valid(character_portrait_preview): character_portrait_preview.texture = null
		prev_char_button.disabled = true
		next_char_button.disabled = true
		return

	var char_data = available_characters_for_selection[current_char_index_for_player]
	character_name_label.text = char_data.get("name", TextDB.CS_CHARACTER_NAME_LABEL_PLACEHOLDER)
	character_description_label.text = char_data.get("description", TextDB.CS_CHARACTER_DESCRIPTION_LABEL_PLACEHOLDER)

	if is_instance_valid(character_portrait_preview):
		var portraits_data = char_data.get("portraits") # This should be a Dictionary
		if portraits_data and typeof(portraits_data) == TYPE_DICTIONARY:
			var portrait_path = portraits_data.get("normal", "") # Use "normal" as the preview
			if not portrait_path.is_empty():
				var portrait_tex = load(portrait_path)
				if portrait_tex:
					character_portrait_preview.texture = portrait_tex
				else:
					printerr("CharacterSelection: Failed to load preview portrait texture at path: ", portrait_path, " for character: ", char_data.get("name"))
					character_portrait_preview.texture = null
			else:
				printerr("CharacterSelection: 'normal' portrait path is empty or missing for character: ", char_data.get("name"))
				character_portrait_preview.texture = null
		else:
			printerr("CharacterSelection: 'portraits' data missing or not a dictionary for character: ", char_data.get("name"))
			character_portrait_preview.texture = null

	prev_char_button.disabled = (current_char_index_for_player == 0)
	next_char_button.disabled = (current_char_index_for_player == available_characters_for_selection.size() - 1)


func _on_prev_char_button_pressed():
	if current_char_index_for_player > 0:
		current_char_index_for_player -= 1
		_update_displayed_character()

func _on_next_char_button_pressed():
	if current_char_index_for_player < available_characters_for_selection.size() - 1:
		current_char_index_for_player += 1
		_update_displayed_character()

func _on_confirm_button_pressed():
	if available_characters_for_selection.is_empty():
		printerr("CharacterSelection: Confirm pressed with no characters available.")
		return
	if current_char_index_for_player < 0 or current_char_index_for_player >= available_characters_for_selection.size():
		printerr("CharacterSelection: Confirm pressed with invalid character index.")
		return

	var selected_char_data = available_characters_for_selection[current_char_index_for_player]

	PlayerProfiles.deselect_character(current_player_id_turn)
	var success = PlayerProfiles.select_character(current_player_id_turn, selected_char_data.key)

	if not success:
		turn_indicator_label.text = TextDB.CS_ERROR_CHARACTER_TAKEN % selected_char_data.name
		printerr("CharacterSelection: Failed to select character %s for player %d - check availability logic." % [selected_char_data.key, current_player_id_turn])
		_start_player_turn()
		return

	print("Player %d confirmed: %s" % [current_player_id_turn, selected_char_data.name])

	current_player_id_turn += 1
	if current_player_id_turn <= num_players_total:
		_start_player_turn()
	else:
		print("All players selected. Starting game...")
		print("Final Selections:", PlayerProfiles.get_all_selections())
		get_tree().change_scene_to_file("res://scenes/Display.tscn")

func _update_confirm_button_state():
	if current_player_id_turn > num_players_total:
		confirm_button.disabled = true
		confirm_button.text = TextDB.CS_ALL_CONFIRMED_BUTTON
	elif current_player_id_turn == num_players_total:
		confirm_button.text = TextDB.CS_CONFIRM_START_GAME_BUTTON
		confirm_button.disabled = available_characters_for_selection.is_empty()
	else:
		confirm_button.text = TextDB.CS_CONFIRM_NEXT_PLAYER_BUTTON
		confirm_button.disabled = available_characters_for_selection.is_empty()
