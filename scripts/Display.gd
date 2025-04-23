extends Control

# --- UI Node References ---
@onready var energy_bar: ProgressBar = $VBoxContainer/EnergyBarContainer/EnergyBar
@onready var energy_level_text: Label = $VBoxContainer/EnergyLevelText
@onready var status_text: Label = $VBoxContainer/StatusText
@onready var coop_progress_text: Label = $VBoxContainer/CoopProgressText
@onready var event_alert_label: Label = $VBoxContainer/EventAlertLabel
@onready var reset_button: Button = $ResetButtonContainer/ResetButton
@onready var safe_zone_indicator_top: ColorRect = $VBoxContainer/EnergyBarContainer/SafeZoneTop
@onready var safe_zone_indicator_bottom: ColorRect = $VBoxContainer/EnergyBarContainer/SafeZoneBottom
# Reference to GameManager
@onready var game_manager: Node = $GameManager
# Reference to the NEW parent container for player indicators
@onready var player_indicators_parent: Control = $PlayerIndicatorsParent # Point to the Control node

# Preload the player indicator scene
const PlayerIndicatorScene = preload("res://scenes/PlayerIndicator.tscn")

# Dictionary to hold references to player indicator instances { player_id: PlayerIndicatorNode }
var player_indicators: Dictionary = {}

# Store last known global state for updating indicators when only player state changes
var last_global_state: Dictionary = {}

# Timers
var event_alert_timer: Timer = Timer.new()

# Define margin for positioning
const INDICATOR_MARGIN = 10.0 # Pixels from the edge

func _ready():
	add_child(event_alert_timer)
	event_alert_timer.one_shot = true
	event_alert_timer.timeout.connect(_on_event_alert_timer_timeout)

	# --- Check Node Validity FIRST ---
	var game_manager_valid = is_instance_valid(game_manager)
	var reset_button_valid = is_instance_valid(reset_button) # Check reset_button validity early

	# --- Handle GameManager and Reset Button Connection ---
	if not game_manager_valid:
		printerr("Display Error: GameManager node not found!")
		# Attempt to disable reset button if it exists, even if GM doesn't
		if reset_button_valid:
			reset_button.disabled = true
	else:
		# GameManager is valid, now check reset_button before connecting
		if reset_button_valid:
			# Both GameManager and ResetButton are valid, connect the signal
			if not reset_button.pressed.is_connected(game_manager.handle_reset_request):
				reset_button.pressed.connect(game_manager.handle_reset_request)
		else:
			# GameManager is valid, but reset_button is not
			printerr("Display Error: ResetButton node not found, cannot connect signal.")

		# Connect other GameManager Signals (safe because we know game_manager is valid here)
		_connect_game_manager_signals()

	# --- Initial UI State ---
	# Hide buttons/labels only if they are valid instances
	if reset_button_valid:
		reset_button.hide()
	else:
		# If reset_button wasn't found initially, print another warning here if desired
		# printerr("Display Warning: ResetButton node was null in _ready, cannot hide.")
		pass

	if is_instance_valid(event_alert_label):
		event_alert_label.hide()

	# Create Player Indicators - Now using the new parent and deferred positioning
	_create_player_indicators()

	# Defer visual setup for energy bar safe zone indicators
	if is_instance_valid(energy_bar) and is_instance_valid(safe_zone_indicator_top) and is_instance_valid(safe_zone_indicator_bottom):
		print("DISPLAY DEBUG: Calling deferred setup for visuals.")
		call_deferred("_setup_visuals_deferred")
	else:
		printerr("Display Error: Cannot defer visual setup - Energy Bar or Safe Zone Indicators not found.")

