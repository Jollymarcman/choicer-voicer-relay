extends Control

const DubPack = preload("res://dub_pack.gd")
const DubRecordingTiming = preload("res://common/niche/dub_recording_timing.gd")
const BrowserAudio = preload("res://browser_audio.gd")
const RECORD_MASTER_SCENE = preload("res://scene/overlay/record_master.tscn")
const WAUKEGAN_LDO = preload("res://graphic/font/Waukegan LDO.ttf")
const VIDEO_DUB_SESSION := 5
const PACK_ROOT := "user://packs_voice/"
const TEMP_ROOT := "user://.temp/online_pack_sync/"
const REGISTRY_PATH := "user://installed_packs.json"
const PACK_CHUNK_BYTES := 512 * 1024
const MAX_PACK_BYTES := 512 * 1024 * 1024
const MAX_PACK_FILES := 4096
const ALLOWED_EXTENSIONS := ["ini", "txt", "json", "cfg", "wav", "mp3", "ogg", "ogv", "png", "jpg", "jpeg", "webp"]

var name_input: LineEdit
var room_input: LineEdit
var join_button: Button
var leave_button: Button
var status_label: Label
var roster_label: Label
var lobby_panel: PanelContainer
var lobby_margin: MarginContainer
var lobby_rows: VBoxContainer
var lobby_scroll: ScrollContainer
var lobby_title: Label
var lobby_subtitle: Label
var lobby_note: Label
var name_row: HBoxContainer
var room_row: HBoxContainer
var mic_device_row: HBoxContainer
var mic_action_row: HBoxContainer
var mic_gain_row: HBoxContainer
var mic_meter_row: HBoxContainer
var mic_gain_label: Label
var join_leave_row: HBoxContainer
var mic_device_option: OptionButton
var mic_setup_button: Button
var mic_monitor_button: Button
var mic_gain_slider: HSlider
var mic_gain_value_label: Label
var mic_level_bar: ProgressBar
var mic_status_label: Label
var _mic_meter_elapsed := 0.0
var _mic_monitor_enabled := false

var record_overlay: ColorRect
var record_preview: TextureRect
var record_caption: Label
var record_character: Label
var record_progress: Label
var record_button: Button
var record_master: Control
var _record_pressed := false
var _queue_cancelled := false

var playback_overlay: ColorRect
var playback_video: VideoStreamPlayer
var playback_backing: AudioStreamPlayer
var playback_title: Label
var playback_audio_nodes: Node
var record_content: BoxContainer
var record_screen_frame: PanelContainer
var record_controls_panel: PanelContainer
var record_title: Label
var record_instruction: Label
var mobile_layout := false

var current_pack: Dictionary = {}
var current_pack_path := ""
var playback_recordings: Dictionary = {}

var sync_pack_path := ""
var sync_pack_name := ""
var sync_temp_root := ""
var sync_digest := ""
var sync_total_bytes := 0
var sync_received_bytes := 0
var sync_expected_files := 0
var sync_received_files := 0
var sync_current_file: FileAccess
var sync_current_path := ""
var sync_current_size := 0
var sync_current_sha := ""
var installed_registry: Dictionary = {}


func _ready() -> void:
	BrowserAudio.setup()
	DirAccess.make_dir_recursive_absolute(PACK_ROOT)
	DirAccess.make_dir_recursive_absolute(TEMP_ROOT)
	_load_registry()
	_build_interface()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_connect_relay_signals()
	set_status("Enter the host's room code to join a Video Dub.")


func _process(delta: float) -> void:
	if not mic_level_bar:
		return
	_mic_meter_elapsed += delta
	if _mic_meter_elapsed < 0.08:
		return
	_mic_meter_elapsed = 0.0
	var bridge := BrowserAudio.interface()
	if not bridge or str(bridge.getState()) != "ready":
		mic_level_bar.value = 0
		return
	var rms := maxf(0.00001, float(bridge.getInputLevel()))
	mic_level_bar.value = clampf((60.0 + 20.0 * log(rms) / log(10.0)) / 60.0 * 100.0, 0.0, 100.0)


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color("899293")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var rings := Label.new()
	rings.text = "◯       ◯    ◯       ◯\n     ◯          ◯\n  ◯        ◯        ◯"
	rings.add_theme_font_size_override("font_size", 96)
	rings.add_theme_color_override("font_color", Color(0.35, 0.72, 0.78, 0.22))
	rings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rings.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rings.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	background.add_child(rings)

	lobby_panel = PanelContainer.new()
	lobby_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lobby_panel.position = Vector2(-410, -325)
	lobby_panel.custom_minimum_size = Vector2(820, 650)
	lobby_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.29, 0.31, 0.31, 0.9), Color(0.45, 0.92, 1.0), 3))
	add_child(lobby_panel)
	lobby_margin = MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		lobby_margin.add_theme_constant_override(side, 24)
	lobby_panel.add_child(lobby_margin)
	lobby_scroll = ScrollContainer.new()
	lobby_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lobby_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lobby_margin.add_child(lobby_scroll)
	lobby_rows = VBoxContainer.new()
	lobby_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_rows.add_theme_constant_override("separation", 14)
	lobby_scroll.add_child(lobby_rows)
	lobby_title = Label.new()
	lobby_title.text = "CHOICER VOICER — ONLINE GUEST"
	lobby_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_title.add_theme_font_size_override("font_size", 34)
	lobby_title.add_theme_color_override("font_color", Color("b9f1ff"))
	lobby_rows.add_child(lobby_title)
	lobby_subtitle = Label.new()
	lobby_subtitle.text = "Join your friend's Video Dub directly from the browser"
	lobby_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_rows.add_child(lobby_subtitle)
	name_input = _input_row(lobby_rows, "Display name", "Player", false)
	name_row = name_input.get_parent() as HBoxContainer
	room_input = _input_row(lobby_rows, "Room code", "ABCDEFGH", true)
	room_row = room_input.get_parent() as HBoxContainer
	_build_microphone_settings(lobby_rows)
	join_leave_row = HBoxContainer.new()
	join_leave_row.alignment = BoxContainer.ALIGNMENT_CENTER
	join_leave_row.add_theme_constant_override("separation", 12)
	lobby_rows.add_child(join_leave_row)
	join_button = _make_button("Join Video Dub")
	join_button.pressed.connect(_join)
	join_leave_row.add_child(join_button)
	leave_button = _make_button("Leave")
	leave_button.disabled = true
	leave_button.pressed.connect(func() -> void:
		var bridge := BrowserAudio.interface()
		if bridge:
			bridge.close()
		RelayClient.leave())
	join_leave_row.add_child(leave_button)
	status_label = Label.new()
	status_label.custom_minimum_size.y = 76
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 18)
	lobby_rows.add_child(status_label)
	roster_label = Label.new()
	roster_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_label.add_theme_font_size_override("font_size", 18)
	lobby_rows.add_child(roster_label)
	lobby_note = Label.new()
	lobby_note.text = "Allow microphone access when asked. Headphones are recommended.\nThe host controls the scene; recording and playback will appear automatically."
	lobby_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_note.add_theme_color_override("font_color", Color("c2e9ef"))
	lobby_rows.add_child(lobby_note)
	_build_record_overlay()
	_build_playback_overlay()


