# scripts/GameManager.gd
extends Node

signal game_state_updated(state_data: Dictionary)
signal game_over_triggered(outcome_data: Dictionary)
signal game_reset_triggered
signal event_updated(event_data: Dictionary)
signal stabilize_effect_updated(stabilize_data: Dictionary)
signal player_state_updated(player_id: int, player_state_data: Dictionary)
signal player_action_visual_feedback(player_id: int, action_name: String)

const NUM_PLAYERS = Config.NUM_PLAYERS # Use Config value

var energy_level: float = Config.SAFE_ZONE_MIN + (Config.SAFE_ZONE_MAX - Config.SAFE_ZONE_MIN) / 2.0
var players: Dictionary = {}
var cumulative_stable_time_s: float = 0.0
var continuous_time_in_danger_low_s: float = 0.0
var continuous_time_in_danger_high_s: float = 0.0
var game_is_running: bool = false
var final_game_outcome: Dictionary = {"reason": "none", "winner_id": 0}
var stabilize_effect_end_time_ms: int = 0
var active_event: Dictionary = {"type": Config.EventType.NONE, "end_time_ms": 0}

@onready var event_check_timer: Timer = $EventCheckTimer
@onready var event_duration_timer: Timer = $EventDurationTimer
@onready var udp_manager = get_node("/root/UdpManager")

const PlayerState = preload("res://scripts/Player.gd")

func _ready():
	print("!!!!! GAMEMANAGER _ready() STARTED !!!!!")
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
	event_duration_timer.one_shot = true

	print("GameManager: Creating player states...")
	for i in range(1, NUM_PLAYERS + 1): _add_player(i)

	print("GameManager: Starting game logic.")
	call_deferred("start_game")
	print("GameManager: _ready() FINISHED")

func _exit_tree():
	if udp_manager != null and udp_manager.player_action_received.is_connected(_on_player_action_received):
		udp_manager.player_action_received.disconnect(_on_player_action_received)

func _add_player(id: int):
	if not players.has(id):
		players[id] = PlayerState.new(id)
	else:
		players[id].reset()

func start_game():
	print("<<<<<< GAMEMANAGER DEBUG: start_game() called >>>>>>")
	_reset_game_state()
	game_is_running = true
	event_check_timer.start()
	_emit_full_game_state()
	for player_id in players: _emit_player_state_update(player_id)
	print("GameManager: Game running.")

func _reset_game_state():
	energy_level = Config.SAFE_ZONE_MIN + (Config.SAFE_ZONE_MAX - Config.SAFE_ZONE_MIN) / 2.0
	cumulative_stable_time_s = 0.0
	continuous_time_in_danger_low_s = 0.0
	continuous_time_in_danger_high_s = 0.0
	game_is_running = false
	final_game_outcome = {"reason": "none", "winner_id": 0}
	stabilize_effect_end_time_ms = 0
	active_event = {"type": Config.EventType.NONE, "end_time_ms": 0}
	event_check_timer.stop(); event_duration_timer.stop()
	for player_id in players:
		if players.has(player_id) and players[player_id]: players[player_id].reset()
	emit_signal("game_reset_triggered")

