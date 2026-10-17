extends Node


func reduce_recording_sample_rate(input: AudioStreamWAV, sample_rate_index: int = Profile.mic_crust_sample_rate_index) -> AudioStreamWAV:
	sample_rate_index = 2 ** clampi(sample_rate_index, 0, 5)
	var data := input.get_data().duplicate()
	var crusted_data := PackedByteArray()
	for datapoint_index in range(0, data.size(), sample_rate_index * 4):
		var crust_repeat := data.slice(datapoint_index, datapoint_index + 4)
		for _index in sample_rate_index:
			crusted_data.append_array(crust_repeat)
	var crust_audio := input.duplicate(true) as AudioStreamWAV
	crust_audio.set_data(crusted_data)
	return crust_audio
