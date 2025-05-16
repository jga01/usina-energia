# File: scripts/Audio.gd
extends Node

var bgm_player: AudioStreamPlayer

# --- IMPORTANT ---
# USER ACTION REQUIRED:
# 1. Create a folder named "audio" inside your "assets" folder (i.e., "res://assets/audio/").
# 2. Place your background music file (e.g., "bgm_menu.ogg" or "bgm_menu.wav") into this "res://assets/audio/" folder.
#    - Using .ogg or .wav is recommended for seamless looping.
#    - If using .mp3, ensure you enable "Loop" in Godot's import settings for that MP3 file.
# 3. Place your button press sound effect file (e.g., "sfx_mash.wav" or "sfx_mash.ogg") into "res://assets/audio/".
# 4. Update the constants below if your filenames are different.
const BGM_MENU_PATH = "res://assets/audio/bgm_menu.ogg" # Placeholder path for menu music
const BGM_GAMEPLAY_PATH = "res://assets/audio/bgm_gameplay.ogg"
const SFX_PLAYER_MASH_PATH = "res://assets/audio/sfx_mash.wav" # Placeholder for mash SFX

func _ready():
	bgm_player = AudioStreamPlayer.new()
	add_child(bgm_player)
	bgm_player.name = "BGMPlayer"
	# Optional: If you have configured audio buses (e.g., a "Music" bus), assign it here:
	# bgm_player.bus = "Music"
	print("Audio Manager initialized.")

func play_bgm(stream_path: String, should_loop: bool = true):
	if not is_instance_valid(bgm_player):
		printerr("Audio: BGMPlayer is not valid.")
		return

	if stream_path.is_empty():
		printerr("Audio: BGM stream path is empty.")
		stop_bgm() # Stop if path is empty
		return

	var new_stream = load(stream_path)
	if not new_stream is AudioStream:
		printerr("Audio: Failed to load BGM stream or not an AudioStream: ", stream_path)
		if is_instance_valid(bgm_player):
			bgm_player.stream = null # Ensure no old stream is playing
			bgm_player.stop()
		return

	# Check if the same stream with the same loop intention is already playing
	if is_instance_valid(bgm_player) and bgm_player.stream == new_stream and bgm_player.playing:
		var current_intended_loop = bgm_player.get_meta("intended_loop_mode", false)
		if current_intended_loop == should_loop:
			# print("Audio: BGM ", stream_path, " already playing with same loop mode.")
			return # Already playing this exact BGM with the same loop setting

	if is_instance_valid(bgm_player):
		bgm_player.stream = new_stream
		bgm_player.set_meta("intended_loop_mode", should_loop) # Store loop intention

		# Set loop property on the stream resource itself where applicable
		if new_stream is AudioStreamOggVorbis:
			new_stream.loop = should_loop
		elif new_stream is AudioStreamWAV:
			new_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if should_loop else AudioStreamWAV.LOOP_DISABLED
		elif new_stream is AudioStreamMP3:
			if should_loop:
				print("Audio: For MP3 looping, ensure 'Loop' is enabled in Godot's import settings for: ", stream_path)
		
		bgm_player.play()
		print("Audio: Playing BGM - ", stream_path, " (Loop: %s)" % should_loop)
	else:
		printerr("Audio: BGMPlayer became invalid before playing.")


func stop_bgm():
	if is_instance_valid(bgm_player) and bgm_player.playing:
		bgm_player.stop()
		bgm_player.stream = null
		bgm_player.remove_meta("intended_loop_mode")
		print("Audio: Stopped BGM.")


# --- SFX Function ---
func play_sfx(sfx_path: String, volume_db: float = 0.0, pitch_scale: float = 1.0, bus_name: String = "Master"):
	if sfx_path.is_empty():
		printerr("Audio: SFX path is empty.")
		return

	var sfx_stream = load(sfx_path)
	if not sfx_stream is AudioStream:
		printerr("Audio: Failed to load SFX stream or not an AudioStream: ", sfx_path)
		return

	var sfx_player = AudioStreamPlayer.new()
	add_child(sfx_player) # Add to the Audio node so it persists across scenes if needed, but usually SFX are short
	
	sfx_player.stream = sfx_stream
	sfx_player.volume_db = volume_db
	sfx_player.pitch_scale = pitch_scale # Added pitch scale for variation
	sfx_player.bus = bus_name # Assign to an audio bus if you have one for SFX
	sfx_player.play()
	
	# Connect to 'finished' signal to queue_free() the sfx_player once it's done
	# Use call_deferred to ensure it's safe to queue_free
	sfx_player.finished.connect(sfx_player.queue_free.bind(), CONNECT_ONE_SHOT)
	# print("Audio: Playing SFX - ", sfx_path)

# Example:
# func set_bgm_volume(volume_db: float):
#    if is_instance_valid(bgm_player):
#        bgm_player.volume_db = volume_db
