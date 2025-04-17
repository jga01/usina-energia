# scripts/GameManager.gd
extends Node

# Signals for the local Display UI (on host)
signal game_state_updated(state_data: Dictionary)
signal game_over_triggered(outcome_data: Dictionary)
signal game_reset_triggered
signal event_updated(event_data: Dictionary)
signal stabilize_effect_updated(stabilize_data: Dictionary)

# Signals for specific player feedback (sent via RPC to a specific controller)
# These are emitted locally on the host but correspond to RPC calls made to clients.
# Useful if the host *also* needs to react to these events locally (e.g., debug UI).
signal action_failed(peer_id: int, fail_data: Dictionary)
signal action_cooldown_update(peer_id: int, cooldown_data: Dictionary)
signal personal_stash_update(peer_id: int, stash_data: Dictionary)

# --- Game State Variables (Authoritative) ---
var energy_level: float = Config.SAFE_ZONE_MIN + (Config.SAFE_ZONE_MAX - Config.SAFE_ZONE_MIN) / 2.0 # Start mid-safe zone
var players: Dictionary = {} # Key: peer_id, Value: PlayerState object
var cumulative_stable_time_s: float = 0.0
var continuous_time_in_danger_low_s: float = 0.0
var continuous_time_in_danger_high_s: float = 0.0
var game_is_running: bool = false # Start paused until explicitly started
var final_game_outcome: Dictionary = {"reason": "none", "winner_id": 0}
var stabilize_effect_end_time_ms: int = 0 # Global effect end time (using Time.get_ticks_msec())
var active_event: Dictionary = {"type": Config.EventType.NONE, "end_time_ms": 0}

# --- Child Node References (Set these up in the Scene Tree Editor) ---
# These timers are children of the GameManager node in Display.tscn
@onready var event_check_timer: Timer = $EventCheckTimer
@onready var event_duration_timer: Timer = $EventDurationTimer

# Preload PlayerState class if using GDScript class_name
const PlayerState = preload("res://scripts/Player.gd") # Adjust path if needed


func _ready():
	# CRITICAL: Only the host should run the game logic
	if not multiplayer.is_server():
		# Disable processing and timers if this instance is not the server
		set_process(false)
		set_physics_process(false)
		if event_check_timer: event_check_timer.stop()
		if event_duration_timer: event_duration_timer.stop()
		print("GameManager initialized on Client - Logic Disabled.")
		return # Stop initialization here for clients

	# --- Host Only Initialization ---
	print("GameManager ready on Host.")
	# Connect signals from NetworkManager to handle player joins/leaves
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	# Connect timer signals
	event_check_timer.timeout.connect(_on_event_check_timer_timeout)
	event_duration_timer.timeout.connect(_on_event_duration_timer_timeout)

	# Set up timer intervals from Config
	event_check_timer.wait_time = Config.EVENT_CHECK_INTERVAL_MS / 1000.0
	event_duration_timer.one_shot = true # Only fires once per event duration

	# Add the host player state
	_add_player(1) # Host always has ID 1

	# Don't start game immediately, wait for UI trigger or auto-start logic
	# start_game() # Example: Call this from Display.gd or after a delay
	# Let's assume the game starts when the host scene loads for simplicity now.
	start_game()

func start_game():
	if game_is_running and multiplayer.is_server():
		print("Host: Game already running.")
		return # Don't restart if already running
	if not multiplayer.is_server(): return # Only host starts

	print("Host: Starting game...")
	_reset_game_state() # Ensure clean state before starting/restarting
	game_is_running = true
	event_check_timer.start()

	# Tell all connected clients the game has started
	rpc("rpc_receive_game_start") # RPC to all clients

	# Broadcast initial state data
	_broadcast_game_state()
	_broadcast_event_state()
	_broadcast_stabilize_state()
	_broadcast_all_player_states() # Send initial cooldowns/stash
	print("Host: Game running.")

