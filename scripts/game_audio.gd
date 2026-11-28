extends Node
## Reused voice pool, per-cue limits and a quiet dedicated rolling loop.

const VOICE_LIMIT := 10
const CUES := {
	&"charge": [-14.0, 0.25, 2], &"launch": [-11.0, 0.08, 2],
	&"impact": [-8.0, 0.075, 3], &"spray": [-13.0, 0.09, 2],
	&"burst": [-15.0, 0.12, 2], &"splash": [-24.0, 0.09, 0],
	&"mine": [-14.0, 0.2, 2], &"shot": [-17.0, 0.065, 1],
	&"boss_hit": [-16.0, 0.08, 1], &"hurt": [-10.0, 0.12, 4],
	&"dash": [-16.0, 0.10, 2], &"drink": [-17.0, 0.30, 1],
	&"win": [-10.0, 0.5, 5], &"lose": [-11.0, 0.5, 5],
}
var streams: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var last_play: Dictionary = {}
var pitch_random := RandomNumberGenerator.new()
var enabled := DisplayServer.get_name() != "headless"

func _ready() -> void:
	pitch_random.randomize()
	if AudioServer.get_bus_index(&"SFX") < 0:
		AudioServer.add_bus()
		var bus := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, &"SFX")
		AudioServer.set_bus_volume_db(bus, -5.0)
		AudioServer.add_bus_effect(bus, AudioEffectLimiter.new())
	for cue in CUES:
		streams[cue] = load("res://audio/sfx/%s.wav" % cue)
	streams[&"roll"] = load("res://audio/sfx/roll.wav").duplicate()
	var rolling: AudioStreamWAV = streams[&"roll"]
	rolling.loop_mode = AudioStreamWAV.LOOP_FORWARD
	rolling.loop_begin = 0
	rolling.loop_end = roundi(rolling.get_length() * rolling.mix_rate)
	for index in range(VOICE_LIMIT):
		var voice := AudioStreamPlayer.new()
		voice.bus = &"SFX"
		add_child(voice)
		voices.append(voice)

func play(cue: StringName) -> bool:
	if not enabled or not CUES.has(cue):
		return false
	var spec: Array = CUES[cue]
	var now := Time.get_ticks_msec()
	if last_play.has(cue) and now - int(last_play[cue]) < float(spec[1]) * 1000.0:
		return false
	var selected: AudioStreamPlayer
	var same_cue := 0
	for voice in voices:
		if not voice.playing:
			if selected == null:
				selected = voice
		elif voice.get_meta(&"cue", &"") == cue:
			same_cue += 1
	if same_cue >= 2:
		return false
	if selected == null:
		for voice in voices:
			if int(voice.get_meta(&"priority", 0)) < int(spec[2]):
				selected = voice
				break
	if selected == null:
		return false
	selected.stop()
	selected.stream = streams[cue]
	selected.volume_db = float(spec[0])
	selected.pitch_scale = 1.0 if cue in [&"win", &"lose", &"charge"] else pitch_random.randf_range(0.96, 1.04)
	selected.set_meta(&"cue", cue)
	selected.set_meta(&"priority", spec[2])
	selected.play()
	last_play[cue] = now
	return true

func create_roll_loop(owner_node: Node) -> AudioStreamPlayer:
	var loop := AudioStreamPlayer.new()
	loop.stream = streams[&"roll"]
	loop.bus = &"SFX"
	loop.volume_db = -24.0
	owner_node.add_child(loop)
	return loop

func stop_all() -> void:
	for voice in voices:
		voice.stop()
		voice.stream = null
	last_play.clear()

func _exit_tree() -> void:
	stop_all()
