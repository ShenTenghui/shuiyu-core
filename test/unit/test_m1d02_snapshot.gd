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
	_test_qianggong_all_face_up()
	_test_angong_not_open_all_face_down()
	_test_tanpai_fan_head_partial_reveal()
	_test_decision_hidden_before_announce()
	_test_full_game_snapshots()


# T1
func _test_snapshot_no_opponent_cards() -> void:
	_setup_game()
	_gc.start_round()
	_drive_arrangements()
	_drive_bets()
	var snaps: Array = _sync.generate_snapshots(_gc.export_full_state())
	for your_pos in range(4):
		var ply: Array = snaps[your_pos].players
		for i in range(4):
			if i == your_pos:
				assert_eq(ply[i].cards.size(), 4, "P%d owns 4 cards" % i)
			else:
				assert_eq(ply[i].cards.size(), 0, "P%d has 0 cards" % i)
	_report("T1: no opponent cards leak")


# T2
func _test_snapshot_no_deck() -> void:
	_setup_game()
	_gc.start_round()
	var snaps: Array = _sync.generate_snapshots(_gc.export_full_state())
	for s in snaps:
		assert_false(s.has("deck"), "no deck")
	_report("T2: no deck leak")


# T3
func _test_snapshot_no_pearls() -> void:
	_setup_game()
	_gc.start_round()
	_drive_arrangements(); _drive_bets(); _drive_decisions_and_queue()
	var snaps: Array = _sync.generate_snapshots(_gc.export_full_state())
	for s in snaps:
		for p in s.players:
			assert_false(p.has("pearl_delta"), "no pearl_delta")
			assert_false(p.has("pearls"), "no pearls")
	_report("T3: no pearl fields")


# T4
func _test_snapshot_public_consistency() -> void:
	_setup_game()
	_gc.start_round()
	_drive_arrangements(); _drive_bets(); _drive_decisions_and_queue()
	var snaps: Array = _sync.generate_snapshots(_gc.export_full_state())
	var p0: int = snaps[0].phase
	var r0: int = snaps[0].round
	var b0: int = snaps[0].banker_position
	for i in range(1, 4):
		assert_eq(snaps[i].phase, p0, "phase")
		assert_eq(snaps[i].round, r0, "round")
		assert_eq(snaps[i].banker_position, b0, "banker")
	for j in range(4):
		for i in range(4):
			assert_eq(snaps[0].players[j].score, snaps[i].players[j].score, "score P%d" % j)
	_report("T4: public info consistent")


# T5
func _test_snapshot_controller_unchanged() -> void:
	_setup_game()
	_gc.start_round()
	_drive_arrangements(); _drive_bets(); _drive_decisions_and_queue()
	var before: String = JSON.stringify(_sanitize(_gc.export_full_state()))
	_sync.generate_snapshots(_gc.export_full_state())
	_sync.generate_snapshots(_gc.export_full_state())
	var after: String = JSON.stringify(_sanitize(_gc.export_full_state()))
	assert_eq(before, after, "controller unchanged")
	_report("T5: controller unchanged")


# T6 (P1): 强攻后 — 全部 face_up + rank/suit 可见
func _test_qianggong_all_face_up() -> void:
	_setup_game()
	_gc.start_round()
	_drive_arrangements(); _drive_bets()
	for i in range(4):
		if i == _gc.banker_idx: continue
		var arr: Dictionary = _gc.get_player_arrangement(i)
		if arr.is_empty(): continue
		var ht: String = CompareUtil.get_hand_type(arr)
		if ht == Types.HAND_SHUIYU or ht == Types.HAND_SHUIYU_TIANTANG: continue
		_gc.submit_decision(i, "qianggong" if i == 1 else "tanpai")

	while _gc.has_pending_challenger():
		var qi: Dictionary = _gc.get_current_challenger()
		if qi.action == Types.DECISION_QIANGGONG:
			_gc.submit_qianggong(qi.idx, "bi_tou")
		elif qi.action == Types.DECISION_TANPAI:
			_gc.submit_tanpai(qi.idx, "give", "guo", "", -1, -1)

	var snaps: Array = _sync.generate_snapshots(_gc.export_full_state())

	# P1 强攻后，四份快照均 revealed=true + 所有牌 face_up=true + rank/suit 存在
	for snap_idx in range(4):
		assert_true(snaps[snap_idx].players[1].revealed, "P1 revealed snap %d" % snap_idx)
		var arr: Dictionary = snaps[snap_idx].players[1].arrangement
		assert_false(arr.is_empty(), "P1 arr visible snap %d" % snap_idx)
		var head: Array = arr.head
		var tail: Array = arr.tail
		for card in head + tail:
			assert_true(card.face_up, "face_up snap %d" % snap_idx)
			assert_true(card.has("rank") and not card.rank.is_empty(), "rank present")
			assert_true(card.has("suit") and not card.suit.is_empty(), "suit present")
	_report("T6: qianggong all face_up + rank/suit visible")


