extends Control

signal replay_finished

@onready var ready_set_go_capsule = $ReadySetGoCapsule
@onready var record_backlight: TextureRect = %MainLightBackColor
@onready var wave_control: ColorRect = %WaveformPlayControl
@onready var waveform_mantle: ColorRect = wave_control
@onready var bottom_bar: TextureRect = %BotBar
@onready var recording_light_element: MarginContainer = %RecLight
@onready var lbl_caption: Label = %LblHint
@onready var rec_indicator: ColorRect = %RecIndicator
@onready var buffer: Control = %Buffer

@onready var countdown_blip: AudioStreamPlayer = %CountdownBlip
@onready var countdown_final: AudioStreamPlayer = %CountdownFinal
@onready var backlights: HBoxContainer = %Backlights


@export var backlight_main: Array[TextureRect]
@export var backlight_innermost: Array[TextureRect]
@export var backlight_meddistance: Array[TextureRect]
@export var backlight_furthest: Array[TextureRect]


const BORDERMINSIZE: int = 164
const PIXELSPERFRAME: float = 3.0

var v: VclipResource

var vclip_seconds_length: float
var stream_playing: bool = false
var vclip_filename: String

var backlight_color: Color


func _ready():
	# These are the desktop game's default studio colours. The browser guest
	# uses the original recorder scene without loading the desktop pack manager.
	Colorize({
		"body": "d1f6ff",
		"block_border": "80e5ff",
		"playbar": "cc0000",
		"record_light": "7dcde3",
		"record_backlight": "a1d6d5",
		"voice_color": "ff00ff",
		"user_color": "00ffff",
	})
	_setup_readysetgo_type()
	visibility_changed.connect( func() -> void : if visible: fix_stretch())


func NewVclipPlay(new_vclip: VclipResource):
	v = new_vclip
	lbl_caption.modulate.a = 0.0
	SetVclipAudio(v.audio)
	await get_tree().create_timer(0.25).timeout
	await wave_control.Vclip()
	if Profile.show_captions:
		if v.hint != "":
			await expand_caption_label(v.hint)
			lbl_caption.text = v.hint
			RevealHint()
			await get_tree().create_timer(Profile.caption_wait_time).timeout


	new_vclip.round_data = get_vclip_data().duplicate(true)


func PlmicRecord() -> Dictionary:
	match Profile.debug_countdown_type:
		0: ReplayPresetPlaybar()
		1:
			ready_set_go_capsule.add_child(load("res://scene/overlay/ready_set_go.tscn").instantiate())
			await ready_set_go_capsule.get_child(0).finished
			ReplayPresetPlaybar()
			await get_tree().create_timer(0.5).timeout
	await PlayPlmic()
	await get_tree().create_timer(1.0).timeout
	return get_plmic_data().duplicate(true)


func ReplayPresetPlaybar(): waveform_mantle.ReplayPreSetPlaybar()

func Replay():
	await waveform_mantle.Pecho()
	replay_finished.emit()


func Colorize(color_dict: Dictionary):
	waveform_mantle.Colorize(color_dict)
	$VBoxContainer / BotBar.self_modulate = Color(color_dict.body)
	backlight_color = Color(color_dict.record_backlight)

	for arr: Array[TextureRect] in [backlight_furthest, backlight_meddistance, backlight_innermost, backlight_main]: for light: TextureRect in arr: light.modulate = Color.BLACK
	var record_light_color_main: Color = Color(color_dict.record_light)
	var rec_material: ShaderMaterial = rec_indicator.material
	var rec_gradient: Gradient = rec_material.get_shader_parameter("palette").gradient
	rec_gradient.colors[6] = Color(record_light_color_main, 0.384)
	rec_gradient.colors[5] = Color(record_light_color_main * 0.785, 1.0)
	rec_gradient.colors[4] = Color(record_light_color_main, 1.0)


func MictestReduction():
	$VBoxContainer / BotBar.self_modulate = Color.TRANSPARENT
	$VBoxContainer / BotBar / VBoxContainer / MarginContainer2.visible = false
	SetVclipAudio(load("res://audio/sfx/silence2-50.wav"))


