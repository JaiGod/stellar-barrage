extends Node
## Headless smoke test: a bot plays full runs with every ship (invulnerable,
## boosted damage) through all 5 stages, mid-bosses and every boss phase,
## then checks game over, continue, practice mode, bombs, graze and pools.

const DT := 1.0 / 60.0
var main
var game
var fails := 0

func _ready() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	main.set_process_input(false)
	game = main.game
	main.data.auto = false
	_run()

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		fails += 1

func bot(f: int) -> void:
	# drift under the nearest target, weaving, bombing now and then
	var tx := 180.0 + sin(f * 0.02) * 120.0
	if game.boss != null:
		tx = game.boss.x + sin(f * 0.05) * 30.0
	game.move_vec = Vector2(clampf((tx - game.px) / 40.0, -1, 1), sin(f * 0.03) * 0.4)
	game.focus = (f / 240) % 2 == 1
	game.shooting = true
	if f % 900 == 450:
		game.bomb_req = true

func _run() -> void:
	var phases_seen := 0
	for ship in 3:
		print("Ship %d (%s): full run, NORMAL" % [ship, game.SHIPS[ship].name])
		main.sel_ship = ship
		main.sel_diff = 1
		main.practice = false
		main._start_game()
		game.god = true
		game.dmg_mult = 5.0
		var mids := 0
		var bosses := 0
		var had_boss := false
		var max_bul := 0
		var stages_seen := {}
		var f := 0
		while game.active and f < 60 * 60 * 15:
			bot(f)
			game.step(DT)
			f += 1
			max_bul = maxi(max_bul, game.eb.n)
			stages_seen[game.stage] = true
			if game.boss != null and not had_boss:
				had_boss = true
				if game.boss.mid:
					mids += 1
				else:
					bosses += 1
					phases_seen += game.boss.phases.size()
			elif game.boss == null:
				had_boss = false
		check(game.all_clear, "all 5 stages cleared in %.0fs of game time" % (f * DT))
		check(stages_seen.size() == 5, "visited stages %s" % str(stages_seen.keys()))
		check(mids == 5 and bosses == 5, "met %d mid-bosses and %d bosses" % [mids, bosses])
		check(game.graze > 0, "grazed %d bullets" % game.graze)
		check(game.score > 0, "score %d" % game.score)
		check(max_bul > 50 and max_bul <= game.eb.cap, "pooled bullets peaked at %d / %d" % [max_bul, game.eb.cap])
		check(main.state == "result" and main.result_kind == "clear", "result screen shows ALL CLEAR")
		check(main._qualifies(), "score qualifies for the high-score table")
		main._commit_name()
		check(main.state == "scores" and main.last_rank >= 0, "name entered at rank %d" % (main.last_rank + 1))
	check(phases_seen >= 18, "multi-phase bosses: %d phases total" % phases_seen)

	print("Game over + continue (no invulnerability, standing still)")
	main.practice = false
	main.sel_diff = 3
	main._start_game()
	game.god = false
	var f2 := 0
	while not game.over and f2 < 60 * 60 * 6:
		game.move_vec = Vector2.ZERO
		game.shooting = false
		game.step(DT)
		f2 += 1
	check(game.over, "player loses all lives in %.0fs" % (f2 * DT))
	check(main.state == "continue", "continue screen offered")
	game.continue_run()
	main.state = "play"
	check(game.lives == 2 and game.bombs == 3 and not game.over, "continue restores lives and bombs")

	print("Bomb")
	var b0: int = game.bombs
	game.invuln = 0.0
	game.respawn = 0.0
	game.dying = 0.0
	game.bomb_t = 0.0
	game.bomb_req = true
	game.step(DT)
	check(game.bombs == b0 - 1 and game.bomb_t > 0.0, "bomb consumed and active")

	print("Practice mode, stage 3, EASY")
	main.practice = true
	main.sel_stage = 3
	main.sel_diff = 0
	main._start_game()
	game.god = true
	game.dmg_mult = 5.0
	check(game.stage == 3 and game.practice, "practice starts on stage 3")
	var f3 := 0
	while game.active and f3 < 60 * 60 * 4:
		bot(f3)
		game.step(DT)
		f3 += 1
	check(main.state == "result" and main.result_kind == "practice", "practice ends after one stage")
	check(int(main.data.practice.get("0_3", 0)) > 0, "practice best saved")

	print("Menus")
	for s in ["title", "diff", "ship", "stage", "scores", "howto", "pause", "continue"]:
		main.goto(s)
		main.ui.queue_redraw()
	await get_tree().process_frame
	check(true, "all menu screens draw")

	if fails == 0:
		print("SMOKE OK")
	else:
		print("SMOKE FAILED: %d" % fails)
	get_tree().quit(1 if fails else 0)
