# scripts/GameManager.gd
extends Node

# --- Signals ---
# Emitted every frame with the overall game state
signal game_state_updated(state_data: Dictionary)
# Emitted when the game ends
signal game_over_triggered(outcome_data: Dictionary)
# Emitted when the game resets
signal game_reset_triggered
# Emitted when a random event starts or ends
signal event_updated(event_data: Dictionary)
# Emitted when the global stabilize effect starts or ends
signal stabilize_effect_updated(stabilize_data: Dictionary)
# Emitted when a specific player's state (stash, cooldowns, status) changes
signal player_state_updated(player_id: int, player_state_data: Dictionary)
# NEW: Emitted purely for visual feedback on the Display indicator when an action is attempted
signal player_action_visual_feedback(player_id: int, action_name: String)


# --- Constants ---
const NUM_PLAYERS = 4 # Define how many local players you expect

# --- State Variables ---
var energy_level: float = Config.SAFE_ZONE_MIN + (Config.SAFE_ZONE_MAX - Config.SAFE_ZONE_MIN) / 2.0
var players: Dictionary = {} # Stores PlayerState for each player_id (1 to NUM_PLAYERS)
var cumulative_stable_time_s: float = 0.0
var continuous_time_in_danger_low_s: float = 0.0
var continuous_time_in_danger_high_s: float = 0.0
var game_is_running: bool = false
var final_game_outcome: Dictionary = {"reason": "none", "winner_id": 0}
var stabilize_effect_end_time_ms: int = 0
var active_event: Dictionary = {"type": Config.EventType.NONE, "end_time_ms": 0}

@onready var event_check_timer: Timer = $EventCheckTimer
@onready var event_duration_timer: Timer = $EventDurationTimer

# Reference to UdpManager (assuming autoload)
@onready var udp_manager = get_node("/root/UdpManager")

const PlayerState = preload("res://scripts/Player.gd")

func _ready():
	print("!!!!! GAMEMANAGER _ready() STARTED !!!!!")
	print("GameManager: _ready() Initializing for Local Play (UDP)")

	# Connect to UdpManager Signal
	if udp_manager == null:
		printerr("GameManager Error: UdpManager node not found! Input disabled.")
		set_process(false)
		set_physics_process(false)
		return
	else:
		# Check if already connected to prevent duplicates if scene reloads
		if not udp_manager.player_action_received.is_connected(_on_player_action_received):
			var err = udp_manager.player_action_received.connect(_on_player_action_received)
			if err != OK: printerr("GameManager ERROR: Failed to connect UdpManager signal! Error: %s" % err)
		# Add check if manager exists but isn't listening
		elif not udp_manager.is_listening:
			printerr("GameManager Error: UdpManager is not listening! Input disabled.")
			set_process(false)
			set_physics_process(false)
			return

	# Connect Timer Signals
	if not event_check_timer.timeout.is_connected(_on_event_check_timer_timeout):
		event_check_timer.timeout.connect(_on_event_check_timer_timeout)
	if not event_duration_timer.timeout.is_connected(_on_event_duration_timer_timeout):
		event_duration_timer.timeout.connect(_on_event_duration_timer_timeout)

	event_check_timer.wait_time = Config.EVENT_CHECK_INTERVAL_MS / 1000.0
	event_duration_timer.one_shot = true

	print("GameManager: Creating player states...")
	# Initialize Players
	for i in range(1, NUM_PLAYERS + 1):
		_add_player(i)

	print("GameManager: Starting game logic.")
	call_deferred("start_game") # Defer start slightly to ensure Display is ready
	print("GameManager: _ready() FINISHED")

func _exit_tree():
	# Disconnect UdpManager signal
	if udp_manager != null and udp_manager.player_action_received.is_connected(_on_player_action_received):
		udp_manager.player_action_received.disconnect(_on_player_action_received)

func _add_player(id: int):
	if not players.has(id):
		print("GameManager: Adding player state for ID:", id)
		players[id] = PlayerState.new(id)
	else:
		players[id].reset() # Reset existing player state if re-adding