func _process(delta: float):
	if not game_is_running: return
	var now_ms = Time.get_ticks_msec()
	var current_decay_rate = Config.BASE_ENERGY_DECAY_RATE
	var stabilize_active = stabilize_effect_end_time_ms > now_ms
	var was_stabilize_active = stabilize_active
	if stabilize_active and now_ms >= stabilize_effect_end_time_ms:
		stabilize_effect_end_time_ms = 0; stabilize_active = false
		if was_stabilize_active: _emit_stabilize_state()
	if stabilize_active: current_decay_rate *= Config.STABILIZE_DECAY_MULTIPLIER
	elif active_event.type == Config.EventType.SURGE and active_event.end_time_ms > now_ms:
		current_decay_rate *= Config.EVENT_SURGE_DECAY_MULTIPLIER
	energy_level = clampf(energy_level - (current_decay_rate * delta), Config.MIN_ENERGY, Config.MAX_ENERGY)
	var in_safe_zone = energy_level >= Config.SAFE_ZONE_MIN and energy_level <= Config.SAFE_ZONE_MAX
	var in_danger_low = energy_level < Config.DANGER_LOW_THRESHOLD
	var in_danger_high = energy_level > Config.DANGER_HIGH_THRESHOLD
	if in_safe_zone: cumulative_stable_time_s += delta; continuous_time_in_danger_low_s = 0.0; continuous_time_in_danger_high_s = 0.0
	elif in_danger_low: continuous_time_in_danger_low_s += delta; continuous_time_in_danger_high_s = 0.0
	elif in_danger_high: continuous_time_in_danger_high_s += delta; continuous_time_in_danger_low_s = 0.0
	else: continuous_time_in_danger_low_s = 0.0; continuous_time_in_danger_high_s = 0.0
	var game_over_reason = "none"; var winner_id = 0
	if cumulative_stable_time_s >= Config.COOP_WIN_DURATION_SECONDS: game_over_reason = "coopWin"
	elif continuous_time_in_danger_low_s >= Config.DANGER_TIME_LIMIT_SECONDS: game_over_reason = "shutdown"
	elif continuous_time_in_danger_high_s >= Config.DANGER_TIME_LIMIT_SECONDS: game_over_reason = "meltdown"
	if game_over_reason != "none": _trigger_game_over(game_over_reason, winner_id); return
	_emit_game_state_update()

func _emit_game_state_update():
	emit_signal("game_state_updated", _get_current_state_snapshot())

func _emit_player_state_update(player_id: int):
	if players.has(player_id) and is_instance_valid(players[player_id]):
		var player_state: PlayerState = players[player_id]
		emit_signal("player_state_updated", player_id, player_state.get_state_data())
		player_state.clear_temp_status()
	else:
		printerr("GameManager Error: Tried to emit update for invalid player ID or state: %d" % player_id)

func _emit_event_state(): emit_signal("event_updated", active_event)
func _emit_stabilize_state():
	emit_signal("stabilize_effect_updated", {
		"active": stabilize_effect_end_time_ms > Time.get_ticks_msec(),
		"end_time_ms": stabilize_effect_end_time_ms
	})
func _emit_full_game_state():
	_emit_game_state_update(); _emit_event_state(); _emit_stabilize_state()

func _get_current_state_snapshot() -> Dictionary:
	var all_player_ids = players.keys(); all_player_ids.sort()
	return {
		"energyLevel": energy_level, "playerIds": all_player_ids, "playerCount": all_player_ids.size(),
		"coopWinTargetSeconds": Config.COOP_WIN_DURATION_SECONDS, "coopWinProgressSeconds": cumulative_stable_time_s,
		"gameIsRunning": game_is_running, "finalOutcomeReason": final_game_outcome.reason, "finalOutcomeWinner": final_game_outcome.winner_id,
		"stashWinTarget": Config.STASH_WIN_TARGET, "playerStashes": _get_all_player_stashes(),
		"safeZoneMin": Config.SAFE_ZONE_MIN, "safeZoneMax": Config.SAFE_ZONE_MAX,
		"dangerLow": Config.DANGER_LOW_THRESHOLD, "dangerHigh": Config.DANGER_HIGH_THRESHOLD,
		"dangerLowProgressSeconds": continuous_time_in_danger_low_s, "dangerHighProgressSeconds": continuous_time_in_danger_high_s,
		"dangerTimeLimitSeconds": Config.DANGER_TIME_LIMIT_SECONDS,
		"activeEventType": active_event.type, # Added for background switching
		"stabilizeEffectActive": stabilize_effect_end_time_ms > Time.get_ticks_msec() # Added for background
	}
func _get_all_player_stashes() -> Dictionary:
	var stashes = {}; for pid in players:
		if players.has(pid) and is_instance_valid(players[pid]): stashes[pid] = players[pid].personal_stash
	return stashes

