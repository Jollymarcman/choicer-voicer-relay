class_name BrowserWaveform
extends Control

const BIN_COUNT := 160
const SOURCE_COLOR := Color("62e7ff")
const VOICE_COLOR := Color("ffb24a")

var source_peaks := PackedFloat32Array()
var voice_peaks := PackedFloat32Array()
var progress := 0.0
var show_voice := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 126)
	_reset_array(source_peaks)
	_reset_array(voice_peaks)


func reset_all() -> void:
	_reset_array(source_peaks)
	_reset_array(voice_peaks)
	progress = 0.0
	show_voice = false
	queue_redraw()


func reset_voice() -> void:
	_reset_array(voice_peaks)
	show_voice = true
	queue_redraw()


func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func add_source_peak(at_progress: float, magnitude: float) -> void:
	_set_peak(source_peaks, at_progress, magnitude)


func add_voice_peak(at_progress: float, magnitude: float) -> void:
	show_voice = true
	_set_peak(voice_peaks, at_progress, magnitude)


func _reset_array(values: PackedFloat32Array) -> void:
	values.resize(BIN_COUNT)
	values.fill(0.0)


func _set_peak(values: PackedFloat32Array, at_progress: float, magnitude: float) -> void:
	var index := clampi(floori(at_progress * float(BIN_COUNT)), 0, BIN_COUNT - 1)
	values[index] = maxf(values[index], clampf(magnitude, 0.0, 1.0))
	queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_style_box(_background_style(), bounds)
	var inner := Rect2(Vector2(14, 10), size - Vector2(28, 20))
	var middle := inner.position.y + inner.size.y * 0.5
	draw_line(Vector2(inner.position.x, middle), Vector2(inner.end.x, middle), Color(0.7, 0.9, 0.93, 0.22), 1.0)
	var bin_width := inner.size.x / float(BIN_COUNT)
	for index in BIN_COUNT:
		var x := inner.position.x + (float(index) + 0.5) * bin_width
		var source_height := _visible_height(source_peaks[index], inner.size.y * 0.45)
		draw_line(Vector2(x, middle - source_height), Vector2(x, middle + source_height), SOURCE_COLOR, maxf(1.0, bin_width * 0.68))
		if show_voice:
			var voice_height := _visible_height(voice_peaks[index], inner.size.y * 0.45)
			draw_line(Vector2(x, middle - voice_height), Vector2(x, middle + voice_height), VOICE_COLOR, maxf(1.0, bin_width * 0.34))
	var playhead_x := inner.position.x + inner.size.x * progress
	draw_line(Vector2(playhead_x, inner.position.y - 3), Vector2(playhead_x, inner.end.y + 3), Color.WHITE, 3.0)
	draw_circle(Vector2(playhead_x, inner.position.y - 3), 5.0, Color.WHITE)


func _visible_height(magnitude: float, maximum: float) -> float:
	if magnitude <= 0.0001:
		return 1.0
	return maxf(2.0, pow(clampf(magnitude, 0.0, 1.0), 0.48) * maximum)


func _background_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("11191b")
	style.border_color = Color("6fd9e8")
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	return style
