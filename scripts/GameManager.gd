# scripts/GameManager.gd
extends Node

# --- [ Signals, State Variables, etc. - Keep as they were in the previous response ] ---
signal game_state_updated(state_data: Dictionary)
signal game_over_triggered(outcome_data: Dictionary)
signal game_reset_triggered
signal event_updated(event_data: Dictionary)
signal stabilize_effect_updated(stabilize_data: Dictionary)
signal game_manager_ready

signal action_failed(peer_id: int, fail_data: Dictionary)
signal action_cooldown_update(peer_id: int, cooldown_data: Dictionary)
signal personal_stash_update(peer_id: int, stash_data: Dictionary)

var energy_level: float = Config.SAFE_ZONE_MIN + (Config.SAFE_ZONE_MAX - Config.SAFE_ZONE_MIN) / 2.0
var players: Dictionary = {}
var cumulative_stable_time_s: float = 0.0
var continuous_time_in_danger_low_s: float = 0.0
var continuous_time_in_danger_high_s: float = 0.0
var game_is_running: bool = false
var final_game_outcome: Dictionary = {"reason": "none", "winner_id": 0}
var stabilize_effect_end_time_ms: int = 0
var active_event: Dictionary = {"type": Config.EventType.NONE, "end_time_ms": 0}
var _host_ready: bool = false

@onready var event_check_timer: Timer = $EventCheckTimer
@onready var event_duration_timer: Timer = $EventDurationTimer

const PlayerState = preload("res://scripts/Player.gd")

# --- [ _ready, _exit_tree, start_game, _reset_game_state, _process - Keep as they were ] ---
# --- [ Ensure _ready calls rpc("rpc_signal_host_ready") AFTER _host_ready = true  ] ---
# --- [ Ensure _on_player_connected calls rpc_id(id, "rpc_signal_host_ready") if _host_ready ] ---
# --- [ Ensure rpc_request_reset handles _host_ready flag and re-signals ] ---


func _ready():
	if not multiplayer.is_server():
		set_process(false)
		set_physics_process(false)
		if event_check_timer: event_check_timer.stop()
		if event_duration_timer: event_duration_timer.stop()
		return

	print(">>> GameManager: _ready() STARTING on Host")
	print("GameManager ready on Host.")

	# --- Connect Multiplayer Signals ---
	# It's safer to check connection status before connecting
	if not multiplayer.peer_connected.is_connected(_on_player_connected):
		multiplayer.peer_connected.connect(_on_player_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_player_disconnected):
		multiplayer.peer_disconnected.connect(_on_player_disconnected)

	# --- Connect Timer Signals ---
	event_check_timer.timeout.connect(_on_event_check_timer_timeout)
	event_duration_timer.timeout.connect(_on_event_duration_timer_timeout)

	event_check_timer.wait_time = Config.EVENT_CHECK_INTERVAL_MS / 1000.0
	event_duration_timer.one_shot = true

	print(">>> GameManager: _ready() Base setup complete. Adding host player.")
	_add_player(1) # Add host player immediately

	# --- Host Readiness ---
	_host_ready = true # Set the flag
	emit_signal("game_manager_ready") # Emit local signal

	# --- MODIFICATION: Defer the RPC signal ---
	# Signal readiness to clients *after* the current frame processing is done.
	# This ensures the node path is reliably resolvable when the RPC arrives.
	print(">>> GameManager: _ready() Deferring host ready RPC signal.")
	call_deferred("rpc", "rpc_signal_host_ready")
	# --- END MODIFICATION ---

	print(">>> GameManager: _ready() Starting game.")
	start_game() # Start game logic (this also broadcasts initial state)
	print(">>> GameManager: _ready() FINISHED on Host")
	if not multiplayer.is_server():
		set_process(false)
		set_physics_process(false)
		if event_check_timer: event_check_timer.stop()
		if event_duration_timer: event_duration_timer.stop()
		return

	print(">>> GameManager: _ready() STARTING on Host")
	print("GameManager ready on Host.")

	if not multiplayer.peer_connected.is_connected(_on_player_connected):
		multiplayer.peer_connected.connect(_on_player_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_player_disconnected):
		multiplayer.peer_disconnected.connect(_on_player_disconnected)

	event_check_timer.timeout.connect(_on_event_check_timer_timeout)
	event_duration_timer.timeout.connect(_on_event_duration_timer_timeout)

	event_check_timer.wait_time = Config.EVENT_CHECK_INTERVAL_MS / 1000.0
	event_duration_timer.one_shot = true

	print(">>> GameManager: _ready() Base setup complete. Signalling readiness.")
	_add_player(1)

	_host_ready = true
	emit_signal("game_manager_ready")
	rpc("rpc_signal_host_ready")

	print(">>> GameManager: _ready() Host ready signaled. Starting game.")
	start_game()
	print(">>> GameManager: _ready() FINISHED on Host")

