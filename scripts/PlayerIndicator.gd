# File: res://scripts/PlayerIndicator.gd
extends Control

@onready var player_id_label: Label = $PanelContainer/VBoxContainer/PlayerIDLabel
@onready var character_portrait: TextureRect = $PanelContainer/VBoxContainer/CharacterPortrait
@onready var stash_amount_label: Label = $PanelContainer/VBoxContainer/StashHBox/StashAmountLabel
@onready var stash_target_label: Label = $PanelContainer/VBoxContainer/StashHBox/StashTargetLabel
@onready var generate_button: Button = $PanelContainer/VBoxContainer/ActionsVBox/GenerateButton
@onready var stabilize_button: Button = $PanelContainer/VBoxContainer/ActionsVBox/StabilizeButton
@onready var emergency_button: Button = $PanelContainer/VBoxContainer/ActionsVBox/EmergencyButton
@onready var steal_grid_button: Button = $PanelContainer/VBoxContainer/ActionsVBox/StealGridButton
@onready var status_label: Label = $PanelContainer/VBoxContainer/StatusLabel
@onready var stash_static_label: Label = $PanelContainer/VBoxContainer/StashHBox/StashLabel # Assuming this node exists

const DIM_COLOR = Color(0.6, 0.6, 0.6)
const NORMAL_COLOR = Color(1.0, 1.0, 1.0)
const FLASH_COLOR = Color(1.5, 1.5, 1.5)
const FLASH_DURATION = 0.1
const ELIMINATED_PANEL_MODULATE = Color(0.7, 0.7, 0.7, 0.8)
const ELIMINATED_BUTTON_MODULATE = Color(0.2, 0.2, 0.2)

var player_id: int = 0
var is_game_running: bool = false
var stash_win_target: int = Config.STASH_WIN_TARGET
var current_stash: float = 0.0
var is_player_eliminated: bool = false

var cooldown_end_times: Dictionary = {
	"generate": 0, "stabilize": 0, "emergencyAdjust": 0, "stealGrid": 0
}
var action_buttons: Dictionary = {}
var status_message_timer: Timer = Timer.new()
var last_player_data: Dictionary = {}
var active_flash_tweens: Dictionary = {}

func _ready():
	action_buttons = {
		"generate": {"button": generate_button, "original_text": TextDB.PI_GENERATE_BUTTON},
		"stabilize": {"button": stabilize_button, "original_text": TextDB.PI_STABILIZE_BUTTON},
		"emergencyAdjust": {"button": emergency_button, "original_text": TextDB.PI_EMERGENCY_BUTTON},
		"stealGrid": {"button": steal_grid_button, "original_text": TextDB.PI_STEAL_BUTTON}
	}

	for action_name in action_buttons:
		var button_node: Button = action_buttons[action_name]["button"]
		if is_instance_valid(button_node):
			button_node.text = action_buttons[action_name]["original_text"] # Set initial text
			button_node.disabled = true
			button_node.modulate = DIM_COLOR

	add_child(status_message_timer)
	status_message_timer.one_shot = true
	status_message_timer.wait_time = 1.5
	status_message_timer.timeout.connect(_clear_temporary_status_message)

	if is_instance_valid(status_label): status_label.hide()
	if is_instance_valid(stash_target_label): stash_target_label.text = str(stash_win_target)
	if is_instance_valid(stash_static_label): stash_static_label.text = TextDB.PI_STASH_LABEL

	# Initial portrait load in set_player_id or first update_display
	if is_instance_valid(character_portrait) and PlayerProfiles:
		var default_normal_path = PlayerProfiles.DEFAULT_PORTRAITS.get("normal", "")
		if not default_normal_path.is_empty():
			character_portrait.texture = load(default_normal_path)
		else:
			character_portrait.texture = load("res://icon.svg") # Absolute fallback
	elif is_instance_valid(character_portrait):
		character_portrait.texture = load("res://icon.svg")


func _process(_delta):
	if is_game_running and not is_player_eliminated:
		for action_name in action_buttons:
			if cooldown_end_times.get(action_name, 0) > Time.get_ticks_msec():
				_update_button_display(action_name)

func set_player_id(id: int):
	player_id = id
	if is_instance_valid(player_id_label):
		player_id_label.text = TextDB.GENERIC_PLAYER_LABEL_FORMAT % id
	if is_instance_valid(character_portrait) and PlayerProfiles:
		var portrait_path = PlayerProfiles.get_character_portrait_path(player_id, "normal")
		if not portrait_path.is_empty(): character_portrait.texture = load(portrait_path)