func _reset_game_state():
	if not multiplayer.is_server(): return # Only host resets
	print("Host: Resetting game state...")
	energy_level = Config.SAFE_ZONE_MIN + (Config.SAFE_ZONE_MAX - Config.SAFE_ZONE_MIN) / 2.0
	cumulative_stable_time_s = 0.0
	continuous_time_in_danger_low_s = 0.0
	continuous_time_in_danger_high_s = 0.0
	game_is_running = false # Will be set true by start_game
	final_game_outcome = {"reason": "none", "winner_id": 0}
	stabilize_effect_end_time_ms = 0
	active_event = {"type": Config.EventType.NONE, "end_time_ms": 0}

	event_check_timer.stop()
	event_duration_timer.stop()

	# Reset state for all currently tracked players (including host)
	for player_id in players:
		if players[player_id]: # Check if player state exists
			players[player_id].reset()

	print("Host: Game state reset complete.")
	# Emit signal for local display UI on the host
	emit_signal("game_reset_triggered")
	# Note: Clients are notified via `rpc_receive_game_reset` when a reset is requested and approved.


func _process(delta: float):
	# This function runs ONLY on the host due to the check in _ready()
	if not game_is_running:
		return

	var now_ms = Time.get_ticks_msec()
	var state_changed = false # Track if relevant state changed for broadcasting

	# --- 1. Update Timers & Effects ---
	var current_decay_rate = Config.BASE_ENERGY_DECAY_RATE
	var stabilize_active = stabilize_effect_end_time_ms > now_ms

	# Check stabilize effect end
	var was_stabilize_active = stabilize_active # Store previous state
	if stabilize_active and now_ms >= stabilize_effect_end_time_ms:
		stabilize_effect_end_time_ms = 0
		stabilize_active = false # Update current state immediately

	if not stabilize_active and was_stabilize_active: # Check if it *just* ended
		print("Host: Stabilize effect ended.")
		state_changed = true
		_broadcast_stabilize_state() # Notify clients effect ended

	# Apply decay modifier from stabilize (if active)
	if stabilize_active:
		current_decay_rate *= Config.STABILIZE_DECAY_MULTIPLIER

	# Apply event decay modifier (if active and stabilize is NOT)
	if not stabilize_active and active_event.type == Config.EventType.SURGE and active_event.end_time_ms > now_ms:
		current_decay_rate *= Config.EVENT_SURGE_DECAY_MULTIPLIER

	# Apply decay
	var old_energy = energy_level
	energy_level -= current_decay_rate * delta
	energy_level = clampf(energy_level, Config.MIN_ENERGY, Config.MAX_ENERGY)
	# Use a small tolerance to avoid broadcasting tiny floating point changes
	if abs(energy_level - old_energy) > 0.01:
		state_changed = true

	# --- 2. Update Win/Loss Condition Timers ---
	var old_stable_time = cumulative_stable_time_s
	var old_danger_low_time = continuous_time_in_danger_low_s
	var old_danger_high_time = continuous_time_in_danger_high_s

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
	else: # Between danger zones but not in safe zone
		continuous_time_in_danger_low_s = 0.0
		continuous_time_in_danger_high_s = 0.0

	# Check if timers changed enough to warrant update
	if abs(cumulative_stable_time_s - old_stable_time) > 0.1 or \
	   abs(continuous_time_in_danger_low_s - old_danger_low_time) > 0.1 or \
	   abs(continuous_time_in_danger_high_s - old_danger_high_time) > 0.1 or \
	   (continuous_time_in_danger_low_s == 0.0 and old_danger_low_time > 0.0) or \
	   (continuous_time_in_danger_high_s == 0.0 and old_danger_high_time > 0.0):
		state_changed = true # Timer changing is a state change

	# --- 3. Check Win/Loss Conditions ---
	var game_over_reason = "none"
	var winner_id = 0

	if cumulative_stable_time_s >= Config.COOP_WIN_DURATION_SECONDS:
		game_over_reason = "coopWin"
	elif continuous_time_in_danger_low_s >= Config.DANGER_TIME_LIMIT_SECONDS:
		game_over_reason = "shutdown"
	elif continuous_time_in_danger_high_s >= Config.DANGER_TIME_LIMIT_SECONDS:
		game_over_reason = "meltdown"
	# Individual win is checked within the steal action logic below

	if game_over_reason != "none":
		_trigger_game_over(game_over_reason, winner_id)
		return # Stop processing immediately after game over

	# --- 4. Broadcast State if Changed ---
	# Broadcast less frequently? Or only when significant changes occur?
	# For now, broadcast if any tracked variable changed significantly.
	if state_changed:
		_broadcast_game_state()