func _exit_tree():
	_host_ready = false
	if multiplayer != null:
		if multiplayer.peer_connected.is_connected(_on_player_connected):
			multiplayer.peer_connected.disconnect(_on_player_connected)
		if multiplayer.peer_disconnected.is_connected(_on_player_disconnected):
			multiplayer.peer_disconnected.disconnect(_on_player_disconnected)

func start_game():
	if game_is_running and multiplayer.is_server(): return
	if not multiplayer.is_server(): return
	print("Host: Starting game...")
	_reset_game_state()
	game_is_running = true
	event_check_timer.start()
	rpc("rpc_receive_game_start")
	_broadcast_game_state()
	_broadcast_event_state()
	_broadcast_stabilize_state()
	_broadcast_all_player_states()
	print("Host: Game running.")

func _reset_game_state():
	if not multiplayer.is_server(): return
	energy_level = Config.SAFE_ZONE_MIN + (Config.SAFE_ZONE_MAX - Config.SAFE_ZONE_MIN) / 2.0
	cumulative_stable_time_s = 0.0
	continuous_time_in_danger_low_s = 0.0
	continuous_time_in_danger_high_s = 0.0
	game_is_running = false
	final_game_outcome = {"reason": "none", "winner_id": 0}
	stabilize_effect_end_time_ms = 0
	active_event = {"type": Config.EventType.NONE, "end_time_ms": 0}
	event_check_timer.stop()
	event_duration_timer.stop()
	for player_id in players:
		if players[player_id]: players[player_id].reset()
	emit_signal("game_reset_triggered")

func _process(delta: float):
	if not game_is_running: return
	var now_ms = Time.get_ticks_msec()
	var state_changed = false
	var current_decay_rate = Config.BASE_ENERGY_DECAY_RATE
	var stabilize_active = stabilize_effect_end_time_ms > now_ms
	var was_stabilize_active = stabilize_active
	if stabilize_active and now_ms >= stabilize_effect_end_time_ms:
		stabilize_effect_end_time_ms = 0
		stabilize_active = false
	if not stabilize_active and was_stabilize_active:
		state_changed = true
		_broadcast_stabilize_state()
	if stabilize_active:
		current_decay_rate *= Config.STABILIZE_DECAY_MULTIPLIER
	if not stabilize_active and active_event.type == Config.EventType.SURGE and active_event.end_time_ms > now_ms:
		current_decay_rate *= Config.EVENT_SURGE_DECAY_MULTIPLIER
	var old_energy = energy_level
	energy_level -= current_decay_rate * delta
	energy_level = clampf(energy_level, Config.MIN_ENERGY, Config.MAX_ENERGY)
	if abs(energy_level - old_energy) > 0.01: state_changed = true
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
	else:
		continuous_time_in_danger_low_s = 0.0
		continuous_time_in_danger_high_s = 0.0
	if abs(cumulative_stable_time_s - old_stable_time) > 0.1 or \
	   abs(continuous_time_in_danger_low_s - old_danger_low_time) > 0.1 or \
	   abs(continuous_time_in_danger_high_s - old_danger_high_time) > 0.1 or \
	   (continuous_time_in_danger_low_s == 0.0 and old_danger_low_time > 0.0) or \
	   (continuous_time_in_danger_high_s == 0.0 and old_danger_high_time > 0.0):
		state_changed = true
	var game_over_reason = "none"
	var winner_id = 0
	if cumulative_stable_time_s >= Config.COOP_WIN_DURATION_SECONDS: game_over_reason = "coopWin"
	elif continuous_time_in_danger_low_s >= Config.DANGER_TIME_LIMIT_SECONDS: game_over_reason = "shutdown"
	elif continuous_time_in_danger_high_s >= Config.DANGER_TIME_LIMIT_SECONDS: game_over_reason = "meltdown"
	if game_over_reason != "none":
		_trigger_game_over(game_over_reason, winner_id)
		return
	if state_changed: _broadcast_game_state()

