# scripts/GameManager.gd
extends Node

signal game_state_updated(state_data: Dictionary)
signal game_over_triggered(outcome_data: Dictionary)
signal game_reset_triggered
signal event_updated(event_data: Dictionary) # To inform UI about current event
signal player_state_updated(player_id: int, player_state_data: Dictionary)
signal player_action_visual_feedback(player_id: int, action_name: String) # action_name will be "mash"

var energy_level: float = Config.SAFE_ZONE_MIN + (Config.SAFE_ZONE_MAX - Config.SAFE_ZONE_MIN) / 2.0
var players: Dictionary = {} # player_id: PlayerState object
var cumulative_stable_time_s: float = 0.0
var continuous_time_in_danger_low_s: float = 0.0
var continuous_time_in_danger_high_s: float = 0.0
var game_is_running: bool = false
var final_game_outcome: Dictionary = {"reason": "none", "winner_id": 0}

var active_event: Dictionary = {"type": Config.EventType.NONE, "end_time_ms": 0}

@onready var event_check_timer: Timer = $EventCheckTimer
@onready var event_duration_timer: Timer = $EventDurationTimer
@onready var udp_manager = get_node("/root/UdpManager") # Autoloaded

const PlayerState = preload("res://scripts/Player.gd")

func _ready():
	print("GameManager: _ready() Initializing for Local Play (UDP)")

	if udp_manager == null:
		printerr("GameManager Error: UdpManager node not found! Input disabled.")
		set_process(false); set_physics_process(false); return
	elif not udp_manager.is_listening:
		printerr("GameManager Error: UdpManager is not listening! Input disabled.")
		set_process(false); set_physics_process(false); return
	else:
		if not udp_manager.player_action_received.is_connected(_on_player_action_received):
			udp_manager.player_action_received.connect(_on_player_action_received)

	if not event_check_timer.timeout.is_connected(_on_event_check_timer_timeout):
		event_check_timer.timeout.connect(_on_event_check_timer_timeout)
	if not event_duration_timer.timeout.is_connected(_on_event_duration_timer_timeout):
		event_duration_timer.timeout.connect(_on_event_duration_timer_timeout)

	event_check_timer.wait_time = Config.EVENT_CHECK_INTERVAL_MS / 1000.0
	event_duration_timer.one_shot = true # Event duration timer stops after one shot

	print("GameManager: Creating player states...")
	for i in range(1, Config.NUM_PLAYERS + 1):
		_add_player(i)

	print("GameManager: Starting game logic.")
	call_deferred("start_game") # Use call_deferred to ensure everything is ready
	print("GameManager: _ready() FINISHED")

func _exit_tree():
	if udp_manager != null and udp_manager.player_action_received.is_connected(_on_player_action_received):
		udp_manager.player_action_received.disconnect(_on_player_action_received)

func _add_player(id: int):
	if not players.has(id):
		players[id] = PlayerState.new(id)
	else:
		players[id].reset() # If player object already exists, reset it

func start_game():
	print("<<<<<< GAMEMANAGER DEBUG: start_game() called >>>>>>")
	_reset_game_state()
	game_is_running = true
	event_check_timer.start()
	_emit_full_game_state() # Emit initial state for UI
	for player_id in players:
		_emit_player_state_update(player_id) # Emit initial player states
	print("GameManager: Game running.")

func _reset_game_state():
	energy_level = Config.SAFE_ZONE_MIN + (Config.SAFE_ZONE_MAX - Config.SAFE_ZONE_MIN) / 2.0
	cumulative_stable_time_s = 0.0
	continuous_time_in_danger_low_s = 0.0
	continuous_time_in_danger_high_s = 0.0
	game_is_running = false
	final_game_outcome = {"reason": "none", "winner_id": 0}
	active_event = {"type": Config.EventType.NONE, "end_time_ms": 0}
	
	event_check_timer.stop()
	event_duration_timer.stop()
	
	for player_id in players:
		if players.has(player_id) and players[player_id]: # Check if player state exists
			players[player_id].reset()
	
	emit_signal("game_reset_triggered")
	_emit_event_state() # Ensure UI reflects no active event after reset