# --- NEW FUNCTION for Deferred Visual Setup ---
func _setup_visuals_deferred():
	print("DISPLAY DEBUG: _setup_visuals_deferred called.")
	if not is_instance_valid(energy_bar):
		printerr("Display Error: Energy Bar invalid in _setup_visuals_deferred.")
		return
	if not is_instance_valid(safe_zone_indicator_top) or not is_instance_valid(safe_zone_indicator_bottom):
		printerr("Display Error: Safe Zone Indicators invalid in _setup_visuals_deferred.")
		return

	# Position and size the safe zone indicators relative to the energy bar
	var bar_global_rect = energy_bar.get_global_rect()
	# Convert global rect back to local coordinates relative to EnergyBarContainer
	var container_inv_transform = energy_bar.get_parent().get_global_transform().affine_inverse()
	var bar_local_pos = container_inv_transform * bar_global_rect.position
	var bar_local_size = bar_global_rect.size # Size is invariant under translation

	var sz_min = Config.SAFE_ZONE_MIN
	var sz_max = Config.SAFE_ZONE_MAX

	# Calculate Y positions based on percentage of bar height
	# Note: ProgressBar value=0 is top, value=100 is bottom. Y increases downwards.
	var y_top_sz = bar_local_pos.y + bar_local_size.y * (1.0 - sz_max / 100.0)
	var y_bottom_sz = bar_local_pos.y + bar_local_size.y * (1.0 - sz_min / 100.0)

	safe_zone_indicator_top.position = Vector2(bar_local_pos.x, y_top_sz)
	safe_zone_indicator_bottom.position = Vector2(bar_local_pos.x, y_bottom_sz)
	safe_zone_indicator_top.size = Vector2(bar_local_size.x, 2) # Small height for the line
	safe_zone_indicator_bottom.size = Vector2(bar_local_size.x, 2) # Small height for the line
	safe_zone_indicator_top.color = Color(0.8, 0.8, 0.8, 0.6) # Semi-transparent white/gray
	safe_zone_indicator_bottom.color = Color(0.8, 0.8, 0.8, 0.6) # Semi-transparent white/gray
	print("DISPLAY DEBUG: Visuals setup completed.")


func _connect_game_manager_signals():
	if not is_instance_valid(game_manager):
		printerr("Display Error: GameManager invalid when connecting signals.")
		return

	print("Display Info: Connecting signals to GameManager.")
	# Connect global state update
	if not game_manager.game_state_updated.is_connected(_on_game_state_updated):
		var err = game_manager.game_state_updated.connect(_on_game_state_updated)
		if err != OK: printerr("DISPLAY ERROR: Failed to connect game_state_updated signal! Error: %s" % err)

	# Connect player state update
	if not game_manager.player_state_updated.is_connected(_on_player_state_updated):
		var err = game_manager.player_state_updated.connect(_on_player_state_updated)
		if err != OK: printerr("DISPLAY ERROR: Failed to connect player_state_updated signal! Error: %s" % err)

	# Connect game over signal
	if not game_manager.game_over_triggered.is_connected(_on_game_over_triggered):
		var err = game_manager.game_over_triggered.connect(_on_game_over_triggered)
		if err != OK: printerr("DISPLAY ERROR: Failed to connect game_over_triggered signal! Error: %s" % err)

	# Connect game reset signal
	if not game_manager.game_reset_triggered.is_connected(_on_game_reset_triggered):
		var err = game_manager.game_reset_triggered.connect(_on_game_reset_triggered)
		if err != OK: printerr("DISPLAY ERROR: Failed to connect game_reset_triggered signal! Error: %s" % err)

	# Connect event update signal
	if not game_manager.event_updated.is_connected(_on_event_updated):
		var err = game_manager.event_updated.connect(_on_event_updated)
		if err != OK: printerr("DISPLAY ERROR: Failed to connect event_updated signal! Error: %s" % err)

	# Connect stabilize effect update signal
	if not game_manager.stabilize_effect_updated.is_connected(_on_stabilize_effect_updated):
		var err = game_manager.stabilize_effect_updated.connect(_on_stabilize_effect_updated)
		if err != OK: printerr("DISPLAY ERROR: Failed to connect stabilize_effect_updated signal! Error: %s" % err)

	# --- NEW: Connect visual feedback signal ---
	if not game_manager.player_action_visual_feedback.is_connected(_on_player_action_visual_feedback):
		var err = game_manager.player_action_visual_feedback.connect(_on_player_action_visual_feedback)
		if err != OK: printerr("DISPLAY ERROR: Failed to connect player_action_visual_feedback signal! Error: %s" % err)
	# --- END NEW ---