func _on_player_connected(id: int):
	if not multiplayer.is_server(): return
	print("GameManager (Host): Player connected ", id)
	_add_player(id)
	rpc_id(id, "rpc_receive_initial_state", _get_current_state_snapshot())
	rpc_id(id, "rpc_receive_event_update", active_event)
	rpc_id(id, "rpc_receive_stabilize_update", {"active": stabilize_effect_end_time_ms > Time.get_ticks_msec(), "end_time_ms": stabilize_effect_end_time_ms})
	var p_state = players.get(id)
	if p_state: _send_player_state(id, p_state)
	if _host_ready:
		print("GameManager (Host): Host already ready, signaling newly connected player ", id)
		rpc_id(id, "rpc_signal_host_ready")
	_broadcast_game_state()

func _on_player_disconnected(id: int):
	if not multiplayer.is_server(): return
	if players.has(id):
		print("GameManager (Host): Removing player ", id)
		players.erase(id)
		_broadcast_game_state()
	else: pass

func _add_player(id: int):
	if not players.has(id): players[id] = PlayerState.new(id)

func _on_event_check_timer_timeout():
	if not game_is_running or active_event.type != Config.EventType.NONE: return
	if randf() * 100.0 <= Config.EVENT_CHANCE_PERCENT:
		var chosen_type_index = randi() % Config.EVENT_TYPES.size()
		var chosen_type = Config.EVENT_TYPES[chosen_type_index]
		var now_ms = Time.get_ticks_msec()
		active_event = {"type": chosen_type, "end_time_ms": now_ms + Config.EVENT_DURATION_MS}
		event_duration_timer.wait_time = Config.EVENT_DURATION_MS / 1000.0
		event_duration_timer.start()
		print("--- EVENT TRIGGERED (Host): ", Config.EventType.keys()[chosen_type], " ---")
		_broadcast_event_state()

func _on_event_duration_timer_timeout():
	if active_event.type != Config.EventType.NONE:
		print("--- EVENT ENDED (Host): ", Config.EventType.keys()[active_event.type], " ---")
		active_event = {"type": Config.EventType.NONE, "end_time_ms": 0}
		_broadcast_event_state()

func _trigger_game_over(reason: String, winner: int = 0):
	if not game_is_running: return
	print("!!! GAME OVER (Host): Reason=%s, Winner=%d !!!" % [reason, winner])
	game_is_running = false
	final_game_outcome = {"reason": reason, "winner_id": winner}
	event_check_timer.stop()
	event_duration_timer.stop()
	if active_event.type != Config.EventType.NONE:
		active_event = {"type": Config.EventType.NONE, "end_time_ms": 0}
		_broadcast_event_state()
	emit_signal("game_over_triggered", final_game_outcome)
	rpc("rpc_receive_game_over", final_game_outcome)


# --- Action Handling RPCs (Called by Clients Directly, Executed on Host) ---