func _on_event_check_timer_timeout():
	if not game_is_running or active_event.type != Config.EventType.NONE: return
	if stabilize_effect_end_time_ms > Time.get_ticks_msec(): return
	if randf() * 100.0 <= Config.EVENT_CHANCE_PERCENT:
		var chosen_type = Config.EVENT_TYPES[randi() % Config.EVENT_TYPES.size()]
		var now_ms = Time.get_ticks_msec()
		active_event = {"type": chosen_type, "end_time_ms": now_ms + Config.EVENT_DURATION_MS}
		event_duration_timer.wait_time = Config.EVENT_DURATION_MS / 1000.0; event_duration_timer.start()
		print("--- EVENT TRIGGERED: ", Config.EventType.keys()[chosen_type], " ---"); _emit_event_state()

func _on_event_duration_timer_timeout():
	if active_event.type != Config.EventType.NONE:
		print("--- EVENT ENDED: ", Config.EventType.keys()[active_event.type], " ---")
		active_event = {"type": Config.EventType.NONE, "end_time_ms": 0}; _emit_event_state()

func _trigger_game_over(reason: String, winner: int = 0):
	if not game_is_running: return
	print("!!! GAME OVER: Reason=%s, Winner=%d !!!" % [reason, winner])
	game_is_running = false; final_game_outcome = {"reason": reason, "winner_id": winner}
	event_check_timer.stop(); event_duration_timer.stop()
	if active_event.type != Config.EventType.NONE:
		active_event = {"type": Config.EventType.NONE, "end_time_ms": 0}; _emit_event_state()
	emit_signal("game_over_triggered", final_game_outcome); _emit_game_state_update()

func _on_player_action_received(player_id: int, action: String):
	if player_id <= 0 or player_id > NUM_PLAYERS:
		printerr("GM: Invalid player ID %d for action %s." % [player_id, action]); return
	if not players.has(player_id) or not is_instance_valid(players[player_id]):
		printerr("GM: No state for player ID %d, action %s ignored." % [player_id, action]); return
	var player_state: PlayerState = players[player_id]
	if player_state.is_eliminated:
		print("GM: Action %s from player %d ignored (eliminated)." % [action, player_id]); return
	emit_signal("player_action_visual_feedback", player_id, action)
	if not game_is_running:
		print("GM: Action %s from player %d ignored (game not running)." % [action, player_id]); return
	match action:
		"generate": _handle_player_action_generate(player_id)
		"stabilize": _handle_player_action_stabilize(player_id)
		"stealGrid": _handle_player_action_stealGrid(player_id)
		"emergencyAdjust": _handle_player_action_emergencyAdjust(player_id)
		_:
			printerr("GM: Unknown action '%s' from player %d." % [action, player_id])
			players[player_id].set_temp_status(TextDB.STATUS_UNKNOWN_CMD)
			_emit_player_state_update(player_id)

func _handle_player_action_generate(player_id: int):
	var now_ms = Time.get_ticks_msec(); var current_gain = Config.BASE_ENERGY_GAIN_PER_CLICK
	var stabilize_active = stabilize_effect_end_time_ms > now_ms
	var event_efficiency_active = active_event.type == Config.EventType.EFFICIENCY and active_event.end_time_ms > now_ms
	if stabilize_active: current_gain *= Config.STABILIZE_GAIN_MULTIPLIER
	elif event_efficiency_active: current_gain *= Config.EVENT_EFFICIENCY_GAIN_MULTIPLIER
	energy_level = clampf(energy_level + current_gain, Config.MIN_ENERGY, Config.MAX_ENERGY)

func _handle_player_action_stabilize(player_id: int):
	var player_state: PlayerState = players[player_id]; var now_ms = Time.get_ticks_msec()
	if now_ms >= player_state.stabilize_cooldown_end_ms:
		stabilize_effect_end_time_ms = now_ms + Config.STABILIZE_DURATION_MS
		player_state.stabilize_cooldown_end_ms = now_ms + Config.STABILIZE_COOLDOWN_MS
		player_state.set_temp_status(TextDB.STATUS_STABILIZED)
		_emit_stabilize_state(); _emit_player_state_update(player_id)
	else:
		player_state.set_temp_status(TextDB.STATUS_STABILIZE_CD)
		_emit_player_state_update(player_id)

