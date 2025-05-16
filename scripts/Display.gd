# File: res://scripts/Display.gd
extends Control

@onready var game_manager: Node = $GameManager
@onready var player_indicators_parent: Control = $PlayerIndicatorsParent
@onready var central_core_sprite: Sprite2D = $CenterContainer/CentralCoreSprite
@onready var core_animation_player: AnimationPlayer = $CenterContainer/CentralCoreSprite/AnimationPlayerCore
@onready var static_background: TextureRect = $StaticBackground

@onready var stability_goal_text: Label = $TopInfoContainer/StabilityGoalContainer/StabilityGoalText
@onready var stability_icon: TextureRect = $TopInfoContainer/StabilityGoalContainer/StabilityIcon

@onready var game_status_text: Label = $GameStatusText
@onready var danger_warning_label: Label = $DangerWarningLabel

@onready var event_notification_overlay: PanelContainer = $EventNotificationOverlay
@onready var event_title_label: Label = $EventNotificationOverlay/VBoxContainer/EventTitleLabel
@onready var event_description_label: Label = $EventNotificationOverlay/VBoxContainer/EventDescriptionLabel
@onready var electricity_flow_parent: Node2D = $ElectricityFlowParent
@onready var energy_progress_bar: ProgressBar = %EnergyProgressBar
@onready var event_particles_container: Node2D = $CenterContainer/CentralCoreSprite/EventParticlesContainer

const PlayerIndicatorScene = preload("res://scenes/PlayerIndicator.tscn")
const GameOverScreenScene = preload("res://scenes/GameOverScreen.tscn")

const SurgeParticles = preload("res://scenes/particles/SurgeParticles.tscn")
const EfficiencyParticles = preload("res://scenes/particles/EfficiencyParticles.tscn")
const UnstableGridParticles = preload("res://scenes/particles/SurgeParticles.tscn") # Assuming reuse is intentional

var player_indicators: Dictionary = {} # { player_id: PlayerIndicator_instance }
var last_global_state: Dictionary = {} # Cache last full game state
var current_event_particles: Node = null # To keep track of the current particle instance

const INDICATOR_MARGIN = 20.0

var core_textures: Dictionary = {
	"low": preload("res://assets/new/battery_normal.png"),
	"mid": preload("res://assets/new/battery_normal.png"),
	"high": preload("res://assets/new/battery_normal.png"),
	"danger_low": preload("res://assets/new/battery_normal.png"),
	"danger_high": preload("res://assets/new/battery_normal.png"),
	"event_surge": preload("res://assets/new/battery_surge.png"),
	"event_efficiency": preload("res://assets/new/battery_efficiency.png"),
	"event_unstable_grid": preload("res://assets/new/battery_surge.png"), # Reusing surge texture
	"stable": preload("res://assets/new/battery_normal.png"), # Default stable
	"game_over": preload("res://assets/new/battery_normal.png") # Game over texture
}
var stability_icons_textures: Dictionary = {
	"normal": preload("res://assets/new/hourglass.png"),
	"warning": preload("res://assets/new/hourglass.png"), # Could be a different color/icon
	"achieved": preload("res://assets/new/hourglass.png") # Could be a different color/icon
}

func _ready():
	if is_instance_valid(stability_icon) and stability_icons_textures.has("normal"):
		stability_icon.texture = stability_icons_textures["normal"]
	if is_instance_valid(game_status_text):
		game_status_text.text = TextDB.DISPLAY_STATUS_WAITING
	if is_instance_valid(stability_goal_text):
		stability_goal_text.text = TextDB.DISPLAY_STABILITY_GOAL_WAITING_SIMPLE

	if not is_instance_valid(game_manager):
		printerr("Display Error: GameManager node not found!")
	else:
		_connect_game_manager_signals()

	if is_instance_valid(event_notification_overlay):
		event_notification_overlay.hide()
	if is_instance_valid(danger_warning_label):
		danger_warning_label.hide()

	_create_player_indicators()

	if is_instance_valid(energy_progress_bar):
		energy_progress_bar.max_value = Config.MAX_ENERGY
		energy_progress_bar.value = Config.MAX_ENERGY / 2.0 # Initial value

	_update_central_core_display(Config.MAX_ENERGY / 2.0, false, {}) # Initial call
	_clear_event_particles() # Ensure no particles at start


