extends Node2D
## Gameplay core: player, shots, bombs, enemies, bosses, lasers, items,
## scoring. Stage content (waves + boss patterns) lives in stages.gd.

const W := 360.0
const H := 640.0
const HIT_R := 2.6
const GRAZE_R := 15.0
const PoolScript := preload("res://scripts/pool.gd")
const LayerScript := preload("res://scripts/layer.gd")
const StagesScript := preload("res://scripts/stages.gd")

const SHIPS := [
	{"name": "VANTA", "title": "Spread Nova", "speed": 205.0, "fspeed": 85.0, "col": Color(0.25, 0.95, 1.0), "bomb": "NOVA RING", "desc": "Wide fan shot that tightens when focused. Bomb: expanding nova rings."},
	{"name": "LANCE", "title": "Needle Beam", "speed": 185.0, "fspeed": 75.0, "col": Color(1.0, 0.3, 0.85), "bomb": "ZENITH LANCE", "desc": "Piercing needles; focus fires a continuous beam. Bomb: a giant vertical lance."},
	{"name": "SEEKER", "title": "Homing Swarm", "speed": 225.0, "fspeed": 95.0, "col": Color(0.55, 1.0, 0.3), "bomb": "SWARM HALO", "desc": "Weak forward shot plus homing missiles. Bomb: a halo that erases everything."},
]
const DIFFS := ["EASY", "NORMAL", "HARD", "OVERDRIVE"]
const DSPD := [0.78, 0.9, 1.0, 1.12]
const DDEN := [0.5, 0.75, 1.0, 1.35]
const EXTENDS := [10000000, 25000000, 50000000, 80000000, 120000000]

var main: Node
var sfx: Node
var st  # stages helper (RefCounted)
var eb  # enemy bullets pool
var ps  # player shots pool
var fx  # sparks pool
var it  # items pool
var L_bg: Node2D
var L_ent: Node2D
var L_ply: Node2D
var L_las: Node2D

# run configuration
var active := false
var paused := false
var practice := false
var diff := 1
var ship := 0
var stage := 1
var dspd := 1.0
var dden := 1.0
var god := false
var dmg_mult := 1.0

# run state
var score := 0
var mult := 1.0
var mult_idle := 0.0
var graze := 0
var stage_graze := 0
var lives := 2
var bombs := 3
var power := 0.0
var continues := 0
var next_extend := 0
var over := false
var all_clear := false

# player
var px := 180.0
var py := 560.0
var focus := false
var shooting := false
var touch_delta := Vector2.ZERO
var move_vec := Vector2.ZERO
var invuln := 0.0
var shot_cd := 0.0
var missile_cd := 0.0
var bomb_t := 0.0
var bomb_len := 0.0
var bomb_req := false
var dying := 0.0
var respawn := 0.0
var beam_on := false
var beam_end := 0.0
var trail := 0.0

# world
var enemies: Array = []
var lasers: Array = []
var popups: Array = []
var boss = null
var events: Array = []
var ev_i := 0
var tl_t := 0.0
var stage_t := 0.0
var phase := "intro"   # intro, play, clear
var phase_t := 0.0
var banner := ""
var banner2 := ""
var banner_t := 0.0
var warn_t := 0.0
var clear_bonus := 0
var shake := 0.0
var flash := 0.0
var flash_col := Color.WHITE
var bg_t := 0.0
var stars: Array = []
var gtime := 0.0
var stage_score0 := 0
var phase_clean := true

var pal := PackedColorArray([
	Color(1.0, 0.22, 0.3), Color(1.0, 0.55, 0.15), Color(1.0, 0.92, 0.2), Color(0.35, 1.0, 0.35),
	Color(0.2, 0.95, 1.0), Color(0.3, 0.45, 1.0), Color(0.7, 0.35, 1.0), Color(1.0, 0.3, 0.9),
	Color(0.95, 0.95, 1.0), Color(1.0, 0.6, 0.75)])

func _ready() -> void:
	st = StagesScript.new()
	st.g = self
	L_bg = _layer(_draw_bg)
	ps = _pool(400, _tex_glow(32, 2.0), _add_mat(), PackedColorArray([Color(0.3, 0.95, 1.0, 0.85), Color(1.0, 0.35, 0.9, 0.85), Color(0.6, 1.0, 0.35, 0.85), Color(1.0, 0.95, 0.6, 0.9)]))
	L_ent = _layer(_draw_ents)
	it = _pool(1500, _tex_item(), null, PackedColorArray([Color(1.0, 0.3, 0.35), Color(1.0, 0.25, 0.3), Color(0.35, 0.55, 1.0), Color(0.6, 1.0, 0.75), Color(0.4, 1.0, 0.45)]))
	L_ply = _layer(_draw_player)
	L_las = _layer(_draw_lasers)
	eb = _pool(4000, _tex_orb(), _bullet_mat(), pal)
	var fxpal := pal.duplicate()
	fx = _pool(1600, _tex_glow(32, 1.6), _add_mat(), fxpal)
	for i in 90:
		stars.append(Vector3(randf() * W, randf() * H, randf_range(0.3, 1.0)))

func _layer(cb: Callable) -> Node2D:
	var l: Node2D = LayerScript.new()
	l.cb = cb
	add_child(l)
	return l