func _build_microphone_settings(parent: VBoxContainer) -> void:
	var device_section := VBoxContainer.new()
	device_section.add_theme_constant_override("separation", 6)
	parent.add_child(device_section)
	var device_row := HBoxContainer.new()
	device_row.add_theme_constant_override("separation", 10)
	device_section.add_child(device_row)
	mic_device_row = device_row
	var device_label := Label.new()
	device_label.text = "Microphone"
	device_label.custom_minimum_size.x = 145
	device_label.add_theme_font_size_override("font_size", 20)
	device_row.add_child(device_label)
	mic_device_option = OptionButton.new()
	mic_device_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mic_device_option.custom_minimum_size.y = 42
	mic_device_option.add_theme_font_size_override("font_size", 17)
	mic_device_option.add_theme_stylebox_override("normal", _panel_style(Color("c6d1d3"), Color("607d81"), 2))
	mic_device_option.add_item("Default microphone")
	mic_device_option.set_item_metadata(0, "")
	mic_device_option.item_selected.connect(_on_mic_device_selected)
	device_row.add_child(mic_device_option)
	mic_action_row = HBoxContainer.new()
	mic_action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mic_action_row.add_theme_constant_override("separation", 8)
	device_row.add_child(mic_action_row)
	mic_monitor_button = _make_button("Listen to mic")
	mic_monitor_button.custom_minimum_size.x = 132
	mic_monitor_button.disabled = true
	mic_monitor_button.pressed.connect(_on_mic_monitor_pressed)
	mic_action_row.add_child(mic_monitor_button)
	mic_setup_button = _make_button("Enable / Refresh")
	mic_setup_button.custom_minimum_size.x = 158
	mic_setup_button.pressed.connect(_request_microphone_settings)
	mic_action_row.add_child(mic_setup_button)

	var gain_section := VBoxContainer.new()
	gain_section.add_theme_constant_override("separation", 6)
	parent.add_child(gain_section)
	var gain_row := HBoxContainer.new()
	gain_row.add_theme_constant_override("separation", 10)
	gain_section.add_child(gain_row)
	mic_gain_row = gain_row
	mic_gain_label = Label.new()
	mic_gain_label.text = "Mic gain"
	mic_gain_label.custom_minimum_size.x = 145
	mic_gain_label.add_theme_font_size_override("font_size", 18)
	gain_row.add_child(mic_gain_label)
	mic_gain_slider = HSlider.new()
	mic_gain_slider.min_value = 0.0
	mic_gain_slider.max_value = 2.0
	mic_gain_slider.step = 0.05
	mic_gain_slider.value = 1.0
	mic_gain_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mic_gain_slider.custom_minimum_size.y = 28
	mic_gain_slider.value_changed.connect(_on_mic_gain_changed)
	gain_row.add_child(mic_gain_slider)
	mic_gain_value_label = Label.new()
	mic_gain_value_label.custom_minimum_size.x = 54
	mic_gain_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mic_gain_value_label.text = "100%"
	gain_row.add_child(mic_gain_value_label)
	var meter_row := HBoxContainer.new()
	mic_meter_row = meter_row
	meter_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter_row.add_theme_constant_override("separation", 10)
	gain_row.add_child(meter_row)
	var meter_label := Label.new()
	meter_label.text = "Input level"
	meter_label.custom_minimum_size.x = 110
	meter_row.add_child(meter_label)
	mic_level_bar = ProgressBar.new()
	mic_level_bar.custom_minimum_size = Vector2(0, 26)
	mic_level_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mic_level_bar.min_value = 0
	mic_level_bar.max_value = 100
	mic_level_bar.show_percentage = false
	meter_row.add_child(mic_level_bar)
	mic_status_label = Label.new()
	mic_status_label.text = "Enable the mic, then speak to test the meter. Use headphones to listen and avoid feedback."
	mic_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mic_status_label.add_theme_font_size_override("font_size", 14)
	mic_status_label.add_theme_color_override("font_color", Color("c2e9ef"))
	gain_section.add_child(mic_status_label)