func _connect_game_manager_signals():
	if not is_instance_valid(game_manager):
		printerr("Display Error: GameManager invalid when connecting signals.")
		return
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
				indicator_instance.set_player_id(i) # Important for portrait loading
				player_indicators[i] = indicator_instance
			else:
				printerr("Display Error: PlayerIndicatorsParent node is not valid!")
		else:
			printerr("Display Error: Failed to instantiate PlayerIndicatorScene!")
	call_deferred("_position_indicators") # Position after they are added and sizes are calculated

func _position_indicators():
	if not is_instance_valid(player_indicators_parent):
		printerr("Display Error: Cannot position indicators, parent node invalid.")
		return

	var parent_size = player_indicators_parent.size # This is the full screen size
	var num_players_created = player_indicators.size()

	for i in range(1, num_players_created + 1):
		if player_indicators.has(i):
			var indicator_control = player_indicators[i] as Control
			if not is_instance_valid(indicator_control): continue

			var indicator_size = indicator_control.size
			# Wait a frame if size is zero, then try again, then fallback
			if indicator_size == Vector2.ZERO:
				await get_tree().process_frame 
				indicator_size = indicator_control.size 
				if indicator_size == Vector2.ZERO:
					indicator_size = indicator_control.custom_minimum_size 
					if indicator_size == Vector2.ZERO:
						printerr("Display Warning: Indicator %d size is zero, cannot position accurately. Using fallback." % i)
						indicator_size = Vector2(160,190) # Fallback based on PlayerIndicator.tscn min_size
			
			match i:
				1: indicator_control.position = Vector2(INDICATOR_MARGIN, INDICATOR_MARGIN) # Top-left
				2: indicator_control.position = Vector2(parent_size.x - indicator_size.x - INDICATOR_MARGIN, INDICATOR_MARGIN) # Top-right
				3: indicator_control.position = Vector2(INDICATOR_MARGIN, parent_size.y - indicator_size.y - INDICATOR_MARGIN) # Bottom-left
				4: indicator_control.position = Vector2(parent_size.x - indicator_size.x - INDICATOR_MARGIN, parent_size.y - indicator_size.y - INDICATOR_MARGIN) # Bottom-right
				_: # Fallback for more than 4 players, though NUM_PLAYERS is likely 4
					indicator_control.position = Vector2(INDICATOR_MARGIN, INDICATOR_MARGIN + ((i-1) * (indicator_size.y + 5)))