# T7 (P1): 暗攻庄家不开 → 对手快照全部 face_down 且无 rank/suit
func _test_angong_not_open_all_face_down() -> void:
	_setup_game()
	_gc.start_round()
	_drive_arrangements(); _drive_bets()
	for i in range(4):
		if i == _gc.banker_idx: continue
		var arr: Dictionary = _gc.get_player_arrangement(i)
		if arr.is_empty(): continue
		var ht: String = CompareUtil.get_hand_type(arr)
		if ht == Types.HAND_SHUIYU or ht == Types.HAND_SHUIYU_TIANTANG: continue
		_gc.submit_decision(i, "angong" if i == 1 else "tanpai")

	while _gc.has_pending_challenger():
		var qi: Dictionary = _gc.get_current_challenger()
		if qi.action == Types.DECISION_ANGONG:
			_gc.submit_angong(qi.idx, "not_open")
		elif qi.action == Types.DECISION_TANPAI:
			_gc.submit_tanpai(qi.idx, "give", "guo", "", -1, -1)

	var snaps: Array = _sync.generate_snapshots(_gc.export_full_state())

	# P1 自己的快照：全部 face_up + rank/suit 可见
	var own: Dictionary = snaps[1].players[1].arrangement
	assert_false(own.is_empty(), "P1 own arr visible")
	for card in own.head + own.tail:
		assert_true(card.face_up, "P1 own face_up")
		assert_true(card.has("rank") and not card.rank.is_empty(), "P1 own rank")
		assert_true(card.has("suit") and not card.suit.is_empty(), "P1 own suit")

	# 对手快照 (P0, P2, P3): P1 的牌全部 face_down 且无 rank/suit
	for snap_idx in [0, 2, 3]:
		var arr: Dictionary = snaps[snap_idx].players[1].arrangement
		assert_false(arr.is_empty(), "P1 arr visible (announced) snap %d" % snap_idx)
		for card in arr.head + arr.tail:
			assert_false(card.face_up, "face_down snap %d" % snap_idx)
			assert_false(card.has("rank"), "no rank snap %d" % snap_idx)
			assert_false(card.has("suit"), "no suit snap %d" % snap_idx)

	_report("T7: angong not-open — own face_up, opponents face_down no rank/suit")


