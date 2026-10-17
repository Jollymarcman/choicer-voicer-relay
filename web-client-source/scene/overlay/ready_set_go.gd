extends Control

signal finished

var countsize: int = 2

@onready var hbar = $VBoxContainer / HBar
@onready var lbl = $Label
@onready var countdown_pre = $CountdownPre
@onready var countdown_final = $CountdownFinal

func _ready():
	Begin()


func Begin():
	countdown_final.connect("finished", countdown_final.queue_free)
	countdown_final.reparent(get_parent())
	lbl.visible = false
	var tween = get_tree().create_tween()

	tween.tween_property(hbar, "size_flags_stretch_ratio", 6.0, 0.5)
	await tween.tween_interval(0.3).finished
	CountDown()


func CountDown():
	lbl.visible = true
	while countsize > 0:
		var tweenA = get_tree().create_tween().set_trans(Tween.TRANS_BACK)
		var tweenB = get_tree().create_tween().set_trans(Tween.TRANS_BACK).set_parallel(true)
		lbl.text = str(countsize)
		countdown_pre.play()
		tweenA.tween_property(lbl, "theme_override_font_sizes/font_size", 320, 0.9)
		tweenB.tween_property(lbl, "theme_override_constants/outline_size", 54, 0.9)
		await tweenB.tween_interval(1.0).finished
		lbl.add_theme_font_size_override("font_size", 192)
		lbl.add_theme_constant_override("outline_size", 32)
		countsize -= 1
	lbl.text = "GO!"
	countdown_final.play()
	var tween1 = get_tree().create_tween().set_trans(Tween.TRANS_SINE)
	var tween2 = get_tree().create_tween().set_trans(Tween.TRANS_SINE)
	var tween3 = get_tree().create_tween().set_trans(Tween.TRANS_SINE).set_parallel(true)
	tween1.tween_property(lbl, "theme_override_font_sizes/font_size", 320, 0.5)
	tween2.tween_property(lbl, "theme_override_constants/outline_size", 54, 0.5)

	tween3.tween_property(hbar, "size_flags_stretch_ratio", 0, 0.45)
	await tween3.tween_interval(0.5).finished
	finished.emit()
	queue_free()


func TweenKill():
	for tween in get_tree().get_processed_tweens():
		tween.kill()
