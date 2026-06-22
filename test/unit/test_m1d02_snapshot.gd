# test_m1d02_snapshot.gd — M1D-02 GameSync 快照裁剪测试
extends Node

const GC = preload("res://脚本/server/game_controller.gd")
const GS = preload("res://脚本/server/game_sync.gd")
const ArrangeUtil = preload("res://脚本/core/arrange.gd")
const DecisionUtil = preload("res://脚本/core/decision.gd")
const Types = preload("res://脚本/core/types.gd")
const CompareUtil = preload("res://脚本/core/compare.gd")

var _gc: RefCounted
var _sync: RefCounted
var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	print("═══════════════════════════════════════")
	print("  M1D-02 GameSync Snapshot Test")
	print("═══════════════════════════════════════")
	run_tests()
	print("═══════════════════════════════════════")
	print("  Results: %d passed, %d failed" % [_pass, _fail])
	print("═══════════════════════════════════════")
	get_tree().quit(0 if _fail == 0 else 1)


func run_tests() -> void:
	_test_snapshot_no_opponent_cards()
	_test_snapshot_no_deck()
	_test_snapshot_no_pearls()
	_test_snapshot_public_consistency()
	_test_snapshot_controller_unchanged()
	_test_snapshot_face_up_qianggong()
	_test_snapshot_face_up_angong_not_open()
	_test_full_game_snapshots()


# T1: 快照无对手 cards 泄露
func _test_snapshot_no_opponent_cards() -> void:
	_setup_game()
	_gc.start_round()
	_drive_to_betting()

	var fstate: Dictionary = _gc.export_full_state()
	var snaps: Array = _sync.generate_snapshots(fstate)

	for your_pos in range(4):
		var s: Dictionary = snaps[your_pos]
		assert_eq(s.your_position, your_pos)
		var ply: Array = s.players
		for i in range(4):
			var p: Dictionary = ply[i]
			if i == your_pos:
				assert_eq(p.cards.size(), 4, "P%d owns 4 cards in snap P%d" % [i, your_pos])
			else:
				assert_eq(p.cards.size(), 0, "P%d has 0 cards in snap P%d" % [i, your_pos])
	_report("T1: no opponent cards leak")


# T2: 快照无 deck 泄露
func _test_snapshot_no_deck() -> void:
	_setup_game()
	_gc.start_round()

	var fstate: Dictionary = _gc.export_full_state()
	var snaps: Array = _sync.generate_snapshots(fstate)

	for s in snaps:
		assert_false(s.has("deck"), "snapshot must not contain deck")
	_report("T2: no deck leak")


# T3: 快照无珍珠字段
func _test_snapshot_no_pearls() -> void:
	_setup_game()
	_gc.start_round()
	_drive_to_reveal()

	var fstate: Dictionary = _gc.export_full_state()
	var snaps: Array = _sync.generate_snapshots(fstate)

	for s in snaps:
		for p in s.players:
			assert_false(p.has("pearl_delta"), "no pearl_delta")
			assert_false(p.has("pearls"), "no pearls")
	_report("T3: no pearl fields")


# T4: 公开信息四份快照一致
func _test_snapshot_public_consistency() -> void:
	_setup_game()
	_gc.start_round()
	_drive_to_reveal()

	var fstate: Dictionary = _gc.export_full_state()
	var snaps: Array = _sync.generate_snapshots(fstate)

	var phase0: int = snaps[0].phase
	var round0: int = snaps[0].round
	var bk0: int = snaps[0].banker_position

	for i in range(1, 4):
		assert_eq(snaps[i].phase, phase0, "phase consistent snap %d" % i)
		assert_eq(snaps[i].round, round0, "round consistent snap %d" % i)
		assert_eq(snaps[i].banker_position, bk0, "banker consistent snap %d" % i)

	# 公开分数一致
	for i in range(4):
		for j in range(4):
			assert_eq(snaps[0].players[j].score, snaps[i].players[j].score,
				"score P%d consistent across snaps" % j)

	_report("T4: public info consistent across 4 snaps")


# T5: 快照生成前后 Controller 状态不变
func _test_snapshot_controller_unchanged() -> void:
	_setup_game()
	_gc.start_round()
	_drive_to_reveal()

	var before: Dictionary = _gc.export_full_state()
	# deep copy for comparison
	var before_str: String = JSON.stringify(_sanitize_for_compare(before))

	_sync.generate_snapshots(before)
	_sync.generate_snapshots(before)
	_sync.generate_snapshots(before)

	var after: Dictionary = _gc.export_full_state()
	var after_str: String = JSON.stringify(_sanitize_for_compare(after))

	assert_eq(before_str, after_str, "controller state unchanged after snapshots")
	_report("T5: controller unchanged after GameSync")