func start_game():
	print("<<<<<< GAMEMANAGER DEBUG: start_game() called >>>>>>")
	_reset_game_state() # Resets global state AND player states
	game_is_running = true
	event_check_timer.start()
	# Emit initial global state via signals for Display
	print("<<<<<< GAMEMANAGER DEBUG: Emitting initial full state from start_game() >>>>>>")
	_emit_full_game_state() # This calls _emit_game_state_update internally
	# Emit initial state for each player indicator AFTER global state is set
	for player_id in players:
		_emit_player_state_update(player_id) # Send initial player state
	print("GameManager: Game running.")

func _reset_game_state():
	energy_level = Config.SAFE_ZONE_MIN + (Config.SAFE_ZONE_MAX - Config.SAFE_ZONE_MIN) / 2.0
	cumulative_stable_time_s = 0.0
	continuous_time_in_danger_low_s = 0.0
	continuous_time_in_danger_high_s = 0.0
	game_is_running = false # Set to false initially, start_game sets to true
	final_game_outcome = {"reason": "none", "winner_id": 0}
	stabilize_effect_end_time_ms = 0
	active_event = {"type": Config.EventType.NONE, "end_time_ms": 0}
	event_check_timer.stop()
	event_duration_timer.stop()
	# Reset all managed player states
	for player_id in players:
		if players.has(player_id) and players[player_id]:
			players[player_id].reset()
	# Signal reset to Display (Display handles resetting indicators visually)
	emit_signal("game_reset_triggered")

func _process(delta: float):
	if not game_is_running:
		return

	var now_ms = Time.get_ticks_msec()

	# --- Energy Decay Logic ---
	var current_decay_rate = Config.BASE_ENERGY_DECAY_RATE
	var stabilize_active = stabilize_effect_end_time_ms > now_ms
	# Check if stabilize effect just ended
	var was_stabilize_active = stabilize_active
	if stabilize_active and now_ms >= stabilize_effect_end_time_ms:
		stabilize_effect_end_time_ms = 0
		stabilize_active = false
		if was_stabilize_active:
			_emit_stabilize_state() # Signal this specific change

	if stabilize_active:
		current_decay_rate *= Config.STABILIZE_DECAY_MULTIPLIER
	elif active_event.type == Config.EventType.SURGE and active_event.end_time_ms > now_ms:
		current_decay_rate *= Config.EVENT_SURGE_DECAY_MULTIPLIER

	energy_level -= current_decay_rate * delta
	energy_level = clampf(energy_level, Config.MIN_ENERGY, Config.MAX_ENERGY)

	# --- Time Tracking & Win/Loss Conditions ---
	var in_safe_zone = energy_level >= Config.SAFE_ZONE_MIN and energy_level <= Config.SAFE_ZONE_MAX
	var in_danger_low = energy_level < Config.DANGER_LOW_THRESHOLD
	var in_danger_high = energy_level > Config.DANGER_HIGH_THRESHOLD

	if in_safe_zone:
		cumulative_stable_time_s += delta
		continuous_time_in_danger_low_s = 0.0
		continuous_time_in_danger_high_s = 0.0
	elif in_danger_low:
		continuous_time_in_danger_low_s += delta
		continuous_time_in_danger_high_s = 0.0
	elif in_danger_high:
		continuous_time_in_danger_high_s += delta
		continuous_time_in_danger_low_s = 0.0
	else: # Between danger low and safe min, or between safe max and danger high
		continuous_time_in_danger_low_s = 0.0
		continuous_time_in_danger_high_s = 0.0

	# --- Check Game Over Conditions ---
	var game_over_reason = "none"
	var winner_id = 0
	if cumulative_stable_time_s >= Config.COOP_WIN_DURATION_SECONDS:
		game_over_reason = "coopWin"
	elif continuous_time_in_danger_low_s >= Config.DANGER_TIME_LIMIT_SECONDS:
		game_over_reason = "shutdown"
	elif continuous_time_in_danger_high_s >= Config.DANGER_TIME_LIMIT_SECONDS:
		game_over_reason = "meltdown"
	# Individual win condition is checked within _handle_player_action_stealGrid

	if game_over_reason != "none":
		_trigger_game_over(game_over_reason, winner_id)
		return # Stop processing after game over

	# --- Emit global state update EVERY frame ---
	_emit_game_state_update()

# --- Signal Emitter Helpers ---

func _emit_game_state_update():
	# Emits the global state snapshot
	emit_signal("game_state_updated", _get_current_state_snapshot())