func _process(delta: float):
	if not game_is_running:
		return

	var now_ms = Time.get_ticks_msec()
	var current_decay_rate = Config.BASE_ENERGY_DECAY_RATE

	# Apply event effects on decay
	if active_event.type == Config.EventType.SURGE and now_ms < active_event.end_time_ms:
		current_decay_rate *= Config.EVENT_SURGE_DECAY_MULTIPLIER
	
	energy_level = clampf(energy_level - (current_decay_rate * delta), Config.MIN_ENERGY, Config.MAX_ENERGY)

	# Check if the active event has ended
	if active_event.type != Config.EventType.NONE and now_ms >= active_event.end_time_ms:
		print("--- EVENT (process check) ENDED: ", Config.EventType.keys()[active_event.type], " ---")
		active_event = {"type": Config.EventType.NONE, "end_time_ms": 0}
		_emit_event_state() # Update UI that event is over
		if not event_duration_timer.is_stopped(): # Should be stopped by its own timeout too
			event_duration_timer.stop()

	# Win/Loss condition checks (largely unchanged)
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
	else: # Not in safe or danger zones (e.g. between danger_low and safe_min)
		continuous_time_in_danger_low_s = 0.0
		continuous_time_in_danger_high_s = 0.0

	var game_over_reason = "none"
	var winner_id = 0
	if cumulative_stable_time_s >= Config.COOP_WIN_DURATION_SECONDS:
		game_over_reason = "coopWin"
	elif continuous_time_in_danger_low_s >= Config.DANGER_TIME_LIMIT_SECONDS:
		game_over_reason = "shutdown"
	elif continuous_time_in_danger_high_s >= Config.DANGER_TIME_LIMIT_SECONDS:
		game_over_reason = "meltdown"
	
	if game_over_reason != "none":
		_trigger_game_over(game_over_reason, winner_id)
		return # Stop further processing if game over

	_emit_game_state_update() # Periodically update the main game state for UI

func _emit_game_state_update():
	emit_signal("game_state_updated", _get_current_state_snapshot())

func _emit_player_state_update(player_id: int):
	if players.has(player_id) and is_instance_valid(players[player_id]):
		var player_state: PlayerState = players[player_id]
		emit_signal("player_state_updated", player_id, player_state.get_state_data())
		player_state.clear_temp_status() # Clear status after emitting
	else:
		printerr("GameManager Error: Tried to emit update for invalid player ID or state: %d" % player_id)

func _emit_event_state():
	emit_signal("event_updated", active_event)

func _emit_full_game_state():
	_emit_game_state_update()
	_emit_event_state()

func _get_current_state_snapshot() -> Dictionary:
	var all_player_ids = players.keys()
	all_player_ids.sort() # Consistent order
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
		"playerStashes": _get_all_player_stashes(),
		"safeZoneMin": Config.SAFE_ZONE_MIN,
		"safeZoneMax": Config.SAFE_ZONE_MAX,
		"dangerLow": Config.DANGER_LOW_THRESHOLD,
		"dangerHigh": Config.DANGER_HIGH_THRESHOLD,
		"dangerLowProgressSeconds": continuous_time_in_danger_low_s,
		"dangerHighProgressSeconds": continuous_time_in_danger_high_s,
		"dangerTimeLimitSeconds": Config.DANGER_TIME_LIMIT_SECONDS,
		"activeEventType": active_event.type
	}

func _get_all_player_stashes() -> Dictionary:
	var stashes = {}
	for pid in players:
		if players.has(pid) and is_instance_valid(players[pid]):
			stashes[pid] = players[pid].personal_stash
	return stashes

func _on_event_check_timer_timeout():
	if not game_is_running or active_event.type != Config.EventType.NONE:
		return # Don't start a new event if one is already active or game not running

	if randf() * 100.0 <= Config.EVENT_CHANCE_PERCENT:
		var chosen_type = Config.EVENT_TYPES[randi() % Config.EVENT_TYPES.size()]
		var now_ms = Time.get_ticks_msec()
		active_event = {"type": chosen_type, "end_time_ms": now_ms + Config.EVENT_DURATION_MS}
		
		event_duration_timer.wait_time = Config.EVENT_DURATION_MS / 1000.0
		event_duration_timer.start()
		
		print("--- EVENT TRIGGERED: ", Config.EventType.keys()[chosen_type], " ---")
		_emit_event_state() # Inform UI about the new event
	# else: No event triggered this time

func _on_event_duration_timer_timeout():
	# This callback signifies the natural end of an event's duration
	if active_event.type != Config.EventType.NONE:
		print("--- EVENT (duration timer) ENDED: ", Config.EventType.keys()[active_event.type], " ---")
		active_event = {"type": Config.EventType.NONE, "end_time_ms": 0}
		_emit_event_state() # Update UI that event is over

func _trigger_game_over(reason: String, winner: int = 0):
	if not game_is_running: # Prevent multiple game over triggers
		return
		
	print("!!! GAME OVER: Reason=%s, Winner=%d !!!" % [reason, winner])
	game_is_running = false
	
	var player_scores_for_leaderboard: Array[Dictionary] = []
	var sorted_player_ids = players.keys()
	sorted_player_ids.sort()

	for pid in sorted_player_ids:
		if players.has(pid) and is_instance_valid(players[pid]):
			var p_state: PlayerState = players[pid]
			var char_details: Dictionary = {}
			if PlayerProfiles:
				char_details = PlayerProfiles.get_selected_character_details(pid)
			
			player_scores_for_leaderboard.append({
				"player_id": pid,
				"character_name": char_details.get("name", TextDB.GENERIC_PLAYER_LABEL_FORMAT % pid),
				"score": p_state.personal_stash,
				"generated_energy": p_state.total_energy_generated,
				"is_eliminated": p_state.is_eliminated
			})
	
	final_game_outcome = {
		"reason": reason,
		"winner_id": winner,
		"leaderboard_data": player_scores_for_leaderboard
	}
	
	event_check_timer.stop()
	event_duration_timer.stop()
	
	# Ensure any active event is cleared on game over
	if active_event.type != Config.EventType.NONE:
		active_event = {"type": Config.EventType.NONE, "end_time_ms": 0}
		_emit_event_state() # Update UI
		
	emit_signal("game_over_triggered", final_game_outcome)
	_emit_game_state_update() # Send final game state