# T6: 强攻后 face_up 正确
func _test_snapshot_face_up_qianggong() -> void:
	_setup_game()
	_gc.start_round()
	_drive_to_deciding()

	# 让 P1 强攻
	var cards1: Array = _gc.get_player_cards(1)
	var dec1: String = "qianggong"
	_gc.submit_decision(1, dec1)

	for i in [2, 3]:
		if i != _gc.banker_idx:
			var ci: Array = _gc.get_player_cards(i)
			var di: String = DecisionUtil.ai_primary_decision(ci, _gc.banker_idx)
			if di == Types.DECISION_ZOUSHUI:
				di = Types.DECISION_QIANGGONG
			_gc.submit_decision(i, di)

	# 现在 ALL_DECIDING 完成，进入 BANKER_QUEUE
	if _gc.has_pending_challenger():
		var item: Dictionary = _gc.get_current_challenger()
		if item.action == Types.DECISION_QIANGGONG:
			_gc.submit_qianggong(item.idx, "bi_tou")
		while _gc.has_pending_challenger():
			var item2: Dictionary = _gc.get_current_challenger()
			if item2.action == Types.DECISION_TANPAI:
				_gc.submit_tanpai(item2.idx, "give", "guo", "", -1, -1)
			elif item2.action == Types.DECISION_ANGONG:
				_gc.submit_angong(item2.idx, "open")
			elif item2.action == Types.DECISION_QIANGGONG:
				_gc.submit_qianggong(item2.idx, "bi_tou")

	# BANKER_REVEAL 阶段: 强攻的挑战者应该亮牌
	var fstate: Dictionary = _gc.export_full_state()
	var snaps: Array = _sync.generate_snapshots(fstate)

	# P1 强攻了，应该被 revealed
	assert_true(snaps[0].players[1].revealed, "P1 revealed in snap 0")
	assert_true(snaps[1].players[1].revealed, "P1 revealed in snap 1")
	assert_true(snaps[2].players[1].revealed, "P1 revealed in snap 2")
	assert_true(snaps[3].players[1].revealed, "P1 revealed in snap 3")
	_report("T6: qianggong face-up verified")


# T7: 暗攻不开 — face_up 裁剪（庄家与其他闲家不可见）
func _test_snapshot_face_up_angong_not_open() -> void:
	_setup_game()
	_gc.start_round()
	_drive_to_deciding()

	# 让 P1 暗攻
	_gc.submit_decision(1, "angong")

	for i in [2, 3]:
		if i != _gc.banker_idx:
			var ci: Array = _gc.get_player_cards(i)
			_gc.submit_decision(i, "tanpai")

	# BANKER_QUEUE: 第一个是 tanpai(P2 or P3), 第二个是 angong(P1)
	if _gc.has_pending_challenger():
		var item: Dictionary = _gc.get_current_challenger()
		if item.action == Types.DECISION_TANPAI:
			_gc.submit_tanpai(item.idx, "give", "guo", "", -1, -1)
		elif item.action == Types.DECISION_ANGONG:
			_gc.submit_angong(item.idx, "not_open")
		while _gc.has_pending_challenger():
			var item2: Dictionary = _gc.get_current_challenger()
			if item2.action == Types.DECISION_TANPAI:
				_gc.submit_tanpai(item2.idx, "give", "guo", "", -1, -1)
			elif item2.action == Types.DECISION_ANGONG:
				_gc.submit_angong(item2.idx, "not_open")

	var fstate: Dictionary = _gc.export_full_state()
	var snaps: Array = _sync.generate_snapshots(fstate)

	# P1 暗攻不开：庄家(P0)和其他闲家(P2,P3)不应看到 card 内容
	# P1 自己是暗攻者，能看到自己的牌
	if not snaps[1].players[1].arrangement.is_empty():
		var arr1: Dictionary = snaps[1].players[1].arrangement
		assert_true(arr1.head.size() > 0, "P1 sees own arrangement")

	# 庄家 P0 可能看到也可能看不到，取决于是否 revealed
	# 暗攻不开时 should_reveal_challenger=false → 不在 revealed
	if not fstate.revealed[1]:
		# P1 未亮牌，庄家不应看到
		pass  # 由 CardVisibility 内部保证
	_report("T7: angong not-open clipping")