func _pool(cap: int, tex: Texture2D, mat: Material, p: PackedColorArray):
	var pl = PoolScript.new()
	add_child(pl)
	pl.setup(cap, tex, mat, p)
	return pl

func _add_mat() -> Material:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m

func _bullet_mat() -> Material:
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
varying vec4 ic;
void vertex() { ic = COLOR; }
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	COLOR = vec4(mix(ic.rgb * t.g, vec3(1.0), t.r), t.a * ic.a);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

func _tex_orb() -> Texture2D:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for yy in s:
		for xx in s:
			var d := Vector2(xx + 0.5 - s / 2.0, yy + 0.5 - s / 2.0).length() / (s / 2.0)
			var core := 1.0 - smoothstep(0.34, 0.46, d)
			var g := 1.0
			var a := 1.0
			if d > 0.74 and d <= 0.84:
				g = 0.22
			elif d > 0.84:
				a = 0.4 * clampf(1.0 - (d - 0.84) / 0.16, 0.0, 1.0)
			img.set_pixel(xx, yy, Color(core, g, 0.0, a))
	return ImageTexture.create_from_image(img)

func _tex_glow(s: int, p: float) -> Texture2D:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for yy in s:
		for xx in s:
			var d := Vector2(xx + 0.5 - s / 2.0, yy + 0.5 - s / 2.0).length() / (s / 2.0)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), p)
			img.set_pixel(xx, yy, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

func _tex_item() -> Texture2D:
	var s := 24
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for yy in s:
		for xx in s:
			var u := absf(xx + 0.5 - s / 2.0) / (s / 2.0)
			var v := absf(yy + 0.5 - s / 2.0) / (s / 2.0)
			var d := u + v
			var c := Color(1, 1, 1, 0)
			if d < 0.62:
				c = Color(1, 1, 1, 1).lerp(Color(0.85, 0.85, 0.85, 1), d)
			elif d < 0.8:
				c = Color(0.25, 0.25, 0.25, 1)
			elif d < 1.0:
				c = Color(1, 1, 1, 0.5 * (1.0 - (d - 0.8) / 0.2))
			img.set_pixel(xx, yy, c)
	return ImageTexture.create_from_image(img)

# ================================================================ run control
func start_run(p_ship: int, p_diff: int, p_stage: int, p_practice: bool) -> void:
	ship = p_ship
	diff = p_diff
	practice = p_practice
	dspd = DSPD[diff]
	dden = DDEN[diff]
	score = 0
	mult = 1.0
	graze = 0
	lives = 2
	bombs = 3
	power = 4.0 if practice else 0.0
	if practice and p_stage > 1:
		power = 4.0
	continues = 0
	next_extend = 0
	over = false
	all_clear = false
	active = true
	paused = false
	start_stage(p_stage)

func start_stage(s: int) -> void:
	stage = s
	enemies.clear()
	lasers.clear()
	popups.clear()
	boss = null
	eb.clear(); ps.clear(); it.clear(); fx.clear()
	events = st.events(s)
	ev_i = 0
	tl_t = 0.0
	stage_t = 0.0
	stage_graze = 0
	stage_score0 = score
	phase = "intro"
	phase_t = 0.0
	var info: Dictionary = st.info(s)
	banner = "STAGE %d" % s
	banner2 = info.name
	banner_t = 3.0
	px = W / 2.0
	py = H - 90.0
	invuln = 2.0
	dying = 0.0
	respawn = 0.0
	bomb_t = 0.0
	if sfx:
		sfx.play_music("stage")
		sfx.play("start")

func continue_run() -> void:
	continues += 1
	over = false
	lives = 2
	bombs = 3
	score = 0 + continues  # arcade tradition: last digit counts continues
	mult = 1.0
	invuln = 3.0
	respawn = 0.0
	px = W / 2.0
	py = H - 90.0

func stage_color() -> Color:
	return st.info(stage).col

# ================================================================ helpers used by stages.gd
func aim(x: float, y: float) -> float:
	return atan2(py - y, px - x)

func fire(x: float, y: float, ang: float, spd: float, c: int, style: int = 0, r: float = 4.0) -> int:
	var s := spd * dspd
	return eb.spawn(x, y, cos(ang) * s, sin(ang) * s, r, c, style)

func ring(x: float, y: float, n: int, spd: float, off: float, c: int, style: int = 0, r: float = 4.0) -> Array:
	var out := []
	for k in n:
		var i := fire(x, y, off + TAU * k / n, spd, c, style, r)
		if i >= 0:
			out.append(i)
	return out

func fan(x: float, y: float, n: int, spread: float, ang: float, spd: float, c: int, style: int = 0, r: float = 4.0) -> Array:
	var out := []
	for k in n:
		var a := ang
		if n > 1:
			a = ang - spread / 2.0 + spread * k / (n - 1)
		var i := fire(x, y, a, spd, c, style, r)
		if i >= 0:
			out.append(i)
	return out

func cnt(base: float) -> int:
	return maxi(1, int(round(base * dden)))

func laser(x: float, y: float, ang: float, length: float, w: float, warn: float, dur: float, turn: float, c: int, follow = null) -> Dictionary:
	var l := {"x": x, "y": y, "ang": ang, "len": length, "w": w, "warn": warn, "dur": dur, "t": 0.0, "turn": turn, "c": c, "follow": follow, "ox": 0.0, "oy": 0.0}
	if follow != null:
		l.ox = x - follow.x
		l.oy = y - follow.y
	lasers.append(l)
	if sfx:
		sfx.play("laser", -6.0)
	return l

func spawn_enemy(e: Dictionary) -> void:
	enemies.append(e)

func add_score(v: float) -> void:
	score += int(v)
	if not practice:
		while next_extend < EXTENDS.size() and score >= EXTENDS[next_extend]:
			next_extend += 1
			lives = mini(lives + 1, 8)
			popup(px, py - 30, "EXTEND!", Color(0.5, 1, 0.6))
			if sfx:
				sfx.play("extend")

func popup(x: float, y: float, txt: String, c: Color) -> void:
	popups.append({"x": x, "y": y, "s": txt, "t": 0.0, "c": c})

func burst(x: float, y: float, n: int, c: int, spd: float, life: float = 0.5, size: float = 10.0, style: int = 1) -> void:
	for k in n:
		var a := randf() * TAU
		var s := randf_range(0.3, 1.0) * spd
		var i: int = fx.spawn(x, y, cos(a) * s, sin(a) * s, size * randf_range(0.6, 1.2), c, style)
		if i >= 0:
			fx.aux[i] = life * randf_range(0.6, 1.2)

func stars_from(pts: PackedVector2Array) -> void:
	for p in pts:
		var i: int = it.spawn(p.x, p.y, randf_range(-20, 20), randf_range(-60, -20), 6.0, 3, 3)
	if pts.size() > 0:
		for k in mini(pts.size(), 40):
			var p: Vector2 = pts[randi() % pts.size()]
			var i: int = fx.spawn(p.x, p.y, 0, 0, 14.0, 8, 0)
			if i >= 0:
				fx.aux[i] = 0.3

func drop(x: float, y: float, kind: int, n: int) -> void:
	for k in n:
		it.spawn(x + randf_range(-14, 14), y + randf_range(-10, 10), randf_range(-40, 40), randf_range(-150, -80), 8.0, kind, kind)

func cancel_all(make_stars: bool) -> void:
	var pts: PackedVector2Array = eb.cancel(0, 0, -1.0)
	if make_stars:
		stars_from(pts)
	lasers.clear()

func power_level() -> int:
	return mini(4, int(power))

# ================================================================ main update
func step(dt: float) -> void:
	gtime += dt
	bg_t += dt
	shake = maxf(0.0, shake - dt * 12.0)
	flash = maxf(0.0, flash - dt * 2.5)
	position = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) if shake > 0.05 else Vector2.ZERO
	if not active:
		L_bg.queue_redraw()
		return
	if paused or over:
		L_bg.queue_redraw()
		return
	stage_t += dt
	phase_t += dt
	banner_t = maxf(0.0, banner_t - dt)
	warn_t = maxf(0.0, warn_t - dt)
	_update_player(dt)
	_update_timeline(dt)
	_update_enemies(dt)
	if boss != null:
		st.boss_update(boss, dt)
		_check_boss()
	_update_lasers(dt)
	var alive := respawn <= 0.0 and dying <= 0.0
	var can_hit := alive and invuln <= 0.0 and not god
	eb.update_bullets(dt, px, py, can_hit, alive and invuln <= 0.0, HIT_R, GRAZE_R, W, H)
	if eb.hit:
		_get_hit()
	if eb.graze_n > 0:
		graze += eb.graze_n
		stage_graze += eb.graze_n
		mult = minf(8.0, mult + 0.012 * eb.graze_n)
		mult_idle = 0.0
		add_score(500.0 * mult * eb.graze_n)
		var i: int = fx.spawn(eb.gx, eb.gy, (eb.gx - px) * 3.0, (eb.gy - py) * 3.0, 12.0, 8, 1)
		if i >= 0:
			fx.aux[i] = 0.25
		if sfx:
			sfx.play("graze", -6.0)
	if eb.splits.size() > 0:
		for sp in eb.splits:
			st.on_split(sp)
		eb.splits.clear()
	_update_shots(dt)
	_update_items(dt)
	fx.update_fx(dt)
	for p in popups:
		p.t += dt
		p.y -= 22.0 * dt
	popups = popups.filter(func(p): return p.t < 1.2)
	mult_idle += dt
	if mult_idle > 2.5:
		mult = maxf(1.0, mult - 0.06 * dt)
	if phase == "clear":
		if phase_t > 4.5:
			_next_stage()
	L_bg.queue_redraw()
	L_ent.queue_redraw()
	L_ply.queue_redraw()
	L_las.queue_redraw()

