extends Control

# --- UI Node References ---
@onready var generate_button: Button = $VBoxContainer/GenerateButton
@onready var stabilize_button: Button = $VBoxContainer/StabilizeButton
@onready var emergency_button: Button = $VBoxContainer/EmergencyButton
@onready var steal_grid_button: Button = $VBoxContainer/StealGridButton
@onready var status_text: Label = $VBoxContainer/StatusText
@onready var stash_amount_text: Label = $VBoxContainer/StashDisplay/StashAmount
@onready var stash_target_text: Label = $VBoxContainer/StashDisplay/StashTarget

# --- Cooldown State ---
var cooldown_timers: Dictionary = {
	"stabilize": {"button": null, "end_time_ms": 0, "timer_node": Timer.new()},
	"emergencyAdjust": {"button": null, "end_time_ms": 0, "timer_node": Timer.new()},
	"stealGrid": {"button": null, "end_time_ms": 0, "timer_node": Timer.new()},
}
var is_game_running: bool = false
var status_message_timer: Timer = Timer.new() # For temporary messages (fail/misuse)

func _ready():
	# Assign buttons to state
	cooldown_timers["stabilize"]["button"] = stabilize_button
	cooldown_timers["emergencyAdjust"]["button"] = emergency_button
	cooldown_timers["stealGrid"]["button"] = steal_grid_button

	# Setup timers
	for action in cooldown_timers:
		var timer = cooldown_timers[action]["timer_node"]
		timer.name = action + "CooldownTimer" # Optional: Name for debugging
		add_child(timer)
		timer.timeout.connect(_update_cooldown_display.bind(action)) # Bind action name
		# Don't set wait_time here, set dynamically or just check time in _process

	add_child(status_message_timer)
	status_message_timer.one_shot = true
	status_message_timer.wait_time = 2.0 # 2 seconds for temporary messages
	status_message_timer.timeout.connect(_clear_temporary_status_message)

	# Connect button signals
	generate_button.pressed.connect(_on_generate_pressed)
	stabilize_button.pressed.connect(_on_action_pressed.bind("stabilize"))
	emergency_button.pressed.connect(_on_action_pressed.bind("emergencyAdjust"))
	steal_grid_button.pressed.connect(_on_action_pressed.bind("stealGrid"))

	# Initial UI state
	set_buttons_interactable(false)
	status_text.text = "Connecting..."
	stash_target_text.text = "??"

	# Connect to network signals if needed (e.g., disconnected from server)
	NetworkManager.connection_failed.connect(_on_disconnected) # If server disconnects or initial join fails
	# NetworkManager.connection_succeeded signal handled by scene transition usually

func _process(_delta):
	# Update cooldown text continuously if timer based approach is insufficient
	for action in cooldown_timers:
		var state = cooldown_timers[action]
		if state.end_time_ms > 0: # If a cooldown is set
			_update_cooldown_display(action)


func set_buttons_interactable(enabled: bool):
	is_game_running = enabled
	generate_button.disabled = not enabled

	# Special actions depend on both game running AND cooldown
	for action in cooldown_timers:
		var state = cooldown_timers[action]
		var is_on_cooldown = state.end_time_ms > Time.get_ticks_msec()
		state.button.disabled = not enabled or is_on_cooldown

	if not enabled and status_message_timer.is_stopped(): # Only update if no temp msg
		status_text.text = "Game Over / Waiting"


# --- Button Press Handlers ---

func _on_generate_pressed():
	# Send RPC to server (GameManager)
	if not generate_button.disabled:
		rpc_id(1, "rpc_player_action_generate") # Target host (ID 1)

func _on_action_pressed(action_name: String):
	var button = cooldown_timers[action_name]["button"]
	if not button.disabled:
		# Disable immediately for visual feedback
		button.disabled = true
		# Send RPC to server
		var rpc_func_name = "rpc_player_action_" + action_name
		if has_method(rpc_func_name): # Basic check, assumes method exists on target
			rpc_id(1, rpc_func_name)
		else:
			printerr("RPC function not found for action: ", action_name)
			# Re-enable button if RPC call failed conceptually? Or wait for server confirmation.
			# Let server handle failure feedback for now.

# --- Cooldown Management ---

func _start_cooldown(action: String, end_time_ms: int):
	if not cooldown_timers.has(action): return

	var state = cooldown_timers[action]
	state.end_time_ms = end_time_ms

	if end_time_ms > Time.get_ticks_msec():
		state.button.disabled = true
		_update_cooldown_display(action) # Initial update
		# Start the visual update timer (or rely on _process)
		# state.timer_node.start(0.5) # Example: update display every 0.5s
	else: # Cooldown is 0 or already passed (e.g., reset)
		state.end_time_ms = 0
		state.button.disabled = not is_game_running # Enable if game is running
		_update_cooldown_display(action) # Clear text
		# state.timer_node.stop()