func _create_player_indicators():
	# Clear any old indicators first
	# Use the NEW parent node reference here
	if is_instance_valid(player_indicators_parent):
		for child in player_indicators_parent.get_children():
			child.queue_free()
	player_indicators.clear()

	# Use NUM_PLAYERS from Config (GameManager might not be fully ready yet)
	var num_players = Config.NUM_PLAYERS

	print("Display: Creating %d player indicators." % num_players)
	for i in range(1, num_players + 1):
		var indicator_instance = PlayerIndicatorScene.instantiate()
		if indicator_instance:
			# Add to the NEW parent node
			if is_instance_valid(player_indicators_parent):
				player_indicators_parent.add_child(indicator_instance)
				indicator_instance.name = "PlayerIndicator_%d" % i # Optional: Give unique name
				indicator_instance.set_player_id(i)
				player_indicators[i] = indicator_instance # Store reference by player ID

				# --- POSITIONING LOGIC MOVED TO DEFERRED FUNCTION ---
			else:
				printerr("Display Error: PlayerIndicatorsParent node is not valid!")
		else:
			printerr("Display Error: Failed to instantiate PlayerIndicatorScene!")

	# --- Call the positioning function deferred ---
	call_deferred("_position_indicators")

# --- NEW FUNCTION TO POSITION INDICATORS ---
func _position_indicators():
	if not is_instance_valid(player_indicators_parent):
		printerr("Display Error: Cannot position indicators, parent node invalid.")
		return

	# Get the size of the parent container (should be full screen due to anchors)
	var parent_size = player_indicators_parent.size
	var num_players = player_indicators.size() # Get actual number added

	print("Display: Positioning %d indicators within parent size %s" % [num_players, str(parent_size)])

	for i in range(1, num_players + 1):
		if player_indicators.has(i):
			var indicator_control = player_indicators[i] as Control
			if not is_instance_valid(indicator_control): continue

			# We need the indicator's size to offset it correctly from right/bottom edges
			# Ensure the PlayerIndicator scene's root Control has a size (e.g., from its PanelContainer child)
			var indicator_size = indicator_control.size
			if indicator_size == Vector2.ZERO:
				# Wait a frame if size is zero initially, might not be calculated yet
				await get_tree().process_frame
				indicator_size = indicator_control.size
				if indicator_size == Vector2.ZERO:
					# Attempt to get size from panel container if root is 0x0
					var panel = indicator_control.get_node_or_null("PanelContainer")
					if is_instance_valid(panel):
						indicator_size = panel.size

				if indicator_size == Vector2.ZERO:
					printerr("Display Warning: Indicator %d size is zero, cannot position accurately." % i)
					# Fallback or set a default size? For now, proceed with potentially bad positioning.

			match i:
				1: # Top-Left
					indicator_control.position = Vector2(INDICATOR_MARGIN, INDICATOR_MARGIN)
				2: # Top-Right
					indicator_control.position = Vector2(parent_size.x - indicator_size.x - INDICATOR_MARGIN, INDICATOR_MARGIN)
				3: # Bottom-Left
					indicator_control.position = Vector2(INDICATOR_MARGIN, parent_size.y - indicator_size.y - INDICATOR_MARGIN)
				4: # Bottom-Right
					indicator_control.position = Vector2(parent_size.x - indicator_size.x - INDICATOR_MARGIN, parent_size.y - indicator_size.y - INDICATOR_MARGIN)
				_: # Basic handling for more players (e.g., stack them top-left)
					indicator_control.position = Vector2(INDICATOR_MARGIN, INDICATOR_MARGIN + (i * (indicator_size.y + 5))) # Simple stacking

			print("  > Indicator %d positioned at %s (size: %s)" % [i, str(indicator_control.position), str(indicator_size)])


