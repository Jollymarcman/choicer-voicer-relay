extends Control



@onready var vclip_drawer = $VclipDrawer
@onready var plmic_drawer = $PlmicDrawer
@onready var pitch_drawer = $PitchDrawer


func CollectFrameSamples(type: String):
	match type:
		"plmic":
			plmic_drawer.CollectFrameSamples()
		"vclip":
			vclip_drawer.CollectFrameSamples()
		_:
			print("WaveformDualDataDrawer | Moron, you somehow coded something wrong.")


func Colorize(color_dict: Dictionary):
	vclip_drawer.vclip_color = color_dict.voice_color
	vclip_drawer.vclip_color_max = Color(color_dict.voice_color, 0.88) / 2.0
	plmic_drawer.plmic_color = color_dict.user_color
	plmic_drawer.plmic_color_max = Color(color_dict.user_color, 0.88) / 2.0


func ClearHistory():
	plmic_drawer.ClearHistory()
	vclip_drawer.ClearHistory()


func Reset():
	ClearHistory()
	queue_redraw()



func _draw():
	plmic_drawer.queue_redraw()
	vclip_drawer.queue_redraw()



func SamplePlmic():
	plmic_drawer.CollectFrameSamples()
	plmic_drawer.queue_redraw()

func SampleVclip():
	vclip_drawer.CollectFrameSamples()
	vclip_drawer.queue_redraw()

func UpdateBoth():
	plmic_drawer.queue_redraw()
	vclip_drawer.queue_redraw()


func get_plmic_data() -> Dictionary:
	return plmic_drawer.get_plmic_data()

func get_vclip_data() -> Dictionary:
	return vclip_drawer.get_vclip_data()

func set_vclip_data(d: Dictionary):
	vclip_drawer.set_vclip_data(d)

func set_plmic_data(d: Dictionary):
	plmic_drawer.set_plmic_data(d)
