extends RefCounted
## Stage content: 5 stage timelines, enemy waves, mid-bosses and
## multi-phase bosses driven by named pattern scripts.

const W := 360.0
const H := 640.0
const F_OFFOK := 4
const F_BOUNCE := 8
const F_SPLIT := 16
const F_REAIM := 2

var g  # game.gd
var dt := 0.016

const INFO := [
	{},
	{"name": "Halo Outskirts", "col": Color(0.2, 0.9, 1.0), "ci": 4, "ci2": 5, "boss": "HALO SENTINEL", "mid": "Sentinel Drone"},
	{"name": "Prism Expanse", "col": Color(1.0, 0.3, 0.9), "ci": 7, "ci2": 6, "boss": "PRISM WARDEN", "mid": "Facet Guard"},
	{"name": "Tidal Nebula", "col": Color(0.35, 1.0, 0.45), "ci": 3, "ci2": 4, "boss": "TIDAL ENGINE", "mid": "Undertow"},
	{"name": "Crimson Corona", "col": Color(1.0, 0.4, 0.2), "ci": 0, "ci2": 1, "boss": "CRIMSON CHOIR", "mid": "Cantor"},
	{"name": "Null Zenith", "col": Color(1.0, 0.9, 0.35), "ci": 2, "ci2": 8, "boss": "NULL SERAPH", "mid": "Herald"},
]

const MID := [
	[],
	[["fans", "Scatter Fan"], ["rings", "Pulse Rings"]],
	[["petal", "Petal Drift"], ["stop_reaim", "Hold & Hunt"]],
	[["wave_curtain", "Wave Wall"], ["whirl", "Eddy"]],
	[["cross", "Crossfire"], ["rain_aim", "Ember Rain"]],
	[["bounce_fans", "Ricochet"], ["starburst", "Starburst"]],
]

const BOSS := [
	[],
	[["spiral_fans", "Halo Sign: Orbit Fan"], ["double_spiral", "Halo Sign: Twin Helix"], ["ring_rain", "Halo Sign: Falling Rings"]],
	[["prism", "Prism Sign: Refraction"], ["laser_cage", "Prism Sign: Light Cage"], ["flower_spiral", "Prism Sign: Glass Bloom"], ["stop_reaim", "Prism Sign: Focal Point"]],
	[["tide_curtain", "Tide Sign: Riptide Curtain"], ["laser_rake", "Tide Sign: Searchlights"], ["whirlpool", "Tide Sign: Maelstrom"], ["big_split", "Tide Sign: Burst Bubbles"]],
	[["choir", "Choir Sign: Three Voices"], ["laser_star", "Choir Sign: Solar Wheel"], ["split_rain", "Choir Sign: Ember Hail"], ["bounce_fans", "Choir Sign: Echo Chamber"]],
	[["halo", "Null Sign: Event Horizon"], ["curtain_lasers", "Null Sign: Gate of Light"], ["starburst", "Null Sign: Supernova"], ["reaim_storm", "Null Sign: Gravity Well"], ["finale", "Last Sign: Stellar Barrage"]],
]

func info(s: int) -> Dictionary:
	return INFO[clampi(s, 1, 5)]

