extends ColorRect

const DubRecordingTiming = preload("res://common/niche/dub_recording_timing.gd")

signal replay_finished

enum VCLIPSOURCE{STANDARD, SECONDARY, PAIR}
@export var vclip_source: VCLIPSOURCE

@onready var playbar = $MarginContainer2 / Control / Playbar
@onready var pecho_stream = $Audio / Pecho
@onready var plmic_stream = $Audio / Plmic
@onready var vclip_stream = $Audio / Vclip
@onready var waveform: ColorRect = $MarginContainer2 / HBoxContainer / WaveformDataDrawerDual
@onready var waveform_core: ColorRect = waveform

var plmic_record_effect: AudioEffectRecord = AudioServer.get_bus_effect(AudioServer.get_bus_index("Plmic"), 7)
var pecho: AudioStreamWAV

const BORDERMINSIZE: int = 164
const PIXELSPERFRAME: float = 3.0

var vclip_seconds_length: float
var stream_playing: float = false


func _ready():
	match vclip_source:



		VCLIPSOURCE.PAIR:
			vclip_stream = AudioStreamPlayer.new()
			waveform.vclip_spectrum_effect = AudioServer.get_bus_effect_instance(AudioServer.get_bus_index("Voice"), 0)


func Colorize(color_dict: Dictionary):
	waveform_core.Colorize(color_dict)
	playbar.texture.gradient.colors[1] = Color(color_dict.playbar)

	var border_color: Color = Color(color_dict.block_border)
	var border_gradient: Gradient = material.get_shader_parameter("palette").gradient
	border_gradient.colors[2] = border_color
	border_gradient.colors[1] = Color.from_hsv(border_color.h, sqrt(border_color.s), border_color.v)


func SetVclipAudio(wav: AudioStream) -> float:
	waveform.Reset()
	vclip_stream.stream = wav
	AssignVclipLength(wav.get_length())
	return wav.get_length()


func AssignVclipLength(seconds_length: float):
	var waveform_width: float = seconds_length * 60.0 * PIXELSPERFRAME
	custom_minimum_size.x = BORDERMINSIZE + floori(waveform_width)
	material.set_shader_parameter("node_size", custom_minimum_size)
	playbar.position.x = 0


func Reset():
	waveform.Reset()
	playbar.position.x = 0


func PlaybarLeft():
	var playbar_position: float = 0.0
	for i in range(24):
		if i > 4:
			playbar_position += PIXELSPERFRAME
			playbar.position.x = int(playbar_position)

		await get_tree().physics_frame







func Vclip():
	var vclip_trigger: bool = true
	var wave_width: int = int(custom_minimum_size.x)
	var right_cutoff_frames: int = int(wave_width / 3.0 - 24)
	for i in range(custom_minimum_size.x / 3 - 3):
		if i > 6:
			playbar.position.x = (i - 6) * 3
		if i > 24 and vclip_trigger:
			vclip_trigger = false
			vclip_stream.play()
		if (i > 26) and (i < right_cutoff_frames):
			waveform.SampleVclip()

		await get_tree().physics_frame


func microphone_on() -> void : if !plmic_stream.playing: plmic_stream.play()

func Plmic():
	vclip_stream.bus = "VclipPlayback"
	var vclip_trigger: bool = true
	var record_stop_trigger: bool = true
	var wave_width: int = int(custom_minimum_size.x)
	var right_cutoff_frames: int = int(wave_width / 3.0 - 24)
	microphone_on()
	plmic_record_effect.set_recording_active(true)
	for i in range(custom_minimum_size.x / 3 - 3):
		if (i > 6):
			playbar.position.x = (i - 6) * 3
		if (i > 24) and vclip_trigger:
			vclip_trigger = false
			vclip_stream.play()
		if (i > 33) and (i < right_cutoff_frames + 4):
			waveform.SamplePlmic()
		elif (i > right_cutoff_frames + 4) and record_stop_trigger:
			plmic_record_effect.set_recording_active(false)
			plmic_stream.stop()
		await get_tree().physics_frame
	var recording: AudioStreamWAV = plmic_record_effect.get_recording()
	if Profile.mic_crust_sample_rate_on: recording = GMCrust.reduce_recording_sample_rate(recording)
	pecho = CropWav(recording)
	vclip_stream.bus = "Vclip"

func ReplayPreSetPlaybar():
	playbar.position.x = 0

func Pecho():
	print("WaveformMantle | %s" % - M.data.settings.match_settings.dual_player_playback)
	var pecho_trigger: bool = true
	pecho_stream.stream = pecho
	for i in range(custom_minimum_size.x / 3 - 3):
		if i > 6:
			playbar.position.x = (i - 6) * 3
		if i > 24 and pecho_trigger:
			pecho_trigger = false
			pecho_stream.play( - M.data.settings.match_settings.dual_player_playback)

		await get_tree().physics_frame


func WaveformImage() -> Image:
	var waveform_rect: Rect2i = waveform.get_global_rect()

	waveform_rect.position.y += 2
	waveform_rect.size.y -= 2



	var TEST_viewport_texture_size: Vector2 = get_window().size
	var TEST_get_viewport_rect: Rect2 = get_viewport_rect()
	var viewport_scaling: float = TEST_viewport_texture_size.x / TEST_get_viewport_rect.size.x


	waveform_rect = Rect2i(floor(waveform_rect.position * viewport_scaling), floor(waveform_rect.size * viewport_scaling))
	return get_window().get_viewport().get_texture().get_image().get_region(waveform_rect)


func CropWav(input: AudioStreamWAV, time: float = 0.4) -> AudioStreamWAV:





	print("WaveformMantle | pre-crop length: %1.3f" % input.get_length())
	var new_wav: AudioStreamWAV = DubRecordingTiming.trim_start(input, time)
	print("WaveformMantle | post-crop length: %1.3f" % new_wav.get_length())
	return new_wav


func StopBoth():
	vclip_stream.stop()
	pecho_stream.stop()


func ReplayJustBoth():
	StopBoth()
	vclip_stream.play()
	pecho_stream.play( - M.data.settings.match_settings.dual_player_playback)


func ReplayJustVclip():
	StopBoth()
	vclip_stream.play()


func ReplayJustPecho():
	StopBoth()
	pecho_stream.play( - M.data.settings.match_settings.dual_player_playback)


func get_plmic_data() -> Dictionary:
	return waveform.get_plmic_data()

func get_vclip_data() -> Dictionary:
	return waveform.get_vclip_data()


func set_vclip_data(d: Dictionary):
	waveform.set_vclip_data(d)

func set_plmic_data(d: Dictionary):
	waveform.set_plmic_data(d)


func SavePecho(file_name: String):
	var date_dict: Dictionary = Time.get_datetime_dict_from_system()
	var timestamp: String = str(date_dict.year) + str(date_dict.month) + str(date_dict.day) + str(date_dict.hour) + str(date_dict.minute)
	print("WaveformPlayControl | Save pecho as %s_%s" % [file_name, timestamp])
	pecho.save_to_wav("user://game/recordings/%s_%s_player.wav" % [file_name, timestamp])


func _play_finished():
	replay_finished.emit()

func ClearPlmicData():
	waveform.plmic_drawer.ClearHistory()
	waveform.queue_redraw()



var continue_live_record: bool = false
func record_live():
	print("initiate live_record")
	waveform_core.ClearHistory()
	continue_live_record = true

	while continue_live_record:
		waveform_core.plmic_drawer.crop_to_right(105)
		waveform_core.SamplePlmic()

		await get_tree().physics_frame
