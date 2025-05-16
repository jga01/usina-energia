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
@onready var event_particles_container: Node2D = %EventParticlesContainer


const PlayerIndicatorScene = preload("res://scenes/PlayerIndicator.tscn")
const GameOverScreenScene = preload("res://scenes/GameOverScreen.tscn")

# Preload your particle scenes here - CREATE THESE SCENES YOURSELF
# Ensure the paths are correct. If paths are wrong, it will error.
const SurgeParticles = preload("res://scenes/particles/SurgeParticles.tscn")
const EfficiencyParticles = preload("res://scenes/particles/EfficiencyParticles.tscn")
const UnstableGridParticles = preload("res://scenes/particles/SurgeParticles.tscn")

var player_indicators: Dictionary = {} # { player_id: PlayerIndicator_instance }
var last_global_state: Dictionary = {} # Cache last full game state
var current_event_particles: Node = null # To keep track of the current particle instance

const INDICATOR_MARGIN = 20.0

# --- Central Core Textures (Placeholders - load your actual assets) ---
var core_textures: Dictionary = {
	"low": preload("res://assets/new/battery_normal.png"),
	"mid": preload("res://assets/new/battery_normal.png"),
	"high": preload("res://assets/new/battery_normal.png"),
	"danger_low": preload("res://assets/new/battery_normal.png"),
	"danger_high": preload("res://assets/new/battery_normal.png"),
	"event_surge": preload("res://assets/new/battery_surge.png"),
	"event_efficiency": preload("res://assets/new/battery_efficiency.png"),
	"event_unstable_grid": preload("res://assets/new/battery_surge.png"),
	"stable": preload("res://assets/new/battery_normal.png"), # Default stable
	"game_over": preload("res://assets/new/battery_normal.png")
}
var stability_icons_textures: Dictionary = { # Placeholder paths
	"normal": preload("res://assets/new/hourglass.png"),
	"warning": preload("res://assets/new/hourglass.png"),
	"achieved": preload("res://assets/new/hourglass.png")
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
		energy_progress_bar.value = Config.MAX_ENERGY / 2.0

	_update_central_core_display(50.0, false, {})
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
	if not game_manager.event_updated.is_connected(_on_event_updated): # This will trigger particle changes
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

	var parent_size = player_indicators_parent.size # This is the full screen size
	var num_players_created = player_indicators.size()

	for i in range(1, num_players_created + 1):
		if player_indicators.has(i):
			var indicator_control = player_indicators[i] as Control
			if not is_instance_valid(indicator_control): continue

			var indicator_size = indicator_control.size
			if indicator_size == Vector2.ZERO:
				await get_tree().process_frame
				indicator_size = indicator_control.size
				if indicator_size == Vector2.ZERO:
					indicator_size = indicator_control.custom_minimum_size
					if indicator_size == Vector2.ZERO:
						printerr("Display Warning: Indicator %d size is zero, cannot position accurately." % i)
						indicator_size = Vector2(185,262) # Fallback to typical size from PlayerIndicator.tscn if needed
			
			match i:
				1: indicator_control.position = Vector2(INDICATOR_MARGIN, INDICATOR_MARGIN) # Top-left
				2: indicator_control.position = Vector2(parent_size.x - indicator_size.x - INDICATOR_MARGIN, INDICATOR_MARGIN) # Top-right
				3: indicator_control.position = Vector2(INDICATOR_MARGIN, parent_size.y - indicator_size.y - INDICATOR_MARGIN) # Bottom-left
				4: indicator_control.position = Vector2(parent_size.x - indicator_size.x - INDICATOR_MARGIN, parent_size.y - indicator_size.y - INDICATOR_MARGIN) # Bottom-right
				_: indicator_control.position = Vector2(INDICATOR_MARGIN, INDICATOR_MARGIN + ((i-1) * (indicator_size.y + 5)))


func _update_central_core_display(level: float, is_running: bool, state_data: Dictionary):
	if not is_instance_valid(central_core_sprite) or \
	   not is_instance_valid(game_status_text) or \
	   not is_instance_valid(energy_progress_bar):
		return
	
	var current_status_message = TextDB.DISPLAY_STATUS_WAITING
	var new_core_texture_key = "stable" # Default texture
	var core_modulate = Color.WHITE

	if is_running:
		var danger_low_thresh = state_data.get("dangerLow", Config.DANGER_LOW_THRESHOLD)
		var safe_min = state_data.get("safeZoneMin", Config.SAFE_ZONE_MIN)
		var safe_max = state_data.get("safeZoneMax", Config.SAFE_ZONE_MAX)
		var danger_high_thresh = state_data.get("dangerHigh", Config.DANGER_HIGH_THRESHOLD)
		var active_game_event_type = state_data.get("activeEventType", Config.EventType.NONE)

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
		else:
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
	else: # Game not running
		var final_reason = state_data.get("finalOutcomeReason", "none")
		if final_reason == "none":
			current_status_message = TextDB.DISPLAY_STATUS_WAITING
			new_core_texture_key = "stable"
		else:
			current_status_message = TextDB.GO_TITLE_GAME_OVER_DEFAULT
			new_core_texture_key = "game_over"
		energy_progress_bar.visible = true
		energy_progress_bar.value = 0
	
	game_status_text.text = current_status_message
	if core_textures.has(new_core_texture_key):
		central_core_sprite.texture = core_textures[new_core_texture_key]
	else:
		printerr("Display: Missing core texture for key: ", new_core_texture_key)
		if core_textures.has("stable"): central_core_sprite.texture = core_textures["stable"]
	
	central_core_sprite.modulate = core_modulate

	if is_instance_valid(danger_warning_label):
		var in_danger_low = state_data.get("dangerLowProgressSeconds", 0.0) > 0.0
		var in_danger_high = state_data.get("dangerHighProgressSeconds", 0.0) > 0.0
		if is_running and (in_danger_low or in_danger_high) :
			var time_limit = Config.DANGER_TIME_LIMIT_SECONDS
			if in_danger_low:
				var remaining_low = time_limit - state_data.get("dangerLowProgressSeconds", 0.0)
				danger_warning_label.text = TextDB.DISPLAY_DANGER_SHUTDOWN_COUNTDOWN % snapped(remaining_low, 0.1)
			elif in_danger_high:
				var remaining_high = time_limit - state_data.get("dangerHighProgressSeconds", 0.0)
				danger_warning_label.text = TextDB.DISPLAY_DANGER_MELTDOWN_COUNTDOWN % snapped(remaining_high, 0.1)
			danger_warning_label.show()
		else:
			danger_warning_label.hide()

	energy_progress_bar.value = level
	var bar_fill_color = Color.GRAY

	if is_running:
		var active_event_for_bar = state_data.get("activeEventType", Config.EventType.NONE)
		var danger_low_thresh_bar = state_data.get("dangerLow", Config.DANGER_LOW_THRESHOLD)
		var safe_min_bar = state_data.get("safeZoneMin", Config.SAFE_ZONE_MIN)
		var safe_max_bar = state_data.get("safeZoneMax", Config.SAFE_ZONE_MAX)
		var danger_high_thresh_bar = state_data.get("dangerHigh", Config.DANGER_HIGH_THRESHOLD)

		if active_event_for_bar == Config.EventType.SURGE:
			bar_fill_color = Color(0.9, 0.4, 0.1, 0.9)
		elif active_event_for_bar == Config.EventType.EFFICIENCY:
			bar_fill_color = Color(0.2, 0.7, 0.9, 0.9)
		elif active_event_for_bar == Config.EventType.UNSTABLE_GRID:
			bar_fill_color = Color(0.6, 0.2, 0.8, 0.9)
		else:
			if level < danger_low_thresh_bar:
				bar_fill_color = Color(0.9, 0.1, 0.1, 0.9)
			elif level < safe_min_bar:
				bar_fill_color = Color(0.9, 0.8, 0.2, 0.9)
			elif level <= safe_max_bar:
				bar_fill_color = Color(0.2, 0.8, 0.2, 0.9)
			elif level < danger_high_thresh_bar:
				bar_fill_color = Color(0.9, 0.8, 0.2, 0.9)
			else:
				bar_fill_color = Color(0.9, 0.1, 0.1, 0.9)

	var fill_stylebox = energy_progress_bar.get_theme_stylebox("fill")
	if fill_stylebox is StyleBoxFlat:
		fill_stylebox.bg_color = bar_fill_color
	else:
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
			else:
				if stability_icons_textures.has("warning"): stability_icon.texture = stability_icons_textures["warning"]
		elif outcome_reason == "coopWin":
			stability_goal_text.text = TextDB.DISPLAY_STABILITY_GOAL_SUCCESS_SIMPLE
			if stability_icons_textures.has("achieved"): stability_icon.texture = stability_icons_textures["achieved"]
		elif not is_running and outcome_reason != "none":
			var outcome_display_text = TextDB.DISPLAY_STABILITY_GOAL_FINAL_STATUS_PREFIX
			match outcome_reason:
				"individualWin": outcome_display_text += TextDB.DISPLAY_INDIVIDUAL_WIN_TEXT % winner_id
				"shutdown": outcome_display_text += TextDB.DISPLAY_GRID_SHUTDOWN_TEXT
				"meltdown": outcome_display_text += TextDB.DISPLAY_GRID_MELTDOWN_TEXT
				"allEliminated": outcome_display_text += TextDB.DISPLAY_ALL_ELIMINATED_TEXT
				"lastPlayerStanding": outcome_display_text += TextDB.DISPLAY_LAST_PLAYER_STANDING_TEXT % winner_id
				_: outcome_display_text += outcome_reason.capitalize()
			stability_goal_text.text = outcome_display_text
			if stability_icons_textures.has("warning"): stability_icon.texture = stability_icons_textures["warning"]
		else:
			stability_goal_text.text = TextDB.DISPLAY_STABILITY_GOAL_SIMPLE % [0, safe_target]
			if stability_icons_textures.has("normal"): stability_icon.texture = stability_icons_textures["normal"]
	else:
		stability_goal_text.text = TextDB.DISPLAY_STABILITY_GOAL_WAITING_SIMPLE
		if stability_icons_textures.has("normal"): stability_icon.texture = stability_icons_textures["normal"]


func _on_game_state_updated(state_data: Dictionary):
	last_global_state = state_data
	_update_central_core_display(state_data.get("energyLevel", 50.0), state_data.get("gameIsRunning", false), state_data)
	_update_coop_progress(
		state_data.get("coopWinProgressSeconds", 0.0),
		state_data.get("coopWinTargetSeconds", Config.COOP_WIN_DURATION_SECONDS),
		state_data.get("gameIsRunning", false),
		state_data.get("finalOutcomeReason", "none"),
		state_data.get("finalOutcomeWinner", 0),
		state_data.get("energyLevel", 50.0)
	)
	for pid in player_indicators:
		var indicator = player_indicators.get(pid)
		if is_instance_valid(indicator):
			var p_data_for_indicator = {}
			if state_data.has("player_data_map") and state_data.player_data_map.has(pid):
				p_data_for_indicator = state_data.player_data_map[pid]
			indicator.update_display(p_data_for_indicator, last_global_state)


func _on_player_state_updated(player_id: int, player_state_data: Dictionary):
	if player_indicators.has(player_id):
		var indicator = player_indicators[player_id]
		if is_instance_valid(indicator):
			indicator.update_display(player_state_data, last_global_state)
		else:
			printerr("Display Warning: Indicator node for player %d is invalid!" % player_id)
	else:
		printerr("Display Warning: Received update for unknown player ID %d" % player_id)

func _on_player_action_visual_feedback(player_id: int, action_name: String):
	if not player_indicators.has(player_id) or not is_instance_valid(central_core_sprite):
		return
	
	var player_indicator_node = player_indicators[player_id] as Control
	if not is_instance_valid(player_indicator_node): return

	var start_pos_global = player_indicator_node.global_position + player_indicator_node.size / 2
	var end_pos_global = central_core_sprite.global_position
	
	var flow_color = Color.CYAN
	var target_pos_global = end_pos_global

	var current_event = last_global_state.get("activeEventType", Config.EventType.NONE)
	var p_state = last_global_state.get("player_data_map",{}).get(player_id,{})
	var is_eliminated = p_state.get("is_eliminated", false)

	if current_event == Config.EventType.UNSTABLE_GRID and not is_eliminated:
		flow_color = Color.MEDIUM_PURPLE
		target_pos_global = start_pos_global 
		start_pos_global = end_pos_global    
	elif current_event == Config.EventType.EFFICIENCY:
		flow_color = Color.LIGHT_GREEN
	
	var line = Line2D.new()
	line.add_point(electricity_flow_parent.to_local(start_pos_global))
	line.add_point(electricity_flow_parent.to_local(target_pos_global))
	line.width = 5.0
	line.default_color = flow_color
	electricity_flow_parent.add_child(line)

	var tween = get_tree().create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.3).from(1.0).set_delay(0.1) 
	tween.tween_callback(line.queue_free)


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
		danger_warning_label.hide()
	
	_show_event_notification(Config.EventType.NONE, 0) 

	if is_instance_valid(central_core_sprite) and core_textures.has("stable"):
		central_core_sprite.texture = core_textures["stable"]
	if is_instance_valid(core_animation_player) and core_animation_player.is_playing():
		core_animation_player.stop()

	if is_instance_valid(energy_progress_bar):
		energy_progress_bar.value = Config.MAX_ENERGY / 2.0
		var reset_fill_stylebox = energy_progress_bar.get_theme_stylebox("fill")
		if reset_fill_stylebox is StyleBoxFlat:
			reset_fill_stylebox.bg_color = Color(0.2, 0.8, 0.2, 0.9)
		energy_progress_bar.visible = true

	for pid in player_indicators:
		var indicator = player_indicators.get(pid)
		if is_instance_valid(indicator):
			indicator.reset_indicator()


