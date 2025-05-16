# File: scripts/PlayerProfiles.gd
extends Node

# Structure: {"key": "char_male_1", "name": "Commander Rex", "gender": "male", "description": "A brave leader.", "portraits": {...}}
# You MUST replace these placeholder paths with your actual asset paths.
const AVAILABLE_CHARACTERS: Array[Dictionary] = [
	{
		"key": "char_male_1", "name": "Comandante Rex", "gender": "male",
		"description": "Um lider estoico com uma mente tatica.",
		"portraits": {
			"normal": "res://assets/portraits/char_male_1_normal.jpeg",
			"warning": "res://assets/portraits/char_male_1_warning.jpeg",
			"danger": "res://assets/portraits/char_male_1_danger.jpeg",
			"dead": "res://assets/portraits/char_male_1_dead.jpeg"
		}
	},
	{
		"key": "char_male_2", "name": "Tecnico Spike", "gender": "male",
		"description": "Expert de gadgets, sempre projetando algo.",
		"portraits": {
			"normal": "res://assets/portraits/char_male_2_normal.jpeg",
			"warning": "res://assets/portraits/char_male_2_warning.jpeg",
			"danger": "res://assets/portraits/char_male_2_danger.jpeg",
			"dead": "res://assets/portraits/char_male_2_dead.jpeg"
		}
	},
	{
		"key": "char_female_1", "name": "Engenheira Ada", "gender": "female",
		"description": "Inventora brilhante, mestre de sistemas complexos.",
		"portraits": {
			"normal": "res://assets/portraits/char_female_1_normal.jpeg",
			"warning": "res://assets/portraits/char_female_1_warning.jpeg",
			"danger": "res://assets/portraits/char_female_1_danger.jpeg",
			"dead": "res://assets/portraits/char_female_1_dead.jpeg"
		}
	},
	{
		"key": "char_female_2", "name": "Operadora Nova", "gender": "female",
		"description": "Agil e perspicaz, percebe cada detalhe.",
		"portraits": {
			"normal": "res://assets/portraits/char_female_2_normal.jpeg",
			"warning": "res://assets/portraits/char_female_2_warning.jpeg",
			"danger": "res://assets/portraits/char_female_2_danger.jpeg",
			"dead": "res://assets/portraits/char_female_2_dead.jpeg"
		}
	}
]

# Use a default placeholder if specific character portraits are missing
# YOU MUST REPLACE THESE WITH YOUR ACTUAL DEFAULT ASSET PATHS or ensure all characters have all portraits
const DEFAULT_PORTRAITS: Dictionary = {
	"normal": "res://assets/icon_normal.svg", # Example placeholder
	"warning": "res://assets/icon_warning.svg", # Example placeholder
	"danger": "res://assets/icon_danger.svg", # Example placeholder
	"dead": "res://assets/icon_dead.svg"      # Example placeholder
}


# Stores the chosen character KEY for each player ID. e.g., {1: "char_male_1", 2: "char_female_2"}
var player_character_selections: Dictionary = {} # { player_id: character_key }

var G_TEMP_GAME_OUTCOME_DATA: Dictionary = {}

func select_character(player_id: int, character_key: String) -> bool:
	if not _is_valid_character_key(character_key):
		printerr("PlayerProfiles: Invalid character key '%s' for player %d." % [character_key, player_id])
		return false

	# Check if this character is already definitively taken by another player
	for pid in player_character_selections:
		if pid != player_id and player_character_selections[pid] == character_key:
			printerr("PlayerProfiles: Character %s already taken by Player %d. Cannot select for Player %d." % [character_key, pid, player_id])
			return false

	player_character_selections[player_id] = character_key
	print("PlayerProfiles: Player %d selected character '%s' (%s)" % [player_id, get_character_details_by_key(character_key).name, character_key])
	return true

func deselect_character(player_id: int):
	if player_character_selections.has(player_id):
		var deselected_char_key = player_character_selections.erase(player_id)
		if not deselected_char_key.is_empty():
			print("PlayerProfiles: Player %d deselected character %s" % [player_id, deselected_char_key])


func get_selected_character_key(player_id: int) -> String:
	return player_character_selections.get(player_id, "")

func get_character_details_by_key(character_key: String) -> Dictionary:
	for char_data in AVAILABLE_CHARACTERS:
		if char_data.key == character_key:
			return char_data
	return {}

func get_selected_character_details(player_id: int) -> Dictionary:
	var char_key = get_selected_character_key(player_id)
	if not char_key.is_empty():
		return get_character_details_by_key(char_key)
	return {} # Return empty if no selection or invalid ID

func get_all_selections() -> Dictionary:
	return player_character_selections.duplicate()

func reset_selections():
	player_character_selections.clear()
	print("PlayerProfiles: Selections reset.")

func _is_valid_character_key(character_key: String) -> bool:
	for char_data in AVAILABLE_CHARACTERS:
		if char_data.key == character_key:
			return true
	return false

# Helper used by CharacterSelection.gd to know which keys are already taken
func get_all_selected_character_keys_array() -> Array[String]:
	var keys_array: Array[String] = []
	for char_key in player_character_selections.values():
		if not char_key.is_empty():
			keys_array.append(char_key)
	return keys_array

# NEW helper function to get portrait path
func get_character_portrait_path(player_id: int, status_key: String) -> String:
	var char_details = get_selected_character_details(player_id)

	# Check if the character has a "portraits" dictionary and if that dictionary has the requested status_key
	if char_details.has("portraits") and typeof(char_details.portraits) == TYPE_DICTIONARY and char_details.portraits.has(status_key):
		return char_details.portraits[status_key]

	# Fallback to default portraits if specific character or status portrait is missing
	if DEFAULT_PORTRAITS.has(status_key):
		# Only print error if the specific character was supposed to have portraits but didn't have the key
		if char_details.has("portraits") and typeof(char_details.portraits) == TYPE_DICTIONARY:
			printerr("PlayerProfiles: Player %d (%s) missing portrait for status '%s'. Using default." % [player_id, char_details.get("key", "UnknownChar"), status_key])
		elif not char_details.has("portraits"):
			printerr("PlayerProfiles: Player %d (%s) has no 'portraits' defined. Using default for status '%s'." % [player_id, char_details.get("key", "UnknownChar"), status_key])
		return DEFAULT_PORTRAITS[status_key]

	# Absolute fallback if even the default for the status_key is missing (should not happen if DEFAULT_PORTRAITS is set up correctly)
	printerr("PlayerProfiles: Player %d (%s) missing portrait for status '%s' AND default for that status is missing. Using absolute default normal." % [player_id, char_details.get("key", "UnknownChar"), status_key])
	return DEFAULT_PORTRAITS.get("normal", "") # Absolute fallback to default normal portrait


func set_temp_game_outcome_data(data: Dictionary):
	G_TEMP_GAME_OUTCOME_DATA = data

func get_temp_game_outcome_data() -> Dictionary:
	var data = G_TEMP_GAME_OUTCOME_DATA.duplicate() # Return a copy
	G_TEMP_GAME_OUTCOME_DATA.clear() # Clear after reading
	return data