# Emits an update for a specific player's state
func _emit_player_state_update(player_id: int):
	if players.has(player_id) and is_instance_valid(players[player_id]):
		var player_state: PlayerState = players[player_id]
		var state_data = player_state.get_state_data()
		emit_signal("player_state_updated", player_id, state_data)
		# Clear temporary status after sending it so it's only sent once
		player_state.clear_temp_status()
	else:
		printerr("GameManager Error: Tried to emit update for invalid player ID or state: %d" % player_id)


func _emit_event_state():
	# Emits the current event state
	emit_signal("event_updated", active_event)

func _emit_stabilize_state():
	# Emits the global stabilize effect state
	var data = {
		"active": stabilize_effect_end_time_ms > Time.get_ticks_msec(),
		"end_time_ms": stabilize_effect_end_time_ms
	}
	emit_signal("stabilize_effect_updated", data)

# Call this to send the full state, e.g., at game start or after reset if needed
func _emit_full_game_state():
	_emit_game_state_update() # Global state
	_emit_event_state()       # Current event
	_emit_stabilize_state()   # Current stabilize effect
	# Note: Initial player states are emitted separately in start_game

# Creates a dictionary representing the current global game state
func _get_current_state_snapshot() -> Dictionary:
	var all_player_ids = players.keys()
	all_player_ids.sort()

	return {
		"energyLevel": energy_level,
		"playerIds": all_player_ids,
		"playerCount": all_player_ids.size(),
		"coopWinTargetSeconds": Config.COOP_WIN_DURATION_SECONDS,
		"coopWinProgressSeconds": cumulative_stable_time_s,
		"gameIsRunning": game_is_running,
		"finalOutcomeReason": final_game_outcome.reason,
		"finalOutcomeWinner": final_game_outcome.winner_id,
		"stashWinTarget": Config.STASH_WIN_TARGET,
		"playerStashes": _get_all_player_stashes(), # Include for convenience if needed
		"safeZoneMin": Config.SAFE_ZONE_MIN,
		"safeZoneMax": Config.SAFE_ZONE_MAX,
		"dangerLow": Config.DANGER_LOW_THRESHOLD,
		"dangerHigh": Config.DANGER_HIGH_THRESHOLD,
		"dangerLowProgressSeconds": continuous_time_in_danger_low_s,
		"dangerHighProgressSeconds": continuous_time_in_danger_high_s,
		"dangerTimeLimitSeconds": Config.DANGER_TIME_LIMIT_SECONDS,
	}

# Helper to get all player stashes for the snapshot
func _get_all_player_stashes() -> Dictionary:
	var stashes = {}
	for pid in players:
		if players.has(pid) and is_instance_valid(players[pid]):
			stashes[pid] = players[pid].personal_stash
	return stashes

# --- Event Timers ---
func _on_event_check_timer_timeout():
	if not game_is_running or active_event.type != Config.EventType.NONE: return
	# Only trigger event if stabilize is not active
	if stabilize_effect_end_time_ms > Time.get_ticks_msec(): return

	if randf() * 100.0 <= Config.EVENT_CHANCE_PERCENT:
		var chosen_type_index = randi() % Config.EVENT_TYPES.size()
		var chosen_type = Config.EVENT_TYPES[chosen_type_index]
		var now_ms = Time.get_ticks_msec()
		active_event = {"type": chosen_type, "end_time_ms": now_ms + Config.EVENT_DURATION_MS}
		event_duration_timer.wait_time = Config.EVENT_DURATION_MS / 1000.0
		event_duration_timer.start()
		print("--- EVENT TRIGGERED: ", Config.EventType.keys()[chosen_type], " ---")
		_emit_event_state() # Signal the update
		# A full global state update will happen on the next _process frame anyway

func _on_event_duration_timer_timeout():
	if active_event.type != Config.EventType.NONE:
		print("--- EVENT ENDED: ", Config.EventType.keys()[active_event.type], " ---")
		active_event = {"type": Config.EventType.NONE, "end_time_ms": 0}
		_emit_event_state() # Signal the update
		# A full global state update will happen on the next _process frame anyway