# ================================================================ timelines
func events(s: int) -> Array:
	var c: int = INFO[s].ci
	var c2: int = INFO[s].ci2
	var fp = ["aim1", "aim3", "ring", "burst", "aim3"][s - 1]
	var tp = ["ring", "spiral", "flower", "spiral", "flower"][s - 1]
	var e := [
		[1.0, "swoop", {"side": -1, "n": 6, "y": 90, "c": c}],
		[3.5, "swoop", {"side": 1, "n": 6, "y": 120, "c": c2}],
		[6.5, "rain", {"n": 10, "dur": 4.0, "c": c, "fp": "aim1"}],
		[11.0, "pair", {"fp": tp, "hold": 5.0, "c": c2}],
		[16.5, "vee", {"n": 7, "c": c, "fp": fp}],
		[20.0, "swoop", {"side": -1, "n": 8, "y": 70, "c": c2, "fp": "aim1"}],
		[21.5, "swoop", {"side": 1, "n": 8, "y": 100, "c": c, "fp": "aim1"}],
		[25.0, "line", {"n": 6, "c": c2, "fp": "ring"}],
		[30.0, "midboss", {}],
		[31.0, "column", {"x": 90, "n": 8, "c": c, "fp": fp}],
		[33.0, "column", {"x": 270, "n": 8, "c": c2, "fp": fp}],
		[37.0, "heavy", {"fp": "spiral", "hold": 7.0, "c": c}],
		[39.0, "rain", {"n": 14, "dur": 6.0, "c": c2, "fp": "aim1"}],
		[46.0, "pair", {"fp": tp, "hold": 6.0, "c": c}],
		[48.0, "swoop", {"side": 1, "n": 8, "y": 60, "c": c2, "fp": "aim1"}],
		[53.0, "vee", {"n": 9, "c": c, "fp": fp}],
		[56.0, "line", {"n": 7, "c": c2, "fp": "ring"}],
		[60.0, "swoop", {"side": -1, "n": 10, "y": 80, "c": c, "fp": "aim1"}],
		[61.0, "swoop", {"side": 1, "n": 10, "y": 110, "c": c2, "fp": "aim1"}],
	]
	if s >= 3:
		e.append([42.0, "heavy", {"fp": "flower", "hold": 6.0, "c": c2, "x": 90}])
		e.append([64.0, "pair", {"fp": "spiral", "hold": 4.0, "c": c}])
	if s >= 4:
		e.append([14.0, "rain", {"n": 12, "dur": 4.0, "c": c2, "fp": "aim3"}])
		e.append([50.0, "heavy", {"fp": "spiral", "hold": 5.0, "c": c, "x": 270}])
	if s == 5:
		e.append([27.0, "pair", {"fp": "flower", "hold": 3.0, "c": c}])
		e.append([66.0, "rain", {"n": 18, "dur": 4.0, "c": c, "fp": "aim1"}])
	e.append([71.0, "boss", {}])
	e.sort_custom(func(a, b): return a[0] < b[0])
	return e

# ================================================================ enemies
func mk(x: float, y: float, kind: String, ci: int) -> Dictionary:
	var s: int = g.stage
	var hpm := 1.0 + 0.15 * (s - 1)
	var d := {"x": x, "y": y, "x0": x, "y0": y, "vx": 0.0, "vy": 0.0, "kind": kind, "ci": ci, "t": 0.0,
		"mv": "lin", "fp": "", "fi": 1.5, "fc": randf_range(0.4, 1.4), "flash": 0.0, "delay": 0.0, "gone": false,
		"a": 0.0, "b": 0.0, "tx": x, "ty": y, "hold": 3.0, "turn": 0.0, "rot": randf() * TAU}
	match kind:
		"dart":
			d.r = 10.0; d.hp = 3.0 * hpm; d.score = 1000; d.drop = "p"
		"drone":
			d.r = 12.0; d.hp = 9.0 * hpm; d.score = 2000; d.drop = "pt"
		"orb":
			d.r = 14.0; d.hp = 22.0 * hpm; d.score = 4000; d.drop = "mix"
		"turret":
			d.r = 18.0; d.hp = 70.0 * hpm; d.score = 10000; d.drop = "mix"
		_:
			d.r = 26.0; d.hp = 260.0 * hpm; d.score = 30000; d.drop = "big"
	d.mhp = d.hp
	return d

