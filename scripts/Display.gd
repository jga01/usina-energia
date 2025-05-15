# File: res://scripts/Display.gd
extends Control

@onready var energy_bar: ProgressBar = $VBoxContainer/EnergyBarContainer/EnergyBar
@onready var energy_level_text: Label = $VBoxContainer/EnergyLevelText
@onready var status_text: Label = $VBoxContainer/StatusText # Central status
@onready var coop_progress_text: Label = $VBoxContainer/CoopProgressText
@onready var event_alert_label: Label = $VBoxContainer/EventAlertLabel
@onready var power_grid_status_title_label: Label = $VBoxContainer/PowerGridStatusLabel # Added @onready for title
@onready var game_manager: Node = $GameManager
@onready var player_indicators_parent: Control = $PlayerIndicatorsParent
@onready var background_sprite: Sprite2D = $"Usina-normal" # Accessing node with hyphen

const PlayerIndicatorScene = preload("res://scenes/PlayerIndicator.tscn")
const GameOverScreenScene = preload("res://scenes/GameOverScreen.tscn")

var player_indicators: Dictionary = {}
var last_global_state: Dictionary = {}
var event_alert_timer: Timer = Timer.new()
const INDICATOR_MARGIN = 10.0

# Background texture management
var background_textures: Dictionary = {
	"stable": preload("res://assets/usina-normal.jpeg"), # Ensure this path is correct
	"warning_low": preload("res://assets/usina-warning-low.jpeg"),
	"warning_high": preload("res://assets/usina-warning-high.jpeg"),
	"danger_low": preload("res://assets/usina-danger-shutdown.jpeg"),
	"danger_high": preload("res://assets/usina-danger-meltdown.jpeg"),
	"event_surge": preload("res://assets/usina-event-surge.jpeg"),
	"event_efficiency": preload("res://assets/usina-event-efficiency.jpeg"),
	"game_over": preload("res://assets/usina-gameover.jpeg") # A generic game over background
}
var current_background_key: String = "stable"


func _ready():
	add_child(event_alert_timer)
	event_alert_timer.one_shot = true
	event_alert_timer.timeout.connect(_on_event_alert_timer_timeout)

	# Set initial static text from TextDB
	if is_instance_valid(power_grid_status_title_label):
		power_grid_status_title_label.text = TextDB.DISPLAY_POWER_GRID_STATUS_TITLE
	if is_instance_valid(status_text):
		status_text.text = TextDB.DISPLAY_STATUS_WAITING
	if is_instance_valid(coop_progress_text):
		coop_progress_text.text = TextDB.DISPLAY_STABILITY_GOAL_WAITING
	if is_instance_valid(energy_level_text):
		energy_level_text.text = TextDB.DISPLAY_ENERGY_LEVEL_PERCENT % 50 # Initial placeholder

	var game_manager_valid = is_instance_valid(game_manager)
	if not game_manager_valid:
		printerr("Display Error: GameManager node not found!")
	else:
		_connect_game_manager_signals()

	if is_instance_valid(event_alert_label):
		event_alert_label.hide()

	_create_player_indicators()

	# Set initial background
	if is_instance_valid(background_sprite) and background_textures.has("stable"):
		background_sprite.texture = background_textures["stable"]
		current_background_key = "stable"


func _connect_game_manager_signals():
	if not is_instance_valid(game_manager):
		printerr("Display Error: GameManager invalid when connecting signals.")
		return
	# Ensure connections are not duplicated if scene is reloaded (though less likely for Display)
	if not game_manager.game_state_updated.is_connected(_on_game_state_updated):
		game_manager.game_state_updated.connect(_on_game_state_updated)
	if not game_manager.player_state_updated.is_connected(_on_player_state_updated):
		game_manager.player_state_updated.connect(_on_player_state_updated)
	if not game_manager.game_over_triggered.is_connected(_on_game_over_triggered):
		game_manager.game_over_triggered.connect(_on_game_over_triggered)
	if not game_manager.game_reset_triggered.is_connected(_on_game_reset_triggered):
		game_manager.game_reset_triggered.connect(_on_game_reset_triggered)
	if not game_manager.event_updated.is_connected(_on_event_updated):
		game_manager.event_updated.connect(_on_event_updated)
	if not game_manager.stabilize_effect_updated.is_connected(_on_stabilize_effect_updated):
		game_manager.stabilize_effect_updated.connect(_on_stabilize_effect_updated)
	if not game_manager.player_action_visual_feedback.is_connected(_on_player_action_visual_feedback):
		game_manager.player_action_visual_feedback.connect(_on_player_action_visual_feedback)