func _update_player(dt: float) -> void:
	if dying > 0.0:
		dying -= dt
		if bomb_req and bombs > 0:
			dying = 0.0
			_bomb()
			popup(px, py - 24, "DEATHBOMB!", Color(1, 0.9, 0.4))
		elif dying <= 0.0:
			_die()
		bomb_req = false
		return
	if respawn > 0.0:
		respawn -= dt
		py = lerpf(py, H - 90.0, dt * 4.0)
		bomb_req = false
		if respawn <= 0.0:
			invuln = 3.0
		return
	invuln = maxf(0.0, invuln - dt)
	var sd: Dictionary = SHIPS[ship]
	var spd: float = sd.fspeed if focus else sd.speed
	var mv := move_vec
	if mv.length() > 1.0:
		mv = mv.normalized()
	px += mv.x * spd * dt + touch_delta.x
	py += mv.y * spd * dt + touch_delta.y
	touch_delta = Vector2.ZERO
	px = clampf(px, 8.0, W - 8.0)
	py = clampf(py, 40.0, H - 16.0)
	if bomb_req and bombs > 0 and bomb_t <= 0.0:
		_bomb()
	bomb_req = false
	if bomb_t > 0.0:
		bomb_t -= dt
		_bomb_tick(dt)
	if shooting:
		_fire_player(dt)
	else:
		beam_on = false
	trail += dt
	if trail > 0.03:
		trail = 0.0
		var i: int = fx.spawn(px + randf_range(-3, 3), py + 12, randf_range(-10, 10), 160, 9.0, 4 if ship == 0 else (7 if ship == 1 else 3), 0)
		if i >= 0:
			fx.aux[i] = 0.25