func SetVclipAudio(wav: AudioStream):
	vclip_seconds_length = wave_control.SetVclipAudio(wav)
	fix_stretch()


func fix_stretch() -> void :
	await get_tree().process_frame
	if vclip_seconds_length > 5.6:
		waveform_mantle.pivot_offset.x = waveform_mantle.custom_minimum_size.x / 2.0
		waveform_mantle.scale = Vector2(5.6 / vclip_seconds_length, 1.0)
	else: waveform_mantle.scale = Vector2.ONE


func PlayVclip(): await wave_control.PlayVclip()


func PlayPlmic():
	match Profile.debug_countdown_type:
		0:
			backlights_on()
			await get_tree().create_timer(Profile.countdown_time - 0.4).timeout
			await wave_control.Plmic()
			backlights_off()
		1:
			var tween = create_tween()
			tween.tween_property(record_backlight, "modulate", backlight_color, 0.1)
			await wave_control.Plmic()
			var tween2 = create_tween()
			tween2.tween_property(record_backlight, "modulate", Color.BLACK, 0.2)


func WaveformImage() -> Image: return wave_control.WaveformImage()
func StopBoth(): wave_control.StopBoth()
func ReplayJustVclip(): StopBoth();wave_control.ReplayJustVclip()
func ReplayJustPecho(): wave_control.ReplayJustPecho()
func ReplayJustBoth(): wave_control.ReplayJustBoth()

func get_plmic_data() -> Dictionary: return wave_control.get_plmic_data()
func get_vclip_data() -> Dictionary: return wave_control.get_vclip_data()
func SavePecho(): wave_control.SavePecho(vclip_filename)


func RevealHint():
	var tween = create_tween().set_trans(Tween.TRANS_CIRC)
	tween.tween_property(lbl_caption, "modulate:a", 1.0, 0.75)


func _on_waveform_play_control_replay_finished(): replay_finished.emit()

func ClearPlmicData(): wave_control.ClearPlmicData()


func HideNonMantleItems(do_hide: bool) -> void :
	bottom_bar.self_modulate.a = float( !do_hide)
	backlights.modulate.a = float( !do_hide)
	lbl_caption.modulate.a = float( !do_hide)


func microphone_on() -> void : waveform_mantle.microphone_on()


func expand_caption_label(text: String) -> void :
	var font: Font = lbl_caption.get_theme_font("font")
	var text_block_size: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, 1152)
	if !text_block_size.y <= 21.0:
		var tween: Tween = get_tree().create_tween().set_trans(Tween.TRANS_CIRC).parallel()

		var real_lines: int = floor(text_block_size.y / 21.0)
		var actual_y_size: float = real_lines * 24.0
		actual_y_size = maxi(0, 324 - actual_y_size)
		await tween.tween_property(buffer, "custom_minimum_size:y", actual_y_size, 0.3).finished


func hide_and_reset_caption() -> void :
	buffer.custom_minimum_size.y = 324.0
	lbl_caption.text = ""
	lbl_caption.custom_minimum_size.y = 21.0
	lbl_caption.modulate.a = 0.0


func backlights_off() -> void :
	const WAIT_TIME: float = 0.03
	for arr: Array[TextureRect] in [backlight_main, backlight_innermost, backlight_meddistance, backlight_furthest]:
		for light: TextureRect in arr: var tween: Tween = create_tween();tween.tween_property(light, "modulate", Color.BLACK, 0.15)
		await get_tree().create_timer(WAIT_TIME).timeout

func backlights_on() -> void :
	var per_blip_wait_time: float = Profile.countdown_time / 3.0
	for arr: Array[TextureRect] in [backlight_furthest, backlight_meddistance, backlight_innermost]:
		countdown_blip.play()
		for light: TextureRect in arr: var tween: Tween = create_tween();tween.tween_property(light, "modulate", backlight_color, 0.1)
		await get_tree().create_timer(per_blip_wait_time).timeout
	for light: TextureRect in backlight_main:

		var tween: Tween = create_tween()
		tween.tween_property(light, "modulate", backlight_color, 0.1)

func _setup_readysetgo_type() -> void :
	match Profile.debug_countdown_type:
		0: pass
		1: for node: Control in backlights.get_children():
			node.visible = node.name == "RecLight"