func _create_player_indicators():
	if is_instance_valid(player_indicators_parent):
		for child in player_indicators_parent.get_children():
			child.queue_free()
	player_indicators.clear()

	var num_players = Config.NUM_PLAYERS
	for i in range(1, num_players + 1):
		var indicator_instance = PlayerIndicatorScene.instantiate()
		if indicator_instance:
			if is_instance_valid(player_indicators_parent):
				player_indicators_parent.add_child(indicator_instance)
				indicator_instance.name = "PlayerIndicator_%d" % i
				indicator_instance.set_player_id(i)
				player_indicators[i] = indicator_instance
			else:
				printerr("Display Error: PlayerIndicatorsParent node is not valid!")
		else:
			printerr("Display Error: Failed to instantiate PlayerIndicatorScene!")
	call_deferred("_position_indicators")

func _position_indicators():
	if not is_instance_valid(player_indicators_parent):
		printerr("Display Error: Cannot position indicators, parent node invalid.")
		return

	var parent_size = player_indicators_parent.size # Use parent's size for positioning
	var num_players_created = player_indicators.size()

	for i in range(1, num_players_created + 1):
		if player_indicators.has(i):
			var indicator_control = player_indicators[i] as Control
			if not is_instance_valid(indicator_control): continue

			var indicator_size = indicator_control.size
			# Await a frame if size is zero initially, common issue.
			if indicator_size == Vector2.ZERO:
				await get_tree().process_frame
				indicator_size = indicator_control.size
				if indicator_size == Vector2.ZERO: # Still zero, try custom_minimum_size
					indicator_size = indicator_control.custom_minimum_size
					if indicator_size == Vector2.ZERO: # Last resort, log and skip precise positioning
						printerr("Display Warning: Indicator %d size is zero after attempts, cannot position accurately." % i)
						continue # Skip positioning for this indicator

			# Positioning logic (example, adjust to your desired layout)
			match i:
				1: indicator_control.position = Vector2(INDICATOR_MARGIN, INDICATOR_MARGIN) # Top-left
				2: indicator_control.position = Vector2(parent_size.x - indicator_size.x - INDICATOR_MARGIN, INDICATOR_MARGIN) # Top-right
				3: indicator_control.position = Vector2(INDICATOR_MARGIN, parent_size.y - indicator_size.y - INDICATOR_MARGIN) # Bottom-left
				4: indicator_control.position = Vector2(parent_size.x - indicator_size.x - INDICATOR_MARGIN, parent_size.y - indicator_size.y - INDICATOR_MARGIN) # Bottom-right
				_: # Fallback for more than 4 players, stacks them down left side
					indicator_control.position = Vector2(INDICATOR_MARGIN, INDICATOR_MARGIN + ((i-1) * (indicator_size.y + 5)))