@rpc("any_peer", "call_local", "reliable")
func rpc_player_action_generate():
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1 # Handle local call if needed for testing host UI

	# --- INTENSIVE DEBUGGING ---
	print("!!!!!! HOST: rpc_player_action_generate CALLED by peer %d !!!!!!" % sender_id)
	print("!!!!!! HOST: self.get_path() = %s" % self.get_path()) # What is MY path? Should be /root/Display/GameManager
	var parent_node = get_parent()
	if is_instance_valid(parent_node):
		print("!!!!!! HOST: Parent Name = %s, Parent Path = %s" % [parent_node.name, parent_node.get_path()]) # Should be Display, /root/Display
	else:
		print("!!!!!! HOST: Parent is INVALID!")

	var root_node = get_tree().get_root()
	if is_instance_valid(root_node):
		print("!!!!!! HOST: Root node exists. Printing tree:")
		root_node.print_tree_pretty()
		# Try to find the node using the path the client used
		var target_path_from_root = "Display/GameManager" # Path relative to root
		print("!!!!!! HOST: Attempting get_node_or_null('%s')" % target_path_from_root)
		var found_node = root_node.get_node_or_null(target_path_from_root)
		if is_instance_valid(found_node):
			print("!!!!!! HOST: Successfully found node at '%s' via get_node_or_null!" % target_path_from_root)
			if found_node == self:
				print("!!!!!! HOST: And the found node IS self!")
			else:
				print("!!!!!! HOST: BUT the found node is NOT self! Found: %s" % found_node)
		else:
			print("!!!!!! HOST: FAILED to find node at '%s' via get_node_or_null!" % target_path_from_root)
	else:
		print("!!!!!! HOST: Root node is INVALID!")
	# --- END INTENSIVE DEBUGGING ---


	# --- Original Check ---
	if not game_is_running or not players.has(sender_id) or not _host_ready:
		printerr("Host rejected generate: game_running=%s, has_player=%s, host_ready=%s" % [game_is_running, players.has(sender_id), _host_ready])
		# We add the debug print above, but still return if check fails
		return

	# --- Rest of the function logic ---
	var now_ms = Time.get_ticks_msec()
	var current_gain = Config.BASE_ENERGY_GAIN_PER_CLICK
	var stabilize_active = stabilize_effect_end_time_ms > now_ms
	var event_efficiency_active = active_event.type == Config.EventType.EFFICIENCY and active_event.end_time_ms > now_ms

	if stabilize_active:
		current_gain *= Config.STABILIZE_GAIN_MULTIPLIER
	elif event_efficiency_active:
		current_gain *= Config.EVENT_EFFICIENCY_GAIN_MULTIPLIER

	var old_energy = energy_level
	energy_level = clampf(energy_level + current_gain, Config.MIN_ENERGY, Config.MAX_ENERGY)
	if abs(energy_level - old_energy) > 0.1:
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
	if sender_id == 0: sender_id = 1
	if not game_is_running or not players.has(sender_id) or not _host_ready:
		printerr("Host rejected stabilize: game_running=%s, has_player=%s, host_ready=%s" % [game_is_running, players.has(sender_id), _host_ready])
		return
	var player_state = players[sender_id]
	var now_ms = Time.get_ticks_msec()
	if now_ms >= player_state.stabilize_cooldown_end_ms:
		stabilize_effect_end_time_ms = now_ms + Config.STABILIZE_DURATION_MS
		player_state.stabilize_cooldown_end_ms = now_ms + Config.STABILIZE_COOLDOWN_MS
		_send_cooldown_update(sender_id, "stabilize", player_state.stabilize_cooldown_end_ms)
		_broadcast_stabilize_state()
		_broadcast_game_state()
	else:
		_send_action_failed(sender_id, "stabilize", "cooldown")
		_send_cooldown_update(sender_id, "stabilize", player_state.stabilize_cooldown_end_ms)

@rpc("any_peer", "call_local", "reliable")
func rpc_player_action_stealGrid():
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1
	if not game_is_running or not players.has(sender_id) or not _host_ready:
		printerr("Host rejected stealGrid: game_running=%s, has_player=%s, host_ready=%s" % [game_is_running, players.has(sender_id), _host_ready])
		return
	var player_state = players[sender_id]
	var now_ms = Time.get_ticks_msec()
	if now_ms < player_state.steal_grid_cooldown_end_ms:
		_send_action_failed(sender_id, "stealGrid", "cooldown")
		_send_cooldown_update(sender_id, "stealGrid", player_state.steal_grid_cooldown_end_ms)
		return
	if energy_level < Config.STEAL_GRID_COST:
		_send_action_failed(sender_id, "stealGrid", "Insufficient grid energy")
		return
	energy_level = max(Config.MIN_ENERGY, energy_level - Config.STEAL_GRID_COST)
	player_state.personal_stash += Config.STEAL_STASH_GAIN
	player_state.steal_grid_cooldown_end_ms = now_ms + Config.STEAL_COOLDOWN_MS
	_send_cooldown_update(sender_id, "stealGrid", player_state.steal_grid_cooldown_end_ms)
	_send_stash_update(sender_id, player_state.personal_stash)
	if player_state.personal_stash >= Config.STASH_WIN_TARGET:
		print("--- INDIVIDUAL WIN (Host): Triggered by Player ", sender_id, " ---")
		_trigger_game_over("individualWin", sender_id)
	else:
		_broadcast_game_state()