# --- Player Management (Host Only) ---

func _on_player_connected(id: int):
	if not multiplayer.is_server(): return
	print("GameManager (Host): Player connected ", id)
	_add_player(id)

	# Send current full state to the new player specifically
	rpc_id(id, "rpc_receive_initial_state", _get_current_state_snapshot())
	# Send current event and stabilize state
	rpc_id(id, "rpc_receive_event_update", active_event)
	rpc_id(id, "rpc_receive_stabilize_update", {"active": stabilize_effect_end_time_ms > Time.get_ticks_msec(), "end_time_ms": stabilize_effect_end_time_ms})

	# Send their specific initial player state (cooldowns, stash)
	var p_state = players.get(id)
	if p_state:
		_send_player_state(id, p_state)

	# Tell everyone else the player count changed (included in snapshot)
	_broadcast_game_state()

func _on_player_disconnected(id: int):
	if not multiplayer.is_server(): return
	if players.has(id):
		print("GameManager (Host): Removing player ", id)
		players.erase(id)
		_broadcast_game_state() # Update player count for everyone
	else:
		print("GameManager (Host): Received disconnect for unknown player ID ", id)

func _add_player(id: int):
	if not players.has(id):
		players[id] = PlayerState.new(id) # Use the PlayerState class


# --- Event Handling (Host Only) ---

func _on_event_check_timer_timeout():
	if not game_is_running or active_event.type != Config.EventType.NONE:
		return # Don't trigger if game over or event already active

	if randf() * 100.0 <= Config.EVENT_CHANCE_PERCENT:
		var chosen_type_index = randi() % Config.EVENT_TYPES.size() # Get random index
		var chosen_type = Config.EVENT_TYPES[chosen_type_index]     # Get enum value
		var now_ms = Time.get_ticks_msec()
		active_event = {
			"type": chosen_type,
			"end_time_ms": now_ms + Config.EVENT_DURATION_MS
		}
		event_duration_timer.wait_time = Config.EVENT_DURATION_MS / 1000.0
		event_duration_timer.start()
		print("--- EVENT TRIGGERED (Host): ", Config.EventType.keys()[chosen_type], " ---")
		_broadcast_event_state() # Notify clients

func _on_event_duration_timer_timeout():
	if active_event.type != Config.EventType.NONE:
		print("--- EVENT ENDED (Host): ", Config.EventType.keys()[active_event.type], " ---")
		active_event = {"type": Config.EventType.NONE, "end_time_ms": 0}
		_broadcast_event_state() # Notify clients event ended


# --- Game Over (Host Only) ---

func _trigger_game_over(reason: String, winner: int = 0):
	if not game_is_running:
		return # Already over
	print("!!! GAME OVER (Host): Reason={reason}, Winner={winner} !!!".format({"reason": reason, "winner": winner}))
	game_is_running = false
	final_game_outcome = {"reason": reason, "winner_id": winner}

	# Stop game logic timers
	event_check_timer.stop()
	event_duration_timer.stop()
	if active_event.type != Config.EventType.NONE: # Clear active event if game ends abruptly
		active_event = {"type": Config.EventType.NONE, "end_time_ms": 0}
		_broadcast_event_state() # Notify clients event ended due to game over

	# Emit signal for local Display UI on the host
	emit_signal("game_over_triggered", final_game_outcome)
	# RPC to all clients to notify them
	rpc("rpc_receive_game_over", final_game_outcome)


# --- Action Handling RPCs (Called by Clients, Executed on Host) ---