# --- Game Over ---
func _trigger_game_over(reason: String, winner: int = 0):
	if not game_is_running: return # Prevent multiple triggers
	print("!!! GAME OVER: Reason=%s, Winner=%d !!!" % [reason, winner])
	game_is_running = false
	final_game_outcome = {"reason": reason, "winner_id": winner}

	# Stop timers and events
	event_check_timer.stop()
	event_duration_timer.stop()
	if active_event.type != Config.EventType.NONE:
		active_event = {"type": Config.EventType.NONE, "end_time_ms": 0}
		_emit_event_state() # Signal event ended

	# Emit the final game over signal
	emit_signal("game_over_triggered", final_game_outcome)
	# Also emit one last global state update containing the final outcome info
	_emit_game_state_update()

# --- Player Action Handling ---

# This function is connected to the UdpManager's signal
func _on_player_action_received(player_id: int, action: String):
	# --- Basic Validation ---
	if player_id <= 0 or player_id > NUM_PLAYERS:
		printerr("GameManager: Received action '%s' from invalid player ID %d." % [action, player_id])
		return

	if not players.has(player_id) or not is_instance_valid(players[player_id]):
		printerr("GameManager: No state found for player ID %d. Action '%s' ignored." % [action, player_id])
		# Attempt to create player state if missing dynamically? Could cause issues.
		# _add_player(player_id)
		return

	# --- NEW: Emit Visual Feedback Signal FIRST ---
	# We emit this regardless of game state or cooldowns to show the button was pressed
	emit_signal("player_action_visual_feedback", player_id, action)

	# --- Game State / Action Routing ---
	if not game_is_running:
		print("GameManager: Action '%s' from player %d ignored (game not running)." % [action, player_id])
		# Provide feedback that game isn't running (optional, the visual flash already happened)
		# players[player_id].set_temp_status("Game Ended")
		# _emit_player_state_update(player_id) # Could update status label on indicator
		return

	# Route to the specific action handler
	match action:
		"generate":
			_handle_player_action_generate(player_id)
		"stabilize":
			_handle_player_action_stabilize(player_id)
		"stealGrid":
			_handle_player_action_stealGrid(player_id)
		"emergencyAdjust":
			_handle_player_action_emergencyAdjust(player_id)
		_:
			printerr("GameManager: Received unknown action '%s' from player %d." % [action, player_id])
			players[player_id].set_temp_status("Unknown Cmd")
			_emit_player_state_update(player_id) # Send feedback for unknown command


# --- Specific Action Handlers (Emit player_state_updated when player state changes) ---

func _handle_player_action_generate(player_id: int):
	# No player state changes needed here, just update global energy
	var player_state: PlayerState = players[player_id] # Get state for context if needed later
	var now_ms = Time.get_ticks_msec()
	var current_gain = Config.BASE_ENERGY_GAIN_PER_CLICK

	var stabilize_active = stabilize_effect_end_time_ms > now_ms
	var event_efficiency_active = active_event.type == Config.EventType.EFFICIENCY and active_event.end_time_ms > now_ms

	if stabilize_active:
		current_gain *= Config.STABILIZE_GAIN_MULTIPLIER
	elif event_efficiency_active:
		current_gain *= Config.EVENT_EFFICIENCY_GAIN_MULTIPLIER

	energy_level = clampf(energy_level + current_gain, Config.MIN_ENERGY, Config.MAX_ENERGY)
	# No change to this player's specific state (stash/cooldowns), so no _emit_player_state_update needed.
	# Global energy level change will be emitted via game_state_updated in _process.

func _handle_player_action_stabilize(player_id: int):
	var player_state: PlayerState = players[player_id]
	var now_ms = Time.get_ticks_msec()

	if now_ms >= player_state.stabilize_cooldown_end_ms:
		# Action Success
		stabilize_effect_end_time_ms = now_ms + Config.STABILIZE_DURATION_MS
		player_state.stabilize_cooldown_end_ms = now_ms + Config.STABILIZE_COOLDOWN_MS
		player_state.set_temp_status("Stabilized!") # Set feedback message
		print("GameManager: Player %d triggered Stabilize." % player_id)
		_emit_stabilize_state() # Emit global stabilize effect change
		_emit_player_state_update(player_id) # Emit player state change (cooldown + status)
	else:
		# Action Failed (Cooldown)
		player_state.set_temp_status("Stabilize CD") # Set feedback message
		print("GameManager: Player %d failed Stabilize (cooldown)." % player_id)
		_emit_player_state_update(player_id) # Emit player state change (just status)

