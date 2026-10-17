extends RefCounted


# The host recorder starts capturing 125 ms after it starts the prompt.  The
# remote recorder captures before the prompt and already removes that preroll,
# so advance remote takes by the same amount to keep both paths aligned.
const REMOTE_ALIGNMENT_SECONDS: float = 0.125


static func align_remote_take(input: AudioStreamWAV) -> AudioStreamWAV:
	return trim_start(input, REMOTE_ALIGNMENT_SECONDS)


static func trim_start(input: AudioStreamWAV, seconds: float) -> AudioStreamWAV:
	if not input or seconds <= 0.0:
		return input
	var bytes_per_sample := 1 if input.format == AudioStreamWAV.FORMAT_8_BITS else 2
	if input.format not in [AudioStreamWAV.FORMAT_8_BITS, AudioStreamWAV.FORMAT_16_BITS]:
		# AudioEffectRecord currently produces PCM, but leave unfamiliar compressed
		# formats untouched rather than cutting through an encoded block.
		return input
	var channel_count := 2 if input.stereo else 1
	var bytes_per_frame := bytes_per_sample * channel_count
	var frames_to_trim := maxi(0, roundi(seconds * float(input.mix_rate)))
	var byte_count := mini(input.data.size(), frames_to_trim * bytes_per_frame)
	# Keep PCM frames intact even if malformed input has an odd byte count.
	byte_count -= byte_count % bytes_per_frame
	var output := input.duplicate(true) as AudioStreamWAV
	output.data = input.data.slice(byte_count)
	return output