func option_pos(k: int, n: int) -> Vector2:
	if n <= 0:
		return Vector2(px, py)
	var spread := 16.0 if focus else 34.0
	var side := -1.0 if k % 2 == 0 else 1.0
	var tier := k / 2
	var ox := side * (spread * 0.55 + tier * spread * 0.55)
	var oy := (6.0 if focus else 10.0) + tier * 8.0 - (12.0 if focus else 0.0)
	return Vector2(px + ox, py + oy + sin(gtime * 4.0 + k) * 2.0)

func _fire_player(dt: float) -> void:
	shot_cd -= dt
	missile_cd -= dt
	var lv := power_level()
	beam_on = false
	if ship == 0:
		if shot_cd <= 0.0:
			shot_cd = 0.065
			for o in [-5.0, 5.0]:
				_pshot(px + o, py - 12, -PI / 2.0, 900.0, 1.0, 0, 0)
			var spread := 0.035 if focus else 0.16
			for k in range(1, lv + 1):
				for s in [-1.0, 1.0]:
					var op := option_pos(k * 2 - (1 if s < 0 else 0) - 1, lv * 2)
					_pshot(op.x, op.y - 6, -PI / 2.0 + s * spread * k, 850.0, 0.75, 0, 0)
			if sfx:
				sfx.play("shot", -14.0)
	elif ship == 1:
		if shot_cd <= 0.0:
			shot_cd = 0.055
			for o in [-4.0, 4.0]:
				_pshot(px + o, py - 12, -PI / 2.0, 1000.0, 1.0, 1, 2)
			if not focus:
				for k in lv * 2:
					var op := option_pos(k, lv * 2)
					_pshot(op.x, op.y - 6, -PI / 2.0, 1000.0, 0.9, 1, 2)
			if sfx:
				sfx.play("shot", -14.0, 1.2)
		if focus:
			beam_on = true
			_beam(dt, 60.0 + lv * 20.0, 7.0 + lv * 2.0)
	else:
		if shot_cd <= 0.0:
			shot_cd = 0.075
			var sp := 0.05 if focus else 0.12
			for s in [-1.0, 1.0]:
				_pshot(px + s * 5.0, py - 12, -PI / 2.0 + s * sp * 0.3, 900.0, 1.0, 2, 0)
			if sfx:
				sfx.play("shot", -14.0, 0.85)
		if missile_cd <= 0.0 and lv >= 0:
			missile_cd = 0.15 if focus else 0.22
			var nm := lv + 1
			for k in nm:
				var op := option_pos(k, nm)
				var a := -PI / 2.0 + (randf_range(-0.2, 0.2) if focus else (-0.9 if k % 2 == 0 else 0.9))
				_pshot(op.x, op.y, a, 260.0, 2.4, 3, 1)

func _pshot(x: float, y: float, a: float, spd: float, dmg: float, c: int, style: int) -> void:
	var i: int = ps.spawn(x, y, cos(a) * spd, sin(a) * spd, 3.0 if style != 1 else 4.0, c, style)
	if i >= 0:
		ps.aux[i] = dmg * dmg_mult

func _targets() -> Array:
	var out := []
	for e in enemies:
		if e.delay <= 0.0 and e.y > -8.0 and e.y < H and e.hp > 0:
			out.append(e)
	if boss != null and boss.vuln:
		out.append(boss)
	return out

func _beam(dt: float, dps: float, w: float) -> void:
	var best = null
	var by := -20.0
	for e in _targets():
		if absf(e.x - px) < e.r + w and e.y < py and e.y > by:
			by = e.y
			best = e
	beam_end = by + (best.r * 0.5 if best != null else 0.0)
	if best != null:
		best.hp -= dps * dt * dmg_mult
		best.flash = 0.05
		if randf() < 0.5:
			var i: int = fx.spawn(px + randf_range(-w, w), beam_end, randf_range(-90, 90), randf_range(-40, 60), 10.0, 7, 1)
			if i >= 0:
				fx.aux[i] = 0.25