func _update_central_core_display(level: float, is_running: bool, state_data: Dictionary):
	if not is_instance_valid(central_core_sprite) or \
	   not is_instance_valid(game_status_text) or \
	   not is_instance_valid(energy_progress_bar):
		return
	
	var current_status_message = TextDB.DISPLAY_STATUS_WAITING
	var new_core_texture_key = "stable" 
	var core_modulate = Color.WHITE # Default modulation

	if is_running:
		var danger_low_thresh = state_data.get("dangerLow", Config.DANGER_LOW_THRESHOLD)
		var safe_min = state_data.get("safeZoneMin", Config.SAFE_ZONE_MIN)
		var safe_max = state_data.get("safeZoneMax", Config.SAFE_ZONE_MAX)
		var danger_high_thresh = state_data.get("dangerHigh", Config.DANGER_HIGH_THRESHOLD)
		var active_game_event_type = state_data.get("activeEventType", Config.EventType.NONE)
		var inactivity_penalty = state_data.get("inactivityPenaltyActive", false)

		energy_progress_bar.visible = true
		if active_game_event_type == Config.EventType.SURGE:
			new_core_texture_key = "event_surge"
			current_status_message = TextDB.EVENT_SURGE_STATUS
		elif active_game_event_type == Config.EventType.EFFICIENCY:
			new_core_texture_key = "event_efficiency"
			current_status_message = TextDB.EVENT_EFFICIENCY_STATUS
		elif active_game_event_type == Config.EventType.UNSTABLE_GRID:
			new_core_texture_key = "event_unstable_grid"
			current_status_message = TextDB.EVENT_UNSTABLE_GRID_STATUS
		else: # No major event, check normal levels
			if is_instance_valid(core_animation_player) and core_animation_player.is_playing(): core_animation_player.stop()

			if level < danger_low_thresh:
				new_core_texture_key = "danger_low"; current_status_message = TextDB.DISPLAY_STATUS_DANGER_SHUTDOWN_IMMINENT
			elif level < safe_min:
				new_core_texture_key = "low"; current_status_message = TextDB.DISPLAY_STATUS_WARNING_LOW_POWER
			elif level <= safe_max:
				new_core_texture_key = "stable"; current_status_message = TextDB.DISPLAY_STATUS_STABLE
			elif level < danger_high_thresh:
				new_core_texture_key = "high"; current_status_message = TextDB.DISPLAY_STATUS_WARNING_HIGH_POWER
			else:
				new_core_texture_key = "danger_high"; current_status_message = TextDB.DISPLAY_STATUS_DANGER_MELTDOWN_IMMINENT
		
		# Inactivity penalty status message override (if no major event or critical countdowns)
		var in_danger_low_countdown_status = state_data.get("dangerLowProgressSeconds", 0.0) > 0.0
		var in_danger_high_countdown_status = state_data.get("dangerHighProgressSeconds", 0.0) > 0.0
		if inactivity_penalty and active_game_event_type == Config.EventType.NONE and not (in_danger_low_countdown_status or in_danger_high_countdown_status) :
			current_status_message = TextDB.DISPLAY_INACTIVITY_WARNING # Overrides normal status
			# Optionally, change core texture for inactivity too
			# new_core_texture_key = "event_unstable_grid" # e.g., reuse a "stressed" texture
				
	else: # Game not running
		var final_reason = state_data.get("finalOutcomeReason", "none")
		if final_reason == "none": # Game hasn't started or was reset without a definitive end
			current_status_message = TextDB.DISPLAY_STATUS_WAITING
			new_core_texture_key = "stable"
		else: # Game ended with a specific outcome
			current_status_message = TextDB.GO_TITLE_GAME_OVER_DEFAULT # Generic game over, more details on GameOverScreen
			new_core_texture_key = "game_over"
		energy_progress_bar.visible = true # Show bar, but it will be at 0 or reflecting final state
		energy_progress_bar.value = 0 # Or state_data.get("energyLevel", 0) if you want to show final level
	
	game_status_text.text = current_status_message
	if core_textures.has(new_core_texture_key):
		central_core_sprite.texture = core_textures[new_core_texture_key]
	else:
		printerr("Display: Missing core texture for key: ", new_core_texture_key)
		if core_textures.has("stable"): central_core_sprite.texture = core_textures["stable"] # Fallback
	
	central_core_sprite.modulate = core_modulate

	# Update Danger Warning Label (for countdowns and inactivity)
	if is_instance_valid(danger_warning_label):
		var in_danger_low_countdown = state_data.get("dangerLowProgressSeconds", 0.0) > 0.0
		var in_danger_high_countdown = state_data.get("dangerHighProgressSeconds", 0.0) > 0.0
		var inactivity_penalty_for_warning = state_data.get("inactivityPenaltyActive", false)

		if is_running: # Only show these warnings if the game is actively running
			if in_danger_low_countdown:
				var time_limit = Config.DANGER_TIME_LIMIT_SECONDS
				var remaining_low = time_limit - state_data.get("dangerLowProgressSeconds", 0.0)
				danger_warning_label.text = TextDB.DISPLAY_DANGER_SHUTDOWN_COUNTDOWN % snapped(remaining_low, 0.1)
				danger_warning_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2, 1)) # Danger Red
				danger_warning_label.show()
			elif in_danger_high_countdown:
				var time_limit = Config.DANGER_TIME_LIMIT_SECONDS
				var remaining_high = time_limit - state_data.get("dangerHighProgressSeconds", 0.0)
				danger_warning_label.text = TextDB.DISPLAY_DANGER_MELTDOWN_COUNTDOWN % snapped(remaining_high, 0.1)
				danger_warning_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2, 1)) # Danger Red

				danger_warning_label.show()
			elif inactivity_penalty_for_warning: # Show inactivity warning if no other critical countdowns
				danger_warning_label.text = TextDB.DISPLAY_INACTIVITY_WARNING
				danger_warning_label.add_theme_color_override("font_color", Color(1, 0.6, 0.2, 1)) # Warning Orange
				danger_warning_label.show()
			else: # No countdowns, no inactivity penalty
				danger_warning_label.hide()
		else: # Game not running, hide all such warnings
			danger_warning_label.hide()

	# Update Energy Progress Bar
	energy_progress_bar.value = level
	var bar_fill_color = Color.GRAY # Default if game not running or state undefined

	if is_running:
		var active_event_for_bar = state_data.get("activeEventType", Config.EventType.NONE)
		var danger_low_thresh_bar = state_data.get("dangerLow", Config.DANGER_LOW_THRESHOLD)
		var safe_min_bar = state_data.get("safeZoneMin", Config.SAFE_ZONE_MIN)
		var safe_max_bar = state_data.get("safeZoneMax", Config.SAFE_ZONE_MAX)
		var danger_high_thresh_bar = state_data.get("dangerHigh", Config.DANGER_HIGH_THRESHOLD)

		if active_event_for_bar == Config.EventType.SURGE:
			bar_fill_color = Color(0.9, 0.4, 0.1, 0.9) # Orange-Red for Surge
		elif active_event_for_bar == Config.EventType.EFFICIENCY:
			bar_fill_color = Color(0.2, 0.7, 0.9, 0.9) # Bright Blue for Efficiency
		elif active_event_for_bar == Config.EventType.UNSTABLE_GRID:
			bar_fill_color = Color(0.6, 0.2, 0.8, 0.9) # Purple for Unstable
		else: # No major event, color based on energy level
			if level < danger_low_thresh_bar:
				bar_fill_color = Color(0.9, 0.1, 0.1, 0.9) # Dark Red (Danger Low)
			elif level < safe_min_bar:
				bar_fill_color = Color(0.9, 0.8, 0.2, 0.9) # Yellow (Warning Low)
			elif level <= safe_max_bar:
				bar_fill_color = Color(0.2, 0.8, 0.2, 0.9) # Green (Safe)
			elif level < danger_high_thresh_bar:
				bar_fill_color = Color(0.9, 0.8, 0.2, 0.9) # Yellow (Warning High)
			else: # level >= danger_high_thresh_bar
				bar_fill_color = Color(0.9, 0.1, 0.1, 0.9) # Dark Red (Danger High)

	# Apply bar color
	var fill_stylebox = energy_progress_bar.get_theme_stylebox("fill")
	if fill_stylebox is StyleBoxFlat:
		fill_stylebox.bg_color = bar_fill_color
	else: # Fallback if stylebox is not flat or not set, create one
		var new_fill_stylebox = StyleBoxFlat.new()
		new_fill_stylebox.bg_color = bar_fill_color
		energy_progress_bar.add_theme_stylebox_override("fill", new_fill_stylebox)


