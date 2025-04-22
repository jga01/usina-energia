# scripts/network_manager.gd
# Autoload Singleton responsible for establishing network connections (hosting or joining),
# and signaling connection status. ROUTING REMOVED.
extends Node

# --- Signals ---
signal connection_failed
signal connection_succeeded

# --- Constants ---
const DEFAULT_PORT = Config.DEFAULT_PORT

# --- Member Variables ---
var multiplayer_peer = ENetMultiplayerPeer.new()
# --- REMOVED registered_game_manager variable ---

# Called when the node enters the scene tree for the first time.
func _ready():
	# Connect to MultiplayerAPI signals (These are still needed for connection status)
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connection_succeeded):
		multiplayer.connected_to_server.connect(_on_connection_succeeded)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

# Called for various node-related events for cleanup.
func _notification(what):
	match what:
		NOTIFICATION_PREDELETE:
			# Clean up multiplayer peer on exit/delete
			if is_instance_valid(multiplayer_peer):
				multiplayer_peer.close()
			if multiplayer != null and multiplayer.multiplayer_peer == multiplayer_peer:
				multiplayer.multiplayer_peer = null
			multiplayer_peer = null
			# --- REMOVED registered_game_manager cleanup ---


# --- Public Functions ---

# --- REMOVED register_game_manager function ---

# --- REMOVED unregister_game_manager function ---

# Attempts to create a game server listening on the specified port.
func create_server(port: int = DEFAULT_PORT):
	print("NetworkManager: Attempting to create server on port %d..." % port)
	# Ensure peer is clean before creating server
	if is_instance_valid(multiplayer_peer) and multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		multiplayer_peer.close()
	multiplayer_peer = ENetMultiplayerPeer.new() # Create a fresh peer

	# Attempt to create the server
	var error = multiplayer_peer.create_server(port)
	if error != OK:
		# Handle server creation error
		printerr("NetworkManager Error: Failed to create server. Error code: ", error)
		multiplayer_peer = null # Clear potentially broken peer
		if multiplayer: multiplayer.multiplayer_peer = null # Clear from singleton
		emit_signal("connection_failed") # Signal failure
		return

	# Assign the created peer to the active multiplayer singleton.
	multiplayer.multiplayer_peer = multiplayer_peer
	print("NetworkManager: Server created successfully on port %d. Waiting for players..." % port)
	emit_signal("connection_succeeded") # Host is considered 'connected' immediately

# Attempts to join an existing game server at the specified IP address and port.
func join_server(ip_address: String, port: int = DEFAULT_PORT):
	print("NetworkManager: Attempting to join server at %s:%d..." % [ip_address, port])
	# Ensure peer is clean before creating client
	if is_instance_valid(multiplayer_peer) and multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		multiplayer_peer.close()
	multiplayer_peer = ENetMultiplayerPeer.new() # Create a fresh peer

	# Attempt to create the client peer
	var error = multiplayer_peer.create_client(ip_address, port)
	if error != OK:
		# Handle client creation error
		printerr("NetworkManager Error: Failed to create client. Error code: ", error)
		multiplayer_peer = null # Clear potentially broken peer
		if multiplayer: multiplayer.multiplayer_peer = null # Clear from singleton
		emit_signal("connection_failed") # Signal failure
		return

	# Assign the created peer to the active multiplayer singleton.
	multiplayer.multiplayer_peer = multiplayer_peer
	print("NetworkManager: Client peer created. Waiting for connection result...")
	# Connection success/failure will be handled by the connected MultiplayerAPI signals.

# --- Multiplayer Signal Handlers ---
# These just print info; the core logic is handled elsewhere (MainMenu scene change, GameManager peer tracking)
func _on_peer_connected(peer_id: int):
	print("NetworkManager: Peer connected: ", peer_id)
	# GameManager handles adding the player state via its own signal connection

func _on_peer_disconnected(peer_id: int):
	print("NetworkManager: Peer disconnected: ", peer_id)
	# GameManager handles removing the player state via its own signal connection

func _on_connection_succeeded():
	# This signal is primarily used by MainMenu to change scenes
	emit_signal("connection_succeeded")

func _on_connection_failed():
	# This signal is primarily used by MainMenu to show an error
	printerr("NetworkManager Error: Connection failed!")
	if is_instance_valid(multiplayer_peer): multiplayer_peer.close() # Close peer connection
	multiplayer_peer = null # Clear reference
	if multiplayer != null: # Check if singleton exists before clearing
		multiplayer.multiplayer_peer = null # Clear from singleton
	# --- REMOVED registered_game_manager cleanup ---
	emit_signal("connection_failed") # Notify MainMenu

func _on_server_disconnected():
	# This signal can notify Controller or MainMenu about disconnection
	print("NetworkManager: Disconnected from server.")
	if is_instance_valid(multiplayer_peer): multiplayer_peer.close()
	multiplayer_peer = null # Clear reference
	if multiplayer != null: # Check if singleton exists before clearing
		multiplayer.multiplayer_peer = null # Clear from singleton
	# --- REMOVED registered_game_manager cleanup ---
	emit_signal("connection_failed") # Treat server disconnect like a connection failure for UI purposes


# --- REMOVED RPC Router Function (receive_player_action) ---
