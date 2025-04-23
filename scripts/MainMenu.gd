extends Node2D

@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var start_button: Button = $VBoxContainer/StartLocalGameButton # Ensure this exists in scene
@onready var ip_display_label: Label = $VBoxContainer/IPDisplayLabel # Add a label to show IP

# Assuming UdpManager is autoloaded
@onready var udp_manager = get_node("/root/UdpManager") # Adjust path if name/autoload differs

func _ready():
	if udp_manager == null:
		status_label.text = "Error: UdpManager Autoload failed!"
		start_button.disabled = true
		ip_display_label.text = "Listener IP: Error"
		printerr("MainMenu Error: UdpManager node not found. Is it autoloaded?")
		return
	elif not udp_manager.is_listening:
		status_label.text = "Error: UDP Listener failed to start!"
		start_button.disabled = true
		ip_display_label.text = "Listener IP: Error"
		printerr("MainMenu Error: UdpManager is not listening. Check logs.")
	else:
		status_label.text = "Ready to Start Local Game."
		start_button.disabled = false
		# Ensure signal connection only happens once
		if not start_button.pressed.is_connected(_on_start_local_game_pressed):
			start_button.pressed.connect(_on_start_local_game_pressed)
		_display_local_ip()

func _display_local_ip():
	# Get local IP addresses
	var local_ips = IP.get_local_addresses()
	var display_ip = "Unknown"
	# Find a non-loopback IPv4 address (common for LAN)
	for ip in local_ips:
		if ip != "127.0.0.1" and not ip.contains(":"): # Basic check for IPv4, not loopback
			display_ip = ip
			break # Use the first one found

	if display_ip == "Unknown" and not local_ips.is_empty():
		display_ip = local_ips[0] # Fallback to the first IP if no ideal one found

	ip_display_label.text = "Listener IP: %s (Port: %d)" % [display_ip, Config.DEFAULT_UDP_PORT]
	print("MainMenu: Godot listening on UDP Port %d" % Config.DEFAULT_UDP_PORT)
	print("MainMenu: Configure ESP32 to send UDP packets to IP: %s" % display_ip)


func _on_start_local_game_pressed():
	if udp_manager == null or not udp_manager.is_listening:
		status_label.text = "Error: UDP Listener not active."
		return

	status_label.text = "Starting game..."
	# UdpManager is an autoload, it will persist
	get_tree().change_scene_to_file("res://scenes/Display.tscn")