func update_display(player_data: Dictionary, global_state: Dictionary):
	var game_running_changed = is_game_running != global_state.get("gameIsRunning", false)
	is_game_running = global_state.get("gameIsRunning", false)
	stash_win_target = global_state.get("stashWinTarget", Config.STASH_WIN_TARGET)
	if is_instance_valid(stash_target_label): stash_target_label.text = str(stash_win_target)

	if not player_data.is_empty(): last_player_data = player_data
	else: player_data = last_player_data

	var player_elimination_changed = false
	if player_data.has("is_eliminated"):
		var new_elim_status = player_data.get("is_eliminated", false)
		if is_player_eliminated != new_elim_status:
			is_player_eliminated = new_elim_status; player_elimination_changed = true

	if player_data.has("personal_stash"):
		current_stash = player_data.get("personal_stash", 0.0)
		if is_instance_valid(stash_amount_label): stash_amount_label.text = str(snapped(current_stash, 0.1))

	var cooldown_changed = false
	for action_name in cooldown_end_times:
		var key = action_name + "_cooldown_end_ms"
		if action_name == "emergencyAdjust": key = "emergency_adjust_cooldown_end_ms"
		elif action_name == "stealGrid": key = "steal_grid_cooldown_end_ms"
		if player_data.has(key):
			var new_cooldown = player_data.get(key, 0)
			if cooldown_end_times[action_name] != new_cooldown:
				cooldown_end_times[action_name] = new_cooldown; cooldown_changed = true

	var last_action_status_key = player_data.get("last_action_status", "") # Expecting a TextDB key here from GameManager
	if not last_action_status_key.is_empty():
		var status_text_to_show = last_action_status_key # Default to the key itself if not found in TextDB
		if last_action_status_key == TextDB.STATUS_STOLE_AMOUNT: # Handle formatted string
			# This assumes GameManager sets "last_action_status" to TextDB.STATUS_STOLE_AMOUNT
			# and another field like "last_action_value" for the amount.
			# For simplicity, let's assume GameManager sends the fully formatted string for this one case for now
			# or PlayerIndicator reconstructs it if it receives the raw value.
			# If GameManager set last_action_status = TextDB.STATUS_STOLE_AMOUNT % value, then this is fine:
			status_text_to_show = last_action_status_key
		_show_temporary_status_message(status_text_to_show)
	elif status_message_timer.is_stopped() and is_instance_valid(status_label) and not is_player_eliminated:
		status_label.hide()

	_update_character_portrait_display_internal(player_data, global_state)

	var panel_container_node = get_node_or_null("PanelContainer")
	if is_player_eliminated:
		if is_instance_valid(player_id_label):
			player_id_label.text = (TextDB.GENERIC_PLAYER_LABEL_FORMAT % player_id) + TextDB.PI_ELIMINATED_TEXT_SUFFIX
			player_id_label.modulate = DIM_COLOR
		if is_instance_valid(panel_container_node): panel_container_node.modulate = ELIMINATED_PANEL_MODULATE
		if is_instance_valid(status_label):
			status_label.text = TextDB.PI_STATUS_LABEL_PREFIX + TextDB.STATUS_ELECTROCUTED
			status_label.show()
		for action_name in action_buttons:
			var btn_node: Button = action_buttons[action_name]["button"]
			if is_instance_valid(btn_node):
				btn_node.text = TextDB.PI_BUTTON_ELIMINATED_TEXT; btn_node.disabled = true; btn_node.modulate = ELIMINATED_BUTTON_MODULATE
	else: # Not eliminated
		if is_instance_valid(player_id_label):
			player_id_label.text = TextDB.GENERIC_PLAYER_LABEL_FORMAT % player_id
			player_id_label.modulate = NORMAL_COLOR
		if is_instance_valid(panel_container_node): panel_container_node.modulate = NORMAL_COLOR
		if is_instance_valid(status_label) and status_label.text == (TextDB.PI_STATUS_LABEL_PREFIX + TextDB.STATUS_ELECTROCUTED) and status_message_timer.is_stopped():
			status_label.hide() # Clear electrocuted if reset and not eliminated
		for action_name in action_buttons: _update_button_display(action_name)


func _update_character_portrait_display_internal(p_data: Dictionary, g_state: Dictionary):
	if not is_instance_valid(character_portrait) or not PlayerProfiles: return
	var portrait_status_key = "normal"
	if is_player_eliminated: portrait_status_key = "dead"
	else:
		var energy = g_state.get("energyLevel", 50.0)
		if energy < g_state.get("dangerLow", Config.DANGER_LOW_THRESHOLD) or energy > g_state.get("dangerHigh", Config.DANGER_HIGH_THRESHOLD):
			portrait_status_key = "danger"
		elif energy < g_state.get("safeZoneMin", Config.SAFE_ZONE_MIN) or energy > g_state.get("safeZoneMax", Config.SAFE_ZONE_MAX):
			portrait_status_key = "warning"
	var portrait_path = PlayerProfiles.get_character_portrait_path(player_id, portrait_status_key)
	if not portrait_path.is_empty():
		var tex = load(portrait_path)
		if tex: character_portrait.texture = tex
		else: character_portrait.texture = load(PlayerProfiles.DEFAULT_PORTRAITS.get("normal","res://icon.svg"))
	else: character_portrait.texture = load(PlayerProfiles.DEFAULT_PORTRAITS.get("normal","res://icon.svg"))