func _update_energy_display(level: float, is_running: bool, state_data: Dictionary):
	if not is_instance_valid(energy_level_text) or \
	   not is_instance_valid(energy_bar) or \
	   not is_instance_valid(status_text):
		return

	energy_level_text.text = TextDB.DISPLAY_ENERGY_LEVEL_PERCENT % round(level)
	energy_bar.value = level

	var fill_stylebox = energy_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	var bg_stylebox = energy_bar.get_theme_stylebox("background").duplicate() as StyleBoxFlat
	var bar_color = Color.GRAY
	var current_status_message = TextDB.DISPLAY_STATUS_WAITING
	var new_bg_key = "stable" # Default background key

	if is_running:
		status_text.remove_theme_color_override("font_color") # Reset color
		var danger_low = state_data.get("dangerLow", Config.DANGER_LOW_THRESHOLD)
		var safe_min = state_data.get("safeZoneMin", Config.SAFE_ZONE_MIN)
		var safe_max = state_data.get("safeZoneMax", Config.SAFE_ZONE_MAX)
		var danger_high = state_data.get("dangerHigh", Config.DANGER_HIGH_THRESHOLD)
		var active_game_event_type = state_data.get("activeEventType", Config.EventType.NONE)
		var stabilize_active = state_data.get("stabilizeEffectActive", false)

		# Determine background and status based on events first, then energy levels
		if active_game_event_type == Config.EventType.SURGE:
			new_bg_key = "event_surge"
		elif active_game_event_type == Config.EventType.EFFICIENCY:
			new_bg_key = "event_efficiency"
		elif stabilize_active:
			new_bg_key = "stable" # Or a specific "stabilized" background if you add one
		# If no special event/effect, determine by energy level
		else:
			if level < danger_low:
				bar_color = Color.DARK_RED; current_status_message = TextDB.DISPLAY_STATUS_DANGER_MELTDOWN # Or shutdown for low
				new_bg_key = "danger_low"
			elif level < safe_min:
				bar_color = Color.ORANGE; current_status_message = TextDB.DISPLAY_STATUS_WARNING_LOW_POWER
				new_bg_key = "warning_low"
			elif level <= safe_max:
				bar_color = Color.LIME_GREEN; current_status_message = TextDB.DISPLAY_STATUS_STABLE
				new_bg_key = "stable"
			elif level < danger_high:
				bar_color = Color.YELLOW; current_status_message = TextDB.DISPLAY_STATUS_WARNING_HIGH_POWER
				new_bg_key = "warning_high"
			else: # level >= danger_high
				bar_color = Color.RED; current_status_message = TextDB.DISPLAY_STATUS_DANGER_OVERLOAD
				new_bg_key = "danger_high"
	else: # Game not running
		bar_color = Color.GRAY
		var final_reason = state_data.get("finalOutcomeReason", "none")
		if final_reason == "none":
			current_status_message = TextDB.DISPLAY_STATUS_WAITING
			new_bg_key = "stable" # Or game_over if preferred immediately
		else:
			# Status message for game over is handled by coop_progress_text typically
			# Or you can set a generic "Game Over" here
			current_status_message = TextDB.GO_TITLE_GAME_OVER_DEFAULT
			new_bg_key = "game_over" # Or specific based on reason
			if final_reason == "shutdown": new_bg_key = "danger_low"
			elif final_reason == "meltdown": new_bg_key = "danger_high"


	status_text.text = current_status_message

	# Update background sprite texture
	if is_instance_valid(background_sprite) and background_textures.has(new_bg_key):
		if current_background_key != new_bg_key: # Only change if different
			background_sprite.texture = background_textures[new_bg_key]
			current_background_key = new_bg_key
	elif is_instance_valid(background_sprite):
		printerr("Display: Missing background texture for key: ", new_bg_key)


	if fill_stylebox:
		fill_stylebox.bg_color = bar_color
		energy_bar.add_theme_stylebox_override("fill", fill_stylebox)
	if bg_stylebox:
		bg_stylebox.bg_color = Color(0.2, 0.2, 0.2) if is_running else Color(0.1, 0.1, 0.1)
		energy_bar.add_theme_stylebox_override("background", bg_stylebox)


func _update_coop_progress(progress_seconds: float, target_seconds: float, is_running: bool, outcome_reason: String, winner_id: int):
	if not is_instance_valid(coop_progress_text): return

	if target_seconds > 0:
		var safe_progress = floor(progress_seconds)
		var safe_target = floor(target_seconds)
		var progress_percent = min(100, floor((progress_seconds / target_seconds) * 100)) if target_seconds > 0 else 0

		if is_running:
			coop_progress_text.text = TextDB.DISPLAY_STABILITY_GOAL % [safe_progress, safe_target, progress_percent]
		elif outcome_reason == "coopWin":
			coop_progress_text.text = TextDB.DISPLAY_STABILITY_GOAL_SUCCESS % [safe_target, safe_target]
		elif not is_running and outcome_reason != "none":
			var outcome_text_key = outcome_reason.capitalize() # Base for TextDB key
			var outcome_display_text = TextDB.DISPLAY_STABILITY_GOAL_FINAL_STATUS_PREFIX
			match outcome_reason:
				"individualWin": outcome_display_text += TextDB.DISPLAY_INDIVIDUAL_WIN_TEXT % winner_id
				"shutdown": outcome_display_text += TextDB.DISPLAY_GRID_SHUTDOWN_TEXT
				"meltdown": outcome_display_text += TextDB.DISPLAY_GRID_MELTDOWN_TEXT
				"allEliminated": outcome_display_text += TextDB.GO_TITLE_ALL_ELIMINATED # Using game over title for this display
				"lastPlayerStanding": outcome_display_text += TextDB.GO_TITLE_LAST_PLAYER_STANDING % (TextDB.GENERIC_PLAYER_LABEL_FORMAT % winner_id) # Assuming winner_id is player
				_: outcome_display_text += outcome_reason.capitalize() # Fallback
			coop_progress_text.text = outcome_display_text
		else: # Not running, no specific outcome (e.g., before game starts after reset)
			coop_progress_text.text = TextDB.DISPLAY_STABILITY_GOAL % [0, safe_target, 0]
	else:
		coop_progress_text.text = TextDB.DISPLAY_STABILITY_GOAL_WAITING