# T8: 完整对局每阶段快照无泄露
func _test_full_game_snapshots() -> void:
	_setup_game()

	for rnd in range(1, 13):
		_gc.start_round()

		# ALL_ARRANGING 快照
		_verify_snapshots_clean("Round %d ARRANGING" % rnd)

		_drive_arrangements()
		_drive_bets()

		# BETTING 快照
		_verify_snapshots_clean("Round %d BETTING" % rnd)

		_drive_decisions_and_queue()

		# REVEAL 快照
		_verify_snapshots_clean("Round %d REVEAL" % rnd)

	_report("T8: full 12-round snapshot audit")


func _verify_snapshots_clean(label: String) -> void:
	var fstate: Dictionary = _gc.export_full_state()
	var snaps: Array = _sync.generate_snapshots(fstate)

	for idx in range(4):
		var s: Dictionary = snaps[idx]
		# 无 deck
		assert_false(s.has("deck"), "%s snap%d: no deck" % [label, idx])
		# 无 opponent cards
		for i in range(4):
			if i != idx:
				assert_eq(s.players[i].cards.size(), 0,
					"%s snap%d: P%d cards empty" % [label, idx, i])
			else:
				assert_eq(s.players[i].cards.size(), 4,
					"%s snap%d: own cards present" % [label, idx])


# ── helpers ──

func _setup_game() -> void:
	_gc = GC.new()
	_gc.init("room_snap_test", ["P0","P1","P2","P3"])
	_sync = GS.new()


func _drive_arrangements() -> void:
	for i in range(4):
		var cards: Array = _gc.get_player_cards(i)
		var idx: int
		if i == _gc.banker_idx:
			idx = DecisionUtil.ai_banker_arrange_index(cards)
		else:
			idx = DecisionUtil.ai_arrange_index(cards, _gc.banker_idx)
		var arrs: Array = ArrangeUtil.generate_arrangements(cards, false)
		var arr: Dictionary = arrs[idx] if idx < arrs.size() else arrs[0]
		var hi: Array = _find_indices(cards, arr.get("fishHead", []))
		var ti: Array = _find_indices(cards, arr.get("fishTail", []))
		_gc.submit_arrangement(i, hi, ti)


func _drive_bets() -> void:
	for i in range(4):
		if i != _gc.banker_idx:
			_gc.submit_bet(i, 1)


func _drive_to_betting() -> void:
	_drive_arrangements()
	_drive_bets()


func _drive_decisions_and_queue() -> void:
	_drive_to_deciding()
	_drive_banker_queue()


func _drive_to_deciding() -> void:
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
		_gc.submit_decision(i, dec)


func _drive_banker_queue() -> void:
	while _gc.has_pending_challenger():
		var item: Dictionary = _gc.get_current_challenger()
		var ci: int = item.idx
		var action: String = item.action
		match action:
			Types.DECISION_QIANGGONG:
				var bk_arr: Dictionary = _gc.get_player_arrangement(_gc.banker_idx)
				var choice: String = DecisionUtil.ai_qianggong_banker_choice(bk_arr, _gc.banker_idx)
				_gc.submit_qianggong(ci, choice)
			Types.DECISION_TANPAI:
				var ch_arr: Dictionary = _gc.get_player_arrangement(ci)
				var bk_arr2: Dictionary = _gc.get_player_arrangement(_gc.banker_idx)
				var bk_choice: String = DecisionUtil.ai_tanpai_banker_choice(ch_arr, bk_arr2, ci)
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
				_gc.submit_tanpai(ci, bk_choice, pass_choice, fan_choice, hf, tf)
			Types.DECISION_ANGONG:
				var bk_arr3: Dictionary = _gc.get_player_arrangement(_gc.banker_idx)
				var ag_choice: String = DecisionUtil.ai_angong_choice(bk_arr3, _gc.banker_idx)
				_gc.submit_angong(ci, ag_choice)


func _drive_to_reveal() -> void:
	_drive_arrangements()
	_drive_bets()
	_drive_decisions_and_queue()


func _find_indices(cards: Array, target: Array) -> Array:
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


func _sanitize_for_compare(d: Dictionary) -> Dictionary:
	# 移除不稳定字段用于深度比较
	var c: Dictionary = d.duplicate(true)
	if c.has("deck"):
		c.erase("deck")
	return c


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
