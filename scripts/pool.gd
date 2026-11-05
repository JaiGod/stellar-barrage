extends MultiMeshInstance2D
## Pooled sprites rendered with ONE MultiMesh draw call.
## Data lives in dense packed arrays (struct-of-arrays). Dead entries are
## swap-removed, so loops only touch live elements. All hot loops live in
## this script so the packed arrays are modified in place (no copies).

const STRIDE := 12  # 8 floats Transform2D + 4 floats Color

# bullet flags
const F_GRAZED := 1
const F_REAIM := 2
const F_OFFOK := 4
const F_BOUNCE := 8
const F_SPLIT := 16
const F_HOME := 32

var cap := 0
var n := 0
var x := PackedFloat32Array()
var y := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
var acc := PackedFloat32Array()
var turn := PackedFloat32Array()
var r := PackedFloat32Array()
var t := PackedFloat32Array()
var aux := PackedFloat32Array()
var aux2 := PackedFloat32Array()
var col := PackedInt32Array()
var style := PackedInt32Array()
var flags := PackedInt32Array()
var buf := PackedFloat32Array()
var pal := PackedColorArray()

# results of the last update
var hit := false
var graze_n := 0
var gx := 0.0
var gy := 0.0
var splits: Array = []
var got := PackedInt32Array([0, 0, 0, 0, 0])