@rpc("any_peer", "call_local", "reliable") # Allow any client to call this function on the server
func rpc_player_action_generate():
	var sender_id = multiplayer.get_remote_sender_id()
	if not game_is_running or not players.has(sender_id): return # Validate

	var now_ms = Time.get_ticks_msec()
	var current_gain = Config.BASE_ENERGY_GAIN_PER_CLICK

	var stabilize_active = stabilize_effect_end_time_ms > now_ms
	var event_efficiency_active = active_event.type == Config.EventType.EFFICIENCY and active_event.end_time_ms > now_ms

	# Apply stabilize modifier (takes precedence)
	if stabilize_active:
		current_gain *= Config.STABILIZE_GAIN_MULTIPLIER
	# Apply event modifier (only if stabilize is not active)
	elif event_efficiency_active:
		current_gain *= Config.EVENT_EFFICIENCY_GAIN_MULTIPLIER

	var old_energy = energy_level
	energy_level = clampf(energy_level + current_gain, Config.MIN_ENERGY, Config.MAX_ENERGY)
	# No immediate broadcast needed here, _process handles periodic updates based on energy level changes.
	# Only broadcast if the change is significant enough to potentially change zones/status
	if abs(energy_level - old_energy) > 0.1:
		# Check if zone changed (e.g., entered/left safe zone) which might warrant an immediate update
		var old_zone = _get_energy_zone(old_energy)
		var new_zone = _get_energy_zone(energy_level)
		if old_zone != new_zone:
			_broadcast_game_state()


func _get_energy_zone(level: float) -> String:
	if level < Config.DANGER_LOW_THRESHOLD: return "danger_low"
	if level < Config.SAFE_ZONE_MIN: return "warning_low"
	if level <= Config.SAFE_ZONE_MAX: return "safe"
	if level < Config.DANGER_HIGH_THRESHOLD: return "warning_high"
	return "danger_high"


@rpc("any_peer", "call_local", "reliable")
func rpc_player_action_stabilize():
	var sender_id = multiplayer.get_remote_sender_id()
	if not game_is_running or not players.has(sender_id): return

	var player_state = players[sender_id]
	var now_ms = Time.get_ticks_msec()

	if now_ms >= player_state.stabilize_cooldown_end_ms:
		#print("Host: Stabilize action processing for Player ", sender_id)
		# Activate global effect
		stabilize_effect_end_time_ms = now_ms + Config.STABILIZE_DURATION_MS
		# Set player cooldown
		player_state.stabilize_cooldown_end_ms = now_ms + Config.STABILIZE_COOLDOWN_MS

		# Notify sender about their new cooldown
		_send_cooldown_update(sender_id, "stabilize", player_state.stabilize_cooldown_end_ms)
		# Broadcast the global effect update to all
		_broadcast_stabilize_state()
		# Broadcast general state as multipliers might change decay/gain rate display immediately
		_broadcast_game_state()
	else:
		# On cooldown, notify sender
		#print("Host: Stabilize blocked for ", sender_id, ", on cooldown.")
		_send_action_failed(sender_id, "stabilize", "cooldown")
		# Resend existing cooldown time to ensure client UI is correct
		_send_cooldown_update(sender_id, "stabilize", player_state.stabilize_cooldown_end_ms)