# T8 (P1): tanpai + not_give + fan_head → BANKER_QUEUE 阶段部分亮牌
# 在庄家队列处理 P1 后但未完成全部队列时，被反门 face_up+rank/suit，隐藏门 face_down+无 rank/suit，desc 不泄露
func _test_tanpai_fan_head_partial_reveal() -> void:
	_setup_game()
	_gc.start_round()
	_drive_arrangements(); _drive_bets()
	# 全部提交 tanpai，让 P1 在队列中排第一
	for i in range(4):
		if i == _gc.banker_idx: continue
		var arr: Dictionary = _gc.get_player_arrangement(i)
		if arr.is_empty(): continue
		var ht: String = CompareUtil.get_hand_type(arr)
		if ht == Types.HAND_SHUIYU or ht == Types.HAND_SHUIYU_TIANTANG: continue
		_gc.submit_decision(i, "tanpai")

	# 只处理 P1（队列第一项）：not_give + fan_head + head_flip=0
	# 不处理 P2/P3 → phase 保持 BANKER_QUEUE
	var qi: Dictionary = _gc.get_current_challenger()
	assert_true(qi.action == Types.DECISION_TANPAI, "first item is tanpai")
	_gc.submit_tanpai(qi.idx, "not_give", "", "fan_head", 0, -1)

	# BANKER_QUEUE 阶段生成快照
	var snaps: Array = _sync.generate_snapshots(_gc.export_full_state())
	var ci: int = qi.idx

	# 自己的快照：全部 face_up+rank/suit+desc
	var own: Dictionary = snaps[ci].players[ci].arrangement
	for card in own.head + own.tail:
		assert_true(card.face_up, "own face_up")
		assert_true(card.has("rank") and not card.rank.is_empty(), "own rank present")
	assert_true(own.has("desc") and not own.desc.is_empty(), "own desc present")

	# 对手快照 (非 ci): 被反门有 face_up+rank/suit，隐藏门 face_down+无 rank/suit，desc 为空
	for snap_idx in range(4):
		if snap_idx == ci: continue
		var arr: Dictionary = snaps[snap_idx].players[ci].arrangement
		assert_false(arr.is_empty(), "arr visible snap %d" % snap_idx)

		# 至少有一张 face_up（被反门）
		var has_face_up: bool = false
		for card in arr.head + arr.tail:
			if card.face_up:
				has_face_up = true
				assert_true(card.has("rank") and not card.rank.is_empty(), "face_up has rank")
				assert_true(card.has("suit") and not card.suit.is_empty(), "face_up has suit")
			else:
				assert_false(card.has("rank"), "face_down no rank snap %d" % snap_idx)
				assert_false(card.has("suit"), "face_down no suit snap %d" % snap_idx)
		assert_true(has_face_up, "at least one face_up card snap %d" % snap_idx)

		# desc 必须为空（部分可见时不能泄露隐藏门牌型）
		assert_false(arr.has("desc") and not arr.desc.is_empty(), "desc empty snap %d" % snap_idx)

	_report("T8: tanpai fan_head — partial reveal, hidden door no rank/suit, desc empty")


# T9: 决策宣告前隐藏
func _test_decision_hidden_before_announce() -> void:
	_setup_game()
	_gc.start_round()
	_drive_arrangements(); _drive_bets()
	_gc.submit_decision(1, "qianggong")
	_gc.submit_decision(2, "tanpai")

	var snaps: Array = _sync.generate_snapshots(_gc.export_full_state())
	assert_eq(snaps[0].players[1].decision, "", "P0: P1 decision hidden")
	assert_eq(snaps[0].players[2].decision, "", "P0: P2 decision hidden")
	assert_eq(snaps[3].players[1].decision, "", "P3: P1 decision hidden")
	assert_eq(snaps[1].players[1].decision, "qianggong", "P1 own visible")
	assert_eq(snaps[2].players[2].decision, "tanpai", "P2 own visible")

	_gc.submit_decision(3, "tanpai")
	while _gc.has_pending_challenger():
		var qi: Dictionary = _gc.get_current_challenger()
		if qi.action == Types.DECISION_QIANGGONG:
			_gc.submit_qianggong(qi.idx, "bi_tou")
		else:
			_gc.submit_tanpai(qi.idx, "give", "guo", "", -1, -1)

	var snaps2: Array = _sync.generate_snapshots(_gc.export_full_state())
	for snap_idx in range(4):
		if snap_idx != 1:
			assert_eq(snaps2[snap_idx].players[1].decision, "qianggong", "after announce P1")
		if snap_idx != 2:
			assert_eq(snaps2[snap_idx].players[2].decision, "tanpai", "after announce P2")
	_report("T9: decision hidden before announce")


# T10: 全量 12 轮审计
func _test_full_game_snapshots() -> void:
	_setup_game()
	for rnd in range(1, 13):
		_gc.start_round()
		_verify_clean("Round %d ARRANGING" % rnd)
		_drive_arrangements(); _drive_bets()
		_verify_clean("Round %d BETTING" % rnd)
		_drive_decisions_and_queue()
		_verify_clean("Round %d REVEAL" % rnd)
	_report("T10: full 12-round snapshot audit")