func _update_shots(dt: float) -> void:
	var hits: PackedVector2Array = ps.update_shots(dt, _targets(), H, W)
	for p in hits:
		if randf() < 0.35:
			var i: int = fx.spawn(p.x, p.y, randf_range(-60, 60), randf_range(-120, -20), 8.0, 4 if ship == 0 else (7 if ship == 1 else 3), 1)
			if i >= 0:
				fx.aux[i] = 0.2
	if hits.size() > 0 and sfx:
		sfx.play("hit", -16.0)
	# deaths
	var keep := []
	for e in enemies:
		if e.hp <= 0:
			_kill_enemy(e)
		elif e.get("gone", false):
			pass
		else:
			keep.append(e)
	enemies = keep

func _kill_enemy(e: Dictionary) -> void:
	add_score(float(e.score) * mult)
	mult = minf(8.0, mult + 0.01)
	mult_idle = 0.0
	burst(e.x, e.y, 10 + int(e.r), e.ci, 220.0, 0.5, 12.0)
	burst(e.x, e.y, 4, 8, 60.0, 0.35, 26.0, 0)
	if e.r > 16:
		shake = maxf(shake, 4.0)
	match e.drop:
		"p": drop(e.x, e.y, 0, 1)
		"P": drop(e.x, e.y, 1, 1)
		"pt": drop(e.x, e.y, 2, 2)
		"mix":
			drop(e.x, e.y, 0, 3)
			drop(e.x, e.y, 2, 3)
		"big":
			drop(e.x, e.y, 1, 2)
			drop(e.x, e.y, 2, 6)
	if diff >= 3 and e.r <= 12:
		fire(e.x, e.y, aim(e.x, e.y), 120.0, e.ci, 3, 3.5)
	if sfx:
		sfx.play("pop", -6.0 if e.r > 16 else -10.0)

func _update_items(dt: float) -> void:
	var attract := py < 190.0 or bomb_t > 0.0 or phase == "clear"
	it.update_items(dt, px, py, attract, 70.0 if focus else 40.0, H)
	var g: PackedInt32Array = it.got
	if g[0] + g[1] + g[2] + g[3] + g[4] == 0:
		return
	var before := power_level()
	if g[0] > 0 or g[1] > 0:
		if power >= 4.0:
			add_score((g[0] * 1000 + g[1] * 5000) * mult)
		power = minf(4.0, power + g[0] * 0.05 + g[1] * 0.5)
	if g[2] > 0:
		var v := 10000.0 if py < 190.0 else 4000.0
		add_score(v * mult * g[2])
	if g[3] > 0:
		add_score(200.0 * mult * g[3])
		mult = minf(8.0, mult + 0.0015 * g[3])
	if g[4] > 0:
		bombs = mini(6, bombs + g[4])
	if power_level() > before:
		popup(px, py - 26, "POWER UP" if power < 4.0 else "MAX POWER", Color(1, 0.5, 0.5))
		if sfx:
			sfx.play("power")
	elif sfx:
		sfx.play("item", -12.0)

# ---------------------------------------------------------------- bombs & death
func _bomb() -> void:
	bombs -= 1
	bomb_len = 2.6
	bomb_t = bomb_len
	invuln = bomb_len + 1.0
	mult = maxf(1.0, mult - 0.5)
	phase_clean = false
	shake = 7.0
	flash = 0.6
	flash_col = SHIPS[ship].col
	cancel_all(true)
	if sfx:
		sfx.play("bomb")

func _bomb_tick(dt: float) -> void:
	var k := 1.0 - bomb_t / bomb_len
	var dps := 900.0
	if ship == 0:
		var rad := fmod(k * 2.0, 1.0) * 720.0
		stars_from(eb.cancel(px, py, rad))
		for e in _targets():
			if Vector2(e.x - px, e.y - py).length() < rad + e.r:
				_bomb_dmg(e, dps * dt)
	elif ship == 1:
		stars_from(eb.cancel_box(px - 46, -20, px + 46, py))
		for e in _targets():
			if absf(e.x - px) < 46 + e.r and e.y < py:
				_bomb_dmg(e, dps * 1.4 * dt)
	else:
		stars_from(eb.cancel(0, 0, -1.0))
		for e in _targets():
			_bomb_dmg(e, dps * 0.8 * dt)
	lasers.clear()
	if randf() < 0.6:
		burst(px + randf_range(-150, 150), py - randf_range(0, 500), 3, 4 if ship == 0 else (7 if ship == 1 else 3), 140, 0.5, 14)

func _bomb_dmg(e: Dictionary, v: float) -> void:
	if is_same(e, boss):
		v *= 0.35
	e.hp -= v * dmg_mult
	e.flash = 0.05

func _get_hit() -> void:
	if dying > 0.0:
		return
	dying = 0.13  # deathbomb window
	if sfx:
		sfx.play("die", -4.0)

