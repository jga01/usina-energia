extends Control

# --- UI Node References ---
# Assign these in the Godot Editor by connecting nodes or ensure paths are correct.
@onready var energy_bar: ProgressBar = $VBoxContainer/EnergyBarContainer/EnergyBar
@onready var energy_level_text: Label = $VBoxContainer/EnergyLevelText
@onready var status_text: Label = $VBoxContainer/StatusText
@onready var coop_progress_text: Label = $VBoxContainer/CoopProgressText
@onready var event_alert_label: Label = $VBoxContainer/EventAlertLabel
@onready var reset_button: Button = $ResetButtonContainer/ResetButton
@onready var safe_zone_indicator_top: ColorRect = $VBoxContainer/EnergyBarContainer/SafeZoneTop
@onready var safe_zone_indicator_bottom: ColorRect = $VBoxContainer/EnergyBarContainer/SafeZoneBottom

# Reference to GameManager Node (Must be a child of the node this script is attached to)
# IMPORTANT: Verify this path in the Godot Editor Scene Tree.
@onready var game_manager: Node = $GameManager

# --- Configuration Thresholds ---
# Copied from Config autoload for direct access, or could use Config.VARIABLE directly.
var DANGER_LOW_THRESHOLD: float = Config.DANGER_LOW_THRESHOLD
var SAFE_ZONE_MIN: float = Config.SAFE_ZONE_MIN
var SAFE_ZONE_MAX: float = Config.SAFE_ZONE_MAX
var DANGER_HIGH_THRESHOLD: float = Config.DANGER_HIGH_THRESHOLD

# --- Timers ---
var event_alert_timer: Timer = Timer.new() # Timer to hide the event alert automatically

# Called when the node enters the scene tree for the first time.
func _ready():
	# Add the dynamically created timer to the scene tree
	add_child(event_alert_timer)
	event_alert_timer.one_shot = true
	event_alert_timer.timeout.connect(_on_event_alert_timer_timeout)

	# Connect the reset button's pressed signal
	reset_button.pressed.connect(_on_reset_button_pressed)

	# Initial UI state
	reset_button.hide() # Hide until game over
	event_alert_label.hide() # Hide until an event occurs

	# --- Setup Visual Safe Zone Indicators ---
	# Wait for the energy bar node to be fully ready before accessing its size/position
	if is_instance_valid(energy_bar) and is_instance_valid(safe_zone_indicator_top) and is_instance_valid(safe_zone_indicator_bottom):
		await energy_bar.ready # Ensure node properties like size are available
		var bar_position = energy_bar.position
		var bar_size = energy_bar.size
		# Assuming ProgressBar min_value=0 and max_value=100
		# Calculate Y position based on percentage from the top of the bar
		safe_zone_indicator_top.position.y = bar_position.y + bar_size.y * (1.0 - SAFE_ZONE_MAX / 100.0)
		safe_zone_indicator_bottom.position.y = bar_position.y + bar_size.y * (1.0 - SAFE_ZONE_MIN / 100.0)
		# Set size (make them thin lines)
		safe_zone_indicator_top.size = Vector2(bar_size.x, 2) # Use bar's width, fixed height
		safe_zone_indicator_bottom.size = Vector2(bar_size.x, 2)
		# Set color (semi-transparent white)
		safe_zone_indicator_top.color = Color(1.0, 1.0, 1.0, 0.5)
		safe_zone_indicator_bottom.color = Color(1.0, 1.0, 1.0, 0.5)
	else:
		printerr("Display Error: Energy Bar or Safe Zone Indicators not found for setup.")


	# --- Connect to GameManager Signals (Host Only) ---
	# The Display script primarily works by reacting to signals from GameManager.
	# Only the host instance (which runs GameManager logic) needs these connections.
	if multiplayer.is_server():
		# Use call_deferred to ensure the game_manager node is fully initialized
		# before we attempt to connect its signals.
		call_deferred("_connect_game_manager_signals")
	else:
		# This instance is a client, not the host.
		# The Display scene isn't typically run on clients in this setup.
		# If it were, it would need its own RPC functions to receive state.
		print("Display Info: Running as client. Signal connections skipped.")


# Deferred function to connect signals after both nodes are ready.
func _connect_game_manager_signals():
	# Double-check if game_manager instance is valid before connecting
	if not is_instance_valid(game_manager):
		printerr("Display Error: GameManager node is invalid when trying to connect signals.")
		return

	print("Display Info: Connecting signals to GameManager.")
	# Connect to signals emitted by GameManager.gd
	game_manager.game_state_updated.connect(_on_game_state_updated)
	game_manager.game_over_triggered.connect(_on_game_over_triggered)
	game_manager.game_reset_triggered.connect(_on_game_reset_triggered)
	game_manager.event_updated.connect(_on_event_updated)
	# Optional: Connect if you want visual feedback for the stabilize effect
	# game_manager.stabilize_effect_updated.connect(_on_stabilize_effect_updated)