func _verify_clean(label: String) -> void:
	var snaps: Array = _sync.generate_snapshots(_gc.export_full_state())
	for idx in range(4):
		var s: Dictionary = snaps[idx]
		assert_false(s.has("deck"), "%s snap%d: no deck" % [label, idx])
		for i in range(4):
			if i != idx:
				assert_eq(s.players[i].cards.size(), 0, "%s snap%d: P%d cards 0" % [label, idx, i])
			else:
				assert_eq(s.players[i].cards.size(), 4, "%s snap%d: own cards present" % [label, idx])


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
		if ht == Types.HAND_SHUIYU or ht == Types.HAND_SHUIYU_TIANTANG: continue
		_gc.submit_decision(i, DecisionUtil.ai_primary_decision(_gc.get_player_cards(i), _gc.banker_idx))

	while _gc.has_pending_challenger():
		var qi: Dictionary = _gc.get_current_challenger()
		match qi.action:
			Types.DECISION_QIANGGONG:
				var ba: Dictionary = _gc.get_player_arrangement(_gc.banker_idx)
				_gc.submit_qianggong(qi.idx, DecisionUtil.ai_qianggong_banker_choice(ba, _gc.banker_idx))
			Types.DECISION_TANPAI:
				var ca: Dictionary = _gc.get_player_arrangement(qi.idx)
				var ba2: Dictionary = _gc.get_player_arrangement(_gc.banker_idx)
				var bc: String = DecisionUtil.ai_tanpai_banker_choice(ca, ba2, qi.idx)
				var pc: String = ""; var fc: String = ""; var hf: int = -1; var tf: int = -1
				if bc == Types.TANPAI_BANKER_GIVE:
					pc = DecisionUtil.ai_tanpai_pass_choice(ca, _gc.banker_idx)
					if pc == Types.TANPAI_PASS_YINGYAO:
						hf = DecisionUtil.ai_tanpai_flip_idx(); tf = DecisionUtil.ai_tanpai_flip_idx()
				else:
					fc = DecisionUtil.ai_tanpai_challenger_choice(ca, _gc.banker_idx)
					if fc in [Types.TANPAI_CHALLENGER_FAN_HEAD, Types.TANPAI_CHALLENGER_FAN_BOTH]: hf = DecisionUtil.ai_tanpai_flip_idx()
					if fc in [Types.TANPAI_CHALLENGER_FAN_TAIL, Types.TANPAI_CHALLENGER_FAN_BOTH]: tf = DecisionUtil.ai_tanpai_flip_idx()
				_gc.submit_tanpai(qi.idx, bc, pc, fc, hf, tf)
			Types.DECISION_ANGONG:
				var ba3: Dictionary = _gc.get_player_arrangement(_gc.banker_idx)
				_gc.submit_angong(qi.idx, DecisionUtil.ai_angong_choice(ba3, _gc.banker_idx))


func _find_indices(cards: Array, target: Array) -> Array:
	var result: Array = []
	var used: Dictionary = {}
	for t in target:
		for ci in range(cards.size()):
			if used.has(ci): continue
			if cards[ci].rank == t.rank and cards[ci].suit == t.suit:
				result.append(ci); used[ci] = true; break
	while result.size() < 2:
		for ci in range(cards.size()):
			if not used.has(ci):
				result.append(ci); used[ci] = true; break
	return result


func _sanitize(d: Dictionary) -> Dictionary:
	var c: Dictionary = d.duplicate(true)
	if c.has("deck"): c.erase("deck")
	return c


func assert_eq(actual, expected, msg: String = "") -> void:
	if actual != expected: _fail += 1; push_error("  FAIL %s" % msg)

func assert_true(v: bool, msg: String = "") -> void:
	if not v: _fail += 1; push_error("  FAIL %s" % msg)

func assert_false(v: bool, msg: String = "") -> void:
	if v: _fail += 1; push_error("  FAIL %s" % msg)

func _report(name: String) -> void:
	print("  OK %s" % name); _pass += 1