@rpc("any_peer", "call_local", "reliable")
func rpc_player_action_steal_grid(): # UI calls it "Divert Power"
	var sender_id = multiplayer.get_remote_sender_id()
	if not game_is_running or not players.has(sender_id): return

	var player_state = players[sender_id]
	var now_ms = Time.get_ticks_msec()

	# Check cooldown
	if now_ms < player_state.steal_grid_cooldown_end_ms:
		#print("Host: Steal Grid blocked for ", sender_id, ", on cooldown.")
		_send_action_failed(sender_id, "stealGrid", "cooldown")
		_send_cooldown_update(sender_id, "stealGrid", player_state.steal_grid_cooldown_end_ms)
		return

	# Check grid energy cost
	if energy_level < Config.STEAL_GRID_COST:
		#print("Host: Steal Grid blocked for ", sender_id, ", not enough grid energy.")
		_send_action_failed(sender_id, "stealGrid", "Insufficient grid energy")
		return

	# Apply effects
	#print("Host: Steal Grid action processing for Player ", sender_id)
	energy_level = max(Config.MIN_ENERGY, energy_level - Config.STEAL_GRID_COST)
	player_state.personal_stash += Config.STEAL_STASH_GAIN
	player_state.steal_grid_cooldown_end_ms = now_ms + Config.STEAL_COOLDOWN_MS

	# Notify sender of cooldown and stash update
	_send_cooldown_update(sender_id, "stealGrid", player_state.steal_grid_cooldown_end_ms)
	_send_stash_update(sender_id, player_state.personal_stash)

	# Check for individual win condition
	if player_state.personal_stash >= Config.STASH_WIN_TARGET:
		print("--- INDIVIDUAL WIN (Host): Triggered by Player ", sender_id, " ---")
		_trigger_game_over("individualWin", sender_id) # This handles broadcast
	else:
		# Broadcast grid energy change if no win occurred
		_broadcast_game_state()

@rpc("any_peer", "call_local", "reliable")
func rpc_player_action_emergency_adjust():
	var sender_id = multiplayer.get_remote_sender_id()
	if not game_is_running or not players.has(sender_id): return

	var player_state = players[sender_id]
	var now_ms = Time.get_ticks_msec()

	# Check cooldown
	if now_ms < player_state.emergency_adjust_cooldown_end_ms:
		#print("Host: Emergency Adjust blocked for ", sender_id, ", on cooldown.")
		_send_action_failed(sender_id, "emergencyAdjust", "cooldown")
		_send_cooldown_update(sender_id, "emergencyAdjust", player_state.emergency_adjust_cooldown_end_ms)
		return

	# Apply effects based on current zone
	#print("Host: Emergency Adjust action processing for Player ", sender_id)
	var energy_change: float = 0.0
	var misused = false

	if energy_level < Config.DANGER_LOW_THRESHOLD:
		energy_change = Config.EMERGENCY_BOOST_AMOUNT
		#print(" > Applying Boost (+", energy_change, ")")
	elif energy_level > Config.DANGER_HIGH_THRESHOLD:
		energy_change = -Config.EMERGENCY_COOLANT_AMOUNT # Negative change
		#print(" > Applying Coolant (", energy_change, ")")
	else: # Misused in safe or warning zones
		misused = true
		# Penalty pushes energy *away* from the center (55)
		if energy_level < (Config.SAFE_ZONE_MIN + Config.SAFE_ZONE_MAX) / 2.0:
			energy_change = -Config.EMERGENCY_PENALTY_WRONG_ZONE # Penalty pushes lower
		else:
			energy_change = Config.EMERGENCY_PENALTY_WRONG_ZONE # Penalty pushes higher
		#print(" > Misused! Applying penalty (", energy_change, ")")
		_send_action_failed(sender_id, "emergencyAdjust", "Used in wrong zone!") # Notify misuse

	# Apply energy change and cooldown
	energy_level = clampf(energy_level + energy_change, Config.MIN_ENERGY, Config.MAX_ENERGY)
	player_state.emergency_adjust_cooldown_end_ms = now_ms + Config.EMERGENCY_ADJUST_COOLDOWN_MS

	# Notify sender of new cooldown
	_send_cooldown_update(sender_id, "emergencyAdjust", player_state.emergency_adjust_cooldown_end_ms)

	# Broadcast state change resulting from the action
	_broadcast_game_state()

@rpc("any_peer", "call_local", "reliable")
func rpc_request_reset():
	# Only allow reset if game is actually over
	var sender_id = multiplayer.get_remote_sender_id()
	print("Host: Reset requested by peer ", sender_id)
	if not game_is_running:
		print("Host: Reset approved.")
		# RPC the reset signal *before* starting the game again
		# This tells clients to clear their UI first.
		rpc("rpc_receive_game_reset")

		# Wait a very short moment for clients to process reset before sending new state
		# This isn't strictly necessary but can prevent race conditions in UI updates
		await get_tree().create_timer(0.1).timeout

		# Restart the game loop and timers (calls _reset_game_state internally)
		start_game() # start_game now includes the reset logic and broadcasts initial state
	else:
		print("Host: Reset denied, game still running.")
		# Optionally notify sender: rpc_id(sender_id, "rpc_receive_reset_denied")