func _request_microphone_settings() -> void:
	var bridge := BrowserAudio.interface()
	if not bridge:
		mic_status_label.text = "Microphone settings are only available in the browser build."
		return
	mic_setup_button.disabled = true
	join_button.disabled = true
	mic_status_label.text = "Waiting for browser microphone permission..."
	if str(bridge.getState()) == "ready":
		bridge.refreshDevices()
	else:
		bridge.prepare()
	for _attempt in range(120):
		var state := str(bridge.getState())
		if state != "pending" and state != "idle":
			break
		await get_tree().create_timer(0.1).timeout
	mic_setup_button.disabled = false
	join_button.disabled = not RelayClient.room_code.is_empty()
	if str(bridge.getState()) != "ready":
		mic_monitor_button.disabled = true
		mic_status_label.text = "Microphone unavailable: %s" % str(bridge.getError())
		return
	mic_monitor_button.disabled = false
	var devices = JSON.parse_string(str(bridge.listInputDevicesJson()))
	if not devices is Array or devices.is_empty():
		mic_status_label.text = "No microphone devices were found. Check browser and Windows permissions."
		return
	var selected_id := str(bridge.getSelectedDeviceId())
	mic_device_option.clear()
	for device in devices:
		var label := str(device.get("label", "Microphone"))
		var id := str(device.get("id", ""))
		mic_device_option.add_item(label)
		var index := mic_device_option.item_count - 1
		mic_device_option.set_item_metadata(index, id)
		if id == selected_id:
			mic_device_option.select(index)
	if selected_id.is_empty():
		mic_device_option.select(0)
		bridge.configureDevice(str(mic_device_option.get_item_metadata(0)))
	mic_status_label.text = "Speak to test the meter. Use headphones when listening to your mic."


func _on_mic_device_selected(index: int) -> void:
	var bridge := BrowserAudio.interface()
	if not bridge:
		return
	var device_id := str(mic_device_option.get_item_metadata(index))
	if device_id == str(bridge.getSelectedDeviceId()) and str(bridge.getState()) == "ready":
		return
	mic_device_option.disabled = true
	mic_monitor_button.disabled = true
	_mic_monitor_enabled = false
	mic_monitor_button.text = "Listen to mic"
	bridge.setMonitorEnabled(false)
	join_button.disabled = true
	mic_status_label.text = "Switching microphone..."
	bridge.configureDevice(device_id)
	for _attempt in range(120):
		var state := str(bridge.getState())
		if state != "pending" and state != "idle":
			break
		await get_tree().create_timer(0.1).timeout
	mic_device_option.disabled = false
	join_button.disabled = not RelayClient.room_code.is_empty()
	if str(bridge.getState()) == "ready":
		mic_monitor_button.disabled = false
		mic_status_label.text = "Microphone ready. Speak to test the meter."
	else:
		mic_monitor_button.disabled = true
		mic_status_label.text = "Could not switch microphone: %s" % str(bridge.getError())


func _on_mic_monitor_pressed() -> void:
	var bridge := BrowserAudio.interface()
	if not bridge or str(bridge.getState()) != "ready":
		mic_status_label.text = "Enable microphone access before listening to the mic."
		return
	_mic_monitor_enabled = not _mic_monitor_enabled
	bridge.setMonitorEnabled(_mic_monitor_enabled)
	mic_monitor_button.text = "Stop listening" if _mic_monitor_enabled else "Listen to mic"
	mic_status_label.text = "Mic monitoring is on — headphones recommended to prevent echo/feedback." if _mic_monitor_enabled else "Mic monitoring is off. Speak to test the level meter."


func _on_mic_gain_changed(value: float) -> void:
	if mic_gain_value_label:
		mic_gain_value_label.text = "%d%%" % roundi(value * 100.0)
	var bridge := BrowserAudio.interface()
	if bridge:
		bridge.setInputGain(value)


func _input_row(parent: VBoxContainer, label_text: String, placeholder: String, uppercase: bool) -> LineEdit:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 145
	label.add_theme_font_size_override("font_size", 20)
	row.add_child(label)
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.max_length = 24 if not uppercase else 8
	input.add_theme_font_size_override("font_size", 20)
	input.add_theme_stylebox_override("normal", _panel_style(Color(0.18, 0.2, 0.2), Color(0.42, 0.62, 0.65), 2))
	input.add_theme_stylebox_override("focus", _panel_style(Color(0.23, 0.26, 0.26), Color(0.45, 0.92, 1.0), 3))
	if uppercase:
		input.text_changed.connect(func(value: String) -> void:
			var caret := input.caret_column
			input.text = value.to_upper()
			input.caret_column = caret)
	row.add_child(input)
	return input


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(180, 48)
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_stylebox_override("normal", _panel_style(Color("c6d1d3"), Color("607d81"), 2))
	button.add_theme_stylebox_override("hover", _panel_style(Color("e7faff"), Color("57ddff"), 3))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("86dbe9"), Color.WHITE, 3))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


func _panel_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(12)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _build_record_overlay() -> void:
	record_overlay = ColorRect.new()
	record_overlay.color = Color(0.28, 0.3, 0.3, 0.98)
	record_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	record_overlay.z_index = 55
	add_child(record_overlay)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 28
	panel.offset_top = 22
	panel.offset_right = -28
	panel.offset_bottom = -22
	panel.add_theme_stylebox_override("panel", _wii_style_box(Color(0.68, 0.7, 0.7, 0.99), Color(0.4, 0.9, 1.0), 3))
	record_overlay.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	margin.add_child(rows)
	var title := Label.new()
	record_title = title
	title.text = "VIDEO DUB — YOUR RECORDING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", WAUKEGAN_LDO)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.72, 0.95, 1.0))
	rows.add_child(title)
	var content := HBoxContainer.new()
	record_content = content
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	rows.add_child(content)
	var screen_frame := PanelContainer.new()
	record_screen_frame = screen_frame
	screen_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_frame.add_theme_stylebox_override("panel", _wii_style_box(Color(0.035, 0.045, 0.05), Color(0.14, 0.18, 0.19), 5))
	content.add_child(screen_frame)
	var aspect := AspectRatioContainer.new()
	aspect.ratio = 16.0 / 9.0
	aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_frame.add_child(aspect)
	record_preview = TextureRect.new()
	record_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	record_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	record_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	record_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	aspect.add_child(record_preview)
	var controls_panel := PanelContainer.new()
	record_controls_panel = controls_panel
	controls_panel.custom_minimum_size = Vector2(285, 0)
	controls_panel.add_theme_stylebox_override("panel", _wii_style_box(Color(0.78, 0.81, 0.81, 0.98), Color(0.36, 0.55, 0.58)))
	content.add_child(controls_panel)
	var controls_margin := MarginContainer.new()
	controls_margin.add_theme_constant_override("margin_left", 12)
	controls_margin.add_theme_constant_override("margin_top", 12)
	controls_margin.add_theme_constant_override("margin_right", 12)
	controls_margin.add_theme_constant_override("margin_bottom", 12)
	controls_panel.add_child(controls_margin)
	var controls := VBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 12)
	controls_margin.add_child(controls)
	record_progress = Label.new()
	record_progress.text = "Preparing your lines..."
	record_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	record_progress.add_theme_font_size_override("font_size", 20)
	controls.add_child(record_progress)
	record_character = Label.new()
	record_character.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record_character.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	record_character.add_theme_color_override("font_color", Color(0.08, 0.3, 0.34))
	controls.add_child(record_character)
	record_instruction = Label.new()
	record_instruction.text = "Press Record when you are ready. The host's prompt and countdown settings will be used automatically."
	record_instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	record_instruction.add_theme_color_override("font_color", Color(0.14, 0.18, 0.19))
	controls.add_child(record_instruction)
	record_button = Button.new()
	record_button.text = "●  RECORD"
	record_button.custom_minimum_size = Vector2(240, 72)
	_style_wii_button(record_button)
	record_button.add_theme_font_size_override("font_size", 25)
	record_button.pressed.connect(func() -> void:
		record_button.disabled = true
		record_button.text = "Starting..."
		_record_pressed = true)
	controls.add_child(record_button)
	record_caption = Label.new()
	record_caption.custom_minimum_size.y = 70
	record_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	record_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	record_caption.add_theme_font_size_override("font_size", 21)
	record_caption.add_theme_color_override("font_color", Color(0.06, 0.1, 0.11))
	rows.add_child(record_caption)
	record_master = RECORD_MASTER_SCENE.instantiate()
	record_master.z_index = 65
	add_child(record_master)
	record_master.hide()
	record_overlay.hide()