func _die() -> void:
	burst(px, py, 50, 8, 320.0, 0.8, 14.0)
	burst(px, py, 30, 4 if ship == 0 else (7 if ship == 1 else 3), 220.0, 0.9, 16.0)
	shake = 9.0
	flash = 0.8
	flash_col = Color(1, 0.3, 0.4)
	phase_clean = false
	var lost := minf(power, 1.0)
	power -= lost
	for k in 5:
		it.spawn(px + randf_range(-30, 30), py - 10, randf_range(-90, 90), randf_range(-260, -160), 8.0, 0 if k < 4 else 1, 0 if k < 4 else 1)
	mult = maxf(1.0, mult * 0.5)
	eb.cancel(0, 0, -1.0)
	lasers.clear()
	lives -= 1
	bombs = maxi(bombs, 3)
	if sfx:
		sfx.play("boom")
	if lives < 0:
		lives = 0
		if practice:
			lives = 0
			bombs = 3
			respawn = 1.0
			py = H + 40
			popup(W / 2, H / 2, "PRACTICE: RESPAWN", Color(1, 1, 1))
			lives = 0
			return
		over = true
		if main:
			main.on_game_over()
		return
	respawn = 1.0
	py = H + 40.0

# ---------------------------------------------------------------- timeline & enemies
func _update_timeline(dt: float) -> void:
	if phase == "intro" and phase_t > 1.5:
		phase = "play"
		phase_t = 0.0
	if phase != "play" or boss != null:
		return
	tl_t += dt
	while ev_i < events.size() and events[ev_i][0] <= tl_t:
		var ev: Array = events[ev_i]
		ev_i += 1
		if ev[1] == "midboss" or ev[1] == "boss":
			boss = st.make_boss(stage, ev[1] == "midboss")
			warn_t = 0.0
			if ev[1] == "boss":
				warn_t = 2.5
				if sfx:
					sfx.play("warn", -4.0)
					sfx.play_music("boss")
			break
		else:
			st.spawn_wave(ev[1], ev[2])

func _update_enemies(dt: float) -> void:
	for e in enemies:
		if e.delay > 0.0:
			e.delay -= dt
			continue
		e.t += dt
		e.flash = maxf(0.0, e.flash - dt)
		st.enemy_update(e, dt)
		if e.t > 1.0 and (e.y > H + 40 or e.y < -80 or e.x < -60 or e.x > W + 60):
			e.gone = true
		if e.hp > 0 and absf(e.x - px) < e.r * 0.6 and absf(e.y - py) < e.r * 0.6 and invuln <= 0.0 and respawn <= 0.0 and dying <= 0.0 and not god:
			_get_hit()
	var keep := []
	for e in enemies:
		if not e.get("gone", false):
			keep.append(e)
	enemies = keep

func _check_boss() -> void:
	var b: Dictionary = boss
	b.flash = maxf(0.0, b.flash - get_process_delta_time())
	if b.state != "fight":
		return
	var ph: Dictionary = b.phases[b.pi]
	var timeout: bool = b.pt >= ph.time
	if b.hp <= 0 or timeout:
		var last: bool = b.pi >= b.phases.size() - 1
		cancel_all(true)
		if not timeout:
			var bonus := int((800000.0 + 400000.0 * stage) * (0.4 + 0.6 * clampf(1.0 - b.pt / ph.time, 0.0, 1.0)))
			if phase_clean:
				bonus *= 2
			add_score(bonus * mult)
			popup(W / 2, 170, ("PERFECT BREAK  +" if phase_clean else "PHASE BREAK  +") + main.fmt(int(bonus * mult)), Color(1, 0.95, 0.5))
		else:
			popup(W / 2, 170, "TIME OUT", Color(0.8, 0.8, 1))
		if sfx:
			sfx.play("break")
		shake = 5.0
		flash = 0.35
		flash_col = b.col
		burst(b.x, b.y, 40, b.ci, 300.0, 0.8, 14.0)
		drop(b.x, b.y, 1 if power < 4.0 else 2, 3)
		drop(b.x, b.y, 2, 8)
		if last:
			_boss_dead()
		else:
			b.pi += 1
			b.state = "trans"
			b.st = 0.0
			b.pt = 0.0
			b.hp = b.phases[b.pi].hp
			b.maxhp = b.hp
			b.vuln = false
			b.acc = {}
			phase_clean = true

func _boss_dead() -> void:
	var b: Dictionary = boss
	burst(b.x, b.y, 120, b.ci, 420.0, 1.2, 18.0)
	burst(b.x, b.y, 60, 8, 260.0, 1.0, 26.0)
	shake = 14.0
	flash = 1.0
	flash_col = Color.WHITE
	drop(b.x, b.y, 2, 20)
	if not b.mid:
		drop(b.x, b.y, 4, 1)
	if sfx:
		sfx.play("boom")
	boss = null
	if not b.mid:
		phase = "clear"
		phase_t = 0.0
		clear_bonus = stage * 1000000 + stage_graze * 2000
		add_score(clear_bonus * mult)
		if sfx:
			sfx.play_music("")
	else:
		if sfx:
			sfx.play_music("stage")

func _next_stage() -> void:
	if practice:
		active = false
		if main:
			main.on_practice_clear()
		return
	if stage >= 5:
		all_clear = true
		active = false
		add_score(lives * 5000000 + bombs * 1000000)
		if main:
			main.on_all_clear()
		return
	start_stage(stage + 1)

