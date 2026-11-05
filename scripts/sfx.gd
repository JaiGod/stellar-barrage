extends Node
## All sound is synthesized at runtime: no audio files ship with the game.
## SFX are rendered once at startup; music loops are rendered a few steps
## per frame so the title screen never hitches.

const RATE := 22050
const MRATE := 11025
var voices: Array[AudioStreamPlayer] = []
var vi := 0
var streams := {}
var gaps := {"shot": 0.075, "eshot": 0.07, "graze": 0.045, "hit": 0.05, "item": 0.045, "pop": 0.04, "move": 0.03}
var last := {}
var music: AudioStreamPlayer
var tracks := {}
var jobs: Array = []
var want := ""
var muted := false
var _seed := 1234567

func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		voices.append(p)
	music = AudioStreamPlayer.new()
	music.volume_db = -9.0
	add_child(music)
	_build_sfx()
	# title, stage, boss loops: [name, roots, minor, tempo-step, drums]
	jobs.append(_job("title", [0, -4, -7, -2], 0.15, 0))
	jobs.append(_job("stage", [0, -2, -4, -5], 0.1, 1))
	jobs.append(_job("boss", [0, 1, -4, -2], 0.09, 2))

func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, m)

func play(name: String, vol: float = 0.0, pitch: float = 1.0) -> void:
	if not streams.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if gaps.has(name):
		if now - float(last.get(name, -1.0)) < gaps[name]:
			return
	last[name] = now
	var p := voices[vi]
	vi = (vi + 1) % voices.size()
	p.stream = streams[name]
	p.volume_db = vol
	p.pitch_scale = pitch
	p.play()

func play_music(name: String) -> void:
	want = name
	if name == "":
		music.stop()
		return
	if tracks.has(name):
		if music.stream != tracks[name] or not music.playing:
			music.stream = tracks[name]
			music.play()

func _process(_dt: float) -> void:
	if jobs.size() > 0:
		var j: Dictionary = jobs[0]
		for k in 5:
			if _step_job(j):
				tracks[j.name] = _wav(j.data, MRATE, true)
				jobs.pop_front()
				if want == j.name:
					play_music(want)
				break

func _rnd() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return float(_seed) / 1073741823.5 - 1.0

func _wav(data: PackedByteArray, rate: int, loop: bool) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size() / 2
	return w

func _render(dur: float, fn: Callable) -> AudioStreamWAV:
	var ns := int(dur * RATE)
	var d := PackedByteArray()
	d.resize(ns * 2)
	for i in ns:
		var tt := float(i) / RATE
		var v: float = fn.call(tt, tt / dur)
		d.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	return _wav(d, RATE, false)

func _sq(ph: float) -> float:
	return 1.0 if fmod(ph, 1.0) < 0.5 else -1.0

func _build_sfx() -> void:
	streams["shot"] = _render(0.045, func(t, k): return _sq(t * lerpf(1500.0, 700.0, k)) * 0.12 * (1.0 - k))
	streams["eshot"] = _render(0.06, func(t, k): return sin(TAU * t * lerpf(900.0, 500.0, k)) * 0.16 * (1.0 - k))
	streams["graze"] = _render(0.05, func(t, k): return sin(TAU * t * 2600.0) * 0.2 * (1.0 - k))
	streams["hit"] = _render(0.035, func(t, k): return _rnd() * 0.18 * (1.0 - k))
	streams["item"] = _render(0.04, func(t, k): return sin(TAU * t * lerpf(1800.0, 2600.0, k)) * 0.14 * (1.0 - k))
	streams["pop"] = _render(0.22, func(t, k): return (_rnd() * 0.5 + sin(TAU * t * lerpf(220.0, 60.0, k)) * 0.5) * 0.45 * pow(1.0 - k, 2.0))
	streams["boom"] = _render(0.9, func(t, k): return (_rnd() * 0.6 + sin(TAU * t * lerpf(120.0, 30.0, k)) * 0.6) * 0.7 * pow(1.0 - k, 1.6))
	streams["bomb"] = _render(1.1, func(t, k): return (sin(TAU * t * lerpf(80.0, 900.0, k * k)) * 0.5 + _rnd() * 0.35 * (1.0 - k)) * 0.6 * minf(1.0, (1.0 - k) * 3.0))
	streams["power"] = _render(0.14, func(t, k): return _sq(t * lerpf(500.0, 1300.0, k)) * 0.14 * (1.0 - k))
	streams["extend"] = _render(0.6, func(t, k): return _sq(t * [523.0, 659.0, 784.0, 1046.0][mini(3, int(k * 4.0))]) * 0.16 * (1.0 - fmod(k * 4.0, 1.0) * 0.6))
	streams["die"] = _render(0.8, func(t, k): return (_sq(t * lerpf(600.0, 60.0, k)) * 0.3 + _rnd() * 0.4) * 0.6 * (1.0 - k))
	streams["warn"] = _render(1.6, func(t, k): return _sq(t * (440.0 if fmod(t, 0.4) < 0.2 else 330.0)) * 0.15 * (1.0 - k * 0.5))
	streams["move"] = _render(0.03, func(t, k): return _sq(t * 900.0) * 0.12 * (1.0 - k))
	streams["ok"] = _render(0.16, func(t, k): return _sq(t * (660.0 if k < 0.4 else 990.0)) * 0.14 * (1.0 - k))
	streams["back"] = _render(0.12, func(t, k): return _sq(t * lerpf(500.0, 250.0, k)) * 0.13 * (1.0 - k))
	streams["break"] = _render(0.7, func(t, k): return (sin(TAU * t * 880.0) + sin(TAU * t * 1320.0) * 0.6 + sin(TAU * t * 1760.0) * 0.4) * 0.16 * pow(1.0 - k, 1.5))
	streams["laser"] = _render(0.5, func(t, k): return (_sq(t * 110.0) * 0.5 + _rnd() * 0.3) * 0.25 * sin(PI * k))
	streams["start"] = _render(0.9, func(t, k): return _sq(t * [392.0, 523.0, 659.0, 784.0, 1046.0, 1046.0][mini(5, int(k * 6.0))]) * 0.15 * (1.0 - k * 0.7))

