extends Node

const MAX_PLAYERS: int = 8
const RELAY_URL := "wss://choicer-voicer-relay-marc.onrender.com"
const RELAY_SETTINGS_PATH := "user://online_multiplayer.cfg"

signal status_changed(message: String)
signal roster_changed(players: Array)
signal lobby_started(session_type: int, dub_style: int)
signal dub_pack_received(pack_path: String, display_name: String)
signal pack_sync_received(message: Dictionary)
signal recording_queue_received(queue_id: int, clips: Array, settings: Dictionary)
signal recording_queue_cancelled(queue_id: int, reason: String)
signal recording_requested(request_id: int, clip: Dictionary)
signal character_choice_requested(request_id: int, options: Array, mystery: bool, max_choices: int)
signal telephone_progress_received(order: Array, active_index: int, status: String)
signal playback_begin_received(label: String)
signal playback_clip_received(file_name: String, wav: Dictionary)
signal playback_end_received
signal playback_go_received
signal kicked

const PROTOCOL_VERSION := 7
const SOCKET_BUFFER_BYTES := 64 * 1024 * 1024
const CONNECT_TIMEOUT_SECONDS := 25.0
const RETRY_DELAYS: Array[float] = [0.5, 1.0, 2.0, 4.0, 6.0, 10.0, 15.0, 20.0]

var display_name := "Player"
var room_code := ""
var roster: Dictionary = {}
var connected := false
var session_started := false
var _configured_relay_url := RELAY_URL

var _socket: WebSocketPeer
var _peer_id := 0
var _resume_token := ""
var _registration_sent := false
var _connect_elapsed := 0.0
var _retry_wait := -1.0
var _retry_attempt := 0
var _keepalive_elapsed := 0.0
var _active_queue_id := 0


func _ready() -> void:
	_load_relay_setting()


func get_configured_relay_url() -> String:
	return _configured_relay_url


func set_configured_relay_url(value: String) -> Dictionary:
	var normalized_url := normalize_relay_url(value)
	if normalized_url.is_empty():
		return {"ok": false, "error": "Enter a valid ws:// or wss:// relay address."}
	var config := ConfigFile.new()
	config.set_value("online", "relay_url", normalized_url)
	var error := config.save(RELAY_SETTINGS_PATH)
	if error != OK:
		return {"ok": false, "error": "Could not save relay settings (%s)." % error_string(error)}
	_configured_relay_url = normalized_url
	return {"ok": true, "url": normalized_url}


func reset_configured_relay_url() -> Dictionary:
	return set_configured_relay_url(RELAY_URL)


static func normalize_relay_url(value: String) -> String:
	var url := value.strip_edges()
	if url.begins_with("https://"):
		url = "wss://" + url.substr(8)
	elif url.begins_with("http://"):
		url = "ws://" + url.substr(7)
	elif not url.contains("://"):
		url = "wss://" + url
	if not url.begins_with("wss://") and not url.begins_with("ws://"):
		return ""
	if url.contains(" ") or url.contains("\t") or url.contains("\n") or url.contains("\r"):
		return ""
	var authority := url.substr(url.find("://") + 3).split("/", false, 1)[0].split("?", false, 1)[0].split("#", false, 1)[0]
	if authority.is_empty():
		return ""
	return url


func _load_relay_setting() -> void:
	var config := ConfigFile.new()
	if config.load(RELAY_SETTINGS_PATH) != OK:
		return
	var saved_url := normalize_relay_url(str(config.get_value("online", "relay_url", RELAY_URL)))
	if not saved_url.is_empty():
		_configured_relay_url = saved_url


func _process(delta: float) -> void:
	if _retry_wait >= 0.0:
		_retry_wait -= delta
		if _retry_wait <= 0.0:
			_retry_wait = -1.0
			_connect()
	if not _socket:
		return
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			_connect_elapsed += delta
			if _connect_elapsed >= CONNECT_TIMEOUT_SECONDS:
				_socket = null
				_schedule_retry("The relay did not answer in time.")
		WebSocketPeer.STATE_OPEN:
			_connect_elapsed = 0.0
			if not _registration_sent:
				_send_registration()
			while _socket and _socket.get_available_packet_count() > 0:
				var packet := _socket.get_packet()
				if _socket.was_string_packet():
					_handle_control(packet.get_string_from_utf8())
				else:
					_handle_binary(packet)
			_keepalive_elapsed += delta
			if _keepalive_elapsed >= 10.0:
				_keepalive_elapsed = 0.0
				_socket.send_text(JSON.stringify({"type": "keepalive"}))
		WebSocketPeer.STATE_CLOSED:
			_handle_socket_closed()