func _wii_style_box(fill: Color, border: Color, width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(12)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func _style_wii_button(button: BaseButton) -> void:
	button.add_theme_stylebox_override("normal", _wii_style_box(Color(0.78, 0.83, 0.84, 0.96), Color(0.35, 0.52, 0.55)))
	button.add_theme_stylebox_override("hover", _wii_style_box(Color(0.91, 0.98, 1.0, 1.0), Color(0.35, 0.88, 1.0), 3))
	button.add_theme_stylebox_override("pressed", _wii_style_box(Color(0.53, 0.86, 0.93, 1.0), Color.WHITE, 3))
	button.add_theme_stylebox_override("focus", _wii_style_box(Color.TRANSPARENT, Color(0.75, 0.96, 1.0), 3))
	button.add_theme_color_override("font_color", Color(0.08, 0.12, 0.13))
	button.add_theme_color_override("font_hover_color", Color(0.02, 0.12, 0.15))
	button.add_theme_color_override("font_pressed_color", Color(0.02, 0.12, 0.15))
	button.add_theme_font_override("font", WAUKEGAN_LDO)
	button.add_theme_font_size_override("font_size", 18)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _build_playback_overlay() -> void:
	playback_overlay = ColorRect.new()
	playback_overlay.color = Color.BLACK
	playback_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	playback_overlay.z_index = 30
	add_child(playback_overlay)
	playback_video = VideoStreamPlayer.new()
	playback_video.expand = true
	playback_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	playback_video.bus = "Master"
	playback_overlay.add_child(playback_video)
	playback_title = Label.new()
	playback_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	playback_title.offset_bottom = 56
	playback_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	playback_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	playback_title.add_theme_font_size_override("font_size", 28)
	playback_title.add_theme_color_override("font_color", Color.WHITE)
	playback_title.add_theme_color_override("font_shadow_color", Color.BLACK)
	playback_title.add_theme_constant_override("shadow_offset_x", 2)
	playback_title.add_theme_constant_override("shadow_offset_y", 2)
	playback_overlay.add_child(playback_title)
	playback_backing = AudioStreamPlayer.new()
	playback_overlay.add_child(playback_backing)
	playback_audio_nodes = Node.new()
	playback_overlay.add_child(playback_audio_nodes)
	playback_overlay.hide()


func _apply_responsive_layout() -> void:
	if not is_node_ready() or not lobby_panel:
		return
	var screen_size := Vector2(get_window().size)
	var viewport_size := get_viewport_rect().size
	var use_mobile := screen_size.x < 720.0 or screen_size.y < 560.0
	if use_mobile == mobile_layout:
		return
	mobile_layout = use_mobile
	if mobile_layout:
		mic_action_row.reparent(mic_device_row.get_parent())
		mic_device_row.get_parent().move_child(mic_action_row, 1)
		mic_meter_row.reparent(mic_gain_row.get_parent())
		mic_gain_row.get_parent().move_child(mic_meter_row, 1)
		lobby_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lobby_panel.offset_left = 8
		lobby_panel.offset_top = 8
		lobby_panel.offset_right = -8
		lobby_panel.offset_bottom = -8
		lobby_panel.position = Vector2.ZERO
		lobby_panel.custom_minimum_size = Vector2.ZERO
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			lobby_margin.add_theme_constant_override(side, 12)
		lobby_title.add_theme_font_size_override("font_size", 23)
		lobby_subtitle.add_theme_font_size_override("font_size", 16)
		lobby_note.add_theme_font_size_override("font_size", 15)
		status_label.add_theme_font_size_override("font_size", 16)
		roster_label.add_theme_font_size_override("font_size", 16)
		for row in [name_row, room_row, mic_device_row, mic_gain_row]:
			for child in row.get_children():
				if child is Label:
					child.custom_minimum_size.x = 96
					child.add_theme_font_size_override("font_size", 16)
		name_input.add_theme_font_size_override("font_size", 18)
		room_input.add_theme_font_size_override("font_size", 18)
		mic_device_option.custom_minimum_size.y = 50
		for button in [mic_monitor_button, mic_setup_button, join_button, leave_button]:
			button.custom_minimum_size = Vector2(0, 54)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.add_theme_font_size_override("font_size", 16)
		mic_gain_slider.custom_minimum_size.y = 42
		mic_level_bar.custom_minimum_size.y = 30
		mic_status_label.add_theme_font_size_override("font_size", 13)
		join_leave_row.add_theme_constant_override("separation", 8)
		_migrate_record_content(true)
		var panel := record_overlay.get_child(0) as PanelContainer
		panel.offset_left = 8
		panel.offset_top = 8
		panel.offset_right = -8
		panel.offset_bottom = -8
		var record_margin := panel.get_child(0) as MarginContainer
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			record_margin.add_theme_constant_override(side, 8)
		record_title.add_theme_font_size_override("font_size", 22)
		record_progress.add_theme_font_size_override("font_size", 18)
		record_character.add_theme_font_size_override("font_size", 16)
		record_instruction.add_theme_font_size_override("font_size", 14)
		record_caption.add_theme_font_size_override("font_size", 18)
		record_caption.custom_minimum_size.y = 42
		record_screen_frame.custom_minimum_size.y = 160
		record_controls_panel.custom_minimum_size = Vector2(0, 230)
		record_button.custom_minimum_size = Vector2(0, 62)
		record_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		mic_action_row.reparent(mic_device_row)
		mic_meter_row.reparent(mic_gain_row)
		lobby_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		lobby_panel.position = Vector2(-410, -325)
		lobby_panel.custom_minimum_size = Vector2(820, 650)
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			lobby_margin.add_theme_constant_override(side, 24)
		lobby_title.add_theme_font_size_override("font_size", 34)
		lobby_subtitle.add_theme_font_size_override("font_size", 18)
		lobby_note.add_theme_font_size_override("font_size", 18)
		status_label.add_theme_font_size_override("font_size", 18)
		roster_label.add_theme_font_size_override("font_size", 18)
		for row in [name_row, room_row, mic_device_row, mic_gain_row]:
			for child in row.get_children():
				if child is Label:
					child.custom_minimum_size.x = 145
					child.add_theme_font_size_override("font_size", 20 if row in [name_row, room_row, mic_device_row] else 18)
		name_input.add_theme_font_size_override("font_size", 20)
		room_input.add_theme_font_size_override("font_size", 20)
		mic_device_option.custom_minimum_size.y = 42
		for button in [mic_monitor_button, mic_setup_button]:
			button.custom_minimum_size = Vector2(132 if button == mic_monitor_button else 158, 48)
			button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			button.add_theme_font_size_override("font_size", 19)
		for button in [join_button, leave_button]:
			button.custom_minimum_size = Vector2(180, 48)
			button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			button.add_theme_font_size_override("font_size", 19)
		mic_gain_slider.custom_minimum_size.y = 28
		mic_level_bar.custom_minimum_size = Vector2(0, 24)
		mic_status_label.add_theme_font_size_override("font_size", 14)
		join_leave_row.add_theme_constant_override("separation", 12)
		_migrate_record_content(false)
		var panel := record_overlay.get_child(0) as PanelContainer
		panel.offset_left = 28
		panel.offset_top = 22
		panel.offset_right = -28
		panel.offset_bottom = -22
		var record_margin := panel.get_child(0) as MarginContainer
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			record_margin.add_theme_constant_override(side, 18 if side in ["margin_left", "margin_right"] else 14)
		record_title.add_theme_font_size_override("font_size", 30)
		record_progress.add_theme_font_size_override("font_size", 20)
		record_character.add_theme_font_size_override("font_size", 18)
		record_instruction.add_theme_font_size_override("font_size", 18)
		record_caption.add_theme_font_size_override("font_size", 21)
		record_caption.custom_minimum_size.y = 70
		record_screen_frame.custom_minimum_size.y = 0
		record_controls_panel.custom_minimum_size = Vector2(285, 0)
		record_button.custom_minimum_size = Vector2(240, 72)
		record_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if record_master and record_master.has_method("set_mobile_layout"):
		record_master.set_mobile_layout(mobile_layout, viewport_size.x)


func _migrate_record_content(vertical: bool) -> void:
	if not record_content or not record_content.get_parent():
		return
	if vertical == (record_content is VBoxContainer):
		return
	var old := record_content
	var parent := old.get_parent()
	var index := old.get_index()
	var replacement: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	replacement.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	replacement.size_flags_vertical = Control.SIZE_EXPAND_FILL
	replacement.add_theme_constant_override("separation", 10 if vertical else 16)
	parent.remove_child(old)
	parent.add_child(replacement)
	parent.move_child(replacement, index)
	for child in old.get_children():
		old.remove_child(child)
		replacement.add_child(child)
	old.queue_free()
	record_content = replacement


func _connect_relay_signals() -> void:
	RelayClient.status_changed.connect(set_status)
	RelayClient.roster_changed.connect(_update_roster)
	RelayClient.lobby_started.connect(_on_lobby_started)
	RelayClient.dub_pack_received.connect(_on_dub_pack)
	RelayClient.pack_sync_received.connect(_on_pack_sync)
	RelayClient.recording_queue_received.connect(_on_recording_queue)
	RelayClient.recording_queue_cancelled.connect(_on_queue_cancelled)
	RelayClient.recording_requested.connect(_on_legacy_recording)
	RelayClient.character_choice_requested.connect(_on_character_choice)
	RelayClient.telephone_progress_received.connect(_on_telephone_progress)
	RelayClient.playback_begin_received.connect(_on_playback_begin)
	RelayClient.playback_clip_received.connect(_on_playback_clip)
	RelayClient.playback_end_received.connect(_on_playback_end)
	RelayClient.playback_go_received.connect(_on_playback_go)


func _join() -> void:
	# The click is also the browser user gesture that permits audio/microphone use.
	var bridge := BrowserAudio.interface()
	if bridge:
		bridge.setMonitorEnabled(false)
		bridge.prepare()
	_mic_monitor_enabled = false
	mic_monitor_button.text = "Listen to mic"
	record_master.microphone_on()
	RelayClient.join(room_input.text, name_input.text)
	join_button.disabled = true
	leave_button.disabled = false
	mic_device_option.disabled = true
	mic_setup_button.disabled = true
	mic_gain_slider.editable = false
	name_input.editable = false
	room_input.editable = false


func set_status(message: String) -> void:
	status_label.text = message
	if RelayClient.room_code.is_empty():
		join_button.disabled = false
		leave_button.disabled = true
		mic_device_option.disabled = false
		mic_setup_button.disabled = false
		mic_monitor_button.disabled = not BrowserAudio.interface() or str(BrowserAudio.interface().getState()) != "ready"
		mic_gain_slider.editable = true
		name_input.editable = true
		room_input.editable = true


func _update_roster(players: Array) -> void:
	if players.is_empty():
		roster_label.text = "No active lobby"
		return
	var lines := PackedStringArray(["Players (%d/4):" % players.size()])
	for index in players.size():
		var entry: Dictionary = players[index]
		lines.append("  %d. %s%s" % [index + 1, str(entry.get("name", "Player")), " (host)" if int(entry.get("peer_id", 0)) == 1 else ""])
	roster_label.text = "\n".join(lines)


func _on_lobby_started(session_type: int, _dub_style: int) -> void:
	if session_type != VIDEO_DUB_SESSION:
		set_status("This browser client supports Video Dub only. Ask the host to choose Video Dub.")
	else:
		set_status("Video Dub started. Waiting for the host's pack...")


func _on_dub_pack(pack_path: String, display_name: String) -> void:
	current_pack_path = pack_path
	var loaded := DubPack.load_from_folder(PACK_ROOT.path_join(pack_path))
	if bool(loaded.get("ok", false)):
		current_pack = loaded
		set_status("Loaded %s. Waiting for recording prompts..." % display_name)
	else:
		current_pack = {}
		set_status("Waiting to download %s from the host..." % display_name)


func _on_pack_sync(message: Dictionary) -> void:
	match str(message.get("type", "")):
		"pack_sync_offer": _handle_pack_offer(message)
		"pack_sync_begin": _begin_pack_sync(message)
		"pack_sync_file_begin": _begin_sync_file(message)
		"pack_sync_file_chunk": _write_sync_chunk(message)
		"pack_sync_file_end": _end_sync_file()
		"pack_sync_end": _finish_pack_sync()


func _handle_pack_offer(message: Dictionary) -> void:
	var pack_path := str(message.get("pack_path", ""))
	var pack_name := str(message.get("pack_name", "Video Dub"))
	var digest := str(message.get("digest", ""))
	if not _valid_relative_path(pack_path):
		RelayClient.send_pack_status("error", "Invalid pack path")
		return
	if str(installed_registry.get(pack_path, "")) == digest:
		var loaded := DubPack.load_from_folder(PACK_ROOT.path_join(pack_path))
		if bool(loaded.get("ok", false)):
			current_pack = loaded
			current_pack_path = pack_path
			RelayClient.send_pack_status("ready")
			set_status("Loaded %s. Waiting for recording prompts..." % pack_name)
			return
	if not bool(message.get("can_transfer", true)):
		set_status("%s is too large for browser auto-download. Ask the host to use a pack below 512 MB." % pack_name)
		RelayClient.send_pack_status("error", "Pack is too large for browser download")
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Download Host's Dub Pack?"
	dialog.dialog_text = "This Video Dub needs ‘%s’.\n\nDownload and store %s in this browser?" % [pack_name, _format_size(int(message.get("total_bytes", 0)))]
	dialog.ok_button_text = "Download & Install"
	dialog.cancel_button_text = "Decline"
	add_child(dialog)
	var dialog_width := mini(600, int(get_viewport_rect().size.x - 24.0))
	dialog.popup_centered(Vector2i(maxi(300, dialog_width), 260 if not mobile_layout else 300))
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		set_status("Downloading %s from the host..." % pack_name)
		RelayClient.send_pack_status("need"))
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
		RelayClient.send_pack_status("error", "Player declined the pack download"))