# ---------------------------------------------------------------- music
func _job(name: String, roots: Array, step: float, drums: int) -> Dictionary:
	var steps := 64
	var sps := int(step * MRATE)
	var d := PackedByteArray()
	d.resize(steps * sps * 2)
	return {"name": name, "roots": roots, "sps": sps, "steps": steps, "i": 0, "data": d, "drums": drums, "pb": 0.0, "pa": 0.0, "pl": 0.0}

func _note(semi: float) -> float:
	return 220.0 * pow(2.0, semi / 12.0)

## Renders one 16th-note step of a loop. Returns true when finished.
func _step_job(j: Dictionary) -> bool:
	var s: int = j.i
	if s >= j.steps:
		return true
	var sps: int = j.sps
	var root: int = j.roots[(s / 16) % 4]
	var chord := [0, 3, 7, 10, 12, 7, 3, 15]
	var bassf := _note(root - 24 + (12 if s % 8 == 6 else 0))
	var arpf := _note(root + chord[s % 8] + (12 if (s / 8) % 2 == 1 else 0))
	var lead_on: bool = j.drums == 2 and (s % 16 < 3 or s % 16 == 8 or s % 16 == 10)
	var leadf := _note(root + 12 + [0, 7, 3, 10][(s / 4) % 4])
	var dr: int = j.drums
	var pb: float = j.pb
	var pa: float = j.pa
	var pl: float = j.pl
	var data: PackedByteArray = j.data
	for i in sps:
		var tt := float(i) / MRATE
		var k := float(i) / sps
		pb += bassf / MRATE
		pa += arpf / MRATE
		pl += leadf / MRATE
		var v := 0.0
		# bass: saw
		var bv := (fmod(pb, 1.0) * 2.0 - 1.0) * 0.22
		if dr == 0:
			bv *= 0.6
		v += bv * (1.0 - k * 0.5)
		# arp: square pluck
		v += _sq(pa) * 0.09 * pow(1.0 - k, 2.0)
		if lead_on:
			v += (fmod(pl, 1.0) * 2.0 - 1.0) * 0.08
		if dr > 0:
			if s % 4 == 0:
				v += sin(TAU * 55.0 * tt * (1.0 + 2.0 * (1.0 - k))) * 0.5 * maxf(0.0, 1.0 - tt * 9.0)
			if s % 4 == 2:
				v += _rnd() * 0.08 * maxf(0.0, 1.0 - tt * 30.0)
			if dr == 2 and s % 8 == 4:
				v += _rnd() * 0.25 * maxf(0.0, 1.0 - tt * 10.0)
		else:
			if s % 16 == 0:
				v += sin(TAU * 440.0 * tt) * 0.05 * maxf(0.0, 1.0 - tt * 2.0)
		data.encode_s16((s * sps + i) * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	j.data = data
	j.pb = fmod(pb, 1.0)
	j.pa = fmod(pa, 1.0)
	j.pl = fmod(pl, 1.0)
	j.i = s + 1
	return j.i >= j.steps