# --- UI Update Functions ---

# Updates energy bar visuals and status text based on global state
func _update_energy_display(level: float, is_running: bool, state_data: Dictionary):
	if not is_instance_valid(energy_level_text) or \
	   not is_instance_valid(energy_bar) or \
	   not is_instance_valid(status_text):
		printerr("DISPLAY ERROR: One or more UI nodes invalid INSIDE _update_energy_display!")
		return

	energy_level_text.text = "%d%%" % round(level)
	energy_bar.value = level

	# --- Declare variables ONCE here ---
	var fill_stylebox = energy_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat # Duplicate to modify
	var bg_stylebox = energy_bar.get_theme_stylebox("background").duplicate() as StyleBoxFlat # Duplicate background too
	var bar_color = Color.GRAY # Default color when not running or unknown state
	var status_message = "Waiting..." # Default status when not running
	# --- End of initial declarations ---

	if is_running:
		status_text.remove_theme_color_override("font_color") # Use default color
		var danger_low = state_data.get("dangerLow", Config.DANGER_LOW_THRESHOLD)
		var safe_min = state_data.get("safeZoneMin", Config.SAFE_ZONE_MIN)
		var safe_max = state_data.get("safeZoneMax", Config.SAFE_ZONE_MAX)
		var danger_high = state_data.get("dangerHigh", Config.DANGER_HIGH_THRESHOLD)

		# Determine bar_color based on energy level
		if level < danger_low:
			bar_color = Color.DARK_RED
			status_message = "DANGER! Meltdown Imminent!"
		elif level < safe_min:
			bar_color = Color.ORANGE
			status_message = "Warning: Low Power"
		elif level <= safe_max: # In safe zone
			bar_color = Color.LIME_GREEN
			status_message = "Stable"
		elif level < danger_high: # Warning high
			bar_color = Color.YELLOW
			status_message = "Warning: High Power"
		else: # level >= danger_high
			bar_color = Color.RED
			status_message = "DANGER! Overload Imminent!"

		status_text.text = status_message

	else: # Game not running
		bar_color = Color.GRAY
		var final_reason = state_data.get("finalOutcomeReason", "none")
		if final_reason == "none":
			# Game isn't running, but no final outcome yet (likely waiting/resetting)
			# Specific text is set by _on_game_over_triggered or _on_game_reset_triggered
			status_text.text = "Waiting..." # Fallback text
		# else: Keep existing Game Over / Resetting message

	# --- Apply modifications to the duplicated styleboxes ---
	# Use the 'fill_stylebox' variable declared at the top (NO 'var' here)
	if fill_stylebox:
		fill_stylebox.bg_color = bar_color
		energy_bar.add_theme_stylebox_override("fill", fill_stylebox)

	# Use the 'bg_stylebox' variable declared at the top (NO 'var' here)
	if bg_stylebox:
		bg_stylebox.bg_color = Color(0.2, 0.2, 0.2) if is_running else Color(0.1, 0.1, 0.1)
		energy_bar.add_theme_stylebox_override("background", bg_stylebox)

# Updates cooperative win progress text
func _update_coop_progress(progress_seconds: float, target_seconds: float, is_running: bool, outcome_reason: String, winner_id: int):
	if not is_instance_valid(coop_progress_text): return

	if target_seconds > 0:
		var safe_progress = floor(progress_seconds)
		var safe_target = floor(target_seconds)
		var progress_percent = min(100, floor((progress_seconds / target_seconds) * 100)) if target_seconds > 0 else 0

		if is_running:
			coop_progress_text.text = "Stability Goal: %ds / %ds (%d%%)" % [safe_progress, safe_target, progress_percent]
		elif outcome_reason == "coopWin":
			coop_progress_text.text = "Stability Goal: %ds / %ds (100%%) - SUCCESS!" % [safe_target, safe_target]
		elif not is_running and outcome_reason != "none":
			# Game is over, show final outcome instead of progress
			var outcome_text = "Final Status: %s" % outcome_reason.capitalize()
			if outcome_reason == "individualWin":
				outcome_text = "Individual Win: Player %d" % winner_id
			elif outcome_reason == "shutdown":
				outcome_text = "Final Status: Grid Shutdown"
			elif outcome_reason == "meltdown":
				outcome_text = "Final Status: Grid Meltdown"
			coop_progress_text.text = outcome_text
		else: # Waiting or just reset
			coop_progress_text.text = "Stability Goal: 0s / %ds (0%%)" % safe_target
	else:
		coop_progress_text.text = "Stability Goal: Waiting..."