func _begin_pack_sync(message: Dictionary) -> void:
	sync_pack_path = str(message.get("pack_path", ""))
	sync_pack_name = str(message.get("pack_name", "Video Dub"))
	sync_digest = str(message.get("digest", ""))
	sync_total_bytes = int(message.get("total_bytes", 0))
	sync_expected_files = int(message.get("file_count", 0))
	if not _valid_relative_path(sync_pack_path) or sync_total_bytes <= 0 or sync_total_bytes > MAX_PACK_BYTES or sync_expected_files <= 0 or sync_expected_files > MAX_PACK_FILES:
		_sync_error("Invalid pack details")
		return
	sync_temp_root = TEMP_ROOT.path_join(sync_pack_path)
	_remove_tree(sync_temp_root)
	DirAccess.make_dir_recursive_absolute(sync_temp_root)
	sync_received_bytes = 0
	sync_received_files = 0
	set_status("Downloading %s: 0%%" % sync_pack_name)


func _begin_sync_file(message: Dictionary) -> void:
	if sync_current_file:
		_sync_error("A new file started early")
		return
	sync_current_path = str(message.get("path", ""))
	sync_current_size = int(message.get("size", -1))
	sync_current_sha = str(message.get("sha256", ""))
	if not _valid_pack_file(sync_current_path) or sync_current_size < 0 or sync_current_size > MAX_PACK_BYTES:
		_sync_error("Invalid file details")
		return
	var output_path := sync_temp_root.path_join(sync_current_path)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	sync_current_file = FileAccess.open(output_path, FileAccess.WRITE)
	if not sync_current_file:
		_sync_error("Could not create a pack file")