func spawn_wave(id: String, p: Dictionary) -> void:
	var c: int = p.get("c", 4)
	var fp: String = p.get("fp", "")
	match id:
		"swoop":
			var side: float = p.side
			for k in p.n:
				var e := mk(-20.0 if side < 0 else W + 20.0, p.y, "dart", c)
				e.mv = "curve"
				e.vx = 150.0 if side < 0 else -150.0
				e.vy = 20.0
				e.turn = 0.9 * (1.0 if side < 0 else -1.0)
				e.delay = k * 0.28
				e.fp = fp
				e.fi = 2.0
				g.spawn_enemy(e)
		"rain":
			for k in p.n:
				var e := mk(randf_range(30, W - 30), -20, "dart" if k % 3 else "drone", c)
				e.mv = "sine"
				e.vy = randf_range(90, 130)
				e.a = randf_range(10, 40)
				e.b = randf_range(1.5, 3.0)
				e.delay = p.dur * k / p.n
				e.fp = fp
				e.fi = 1.6
				g.spawn_enemy(e)
		"vee":
			for k in p.n:
				var off: int = k - p.n / 2
				var e := mk(W / 2 + off * 30, -20 - absi(off) * 22, "drone", c)
				e.vy = 110.0
				e.fp = fp
				e.fi = 1.8
				g.spawn_enemy(e)
		"line":
			for k in p.n:
				var e := mk(40 + k * (W - 80) / (p.n - 1), -20, "orb", c)
				e.mv = "stop"
				e.tx = e.x
				e.ty = 110 + (k % 2) * 30
				e.hold = 3.0
				e.delay = k * 0.15
				e.fp = fp
				e.fi = 1.4
				g.spawn_enemy(e)
		"pair":
			for k in 2:
				var e := mk(90.0 + k * 180.0, -30, "turret", c)
				e.mv = "stop"
				e.tx = e.x
				e.ty = 150.0
				e.hold = p.hold
				e.fp = p.fp
				e.fi = 0.1 if p.fp == "spiral" else (0.35 if p.fp == "flower" else 0.9)
				g.spawn_enemy(e)
		"column":
			for k in p.n:
				var e := mk(p.x, -20, "drone", c)
				e.mv = "sine"
				e.vy = 120.0
				e.a = 40.0
				e.b = 2.2
				e.delay = k * 0.35
				e.fp = fp
				e.fi = 1.6
				g.spawn_enemy(e)
		"heavy":
			var e := mk(p.get("x", W / 2), -40, "heavy", c)
			e.mv = "stop"
			e.tx = e.x
			e.ty = 140.0
			e.hold = p.hold
			e.fp = p.fp
			e.fi = 0.08 if p.fp == "spiral" else 0.3
			g.spawn_enemy(e)

func enemy_update(e: Dictionary, pdt: float) -> void:
	dt = pdt
	e.rot += dt * 2.0
	match e.mv:
		"lin":
			e.x += e.vx * dt
			e.y += e.vy * dt
		"curve":
			var v := Vector2(e.vx, e.vy).rotated(e.turn * dt * (1.0 if e.t < 1.4 else 0.2))
			e.vx = v.x
			e.vy = v.y
			e.x += e.vx * dt
			e.y += e.vy * dt
		"sine":
			e.y += e.vy * dt
			e.x = e.x0 + sin(e.t * e.b) * e.a
		"stop":
			if e.t < 1.2:
				var k := ease(e.t / 1.2, 0.4)
				e.x = lerpf(e.x0, e.tx, k)
				e.y = lerpf(e.y0, e.ty, k)
			elif e.t > 1.2 + e.hold:
				e.vy = minf(e.vy + 140.0 * dt, 160.0)
				e.y -= e.vy * dt * 0.8
	if e.fp == "" or e.t < 0.5 or e.y < 8 or e.y > H * 0.7:
		return
	if e.mv == "stop" and e.t > 1.2 + e.hold:
		return
	e.fc -= dt
	if e.fc > 0.0:
		return
	var sp = 120.0 * (1.0 + 0.05 * (g.stage - 1))
	e.fc = e.fi / (1.0 if e.fi < 0.2 else g.dden)
	var x: float = e.x
	var y: float = e.y
	var c: int = e.ci
	match e.fp:
		"aim1":
			g.fire(x, y, g.aim(x, y), sp * 1.1, c, 1, 4)
			g.sfx.play("eshot", -14.0)
		"aim3":
			g.fan(x, y, 3, 0.4, g.aim(x, y), sp, c, 1, 4)
			g.sfx.play("eshot", -14.0)
		"burst":
			for k in 3 + g.diff:
				g.fire(x, y, g.aim(x, y), sp * (0.8 + k * 0.18), c, 0, 4)
		"ring":
			g.ring(x, y, g.cnt(12), sp * 0.85, randf() * TAU, c, 0, 4)
			g.sfx.play("eshot", -12.0)
		"spiral":
			e.rot += 0.33
			for k in 2:
				g.fire(x, y, e.rot + PI * k, sp, c, 1, 4)
		"flower":
			e.rot += 0.2
			for i in g.ring(x, y, g.cnt(8), sp * 0.8, e.rot, c, 0, 4):
				g.eb.set_motion(i, 0.0, 0.7)

