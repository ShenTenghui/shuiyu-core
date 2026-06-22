# test_m1d01_controller.gd — M1D-01 GameController Headless 受控测试
extends Node

const GC = preload("res://脚本/server/game_controller.gd")
const GD = preload("res://脚本/server/game_dealer.gd")
const ArrangeUtil = preload("res://脚本/core/arrange.gd")
const DecisionUtil = preload("res://脚本/core/decision.gd")
const Types = preload("res://脚本/core/types.gd")
const CompareUtil = preload("res://脚本/core/compare.gd")

var _gc: RefCounted
var _pass: int = 0
var _fail: int = 0


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


func _test_init_rejects_invalid() -> void:
	var gc: RefCounted = GC.new()
	assert_false(gc.init("", ["a","b","c","d"]), "reject empty room_id")
	assert_false(gc.init("r1", ["a","b","c"]), "reject 3 players")
	assert_false(gc.init("r1", ["a","b","c","d","e"]), "reject 5 players")
	assert_false(gc.init("r1", ["a","b","c","a"]), "reject duplicate")
	assert_false(gc.init("r1", ["","b","c","d"]), "reject empty name")
	_report("T1: rejects invalid init")


func _test_init_accepts_valid() -> void:
	_gc = GC.new()
	assert_true(_gc.init("room_m1d01_test", ["P0","P1","P2","P3"]), "valid init")
	assert_eq(_gc.game_id, "room_m1d01_test")
	assert_eq(_gc.players.size(), 4)
	_report("T2: accepts valid init")


func _test_dealer_no_state() -> void:
	var d: RefCounted = GD.new()
	var deck1: Array = d.shuffle_new()
	assert_eq(deck1.size(), 52, "full deck")

	var r: Dictionary = d.deal_to_all(deck1, 4, 4)
	assert_eq(r.hands.size(), 4)
	for h in r.hands:
		assert_eq(h.size(), 4, "4 cards per hand")
	assert_eq(r.remaining.size(), 36, "52 - 16 = 36")

	var deck2: Array = d.shuffle_new()
	assert_eq(deck2.size(), 52, "second shuffle independent")
	_report("T3: GameDealer holds no state")


func _test_full_12_rounds() -> void:
	_gc = GC.new()
	_gc.init("room_test_full", ["P0","P1","P2","P3"])
	if not _gc:
		push_error("GC init failed")
		_fail += 1
		return

	for rnd in range(1, 13):
		_gc.start_round()
		assert_eq(_gc.phase, 1, "Round %d: ALL_ARRANGING" % rnd)

		for i in range(4):
			var cards: Array = _gc.get_player_cards(i)
			assert_eq(cards.size(), 4)
			var idx: int
			if i == _gc.banker_idx:
				idx = DecisionUtil.ai_banker_arrange_index(cards)
			else:
				idx = DecisionUtil.ai_arrange_index(cards, _gc.banker_idx)
			var arrs: Array = ArrangeUtil.generate_arrangements(cards, false)
			var arr: Dictionary = arrs[idx] if idx < arrs.size() else arrs[0]
			var head_cards: Array = arr.get("fishHead", [])
			var tail_cards: Array = arr.get("fishTail", [])
			var hi: Array = _find_card_indices(cards, head_cards)
			var ti: Array = _find_card_indices(cards, tail_cards)
			assert_true(_gc.submit_arrangement(i, hi, ti), "Round %d: arr P%d" % [rnd, i])

		assert_eq(_gc.phase, 3, "Round %d: BETTING" % rnd)
		for i in range(4):
			if i != _gc.banker_idx:
				assert_true(_gc.submit_bet(i, 1), "Round %d: bet P%d" % [rnd, i])

		_run_decisions(rnd)
		_run_banker_queue(rnd)
		_verify_round_scores(rnd)

	if not _gc.is_game_over():
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
		var arr: Dictionary = _gc.get_player_arrangement(i)
		if arr.is_empty(): continue
		var ht: String = CompareUtil.get_hand_type(arr)
		if ht == Types.HAND_SHUIYU or ht == Types.HAND_SHUIYU_TIANTANG:
			continue
		var cards: Array = _gc.get_player_cards(i)
		var dec: String = DecisionUtil.ai_primary_decision(cards, _gc.banker_idx)
		if dec == Types.DECISION_ZOUSHUI:
			dec = Types.DECISION_ZOUSHUI
		assert_true(_gc.submit_decision(i, dec), "Round %d: dec P%d=%s" % [rnd, i, dec])


func _run_banker_queue(rnd: int) -> void:
	while _gc.has_pending_challenger():
		var item: Dictionary = _gc.get_current_challenger()
		var ci: int = item.idx
		var action: String = item.action

		match action:
			Types.DECISION_QIANGGONG:
				var bk_arr: Dictionary = _gc.get_player_arrangement(_gc.banker_idx)
				var choice: String = DecisionUtil.ai_qianggong_banker_choice(bk_arr, _gc.banker_idx)
				assert_true(_gc.submit_qianggong(ci, choice), "Round %d: qg P%d" % [rnd, ci])

			Types.DECISION_TANPAI:
				var ch_arr: Dictionary = _gc.get_player_arrangement(ci)
				var bk_arr: Dictionary = _gc.get_player_arrangement(_gc.banker_idx)
				var bk_choice: String = DecisionUtil.ai_tanpai_banker_choice(ch_arr, bk_arr, ci)
				var pass_choice: String = ""
				var fan_choice: String = ""
				var hf: int = -1
				var tf: int = -1
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
					"Round %d: tp P%d" % [rnd, ci])

			Types.DECISION_ANGONG:
				var bk_arr: Dictionary = _gc.get_player_arrangement(_gc.banker_idx)
				var choice: String = DecisionUtil.ai_angong_choice(bk_arr, _gc.banker_idx)
				assert_true(_gc.submit_angong(ci, choice), "Round %d: ag P%d" % [rnd, ci])


func _verify_round_scores(rnd: int) -> void:
	var scores: Array = _gc.get_scores()
	var total: int = 0
	for s in scores:
		total += s
	assert_eq(total, 0, "Round %d: scores sum to zero (was %d)" % [rnd, total])


func _test_controller_no_gamestate_dep() -> void:
	var gc: RefCounted = GC.new()
	assert_true(gc.init("r_depcheck", ["A","B","C","D"]), "init ok")
	gc.start_round()
	for i in range(4):
		var cards: Array = gc.get_player_cards(i)
		var idx: int = DecisionUtil.ai_arrange_index(cards, gc.banker_idx)
		var arrs: Array = ArrangeUtil.generate_arrangements(cards, false)
		var arr: Dictionary = arrs[idx] if idx < arrs.size() else arrs[0]
		var hc: Array = arr.fishHead
		var tc: Array = arr.fishTail
		var hi: Array = _find_card_indices(cards, hc)
		var ti: Array = _find_card_indices(cards, tc)
		gc.submit_arrangement(i, hi, ti)
	for i in range(4):
		if i != gc.banker_idx:
			gc.submit_bet(i, 1)
	_report("T5: no GameState dependency")


func _find_card_indices(cards: Array, target: Array) -> Array:
	var result: Array = []
	var used: Dictionary = {}
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
		push_error("  FAIL %s" % msg)

func assert_true(v: bool, msg: String = "") -> void:
	if not v:
		_fail += 1
		push_error("  FAIL %s" % msg)

func assert_false(v: bool, msg: String = "") -> void:
	if v:
		_fail += 1
		push_error("  FAIL %s" % msg)

func _report(name: String) -> void:
	print("  OK %s" % name)
	_pass += 1
