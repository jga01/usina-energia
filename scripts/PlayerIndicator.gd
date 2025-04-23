extends Control

# --- UI Node References ---
@onready var player_id_label: Label = $PanelContainer/VBoxContainer/PlayerIDLabel
@onready var stash_amount_label: Label = $PanelContainer/VBoxContainer/StashHBox/StashAmountLabel
@onready var stash_target_label: Label = $PanelContainer/VBoxContainer/StashHBox/StashTargetLabel
@onready var generate_button: Button = $PanelContainer/VBoxContainer/ActionsVBox/GenerateButton # Keep reference for flashing
@onready var stabilize_button: Button = $PanelContainer/VBoxContainer/ActionsVBox/StabilizeButton
@onready var emergency_button: Button = $PanelContainer/VBoxContainer/ActionsVBox/EmergencyButton
@onready var steal_grid_button: Button = $PanelContainer/VBoxContainer/ActionsVBox/StealGridButton
@onready var status_label: Label = $PanelContainer/VBoxContainer/StatusLabel

# --- Constants ---
const DIM_COLOR = Color(0.6, 0.6, 0.6)
const NORMAL_COLOR = Color(1.0, 1.0, 1.0)
const FLASH_COLOR = Color(1.5, 1.5, 1.5) # Brighter than normal
const FLASH_DURATION = 0.1 # Seconds for the flash effect

# --- State ---
var player_id: int = 0
var is_game_running: bool = false
var stash_win_target: int = Config.STASH_WIN_TARGET # Use config default initially
var current_stash: float = 0.0

# Store cooldown END times (in milliseconds since engine start)
var cooldown_end_times: Dictionary = {
	"generate": 0, # Generate usually doesn't have a cooldown, but include for mapping
	"stabilize": 0,
	"emergencyAdjust": 0,
	"stealGrid": 0
}

# Store button references and original text
var action_buttons: Dictionary = {} # Populated in _ready

# Temporary status message handling
var status_message_timer: Timer = Timer.new()

# Store last known player state data to merge with global state updates
var last_player_data: Dictionary = {}

# Store active tweens to avoid conflicts
var active_flash_tweens: Dictionary = {}

func _ready():
	# Populate action_buttons dictionary for easier access
	action_buttons = {
		"generate": {"button": generate_button, "original_text": "Generate"},
		"stabilize": {"button": stabilize_button, "original_text": "Stabilize"},
		"emergencyAdjust": {"button": emergency_button, "original_text": "Emergency"},
		"stealGrid": {"button": steal_grid_button, "original_text": "Steal"}
	}

	# Disable buttons initially, they are just indicators here
	for action_name in action_buttons:
		var button: Button = action_buttons[action_name]["button"]
		if is_instance_valid(button):
			button.disabled = true
			button.modulate = DIM_COLOR

	# Setup status timer
	add_child(status_message_timer)
	status_message_timer.one_shot = true
	status_message_timer.wait_time = 1.5 # How long status messages last
	status_message_timer.timeout.connect(_clear_temporary_status_message)

	# Hide optional status initially
	status_label.hide()
	stash_target_label.text = str(stash_win_target) # Set initial target


func _process(_delta):
	# Update cooldown displays every frame if game is running
	# This handles the countdown text changing over time
	if is_game_running:
		for action_name in action_buttons:
			if cooldown_end_times.get(action_name, 0) > Time.get_ticks_msec():
				_update_button_display(action_name) # Only update if currently on cooldown


func set_player_id(id: int):
	player_id = id
	player_id_label.text = "Player %d" % id

# Called by Display.gd to update this indicator's visuals
# player_data might be empty if only global state changed
func update_display(player_data: Dictionary, global_state: Dictionary):
	# Update game running status and target from global state
	var game_running_changed = is_game_running != global_state.get("gameIsRunning", false)
	is_game_running = global_state.get("gameIsRunning", false)
	stash_win_target = global_state.get("stashWinTarget", Config.STASH_WIN_TARGET)
	stash_target_label.text = str(stash_win_target)

	# Merge new player_data with last known player_data if needed
	if not player_data.is_empty():
		last_player_data = player_data # Store the latest full player update
	else:
		# If only global state changed, use the last known player data for updates
		player_data = last_player_data

	# --- Update Stash ---
	# Only update if player_data actually contains stash info
	if player_data.has("personal_stash"):
		current_stash = player_data.get("personal_stash", 0.0)
		stash_amount_label.text = str(snapped(current_stash, 0.1)) # Format stash nicely
		# print("Indicator %d: Stash updated to %.1f" % [player_id, current_stash]) # DEBUG

	# --- Update Cooldown End Times ---
	# Only update if player_data contains the relevant cooldown info
	var cooldown_changed = false
	for action_name in cooldown_end_times:
		var key = action_name + "_cooldown_end_ms"
		# Special case mapping for emergencyAdjust
		if action_name == "emergencyAdjust": key = "emergency_adjust_cooldown_end_ms"
		elif action_name == "stealGrid": key = "steal_grid_cooldown_end_ms"

		if player_data.has(key):
			var new_cooldown = player_data.get(key, 0)
			if cooldown_end_times[action_name] != new_cooldown:
				cooldown_end_times[action_name] = new_cooldown
				cooldown_changed = true

	# Check for action feedback/status (if GameManager provides it)
	var last_action_status = player_data.get("last_action_status", "")
	if not last_action_status.is_empty():
		_show_temporary_status_message(last_action_status)
	elif status_message_timer.is_stopped(): # Only hide if no temp message active
		status_label.hide()

	# --- Refresh Button Displays ---
	# Refresh all buttons if game running state changed OR if any cooldown changed
	if game_running_changed or cooldown_changed:
		for action_name in action_buttons:
			_update_button_display(action_name)