func on_split(sp: Array) -> void:
	var n: int = sp[2]
	g.ring(sp[0], sp[1], maxi(4, n), 100.0, randf() * TAU, sp[3], 0, 3.5)

# ================================================================ bosses
func make_boss(s: int, mid: bool) -> Dictionary:
	var inf: Dictionary = INFO[s]
	var list: Array = MID[s] if mid else BOSS[s]
	var phases := []
	for k in list.size():
		var hp := (520.0 + s * 120.0) if mid else (950.0 + s * 260.0 + k * 120.0)
		phases.append({"pat": list[k][0], "name": list[k][1], "hp": hp, "time": 30.0 if mid else 42.0 + k * 2.0})
	if not mid:
		phases[phases.size() - 1].hp *= 1.25
	var b := {"x": W / 2, "y": -70.0, "tx": W / 2, "ty": 130.0, "r": 22.0 if mid else 30.0, "hp": phases[0].hp,
		"maxhp": phases[0].hp, "phases": phases, "pi": 0, "pt": 0.0, "st": 0.0, "state": "enter",
		"name": inf.mid if mid else inf.boss, "col": inf.col, "ci": inf.ci, "ci2": inf.ci2, "mid": mid,
		"vuln": false, "acc": {}, "flash": 0.0, "mt": 0.0, "kind": s, "rot": 0.0}
	return b

func boss_update(b: Dictionary, pdt: float) -> void:
	dt = pdt
	b.st += dt
	b.rot += dt
	match b.state:
		"enter":
			b.y = lerpf(-70.0, 130.0, ease(minf(1.0, b.st / 1.8), 0.4))
			if b.st >= 1.8:
				b.state = "trans"
				b.st = 0.0
		"trans":
			b.x = lerpf(b.x, W / 2, dt * 3.0)
			b.y = lerpf(b.y, 130.0, dt * 3.0)
			if b.st >= 1.1:
				b.state = "fight"
				b.vuln = true
				b.pt = 0.0
				b.tx = b.x
				b.ty = b.y
				g.phase_clean = true
				g.banner = ""
				g.popup(W / 2, 210, b.phases[b.pi].name, b.col)
		"fight":
			b.pt += dt
			var pat: String = b.phases[b.pi].pat
			_boss_move(b, pat)
			_pattern(b, pat)

func _boss_move(b: Dictionary, pat: String) -> void:
	if pat in ["laser_star", "halo", "whirlpool", "laser_rake", "finale"]:
		b.tx = W / 2
		b.ty = 140.0
	else:
		b.mt -= dt
		if b.mt <= 0.0:
			b.mt = randf_range(2.5, 4.0)
			b.tx = clampf(g.px + randf_range(-60, 60), 70, W - 70)
			b.ty = randf_range(95, 165)
	b.x = lerpf(b.x, b.tx, dt * 1.4)
	b.y = lerpf(b.y, b.ty, dt * 1.4)

func ev(b: Dictionary, k: String, iv: float) -> bool:
	var a: Dictionary = b.acc
	var v: float = a.get(k, 0.4) - dt
	if v <= 0.0:
		a[k] = maxf(v + iv, 0.0)
		return true
	a[k] = v
	return false

func _r(b: Dictionary, k: String, d: float) -> float:
	var a: Dictionary = b.acc
	a[k] = a.get(k, 0.0) + d
	return a[k]