func _update_coop_progress(progress_seconds: float, target_seconds: float, is_running: bool, outcome_reason: String, winner_id: int, energy_level: float):
	if not is_instance_valid(stability_goal_text) or not is_instance_valid(stability_icon): return

	if target_seconds > 0:
		var safe_progress = floor(progress_seconds)
		var safe_target = floor(target_seconds)

		if is_running:
			stability_goal_text.text = TextDB.DISPLAY_STABILITY_GOAL_SIMPLE % [safe_progress, safe_target]
			var in_safe_zone = energy_level >= Config.SAFE_ZONE_MIN and energy_level <= Config.SAFE_ZONE_MAX
			if in_safe_zone:
				if stability_icons_textures.has("normal"): stability_icon.texture = stability_icons_textures["normal"]
			else: # Not in safe zone, show warning icon
				if stability_icons_textures.has("warning"): stability_icon.texture = stability_icons_textures["warning"]
		elif outcome_reason == "coopWin":
			stability_goal_text.text = TextDB.DISPLAY_STABILITY_GOAL_SUCCESS_SIMPLE
			if stability_icons_textures.has("achieved"): stability_icon.texture = stability_icons_textures["achieved"]
		elif not is_running and outcome_reason != "none": # Game ended for other reasons
			var outcome_display_text = TextDB.DISPLAY_STABILITY_GOAL_FINAL_STATUS_PREFIX
			match outcome_reason:
				"individualWin": outcome_display_text += TextDB.DISPLAY_INDIVIDUAL_WIN_TEXT % winner_id
				"shutdown": outcome_display_text += TextDB.DISPLAY_GRID_SHUTDOWN_TEXT
				"meltdown": outcome_display_text += TextDB.DISPLAY_GRID_MELTDOWN_TEXT
				"allEliminated": outcome_display_text += TextDB.DISPLAY_ALL_ELIMINATED_TEXT
				"lastPlayerStanding": outcome_display_text += TextDB.DISPLAY_LAST_PLAYER_STANDING_TEXT % winner_id
				_: outcome_display_text += outcome_reason.capitalize() # Fallback for unhandled reasons
			stability_goal_text.text = outcome_display_text
			if stability_icons_textures.has("warning"): stability_icon.texture = stability_icons_textures["warning"] # Show warning icon for non-coop-win endings
		else: # Game not running, no definitive outcome yet (e.g., reset state)
			stability_goal_text.text = TextDB.DISPLAY_STABILITY_GOAL_SIMPLE % [0, safe_target]
			if stability_icons_textures.has("normal"): stability_icon.texture = stability_icons_textures["normal"]
	else: # Target seconds not set (e.g., before game starts)
		stability_goal_text.text = TextDB.DISPLAY_STABILITY_GOAL_WAITING_SIMPLE
		if stability_icons_textures.has("normal"): stability_icon.texture = stability_icons_textures["normal"]