func _write_sync_chunk(message: Dictionary) -> void:
	if not sync_current_file:
		_sync_error("Received data without a file")
		return
	var data: PackedByteArray = message.get("data", PackedByteArray())
	if data.size() > PACK_CHUNK_BYTES or sync_received_bytes + data.size() > sync_total_bytes:
		_sync_error("Received too much data")
		return
	sync_current_file.store_buffer(data)
	sync_received_bytes += data.size()
	set_status("Downloading %s: %d%%" % [sync_pack_name, int(float(sync_received_bytes) * 100.0 / float(sync_total_bytes))])


func _end_sync_file() -> void:
	if not sync_current_file:
		_sync_error("File ended unexpectedly")
		return
	var path := sync_temp_root.path_join(sync_current_path)
	sync_current_file.close()
	sync_current_file = null
	var file := FileAccess.open(path, FileAccess.READ)
	var size := file.get_length() if file else -1
	if file:
		file.close()
	if size != sync_current_size or FileAccess.get_sha256(path) != sync_current_sha:
		_sync_error("File verification failed")
		return
	sync_received_files += 1


func _finish_pack_sync() -> void:
	if sync_current_file or sync_received_bytes != sync_total_bytes or sync_received_files != sync_expected_files:
		_sync_error("The transfer was incomplete")
		return
	var target := PACK_ROOT.path_join(sync_pack_path)
	_remove_tree(target)
	if not _copy_tree(sync_temp_root, target):
		_sync_error("Could not install the pack")
		return
	_remove_tree(sync_temp_root)
	var loaded := DubPack.load_from_folder(target)
	if not bool(loaded.get("ok", false)):
		_sync_error(str(loaded.get("error", "Downloaded pack could not be loaded")))
		return
	current_pack = loaded
	current_pack_path = sync_pack_path
	installed_registry[sync_pack_path] = sync_digest
	_save_registry()
	RelayClient.send_pack_status("ready")
	set_status("Installed %s. Waiting for recording prompts..." % sync_pack_name)