# --- UI Update Functions ---

# Updates the energy bar visuals and status text based on the current energy level.
func _update_energy_display(level: float, is_running: bool):
	# Ensure UI elements are valid before updating
	if not is_instance_valid(energy_level_text): return
	if not is_instance_valid(energy_bar): return
	if not is_instance_valid(status_text): return

	# Update the percentage text (rounded to nearest integer)
	energy_level_text.text = "%d%%" % round(level)
	# Update the progress bar value
	energy_bar.value = level

	# --- Update Bar Color and Status Text ---
	var bar_stylebox = energy_bar.get_theme_stylebox("fill") # Get the stylebox used for the bar's fill
	var bar_color = Color.GRAY # Default color when not running
	var status_message = "Waiting..." # Default status

	if is_running:
		status_text.remove_theme_color_override("font_color") # Reset status text color

		# Determine color and status based on energy zones
		if level < DANGER_LOW_THRESHOLD:
			bar_color = Color.DARK_BLUE
			status_message = "Dangerously Low!"
		elif level < SAFE_ZONE_MIN:
			bar_color = Color.LIGHT_BLUE
			status_message = "Low Power"
		elif level >= SAFE_ZONE_MIN and level <= SAFE_ZONE_MAX:
			bar_color = Color.LIME_GREEN
			status_message = "Stable"
		elif level < DANGER_HIGH_THRESHOLD:
			bar_color = Color.ORANGE
			status_message = "High Power"
		else: # level >= DANGER_HIGH_THRESHOLD
			bar_color = Color.RED
			status_message = "Dangerously High!"

		status_text.text = status_message

		# Apply the color to the progress bar's fill
		if bar_stylebox and bar_stylebox.has_method("set_bg_color"):
			# This requires the theme override to use a StyleBoxFlat or similar
			bar_stylebox.set("bg_color", bar_color)
		else:
			# Fallback: Modulate the whole bar's color if theme override isn't set up correctly.
			# Note: This tints the background too, might not look as intended.
			energy_bar.modulate = bar_color
			if not bar_stylebox:
				printerr("Display Warning: No 'fill' StyleBox found for EnergyBar. Using modulate.")
			elif not bar_stylebox.has_method("set_bg_color"):
				printerr("Display Warning: 'fill' StyleBox for EnergyBar does not support 'set_bg_color'. Using modulate.")

	else: # Game is not running (Game Over or Waiting)
		# Use default grey color and let game over/reset functions set status text
		if bar_stylebox and bar_stylebox.has_method("set_bg_color"):
			bar_stylebox.set("bg_color", Color.GRAY)
		else:
			energy_bar.modulate = Color.GRAY


# Updates the text showing the cooperative win progress.
func _update_coop_progress(progress_seconds: float, target_seconds: float, is_running: bool, outcome_reason: String, winner_id: int):
	if not is_instance_valid(coop_progress_text): return

	if target_seconds > 0:
		var safe_progress_seconds = floor(progress_seconds) # Display whole seconds achieved
		var safe_target_seconds = floor(target_seconds)     # Display whole target seconds
		var progress_percent = min(100, floor((progress_seconds / target_seconds) * 100))

		if is_running:
			coop_progress_text.text = "Stability Goal: %ds / %ds (%d%%)" % [safe_progress_seconds, safe_target_seconds, progress_percent]
		elif outcome_reason == "coopWin": # Show final win state even if not running
			coop_progress_text.text = "Stability Goal: %ds / %ds (100%%) - SUCCESS!" % [safe_target_seconds, safe_target_seconds]
		elif not is_running and outcome_reason != "none":
			# Game is over, show the final outcome
			var outcome_text = "Final Status: %s" % outcome_reason.capitalize()
			if outcome_reason == "individualWin":
				outcome_text = "Individual Win: Player %d" % winner_id
			elif outcome_reason == "shutdown":
				outcome_text = "Final Status: Grid Shutdown (Low Energy)"
			elif outcome_reason == "meltdown":
				outcome_text = "Final Status: Grid Meltdown (High Energy)"
			coop_progress_text.text = outcome_text
		else: # Game hasn't started yet or was reset
			coop_progress_text.text = "Stability Goal: 0s / %ds (0%%)" % safe_target_seconds
	else: # Target is 0 (shouldn't normally happen if Config is set)
		coop_progress_text.text = "Stability Goal: Waiting..."


# --- Signal Handlers from GameManager ---

# Called when the GameManager emits 'game_state_updated'.
func _on_game_state_updated(state_data: Dictionary):
	# print("Display received state update: ", state_data) # Debug
	_update_energy_display(state_data.get("energyLevel", 50.0), state_data.get("gameIsRunning", false))
	_update_coop_progress(
		state_data.get("coopWinProgressSeconds", 0.0),
		state_data.get("coopWinTargetSeconds", Config.COOP_WIN_DURATION_SECONDS),
		state_data.get("gameIsRunning", false),
		state_data.get("finalOutcomeReason", "none"),
		state_data.get("finalOutcomeWinner", 0)
	)
	# Event updates are handled by _on_event_updated