func _pattern(b: Dictionary, pat: String) -> void:
	var x: float = b.x
	var y: float = b.y
	var c: int = b.ci
	var c2: int = b.ci2
	var dd: float = g.dden
	var df: int = g.diff
	match pat:
		"fans":
			if ev(b, "a", 0.9 / dd):
				g.fan(x, y, 5 + df, 0.8, g.aim(x, y), 150, c, 1, 4)
				g.sfx.play("eshot", -10.0)
			if ev(b, "b", 2.2):
				g.ring(x, y, g.cnt(14), 90, randf() * TAU, c2, 0, 4.5)
		"rings":
			if ev(b, "a", 0.55 / dd):
				g.ring(x, y, g.cnt(16), 110, randf() * TAU, c2, 0, 4.5)
				g.sfx.play("eshot", -10.0)
			if ev(b, "b", 2.0):
				g.fan(x, y, 3, 0.3, g.aim(x, y), 170, c, 2, 7)
		"spiral_fans":
			if ev(b, "a", 0.09 / sqrt(dd)):
				var rot := _r(b, "rot", 0.27)
				for k in 3:
					g.fire(x, y, rot + k * TAU / 3.0, 130, c, 1, 4)
			if ev(b, "b", 1.6):
				g.fan(x, y, 5 + df * 2, 0.9, g.aim(x, y), 180, c2, 0, 4.5)
				g.sfx.play("eshot", -10.0)
		"double_spiral":
			if ev(b, "a", 0.075 / sqrt(dd)):
				var r1 := _r(b, "r1", 0.21)
				var r2 := _r(b, "r2", -0.19)
				for k in 2:
					g.fire(x, y, r1 + PI * k, 135, c, 1, 4)
					g.fire(x, y, r2 + PI * k + 0.5, 115, c2, 0, 4.5)
		"ring_rain":
			if ev(b, "a", 0.55 / dd):
				g.ring(x, y, g.cnt(18), 100, _r(b, "rot", 0.17), c, 0, 4.5)
			if ev(b, "b", 0.06 / dd):
				var i: int = g.fire(randf() * W, -10, PI / 2 + randf_range(-0.12, 0.12), randf_range(85, 130), 8, 0, 3.2)
				if i >= 0:
					g.eb.set_aux(i, F_OFFOK, 0, 0)
		"petal":
			if ev(b, "a", 0.32 / dd):
				var rot := _r(b, "rot", 0.13)
				for i in g.ring(x, y, g.cnt(12), 120, rot, c, 1, 4):
					g.eb.set_motion(i, 0, 0.8)
				for i in g.ring(x, y, g.cnt(12), 120, -rot, c2, 1, 4):
					g.eb.set_motion(i, 0, -0.8)
		"stop_reaim":
			if ev(b, "a", 1.1 / dd):
				for i in g.ring(x, y, g.cnt(22), 220, randf() * TAU, c2 if b.mid else c, 0, 4.5):
					g.eb.set_motion(i, -260.0, 0)
					g.eb.set_aux(i, F_REAIM, 1.0, 150.0 * g.dspd)
				g.sfx.play("eshot", -10.0)
			if not b.mid and ev(b, "b", 0.15 / dd):
				g.fire(x, y, _r(b, "rot", 0.5), 90, c2, 3, 3.5)
		"prism":
			if ev(b, "a", 0.065 / sqrt(dd)):
				var rot := _r(b, "rot", 0.11 + sin(b.pt * 0.5) * 0.06)
				for k in 5:
					g.fire(x, y, rot + k * TAU / 5.0, 140, [c, c2, 9][k % 3], 1, 4)
		"laser_cage":
			if ev(b, "a", 2.4):
				for k in 3 + df / 2:
					g.laser(randf_range(30, W - 30), 0, PI / 2, 700, 22, 1.0, 1.1, 0, c)
				g.laser(g.px, 0, PI / 2, 700, 22, 1.1, 1.0, 0, c2)
			if ev(b, "b", 0.8 / dd):
				g.fan(x, y, 5, 0.6, g.aim(x, y), 160, c2, 1, 4)
		"flower_spiral":
			if ev(b, "a", 0.08 / sqrt(dd)):
				var rot := _r(b, "rot", 0.37)
				for k in 4:
					var i: int = g.fire(x, y, rot + k * TAU / 4.0, 150, 9 if k % 2 else c, 0, 4)
					if i >= 0:
						g.eb.set_motion(i, -40.0, 0.9)
		"wave_curtain":
			if ev(b, "a", 0.12 / dd):
				var ang := PI / 2 + sin(b.pt * 1.6) * 1.1
				var sg := signf(cos(b.pt * 1.6))
				for k in 3:
					var i: int = g.fire(x, y, ang + (k - 1) * 0.12, 150, c, 1, 4)
					if i >= 0:
						g.eb.set_motion(i, 0, 0.3 * sg)
		"whirl":
			if ev(b, "a", 0.3 / dd):
				var dir := 1.0 if int(b.pt / 2.0) % 2 == 0 else -1.0
				for i in g.ring(x, y, g.cnt(14), 60, _r(b, "rot", 0.2), c2, 0, 4.5):
					g.eb.set_motion(i, 70.0, 1.2 * dir)
		"tide_curtain":
			if ev(b, "a", 0.45 / sqrt(dd)):
				var gx := W / 2 + sin(b.pt * 0.7) * 120.0
				var spc := 19.0 / pow(dd, 0.3)
				var xx := 6.0
				while xx < W:
					if absf(xx - gx) > 40.0:
						var i: int = g.fire(xx, -8, PI / 2, 95, c, 0, 4.5)
						if i >= 0:
							g.eb.set_aux(i, F_OFFOK, 0, 0)
					xx += spc
			if ev(b, "b", 1.3):
				g.fire(x, y, g.aim(x, y), 150, c2, 2, 9)
		"laser_rake":
			if ev(b, "a", 3.2):
				for s in [-1.0, 1.0]:
					g.laser(x, y, PI / 2 + s * 1.05, 700, 18, 0.8, 1.8, -s * 0.55, c, b)
			if ev(b, "b", 0.42 / dd):
				g.ring(x, y, g.cnt(10), 100, randf() * TAU, c2, 0, 4.5)
		"whirlpool":
			if ev(b, "a", 0.05 / sqrt(dd)):
				var rot := _r(b, "rot", 0.5)
				for k in 2:
					var i: int = g.fire(x, y, rot + PI * k, 40, c if k == 0 else c2, 1, 4)
					if i >= 0:
						g.eb.set_motion(i, 90.0, 1.5)
		"big_split":
			if ev(b, "a", 0.9 / dd):
				var i: int = g.fire(x, y, g.aim(x, y) + randf_range(-0.6, 0.6), 140, c2, 2, 10)
				if i >= 0:
					g.eb.set_motion(i, -90.0, 0)
					g.eb.set_aux(i, F_SPLIT, 1.1, g.cnt(14))
			if ev(b, "b", 0.2):
				g.fire(x, y, _r(b, "rot", 0.7), 110, c, 3, 3.5)
		"cross":
			if ev(b, "a", 0.08 / sqrt(dd)):
				var r1 := _r(b, "r1", 0.07)
				for k in 4:
					g.fire(x, y, r1 + k * TAU / 4.0, 160, c, 1, 4)
			if ev(b, "b", 0.08 / sqrt(dd)):
				var r2 := _r(b, "r2", -0.09)
				for k in 4:
					g.fire(x, y, r2 + k * TAU / 4.0 + 0.4, 115, c2, 0, 4)
		"rain_aim":
			if ev(b, "a", 0.07 / dd):
				var i: int = g.fire(randf() * W, -8, PI / 2 + randf_range(-0.25, 0.25), randf_range(110, 170), c2, 1, 3.5)
				if i >= 0:
					g.eb.set_aux(i, F_OFFOK, 0, 0)
			if ev(b, "b", 0.9):
				for k in 5:
					g.fire(x, y, g.aim(x, y), 120 + k * 30, c, 2, 6)
				g.sfx.play("eshot", -10.0)
		"choir":
			if ev(b, "a", 0.75 / dd):
				var rot := _r(b, "rot", 0.17)
				for k in 3:
					g.ring(x, y, g.cnt(18), 80 + k * 45, rot + k * 0.1, [c, c2, 9][k], 0, 4.5)
				g.sfx.play("eshot", -10.0)
		"laser_star":
			if not b.acc.has("init"):
				b.acc["init"] = true
				for k in 6:
					g.laser(x, y, k * TAU / 6.0, 720, 16, 1.4, 999.0, 0.32, c, b)
			if ev(b, "b", 0.5 / dd):
				g.fan(x, y, 3, 0.35, g.aim(x, y), 150, c2, 1, 4)
			if ev(b, "c", 1.7 / dd):
				g.ring(x, y, g.cnt(20), 85, randf() * TAU, 9, 0, 4)
		"split_rain":
			if ev(b, "a", 0.55 / dd):
				var i: int = g.fire(randf_range(20, W - 20), -10, PI / 2, 120, c, 2, 9)
				if i >= 0:
					g.eb.set_aux(i, F_SPLIT | F_OFFOK, 1.0 + randf() * 1.4, g.cnt(10))
			if ev(b, "b", 1.2):
				g.fan(x, y, 7, 1.0, g.aim(x, y), 150, c2, 1, 4)
		"bounce_fans":
			if ev(b, "a", 0.55 / dd):
				for i in g.fan(x, y, g.cnt(9), 2.2, g.aim(x, y), 170, c2 if b.mid else c, 1, 4):
					g.eb.set_aux(i, F_BOUNCE, 0, 0)
				g.sfx.play("eshot", -10.0)
		"halo":
			if ev(b, "a", 0.055 / sqrt(dd)):
				var r1 := _r(b, "r1", 0.23)
				var r2 := _r(b, "r2", -0.23)
				for k in 3:
					g.fire(x, y, r1 + k * TAU / 3.0, 150, c, 1, 4)
					g.fire(x, y, r2 + k * TAU / 3.0, 120, c2, 0, 4)
		"curtain_lasers":
			if ev(b, "a", 0.5 / sqrt(dd)):
				var off := fmod(b.pt * 23.0, 22.0)
				var xx := off
				while xx < W:
					var i: int = g.fire(xx, -8, PI / 2 + sin(b.pt + xx * 0.02) * 0.2, 90, c, 0, 4)
					if i >= 0:
						g.eb.set_aux(i, F_OFFOK, 0, 0)
					xx += 26.0 / pow(dd, 0.3)
			if ev(b, "c", 2.6):
				g.laser(g.px, 0, PI / 2, 700, 26, 1.0, 0.8, 0, c2)
				g.laser(clampf(g.px + randf_range(-120, 120), 20, W - 20), 0, PI / 2, 700, 26, 1.0, 0.8, 0, c2)
		"starburst":
			if ev(b, "a", 0.85 / dd):
				for i in g.ring(x, y, g.cnt(8), 160, randf() * TAU, c, 2, 9):
					g.eb.set_motion(i, -120.0, 0)
					g.eb.set_aux(i, F_SPLIT, 0.8, g.cnt(10))
			if ev(b, "b", 0.16):
				g.fire(x, y, g.aim(x, y) + randf_range(-0.2, 0.2), 150, c2, 3, 3.5)
		"reaim_storm":
			if ev(b, "a", 0.6 / dd):
				for i in g.ring(x, y, g.cnt(26), 260, randf() * TAU, 8, 1, 4):
					g.eb.set_motion(i, -330.0, 0)
					g.eb.set_aux(i, F_REAIM, 0.9, 190.0 * g.dspd)
			if ev(b, "b", 1.8):
				g.laser(x, y, g.aim(x, y), 720, 18, 0.9, 0.6, 0, c)
		"finale":
			if ev(b, "a", 0.065 / sqrt(dd)):
				var rot := _r(b, "rot", 0.19)
				for k in 4:
					g.fire(x, y, rot + k * TAU / 4.0, 140, [c, c2, 0, 7][k], 1, 4)
			if ev(b, "b", 1.1 / dd):
				g.fan(x, y, 9, 1.2, g.aim(x, y), 170, 8, 0, 4.5)
			if ev(b, "c", 3.2):
				var base := randf() * TAU
				for k in 4:
					g.laser(x, y, base + k * TAU / 4.0, 720, 14, 1.0, 2.0, 0.45, c, b)

