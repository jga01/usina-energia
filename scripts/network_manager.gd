extends Node

signal peer_list_changed
signal connection_failed
signal connection_succeeded
signal game_started # Emitted by host when game begins
signal game_ended   # Emitted by host when game ends

const DEFAULT_PORT = Config.DEFAULT_PORT # Get from Config autoload
var peer = ENetMultiplayerPeer.new()

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connection_succeeded)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func create_server(port: int = DEFAULT_PORT):
	var error = peer.create_server(port)
	if error != OK:
		printerr("Failed to create server. Error code: ", error)
		emit_signal("connection_failed")
		return
	multiplayer.set_multiplayer_peer(peer)
	print("Server created on port ", port, ". Waiting for players...")
	emit_signal("peer_list_changed") # Update UI immediately
	emit_signal("connection_succeeded") # Host is 'connected'

func join_server(ip_address: String, port: int = DEFAULT_PORT):
	var error = peer.create_client(ip_address, port)
	if error != OK:
		printerr("Failed to create client. Error code: ", error)
		emit_signal("connection_failed")
		return
	multiplayer.set_multiplayer_peer(peer)
	print("Attempting to connect to ", ip_address, ":", port)
	# connection_succeeded or connection_failed signals will fire

func get_player_list() -> Array:
	# Include host (ID 1) and connected peers
	if not multiplayer.is_server():
		return [] # Only server knows the full list reliably at start
	var players = [1] # Host is always 1
	players.append_array(multiplayer.get_peers())
	return players

func get_own_id() -> int:
	return multiplayer.get_unique_id()

# --- Signal Handlers ---

func _on_peer_connected(id: int):
	print("Player connected: ", id)
	# Important: Host needs to manage game state for the new player
	emit_signal("peer_list_changed")

func _on_peer_disconnected(id: int):
	print("Player disconnected: ", id)
	# Important: Host needs to clean up game state for this player
	emit_signal("peer_list_changed")

func _on_connection_succeeded():
	print("Connection successful!")
	emit_signal("connection_succeeded")

func _on_connection_failed():
	printerr("Connection failed!")
	multiplayer.set_multiplayer_peer(null) # Clean up peer
	emit_signal("connection_failed")

func _on_server_disconnected():
	print("Disconnected from server.")
	multiplayer.set_multiplayer_peer(null) # Clean up peer
	emit_signal("connection_failed") # Treat as failure for client UI
	# Maybe transition back to Main Menu