# Placeholder for stabilize effect update (e.g., visual feedback on main display)
func _on_stabilize_effect_updated(stabilize_data: Dictionary):
	var is_active = stabilize_data.get("active", false)
	# Example: Change border color of the main display or energy bar background
	if is_active:
		if is_instance_valid(energy_bar): energy_bar.modulate = Color(0.8, 1.0, 0.8, 1.0) # Slight green tint?
	else:
		if is_instance_valid(energy_bar): energy_bar.modulate = Color(1.0, 1.0, 1.0, 1.0) # Normal


# --- Signal Handlers ---

# Handles GLOBAL game state updates from GameManager
func _on_game_state_updated(state_data: Dictionary):
	# print("Display: Received game_state_updated") # DEBUG
	last_global_state = state_data # Store for use in player updates

	# Update global display elements based on the received state
	_update_energy_display(state_data.get("energyLevel", 50.0), state_data.get("gameIsRunning", false), state_data)
	_update_coop_progress(
		state_data.get("coopWinProgressSeconds", 0.0),
		state_data.get("coopWinTargetSeconds", Config.COOP_WIN_DURATION_SECONDS),
		state_data.get("gameIsRunning", false),
		state_data.get("finalOutcomeReason", "none"), # Use final outcome from state if available
		state_data.get("finalOutcomeWinner", 0)
	)

	# Refresh ALL player indicators based on the new global state
	# This ensures their 'is_game_running' status and button enabled states are correct.
	# Individual data like stash/cooldowns comes via _on_player_state_updated.
	for pid in player_indicators:
		var indicator = player_indicators.get(pid) # Use .get() for safety
		if is_instance_valid(indicator):
			# Pass an empty dictionary for player data, as this handler only has global state.
			# The indicator uses the global state's 'gameIsRunning' flag primarily here.
			# It will merge this with its own last known player data if needed.
			indicator.update_display({}, last_global_state)


# Handles INDIVIDUAL player state updates from GameManager
func _on_player_state_updated(player_id: int, player_state_data: Dictionary):
	# print("Display: Received player_state_updated for Player %d Stash: %.1f" % [player_id, player_state_data.get("personal_stash", -1.0)]) # DEBUG
	if player_indicators.has(player_id):
		var indicator = player_indicators[player_id]
		if is_instance_valid(indicator):
			# Pass both the specific player data and the last known global state
			# The indicator uses player_state_data for stash/cooldowns/status
			# and last_global_state for context like 'is_game_running' and targets.
			indicator.update_display(player_state_data, last_global_state)
		else:
			printerr("Display Warning: Indicator node for player %d is invalid!" % player_id)
	else:
		printerr("Display Warning: Received update for unknown player ID %d" % player_id)


# --- NEW: Handles Visual Feedback Signal ---
func _on_player_action_visual_feedback(player_id: int, action_name: String):
	# print("Display: Received visual feedback for P%d, Action: %s" % [player_id, action_name]) # DEBUG
	if player_indicators.has(player_id):
		var indicator = player_indicators[player_id]
		if is_instance_valid(indicator):
			indicator.flash_button(action_name)
		else:
			printerr("Display Warning: Indicator for player %d invalid during visual feedback." % player_id)
	else:
		printerr("Display Warning: Received visual feedback for unknown player ID %d" % player_id)
# --- END NEW ---