func _update_button_display(action_name: String):
	if not action_buttons.has(action_name) or is_player_eliminated: return
	var button_info = action_buttons[action_name]
	var button_node: Button = button_info["button"]
	var original_text: String = button_info["original_text"]
	var end_time_ms: int = cooldown_end_times.get(action_name, 0)
	if not is_instance_valid(button_node): return
	if active_flash_tweens.has(action_name) and is_instance_valid(active_flash_tweens[action_name]): return
	var now_ms = Time.get_ticks_msec(); var time_left_ms = end_time_ms - now_ms
	if is_game_running and time_left_ms <= 0:
		button_node.text = original_text; button_node.disabled = false; button_node.modulate = NORMAL_COLOR
	elif is_game_running and time_left_ms > 0:
		button_node.text = original_text + " (%ds)" % int(ceil(time_left_ms / 1000.0))
		button_node.disabled = true; button_node.modulate = DIM_COLOR
	else: # Game not running
		button_node.text = original_text; button_node.disabled = true; button_node.modulate = DIM_COLOR

func flash_button(action_name: String):
	if not action_buttons.has(action_name) or is_player_eliminated: return
	var button_info = action_buttons[action_name]; var button_node: Button = button_info["button"]
	if not is_instance_valid(button_node): return
	if active_flash_tweens.has(action_name) and is_instance_valid(active_flash_tweens[action_name]):
		active_flash_tweens[action_name].kill()
	var tween = get_tree().create_tween(); active_flash_tweens[action_name] = tween
	var start_modulate = button_node.modulate
	tween.tween_property(button_node, "modulate", FLASH_COLOR, FLASH_DURATION / 2.0).from(start_modulate).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var target_modulate = NORMAL_COLOR; var now_ms = Time.get_ticks_msec()
	var end_time_ms = cooldown_end_times.get(action_name, 0)
	if not is_game_running or (end_time_ms > now_ms): target_modulate = DIM_COLOR
	var final_modulate = target_modulate if start_modulate != target_modulate else start_modulate
	tween.tween_property(button_node, "modulate", final_modulate, FLASH_DURATION / 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_update_button_display.bind(action_name))
	tween.tween_callback(_remove_flash_tween.bind(action_name))

func _show_temporary_status_message(message_text: String): # Expects already processed text
	if is_player_eliminated or not is_instance_valid(status_label): return
	status_label.text = TextDB.PI_STATUS_LABEL_PREFIX + message_text
	status_label.show(); status_message_timer.start()

func _clear_temporary_status_message():
	if status_message_timer.is_stopped() and is_instance_valid(status_label) and not is_player_eliminated:
		status_label.hide(); status_label.text = ""

func _remove_flash_tween(action_name_to_remove: String):
	if active_flash_tweens.has(action_name_to_remove): active_flash_tweens.erase(action_name_to_remove)

func reset_indicator():
	print("Indicator %d: Resetting..." % player_id)
	is_game_running = false; current_stash = 0.0; last_player_data = {}; is_player_eliminated = false
	if is_instance_valid(stash_amount_label): stash_amount_label.text = "0"
	stash_win_target = Config.STASH_WIN_TARGET
	if is_instance_valid(stash_target_label): stash_target_label.text = str(stash_win_target)
	if is_instance_valid(player_id_label):
		player_id_label.text = TextDB.GENERIC_PLAYER_LABEL_FORMAT % player_id
		player_id_label.modulate = NORMAL_COLOR
	var panel_container_node = get_node_or_null("PanelContainer")
	if is_instance_valid(panel_container_node): panel_container_node.modulate = NORMAL_COLOR
	if is_instance_valid(character_portrait) and PlayerProfiles:
		var portrait_path = PlayerProfiles.get_character_portrait_path(player_id, "normal")
		if not portrait_path.is_empty(): character_portrait.texture = load(portrait_path)
		else: character_portrait.texture = load(PlayerProfiles.DEFAULT_PORTRAITS.get("normal", "res://icon.svg"))
	elif is_instance_valid(character_portrait): character_portrait.texture = load("res://icon.svg")
	for action_name in cooldown_end_times: cooldown_end_times[action_name] = 0
	if status_message_timer.time_left > 0: status_message_timer.stop()
	if is_instance_valid(status_label): status_label.hide()
	for action_name in active_flash_tweens:
		if is_instance_valid(active_flash_tweens[action_name]): active_flash_tweens[action_name].kill()
	active_flash_tweens.clear()
	for action_name in action_buttons: _update_button_display(action_name)
