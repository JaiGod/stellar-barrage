extends Node2D
## Stellar Barrage — app shell: menus, HUD, input mapping, touch controls,
## save data (high scores, practice bests, options).

const W := 360.0
const H := 640.0
const GameScript := preload("res://scripts/game.gd")
const SfxScript := preload("res://scripts/sfx.gd")
const LayerScript := preload("res://scripts/layer.gd")
const SAVE := "user://stellar_barrage_save.json"
const CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-*."
const MAX_CONT := 3

var game
var sfx
var ui: Node2D
var font: Font
var state := "title"
var sel := 0
var items: Array = []
var item_y0 := 300.0
var item_gap := 40.0
var t := 0.0
var st_t := 0.0
var sel_ship := 0
var sel_diff := 1
var sel_stage := 1
var practice := false
var score_tab := 1
var cont_t := 10.0
var result_kind := ""   # over, clear, practice
var name_chars := [0, 0, 0]
var name_pos := 0
var last_rank := -1
var touch_mode := false
var drag_id := -1
var touch_focus := false
var data := {}
var title_rot := 0.0
var title_cd := 0.0

func _ready() -> void:
	_setup_input()
	font = ThemeDB.fallback_font
	sfx = SfxScript.new()
	add_child(sfx)
	game = GameScript.new()
	game.main = self
	game.sfx = sfx
	add_child(game)
	ui = LayerScript.new()
	ui.cb = draw_ui
	add_child(ui)
	_load()
	sfx.set_muted(not data.sound)
	sel_ship = int(data.ship)
	sel_diff = int(data.diff)
	score_tab = sel_diff
	goto("title")
	_url_hook()

# Web-only test/demo hook, e.g. play/?stage=3&boss=1&ship=1&god=1 (used for
# screenshots and the live beta test). Ignored on desktop builds.
func _url_hook() -> void:
	if not OS.has_feature("web"):
		return
	var q := str(JavaScriptBridge.eval("location.search", true))
	if q.find("stage=") < 0:
		return
	var args := {}
	for kv in q.trim_prefix("?").split("&"):
		var parts := kv.split("=")
		if parts.size() == 2:
			args[parts[0]] = parts[1]
	sel_ship = clampi(int(args.get("ship", "0")), 0, 2)
	sel_diff = clampi(int(args.get("diff", "1")), 0, 3)
	sel_stage = clampi(int(args.get("stage", "1")), 1, 5)
	practice = true
	_start_game()
	game.god = args.get("god", "0") == "1"
	if args.has("boss") or args.has("mid"):
		game.banner_t = 0.0
	if args.get("boss", "0") == "1":
		game.phase = "play"
		game.tl_t = 70.5
		game.ev_i = game.events.size() - 1
	elif args.get("mid", "0") == "1":
		game.phase = "play"
		game.tl_t = 29.5
		for i in game.events.size():
			if game.events[i][1] == "midboss":
				game.ev_i = i
				break

# ================================================================ input map
func _add(action: String, keys: Array, buttons: Array, axes: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.35)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(action, e)
	for a in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = a[0]
		e.axis_value = a[1]
		InputMap.action_add_event(action, e)