func _handle_player_action_stealGrid(player_id: int):
	var player_state: PlayerState = players[player_id]; var now_ms = Time.get_ticks_msec()
	if now_ms < player_state.steal_grid_cooldown_end_ms:
		player_state.set_temp_status(TextDB.STATUS_STEAL_CD); _emit_player_state_update(player_id); return
	if energy_level < Config.STEAL_GRID_COST:
		player_state.set_temp_status(TextDB.STATUS_LOW_GRID); _emit_player_state_update(player_id); return
	if randf() * 100.0 < Config.STEAL_ELECTROCUTION_CHANCE_PERCENT:
		player_state.eliminate_player()
		player_state.set_temp_status(TextDB.STATUS_ELECTROCUTED)
		_emit_player_state_update(player_id)
		_check_elimination_game_over_conditions(); return
	energy_level = max(Config.MIN_ENERGY, energy_level - Config.STEAL_GRID_COST)
	player_state.personal_stash += Config.STEAL_STASH_GAIN
	player_state.steal_grid_cooldown_end_ms = now_ms + Config.STEAL_COOLDOWN_MS
	player_state.set_temp_status(TextDB.STATUS_STOLE_AMOUNT % Config.STEAL_STASH_GAIN)
	_emit_player_state_update(player_id)
	if player_state.personal_stash >= Config.STASH_WIN_TARGET:
		_trigger_game_over("individualWin", player_id)

func _handle_player_action_emergencyAdjust(player_id: int):
	var player_state: PlayerState = players[player_id]; var now_ms = Time.get_ticks_msec()
	if now_ms < player_state.emergency_adjust_cooldown_end_ms:
		player_state.set_temp_status(TextDB.STATUS_EMERGENCY_CD); _emit_player_state_update(player_id); return
	var energy_change: float = 0.0; var feedback_msg_key = TextDB.STATUS_MISUSED
	if energy_level < Config.DANGER_LOW_THRESHOLD:
		energy_change = Config.EMERGENCY_BOOST_AMOUNT; feedback_msg_key = TextDB.STATUS_BOOST_USED
	elif energy_level > Config.DANGER_HIGH_THRESHOLD:
		energy_change = -Config.EMERGENCY_COOLANT_AMOUNT; feedback_msg_key = TextDB.STATUS_COOLANT_USED
	else: # Misused
		if energy_level < (Config.SAFE_ZONE_MIN + Config.SAFE_ZONE_MAX) / 2.0:
			energy_change = -Config.EMERGENCY_PENALTY_WRONG_ZONE
		else: energy_change = Config.EMERGENCY_PENALTY_WRONG_ZONE
	energy_level = clampf(energy_level + energy_change, Config.MIN_ENERGY, Config.MAX_ENERGY)
	player_state.emergency_adjust_cooldown_end_ms = now_ms + Config.EMERGENCY_ADJUST_COOLDOWN_MS
	player_state.set_temp_status(feedback_msg_key)
	_emit_player_state_update(player_id)

func _check_elimination_game_over_conditions():
	if not game_is_running: return
	var active_players_count = 0; var last_active_player_id = 0
	for pid in players:
		var p_state: PlayerState = players[pid]
		if not p_state.is_eliminated: active_players_count += 1; last_active_player_id = pid
	if active_players_count == 0 and NUM_PLAYERS > 0:
		_trigger_game_over("allEliminated")
	elif active_players_count == 1 and NUM_PLAYERS > 1:
		_trigger_game_over("lastPlayerStanding", last_active_player_id)

func handle_reset_request(): # Called from Display if a reset button is ever added there
	if not game_is_running: print("GM: Reset approved."); start_game()
	else: print("GM: Reset denied, game still running.")