# Handles Game Over signal from GameManager
func _on_game_over_triggered(outcome_data: Dictionary):
	print("Display received Game Over: ", outcome_data)
	if not is_instance_valid(status_text): return

	status_text.add_theme_color_override("font_color", Color.YELLOW_GREEN if outcome_data.get("reason") == "coopWin" else Color.ORANGE_RED)
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

	# Update coop progress text one last time to show final status
	if is_instance_valid(game_manager): # Ensure game_manager is still valid
		# Use final state from game manager if possible, otherwise use outcome_data
		var final_progress = game_manager.cumulative_stable_time_s if is_instance_valid(game_manager) else 0.0
		_update_coop_progress(
			final_progress, Config.COOP_WIN_DURATION_SECONDS,
			false, # Game is not running
			reason, winner_id
		)
	else: # Fallback if game_manager is gone
		_update_coop_progress(0.0, Config.COOP_WIN_DURATION_SECONDS, false, reason, winner_id)


	if is_instance_valid(reset_button):
		reset_button.show()
	_update_event_alert(Config.EventType.NONE, 0) # Clear event alert

	# Update player indicators to reflect game over state (usually disabled)
	last_global_state["gameIsRunning"] = false # Ensure global state reflects game over
	for pid in player_indicators:
		var indicator = player_indicators.get(pid)
		if is_instance_valid(indicator):
			# Pass empty player data, let the indicator update based on gameIsRunning = false
			indicator.update_display({}, last_global_state)


# Handles Game Reset signal from GameManager
func _on_game_reset_triggered():
	print("Display received Game Reset.")
	if not is_instance_valid(status_text) or not is_instance_valid(coop_progress_text): return

	status_text.text = "Game Resetting..."
	status_text.remove_theme_color_override("font_color")
	coop_progress_text.text = "Stability Goal: Waiting..."
	if is_instance_valid(reset_button):
		reset_button.hide()
	_update_event_alert(Config.EventType.NONE, 0) # Clear event alert

	# Explicitly reset each player indicator to its initial state
	print("Display: Resetting player indicators.")
	for pid in player_indicators:
		var indicator = player_indicators.get(pid)
		if is_instance_valid(indicator):
			indicator.reset_indicator()


# Handles Event Update signal from GameManager
func _on_event_updated(event_data: Dictionary):
	# print("Display received Event Update: ", event_data) # DEBUG
	var event_type = event_data.get("type", Config.EventType.NONE)
	var end_time_ms = event_data.get("end_time_ms", 0)
	_update_event_alert(event_type, end_time_ms)

# --- Event Alert Helpers ---
func _update_event_alert(type: Config.EventType, end_time_ms: int):
	if not is_instance_valid(event_alert_label): return
	# Stop any existing timer first
	if not event_alert_timer.is_stopped(): event_alert_timer.stop()

	if type != Config.EventType.NONE:
		var event_text = "Unknown Event"; var alert_color = Color.YELLOW
		match type:
			Config.EventType.SURGE: event_text = "WARNING: Demand Surge!"; alert_color = Color.ORANGE_RED
			Config.EventType.EFFICIENCY: event_text = "NOTICE: Efficiency Drive!"; alert_color = Color.LIGHT_GREEN

		var time_left_ms = max(0, end_time_ms - Time.get_ticks_msec())
		var duration_s = time_left_ms / 1000.0

		if duration_s > 0.1: # Only show if more than a fraction of a second left
			event_alert_label.text = "%s (%ds left)" % [event_text, ceil(duration_s)]
			event_alert_label.add_theme_color_override("font_color", alert_color)
			event_alert_label.show()
			# Set timer to hide the label when the event duration ends
			event_alert_timer.wait_time = duration_s
			event_alert_timer.start()
		else:
			# Event already ended or too short to display
			event_alert_label.hide(); event_alert_label.remove_theme_color_override("font_color")
	else:
		# No active event
		event_alert_label.hide(); event_alert_label.remove_theme_color_override("font_color")

func _on_event_alert_timer_timeout():
	# Hide the label when the timer finishes
	if is_instance_valid(event_alert_label):
		event_alert_label.hide(); event_alert_label.remove_theme_color_override("font_color")