# ================================================================ drawing
func draw_enemy(c: CanvasItem, e: Dictionary) -> void:
	var col: Color = g.pal[e.ci]
	if e.flash > 0.0:
		col = Color.WHITE
	var p := Vector2(e.x, e.y)
	var r: float = e.r
	var pts: PackedVector2Array
	match e.kind:
		"dart":
			var ang := atan2(e.vy, e.vx) - PI / 2 if e.mv != "sine" else 0.0
			pts = g.shape(p, [[0, 1.0], [0.8, -0.7], [0, -0.3], [-0.8, -0.7]], r, ang)
		"drone":
			pts = g.shape(p, [[0, 1], [1, 0], [0, -1], [-1, 0]], r, 0)
			g._poly(c, p, r * 0.45, 4, e.rot, col, 1.5)
		"orb":
			pts = PackedVector2Array()
			for k in 7:
				pts.append(p + Vector2(cos(e.rot * 0.5 + k * TAU / 6), sin(e.rot * 0.5 + k * TAU / 6)) * r)
			c.draw_circle(p, r * 0.35, Color(col, 0.8))
		"turret":
			pts = g.shape(p, [[1, 1], [1, -1], [-1, -1], [-1, 1]], r * 0.8, e.rot * 0.6)
			g._poly(c, p, r * 1.15, 8, -e.rot, Color(col, 0.5), 1.5)
			c.draw_circle(p, r * 0.3, Color(1, 1, 1, 0.7))
		_:
			pts = PackedVector2Array()
			for k in 9:
				pts.append(p + Vector2(cos(k * TAU / 8 + PI / 8), sin(k * TAU / 8 + PI / 8)) * r)
			for k in 4:
				var a: float = e.rot + k * PI / 2
				c.draw_line(p + Vector2(cos(a), sin(a)) * r * 0.4, p + Vector2(cos(a), sin(a)) * r * 1.35, Color(col, 0.7), 2)
			g._poly(c, p, r * 0.55, 6, -e.rot, col, 2)
			if e.hp < e.mhp:
				c.draw_rect(Rect2(e.x - r, e.y - r - 8, 2 * r * e.hp / e.mhp, 2), Color(col, 0.8))
	c.draw_colored_polygon(pts, Color(col.r * 0.12, col.g * 0.12, col.b * 0.15, 0.85))
	g.neon(c, pts, col, 1.5)