@rpc("any_peer", "call_local", "reliable")
func rpc_player_action_emergencyAdjust():
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1
	if not game_is_running or not players.has(sender_id) or not _host_ready:
		printerr("Host rejected emergencyAdjust: game_running=%s, has_player=%s, host_ready=%s" % [game_is_running, players.has(sender_id), _host_ready])
		return
	var player_state = players[sender_id]
	var now_ms = Time.get_ticks_msec()
	if now_ms < player_state.emergency_adjust_cooldown_end_ms:
		_send_action_failed(sender_id, "emergencyAdjust", "cooldown")
		_send_cooldown_update(sender_id, "emergencyAdjust", player_state.emergency_adjust_cooldown_end_ms)
		return
	var energy_change: float = 0.0
	var misused = false
	if energy_level < Config.DANGER_LOW_THRESHOLD:
		energy_change = Config.EMERGENCY_BOOST_AMOUNT
	elif energy_level > Config.DANGER_HIGH_THRESHOLD:
		energy_change = -Config.EMERGENCY_COOLANT_AMOUNT
	else:
		misused = true
		if energy_level < (Config.SAFE_ZONE_MIN + Config.SAFE_ZONE_MAX) / 2.0: energy_change = -Config.EMERGENCY_PENALTY_WRONG_ZONE
		else: energy_change = Config.EMERGENCY_PENALTY_WRONG_ZONE
		_send_action_failed(sender_id, "emergencyAdjust", "Used in wrong zone!")
	energy_level = clampf(energy_level + energy_change, Config.MIN_ENERGY, Config.MAX_ENERGY)
	player_state.emergency_adjust_cooldown_end_ms = now_ms + Config.EMERGENCY_ADJUST_COOLDOWN_MS
	_send_cooldown_update(sender_id, "emergencyAdjust", player_state.emergency_adjust_cooldown_end_ms)
	_broadcast_game_state()

@rpc("any_peer", "call_local", "reliable")
func rpc_request_reset():
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1
	if not game_is_running:
		print("Host: Reset approved.")
		_host_ready = false
		rpc("rpc_receive_game_reset")
		await get_tree().create_timer(0.1).timeout
		print("Host: Reset complete. Signalling readiness again.")
		_host_ready = true
		emit_signal("game_manager_ready")
		rpc("rpc_signal_host_ready")
		start_game()
	else:
		print("Host: Reset denied, game still running.")


# --- [ Broadcasting Helper Functions - Keep as they were ] ---
func _get_current_state_snapshot() -> Dictionary:
	var all_player_ids: Array[int] = []
	all_player_ids.push_front(1)
	if multiplayer != null and multiplayer.multiplayer_peer:
		var client_peer_ids: PackedInt32Array = multiplayer.get_peers()
		for peer_id in client_peer_ids: all_player_ids.append(peer_id)
	return { "energyLevel": energy_level, "playerIds": all_player_ids, "playerCount": all_player_ids.size(), "coopWinTargetSeconds": Config.COOP_WIN_DURATION_SECONDS, "coopWinProgressSeconds": cumulative_stable_time_s, "gameIsRunning": game_is_running, "finalOutcomeReason": final_game_outcome.reason, "finalOutcomeWinner": final_game_outcome.winner_id, "stashWinTarget": Config.STASH_WIN_TARGET, "safeZoneMin": Config.SAFE_ZONE_MIN, "safeZoneMax": Config.SAFE_ZONE_MAX, "dangerLow": Config.DANGER_LOW_THRESHOLD, "dangerHigh": Config.DANGER_HIGH_THRESHOLD, "dangerLowProgressSeconds": continuous_time_in_danger_low_s, "dangerHighProgressSeconds": continuous_time_in_danger_high_s, "dangerTimeLimitSeconds": Config.DANGER_TIME_LIMIT_SECONDS, }