func _on_stabilize_effect_updated(stabilize_data: Dictionary):
	var is_active = stabilize_data.get("active", false)
	if is_instance_valid(energy_bar):
		energy_bar.modulate = Color(0.8, 1.0, 0.8, 1.0) if is_active else Color(1.0, 1.0, 1.0, 1.0)

func _on_game_state_updated(state_data: Dictionary):
	last_global_state = state_data
	_update_energy_display(state_data.get("energyLevel", 50.0), state_data.get("gameIsRunning", false), state_data)
	_update_coop_progress(
		state_data.get("coopWinProgressSeconds", 0.0),
		state_data.get("coopWinTargetSeconds", Config.COOP_WIN_DURATION_SECONDS),
		state_data.get("gameIsRunning", false),
		state_data.get("finalOutcomeReason", "none"),
		state_data.get("finalOutcomeWinner", 0)
	)
	for pid in player_indicators:
		var indicator = player_indicators.get(pid)
		if is_instance_valid(indicator): indicator.update_display({}, last_global_state)


func _on_player_state_updated(player_id: int, player_state_data: Dictionary):
	if player_indicators.has(player_id):
		var indicator = player_indicators[player_id]
		if is_instance_valid(indicator): indicator.update_display(player_state_data, last_global_state)
		else: printerr("Display Warning: Indicator node for player %d is invalid!" % player_id)
	else: printerr("Display Warning: Received update for unknown player ID %d" % player_id)


func _on_player_action_visual_feedback(player_id: int, action_name: String):
	if player_indicators.has(player_id):
		var indicator = player_indicators[player_id]
		if is_instance_valid(indicator): indicator.flash_button(action_name)
		else: printerr("Display Warning: Indicator for player %d invalid during visual feedback." % player_id)
	else: printerr("Display Warning: Received visual feedback for unknown player ID %d" % player_id)

func _on_game_over_triggered(outcome_data: Dictionary):
	print("Display received Game Over signal, transitioning to GameOverScreen. Outcome: ", outcome_data)
	if PlayerProfiles:
		PlayerProfiles.set_temp_game_outcome_data(outcome_data)
	else:
		printerr("Display Error: PlayerProfiles autoload not found. Cannot pass game outcome data.")
	get_tree().change_scene_to_file("res://scenes/GameOverScreen.tscn")


func _on_game_reset_triggered():
	print("Display received Game Reset.")
	if is_instance_valid(status_text):
		status_text.text = TextDB.DISPLAY_GAME_RESETTING
		status_text.remove_theme_color_override("font_color")
	if is_instance_valid(coop_progress_text):
		coop_progress_text.text = TextDB.DISPLAY_STABILITY_GOAL_WAITING
	
	_update_event_alert(Config.EventType.NONE, 0) # Clear event alert

	# Reset background
	if is_instance_valid(background_sprite) and background_textures.has("stable"):
		background_sprite.texture = background_textures["stable"]
		current_background_key = "stable"

	for pid in player_indicators:
		var indicator = player_indicators.get(pid)
		if is_instance_valid(indicator): indicator.reset_indicator()


func _on_event_updated(event_data: Dictionary):
	var event_type = event_data.get("type", Config.EventType.NONE)
	var end_time_ms = event_data.get("end_time_ms", 0)
	_update_event_alert(event_type, end_time_ms)

func _update_event_alert(type: Config.EventType, end_time_ms: int):
	if not is_instance_valid(event_alert_label): return
	if not event_alert_timer.is_stopped(): event_alert_timer.stop()

	if type != Config.EventType.NONE:
		var event_text_format = TextDB.EVENT_UNKNOWN_ALERT; var alert_color = Color.YELLOW
		match type:
			Config.EventType.SURGE: event_text_format = TextDB.EVENT_SURGE_ALERT; alert_color = Color.ORANGE_RED
			Config.EventType.EFFICIENCY: event_text_format = TextDB.EVENT_EFFICIENCY_ALERT; alert_color = Color.LIGHT_GREEN

		var time_left_ms = max(0, end_time_ms - Time.get_ticks_msec())
		var duration_s = time_left_ms / 1000.0

		if duration_s > 0.1:
			event_alert_label.text = event_text_format % ceil(duration_s)
			event_alert_label.add_theme_color_override("font_color", alert_color)
			event_alert_label.show()
			event_alert_timer.wait_time = duration_s
			event_alert_timer.start()
		else:
			event_alert_label.hide(); event_alert_label.remove_theme_color_override("font_color")
	else:
		event_alert_label.hide(); event_alert_label.remove_theme_color_override("font_color")

func _on_event_alert_timer_timeout():
	if is_instance_valid(event_alert_label):
		event_alert_label.hide(); event_alert_label.remove_theme_color_override("font_color")
