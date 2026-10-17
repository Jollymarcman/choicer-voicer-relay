extends Control

@onready var plmic_spectrum_effect: AudioEffectSpectrumAnalyzerInstance = AudioServer.get_bus_effect_instance(AudioServer.get_bus_index("Plmic"), 8)

@onready var pitch_drawer = get_parent().get_node("PitchDrawer")

var plmic_color: = Color("00ffff")
var plmic_color_max: = Color(plmic_color, 0.44)
var plmic_color_pitch: = Color("00ff00")

var plmic_history_max: PackedByteArray
var plmic_history_avg: PackedByteArray
var plmic_history_pitch: PackedByteArray


const PITCH_C2: float = 65.41
const PITCH_C3: float = 130.81
const PITCH_C8: float = 4186.0
const PITCH_C9: float = 8372.0
const MIN_DB: float = 60.0
func CollectFrameSamples():

	var mag: float = plmic_spectrum_effect.get_magnitude_for_frequency_range(PITCH_C2, PITCH_C9, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX).length()

	var percent: float = clampf((MIN_DB + linear_to_db(mag)) / MIN_DB, 0.0, 1.0)
	var byte: int = floori(percent * 255)
	plmic_history_max.append(byte)

	mag = plmic_spectrum_effect.get_magnitude_for_frequency_range(PITCH_C2, PITCH_C9, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE).length()

	percent = clampf((MIN_DB + linear_to_db(mag)) / MIN_DB, 0.0, 1.0)
	byte = floori(percent * 255)
	plmic_history_avg.append(byte)

	plmic_history_pitch.append(CollectPitchSamples())



const DIVISIONS: float = 128
const HEIGHT: float = 128

const HZMAX: float = PITCH_C9
func CollectPitchSamples() -> int:
	var pitch_set: PackedByteArray = []
	var hz_min: float = PITCH_C3
	var hz_max: float
	for d in range(DIVISIONS):
		hz_max = HZMAX / DIVISIONS * (d + 1)
		var mag: float = plmic_spectrum_effect.get_magnitude_for_frequency_range(hz_min, hz_max, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX).length()
		var high: float = plmic_spectrum_effect.get_magnitude_for_frequency_range(8372, 16744, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE).length()
		mag = clampf((MIN_DB + linear_to_db(mag)) / MIN_DB, 0, 1)
		high = clampf((MIN_DB + linear_to_db(high)) / MIN_DB, 0, 1)
		if high > mag:
			pitch_set.append(int(high * 255))
		else:
			pitch_set.append(int(mag * 128))

		hz_min = hz_max
	return floori(AverageFromPitchSet(pitch_set))


func CollectPitchSamplesUneven() -> int:
	var pitch_set: PackedByteArray = []
	var hz_min: float = 7.929
	var hz_max: float = 250.19
	for d in range(DIVISIONS):

		var mag: float = plmic_spectrum_effect.get_magnitude_for_frequency_range(hz_min, hz_max, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX).length()
		mag = clamp((MIN_DB + linear_to_db(mag)) / MIN_DB, 0, 1)
		pitch_set.append(int(mag * 255))
		hz_min = hz_max
		hz_max += hz_max / 1.01105
	return floori(AverageFromPitchSet(pitch_set))


func AverageFromPitchSet(pitch_set: PackedByteArray) -> float:
	var sum: int = 0
	for sample in pitch_set:
		sum += sample
	var expected_value: float = 0.0
	for idx in pitch_set.size():
		expected_value += pitch_set[idx] * idx
	return expected_value / float(sum)



func ClearHistory():
	plmic_history_avg.clear()
	plmic_history_max.clear()
	plmic_history_pitch.clear()


func Reset():
	ClearHistory()
	queue_redraw()



func _draw():
	DrawSample()


func DrawSample():
	var waveheight: float = size.y / 128.0 / 2.0
	var y_pos: float = position.y + size.y / 2.0
	InterpolatedRect(plmic_history_max, waveheight, y_pos, plmic_color_max)
	InterpolatedRect(plmic_history_avg, waveheight, y_pos, plmic_color)

	waveheight = (size.y * 0.4)
	for pitch_idx in plmic_history_pitch.size():
		var pitch_sample: float = (2.5 - plmic_history_pitch[pitch_idx] / float(DIVISIONS)) * waveheight
		draw_line(Vector2(pitch_idx * PIXELSPERFRAME, pitch_sample), \
		Vector2(pitch_idx * PIXELSPERFRAME + PIXELSPERFRAME, pitch_sample), plmic_color_pitch, 2.0)


const PIXELSPERFRAME: float = 3.0
func InterpolatedRect(sample: PackedByteArray, waveheight: float, y_pos: float, clr: Color):
	for idx in sample.size():
		if idx == 0:
			var height: float = max(1.0, sample[idx] * waveheight)
			draw_rect(Rect2(Vector2(idx * PIXELSPERFRAME, y_pos - height / 2.0), \
			Vector2(PIXELSPERFRAME, height)), clr, true)
		elif idx != sample.size() - 1:
			var height: float = max(1.0, (sample[idx] * 2.0 + sample[idx - 1]) / 3.0 * waveheight)
			draw_rect(Rect2(Vector2(idx * PIXELSPERFRAME, y_pos - height / 2.0), \
			Vector2(PIXELSPERFRAME - 2.0, height)), clr, true)
			height = max(1, sample[idx] * waveheight)
			draw_rect(Rect2(Vector2(idx * PIXELSPERFRAME + 1, y_pos - height / 2.0), \
			Vector2(PIXELSPERFRAME - 2.0, height)), clr, true)
			height = max(1, (sample[idx] * 2.0 + sample[idx + 1]) / 3.0 * waveheight)
			draw_rect(Rect2(Vector2(idx * PIXELSPERFRAME + 2.0, y_pos - height / 2.0), \
			Vector2(PIXELSPERFRAME - 2.0, height)), clr, true)
		else:
			var height: float = max(1.0, (sample[idx] * 2.0 + sample[idx - 1]) / 3.0 * waveheight)
			draw_rect(Rect2(Vector2(idx * PIXELSPERFRAME, y_pos - height / 2.0), \
			Vector2(PIXELSPERFRAME - 2.0, height)), clr, true)
			height = max(1.0, sample[idx] * waveheight)
			draw_rect(Rect2(Vector2(idx * PIXELSPERFRAME + 1.0, y_pos - height / 2.0), \
			Vector2(PIXELSPERFRAME - 1.0, height)), clr, true)



func SamplePlmic():
	CollectFrameSamples()

func Update():
	queue_redraw()

func get_plmic_data() -> Dictionary:
	return {
		"average": plmic_history_avg.duplicate(),
		"max": plmic_history_max.duplicate(),
		"pitch": plmic_history_pitch.duplicate()
	}

func receive_plmic_data(d: Dictionary):
	plmic_history_avg = d.average
	plmic_history_max = d.max
	plmic_history_pitch = d.pitch
	queue_redraw()


func set_plmic_data(d: Dictionary):
	plmic_history_avg = d.average.duplicate()
	plmic_history_max = d.max.duplicate()
	plmic_history_pitch = d.pitch.duplicate()




func crop_to_right(samples: int):
	var sz: int = plmic_history_avg.size()
	if sz > samples:
		plmic_history_avg = plmic_history_avg.slice(sz - samples, sz)
		plmic_history_max = plmic_history_max.slice(sz - samples, sz)
		plmic_history_pitch = plmic_history_pitch.slice(sz - samples, sz)
