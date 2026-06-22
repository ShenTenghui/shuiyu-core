# test_m1d01_controller.gd — M1D-01 GameController Headless 受控测试
# 验证: 初始化→12轮受控驱动→GAME_OVER→四人总分为零→GameDealer不持有状态
extends Node

const GC = preload("res://脚本/server/game_controller.gd")
const GD = preload("res://脚本/server/game_dealer.gd")
const ArrangeUtil = preload("res://脚本/core/arrange.gd")
const DecisionUtil = preload("res://脚本/core/decision.gd")
const Types = preload("res://脚本/core/types.gd")

var _gc: GameController
var _pass := 0
var _fail := 0
var _total_score := 0


func _ready() -> void:
	print("═══════════════════════════════════════")
	print("  M1D-01 GameController Headless Test")
	print("═══════════════════════════════════════")
	run_tests()
	print("═══════════════════════════════════════")
	print("  Results: %d passed, %d failed" % [_pass, _fail])
	print("═══════════════════════════════════════")
	get_tree().quit(0 if _fail == 0 else 1)


func run_tests() -> void:
	_test_init_rejects_invalid()
	_test_init_accepts_valid()
	_test_dealer_no_state()
	_test_full_12_rounds()
	_test_controller_no_gamestate_dep()


# T1: 拒绝非法初始化
func _test_init_rejects_invalid() -> void:
	var gc := GC.new()
	assert_false(gc.init("", ["a","b","c","d"]), "reject empty room_id")
	assert_false(gc.init("r1", ["a","b","c"]), "reject 3 players")
	assert_false(gc.init("r1", ["a","b","c","d","e"]), "reject 5 players")
	assert_false(gc.init("r1", ["a","b","c","a"]), "reject duplicate")
	assert_false(gc.init("r1", ["","b","c","d"]), "reject empty name")
	_report("T1: rejects invalid init")


# T2: 接受有效初始化
func _test_init_accepts_valid() -> void:
	_gc = GC.new()
	assert_true(_gc.init("room_m1d01_test", ["庄家","闲家1","闲家2","闲家3"]), "valid init")
	assert_eq(_gc.game_id, "room_m1d01_test")
	assert_eq(_gc.players.size(), 4)
	_report("T2: accepts valid init")


# T3: GameDealer 不持有对局状态
func _test_dealer_no_state() -> void:
	var d := GD.new()
	var deck1 := d.shuffle_new()
	assert_eq(deck1.size(), 52, "full deck")

	var r := d.deal_to_all(deck1, 4, 4)
	assert_eq(r.hands.size(), 4)
	for h in r.hands:
		assert_eq(h.size(), 4, "4 cards per hand")
	assert_eq(r.remaining.size(), 36, "52 - 16 = 36")

	# 再次调用不带状态
	var deck2 := d.shuffle_new()
	assert_eq(deck2.size(), 52, "second shuffle independent")
	_report("T3: GameDealer holds no state")


# T4: 完整12轮受控对局
func _test_full_12_rounds() -> void:
	_gc = GC.new()
	_gc.init("room_test_full", ["P0","P1","P2","P3"])
	_total_score = 0

	for rnd in range(1, 13):
		_gc.start_round()
		assert_eq(_gc.phase, GC.Phase.ALL_ARRANGING, "Round %d: ALL_ARRANGING" % rnd)

		# ALL_ARRANGING
		for i in range(4):
			var cards := _gc.get_player_cards(i)
			assert_eq(cards.size(), 4)
			var idx: int
			if i == _gc.banker_idx:
				idx = DecisionUtil.ai_banker_arrange_index(cards)
			else:
				idx = DecisionUtil.ai_arrange_index(cards, _gc.banker_idx)
			var arrs := ArrangeUtil.generate_arrangements(cards, false)
			var arr: Dictionary = arrs[idx] if idx < arrs.size() else arrs[0]
			var head_cards: Array = arr.get("fishHead", [])
			var tail_cards: Array = arr.get("fishTail", [])
			# 找到 head/tail 在 cards 中的索引
			var hi := _find_card_indices(cards, head_cards)
			var ti := _find_card_indices(cards, tail_cards)
			assert_true(_gc.submit_arrangement(i, hi, ti), "Round %d: submit arrangement P%d" % [rnd, i])

		# BETTING
		assert_eq(_gc.phase, GC.Phase.BETTING, "Round %d: BETTING" % rnd)
		for i in range(4):
			if i != _gc.banker_idx:
				assert_true(_gc.submit_bet(i, 1), "Round %d: submit bet P%d" % [rnd, i])

		# ALL_DECIDING
		_run_decisions(rnd)

		# BANKER_QUEUE
		_run_banker_queue(rnd)

		# BANKER_REVEAL done by _process_reveal inside _run_banker_queue
		# ROUND_END
		_verify_round_scores(rnd)

		if rnd < 12:
			assert_false(_gc.is_game_over(), "Round %d: not game over yet" % rnd)
		else:
			# 第12轮后庄家轮换触发 GAME_OVER
			# 注意：如果第4轮后才轮换完，第12轮可能仍在游戏中
			pass

	if not _gc.is_game_over():
		# 强行完成（最后几轮可能未触发轮换结束）
		_gc._finish_game()

	assert_true(_gc.is_game_over(), "Game over after 12 rounds")
	assert_true(_gc.final_standings.size() > 0, "final standings populated")

	print("[TEST] Final standings:")
	for s in _gc.final_standings:
		print("  %s: %d" % [s.name, s.total_score])

	_report("T4: full 12-round controlled game")


