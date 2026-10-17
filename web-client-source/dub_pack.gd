extends RefCounted

const AUDIO_EXTENSIONS := ["wav", "mp3", "ogg"]
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const CONFIG_EXTENSIONS := ["ini", "cfg", "txt"]
const RESERVED_AUDIO_PREFIXES := ["_ignore", "_backing_track", "_dubrecord_freestyle"]


static func load_from_folder(folder: String) -> Dictionary:
	var root := folder.trim_suffix("/") + "/"
	if not DirAccess.dir_exists_absolute(root):
		return {"ok": false, "error": "Pack folder is missing."}
	var video_path := _find_sibling_path(root, "dub_video", ["ogv"])
	if video_path.is_empty():
		return {"ok": false, "error": "Pack has no dub_video.ogv file."}
	var video := VideoStreamTheora.new()
	video.file = video_path
	var backing: AudioStream = null
	var backing_path := _find_sibling_path(root, "_backing_track", AUDIO_EXTENSIONS)
	if not backing_path.is_empty():
		backing = load_audio(backing_path)
	var lines: Dictionary = {}
	_collect_lines(root, root, lines)
	if lines.is_empty():
		return {"ok": false, "error": "Pack has no timed dub lines."}
	return {"ok": true, "video": video, "backing": backing, "lines": lines, "folder": root}


static func _collect_lines(root: String, folder: String, output: Dictionary) -> void:
	for file_name in DirAccess.get_files_at(folder):
		var extension := file_name.get_extension().to_lower()
		if extension not in AUDIO_EXTENSIONS:
			continue
		var base := file_name.get_basename()
		var reserved := false
		for prefix in RESERVED_AUDIO_PREFIXES:
			if base.begins_with(prefix):
				reserved = true
				break
		if reserved:
			continue
		var file_path := folder.path_join(file_name)
		var config_path := _find_sibling_path(folder, base, CONFIG_EXTENSIONS)
		if config_path.is_empty():
			continue
		var config := ConfigFile.new()
		if config.load(config_path) != OK:
			continue
		var raw_timestamps = config.get_value("data", "dub_timestamps", [])
		var timestamps := PackedFloat32Array(raw_timestamps)
		if timestamps.is_empty():
			continue
		var characters := PackedStringArray(config.get_value("data", "dub_characters", []))
		var caption := str(config.get_value("data", "caption", ""))
		if caption.is_empty():
			var text_path := _find_sibling_path(folder, base, ["txt"])
			if not text_path.is_empty():
				caption = FileAccess.get_file_as_string(text_path).strip_edges()
		var texture: Texture2D = null
		var image_name := str(config.get_value("data", "image", ""))
		if not image_name.is_empty():
			texture = _find_texture(folder, image_name)
		if not texture:
			texture = _find_texture(folder, base)
		if not texture:
			texture = _find_texture(root, "_pack_filler_image")
		if not texture:
			texture = _find_texture(root, "_icon")
		var stream := load_audio(file_path)
		if not stream:
			continue
		output[base] = {
			"file_name": base,
			"audio_path": file_path,
			"stream": stream,
			"caption": caption,
			"characters": characters,
			"timestamps": timestamps,
			"texture": texture,
		}
	for directory in DirAccess.get_directories_at(folder):
		_collect_lines(root, folder.path_join(directory), output)


static func _find_texture(folder: String, name_or_file: String) -> Texture2D:
	var wanted_file := name_or_file.get_file()
	var wanted_extension := wanted_file.get_extension().to_lower()
	var wanted_base := wanted_file.get_basename() if wanted_extension in IMAGE_EXTENSIONS else wanted_file
	for actual_name in DirAccess.get_files_at(folder):
		if actual_name.get_basename().to_lower() != wanted_base.to_lower():
			continue
		var actual_extension := actual_name.get_extension().to_lower()
		if actual_extension not in IMAGE_EXTENSIONS:
			continue
		if wanted_extension.is_empty() or actual_extension == wanted_extension:
			return _load_texture(folder.path_join(actual_name))
	return null


static func _find_sibling_path(folder: String, base_name: String, extensions: Array) -> String:
	# Callers pass an already extension-free audio base. It may legitimately end
	# in a decimal timestamp (for example "line0.112"), so applying
	# get_basename() a second time would incorrectly turn it into "line0".
	var wanted_base := base_name.get_file().to_lower()
	for actual_name in DirAccess.get_files_at(folder):
		if actual_name.get_basename().to_lower() == wanted_base and actual_name.get_extension().to_lower() in extensions:
			return folder.path_join(actual_name)
	return ""


static func _load_texture(path: String) -> Texture2D:
	var image := Image.new()
	var bytes := FileAccess.get_file_as_bytes(path)
	var error := ERR_FILE_UNRECOGNIZED
	match path.get_extension().to_lower():
		"png": error = image.load_png_from_buffer(bytes)
		"jpg", "jpeg": error = image.load_jpg_from_buffer(bytes)
		"webp": error = image.load_webp_from_buffer(bytes)
	if error != OK:
		return null
	return ImageTexture.create_from_image(image)


static func load_audio(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	match path.get_extension().to_lower():
		"wav": return _wav_from_file_bytes(bytes)
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			return mp3
		"ogg": return AudioStreamOggVorbis.load_from_buffer(bytes)
	return null


static func _wav_from_file_bytes(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var channels := int(bytes.decode_u16(22))
	var sample_rate := int(bytes.decode_u32(24))
	var bits := int(bytes.decode_u16(34))
	var data_location := 36
	while data_location + 8 <= bytes.size() and bytes.slice(data_location, data_location + 4).get_string_from_ascii() != "data":
		data_location += 1
	if data_location + 8 > bytes.size():
		return null
	var data_size := mini(int(bytes.decode_u32(data_location + 4)), bytes.size() - data_location - 8)
	var wav := AudioStreamWAV.new()
	wav.mix_rate = sample_rate
	wav.stereo = channels == 2
	if bits == 8:
		wav.format = AudioStreamWAV.FORMAT_8_BITS
		var converted := PackedByteArray()
		converted.resize(data_size)
		for index in data_size:
			converted[index] = (int(bytes[data_location + 8 + index]) - 128) & 0xff
		wav.data = converted
	elif bits == 16:
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.data = bytes.slice(data_location + 8, data_location + 8 + data_size)
	else:
		return null
	return wav