func _on_game_state_updated(state_data: Dictionary):
	last_global_state = state_data # Cache the full state
	_update_central_core_display(state_data.get("energyLevel", 50.0), state_data.get("gameIsRunning", false), state_data)
	_update_coop_progress(
		state_data.get("coopWinProgressSeconds", 0.0),
		state_data.get("coopWinTargetSeconds", Config.COOP_WIN_DURATION_SECONDS),
		state_data.get("gameIsRunning", false),
		state_data.get("finalOutcomeReason", "none"),
		state_data.get("finalOutcomeWinner", 0),
		state_data.get("energyLevel", 50.0)
	)
	# Update all player indicators with their specific data from the map
	for pid in player_indicators:
		var indicator = player_indicators.get(pid)
		if is_instance_valid(indicator):
			var p_data_for_indicator = {} # Default to empty if no data for this player
			if state_data.has("player_data_map") and state_data.player_data_map.has(pid):
				p_data_for_indicator = state_data.player_data_map[pid]
			indicator.update_display(p_data_for_indicator, last_global_state) # Pass individual and global state


func _on_player_state_updated(player_id: int, player_state_data: Dictionary):
	# This signal is for more frequent, individual player updates if needed.
	# The main update logic is handled by _on_game_state_updated which includes all player data.
	# However, if GameManager emits this for specific player actions (like status text), we update here.
	if player_indicators.has(player_id):
		var indicator = player_indicators[player_id]
		if is_instance_valid(indicator):
			# We need the global state as well for context (like gameIsRunning for portraits)
			indicator.update_display(player_state_data, last_global_state)
		else:
			printerr("Display Warning: Indicator node for player %d is invalid!" % player_id)
	else:
		printerr("Display Warning: Received update for unknown player ID %d" % player_id)