func _update_lasers(dt: float) -> void:
	var keep := []
	var vulnerable := invuln <= 0.0 and respawn <= 0.0 and dying <= 0.0 and not god
	for l in lasers:
		l.t += dt
		l.ang += l.turn * dt
		if l.follow != null:
			l.x = l.follow.x + l.ox
			l.y = l.follow.y + l.oy
		if l.t > l.warn + l.dur + 0.25:
			continue
		keep.append(l)
		if l.t > l.warn and l.t < l.warn + l.dur and vulnerable:
			var d := Vector2(cos(l.ang), sin(l.ang))
			var rel := Vector2(px - l.x, py - l.y)
			var along := clampf(rel.dot(d), 0.0, l.len)
			var dist := (rel - d * along).length()
			if dist < l.w * 0.32 + HIT_R:
				_get_hit()
			elif dist < l.w * 0.5 + GRAZE_R and randf() < 0.3:
				graze += 1
				stage_graze += 1
				add_score(300.0 * mult)
	lasers = keep

# ================================================================ drawing
func _draw_bg(c: CanvasItem) -> void:
	var col := stage_color() if active else Color(0.6, 0.3, 1.0)
	c.draw_rect(Rect2(0, 0, W, H), Color(0.015, 0.008, 0.04))
	# perspective neon grid
	var hor := 150.0
	var gcol := Color(col.r, col.g, col.b, 0.13)
	for k in 14:
		var f := fmod(k / 14.0 + bg_t * 0.08, 1.0)
		var yy := hor + pow(f, 2.2) * (H - hor + 80)
		c.draw_line(Vector2(0, yy), Vector2(W, yy), Color(gcol, gcol.a * f * 1.6), 1.0)
	for k in range(-8, 9):
		c.draw_line(Vector2(W / 2 + k * 14, hor), Vector2(W / 2 + k * 110, H + 40), gcol, 1.0)
	var s := stage if active else 0
	match s:
		1:
			for k in 3:
				var rr := 60.0 + k * 50.0 + sin(bg_t + k) * 6.0
				_poly(c, Vector2(W / 2, 90), rr, 6, bg_t * 0.2 * (1 if k % 2 == 0 else -1), Color(col, 0.08), 1.5)
		2:
			for k in 5:
				var cx := fmod(k * 97.0 + bg_t * 14.0, W + 80) - 40
				_poly(c, Vector2(cx, 60 + k * 30), 30 + k * 6, 3, bg_t * 0.4 + k, Color(col, 0.09), 1.5)
		3:
			for k in 4:
				var pts := PackedVector2Array()
				for xx in 25:
					pts.append(Vector2(xx * 15.0, 60 + k * 26 + sin(xx * 0.5 + bg_t * (1.0 + k * 0.3)) * 10))
				c.draw_polyline(pts, Color(col, 0.1), 1.5)
		4:
			c.draw_circle(Vector2(W / 2, hor), 70, Color(col, 0.07))
			for k in 6:
				c.draw_line(Vector2(W / 2 - 70, hor - 60 + k * 12), Vector2(W / 2 + 70, hor - 60 + k * 12), Color(0.015, 0.008, 0.04), 4)
		5:
			for k in 16:
				var a := k * TAU / 16 + bg_t * 0.05
				c.draw_line(Vector2(W / 2, 100), Vector2(W / 2, 100) + Vector2(cos(a), sin(a)) * 500, Color(col, 0.05), 2)
	# starfield
	for i in stars.size():
		var sv: Vector3 = stars[i]
		var yy := fmod(sv.y + bg_t * 60.0 * sv.z * sv.z * 2.0, H)
		c.draw_rect(Rect2(sv.x, yy, 1.5 * sv.z, 1.5 * sv.z + sv.z * 3.0), Color(0.7, 0.8, 1.0, 0.25 + 0.6 * sv.z))