# --- NEW: Updates text, disabled state, and modulate for a SINGLE button ---
func _update_button_display(action_name: String):
	if not action_buttons.has(action_name): return

	var button_info = action_buttons[action_name]
	var button: Button = button_info["button"]
	var original_text: String = button_info["original_text"]
	var end_time_ms: int = cooldown_end_times.get(action_name, 0)

	if not is_instance_valid(button):
		printerr("PlayerIndicator %d: Button '%s' invalid in _update_button_display." % [player_id, action_name])
		return # Skip if button somehow became invalid

	# Check if a flash tween is active for this button
	if active_flash_tweens.has(action_name) and is_instance_valid(active_flash_tweens[action_name]):
		# Don't update modulate/text if flashing, the flash tween will handle it
		return

	var now_ms = Time.get_ticks_msec()
	var time_left_ms = end_time_ms - now_ms

	if is_game_running and time_left_ms <= 0:
		# Game running, cooldown finished (or no cooldown): Ready state
		button.text = original_text
		button.disabled = false # Button is "active" (not on cooldown)
		button.modulate = NORMAL_COLOR
	elif is_game_running and time_left_ms > 0:
		# Game running, on cooldown
		var seconds_left = ceil(time_left_ms / 1000.0)
		button.text = "%s (%ds)" % [original_text, int(seconds_left)]
		button.disabled = true # Button is "inactive" (on cooldown)
		button.modulate = DIM_COLOR
	else:
		# Game not running: Reset text, keep disabled
		button.text = original_text
		button.disabled = true # Always disabled if game not running
		button.modulate = DIM_COLOR


# --- NEW: Visual feedback for button press ---
func flash_button(action_name: String):
	if not action_buttons.has(action_name):
		printerr("PlayerIndicator %d: Unknown action '%s' for flashing." % [player_id, action_name])
		return

	var button_info = action_buttons[action_name]
	var button_node: Button = button_info["button"]

	if not is_instance_valid(button_node):
		printerr("PlayerIndicator %d: Button node for action '%s' is invalid." % [player_id, action_name])
		return

	# Kill existing tween for this button if it exists
	if active_flash_tweens.has(action_name) and is_instance_valid(active_flash_tweens[action_name]):
		active_flash_tweens[action_name].kill()

	# Create and store the new tween
	var tween = get_tree().create_tween()
	active_flash_tweens[action_name] = tween

	# Get the current modulate to tween from (could be NORMAL or DIM)
	var start_modulate = button_node.modulate

	# Make it brighter briefly, then return to the correct state
	tween.tween_property(button_node, "modulate", FLASH_COLOR, FLASH_DURATION / 2.0).from(start_modulate).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Tween back towards the *target* modulate (based on current state after flash)
	# We need to calculate the target state *now* for the tween end point
	var target_modulate = NORMAL_COLOR # Assume ready by default
	var target_disabled = false
	var now_ms = Time.get_ticks_msec()
	var end_time_ms = cooldown_end_times.get(action_name, 0)
	if not is_game_running or (end_time_ms > now_ms):
		target_modulate = DIM_COLOR
		target_disabled = true

	# Don't tween modulate back if target is same as start (e.g. flashing while already dim)
	# Instead, just ensure state is correct after delay
	if start_modulate != target_modulate:
		tween.tween_property(button_node, "modulate", target_modulate, FLASH_DURATION / 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Ensure the final state (text, disabled) is correctly set after the tween finishes
	# Use tween_callback AFTER properties to ensure it runs last
	tween.tween_callback(_update_button_display.bind(action_name))
	# Make sure tween cleans itself up
	tween.tween_callback(_remove_flash_tween.bind(action_name)) # Call helper to remove from dict


# --- Status Message Helpers ---
func _show_temporary_status_message(message: String):
	status_label.text = "Status: %s" % message
	status_label.show()
	status_message_timer.start()

func _clear_temporary_status_message():
	# Check if another message was posted while timer was running
	if status_message_timer.is_stopped():
		status_label.hide()
		status_label.text = "" # Clear text
		
func _remove_flash_tween(action_name_to_remove: String):
	# Check if it still exists before erasing (optional safety)
	if active_flash_tweens.has(action_name_to_remove):
		# print("Removing tween for: ", action_name_to_remove) # Optional Debug
		active_flash_tweens.erase(action_name_to_remove)

# Call this on game over or reset
func reset_indicator():
	print("Indicator %d: Resetting..." % player_id)
	is_game_running = false
	current_stash = 0.0
	last_player_data = {} # Clear last known player data
	stash_amount_label.text = "0"
	stash_win_target = Config.STASH_WIN_TARGET # Reset target display
	stash_target_label.text = str(stash_win_target)

	# Clear cooldowns
	for action_name in cooldown_end_times:
		cooldown_end_times[action_name] = 0

	# Stop status timer and hide label
	if status_message_timer.time_left > 0: status_message_timer.stop()
	status_label.hide()

	# Kill any active flash tweens
	for action_name in active_flash_tweens:
		if is_instance_valid(active_flash_tweens[action_name]):
			active_flash_tweens[action_name].kill()
	active_flash_tweens.clear()

	# Reset all buttons to their initial (disabled, dim) state
	for action_name in action_buttons:
		_update_button_display(action_name)
