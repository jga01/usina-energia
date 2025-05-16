# File: res://scripts/MainMenu.gd
extends Node2D

@onready var start_button: Button = $CenterContainer/VBoxContainer/StartLocalGameButton
@onready var udp_manager = get_node("/root/UdpManager") # Assuming UdpManager is an autoload

func _ready():
	start_button.text = TextDB.MAIN_MENU_START_BUTTON_TEXT

	# Play BGM
	# The Audio node is autoloaded, so it can be accessed directly by its name.
	if Audio: # Good practice to check if the autoload is available
		Audio.play_bgm(Audio.BGM_MENU_PATH) # Use the path defined in Audio.gd
	else:
		printerr("MainMenu: Audio autoload not found!")

	if udp_manager == null:
		printerr("MainMenu Error: UdpManager node not found. Is it autoloaded?")
		start_button.disabled = true
		return
	elif not udp_manager.is_listening:
		printerr("MainMenu Error: UdpManager is not listening. Check logs.")
		start_button.disabled = true
	else:
		start_button.disabled = false
		if not start_button.pressed.is_connected(_on_start_local_game_pressed):
			start_button.pressed.connect(_on_start_local_game_pressed)
		_log_local_ip_info()

func _log_local_ip_info():
	var local_ips = IP.get_local_addresses()
	var display_ip_for_log = "Unknown"
	for ip in local_ips:
		if ip != "127.0.0.1" and not ip.contains(":"): # Prefer non-localhost IPv4
			display_ip_for_log = ip
			break
	if display_ip_for_log == "Unknown" and not local_ips.is_empty():
		display_ip_for_log = local_ips[0]

	print("MainMenu: Godot listening on UDP Port %d" % Config.DEFAULT_UDP_PORT)
	print("MainMenu: If using ESP32 or other devices, configure them to send UDP packets to IP: %s on port %d" % [display_ip_for_log, Config.DEFAULT_UDP_PORT])

func _on_start_local_game_pressed():
	if udp_manager == null or not udp_manager.is_listening:
		printerr("MainMenu Error: Cannot start game, UdpManager is not active.")
		return
	get_tree().change_scene_to_file("res://scenes/CharacterSelection.tscn")