func join(code: String, player_name: String) -> void:
	leave("")
	room_code = code.strip_edges().to_upper()
	display_name = player_name.strip_edges().left(24)
	if display_name.is_empty():
		display_name = "Player"
	if room_code.is_empty():
		_set_status("Enter the host's room code first.")
		return
	if _configured_relay_url.is_empty():
		_set_status("Set a valid relay address before joining.")
		return
	_set_status("Connecting to room %s; a sleeping relay can take about a minute..." % room_code)
	_connect()


func leave(reason: String = "Offline") -> void:
	if _socket and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.close(1000, "Session closed")
	_socket = null
	connected = false
	session_started = false
	roster.clear()
	_peer_id = 0
	_resume_token = ""
	_registration_sent = false
	_connect_elapsed = 0.0
	_retry_wait = -1.0
	_retry_attempt = 0
	_active_queue_id = 0
	if not reason.is_empty():
		_set_status(reason)
	roster_changed.emit([])


func _connect() -> void:
	_registration_sent = false
	_connect_elapsed = 0.0
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = SOCKET_BUFFER_BYTES
	_socket.outbound_buffer_size = SOCKET_BUFFER_BYTES
	_socket.max_queued_packets = 256
	_socket.heartbeat_interval = 10.0
	var error := _socket.connect_to_url(_configured_relay_url)
	if error != OK:
		_socket = null
		_schedule_retry("Could not start the relay connection (error %s)." % error)


func _send_registration() -> void:
	_registration_sent = true
	if not _resume_token.is_empty() and _peer_id > 0:
		_socket.send_text(JSON.stringify({
			"type": "resume", "protocol": PROTOCOL_VERSION, "room": room_code,
			"peerId": _peer_id, "resumeToken": _resume_token, "name": display_name,
		}))
	else:
		_socket.send_text(JSON.stringify({
			"type": "join", "protocol": PROTOCOL_VERSION,
			"room": room_code, "name": display_name,
		}))


func _schedule_retry(reason: String) -> void:
	var delay := RETRY_DELAYS[mini(_retry_attempt, RETRY_DELAYS.size() - 1)]
	_retry_attempt += 1
	_retry_wait = delay
	_set_status("%s Retry in %.1f seconds..." % [reason, delay])


func _handle_socket_closed() -> void:
	if not _socket:
		return
	var code := _socket.get_close_code()
	var reason := _socket.get_close_reason()
	_socket = null
	connected = false
	# These responses will not improve by repeatedly reconnecting. Return the
	# player to the join form with a useful explanation instead.
	if code in [4001, 4002, 4003, 4004]:
		var message := reason
		match code:
			4001: message = "The host disconnected."
			4002: message = "The host is using an incompatible game version."
			4003: message = "That room is full."
			4004: message = "Room not found. Check the room code."
		leave(message)
		return
	# If the relay forgot only this browser's resume slot, rejoin the still-live
	# room as a fresh guest instead of making the player refresh the page.
	if code == 4006:
		_peer_id = 0
		_resume_token = ""
	_schedule_retry(reason if not reason.is_empty() else "Relay connection closed.")


func _handle_control(text: String) -> void:
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return
	var message: Dictionary = parsed
	match str(message.get("type", "")):
		"joined", "resumed":
			_peer_id = int(message.get("peerId", _peer_id))
			_resume_token = str(message.get("resumeToken", _resume_token))
			room_code = str(message.get("room", room_code))
			connected = true
			_retry_attempt = 0
			_retry_wait = -1.0
			_set_status("Connected to room %s. Waiting for the host..." % room_code)