func _update_cooldown_display(action: String):
	if not cooldown_timers.has(action): return

	var state = cooldown_timers[action]
	var button = state.button
	var end_time_ms = state.end_time_ms
	var original_text = "" # Get base text from button property or store it

	# Find the base text if needed (better to store it)
	match action:
		"stabilize": original_text = "Stabilize Burst"
		"emergencyAdjust": original_text = "Emergency Adjust"
		"stealGrid": original_text = "Divert Power"

	if end_time_ms <= 0: # No active cooldown
		button.text = original_text
		button.disabled = not is_game_running # Respect game running state
		# state.timer_node.stop() # Stop timer if using timed updates
		return

	var now_ms = Time.get_ticks_msec()
	var time_left_ms = end_time_ms - now_ms

	if time_left_ms <= 0:
		# Cooldown finished
		state.end_time_ms = 0 # Clear the end time
		button.text = original_text
		button.disabled = not is_game_running # Enable if game running
		# state.timer_node.stop()
		# Update status text if this was the last active cooldown
		_check_and_update_ready_status()

	else:
		# Cooldown active
		var seconds_left = ceil(time_left_ms / 1000.0)
		button.text = "%s (%ds)" % [original_text, seconds_left]
		button.disabled = true # Ensure it's disabled


# --- Status Text Management ---
func _show_temporary_status_message(message: String):
	status_text.text = message
	status_message_timer.start() # Will call _clear_temporary_status_message on timeout

func _clear_temporary_status_message():
	# Check if game is running or over and update status accordingly
	_check_and_update_ready_status()


func _check_and_update_ready_status():
	# Only update if no temporary message is scheduled
	if status_message_timer.is_stopped():
		if is_game_running:
			# Check if any cooldown is active
			var any_cooldown_active = false
			for action in cooldown_timers:
				if cooldown_timers[action].end_time_ms > Time.get_ticks_msec():
					any_cooldown_active = true
					break # Found one, no need to check more
			if not any_cooldown_active:
				status_text.text = "Connected - Ready"
			# Else: Cooldown display logic should update status text if needed
		else:
			status_text.text = "Game Over / Waiting"


# --- RPC Functions Called BY Host ---

@rpc("authority", "call_remote")
func rpc_receive_game_state_update(state_data: Dictionary):
	# Update interactability based on game running state
	set_buttons_interactable(state_data.gameIsRunning)

	# Update stash target display
	if state_data.has("stashWinTarget"):
		stash_target_text.text = str(state_data.stashWinTarget)

	# Update status text if needed (e.g., when game starts/stops)
	_check_and_update_ready_status()


@rpc("authority", "call_remote")
func rpc_receive_action_cooldown(cooldown_data: Dictionary):
	# print("Controller received cooldown: ", cooldown_data) # Debug
	if cooldown_data.has("action") and cooldown_data.has("cooldown_end_time_ms"):
		_start_cooldown(cooldown_data.action, cooldown_data.cooldown_end_time_ms)

@rpc("authority", "call_remote")
func rpc_receive_personal_stash_update(stash_data: Dictionary):
	# print("Controller received stash update: ", stash_data) # Debug
	if stash_data.has("personal_stash"):
		stash_amount_text.text = str(stash_data.personal_stash)

@rpc("authority", "call_remote")
func rpc_receive_action_failed(fail_data: Dictionary):
	print("Controller received action failed: ", fail_data)
	var reason = fail_data.get("reason", "Unknown reason")
	var message = ""
	if reason == "Used in wrong zone!":
		message = "Misused!"
	elif reason == "cooldown":
		# Cooldown message is implicitly handled by the cooldown display
		# Don't show a separate "Failed: cooldown" message
		return
	else:
		message = "Failed: %s" % reason

	_show_temporary_status_message(message)

@rpc("authority", "call_remote")
func rpc_receive_game_over(outcome_data: Dictionary):
	print("Controller received Game Over: ", outcome_data)
	set_buttons_interactable(false)
	status_text.text = "Game Over: %s" % outcome_data.reason
	# Clear any active cooldown displays visually
	for action in cooldown_timers:
		_start_cooldown(action, 0) # Reset cooldown state

@rpc("authority", "call_remote")
func rpc_receive_game_reset():
	print("Controller received Game Reset.")
	status_text.text = "Game Resetting..."
	stash_amount_text.text = "0"
	stash_target_text.text = "??" # Might get updated by initial state
	set_buttons_interactable(false) # Wait for game start signal/state
	# Clear any active cooldown displays visually
	for action in cooldown_timers:
		_start_cooldown(action, 0)

@rpc("authority", "call_remote")
func rpc_receive_game_start():
	print("Controller received Game Start.")
	is_game_running = true
	set_buttons_interactable(true) # Enable buttons respecting cooldowns
	_check_and_update_ready_status()


@rpc("authority", "call_remote")
func rpc_receive_initial_state(state_data: Dictionary):
	print("Controller received initial state.")
	# Apply initial state, similar to gameStateUpdate but maybe more comprehensive
	is_game_running = state_data.get("gameIsRunning", false)
	set_buttons_interactable(is_game_running)
	if state_data.has("stashWinTarget"):
		stash_target_text.text = str(state_data.stashWinTarget)
	 # Assume cooldowns/stash will be sent separately if needed on connect

# --- Network Handling ---
func _on_disconnected():
	status_text.text = "Disconnected"
	set_buttons_interactable(false)
	# Potentially transition back to Main Menu
	# get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# Note: Event and Stabilize updates are not explicitly handled here,
# as they don't directly affect the controller UI in the original design.
# If visual feedback is desired (e.g., button glows), add receivers for those RPCs too.