func _setup_input() -> void:
	_add("left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_add("right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_add("up", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_add("down", [KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_add("shoot", [KEY_Z, KEY_J], [JOY_BUTTON_A], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_add("bomb", [KEY_X, KEY_K], [JOY_BUTTON_B, JOY_BUTTON_Y])
	_add("focus", [KEY_SHIFT, KEY_L], [JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_SHOULDER])
	_add("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	_add("accept", [KEY_Z, KEY_ENTER, KEY_SPACE, KEY_KP_ENTER], [JOY_BUTTON_A])
	_add("back", [KEY_X, KEY_ESCAPE, KEY_BACKSPACE], [JOY_BUTTON_B])
	_add("mute", [KEY_M], [])

# ================================================================ save data
func _default_scores() -> Array:
	var names := ["NOV", "JAI", "ORB", "ZEN", "VEX", "LUX", "ION", "RAY", "SOL", "KAI"]
	var out := []
	for i in 10:
		out.append({"name": names[i], "score": (10 - i) * 600000, "ship": i % 3, "stage": maxi(1, 5 - i / 2), "cont": 0})
	return out

func _load() -> void:
	data = {"scores": {}, "practice": {}, "sound": true, "auto": true, "ship": 0, "diff": 1}
	for d in 4:
		data.scores[str(d)] = _default_scores()
	if FileAccess.file_exists(SAVE):
		var f := FileAccess.open(SAVE, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				for k in parsed:
					data[k] = parsed[k]

func save() -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

func hi_for(d: int) -> int:
	var arr: Array = data.scores.get(str(d), [])
	return int(arr[0].score) if arr.size() > 0 else 0

# ================================================================ state machine
func goto(s: String) -> void:
	state = s
	st_t = 0.0
	sel = 0
	items = []
	match s:
		"title":
			items = ["START GAME", "PRACTICE", "HIGH SCORES", "HOW TO PLAY", "SOUND: " + ("ON" if data.sound else "OFF"), "AUTO-FIRE: " + ("ON" if data.auto else "OFF")]
			item_y0 = 318.0
			item_gap = 40.0
			sfx.play_music("title")
		"diff":
			items = game.DIFFS.duplicate()
			sel = sel_diff
			item_y0 = 200.0
			item_gap = 70.0
		"ship":
			sel = sel_ship
		"stage":
			items = ["STAGE 1", "STAGE 2", "STAGE 3", "STAGE 4", "STAGE 5"]
			sel = sel_stage - 1
			item_y0 = 170.0
			item_gap = 74.0
		"pause":
			items = ["RESUME", "RESTART", "SOUND: " + ("ON" if data.sound else "OFF"), "QUIT TO TITLE"]
			item_y0 = 300.0
			item_gap = 46.0
		"continue":
			cont_t = 10.0
			items = ["CONTINUE", "GIVE UP"]
			item_y0 = 380.0
			item_gap = 50.0

func _start_game() -> void:
	data.ship = sel_ship
	data.diff = sel_diff
	save()
	game.start_run(sel_ship, sel_diff, sel_stage if practice else 1, practice)
	touch_focus = false
	state = "play"

func on_game_over() -> void:
	if game.continues < MAX_CONT:
		goto("continue")
	else:
		_finish("over")

func on_all_clear() -> void:
	_finish("clear")

func on_practice_clear() -> void:
	_practice_best()
	_finish("practice")

func _practice_best() -> void:
	var key := "%d_%d" % [game.diff, game.stage]
	if game.score > int(data.practice.get(key, 0)):
		data.practice[key] = game.score
		save()

func _finish(kind: String) -> void:
	result_kind = kind
	sfx.play_music("")
	game.active = false
	last_rank = -1
	state = "result"
	st_t = 0.0
	if kind == "clear":
		sfx.play("extend")

func _qualifies() -> bool:
	if result_kind == "practice":
		return false
	var arr: Array = data.scores[str(game.diff)]
	return arr.size() < 10 or game.score > int(arr[arr.size() - 1].score)

func _commit_name() -> void:
	var nm := ""
	for k in 3:
		nm += CHARS[name_chars[k]]
	var arr: Array = data.scores[str(game.diff)]
	var entry := {"name": nm, "score": game.score, "ship": game.ship, "stage": game.stage if result_kind != "clear" else 6, "cont": game.continues}
	arr.append(entry)
	arr.sort_custom(func(a, b): return int(a.score) > int(b.score))
	while arr.size() > 10:
		arr.pop_back()
	last_rank = arr.find(entry)
	data.scores[str(game.diff)] = arr
	save()
	score_tab = game.diff
	sfx.play("ok")
	goto("scores")

# ================================================================ per-frame
func _process(delta: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	t += dt
	st_t += dt
	if state == "play":
		game.move_vec = Input.get_vector("left", "right", "up", "down", 0.25)
		game.focus = Input.is_action_pressed("focus") or touch_focus
		game.shooting = data.auto or Input.is_action_pressed("shoot") or drag_id >= 0
	if state == "continue":
		cont_t -= dt
		if cont_t <= 0.0:
			_finish("over")
	if not game.active:
		_title_fx(dt)
	game.step(dt)
	ui.queue_redraw()

func _title_fx(dt: float) -> void:
	title_cd -= dt
	if title_cd <= 0.0 and state != "result":
		title_cd = 0.09
		title_rot += 0.31
		for k in 4:
			var i: int = game.eb.spawn(W / 2, 200, cos(title_rot + k * TAU / 4) * 70, sin(title_rot + k * TAU / 4) * 70, 4.0, [4, 7, 2, 6][k], 1)
			if i >= 0:
				game.eb.set_motion(i, 25.0, 0.35)
	game.eb.update_bullets(dt, -999, -999, false, false, 1, 1, W, H)
	game.fx.update_fx(dt)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "play" and game.active:
		_pause()

func _pause() -> void:
	game.paused = true
	goto("pause")
	sfx.play("back")

# ================================================================ input events
func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch or ev is InputEventScreenDrag:
		touch_mode = true
		_touch(ev)
		return
	if ev is InputEventMouse:
		return
	if ev.is_action_pressed("mute"):
		_toggle_sound()
		return
	if state == "play":
		if ev.is_action_pressed("pause"):
			_pause()
		elif ev.is_action_pressed("bomb"):
			game.bomb_req = true
		if ev is InputEventKey or ev is InputEventJoypadButton:
			if not ev.is_action("pause") and ev.is_pressed():
				touch_mode = false if ev is InputEventKey else touch_mode
		return
	var up := ev.is_action_pressed("up", true)
	var down := ev.is_action_pressed("down", true)
	var left := ev.is_action_pressed("left", true)
	var right := ev.is_action_pressed("right", true)
	var ok := ev.is_action_pressed("accept")
	var back := ev.is_action_pressed("back") or (ev.is_action_pressed("pause") and state != "pause")
	if state == "pause" and ev.is_action_pressed("pause"):
		_activate(0)
		return
	_nav(up, down, left, right, ok, back)

func _nav(up: bool, down: bool, left: bool, right: bool, ok: bool, back: bool) -> void:
	match state:
		"ship":
			if left or up:
				sel_ship = (sel_ship + 2) % 3
				sfx.play("move")
			elif right or down:
				sel_ship = (sel_ship + 1) % 3
				sfx.play("move")
			elif ok:
				sfx.play("ok")
				if practice:
					goto("stage")
				else:
					_start_game()
			elif back:
				sfx.play("back")
				goto("diff")
			return
		"scores":
			if left:
				score_tab = (score_tab + 3) % 4
				sfx.play("move")
			elif right:
				score_tab = (score_tab + 1) % 4
				sfx.play("move")
			elif ok or back:
				sfx.play("back")
				goto("title")
			return
		"howto":
			if ok or back:
				sfx.play("back")
				goto("title")
			return
		"result":
			if (ok or back) and st_t > 0.8:
				sfx.play("ok")
				if _qualifies():
					name_chars = [9, 0, 8]
					name_pos = 0
					state = "name"
				else:
					goto("title")
			return
		"name":
			if up:
				name_chars[name_pos] = (name_chars[name_pos] + 1) % CHARS.length()
				sfx.play("move")
			elif down:
				name_chars[name_pos] = (name_chars[name_pos] + CHARS.length() - 1) % CHARS.length()
				sfx.play("move")
			elif right or ok:
				if name_pos < 2:
					name_pos += 1
					sfx.play("move")
				elif ok:
					_commit_name()
			elif left or back:
				if name_pos > 0:
					name_pos -= 1
					sfx.play("back")
			return
	if items.size() == 0:
		return
	if up:
		sel = (sel + items.size() - 1) % items.size()
		sfx.play("move")
	elif down:
		sel = (sel + 1) % items.size()
		sfx.play("move")
	elif ok:
		_activate(sel)
	elif back:
		sfx.play("back")
		match state:
			"diff":
				goto("title")
			"stage":
				goto("ship")
			"pause":
				_activate(0)
			"continue":
				_finish("over")

func _activate(i: int) -> void:
	sel = i
	match state:
		"title":
			match i:
				0:
					practice = false
					sfx.play("ok")
					goto("diff")
				1:
					practice = true
					sfx.play("ok")
					goto("diff")
				2:
					sfx.play("ok")
					score_tab = sel_diff
					goto("scores")
				3:
					sfx.play("ok")
					goto("howto")
				4:
					_toggle_sound()
					items[4] = "SOUND: " + ("ON" if data.sound else "OFF")
				5:
					data.auto = not data.auto
					save()
					items[5] = "AUTO-FIRE: " + ("ON" if data.auto else "OFF")
					sfx.play("move")
		"diff":
			sel_diff = i
			sfx.play("ok")
			goto("ship")
		"stage":
			sel_stage = i + 1
			sfx.play("ok")
			_start_game()
		"pause":
			match i:
				0:
					game.paused = false
					state = "play"
					sfx.play("ok")
				1:
					if game.practice:
						_practice_best()
					sfx.play("ok")
					if game.practice:
						_start_game()
					else:
						_restart_full()
				2:
					_toggle_sound()
					items[2] = "SOUND: " + ("ON" if data.sound else "OFF")
				3:
					if game.practice:
						_practice_best()
					game.active = false
					game.paused = false
					game.eb.clear()
					sfx.play("back")
					goto("title")
		"continue":
			if i == 0:
				game.continue_run()
				sfx.play("start")
				state = "play"
			else:
				_finish("over")

func _restart_full() -> void:
	practice = false
	_start_game()

func _toggle_sound() -> void:
	data.sound = not data.sound
	sfx.set_muted(not data.sound)
	save()
	sfx.play("move")

# ---------------------------------------------------------------- touch
const BOMB_BTN := Vector2(46, 588)
const FOCUS_BTN := Vector2(314, 588)

func _touch(ev: InputEvent) -> void:
	var p: Vector2 = ev.position
	if state == "play":
		if ev is InputEventScreenTouch:
			if ev.pressed:
				if p.x > W - 52 and p.y < 52:
					_pause()
					return
				if p.distance_to(BOMB_BTN) < 36:
					game.bomb_req = true
					return
				if p.distance_to(FOCUS_BTN) < 36:
					touch_focus = not touch_focus
					return
				if drag_id < 0:
					drag_id = ev.index
			elif ev.index == drag_id:
				drag_id = -1
		elif ev is InputEventScreenDrag and ev.index == drag_id:
			game.touch_delta += ev.relative * 1.3
		return
	if not (ev is InputEventScreenTouch and ev.pressed):
		return
	# back button
	if p.x < 96 and p.y < 50 and state in ["diff", "ship", "stage", "scores", "howto"]:
		_nav(false, false, false, false, false, true)
		return
	match state:
		"ship":
			if p.y > 540:
				_nav(false, false, false, false, true, false)
			elif p.y > 80 and p.y < 160:
				var k := clampi(int(p.x / 120.0), 0, 2)
				if k != sel_ship:
					sel_ship = k
					sfx.play("move")
			elif p.x < 90:
				_nav(false, false, true, false, false, false)
			elif p.x > W - 90:
				_nav(false, false, false, true, false, false)
			return
		"scores":
			if p.y > 560:
				_nav(false, false, false, false, true, false)
			elif p.y < 140 and p.y > 60:
				score_tab = clampi(int(p.x / 90.0), 0, 3)
				sfx.play("move")
			return
		"howto":
			_nav(false, false, false, false, true, false)
			return
		"result":
			_nav(false, false, false, false, true, false)
			return
		"name":
			for k in 3:
				var cx := W / 2 + (k - 1) * 70
				if absf(p.x - cx) < 32 and p.y > 230 and p.y < 400:
					name_pos = k
					if p.y < 315:
						name_chars[k] = (name_chars[k] + 1) % CHARS.length()
					else:
						name_chars[k] = (name_chars[k] + CHARS.length() - 1) % CHARS.length()
					sfx.play("move")
					return
			if p.y > 440 and p.y < 500:
				_commit_name()
			return
	for i in items.size():
		var y := item_y0 + i * item_gap
		if absf(p.y - y) < item_gap * 0.48 and absf(p.x - W / 2) < 150:
			_activate(i)
			return

# ================================================================ drawing
func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out

func txt(c: CanvasItem, x: float, y: float, s: String, size: int, col: Color, align: int = 1, glow: bool = false) -> void:
	var w := 600.0
	var px := x - w / 2.0
	if align == 0:
		px = x
	elif align == 2:
		px = x - w
	var ha := HORIZONTAL_ALIGNMENT_CENTER if align == 1 else (HORIZONTAL_ALIGNMENT_LEFT if align == 0 else HORIZONTAL_ALIGNMENT_RIGHT)
	if glow:
		c.draw_string(font, Vector2(px, y + 2), s, ha, w, size, Color(col, 0.35))
		c.draw_string_outline(font, Vector2(px, y), s, ha, w, size, 6, Color(col, 0.25))
	c.draw_string_outline(font, Vector2(px, y), s, ha, w, size, 3, Color(0, 0, 0, 0.6 * col.a))
	c.draw_string(font, Vector2(px, y), s, ha, w, size, col)

func panel(c: CanvasItem, r: Rect2, col: Color) -> void:
	c.draw_rect(r, Color(0.02, 0.01, 0.06, 0.82))
	c.draw_rect(r, Color(col, 0.7), false, 1.5)
	c.draw_rect(r.grow(3), Color(col, 0.18), false, 3)

func draw_ui(c: CanvasItem) -> void:
	if game.active or state in ["play", "pause", "continue"]:
		_draw_hud(c)
	match state:
		"title":
			_draw_title(c)
		"diff":
			_draw_diff(c)
		"ship":
			_draw_ship(c)
		"stage":
			_draw_stage(c)
		"scores":
			_draw_scores(c)
		"howto":
			_draw_howto(c)
		"pause":
			c.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0.02, 0.55))
			txt(c, W / 2, 230, "PAUSED", 40, Color(0.6, 0.9, 1), 1, true)
			_draw_items(c)
			txt(c, W / 2, 560, "Esc / P / Start to resume", 13, Color(1, 1, 1, 0.5))
		"continue":
			c.draw_rect(Rect2(0, 0, W, H), Color(0.05, 0, 0.02, 0.6))
			txt(c, W / 2, 220, "GAME OVER", 40, Color(1, 0.35, 0.45), 1, true)
			txt(c, W / 2, 270, "CONTINUE?", 24, Color.WHITE)
			txt(c, W / 2, 335, str(int(ceil(cont_t))), 52, Color(1, 0.9, 0.4), 1, true)
			txt(c, W / 2, 470, "Continues left: %d   (score resets)" % (MAX_CONT - game.continues), 13, Color(1, 1, 1, 0.6))
			_draw_items(c)
		"result":
			_draw_result(c)
		"name":
			_draw_name(c)
	if touch_mode and state in ["diff", "ship", "stage", "scores", "howto"]:
		txt(c, 14, 32, "< BACK", 16, Color(1, 1, 1, 0.75), 0)

func _draw_items(c: CanvasItem) -> void:
	for i in items.size():
		var y := item_y0 + i * item_gap
		var on := i == sel
		var col := Color(1, 1, 1, 1) if on else Color(0.75, 0.8, 1.0, 0.65)
		if on:
			var w := 250.0
			var pulse := 0.5 + 0.5 * sin(t * 6.0)
			c.draw_rect(Rect2(W / 2 - w / 2, y - 24, w, 34), Color(0.4, 0.2, 1.0, 0.18 + 0.1 * pulse))
			c.draw_rect(Rect2(W / 2 - w / 2, y - 24, w, 34), Color(0.4, 0.9, 1.0, 0.8), false, 1.5)
			txt(c, W / 2 - w / 2 + 14, y, ">", 18, Color(0.4, 1, 1), 0)
		txt(c, W / 2, y, items[i], 20 if on else 18, col)

func _draw_title(c: CanvasItem) -> void:
	var y := 120.0 + sin(t * 1.5) * 4.0
	txt(c, W / 2, y, "STELLAR", 54, Color(0.35, 0.95, 1.0), 1, true)
	txt(c, W / 2, y + 52, "BARRAGE", 54, Color(1.0, 0.35, 0.9), 1, true)
	c.draw_line(Vector2(50, y + 70), Vector2(W - 50, y + 70), Color(1, 0.9, 0.4, 0.6), 2)
	txt(c, W / 2, y + 94, "a neon bullet-hell shoot-'em-up", 14, Color(1, 1, 1, 0.7))
	_draw_items(c)
	txt(c, W / 2, 586, "HI-SCORE  " + fmt(hi_for(sel_diff)) + "  (" + game.DIFFS[sel_diff] + ")", 13, Color(1, 0.9, 0.5, 0.85))
	txt(c, W / 2, 612, "Made by Jaineil Rana (JaKing) · JaiGod", 11, Color(1, 1, 1, 0.45))

func _draw_diff(c: CanvasItem) -> void:
	txt(c, W / 2, 110, ("PRACTICE · " if practice else "") + "DIFFICULTY", 26, Color(0.5, 0.95, 1), 1, true)
	var desc := ["Gentle patterns. Learn the ropes.", "The intended challenge.", "Dense, fast and unforgiving.", "Popcorn fires back. Good luck."]
	var cols := [Color(0.4, 1, 0.5), Color(0.4, 0.9, 1), Color(1, 0.6, 0.3), Color(1, 0.3, 0.5)]
	for i in 4:
		var y := item_y0 + i * item_gap
		var on := i == sel
		var r := Rect2(40, y - 30, W - 80, 56)
		panel(c, r, cols[i] if on else Color(0.4, 0.4, 0.6))
		if on:
			c.draw_rect(r, Color(cols[i], 0.12 + 0.06 * sin(t * 6)))
		txt(c, W / 2, y - 2, game.DIFFS[i], 22, cols[i] if on else Color(1, 1, 1, 0.7))
		txt(c, W / 2, y + 18, desc[i], 12, Color(1, 1, 1, 0.6))
	txt(c, W / 2, 590, "Up/Down + Z · Tap to choose", 12, Color(1, 1, 1, 0.45))

func _draw_ship(c: CanvasItem) -> void:
	txt(c, W / 2, 62, "SELECT SHIP", 24, Color(0.5, 0.95, 1), 1, true)
	for k in 3:
		var cx := 60.0 + k * 120.0
		var on := k == sel_ship
		panel(c, Rect2(cx - 48, 84, 96, 74), game.SHIPS[k].col if on else Color(0.3, 0.3, 0.5))
		game.draw_ship(c, k, Vector2(cx, 121), 1.6 if on else 1.2)
	var sd: Dictionary = game.SHIPS[sel_ship]
	var col: Color = sd.col
	var cy := 260.0
	c.draw_circle(Vector2(W / 2, cy), 66, Color(col, 0.07))
	game._poly(c, Vector2(W / 2, cy), 60, 6, t * 0.5, Color(col, 0.4), 1.5)
	game.draw_ship(c, sel_ship, Vector2(W / 2, cy + sin(t * 2) * 4), 3.4)
	txt(c, 26, cy, "<", 34, Color(1, 1, 1, 0.5 + 0.3 * sin(t * 5)), 0)
	txt(c, W - 26, cy, ">", 34, Color(1, 1, 1, 0.5 + 0.3 * sin(t * 5)), 2)
	txt(c, W / 2, 365, sd.name, 30, col, 1, true)
	txt(c, W / 2, 390, sd.title, 15, Color(1, 1, 1, 0.8))
	panel(c, Rect2(24, 404, W - 48, 128), col)
	var lines := _wrap(sd.desc, 40)
	for i in lines.size():
		txt(c, W / 2, 428 + i * 17, lines[i], 13, Color(1, 1, 1, 0.85))
	var stats := [["SPEED", [3, 2, 4][sel_ship]], ["POWER", [3, 4, 2][sel_ship]], ["RANGE", [4, 2, 5][sel_ship]]]
	for i in 3:
		var y := 478.0 + i * 16
		txt(c, 50, y + 4, stats[i][0], 11, Color(1, 1, 1, 0.6), 0)
		for j in 5:
			c.draw_rect(Rect2(120 + j * 40, y - 6, 34, 8), Color(col, 0.85) if j < stats[i][1] else Color(1, 1, 1, 0.12))
	txt(c, W / 2, 527, "BOMB: " + sd.bomb, 12, Color(1, 0.9, 0.5, 0.9))
	var pulse := 0.5 + 0.5 * sin(t * 5)
	panel(c, Rect2(80, 550, 200, 44), col)
	c.draw_rect(Rect2(80, 550, 200, 44), Color(col, 0.12 + 0.12 * pulse))
	txt(c, W / 2, 579, "LAUNCH", 22, Color.WHITE)
	txt(c, W / 2, 618, game.DIFFS[sel_diff] + (" · PRACTICE" if practice else "") + " · Left/Right + Z", 11, Color(1, 1, 1, 0.45))

func _wrap(s: String, n: int) -> Array:
	var out := []
	var line := ""
	for w in s.split(" "):
		if (line + " " + w).strip_edges().length() > n:
			out.append(line.strip_edges())
			line = w
		else:
			line += " " + w
	if line.strip_edges() != "":
		out.append(line.strip_edges())
	return out

func _draw_stage(c: CanvasItem) -> void:
	txt(c, W / 2, 100, "PRACTICE · STAGE", 24, Color(0.5, 0.95, 1), 1, true)
	for i in 5:
		var y := item_y0 + i * item_gap
		var inf: Dictionary = game.st.info(i + 1)
		var on := i == sel
		panel(c, Rect2(30, y - 32, W - 60, 60), inf.col if on else Color(0.35, 0.35, 0.55))
		if on:
			c.draw_rect(Rect2(30, y - 32, W - 60, 60), Color(inf.col, 0.1 + 0.06 * sin(t * 6)))
		txt(c, 46, y - 6, "STAGE %d" % (i + 1), 18, inf.col, 0)
		txt(c, W - 46, y - 6, inf.name, 14, Color(1, 1, 1, 0.8), 2)
		var best := int(data.practice.get("%d_%d" % [sel_diff, i + 1], 0))
		txt(c, 46, y + 16, "Boss: " + inf.boss, 11, Color(1, 1, 1, 0.55), 0)
		txt(c, W - 46, y + 16, "BEST " + fmt(best), 11, Color(1, 0.9, 0.5, 0.8), 2)
	txt(c, W / 2, 600, game.DIFFS[sel_diff] + " · full power, unlimited lives", 12, Color(1, 1, 1, 0.5))

func _draw_scores(c: CanvasItem) -> void:
	txt(c, W / 2, 62, "HIGH SCORES", 28, Color(1, 0.9, 0.4), 1, true)
	for d in 4:
		var on := d == score_tab
		var r := Rect2(6 + d * 87, 82, 84, 32)
		panel(c, r, Color(0.5, 0.9, 1) if on else Color(0.3, 0.3, 0.5))
		txt(c, r.position.x + 42, 104, game.DIFFS[d], 12 if d < 3 else 10, Color.WHITE if on else Color(1, 1, 1, 0.5))
	var arr: Array = data.scores.get(str(score_tab), [])
	txt(c, 22, 150, "#", 12, Color(1, 1, 1, 0.5), 0)
	txt(c, 46, 150, "NAME", 12, Color(1, 1, 1, 0.5), 0)
	txt(c, 250, 150, "SCORE", 12, Color(1, 1, 1, 0.5), 2)
	txt(c, 300, 150, "SHIP", 12, Color(1, 1, 1, 0.5), 1)
	txt(c, 345, 150, "ST", 12, Color(1, 1, 1, 0.5), 2)
	for i in arr.size():
		var e: Dictionary = arr[i]
		var y := 182.0 + i * 36
		var hl = i == last_rank and score_tab == game.diff
		var col := Color(1, 0.95, 0.5) if hl else (Color(0.6, 1, 1) if i == 0 else Color(1, 1, 1, 0.85))
		if hl:
			c.draw_rect(Rect2(12, y - 22, W - 24, 32), Color(1, 0.9, 0.3, 0.12 + 0.08 * sin(t * 8)))
		txt(c, 22, y, str(i + 1), 16, col, 0)
		txt(c, 46, y, str(e.name), 16, col, 0)
		txt(c, 250, y, fmt(int(e.score)), 16, col, 2)
		txt(c, 300, y, game.SHIPS[int(e.ship)].name.substr(0, 3), 12, game.SHIPS[int(e.ship)].col, 1)
		var stg := "ALL" if int(e.stage) >= 6 else str(int(e.stage))
		txt(c, 345, y, stg + ("c" if int(e.get("cont", 0)) > 0 else ""), 12, col, 2)
	txt(c, W / 2, 598, "Left/Right: difficulty · Z: back", 12, Color(1, 1, 1, 0.5))

func _draw_howto(c: CanvasItem) -> void:
	txt(c, W / 2, 70, "HOW TO PLAY", 28, Color(0.5, 0.95, 1), 1, true)
	var lines := [
		["MOVE", "Arrows / WASD / stick · drag anywhere (touch)"],
		["SHOOT", "Z or hold A (auto-fire is on by default)"],
		["FOCUS", "Shift / X button · FOCUS pad (touch): slow,"],
		["", "precise movement, shows your hitbox, tightens shots"],
		["BOMB", "X / B button · BOMB pad: clears bullets, invincible"],
		["PAUSE", "Esc / P / Start · top-right on touch · M = mute"],
		["", ""],
		["GRAZE", "Skim bullets without touching the white dot."],
		["", "Grazing raises the multiplier (up to x8.00)."],
		["ITEMS", "Red P = power, blue = points (worth more high up),"],
		["", "move above the line near the top to collect all."],
		["BOSS", "Break each phase fast for a phase bonus;"],
		["", "no deaths or bombs = PERFECT (double)."],
		["DEATH", "Bomb right as you are hit for a deathbomb!"],
		["EXTEND", "Extra lives at 10M, 25M, 50M, 80M, 120M."],
	]
	for i in lines.size():
		var y := 120.0 + i * 28
		txt(c, 16, y, lines[i][0], 13, Color(1, 0.85, 0.4), 0)
		txt(c, 78, y, lines[i][1], 12, Color(1, 1, 1, 0.85), 0)
	txt(c, W / 2, 600, "Press Z or tap to return", 13, Color(1, 1, 1, 0.5))

func _draw_result(c: CanvasItem) -> void:
	c.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0.03, 0.6))
	var title := "GAME OVER"
	var col := Color(1, 0.35, 0.45)
	if result_kind == "clear":
		title = "ALL CLEAR!"
		col = Color(1, 0.9, 0.4)
	elif result_kind == "practice":
		title = "STAGE CLEAR"
		col = Color(0.5, 1, 0.6)
	txt(c, W / 2, 170, title, 42, col, 1, true)
	if result_kind == "clear":
		txt(c, W / 2, 205, "The Null Seraph falls. The stars are quiet again.", 12, Color(1, 1, 1, 0.75))
	panel(c, Rect2(40, 240, W - 80, 200), col)
	var rows := [["SCORE", fmt(game.score)], ["SHIP", game.SHIPS[game.ship].name], ["DIFFICULTY", game.DIFFS[game.diff]],
		["STAGE", "ALL" if result_kind == "clear" else str(game.stage)], ["GRAZE", fmt(game.graze)], ["CONTINUES", str(game.continues)]]
	for i in rows.size():
		txt(c, 60, 272 + i * 28, rows[i][0], 14, Color(1, 1, 1, 0.6), 0)
		txt(c, W - 60, 272 + i * 28, rows[i][1], 16, Color.WHITE, 2)
	if st_t > 0.8:
		var msg := "NEW HIGH SCORE! Press Z / tap" if _qualifies() else "Press Z / tap to continue"
		txt(c, W / 2, 500, msg, 15, Color(1, 0.9, 0.5, 0.6 + 0.4 * sin(t * 5)))

func _draw_name(c: CanvasItem) -> void:
	c.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0.03, 0.75))
	txt(c, W / 2, 140, "NEW HIGH SCORE", 30, Color(1, 0.9, 0.4), 1, true)
	txt(c, W / 2, 180, fmt(game.score), 22, Color.WHITE)
	txt(c, W / 2, 212, "Enter your initials", 13, Color(1, 1, 1, 0.6))
	for k in 3:
		var cx := W / 2 + (k - 1) * 70
		var on := k == name_pos
		panel(c, Rect2(cx - 28, 278, 56, 64), Color(0.4, 1, 1) if on else Color(0.4, 0.4, 0.6))
		txt(c, cx, 326, CHARS[name_chars[k]], 40, Color.WHITE if on else Color(1, 1, 1, 0.7))
		txt(c, cx, 266, "^", 22, Color(0.4, 1, 1, 0.8 if on else 0.3))
		txt(c, cx, 372, "v", 20, Color(0.4, 1, 1, 0.8 if on else 0.3))
	panel(c, Rect2(110, 446, 140, 46), Color(1, 0.9, 0.4))
	txt(c, W / 2, 477, "OK", 22, Color.WHITE)
	txt(c, W / 2, 540, "Up/Down: letter · Left/Right: move · Z: next", 11, Color(1, 1, 1, 0.5))

func _draw_hud(c: CanvasItem) -> void:
	var g = game
	# flash
	if g.flash > 0.0:
		c.draw_rect(Rect2(0, 0, W, H), Color(g.flash_col, g.flash * 0.35))
	# top bar
	c.draw_rect(Rect2(0, 0, W, 40), Color(0.01, 0.0, 0.04, 0.6))
	c.draw_line(Vector2(0, 40), Vector2(W, 40), Color(g.stage_color(), 0.5), 1)
	txt(c, 8, 15, "SCORE", 9, Color(1, 1, 1, 0.5), 0)
	txt(c, 8, 33, fmt(g.score), 17, Color.WHITE, 0)
	var hi := maxi(hi_for(g.diff), g.score)
	txt(c, 196, 15, "HI " + fmt(hi), 10, Color(1, 0.9, 0.5, 0.75), 2)
	var mcol := Color(0.5, 1, 1).lerp(Color(1, 0.4, 0.9), (g.mult - 1.0) / 7.0)
	txt(c, 196, 34, "x%.2f" % g.mult, 15, mcol, 2)
	# lives & bombs
	for k in mini(g.lives, 7):
		game.draw_ship(c, g.ship, Vector2(214 + k * 13, 14), 0.42)
	for k in mini(g.bombs, 7):
		var p := Vector2(214 + k * 13, 31)
		game._poly(c, p, 5, 4, t * 2.0, Color(0.5, 1, 0.5), 1.5)
	txt(c, W - 50, 15, "GRZ " + str(g.graze), 9, Color(1, 1, 1, 0.55), 2)
	var pw: float = g.power
	txt(c, W - 50, 33, "MAX" if pw >= 4.0 else "P %.2f" % pw, 11, Color(1, 0.45, 0.5), 2)
	# pause button
	c.draw_rect(Rect2(W - 40, 8, 30, 26), Color(1, 1, 1, 0.08))
	c.draw_rect(Rect2(W - 31, 13, 4, 16), Color(1, 1, 1, 0.7))
	c.draw_rect(Rect2(W - 23, 13, 4, 16), Color(1, 1, 1, 0.7))
	# boss bar
	if g.boss != null:
		var b: Dictionary = g.boss
		var ph: Dictionary = b.phases[b.pi]
		c.draw_rect(Rect2(8, 46, W - 16, 6), Color(1, 1, 1, 0.1))
		var k := clampf(b.hp / b.maxhp, 0.0, 1.0) if b.state == "fight" else minf(1.0, b.st)
		c.draw_rect(Rect2(8, 46, (W - 16) * k, 6), Color(b.col, 0.9))
		var remaining: int = b.phases.size() - b.pi - 1
		for j in remaining:
			game._poly(c, Vector2(14 + j * 12, 64), 4, 4, 0, b.col, 1.5)
		txt(c, 14 + remaining * 12, 69, b.name, 11, Color(b.col, 0.9), 0)
		if b.state == "fight":
			var left := maxf(0.0, ph.time - b.pt)
			txt(c, W - 10, 69, "%d" % int(ceil(left)), 14, Color(1, 0.4, 0.4) if left < 10 else Color.WHITE, 2)
			txt(c, W - 34, 69, ph.name, 10, Color(1, 1, 1, 0.7), 2)
	# collection line hint
	if g.active and g.py < 230 and g.boss == null:
		c.draw_line(Vector2(0, 190), Vector2(W, 190), Color(0.4, 0.6, 1, 0.15), 1)
	# popups
	for p in g.popups:
		var a := clampf(1.3 - p.t, 0.0, 1.0)
		txt(c, clampf(p.x, 90, W - 90), p.y, p.s, 13, Color(p.c, a))
	# stage banner
	if g.banner_t > 0.0 and g.banner != "":
		var a := clampf(g.banner_t, 0.0, 1.0) * clampf((3.0 - g.banner_t) * 3.0, 0.0, 1.0)
		var col: Color = g.stage_color()
		c.draw_rect(Rect2(0, 260, W, 90), Color(0, 0, 0, 0.35 * a))
		c.draw_line(Vector2(0, 260), Vector2(W, 260), Color(col, 0.6 * a), 1)
		c.draw_line(Vector2(0, 350), Vector2(W, 350), Color(col, 0.6 * a), 1)
		txt(c, W / 2, 302, g.banner, 34, Color(col, a), 1, true)
		txt(c, W / 2, 332, g.banner2, 16, Color(1, 1, 1, a))
	if g.warn_t > 0.0:
		var a2 := 0.5 + 0.5 * sin(t * 14.0)
		c.draw_rect(Rect2(0, 280, W, 60), Color(1, 0.1, 0.2, 0.18 * a2))
		txt(c, W / 2, 322, "WARNING", 38, Color(1, 0.3, 0.35, a2), 1, true)
	if g.phase == "clear" and g.active:
		var a3 := clampf(g.phase_t * 2.0, 0.0, 1.0)
		panel(c, Rect2(30, 240, W - 60, 150), Color(g.stage_color(), a3))
		txt(c, W / 2, 285, "STAGE %d CLEAR" % g.stage, 28, Color(1, 0.95, 0.6, a3), 1, true)
		txt(c, W / 2, 322, "Clear bonus  " + fmt(g.clear_bonus), 15, Color(1, 1, 1, a3))
		txt(c, W / 2, 346, "Graze this stage  " + str(g.stage_graze), 13, Color(1, 1, 1, 0.8 * a3))
		txt(c, W / 2, 372, ("Next: " + g.st.info(g.stage + 1).name) if g.stage < 5 and not g.practice else "", 13, Color(1, 1, 1, 0.7 * a3))
	if g.practice:
		txt(c, 8, 56 if g.boss == null else 86, "PRACTICE", 10, Color(1, 1, 1, 0.4), 0)
	if g.focus and state == "play":
		pass
	# touch pads
	if touch_mode and state == "play":
		var bc := Color(0.5, 1, 0.5)
		c.draw_circle(BOMB_BTN, 30, Color(bc, 0.1))
		c.draw_arc(BOMB_BTN, 30, 0, TAU, 32, Color(bc, 0.5), 2)
		txt(c, BOMB_BTN.x, BOMB_BTN.y + 5, "BOMB", 12, Color(bc, 0.8))
		var fc := Color(0.5, 0.9, 1)
		c.draw_circle(FOCUS_BTN, 30, Color(fc, 0.25 if touch_focus else 0.08))
		c.draw_arc(FOCUS_BTN, 30, 0, TAU, 32, Color(fc, 0.5), 2)
		txt(c, FOCUS_BTN.x, FOCUS_BTN.y + 5, "FOCUS", 11, Color(fc, 0.9))