func _broadcast_game_state():
	if not multiplayer.is_server(): return
	var snapshot = _get_current_state_snapshot()
	emit_signal("game_state_updated", snapshot)
	rpc("rpc_receive_game_state_update", snapshot)
func _broadcast_event_state():
	if not multiplayer.is_server(): return
	emit_signal("event_updated", active_event)
	rpc("rpc_receive_event_update", active_event)
func _broadcast_stabilize_state():
	if not multiplayer.is_server(): return
	var data = {"active": stabilize_effect_end_time_ms > Time.get_ticks_msec(), "end_time_ms": stabilize_effect_end_time_ms}
	emit_signal("stabilize_effect_updated", data)
	rpc("rpc_receive_stabilize_update", data)
func _broadcast_all_player_states():
	if not multiplayer.is_server(): return
	for pid in players:
		if players[pid]: _send_player_state(pid, players[pid])

# --- [ Specific Player Feedback RPC Calls - Keep as they were ] ---
func _send_player_state(peer_id: int, player_state: PlayerState):
	if not multiplayer.is_server(): return
	if player_state:
		_send_cooldown_update(peer_id, "stabilize", player_state.stabilize_cooldown_end_ms)
		_send_cooldown_update(peer_id, "stealGrid", player_state.steal_grid_cooldown_end_ms)
		_send_cooldown_update(peer_id, "emergencyAdjust", player_state.emergency_adjust_cooldown_end_ms)
		_send_stash_update(peer_id, player_state.personal_stash)
func _send_cooldown_update(peer_id: int, action: String, end_time_ms: int):
	if not multiplayer.is_server(): return
	var data = {"action": action, "cooldown_end_time_ms": end_time_ms}
	emit_signal("action_cooldown_update", peer_id, data)
	if peer_id != 1: rpc_id(peer_id, "rpc_receive_action_cooldown", data)
func _send_stash_update(peer_id: int, stash_amount: float):
	if not multiplayer.is_server(): return
	var data = {"personal_stash": stash_amount}
	emit_signal("personal_stash_update", peer_id, data)
	if peer_id != 1: rpc_id(peer_id, "rpc_receive_personal_stash_update", data)
func _send_action_failed(peer_id: int, action: String, reason: String):
	if not multiplayer.is_server(): return
	var data = {"action": action, "reason": reason}
	emit_signal("action_failed", peer_id, data)
	if peer_id != 1: rpc_id(peer_id, "rpc_receive_action_failed", data)


# --- [ RPC Function Definitions for Client Calls - Keep as they were ] ---
@rpc("authority", "call_remote", "reliable") func rpc_receive_game_state_update(state_data: Dictionary): assert(not multiplayer.is_server()); pass
@rpc("authority", "call_remote", "reliable") func rpc_receive_event_update(event_data: Dictionary): assert(not multiplayer.is_server()); pass
@rpc("authority", "call_remote", "reliable") func rpc_receive_stabilize_update(stabilize_data: Dictionary): assert(not multiplayer.is_server()); pass
@rpc("authority", "call_remote", "reliable") func rpc_receive_game_over(outcome_data: Dictionary): assert(not multiplayer.is_server()); pass
@rpc("authority", "call_remote", "reliable") func rpc_receive_game_reset(): assert(not multiplayer.is_server()); pass
@rpc("authority", "call_remote", "reliable") func rpc_receive_game_start(): assert(not multiplayer.is_server()); pass
@rpc("authority", "call_remote", "reliable") func rpc_receive_initial_state(state_data: Dictionary): assert(not multiplayer.is_server()); pass
@rpc("authority", "call_remote", "reliable") func rpc_receive_action_cooldown(cooldown_data: Dictionary): assert(not multiplayer.is_server()); pass
@rpc("authority", "call_remote", "reliable") func rpc_receive_personal_stash_update(stash_data: Dictionary): assert(not multiplayer.is_server()); pass
@rpc("authority", "call_remote", "reliable") func rpc_receive_action_failed(fail_data: Dictionary): assert(not multiplayer.is_server()); pass
@rpc("authority", "call_remote", "reliable") func rpc_signal_host_ready(): assert(not multiplayer.is_server(), "rpc_signal_host_ready should only run on clients!"); pass