func setup(capacity: int, tex: Texture2D, mat: Material, palette: PackedColorArray) -> void:
	cap = capacity
	pal = palette
	x.resize(cap); y.resize(cap); vx.resize(cap); vy.resize(cap)
	acc.resize(cap); turn.resize(cap); r.resize(cap); t.resize(cap)
	aux.resize(cap); aux2.resize(cap); col.resize(cap); style.resize(cap); flags.resize(cap)
	buf.resize(cap * STRIDE)
	buf.fill(0.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = false
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = cap
	mm.visible_instance_count = 0
	multimesh = mm
	texture = tex
	material = mat

func spawn(px: float, py: float, pvx: float, pvy: float, pr: float, pc: int, pstyle: int) -> int:
	if n >= cap:
		return -1
	var i := n
	x[i] = px; y[i] = py; vx[i] = pvx; vy[i] = pvy
	acc[i] = 0.0; turn[i] = 0.0; r[i] = pr; t[i] = 0.0
	aux[i] = 0.0; aux2[i] = 0.0; col[i] = pc; style[i] = pstyle; flags[i] = 0
	n += 1
	return i

func set_motion(i: int, pacc: float, pturn: float) -> void:
	acc[i] = pacc
	turn[i] = pturn

func set_aux(i: int, pflags: int, a1: float, a2: float) -> void:
	flags[i] = flags[i] | pflags
	aux[i] = a1
	aux2[i] = a2

## Remove element i by moving the last element into its slot (buffer slot too).
func kill(i: int) -> void:
	var l := n - 1
	if i != l:
		x[i] = x[l]; y[i] = y[l]; vx[i] = vx[l]; vy[i] = vy[l]
		acc[i] = acc[l]; turn[i] = turn[l]; r[i] = r[l]; t[i] = t[l]
		aux[i] = aux[l]; aux2[i] = aux2[l]; col[i] = col[l]; style[i] = style[l]; flags[i] = flags[l]
		var o := i * STRIDE
		var ol := l * STRIDE
		for k in STRIDE:
			buf[o + k] = buf[ol + k]
	n = l

func commit() -> void:
	multimesh.buffer = buf
	multimesh.visible_instance_count = n

func clear() -> void:
	n = 0
	splits.clear()
	if multimesh:
		multimesh.visible_instance_count = 0

func _put(i: int, px: float, py: float, c: float, s: float, sx: float, sy: float, cl: Color, alpha: float) -> void:
	var o := i * STRIDE
	buf[o] = c * sx
	buf[o + 1] = -s * sy
	buf[o + 2] = 0.0
	buf[o + 3] = px
	buf[o + 4] = s * sx
	buf[o + 5] = c * sy
	buf[o + 6] = 0.0
	buf[o + 7] = py
	buf[o + 8] = cl.r
	buf[o + 9] = cl.g
	buf[o + 10] = cl.b
	buf[o + 11] = cl.a * alpha

# ---------------------------------------------------------------- enemy bullets
## Moves every enemy bullet, tests player hit + graze, writes render buffer.
func update_bullets(dt: float, px: float, py: float, can_hit: bool, can_graze: bool, hit_r: float, graze_r: float, w: float, h: float) -> void:
	hit = false
	graze_n = 0
	var i := n - 1
	while i >= 0:
		var tt := t[i] + dt
		t[i] = tt
		var bvx := vx[i]
		var bvy := vy[i]
		var fl := flags[i]
		var a := acc[i]
		var tr := turn[i]
		var bx := x[i]
		var by := y[i]
		if fl & F_SPLIT and tt >= aux[i]:
			splits.append([bx, by, int(aux2[i]), col[i], atan2(bvy, bvx)])
			kill(i)
			i -= 1
			continue
		if a != 0.0 or tr != 0.0:
			var sp := sqrt(bvx * bvx + bvy * bvy)
			var an := atan2(bvy, bvx)
			sp += a * dt
			if sp < 0.01:
				sp = 0.01
				acc[i] = 0.0
			elif sp > 420.0:
				sp = 420.0
			an += tr * dt
			bvx = cos(an) * sp
			bvy = sin(an) * sp
			vx[i] = bvx
			vy[i] = bvy
		if fl & F_REAIM and tt >= aux[i]:
			var an2 := atan2(py - by, px - bx)
			bvx = cos(an2) * aux2[i]
			bvy = sin(an2) * aux2[i]
			vx[i] = bvx
			vy[i] = bvy
			acc[i] = 0.0
			turn[i] = 0.0
			fl &= ~F_REAIM
			flags[i] = fl
		bx += bvx * dt
		by += bvy * dt
		if fl & F_BOUNCE:
			if bx < 0.0 or bx > w:
				bvx = -bvx
				vx[i] = bvx
				bx = clampf(bx, 0.0, w)
				fl &= ~F_BOUNCE
				flags[i] = fl
			elif by < 0.0 and bvy < 0.0:
				bvy = -bvy
				vy[i] = bvy
				fl &= ~F_BOUNCE
				flags[i] = fl
		x[i] = bx
		y[i] = by
		var br := r[i]
		var m := 20.0 + br * 2.0
		var top := -m
		if fl & F_OFFOK and tt < 5.0:
			top = -160.0
		if bx < -m or bx > w + m or by < top or by > h + m:
			kill(i)
			i -= 1
			continue
		var dx := bx - px
		var dy := by - py
		var d2 := dx * dx + dy * dy
		if can_hit:
			var rr := br * 0.72 + hit_r
			if d2 < rr * rr:
				hit = true
				kill(i)
				i -= 1
				continue
		if can_graze and (fl & F_GRAZED) == 0:
			var gr := br + graze_r
			if d2 < gr * gr:
				flags[i] = fl | F_GRAZED
				graze_n += 1
				gx = bx
				gy = by
		var st := style[i]
		var c := 1.0
		var s := 0.0
		var sx := br * 3.0
		var sy := sx
		if st == 1:
			var spd := sqrt(bvx * bvx + bvy * bvy)
			if spd > 0.001:
				c = bvx / spd
				s = bvy / spd
			sx = br * 4.4
			sy = br * 2.3
		elif st == 2:
			sx = br * 2.7
			sy = sx
		if tt < 0.12:
			var k := 2.2 - tt * 10.0
			sx *= k
			sy *= k
		_put(i, bx, by, c, s, sx, sy, pal[col[i]], minf(1.0, 0.35 + tt * 8.0))
		i -= 1
	commit()

## Removes all bullets (or those within rad of cx,cy). Returns their positions.
func cancel(cx: float, cy: float, rad: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var r2 := rad * rad
	var i := n - 1
	while i >= 0:
		var dx := x[i] - cx
		var dy := y[i] - cy
		if rad < 0.0 or dx * dx + dy * dy < r2:
			out.append(Vector2(x[i], y[i]))
			kill(i)
		i -= 1
	commit()
	return out

## Removes bullets inside an axis-aligned box.
func cancel_box(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i := n - 1
	while i >= 0:
		if x[i] > x0 and x[i] < x1 and y[i] > y0 and y[i] < y1:
			out.append(Vector2(x[i], y[i]))
			kill(i)
		i -= 1
	return out

# ---------------------------------------------------------------- player shots
## targets: Array of Dictionary {x,y,r,hp,flash}. Returns hit spark positions.
func update_shots(dt: float, targets: Array, h: float, w: float) -> PackedVector2Array:
	var hits := PackedVector2Array()
	var nt := targets.size()
	var tx := PackedFloat32Array()
	var ty := PackedFloat32Array()
	var trr := PackedFloat32Array()
	tx.resize(nt); ty.resize(nt); trr.resize(nt)
	for j in nt:
		var e: Dictionary = targets[j]
		tx[j] = e.x
		ty[j] = e.y
		trr[j] = e.r
	var i := n - 1
	while i >= 0:
		var bx := x[i]
		var by := y[i]
		var bvx := vx[i]
		var bvy := vy[i]
		t[i] += dt
		if style[i] == 1 and nt > 0:
			# homing missile: steer toward nearest target
			var best := -1
			var bd := 1e12
			for j in nt:
				var ddx := tx[j] - bx
				var ddy := ty[j] - by
				var dd := ddx * ddx + ddy * ddy
				if dd < bd:
					bd = dd
					best = j
			if best >= 0:
				var want := atan2(ty[best] - by, tx[best] - bx)
				var cur := atan2(bvy, bvx)
				var diff := wrapf(want - cur, -PI, PI)
				cur += clampf(diff, -9.0 * dt, 9.0 * dt)
				var sp := minf(sqrt(bvx * bvx + bvy * bvy) + 600.0 * dt, 620.0)
				bvx = cos(cur) * sp
				bvy = sin(cur) * sp
				vx[i] = bvx
				vy[i] = bvy
		bx += bvx * dt
		by += bvy * dt
		x[i] = bx
		y[i] = by
		if by < -30.0 or by > h + 30.0 or bx < -30.0 or bx > w + 30.0 or t[i] > 3.0:
			kill(i)
			i -= 1
			continue
		var br := r[i]
		var done := false
		for j in nt:
			var ddx := tx[j] - bx
			var ddy := ty[j] - by
			var rr := trr[j] + br
			if ddx * ddx + ddy * ddy < rr * rr:
				var e: Dictionary = targets[j]
				e.hp -= aux[i]
				e.flash = 0.06
				hits.append(Vector2(bx, by))
				done = true
				break
		if done:
			kill(i)
			i -= 1
			continue
		var spd := sqrt(bvx * bvx + bvy * bvy)
		var c := 0.0
		var s := -1.0
		if spd > 0.001:
			c = bvx / spd
			s = bvy / spd
		var st := style[i]
		var sx := 22.0 if st == 0 else (16.0 if st == 1 else 30.0)
		var sy := 8.0 if st == 0 else (11.0 if st == 1 else 6.0)
		_put(i, bx, by, c, s, sx, sy, pal[col[i]], 0.9)
		i -= 1
	commit()
	return hits

# ---------------------------------------------------------------- sparks
func update_fx(dt: float) -> void:
	var i := n - 1
	var drag := pow(0.04, dt)
	while i >= 0:
		var tt := t[i] + dt
		t[i] = tt
		var life := aux[i]
		if tt >= life:
			kill(i)
			i -= 1
			continue
		var bvx := vx[i] * drag
		var bvy := vy[i] * drag + acc[i] * dt
		vx[i] = bvx
		vy[i] = bvy
		var bx := x[i] + bvx * dt
		var by := y[i] + bvy * dt
		x[i] = bx
		y[i] = by
		var k := 1.0 - tt / life
		var c := 1.0
		var s := 0.0
		var sx := r[i] * (0.4 + 0.6 * k)
		var sy := sx
		if style[i] == 1:
			var spd := sqrt(bvx * bvx + bvy * bvy)
			if spd > 0.001:
				c = bvx / spd
				s = bvy / spd
			sx = maxf(sy, spd * 0.06) * 1.6
			sy *= 0.45
		_put(i, bx, by, c, s, sx, sy, pal[col[i]], k)
		i -= 1
	commit()

# ---------------------------------------------------------------- items
## style: 0 small power, 1 big power, 2 point, 3 star (cancel), 4 bomb
func update_items(dt: float, px: float, py: float, attract_all: bool, magnet_r: float, h: float) -> void:
	got[0] = 0; got[1] = 0; got[2] = 0; got[3] = 0; got[4] = 0
	var i := n - 1
	var m2 := magnet_r * magnet_r
	while i >= 0:
		var tt := t[i] + dt
		t[i] = tt
		var bx := x[i]
		var by := y[i]
		var dx := px - bx
		var dy := py - by
		var d2 := dx * dx + dy * dy
		var st := style[i]
		if d2 < 20.0 * 20.0:
			got[st] += 1
			kill(i)
			i -= 1
			continue
		var fl := flags[i]
		if fl & F_HOME == 0:
			if attract_all or d2 < m2 or (st == 3 and tt > 0.3):
				fl |= F_HOME
				flags[i] = fl
		if fl & F_HOME:
			var d := sqrt(d2)
			var sp := 380.0 + tt * 200.0
			vx[i] = dx / d * sp
			vy[i] = dy / d * sp
		else:
			vx[i] *= 0.94
			vy[i] = minf(vy[i] + 220.0 * dt, 95.0)
		bx += vx[i] * dt
		by += vy[i] * dt
		x[i] = bx
		y[i] = by
		if by > h + 20.0:
			kill(i)
			i -= 1
			continue
		var sz := 10.0
		if st == 1 or st == 4:
			sz = 15.0
		elif st == 3:
			sz = 7.0
		var a := tt * 3.0
		_put(i, bx, by, cos(a), sin(a), sz, sz, pal[st], 1.0)
		i -= 1
	commit()
