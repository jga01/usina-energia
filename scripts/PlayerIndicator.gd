# File: res://scripts/PlayerIndicator.gd
extends Control

@onready var player_id_label: Label = $PanelContainer/MarginContainer/VBoxContainer/PlayerIDLabel
@onready var character_portrait: TextureRect = $CharacterPortrait
@onready var stash_amount_label: Label = $PanelContainer/MarginContainer/VBoxContainer/StashHBox/StashAmountLabel
@onready var stash_icon: TextureRect = $PanelContainer/MarginContainer/VBoxContainer/StashHBox/StashIcon # Reference to the new stash icon
@onready var panel_container_node: PanelContainer = $PanelContainer # Direct reference to PanelContainer for modulation

# Removed: action_button, status_label references

const DIM_COLOR_MODULATE = Color(0.6, 0.6, 0.6, 0.8) # For eliminated player portrait/text
const NORMAL_COLOR_MODULATE = Color(1.0, 1.0, 1.0, 1.0)
const ELIMINATED_PANEL_MODULATE = Color(0.4, 0.4, 0.4, 0.7) # Darker panel when eliminated

var player_id: int = 0
# Removed: is_game_running (not directly used by indicator logic anymore for button state)
# Removed: stash_win_target (not displayed on indicator anymore)
var current_stash: float = 0.0
var is_player_eliminated: bool = false

# Removed: status_message_clear_timer

# Preload stash icon texture (REPLACE WITH YOUR ACTUAL ASSET PATH)
const STASH_ICON_TEXTURE = preload("res://assets/new/stash.png") # Example path

func _ready():
	if is_instance_valid(stash_icon) and STASH_ICON_TEXTURE:
		stash_icon.texture = STASH_ICON_TEXTURE
	else:
		printerr("PlayerIndicator: Stash icon texture not loaded or node invalid.")

	# Ensure the PanelContainer is correctly styled by the NinePatchRect
	# This is mostly handled by scene setup now, but good to be aware of.
	# If panel_container_node.theme_override_styles/panel is not StyleBoxEmpty, NinePatch won't show.
	# It's set to null in the .tscn to allow NinePatchRect to be the visual background.

	if is_instance_valid(character_portrait) and PlayerProfiles:
		character_portrait.texture = load(PlayerProfiles.DEFAULT_PORTRAITS.get("normal", "res://icon.svg"))
	elif is_instance_valid(character_portrait):
		character_portrait.texture = load("res://icon.svg") # Absolute fallback

func set_player_id(id: int):
	player_id = id
	if is_instance_valid(player_id_label):
		player_id_label.text = TextDB.GENERIC_PLAYER_LABEL_FORMAT % id
	_update_portrait_for_initial_selection()

func _update_portrait_for_initial_selection():
	# Load initial portrait based on ID and character selection
	if is_instance_valid(character_portrait) and PlayerProfiles:
		var portrait_path = PlayerProfiles.get_character_portrait_path(player_id, "normal")
		if not portrait_path.is_empty():
			var tex = load(portrait_path)
			if tex: character_portrait.texture = tex
			else: printerr("PI %d: Failed to load initial portrait: %s" % [player_id, portrait_path])
		else: # Fallback to default if specific not found
			character_portrait.texture = load(PlayerProfiles.DEFAULT_PORTRAITS.get("normal", "res://icon.svg"))


