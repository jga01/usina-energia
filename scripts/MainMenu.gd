# scripts/MainMenu.gd
extends Node2D

# --- UI Node References ---
# Adjust these paths if your scene structure is different
@onready var host_button: Button = $VBoxContainer/HostGameButton
@onready var join_button: Button = $VBoxContainer/JoinGameButton
@onready var ip_address_input: LineEdit = $VBoxContainer/HBoxContainer/IPAddressInput
@onready var status_label: Label = $VBoxContainer/StatusLabel

func _ready():
	# Default IP for convenience (localhost) - players need to change this to the host's actual LAN IP
	ip_address_input.text = "127.0.0.1"
	status_label.text = "Ready."

	# Connect button signals to functions in this script
	host_button.pressed.connect(_on_host_button_pressed)
	join_button.pressed.connect(_on_join_button_pressed)

	# Connect signals from NetworkManager for feedback
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)

func _set_buttons_disabled(disabled: bool):
	"""Helper function to enable/disable buttons."""
	host_button.disabled = disabled
	join_button.disabled = disabled
	ip_address_input.editable = not disabled # Make input non-editable while connecting

# --- Button Handlers ---

func _on_host_button_pressed():
	status_label.text = "Starting server..."
	_set_buttons_disabled(true)
	NetworkManager.create_server()
	# Connection success/fail will be handled by the signals connected in _ready()

func _on_join_button_pressed():
	var ip_address = ip_address_input.text.strip_edges() # Remove leading/trailing whitespace

	if ip_address.is_empty():
		status_label.text = "Error: Please enter the Host IP address."
		return

	if not ip_address.is_valid_ip_address():
		status_label.text = "Error: Invalid IP address format."
		# Optionally add more robust validation if needed
		return

	status_label.text = "Attempting to connect to %s..." % ip_address
	_set_buttons_disabled(true)
	NetworkManager.join_server(ip_address)
	# Connection success/fail will be handled by the signals connected in _ready()

# --- NetworkManager Signal Handlers ---

func _on_connection_succeeded():
	status_label.text = "Connection successful!"
	# Check if we are now the server or a client
	if multiplayer.is_server():
		print("MainMenu: Hosting successful. Changing scene to Display.")
		get_tree().change_scene_to_file("res://scenes/Display.tscn")
	else:
		print("MainMenu: Joining successful. Changing scene to Controller.")
		get_tree().change_scene_to_file("res://scenes/Controller.tscn")
	# Note: We don't re-enable buttons here because we change scene on success.

func _on_connection_failed():
	status_label.text = "Connection failed. Please check IP and host status."
	_set_buttons_disabled(false) # Re-enable buttons to allow retry


# Optional: Handle disconnection if returning to main menu
func _enter_tree():
	# If returning to this scene after being connected, clean up the peer
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		print("MainMenu: Cleaned up existing multiplayer peer.")