func _on_player_action_visual_feedback(player_id: int, action_name: String):
	# Ensure player indicator and core sprite are valid
	if not player_indicators.has(player_id) or not is_instance_valid(central_core_sprite):
		return
	
	var player_indicator_node = player_indicators[player_id] as Control
	if not is_instance_valid(player_indicator_node): return

	# Calculate start and end positions for the line in global coordinates
	var start_pos_global = player_indicator_node.global_position + player_indicator_node.size / 2
	var end_pos_global = central_core_sprite.global_position
	
	var flow_color = Color.CYAN # Default for normal mash
	var target_pos_global = end_pos_global # Default target is core

	# Customize based on current event or action type
	var current_event = last_global_state.get("activeEventType", Config.EventType.NONE)
	var p_state = last_global_state.get("player_data_map",{}).get(player_id,{}) # Get player state
	var is_eliminated = p_state.get("is_eliminated", false)

	if current_event == Config.EventType.UNSTABLE_GRID and not is_eliminated:
		flow_color = Color.MEDIUM_PURPLE # Purple for unstable grid drain
		# Reverse direction for unstable grid: from core to player
		target_pos_global = start_pos_global 
		start_pos_global = end_pos_global    
	elif current_event == Config.EventType.EFFICIENCY:
		flow_color = Color.LIGHT_GREEN # Green for efficiency boost
	
	# Create and configure the Line2D
	var line = Line2D.new()
	line.add_point(electricity_flow_parent.to_local(start_pos_global)) # Convert to local space of parent
	line.add_point(electricity_flow_parent.to_local(target_pos_global))
	line.width = 5.0
	line.default_color = flow_color
	electricity_flow_parent.add_child(line) # Add to its dedicated parent node

	# Tween to fade out and then remove the line
	var tween = get_tree().create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.3).from(1.0).set_delay(0.1) 
	tween.tween_callback(line.queue_free) # Remove node after fade


func _on_game_over_triggered(outcome_data: Dictionary):
	print("Display received Game Over signal, transitioning. Outcome: ", outcome_data)
	_clear_event_particles() # Clear particles on game over
	if PlayerProfiles:
		PlayerProfiles.set_temp_game_outcome_data(outcome_data)
	else:
		printerr("Display Error: PlayerProfiles autoload not found. Cannot pass game outcome data.")
	
	if is_instance_valid(core_animation_player) and core_animation_player.is_playing():
		core_animation_player.stop()
	if is_instance_valid(central_core_sprite) and core_textures.has("game_over"):
		central_core_sprite.texture = core_textures["game_over"]

	get_tree().change_scene_to_file("res://scenes/GameOverScreen.tscn")


func _on_game_reset_triggered():
	print("Display received Game Reset.")
	_clear_event_particles() # Clear particles on reset
	if is_instance_valid(game_status_text):
		game_status_text.text = TextDB.DISPLAY_GAME_RESETTING
	if is_instance_valid(stability_goal_text):
		stability_goal_text.text = TextDB.DISPLAY_STABILITY_GOAL_WAITING_SIMPLE
	if is_instance_valid(stability_icon) and stability_icons_textures.has("normal"):
		stability_icon.texture = stability_icons_textures["normal"]
	if is_instance_valid(danger_warning_label):
		danger_warning_label.hide() # Hide warnings on reset
	
	_show_event_notification(Config.EventType.NONE, 0) # Clear event notification

	if is_instance_valid(central_core_sprite) and core_textures.has("stable"):
		central_core_sprite.texture = core_textures["stable"]
	if is_instance_valid(core_animation_player) and core_animation_player.is_playing():
		core_animation_player.stop()

	# Reset progress bar
	if is_instance_valid(energy_progress_bar):
		energy_progress_bar.value = Config.MAX_ENERGY / 2.0 # Reset to mid-value
		var reset_fill_stylebox = energy_progress_bar.get_theme_stylebox("fill")
		if reset_fill_stylebox is StyleBoxFlat: # Reset color to default safe
			reset_fill_stylebox.bg_color = Color(0.2, 0.8, 0.2, 0.9)
		energy_progress_bar.visible = true

	# Reset all player indicators
	for pid in player_indicators:
		var indicator = player_indicators.get(pid)
		if is_instance_valid(indicator):
			indicator.reset_indicator()


func _on_event_updated(event_data: Dictionary):
	var event_type = event_data.get("type", Config.EventType.NONE)
	var end_time_ms = event_data.get("end_time_ms", 0)
	_show_event_notification(event_type, end_time_ms)
	_update_event_particles(event_type)


