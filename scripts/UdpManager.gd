# scripts/UdpManager.gd
extends Node

# Signal emitted when a valid player action command is received via UDP
# player_id: The integer ID of the player (e.g., 1, 2, ...)
# action: The string name of the action (e.g., "generate", "stabilize")
signal player_action_received(player_id: int, action: String)

# --- Configuration ---
const LISTEN_PORT: int = Config.DEFAULT_UDP_PORT
const MAX_PACKET_SIZE = 1024 # Max expected packet size in bytes

# --- State ---
var udp_peer: PacketPeerUDP = PacketPeerUDP.new()
var is_listening: bool = false

func _ready():
	print("UdpManager: Initializing...")
	start_listening()

func _notification(what):
	# Clean up the socket when the node is deleted
	if what == NOTIFICATION_PREDELETE:
		stop_listening()

func _process(_delta):
	if not is_listening:
		return

	# Check for incoming packets
	while udp_peer.get_available_packet_count() > 0:
		var packet_data: PackedByteArray = udp_peer.get_packet()
		var sender_ip: String = udp_peer.get_packet_ip()
		var sender_port: int = udp_peer.get_packet_port()

		# Decode packet data to string (assuming UTF-8)
		var message: String = packet_data.get_string_from_utf8().strip_edges()

		if not message.is_empty():
			# Optional: Log received message and sender
			print("UDP RX from %s:%d - %s" % [sender_ip, sender_port, message])
			_parse_message(message)
		else:
			printerr("UdpManager: Received empty packet from %s:%d" % [sender_ip, sender_port])


func start_listening(port: int = LISTEN_PORT):
	if is_listening:
		print("UdpManager: Already listening on port %d." % udp_peer.get_local_port())
		return

	var err = udp_peer.bind(port)
	if err != OK:
		printerr("UdpManager Error: Failed to start listening on port %d. Error code: %s" % [port, err])
		is_listening = false
	else:
		print("UdpManager: Now listening for UDP packets on port %d." % port)
		is_listening = true

func stop_listening():
	if is_listening:
		udp_peer.close()
		is_listening = false
		print("UdpManager: Stopped listening.")

func _parse_message(message: String):
	# Expected format: P<player_id>:<action>
	# Example: "P1:generate", "P2:stabilize"
	if not message.begins_with("P"):
		printerr("UdpManager: Invalid message format (doesn't start with P):", message)
		return

	# Split after 'P', max 1 split, don't allow empty parts
	var parts = message.substr(1).split(":", false, 1)
	if parts.size() != 2 or parts[0].is_empty() or parts[1].is_empty():
		printerr("UdpManager: Invalid message format (expected P<id>:<action>):", message)
		return

	var player_id_str = parts[0]
	var action_str = parts[1].strip_edges() # Ensure no trailing whitespace on action

	if not player_id_str.is_valid_int():
		printerr("UdpManager: Invalid player ID:", player_id_str)
		return

	var player_id = int(player_id_str)

	# Basic validation (optional, GameManager handles unknown actions too)
	# if player_id <= 0:
	#     printerr("UdpManager: Player ID must be positive:", player_id_str)
	#     return

	print("UdpManager: Parsed Action - Player:", player_id, "Action:", action_str)
	emit_signal("player_action_received", player_id, action_str)