# --- Broadcasting Helper Functions (Host Only) ---

func _get_current_state_snapshot() -> Dictionary:
	# Create a dictionary representation of the current essential game state for clients
	var player_list = []
	for pid in players:
		player_list.append(pid) # Just send IDs

	return {
		"energyLevel": energy_level,
		"playerIds": player_list, # List of connected player IDs
		"playerCount": players.size(),
		"coopWinTargetSeconds": Config.COOP_WIN_DURATION_SECONDS,
		"coopWinProgressSeconds": cumulative_stable_time_s,
		"gameIsRunning": game_is_running,
		"finalOutcomeReason": final_game_outcome.reason,
		"finalOutcomeWinner": final_game_outcome.winner_id,
		"stashWinTarget": Config.STASH_WIN_TARGET,
		# Send necessary thresholds clients might need for display rendering
		"safeZoneMin": Config.SAFE_ZONE_MIN,
		"safeZoneMax": Config.SAFE_ZONE_MAX,
		"dangerLow": Config.DANGER_LOW_THRESHOLD,
		"dangerHigh": Config.DANGER_HIGH_THRESHOLD,
		# Send danger zone timers if needed on display (optional)
		"dangerLowProgressSeconds": continuous_time_in_danger_low_s,
		"dangerHighProgressSeconds": continuous_time_in_danger_high_s,
		"dangerTimeLimitSeconds": Config.DANGER_TIME_LIMIT_SECONDS,
	}

func _broadcast_game_state():
	if not multiplayer.is_server(): return
	var snapshot = _get_current_state_snapshot()
	# Emit signal for local display on the host
	emit_signal("game_state_updated", snapshot)
	# RPC to all connected clients
	rpc("rpc_receive_game_state_update", snapshot)

func _broadcast_event_state():
	if not multiplayer.is_server(): return
	# Emit signal for local display on the host
	emit_signal("event_updated", active_event)
	# RPC to all connected clients
	rpc("rpc_receive_event_update", active_event)

func _broadcast_stabilize_state():
	if not multiplayer.is_server(): return
	var data = {
		"active": stabilize_effect_end_time_ms > Time.get_ticks_msec(),
		"end_time_ms": stabilize_effect_end_time_ms
	}
	# Emit signal for local display on the host
	emit_signal("stabilize_effect_updated", data)
	# RPC to all connected clients
	rpc("rpc_receive_stabilize_update", data)

func _broadcast_all_player_states():
	# Send initial/reset state for all players
	if not multiplayer.is_server(): return
	for pid in players:
		if players[pid]:
			_send_player_state(pid, players[pid])

# --- Specific Player Feedback RPC Calls (Host -> Specific Client) ---

func _send_player_state(peer_id: int, player_state: PlayerState):
	# Helper to send all relevant state for a player at once
	if not multiplayer.is_server(): return
	if player_state:
		_send_cooldown_update(peer_id, "stabilize", player_state.stabilize_cooldown_end_ms)
		_send_cooldown_update(peer_id, "stealGrid", player_state.steal_grid_cooldown_end_ms)
		_send_cooldown_update(peer_id, "emergencyAdjust", player_state.emergency_adjust_cooldown_end_ms)
		_send_stash_update(peer_id, player_state.personal_stash)


func _send_cooldown_update(peer_id: int, action: String, end_time_ms: int):
	if not multiplayer.is_server(): return
	var data = {"action": action, "cooldown_end_time_ms": end_time_ms}
	# Emit signal if host needs it locally (e.g., debug UI or if host also plays)
	emit_signal("action_cooldown_update", peer_id, data)
	# RPC to the specific client, unless it's the host itself (ID 1)
	if peer_id != 1:
		rpc_id(peer_id, "rpc_receive_action_cooldown", data)
	# else: # If host (1) needs to update its own UI, handle via the emitted signal