func _sync_error(message: String) -> void:
	if sync_current_file:
		sync_current_file.close()
		sync_current_file = null
	_remove_tree(sync_temp_root)
	set_status("Pack download failed: %s" % message)
	RelayClient.send_pack_status("error", message)


func _on_recording_queue(queue_id: int, clips: Array, settings: Dictionary) -> void:
	if current_pack.is_empty():
		RelayClient.finish_queue(queue_id)
		set_status("The required pack is not loaded.")
		return
	_queue_cancelled = false
	var recording_error := ""
	for index in clips.size():
		if _queue_cancelled:
			break
		var info: Dictionary = clips[index]
		var file_name := str(info.get("file_name", ""))
		var line: Dictionary = current_pack.lines.get(file_name, {})
		if line.is_empty():
			continue
		_show_record_line(line, index, clips.size(), settings)
		RelayClient.send_queue_progress(queue_id, index, "Ready for line %d" % (index + 1))
		_record_pressed = false
		record_button.disabled = false
		while not _record_pressed and not _queue_cancelled:
			await get_tree().process_frame
		if _queue_cancelled:
			break
		RelayClient.send_queue_progress(queue_id, index, "Recording line %d" % (index + 1))
		var override := RelayClient.wav_from_payload(info.get("prompt_wav", {}))
		var original_path := "" if override else str(line.get("audio_path", ""))
		var result := await _capture_line(override if override else line.stream, settings, original_path)
		if not result.is_empty() and not _queue_cancelled:
			RelayClient.send_queue_recording(queue_id, index, result)
		elif not _queue_cancelled:
			recording_error = "Microphone recording failed. Check browser mic permission, then rejoin to retry."
			break
	if not _queue_cancelled:
		RelayClient.finish_queue(queue_id)
	record_overlay.hide()
	set_status(recording_error if not recording_error.is_empty() else "All of your lines were sent. Waiting for the host...")


func _show_record_line(line: Dictionary, index: int, total: int, settings: Dictionary) -> void:
	record_preview.texture = line.get("texture")
	record_progress.text = "Your line %d of %d" % [index + 1, total]
	record_character.text = "Character: %s" % ", ".join(line.get("characters", PackedStringArray()))
	record_caption.text = str(line.get("caption", "")) if bool(settings.get("show_captions", true)) else "Captions disabled by the host"
	record_button.text = "●  RECORD"
	record_overlay.show()


func _capture_line(stream: AudioStream, settings: Dictionary, original_path: String = "") -> Dictionary:
	if not stream or not record_master:
		return {}
	# This is the same RecordMaster flow used by an EXE guest in online_lobby.gd.
	Profile.show_captions = bool(settings.get("show_captions", true))
	Profile.countdown_time = float(settings.get("countdown_time", 2.0))
	Profile.debug_countdown_type = int(settings.get("countdown_type", 0))
	Profile.caption_wait_time = float(settings.get("caption_wait_time", 0.5))
	Profile.mic_crust_sample_rate_on = false
	record_master.show()
	var vclip := VclipResource.new()
	vclip.audio = stream
	vclip.hint = record_caption.text if Profile.show_captions else ""
	vclip.directory = "Online parallel recording"
	var bridge := BrowserAudio.interface()
	if bridge and not original_path.is_empty() and FileAccess.file_exists(original_path):
		bridge.analyzeAudio(Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(original_path)))
	if bool(settings.get("mute_prompts", false)):
		record_master.SetVclipAudio(stream)
	else:
		await record_master.NewVclipPlay(vclip)
	var original_waveform: Dictionary = await BrowserAudio.wait_for_waveform()
	if not original_waveform.is_empty():
		record_master.wave_control.set_vclip_data(original_waveform)
		record_master.wave_control.waveform.UpdateBoth()
	record_master.microphone_on()
	var samples: Dictionary = await record_master.PlmicRecord()
	var wav: AudioStreamWAV = BrowserAudio.take_recording()
	if wav:
		wav = DubRecordingTiming.trim_start(wav, 0.4)
	else:
		wav = record_master.wave_control.pecho
	if wav:
		wav = DubRecordingTiming.align_remote_take(wav)
	if bool(settings.get("reduce_sample_rate", false)) and wav:
		wav = GMCrust.reduce_recording_sample_rate(wav)
	# The host reconstructs the waveform from the sample data. Reading the
	# viewport texture back from WebGL can block indefinitely on some browsers.
	var waveform_png := PackedByteArray()
	record_master.StopBoth()
	record_master.hide()
	if not wav or wav.data.is_empty():
		return {}
	return {"wav": RelayClient.wav_to_payload(wav), "samples": samples, "waveform_png": waveform_png}