# Called when the GameManager emits 'game_over_triggered'.
func _on_game_over_triggered(outcome_data: Dictionary):
	print("Display received Game Over: ", outcome_data)
	if not is_instance_valid(status_text): return

	status_text.add_theme_color_override("font_color", Color.RED) # Make game over text red

	var reason = outcome_data.get("reason", "unknown")
	var winner_id = outcome_data.get("winner_id", 0)
	var outcome_message = "Unknown"

	match reason:
		"coopWin": outcome_message = "Cooperative Win!"
		"shutdown": outcome_message = "Grid Shutdown! (Low Energy)"
		"meltdown": outcome_message = "Grid Meltdown! (High Energy)"
		"individualWin": outcome_message = "Individual Win by Player %d!" % winner_id
		_: outcome_message = "Game Ended (%s)" % reason.capitalize()

	status_text.text = "!!! GAME OVER: %s !!!" % outcome_message

	# Update progress text one last time using final values from GameManager
	if is_instance_valid(game_manager):
		_update_coop_progress(
			game_manager.cumulative_stable_time_s, # Get final value directly
			Config.COOP_WIN_DURATION_SECONDS,
			false, # Game is not running
			reason,
			winner_id
		)
	else:
		# Fallback if game_manager somehow invalid
		_update_coop_progress(0.0, Config.COOP_WIN_DURATION_SECONDS, false, reason, winner_id)

	reset_button.show() # Show the 'Play Again?' button
	_update_event_alert(Config.EventType.NONE, 0) # Clear any active event alert


# Called when the GameManager emits 'game_reset_triggered'.
func _on_game_reset_triggered():
	print("Display received Game Reset.")
	if not is_instance_valid(status_text): return
	if not is_instance_valid(coop_progress_text): return

	status_text.text = "Game Resetting..."
	status_text.remove_theme_color_override("font_color") # Remove red color if game ended before
	coop_progress_text.text = "Stability Goal: Waiting..."
	reset_button.hide() # Hide 'Play Again?' button
	_update_event_alert(Config.EventType.NONE, 0) # Clear any active event alert


# Called when the GameManager emits 'event_updated'.
func _on_event_updated(event_data: Dictionary):
	print("Display received Event Update: ", event_data)
	var event_type = event_data.get("type", Config.EventType.NONE)
	var end_time_milliseconds = event_data.get("end_time_ms", 0)
	_update_event_alert(event_type, end_time_milliseconds)


# --- UI Event Handlers ---

# Called when the 'Play Again?' button is pressed.
func _on_reset_button_pressed():
	# Tell the GameManager (running on this host instance) to request a reset.
	# GameManager handles the actual reset logic and notifying clients via RPC.
	if is_instance_valid(game_manager):
		# Call the RPC function directly on the local GameManager node
		game_manager.rpc_request_reset()
	else:
		printerr("Display Error: Cannot request reset, GameManager instance is invalid.")


# --- Event Alert Helper Functions ---

# Updates the event alert label based on the event data.
func _update_event_alert(type: Config.EventType, end_time_milliseconds: int):
	if not is_instance_valid(event_alert_label): return # Ensure label exists

	# Stop the timer if it's currently running from a previous event alert
	if event_alert_timer.is_processing():
		event_alert_timer.stop()

	if type != Config.EventType.NONE:
		var event_text = "Unknown Event"
		var alert_color = Color.YELLOW # Default alert color

		match type:
			Config.EventType.SURGE:
				event_text = "WARNING: Demand Surge!"
				alert_color = Color.ORANGE_RED
			Config.EventType.EFFICIENCY:
				event_text = "NOTICE: Efficiency Drive!"
				alert_color = Color.LIGHT_GREEN

		var current_time_milliseconds = Time.get_ticks_msec()
		var time_left_milliseconds = end_time_milliseconds - current_time_milliseconds
		var duration_seconds = max(0.0, time_left_milliseconds / 1000.0) # Ensure non-negative

		if duration_seconds > 0:
			# Event is active, show the alert
			event_alert_label.text = "%s (%ds left)" % [event_text, ceil(duration_seconds)]
			event_alert_label.add_theme_color_override("font_color", alert_color)
			event_alert_label.show()
			# Start the timer to hide the alert when the event duration ends
			event_alert_timer.wait_time = duration_seconds
			event_alert_timer.start()
		else:
			# Event type received, but its end time is already past
			event_alert_label.hide()
			event_alert_label.remove_theme_color_override("font_color")
	else:
		# No active event (EventType.NONE)
		event_alert_label.hide()
		event_alert_label.remove_theme_color_override("font_color")


# Called when the event_alert_timer times out.
func _on_event_alert_timer_timeout():
	# Hide the label gracefully when the event ends
	if is_instance_valid(event_alert_label):
		event_alert_label.hide()
		event_alert_label.remove_theme_color_override("font_color")