func _send_stash_update(peer_id: int, stash_amount: float):
	if not multiplayer.is_server(): return
	var data = {"personal_stash": stash_amount}
	emit_signal("personal_stash_update", peer_id, data) # Emit locally
	if peer_id != 1:
		rpc_id(peer_id, "rpc_receive_personal_stash_update", data)
	# else: # Handle host stash update locally via signal if needed

func _send_action_failed(peer_id: int, action: String, reason: String):
	if not multiplayer.is_server(): return
	var data = {"action": action, "reason": reason}
	emit_signal("action_failed", peer_id, data) # Emit locally
	if peer_id != 1:
		rpc_id(peer_id, "rpc_receive_action_failed", data)
	# else: # Handle host action failure locally via signal if needed


# --- RPC Functions Called BY Host ON Clients ---
# These functions need to be defined in the client-side scripts (Controller.gd).
# The @rpc decoration here defines *how clients should receive calls* with these names.
# The bodies here are just placeholders; the actual execution happens on the client.

@rpc("authority", "call_remote", "reliable") # Mark that only the server (authority) can call this on clients
func rpc_receive_game_state_update(state_data: Dictionary):
	# Implementation is in Controller.gd
	assert(multiplayer.is_server(), "Host: rpc_receive_game_state_update should not execute on host!")
	pass

@rpc("authority", "call_remote", "reliable")
func rpc_receive_event_update(event_data: Dictionary):
	# Implementation primarily needed in Display.gd (if client), but Controller might show status? Add if needed.
	assert(multiplayer.is_server(), "Host: rpc_receive_event_update should not execute on host!")
	pass # Check Controller.gd - currently doesn't use this.

@rpc("authority", "call_remote", "reliable")
func rpc_receive_stabilize_update(stabilize_data: Dictionary):
	# Implementation might be visual feedback in Controller.gd? Add if needed.
	assert(multiplayer.is_server(), "Host: rpc_receive_stabilize_update should not execute on host!")
	pass # Check Controller.gd - currently doesn't use this.

@rpc("authority", "call_remote", "reliable")
func rpc_receive_game_over(outcome_data: Dictionary):
	# Implementation is in Controller.gd
	assert(multiplayer.is_server(), "Host: rpc_receive_game_over should not execute on host!")
	pass

@rpc("authority", "call_remote", "reliable")
func rpc_receive_game_reset():
	# Implementation is in Controller.gd
	assert(multiplayer.is_server(), "Host: rpc_receive_game_reset should not execute on host!")
	pass

@rpc("authority", "call_remote", "reliable")
func rpc_receive_game_start():
	# Implementation is in Controller.gd
	assert(multiplayer.is_server(), "Host: rpc_receive_game_start should not execute on host!")
	pass

@rpc("authority", "call_remote", "reliable")
func rpc_receive_initial_state(state_data: Dictionary):
	# Implementation is in Controller.gd
	assert(multiplayer.is_server(), "Host: rpc_receive_initial_state should not execute on host!")
	pass

@rpc("authority", "call_remote", "reliable")
func rpc_receive_action_cooldown(cooldown_data: Dictionary):
	# Implementation is in Controller.gd
	assert(multiplayer.is_server(), "Host: rpc_receive_action_cooldown should not execute on host!")
	pass

@rpc("authority", "call_remote", "reliable")
func rpc_receive_personal_stash_update(stash_data: Dictionary):
	# Implementation is in Controller.gd
	assert(multiplayer.is_server(), "Host: rpc_receive_personal_stash_update should not execute on host!")
	pass

@rpc("authority", "call_remote", "reliable")
func rpc_receive_action_failed(fail_data: Dictionary):
	# Implementation is in Controller.gd
	assert(multiplayer.is_server(), "Host: rpc_receive_action_failed should not execute on host!")
	pass