func _on_event_updated(event_data: Dictionary):
	var event_type = event_data.get("type", Config.EventType.NONE)
	var end_time_ms = event_data.get("end_time_ms", 0) # Not directly used for particles here, but good to have
	_show_event_notification(event_type, end_time_ms)
	_update_event_particles(event_type)


func _show_event_notification(type: Config.EventType, end_time_ms: int):
	if not is_instance_valid(event_notification_overlay) or not is_instance_valid(event_title_label): return

	var current_time_ms = Time.get_ticks_msec()
	var duration_left_ms = end_time_ms - current_time_ms

	if type != Config.EventType.NONE and duration_left_ms > 100 : 
		var event_title_text = TextDB.EVENT_UNKNOWN_TITLE 
		var event_desc_text = "" 
		
		match type:
			Config.EventType.SURGE:
				event_title_text = TextDB.EVENT_SURGE_TITLE_OVERLAY
			Config.EventType.EFFICIENCY:
				event_title_text = TextDB.EVENT_EFFICIENCY_TITLE_OVERLAY
			Config.EventType.UNSTABLE_GRID:
				event_title_text = TextDB.EVENT_UNSTABLE_GRID_TITLE_OVERLAY
		
		event_title_label.text = event_title_text
		if is_instance_valid(event_description_label): event_description_label.text = event_desc_text

		var tween = get_tree().create_tween()
		event_notification_overlay.modulate.a = 0.0
		event_notification_overlay.show()
		
		tween.tween_property(event_notification_overlay, "modulate:a", 1.0, 0.3) 
		tween.tween_interval(2.0) 
		tween.tween_property(event_notification_overlay, "modulate:a", 0.0, 0.3) 
		tween.tween_callback(event_notification_overlay.hide)

	else: 
		if event_notification_overlay.visible: 
			var tween = get_tree().create_tween()
			tween.tween_property(event_notification_overlay, "modulate:a", 0.0, 0.3).from(event_notification_overlay.modulate.a)
			tween.tween_callback(event_notification_overlay.hide)
		else:
			event_notification_overlay.hide()


func _clear_event_particles():
	if is_instance_valid(current_event_particles):
		current_event_particles.queue_free()
		current_event_particles = null
	# Also clear any stragglers if container had children directly (less ideal)
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
			# Ensure particles are set to emit. CPUParticles2D use set_emitting(), GPUParticles2D use .emitting
			if current_event_particles is CPUParticles2D:
				current_event_particles.set_emitting(true)
			elif current_event_particles is GPUParticles2D: # Check for GPUParticles2D as well
				current_event_particles.emitting = true
			# Fallback if it's some other node type that has a general 'emitting' property
			elif current_event_particles.has_method("set_emitting"):
				current_event_particles.set_emitting(true)
			elif "emitting" in current_event_particles: # Check if property exists
				current_event_particles.set("emitting", true)

			print("Display: Started particles for event ", Config.EventType.keys()[event_type])
		else:
			printerr("Display: Failed to instantiate particle scene for event ", Config.EventType.keys()[event_type])