func draw_boss(c: CanvasItem, b: Dictionary) -> void:
	var col: Color = b.col
	var p := Vector2(b.x, b.y)
	var sc := 0.72 if b.mid else 1.0
	var s: int = b.kind
	var hot = b.flash > 0.0
	var mc := Color.WHITE if hot else col
	# aura
	c.draw_circle(p, 58 * sc, Color(col, 0.06))
	c.draw_circle(p, 40 * sc, Color(col, 0.08))
	# rotating rings
	var sides := s + 2
	g._poly(c, p, 46 * sc, sides, b.rot * 0.6, Color(mc, 0.7), 2)
	g._poly(c, p, 34 * sc, sides, -b.rot * 0.9, Color(mc, 0.9), 2)
	# orbiting nodes
	for k in 6:
		var a: float = b.rot * 1.3 + k * TAU / 6
		var q := p + Vector2(cos(a), sin(a) * 0.55) * 64 * sc
		c.draw_circle(q, 5 * sc, Color(col, 0.35))
		g._poly(c, q, 4 * sc, 3, a, mc, 1.5)
	# wings
	for sd in [-1.0, 1.0]:
		var wpts = g.shape(p, [[sd * 20, -6], [sd * 70, -22], [sd * 58, 6], [sd * 80, 18], [sd * 30, 14]], sc, 0)
		c.draw_colored_polygon(wpts, Color(col.r * 0.15, col.g * 0.15, col.b * 0.2, 0.8))
		g.neon(c, wpts, mc, 1.6)
	var core = g.shape(p, [[0, -26], [18, 0], [0, 26], [-18, 0]], sc, 0)
	c.draw_colored_polygon(core, Color(col.r * 0.2, col.g * 0.2, col.b * 0.25, 0.95))
	g.neon(c, core, mc, 2.0)
	c.draw_circle(p, (8 + sin(b.rot * 6) * 2) * sc, Color(1, 1, 1, 0.9))
	if b.state == "fight":
		# phase timer ring
		var ph: Dictionary = b.phases[b.pi]
		var k := clampf(b.hp / b.maxhp, 0.0, 1.0)
		c.draw_arc(p, 76 * sc, -PI / 2, -PI / 2 + TAU * k, 48, Color(col, 0.55), 3)