func _on_player_action_received(player_id: int, action_string: String): # action_string is "mash"
	if player_id <= 0 or player_id > Config.NUM_PLAYERS:
		printerr("GM: Invalid player ID %d for action." % player_id)
		return
	if not players.has(player_id) or not is_instance_valid(players[player_id]):
		printerr("GM: No state for player ID %d, action ignored." % player_id)
		return

	var player_state: PlayerState = players[player_id]
	if player_state.is_eliminated:
		return # Eliminated players cannot act

	# Visual feedback for the button press
	emit_signal("player_action_visual_feedback", player_id, "mash") # Use "mash" or a generic term

	if not game_is_running:
		return # No actions if game isn't running

	var now_ms = Time.get_ticks_msec()
	var current_event_type = active_event.type
	var event_is_active = (active_event.end_time_ms > now_ms)

	# If event_is_active is false, but current_event_type is not NONE, it means event just ended.
	# Treat as NONE state for player action.
	if not event_is_active and current_event_type != Config.EventType.NONE:
		current_event_type = Config.EventType.NONE

	var energy_gained_by_this_mash: float = 0.0

	match current_event_type:
		Config.EventType.NONE: # Normal Operation
			energy_gained_by_this_mash = Config.BASE_ENERGY_GAIN_PER_MASH
			energy_level = clampf(energy_level + Config.BASE_ENERGY_GAIN_PER_MASH, Config.MIN_ENERGY, Config.MAX_ENERGY)
		
		Config.EventType.EFFICIENCY:
			energy_gained_by_this_mash = Config.BASE_ENERGY_GAIN_PER_MASH * Config.EVENT_EFFICIENCY_GAIN_MULTIPLIER
			energy_level = clampf(energy_level + energy_gained_by_this_mash, Config.MIN_ENERGY, Config.MAX_ENERGY)
		
		Config.EventType.SURGE:
			energy_gained_by_this_mash = Config.BASE_ENERGY_GAIN_PER_MASH * Config.EVENT_SURGE_GAIN_REDUCTION_FACTOR
			energy_level = clampf(energy_level + energy_gained_by_this_mash, Config.MIN_ENERGY, Config.MAX_ENERGY)
		
		Config.EventType.UNSTABLE_GRID:
			# This event does NOT generate grid energy, it drains it.
			# So, energy_gained_by_this_mash remains 0.0 for this case.
			if randf() * 100.0 < Config.UNSTABLE_GRID_ELECTROCUTION_CHANCE_PERCENT:
				player_state.eliminate_player()
				_emit_player_state_update(player_id)
				_check_elimination_game_over_conditions()
				return 
			
			var drained_amount = Config.UNSTABLE_GRID_DRAIN_PER_MASH
			if energy_level >= drained_amount:
				energy_level -= drained_amount
				player_state.personal_stash += drained_amount
				player_state.set_temp_status(TextDB.STATUS_STOLE_AMOUNT % drained_amount)
				_emit_player_state_update(player_id)
				
				if player_state.personal_stash >= Config.STASH_WIN_TARGET:
					_trigger_game_over("individualWin", player_id)
			else:
				player_state.set_temp_status(TextDB.STATUS_LOW_GRID_FOR_STEAL)
				_emit_player_state_update(player_id)
		_:
			printerr("GM: Unhandled event type for player action:", current_event_type)
			
	if energy_gained_by_this_mash > 0:
		player_state.add_generated_energy(energy_gained_by_this_mash)
	
	# No need to call _emit_player_state_update here unless a status was set.
	# Energy level changes are reflected by _emit_game_state_update in _process.

func _check_elimination_game_over_conditions():
	if not game_is_running: return # Don't check if game already over
	
	var active_players_count = 0
	var last_active_player_id = 0
	for pid in players:
		var p_state: PlayerState = players[pid]
		if not p_state.is_eliminated:
			active_players_count += 1
			last_active_player_id = pid
			
	if active_players_count == 0 and Config.NUM_PLAYERS > 0:
		_trigger_game_over("allEliminated")
	elif active_players_count == 1 and Config.NUM_PLAYERS > 1: # Only matters if more than 1 player started
		_trigger_game_over("lastPlayerStanding", last_active_player_id)

func handle_reset_request(): # Example if UI had a reset button directly
	if not game_is_running:
		print("GM: Reset approved (game not running). Starting new game.")
		start_game()
	else:
		print("GM: Reset denied, game still running.")