func _handle_binary(packet: PackedByteArray) -> void:
	if packet.size() < 5 or _decode_u32_be(packet) != 1:
		return
	var decoded = bytes_to_var(packet.slice(4))
	if not decoded is Dictionary:
		return
	var message: Dictionary = decoded
	match str(message.get("type", "")):
		"roster":
			roster.clear()
			for player_value in message.get("players", []):
				if player_value is Dictionary:
					var player: Dictionary = player_value
					roster[int(player.get("peer_id", 0))] = player
			roster_changed.emit(roster.values())
		"start":
			session_started = true
			_set_status("Video Dub started. Waiting for the host's pack...")
			lobby_started.emit(int(message.get("session_type", 0)), int(message.get("dub_style", 0)))
		"dub_pack":
			dub_pack_received.emit(str(message.get("path", "")), str(message.get("name", "Video Dub")))
		"pack_sync_offer", "pack_sync_begin", "pack_sync_file_begin", "pack_sync_file_chunk", "pack_sync_file_end", "pack_sync_end":
			pack_sync_received.emit(message)
		"record_queue_begin":
			if _active_queue_id == 0:
				_active_queue_id = int(message.get("queue_id", 0))
				recording_queue_received.emit(_active_queue_id, message.get("clips", []), message.get("settings", {}))
		"record_queue_cancel":
			var queue_id := int(message.get("queue_id", 0))
			if queue_id == _active_queue_id:
				_active_queue_id = 0
				recording_queue_cancelled.emit(queue_id, str(message.get("reason", "Skipped by host")))
		"record_request":
			recording_requested.emit(int(message.get("request_id", 0)), message.get("clip", {}))
		"character_choice_request":
			character_choice_requested.emit(int(message.get("request_id", 0)), message.get("options", []), false, int(message.get("max_choices", 1)))
		"mystery_character_assignment":
			character_choice_requested.emit(int(message.get("request_id", 0)), [str(message.get("character", ""))], true, 1)
		"telephone_progress":
			telephone_progress_received.emit(message.get("order", []), int(message.get("active_index", -1)), str(message.get("status", "")))
		"dub_playback_begin":
			playback_begin_received.emit(str(message.get("label", "Video Dub")))
		"dub_playback_clip":
			playback_clip_received.emit(str(message.get("file_name", "")), message.get("wav", {}))
		"dub_playback_end":
			playback_end_received.emit()
		"dub_playback_go":
			playback_go_received.emit()
		"host_kick":
			leave("You were removed by the host.")
			kicked.emit()


func send_pack_status(status: String, detail: String = "") -> void:
	_send_message({"type": "pack_sync_status", "status": status, "detail": detail.left(160)})


func send_queue_progress(queue_id: int, clip_index: int, status: String) -> void:
	if queue_id == _active_queue_id:
		_send_message({"type": "record_queue_progress", "queue_id": queue_id, "clip_index": clip_index, "status": status.left(40)})


func send_queue_recording(queue_id: int, clip_index: int, result: Dictionary) -> void:
	if queue_id == _active_queue_id:
		_send_message({"type": "record_queue_result", "queue_id": queue_id, "clip_index": clip_index, "result": result})


func finish_queue(queue_id: int) -> void:
	if queue_id == _active_queue_id:
		_send_message({"type": "record_queue_finished", "queue_id": queue_id})
		_active_queue_id = 0


func send_recording(request_id: int, result: Dictionary) -> void:
	_send_message({"type": "record_result", "request_id": request_id, "result": result})


func send_character_choice(request_id: int, choice: String, choices: Array[String] = []) -> void:
	var selected := choices.duplicate()
	if selected.is_empty() and not choice.is_empty():
		selected.append(choice)
	_send_message({"type": "character_choice_result", "request_id": request_id, "choice": choice, "choices": selected})


func send_playback_ready() -> void:
	_send_message({"type": "dub_playback_ready"})


func _send_message(message: Dictionary) -> bool:
	if not _socket or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var payload := var_to_bytes(message)
	var packet := PackedByteArray([0, 0, 0, 1])
	packet.append_array(payload)
	return _socket.send(packet, WebSocketPeer.WRITE_MODE_BINARY) == OK


func wav_to_payload(wav: AudioStreamWAV) -> Dictionary:
	if not wav:
		return {}
	return {"data": wav.data, "format": wav.format, "mix_rate": wav.mix_rate, "stereo": wav.stereo}


func wav_from_payload(payload: Dictionary) -> AudioStreamWAV:
	var data: PackedByteArray = payload.get("data", PackedByteArray())
	if data.is_empty():
		return null
	var wav := AudioStreamWAV.new()
	wav.data = data
	wav.format = int(payload.get("format", AudioStreamWAV.FORMAT_16_BITS))
	wav.mix_rate = int(payload.get("mix_rate", 48000))
	wav.stereo = bool(payload.get("stereo", true))
	return wav


func stream_from_payload(payload: Dictionary) -> AudioStream:
	var data: PackedByteArray = payload.get("data", PackedByteArray())
	match str(payload.get("kind", "")):
		"wav":
			return wav_from_payload(payload)
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = data
			return mp3
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(data)
	return null


func _decode_u32_be(packet: PackedByteArray) -> int:
	return (int(packet[0]) << 24) | (int(packet[1]) << 16) | (int(packet[2]) << 8) | int(packet[3])


func _set_status(message: String) -> void:
	status_changed.emit(message)