func update_display(player_data: Dictionary, global_state: Dictionary):
	# is_game_running = global_state.get("gameIsRunning", false) # Keep if needed for portrait logic
	# stash_win_target = global_state.get("stashWinTarget", Config.STASH_WIN_TARGET) # Not displayed

	if not player_data.is_empty():
		is_player_eliminated = player_data.get("is_eliminated", is_player_eliminated)
		current_stash = player_data.get("personal_stash", current_stash)
		if is_instance_valid(stash_amount_label):
			stash_amount_label.text = str(snapped(current_stash, 0.1))

		# Temporary status messages are now handled by the main Display.gd, not here.
		# var last_action_status_key = player_data.get("last_action_status", "")
		# if not last_action_status_key.is_empty():
			# _show_temporary_status_message(last_action_status_key) # Removed

	_update_character_portrait_display(global_state) # Update portrait based on global/player state
	# _update_action_button_state() # Removed, no button state to update

	if is_instance_valid(panel_container_node):
		if is_player_eliminated:
			if is_instance_valid(player_id_label):
				player_id_label.text = (TextDB.GENERIC_PLAYER_LABEL_FORMAT % player_id) # No suffix needed, portrait shows elimination
				player_id_label.modulate = DIM_COLOR_MODULATE
			panel_container_node.modulate = ELIMINATED_PANEL_MODULATE
			character_portrait.modulate = DIM_COLOR_MODULATE # Dim the portrait too
		else: # Not eliminated
			if is_instance_valid(player_id_label):
				player_id_label.text = TextDB.GENERIC_PLAYER_LABEL_FORMAT % player_id
				player_id_label.modulate = NORMAL_COLOR_MODULATE
			panel_container_node.modulate = NORMAL_COLOR_MODULATE
			character_portrait.modulate = NORMAL_COLOR_MODULATE


func _update_character_portrait_display(g_state: Dictionary):
	if not is_instance_valid(character_portrait) or not PlayerProfiles: return
	
	var portrait_status_key = "normal"
	var game_is_running_for_portrait = g_state.get("gameIsRunning", false) # Local var for clarity

	if is_player_eliminated:
		portrait_status_key = "dead"
	elif game_is_running_for_portrait : # Only show warning/danger if game is running
		var energy = g_state.get("energyLevel", 50.0)
		var active_event = g_state.get("activeEventType", Config.EventType.NONE)
		
		if active_event == Config.EventType.UNSTABLE_GRID:
			portrait_status_key = "danger"
		elif active_event == Config.EventType.SURGE:
			portrait_status_key = "warning"
		else: # Normal energy level checks
			if energy < g_state.get("dangerLow", Config.DANGER_LOW_THRESHOLD) or \
			   energy > g_state.get("dangerHigh", Config.DANGER_HIGH_THRESHOLD):
				portrait_status_key = "danger"
			elif energy < g_state.get("safeZoneMin", Config.SAFE_ZONE_MIN) or \
				 energy > g_state.get("safeZoneMax", Config.SAFE_ZONE_MAX):
				portrait_status_key = "warning"
				
	var portrait_path = PlayerProfiles.get_character_portrait_path(player_id, portrait_status_key)
	if not portrait_path.is_empty():
		var tex = load(portrait_path)
		if tex: character_portrait.texture = tex
		else: character_portrait.texture = load(PlayerProfiles.DEFAULT_PORTRAITS.get("normal","res://icon.svg"))
	else:
		character_portrait.texture = load(PlayerProfiles.DEFAULT_PORTRAITS.get("normal","res://icon.svg"))

# Removed _update_action_button_state()
# Removed flash_button()
# Removed _show_temporary_status_message()
# Removed _clear_temporary_status_message()

func reset_indicator():
	print("Indicator %d: Resetting (minimalist)..." % player_id)
	# is_game_running = false # Not directly used here anymore
	current_stash = 0.0
	is_player_eliminated = false
	
	if is_instance_valid(stash_amount_label): stash_amount_label.text = "0"
	# stash_win_target = Config.STASH_WIN_TARGET # Not displayed
	
	if is_instance_valid(player_id_label):
		player_id_label.text = TextDB.GENERIC_PLAYER_LABEL_FORMAT % player_id
		player_id_label.modulate = NORMAL_COLOR_MODULATE
	
	if is_instance_valid(panel_container_node): panel_container_node.modulate = NORMAL_COLOR_MODULATE
	if is_instance_valid(character_portrait): character_portrait.modulate = NORMAL_COLOR_MODULATE
	
	_update_portrait_for_initial_selection() # Reset portrait to normal for selected char

	# No status message timer or flash tween to manage
	# No action button state to update
