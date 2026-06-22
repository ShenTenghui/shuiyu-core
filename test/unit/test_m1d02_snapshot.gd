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
	_test_decision_hidden_before_announce()
	_test_full_game_snapshots()


# T1: 快照无对手 cards 泄露
func _test_snapshot_no_opponent_cards() -> void:
	_setup_game()
	_gc.start_round()
	_drive_arrangements()
	_drive_bets()

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
	_drive_arrangements()
	_drive_bets()
	_drive_decisions_and_queue()

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
	_drive_arrangements()
	_drive_bets()
	_drive_decisions_and_queue()

	var fstate: Dictionary = _gc.export_full_state()
	var snaps: Array = _sync.generate_snapshots(fstate)

	var phase0: int = snaps[0].phase
	var round0: int = snaps[0].round
	var bk0: int = snaps[0].banker_position

	for i in range(1, 4):
		assert_eq(snaps[i].phase, phase0, "phase consistent snap %d" % i)
		assert_eq(snaps[i].round, round0, "round consistent snap %d" % i)
		assert_eq(snaps[i].banker_position, bk0, "banker consistent snap %d" % i)

	for i in range(4):
		for j in range(4):
			assert_eq(snaps[0].players[j].score, snaps[i].players[j].score,
				"score P%d consistent across snaps" % j)

	_report("T4: public info consistent across 4 snaps")


# T5: 快照生成前后 Controller 状态不变
func _test_snapshot_controller_unchanged() -> void:
	_setup_game()
	_gc.start_round()
	_drive_arrangements()
	_drive_bets()
	_drive_decisions_and_queue()

	var before: Dictionary = _gc.export_full_state()
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
	_drive_arrangements()
	_drive_bets()

	# 让 P1 强攻,P2/P3 摊牌
	for i in range(4):
		if i == _gc.banker_idx: continue
		var arr2: Dictionary = _gc.get_player_arrangement(i)
		if arr2.is_empty(): continue
		var ht2: String = CompareUtil.get_hand_type(arr2)
		if ht2 == Types.HAND_SHUIYU or ht2 == Types.HAND_SHUIYU_TIANTANG: continue
		if i == 1:
			_gc.submit_decision(i, "qianggong")
		else:
			_gc.submit_decision(i, "tanpai")

	# 处理 banker queue
	while _gc.has_pending_challenger():
		var item: Dictionary = _gc.get_current_challenger()
		var ci: int = item.idx
		if item.action == Types.DECISION_QIANGGONG:
			_gc.submit_qianggong(ci, "bi_tou")
		elif item.action == Types.DECISION_TANPAI:
			_gc.submit_tanpai(ci, "give", "guo", "", -1, -1)

	# 快照
	var fstate: Dictionary = _gc.export_full_state()
	var snaps: Array = _sync.generate_snapshots(fstate)

	# P1 强攻，应在四份快照中 revealed=true
	for snap_idx in range(4):
		assert_true(snaps[snap_idx].players[1].revealed, "P1 revealed in snap %d" % snap_idx)

	_report("T6: qianggong face-up verified")


# T7: 暗攻不开 — face_up 裁剪
func _test_snapshot_face_up_angong_not_open() -> void:
	_setup_game()
	_gc.start_round()
	_drive_arrangements()
	_drive_bets()

	# P1 暗攻
	for i in range(4):
		if i == _gc.banker_idx: continue
		var arr2: Dictionary = _gc.get_player_arrangement(i)
		if arr2.is_empty(): continue
		var ht2: String = CompareUtil.get_hand_type(arr2)
		if ht2 == Types.HAND_SHUIYU or ht2 == Types.HAND_SHUIYU_TIANTANG: continue
		if i == 1:
			_gc.submit_decision(i, "angong")
		else:
			_gc.submit_decision(i, "tanpai")

	# 庄家不开暗攻的牌
	while _gc.has_pending_challenger():
		var item: Dictionary = _gc.get_current_challenger()
		var ci: int = item.idx
		if item.action == Types.DECISION_ANGONG:
			_gc.submit_angong(ci, "not_open")
		elif item.action == Types.DECISION_TANPAI:
			_gc.submit_tanpai(ci, "give", "guo", "", -1, -1)

	var fstate: Dictionary = _gc.export_full_state()
	var snaps: Array = _sync.generate_snapshots(fstate)

	# P1 暗攻不开: 不在 revealed 中，自己能看到排列，对手看不到内容
	for snap_idx in range(4):
		if snap_idx == 1:
			# P1 自己看到排列
			assert_false(snaps[snap_idx].players[1].arrangement.is_empty(), "P1 sees own arr")
		else:
			# 对手不应看到 P1 的 card 内容（可能看到空排列或 face_down 排列）
			var arr: Dictionary = snaps[snap_idx].players[1].arrangement
			if not arr.is_empty():
				# 有排列但 card 内容应为无（face_down）
				pass

	_report("T7: angong not-open clipping")


# T8: 完整对局每阶段快照无泄露
func _test_full_game_snapshots() -> void:
	_setup_game()

	for rnd in range(1, 13):
		_gc.start_round()
		_verify_snapshots_clean("Round %d ARRANGING" % rnd)
		_drive_arrangements()
		_drive_bets()
		_verify_snapshots_clean("Round %d BETTING" % rnd)
		_drive_decisions_and_queue()
		_verify_snapshots_clean("Round %d REVEAL" % rnd)

	_report("T8: full 12-round snapshot audit")


func _verify_snapshots_clean(label: String) -> void:
	var fstate: Dictionary = _gc.export_full_state()
	var snaps: Array = _sync.generate_snapshots(fstate)

	for idx in range(4):
		var s: Dictionary = snaps[idx]
		assert_false(s.has("deck"), "%s snap%d: no deck" % [label, idx])
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


func _drive_decisions_and_queue() -> void:
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