func _handle_player_action_stealGrid(player_id: int):
	var player_state: PlayerState = players[player_id]
	var now_ms = Time.get_ticks_msec()

	if now_ms < player_state.steal_grid_cooldown_end_ms:
		# Action Failed (Cooldown)
		player_state.set_temp_status("Steal CD")
		print("GameManager: Player %d failed Steal Grid (cooldown)." % player_id)
		_emit_player_state_update(player_id)
		return

	if energy_level < Config.STEAL_GRID_COST:
		# Action Failed (Low Grid Energy)
		player_state.set_temp_status("Low Grid!")
		print("GameManager: Player %d failed Steal Grid (low grid energy)." % player_id)
		_emit_player_state_update(player_id)
		return

	# Action Success
	energy_level = max(Config.MIN_ENERGY, energy_level - Config.STEAL_GRID_COST)
	player_state.personal_stash += Config.STEAL_STASH_GAIN # <-- STASH IS UPDATED HERE
	player_state.steal_grid_cooldown_end_ms = now_ms + Config.STEAL_COOLDOWN_MS
	player_state.set_temp_status("Stole %.1f" % Config.STEAL_STASH_GAIN)
	print("GameManager: Player %d stole from grid. Stash: %.1f" % [player_id, player_state.personal_stash])
	_emit_player_state_update(player_id) # <-- EMITS UPDATED STATE (INCLUDING STASH)

	# Check for individual win condition
	if player_state.personal_stash >= Config.STASH_WIN_TARGET:
		print("--- INDIVIDUAL WIN: Triggered by Player ", player_id, " ---")
		_trigger_game_over("individualWin", player_id)
		# Game over handles final state emission.

func _handle_player_action_emergencyAdjust(player_id: int):
	var player_state: PlayerState = players[player_id]
	var now_ms = Time.get_ticks_msec()

	if now_ms < player_state.emergency_adjust_cooldown_end_ms:
		# Action Failed (Cooldown)
		player_state.set_temp_status("Emergency CD")
		print("GameManager: Player %d failed Emergency Adjust (cooldown)." % player_id)
		_emit_player_state_update(player_id)
		return

	var energy_change: float = 0.0
	var misused = false
	var feedback_msg = ""

	if energy_level < Config.DANGER_LOW_THRESHOLD:
		# Use Boost
		energy_change = Config.EMERGENCY_BOOST_AMOUNT
		feedback_msg = "Boost Used!"
		print("GameManager: Player %d used Emergency Boost." % player_id)
	elif energy_level > Config.DANGER_HIGH_THRESHOLD:
		# Use Coolant
		energy_change = -Config.EMERGENCY_COOLANT_AMOUNT
		feedback_msg = "Coolant Used!"
		print("GameManager: Player %d used Emergency Coolant." % player_id)
	else:
		# Misused (in safe or warning zone)
		misused = true
		feedback_msg = "Misused!"
		# Apply penalty
		if energy_level < (Config.SAFE_ZONE_MIN + Config.SAFE_ZONE_MAX) / 2.0:
			energy_change = -Config.EMERGENCY_PENALTY_WRONG_ZONE # Penalty pushes further away
		else:
			energy_change = Config.EMERGENCY_PENALTY_WRONG_ZONE # Penalty pushes further away
		print("GameManager: Player %d misused Emergency Adjust (penalty: %.1f)." % [player_id, energy_change])

	# Apply energy change and cooldown regardless of success/misuse
	energy_level = clampf(energy_level + energy_change, Config.MIN_ENERGY, Config.MAX_ENERGY)
	player_state.emergency_adjust_cooldown_end_ms = now_ms + Config.EMERGENCY_ADJUST_COOLDOWN_MS
	player_state.set_temp_status(feedback_msg) # Set feedback message
	_emit_player_state_update(player_id) # Emit player state change (cooldown, status)
	# Global energy change emitted next frame by _process

# --- Reset Request Handling ---
# Connected from Display's Reset Button
func handle_reset_request():
	if not game_is_running:
		print("GameManager: Reset approved.")
		start_game() # This handles reset and emits initial states
	else:
		print("GameManager: Reset denied, game still running.")