func _poly(c: CanvasItem, ctr: Vector2, rad: float, n: int, rot: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for k in n + 1:
		var a := rot + TAU * k / n
		pts.append(ctr + Vector2(cos(a), sin(a)) * rad)
	c.draw_polyline(pts, col, w)

func neon(c: CanvasItem, pts: PackedVector2Array, col: Color, w: float = 2.0) -> void:
	c.draw_polyline(pts, Color(col, 0.18), w * 4.0)
	c.draw_polyline(pts, Color(col, 0.45), w * 2.0)
	c.draw_polyline(pts, col.lerp(Color.WHITE, 0.35), w)

func shape(ctr: Vector2, verts: Array, sc: float, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cr := cos(rot)
	var sr := sin(rot)
	for v in verts:
		var p := Vector2(v[0], v[1]) * sc
		pts.append(ctr + Vector2(p.x * cr - p.y * sr, p.x * sr + p.y * cr))
	pts.append(pts[0])
	return pts

func _draw_ents(c: CanvasItem) -> void:
	for e in enemies:
		if e.delay > 0.0:
			continue
		st.draw_enemy(c, e)
	if boss != null:
		st.draw_boss(c, boss)

func ship_points(idx: int, ctr: Vector2, sc: float) -> PackedVector2Array:
	match idx:
		0:
			return shape(ctr, [[0, -14], [5, -4], [13, 9], [4, 6], [0, 11], [-4, 6], [-13, 9], [-5, -4]], sc, 0)
		1:
			return shape(ctr, [[0, -17], [3, -6], [9, 2], [9, 11], [3, 7], [0, 12], [-3, 7], [-9, 11], [-9, 2], [-3, -6]], sc, 0)
		_:
			return shape(ctr, [[0, -12], [7, -6], [12, 4], [7, 11], [0, 7], [-7, 11], [-12, 4], [-7, -6]], sc, 0)

func draw_ship(c: CanvasItem, idx: int, ctr: Vector2, sc: float) -> void:
	var col: Color = SHIPS[idx].col
	var pts := ship_points(idx, ctr, sc)
	c.draw_colored_polygon(pts, Color(col.r * 0.15, col.g * 0.15, col.b * 0.2, 0.9))
	neon(c, pts, col, 1.6 * sc)
	c.draw_circle(ctr + Vector2(0, 13 * sc), (3.0 + sin(gtime * 30.0)) * sc, Color(1, 0.85, 0.5, 0.8))

func _draw_player(c: CanvasItem) -> void:
	if not active:
		return
	if phase == "clear" or over:
		pass
	if respawn > 0.0 and py > H:
		return
	var sd: Dictionary = SHIPS[ship]
	var col: Color = sd.col
	# beam
	if beam_on:
		var w := 7.0 + power_level() * 2.0
		var top := beam_end
		c.draw_rect(Rect2(px - w * 1.8, top, w * 3.6, py - top - 10), Color(col, 0.12))
		c.draw_rect(Rect2(px - w * 0.9, top, w * 1.8, py - top - 10), Color(col, 0.35))
		c.draw_rect(Rect2(px - w * 0.3, top, w * 0.6, py - top - 10), Color(1, 1, 1, 0.85))
		c.draw_circle(Vector2(px, top), w * 1.4, Color(1, 1, 1, 0.5))
	# bomb visuals
	if bomb_t > 0.0:
		var k := 1.0 - bomb_t / bomb_len
		var a := minf(1.0, bomb_t)
		if ship == 0:
			for j in 2:
				var rad := fmod(k * 2.0 + j * 0.5, 1.0) * 720.0
				c.draw_arc(Vector2(px, py), rad, 0, TAU, 64, Color(col, 0.5 * a), 10.0)
				c.draw_arc(Vector2(px, py), rad, 0, TAU, 64, Color(1, 1, 1, 0.7 * a), 3.0)
		elif ship == 1:
			var ww := 46.0 * (0.8 + 0.2 * sin(gtime * 40.0))
			c.draw_rect(Rect2(px - ww, 0, ww * 2, py), Color(col, 0.25 * a))
			c.draw_rect(Rect2(px - ww * 0.5, 0, ww, py), Color(col, 0.45 * a))
			c.draw_rect(Rect2(px - ww * 0.15, 0, ww * 0.3, py), Color(1, 1, 1, 0.8 * a))
		else:
			for j in 14:
				var ang := j * TAU / 14 + gtime * 2.5
				var rad := 30.0 + k * 520.0 * (0.6 + 0.4 * sin(j * 1.7))
				var p := Vector2(px, py) + Vector2(cos(ang), sin(ang)) * rad
				c.draw_circle(p, 16, Color(col, 0.3 * a))
				c.draw_circle(p, 7, Color(1, 1, 1, 0.8 * a))
	if dying > 0.0 or (invuln > 0.0 and fmod(gtime, 0.12) < 0.05 and bomb_t <= 0.0):
		return
	# options
	var lv := power_level()
	var no := lv * 2 if ship != 2 else lv + 1
	for k in no:
		var op := option_pos(k, no)
		c.draw_circle(op, 5.0, Color(col, 0.3))
		_poly(c, op, 4.0, 4, gtime * 5.0 + k, col.lerp(Color.WHITE, 0.4), 1.5)
	draw_ship(c, ship, Vector2(px, py), 1.0)
	if focus:
		_poly(c, Vector2(px, py), 15.0, 6, gtime * 2.0, Color(1, 1, 1, 0.35), 1.0)
		c.draw_circle(Vector2(px, py), HIT_R + 1.5, Color(col, 0.9))
		c.draw_circle(Vector2(px, py), HIT_R, Color.WHITE)

func _draw_lasers(c: CanvasItem) -> void:
	for l in lasers:
		var d := Vector2(cos(l.ang), sin(l.ang))
		var a := Vector2(l.x, l.y)
		var b = a + d * l.len
		var col: Color = pal[l.c]
		if l.t < l.warn:
			var blink := 0.35 + 0.35 * sin(l.t * 30.0)
			c.draw_line(a, b, Color(col, blink), 1.5)
		else:
			var k := 1.0
			if l.t > l.warn + l.dur:
				k = maxf(0.0, 1.0 - (l.t - l.warn - l.dur) / 0.25)
			var grow := minf(1.0, (l.t - l.warn) / 0.12)
			var w: float = l.w * grow * k
			c.draw_line(a, b, Color(col, 0.25), w * 1.6)
			c.draw_line(a, b, Color(col, 0.7), w)
			c.draw_line(a, b, Color(1, 1, 1, 0.95), w * 0.4)
			c.draw_circle(a, w * 0.9, Color(1, 1, 1, 0.6 * k))