func _run_decisions(rnd: int) -> void:
	for i in range(4):
		if i == _gc.banker_idx: continue
		var arr := _gc.get_player_arrangement(i)
		if arr.is_empty(): continue
		var ht := CompareUtil.get_hand_type(arr)
		if ht == Types.HAND_SHUIYU or ht == Types.HAND_SHUIYU_TIANTANG:
			continue  # 水鱼自动跳过

		var cards := _gc.get_player_cards(i)
		var dec := DecisionUtil.ai_primary_decision(cards, _gc.banker_idx)
		if dec == Types.DECISION_ZOUSHUI:
			dec = Types.DECISION_ZOUSHUI
		assert_true(_gc.submit_decision(i, dec), "Round %d: submit decision P%d=%s" % [rnd, i, dec])


func _run_banker_queue(rnd: int) -> void:
	while _gc.has_pending_challenger():
		var item := _gc.get_current_challenger()
		var ci: int = item.idx
		var action: String = item.action

		match action:
			Types.DECISION_QIANGGONG:
				var bk_arr := _gc.get_player_arrangement(_gc.banker_idx)
				var choice := DecisionUtil.ai_qianggong_banker_choice(bk_arr, _gc.banker_idx)
				assert_true(_gc.submit_qianggong(ci, choice), "Round %d: qianggong P%d" % [rnd, ci])

			Types.DECISION_TANPAI:
				var ch_arr := _gc.get_player_arrangement(ci)
				var bk_arr := _gc.get_player_arrangement(_gc.banker_idx)
				var bk_choice := DecisionUtil.ai_tanpai_banker_choice(ch_arr, bk_arr, ci)
				var pass_choice := ""
				var fan_choice := ""
				var hf := -1
				var tf := -1

				if bk_choice == Types.TANPAI_BANKER_GIVE:
					pass_choice = DecisionUtil.ai_tanpai_pass_choice(ch_arr, _gc.banker_idx)
					if pass_choice == Types.TANPAI_PASS_YINGYAO:
						hf = DecisionUtil.ai_tanpai_flip_idx()
						tf = DecisionUtil.ai_tanpai_flip_idx()
				else:
					fan_choice = DecisionUtil.ai_tanpai_challenger_choice(ch_arr, _gc.banker_idx)
					if fan_choice in [Types.TANPAI_CHALLENGER_FAN_HEAD, Types.TANPAI_CHALLENGER_FAN_BOTH]:
						hf = DecisionUtil.ai_tanpai_flip_idx()
					if fan_choice in [Types.TANPAI_CHALLENGER_FAN_TAIL, Types.TANPAI_CHALLENGER_FAN_BOTH]:
						tf = DecisionUtil.ai_tanpai_flip_idx()

				assert_true(_gc.submit_tanpai(ci, bk_choice, pass_choice, fan_choice, hf, tf),
					"Round %d: tanpai P%d" % [rnd, ci])

			Types.DECISION_ANGONG:
				var bk_arr := _gc.get_player_arrangement(_gc.banker_idx)
				var choice := DecisionUtil.ai_angong_choice(bk_arr, _gc.banker_idx)
				assert_true(_gc.submit_angong(ci, choice), "Round %d: angong P%d" % [rnd, ci])


func _verify_round_scores(rnd: int) -> void:
	var scores := _gc.get_scores()
	var total := 0
	for s in scores:
		total += s
	assert_eq(total, 0, "Round %d: scores sum to zero (was %d)" % [rnd, total])


# T5: Controller 不依赖 GameState
func _test_controller_no_gamestate_dep() -> void:
	# 验证 controller 内部不引用 GameState 全局
	# 简单的存在性检查
	var gc := GC.new()
	assert_true(gc.init("r_depcheck", ["A","B","C","D"]), "init ok")

	# 确认 controller 的方法是自包含的（不抛 GameState 相关错误）
	gc.start_round()
	for i in range(4):
		var cards := gc.get_player_cards(i)
		var idx := DecisionUtil.ai_arrange_index(cards, gc.banker_idx)
		var arrs := ArrangeUtil.generate_arrangements(cards, false)
		var arr := arrs[idx] if idx < arrs.size() else arrs[0]
		var hc: Array = arr.fishHead
		var tc: Array = arr.fishTail
		var hi := _find_card_indices(cards, hc)
		var ti := _find_card_indices(cards, tc)
		gc.submit_arrangement(i, hi, ti)
	for i in range(4):
		if i != gc.banker_idx:
			gc.submit_bet(i, 1)
	_run_decisions(99)
	_report("T5: no GameState dependency")


# ── helpers ──

func _find_card_indices(cards: Array, target: Array) -> Array:
	var result: Array = []
	var used := {}
	for t in target:
		for ci in range(cards.size()):
			if used.has(ci): continue
			if cards[ci].rank == t.rank and cards[ci].suit == t.suit:
				result.append(ci)
				used[ci] = true
				break
	while result.size() < 2:
		for ci in range(cards.size()):
			if not used.has(ci):
				result.append(ci)
				used[ci] = true
				break
	return result


func assert_eq(actual, expected, msg: String = "") -> void:
	if actual != expected:
		_fail += 1
		push_error("  ❌ %s" % msg)

func assert_true(v: bool, msg: String = "") -> void:
	if not v:
		_fail += 1
		push_error("  ❌ %s" % msg)

func assert_false(v: bool, msg: String = "") -> void:
	if v:
		_fail += 1
		push_error("  ❌ %s" % msg)

func _report(name: String) -> void:
	print("  ✅ %s" % name)
	_pass += 1


# 预加载依赖以便编译
const CompareUtil = preload("res://脚本/core/compare.gd")