func _show_event_notification(type: Config.EventType, end_time_ms: int):
	if not is_instance_valid(event_notification_overlay) or not is_instance_valid(event_title_label): return

	var current_time_ms = Time.get_ticks_msec()
	var duration_left_ms = end_time_ms - current_time_ms

	if type != Config.EventType.NONE and duration_left_ms > 100 : # Only show if event is active and has some time left
		var event_title_text = TextDB.EVENT_UNKNOWN_TITLE # Fallback
		var event_desc_text = "" # Description is optional here, main status text covers it
		
		match type:
			Config.EventType.SURGE:
				event_title_text = TextDB.EVENT_SURGE_TITLE_OVERLAY
			Config.EventType.EFFICIENCY:
				event_title_text = TextDB.EVENT_EFFICIENCY_TITLE_OVERLAY
			Config.EventType.UNSTABLE_GRID:
				event_title_text = TextDB.EVENT_UNSTABLE_GRID_TITLE_OVERLAY
		
		event_title_label.text = event_title_text
		if is_instance_valid(event_description_label): event_description_label.text = event_desc_text

		# Tween for fade-in and fade-out
		var tween = get_tree().create_tween()
		event_notification_overlay.modulate.a = 0.0 # Start transparent
		event_notification_overlay.show()
		
		tween.tween_property(event_notification_overlay, "modulate:a", 1.0, 0.3) # Fade in
		tween.tween_interval(2.0) # Hold visible
		tween.tween_property(event_notification_overlay, "modulate:a", 0.0, 0.3) # Fade out
		tween.tween_callback(event_notification_overlay.hide) # Hide after fade out

	else: # No active event, or event just ended, ensure it's hidden
		if event_notification_overlay.visible: # If it was visible, fade it out
			var tween = get_tree().create_tween()
			tween.tween_property(event_notification_overlay, "modulate:a", 0.0, 0.3).from(event_notification_overlay.modulate.a)
			tween.tween_callback(event_notification_overlay.hide)
		else: # Already hidden
			event_notification_overlay.hide()


func _clear_event_particles():
	if is_instance_valid(current_event_particles):
		current_event_particles.queue_free()
		current_event_particles = null
	# Also clear any stragglers if container had children directly
	if is_instance_valid(event_particles_container):
		for child in event_particles_container.get_children():
			child.queue_free()


func _update_event_particles(event_type: Config.EventType):
	_clear_event_particles() # Remove any existing particles

	if not is_instance_valid(event_particles_container):
		printerr("Display: EventParticlesContainer is not valid!")
		return

	var particle_scene_to_load = null
	match event_type:
		Config.EventType.SURGE:
			if SurgeParticles: particle_scene_to_load = SurgeParticles
		Config.EventType.EFFICIENCY:
			if EfficiencyParticles: particle_scene_to_load = EfficiencyParticles
		Config.EventType.UNSTABLE_GRID:
			if UnstableGridParticles: particle_scene_to_load = UnstableGridParticles
		Config.EventType.NONE:
			pass # No particles for NONE event, already cleared
		_:
			printerr("Display: Unknown event type for particles: ", event_type)

	if particle_scene_to_load:
		current_event_particles = particle_scene_to_load.instantiate()
		if is_instance_valid(current_event_particles):
			event_particles_container.add_child(current_event_particles)
			# Ensure particles are set to emit.
			if current_event_particles is CPUParticles2D:
				current_event_particles.set_emitting(true)
			elif current_event_particles is GPUParticles2D:
				current_event_particles.emitting = true
			# Fallback if it's some other node type that has a general 'emitting' property
			elif current_event_particles.has_method("set_emitting"):
				current_event_particles.set_emitting(true)
			elif "emitting" in current_event_particles: # Check if property exists
				current_event_particles.set("emitting", true)

			print("Display: Started particles for event ", Config.EventType.keys()[event_type])
		else:
			printerr("Display: Failed to instantiate particle scene for event ", Config.EventType.keys()[event_type])