func _on_queue_cancelled(_queue_id: int, reason: String) -> void:
	_queue_cancelled = true
	_record_pressed = true
	if record_master:
		record_master.StopBoth()
		record_master.hide()
	record_overlay.hide()
	set_status("The host skipped your remaining lines: %s" % reason)


func _on_legacy_recording(request_id: int, payload: Dictionary) -> void:
	var stream := RelayClient.stream_from_payload(payload)
	if not stream:
		RelayClient.send_recording(request_id, {"wav": {}})
		return
	var line := {"texture": null, "caption": str(payload.get("caption", "")), "characters": PackedStringArray()}
	_show_record_line(line, 0, 1, {"show_captions": true})
	_record_pressed = false
	record_button.disabled = false
	while not _record_pressed:
		await get_tree().process_frame
	var result := await _capture_line(stream, {"countdown_time": 2.0})
	RelayClient.send_recording(request_id, result)
	record_overlay.hide()


func _on_character_choice(request_id: int, options: Array, mystery: bool) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Your Secret Character" if mystery else "Choose Your Character"
	dialog.dialog_text = "You are %s. Keep it secret!" % str(options[0]) if mystery else "Choose the character you will dub."
	var selector := OptionButton.new()
	for option in options:
		selector.add_item(str(option))
	if not mystery:
		dialog.add_child(selector)
	dialog.get_cancel_button().hide()
	add_child(dialog)
	var dialog_width := mini(520, int(get_viewport_rect().size.x - 24.0))
	dialog.popup_centered(Vector2i(maxi(300, dialog_width), 230 if not mobile_layout else 280))
	await dialog.confirmed
	var choice := str(options[0]) if mystery else selector.get_item_text(selector.selected)
	dialog.queue_free()
	RelayClient.send_character_choice(request_id, choice)
	set_status("Your character is %s. Waiting for recording prompts..." % choice)


func _on_telephone_progress(order: Array, active_index: int, text: String) -> void:
	var lines := PackedStringArray(["TRUE TELEPHONE — %s" % text])
	for index in order.size():
		var marker := "Recording" if index == active_index else ("Complete" if index < active_index else "Waiting")
		lines.append("%d. %s — %s" % [index + 1, str(order[index]), marker])
	set_status("\n".join(lines))


func _on_playback_begin(label: String) -> void:
	playback_title.text = label
	playback_recordings.clear()
	set_status("Receiving %s..." % label)


func _on_playback_clip(file_name: String, payload: Dictionary) -> void:
	var wav := RelayClient.wav_from_payload(payload)
	if wav:
		playback_recordings[file_name] = wav


func _on_playback_end() -> void:
	if current_pack.is_empty():
		set_status("Cannot play the dub because the pack is not loaded.")
		return
	RelayClient.send_playback_ready()
	set_status("Dub ready. Waiting for synchronized playback...")


func _on_playback_go() -> void:
	if current_pack.is_empty():
		return
	await get_tree().create_timer(1.0).timeout
	for child in playback_audio_nodes.get_children():
		child.queue_free()
	playback_video.stream = current_pack.video
	playback_backing.stream = current_pack.backing
	_set_playback_latency_mode(playback_backing, playback_backing.stream)
	for file_name in current_pack.lines:
		var line: Dictionary = current_pack.lines[file_name]
		var stream: AudioStream = playback_recordings.get(file_name, line.stream)
		for timestamp in line.timestamps:
			var timer := Timer.new()
			timer.one_shot = true
			timer.wait_time = maxf(0.01, float(timestamp))
			var player := AudioStreamPlayer.new()
			player.stream = stream
			_set_playback_latency_mode(player, stream)
			timer.timeout.connect(player.play)
			timer.add_child(player)
			playback_audio_nodes.add_child(timer)
	playback_overlay.show()
	playback_video.play()
	if playback_backing.stream:
		playback_backing.play()
	for timer in playback_audio_nodes.get_children():
		timer.start()
	await playback_video.finished
	playback_backing.stop()
	playback_overlay.hide()
	set_status("Playback finished. Waiting for the host...")


func _set_playback_latency_mode(player: AudioStreamPlayer, stream: AudioStream) -> void:
	# Web's Stream playback can add substantial output delay in single-threaded exports.
	# Recorded lines are WAV/static streams, so Sample mode gives them lower-latency playback.
	# Keep streaming formats (for example MP3 backing tracks) on Stream because they cannot
	# be sampled by Godot.
	if stream and stream.can_be_sampled():
		player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
	else:
		player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM


func _valid_relative_path(path: String) -> bool:
	var normalized := path.replace("\\", "/")
	return not normalized.is_empty() and not normalized.begins_with("/") and not normalized.contains(":") and not normalized.split("/").has("..")


func _valid_pack_file(path: String) -> bool:
	return _valid_relative_path(path) and path.get_extension().to_lower() in ALLOWED_EXTENSIONS


func _remove_tree(path: String) -> void:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(directory))
	DirAccess.remove_absolute(path)


func _copy_tree(source: String, target: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(target) not in [OK, ERR_ALREADY_EXISTS]:
		return false
	for file_name in DirAccess.get_files_at(source):
		if DirAccess.copy_absolute(source.path_join(file_name), target.path_join(file_name)) != OK:
			return false
	for directory in DirAccess.get_directories_at(source):
		if not _copy_tree(source.path_join(directory), target.path_join(directory)):
			return false
	return true


func _load_registry() -> void:
	if not FileAccess.file_exists(REGISTRY_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_PATH))
	if parsed is Dictionary:
		installed_registry = parsed


func _save_registry() -> void:
	var file := FileAccess.open(REGISTRY_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(installed_registry))


func _format_size(bytes: int) -> String:
	if bytes >= 1024 * 1024:
		return "%.1f MB" % (float(bytes) / float(1024 * 1024))
	return "%.1f KB" % (float(bytes) / 1024.0)
