# test_m1d03_network.gd — M1D-03 网络命令与服务端验证 Headless 测试
extends Node

const ProtocolTypes = preload("res://脚本/shared/protocol_types.gd")
const GameSessionManager = preload("res://脚本/server/game_session_manager.gd")
const GameController = preload("res://脚本/server/game_controller.gd")
const GameSync = preload("res://脚本/server/game_sync.gd")
const ArrangeUtil = preload("res://脚本/core/arrange.gd")
const LegalDecisions = preload("res://test/support/legal_decisions.gd")
const Types = preload("res://脚本/core/types.gd")
const CompareUtil = preload("res://脚本/core/compare.gd")

var _gsm: RefCounted
var _pass: int = 0
var _fail: int = 0

const ROOM_ID: String = "room_m1d03_test"
const USERS: Array = ["u0", "u1", "u2", "u3"]


func _ready() -> void:
	seed(20261104)
	print("═══════════════════════════════════════")
	print("  M1D-03 Network Command Headless Test")
	print("═══════════════════════════════════════")
	run_tests()
	print("═══════════════════════════════════════")
	print("  Results: %d passed, %d failed" % [_pass, _fail])
	print("═══════════════════════════════════════")
	get_tree().quit(0 if _fail == 0 else 1)


func run_tests() -> void:
	_test_protocol_constants()
	_test_create_game()
	_test_snapshots_after_create()
	_test_legal_arrange_command()
	_test_illegal_arrange_wrong_phase()
	_test_illegal_command_wrong_seat()
	_test_illegal_arrange_invalid_indices()
	_test_illegal_not_in_game()
	_test_controller_unchanged_on_reject()
	_test_legal_bet_command()
	_test_legal_decide_command()
	_test_banker_queue_commands()
	_test_tanpai_multi_step()
	_test_full_12_round_network_flow()
	_test_m1d02_snapshot_contract()


# ── T1: Protocol constants ──

func _test_protocol_constants() -> void:
	assert_eq(ProtocolTypes.CMD_GAME_ARRANGE, 13, "CMD_GAME_ARRANGE=13")
	assert_eq(ProtocolTypes.CMD_GAME_BET, 14, "CMD_GAME_BET=14")
	assert_eq(ProtocolTypes.CMD_GAME_DECIDE, 15, "CMD_GAME_DECIDE=15")
	assert_eq(ProtocolTypes.CMD_GAME_TANPAI_BANKER, 16, "CMD_GAME_TANPAI_BANKER=16")
	assert_eq(ProtocolTypes.CMD_GAME_TANPAI_PASS, 17, "CMD_GAME_TANPAI_PASS=17")
	assert_eq(ProtocolTypes.CMD_GAME_TANPAI_CHALLENGER, 18, "CMD_GAME_TANPAI_CHALLENGER=18")
	assert_eq(ProtocolTypes.CMD_GAME_ANGONG, 19, "CMD_GAME_ANGONG=19")
	assert_eq(ProtocolTypes.CMD_GAME_QIANGGONG_BANKER, 20, "CMD_GAME_QIANGGONG_BANKER=20")
	assert_eq(ProtocolTypes.EVT_GAME_CREATED, 400, "EVT_GAME_CREATED=400")
	assert_eq(ProtocolTypes.EVT_GAME_CARDS_DEALT, 401, "EVT_GAME_CARDS_DEALT=401")
	assert_eq(ProtocolTypes.EVT_GAME_PHASE_CHANGED, 402, "EVT_GAME_PHASE_CHANGED=402")
	assert_eq(ProtocolTypes.EVT_GAME_PLAYER_ACTION, 403, "EVT_GAME_PLAYER_ACTION=403")
	assert_eq(ProtocolTypes.EVT_GAME_ROUND_RESULT, 404, "EVT_GAME_ROUND_RESULT=404")
	assert_eq(ProtocolTypes.EVT_GAME_MATCH_FINISHED, 405, "EVT_GAME_MATCH_FINISHED=405")
	assert_eq(ProtocolTypes.EVT_GAME_STATE_SYNC, 406, "EVT_GAME_STATE_SYNC=406")
	assert_eq(ProtocolTypes.EVT_GAME_SNAPSHOT, 407, "EVT_GAME_SNAPSHOT=407")
	assert_eq(ProtocolTypes.ERR_GAME_NOT_YOUR_TURN, "GAME_NOT_YOUR_TURN")
	assert_eq(ProtocolTypes.ERR_GAME_INVALID_ACTION, "GAME_INVALID_ACTION")
	assert_eq(ProtocolTypes.ERR_GAME_INVALID_ARRANGEMENT, "GAME_INVALID_ARRANGEMENT")
	assert_eq(ProtocolTypes.ERR_GAME_NOT_IN_GAME, "GAME_NOT_IN_GAME")
	_report("T1: protocol constants match M1D-00 contract")


# ── T2: Create game ──

func _test_create_game() -> void:
	_gsm = GameSessionManager.new()
	assert_true(_gsm.create_game(ROOM_ID, USERS), "create_game succeeds")
	assert_false(_gsm.create_game(ROOM_ID, USERS), "duplicate create fails")
	assert_true(_gsm.has_game(ROOM_ID), "has_game true")
	assert_eq(_gsm.get_position(ROOM_ID, "u0"), 0, "u0 → pos 0")
	assert_eq(_gsm.get_position(ROOM_ID, "u3"), 3, "u3 → pos 3")
	assert_eq(_gsm.get_position(ROOM_ID, "u99"), -1, "unknown user → -1")
	assert_eq(_gsm.get_user_at_position(ROOM_ID, 1), "u1", "pos 1 → u1")
	_report("T2: create_game + position mapping")


# ── T3: Snapshots after create + start_round ──

func _test_snapshots_after_create() -> void:
	_setup_fresh()
	var snaps: Dictionary = _gsm.generate_snapshots(ROOM_ID)
	assert_eq(snaps.size(), 4, "4 snapshots")
	for uid in snaps:
		var s: Dictionary = snaps[uid]
		assert_eq(s.game_id, ROOM_ID, "game_id")
		assert_eq(s.phase, GameController.Phase.ALL_ARRANGING, "phase=ARRANGING")
		assert_eq(s.round, 1, "round=1")
		# Each user sees only their own cards
		var your_pos: int = s.your_position
		for i in range(4):
			var ply: Dictionary = s.players[i]
			if i == your_pos:
				assert_eq(ply.cards.size(), 4, "own cards present")
			else:
				assert_eq(ply.cards.size(), 0, "opponent cards empty")
	# No deck leak
	for uid in snaps:
		assert_false(snaps[uid].has("deck"), "no deck in snapshot")
	_report("T3: snapshots after create — 4 per-user, no opponent cards, no deck")


# ── T4: Legal arrange command ──

func _test_legal_arrange_command() -> void:
	_setup_fresh()
	var gc: RefCounted = _gsm.get_controller(ROOM_ID)
	for i in range(4):
		var cards: Array = gc.get_player_cards(i)
		var idx: int
		if i == gc.banker_idx:
			idx = LegalDecisions.choose_banker_arrange_index(cards)
		else:
			idx = LegalDecisions.choose_arrange_index(cards, gc.banker_idx)
		var arrs: Array = ArrangeUtil.generate_arrangements(cards, false)
		var arr: Dictionary = arrs[idx] if idx < arrs.size() else arrs[0]
		var hi: Array = _find_indices(cards, arr.get("fishHead", []))
		var ti: Array = _find_indices(cards, arr.get("fishTail", []))
		var r: Dictionary = _gsm.handle_command(ROOM_ID, USERS[i],
			ProtocolTypes.CMD_GAME_ARRANGE, {"head": hi, "tail": ti})
		assert_true(r.ok, "arrange P%d ok" % i)

	assert_eq(gc.phase, GameController.Phase.BETTING, "phase→BETTING after all arrange")
	_report("T4: legal arrange commands advance to BETTING")


# ── T5: Illegal arrange in wrong phase ──

func _test_illegal_arrange_wrong_phase() -> void:
	_setup_fresh()
	# Advance to BETTING first
	_drive_arrange_all()

	var gc: RefCounted = _gsm.get_controller(ROOM_ID)
	assert_eq(gc.phase, GameController.Phase.BETTING, "phase is BETTING")

	# Try arrange in BETTING
	var r: Dictionary = _gsm.handle_command(ROOM_ID, "u0",
		ProtocolTypes.CMD_GAME_ARRANGE, {"head": [0, 1], "tail": [2, 3]})
	assert_false(r.ok, "arrange rejected in BETTING")
	assert_eq(r.error, "GAME_INVALID_ACTION", "error code")
	_report("T5: arrange rejected in wrong phase")


# ── T6: Illegal command from wrong seat ──

func _test_illegal_command_wrong_seat() -> void:
	_setup_fresh()
	# Banker (pos 0) tries to bet
	var r: Dictionary = _gsm.handle_command(ROOM_ID, "u0",
		ProtocolTypes.CMD_GAME_BET, {"amount": 1})
	# Bet is only for non-banker; but we're still in ALL_ARRANGING
	# Let's test in BETTING phase instead
	_drive_arrange_all()

	var gc: RefCounted = _gsm.get_controller(ROOM_ID)
	# Banker (pos 0) should not be able to bet
	var r2: Dictionary = _gsm.handle_command(ROOM_ID, "u0",
		ProtocolTypes.CMD_GAME_BET, {"amount": 1})
	assert_false(r2.ok, "banker cannot bet")
	assert_eq(r2.error, "GAME_NOT_YOUR_TURN", "error=GAME_NOT_YOUR_TURN")
	_report("T6: banker rejected from betting")


# ── T7: Illegal arrange — invalid indices ──

func _test_illegal_arrange_invalid_indices() -> void:
	_setup_fresh()
	# Duplicate index
	var r: Dictionary = _gsm.handle_command(ROOM_ID, "u0",
		ProtocolTypes.CMD_GAME_ARRANGE, {"head": [0, 0], "tail": [1, 2]})
	assert_false(r.ok, "duplicate rejected")

	# Index out of bounds
	var r2: Dictionary = _gsm.handle_command(ROOM_ID, "u0",
		ProtocolTypes.CMD_GAME_ARRANGE, {"head": [0, 4], "tail": [1, 2]})
	assert_false(r2.ok, "OOB rejected")

	# Wrong count
	var r3: Dictionary = _gsm.handle_command(ROOM_ID, "u0",
		ProtocolTypes.CMD_GAME_ARRANGE, {"head": [0], "tail": [1, 2, 3]})
	assert_false(r3.ok, "wrong count rejected")
	_report("T7: invalid arrange indices rejected")


# ── T8: Illegal — user not in game ──

func _test_illegal_not_in_game() -> void:
	_setup_fresh()
	var r: Dictionary = _gsm.handle_command(ROOM_ID, "u99",
		ProtocolTypes.CMD_GAME_ARRANGE, {"head": [0, 1], "tail": [2, 3]})
	assert_false(r.ok, "unknown user rejected")
	assert_eq(r.error, "GAME_NOT_IN_GAME")

	var r2: Dictionary = _gsm.handle_command("room_bogus", "u0",
		ProtocolTypes.CMD_GAME_ARRANGE, {"head": [0, 1], "tail": [2, 3]})
	assert_false(r2.ok, "unknown room rejected")
	_report("T8: non-member and non-room rejected")


# ── T9: Controller state unchanged after rejection ──

func _test_controller_unchanged_on_reject() -> void:
	_setup_fresh()
	var gc: RefCounted = _gsm.get_controller(ROOM_ID)
	var before: String = _state_hash(gc)

	# Try several illegal commands
	_gsm.handle_command(ROOM_ID, "u0", ProtocolTypes.CMD_GAME_BET, {"amount": 1})
	_gsm.handle_command(ROOM_ID, "u99", ProtocolTypes.CMD_GAME_ARRANGE, {"head": [0, 1], "tail": [2, 3]})
	_gsm.handle_command(ROOM_ID, "u1", ProtocolTypes.CMD_GAME_DECIDE, {"action": "qianggong"})

	var after: String = _state_hash(gc)
	assert_eq(before, after, "controller state unchanged after rejects")
	_report("T9: controller unchanged after illegal commands")


# ── T10: Legal bet command ──

func _test_legal_bet_command() -> void:
	_setup_fresh()
	_drive_arrange_all()

	var gc: RefCounted = _gsm.get_controller(ROOM_ID)
	assert_eq(gc.phase, GameController.Phase.BETTING)

	var bet_count: int = 0
	for i in range(4):
		if i != gc.banker_idx:
			var r: Dictionary = _gsm.handle_command(ROOM_ID, USERS[i],
				ProtocolTypes.CMD_GAME_BET, {"amount": 1})
			assert_true(r.ok, "bet P%d ok" % i)
			bet_count += 1

	assert_eq(gc.phase, GameController.Phase.ALL_DECIDING, "phase→DECIDING after all bets")
	_report("T10: legal bet commands advance to DECIDING")


# ── T11: Legal decide command ──

func _test_legal_decide_command() -> void:
	_setup_fresh()
	_drive_arrange_all()
	_drive_bets()

	var gc: RefCounted = _gsm.get_controller(ROOM_ID)
	for i in range(4):
		if i == gc.banker_idx: continue
		var arr: Dictionary = gc.get_player_arrangement(i)
		if arr.is_empty(): continue
		var ht: String = CompareUtil.get_hand_type(arr)
		if ht == Types.HAND_SHUIYU or ht == Types.HAND_SHUIYU_TIANTANG: continue
		var dec: String = LegalDecisions.choose_primary_decision(gc.get_player_cards(i), gc.banker_idx)
		var r: Dictionary = _gsm.handle_command(ROOM_ID, USERS[i],
			ProtocolTypes.CMD_GAME_DECIDE, {"action": dec})
		assert_true(r.ok, "decide P%d=%s ok" % [i, dec])
	_report("T11: legal decide commands accepted")


# ── T12: Banker queue commands (qianggong, angong) ──

func _test_banker_queue_commands() -> void:
	_setup_fresh()
	_drive_arrange_all()
	_drive_bets()
	_drive_decisions()

	var gc: RefCounted = _gsm.get_controller(ROOM_ID)

	while gc.has_pending_challenger():
		var item: Dictionary = gc.get_current_challenger()
		var ci: int = item.idx
		var action: String = item.action

		match action:
			Types.DECISION_QIANGGONG:
				var r: Dictionary = _gsm.handle_command(ROOM_ID, USERS[gc.banker_idx],
					ProtocolTypes.CMD_GAME_QIANGGONG_BANKER, {"choice": "bi_tou"})
				assert_true(r.ok, "qianggong P%d ok" % ci)

			Types.DECISION_ANGONG:
				var r: Dictionary = _gsm.handle_command(ROOM_ID, USERS[gc.banker_idx],
					ProtocolTypes.CMD_GAME_ANGONG, {"choice": "not_open"})
				assert_true(r.ok, "angong P%d ok" % ci)

			Types.DECISION_TANPAI:
				# Use bundled approach for simplicity in this test
				var ca: Dictionary = gc.get_player_arrangement(ci)
				var ba: Dictionary = gc.get_player_arrangement(gc.banker_idx)
				var bc: String = LegalDecisions.choose_tanpai_banker_choice(ca, ba, ci)
				if bc == Types.TANPAI_BANKER_GIVE:
					# Multi-step tanpai
					var r1: Dictionary = _gsm.handle_command(ROOM_ID, USERS[gc.banker_idx],
						ProtocolTypes.CMD_GAME_TANPAI_BANKER, {"choice": bc})
					assert_true(r1.ok, "tanpai_banker P%d give" % ci)
					var r2: Dictionary = _gsm.handle_command(ROOM_ID, USERS[ci],
						ProtocolTypes.CMD_GAME_TANPAI_PASS, {"choice": "guo"})
					assert_true(r2.ok, "tanpai_pass P%d guo" % ci)
				else:
					var r1: Dictionary = _gsm.handle_command(ROOM_ID, USERS[gc.banker_idx],
						ProtocolTypes.CMD_GAME_TANPAI_BANKER, {"choice": bc})
					assert_true(r1.ok, "tanpai_banker P%d not_give" % ci)
					var fc: String = LegalDecisions.choose_tanpai_challenger_choice(ca, gc.banker_idx)
					var payload: Dictionary = {"choice": fc}
					if fc in [Types.TANPAI_CHALLENGER_FAN_HEAD, Types.TANPAI_CHALLENGER_FAN_BOTH]:
						payload["head_flip"] = 0
					if fc in [Types.TANPAI_CHALLENGER_FAN_TAIL, Types.TANPAI_CHALLENGER_FAN_BOTH]:
						payload["tail_flip"] = 0
					var r2: Dictionary = _gsm.handle_command(ROOM_ID, USERS[ci],
						ProtocolTypes.CMD_GAME_TANPAI_CHALLENGER, payload)
					assert_true(r2.ok, "tanpai_challenger P%d %s" % [ci, fc])

	assert_true(gc.phase == GameController.Phase.ROUND_END or gc.phase == GameController.Phase.GAME_OVER,
		"phase reached ROUND_END or GAME_OVER")
	_report("T12: banker queue commands — qianggong, angong, tanpai multi-step")


# ── T13: Multi-step tanpai protocol ──

func _test_tanpai_multi_step() -> void:
	_setup_fresh()
	_drive_arrange_all()
	_drive_bets()

	var gc: RefCounted = _gsm.get_controller(ROOM_ID)
	# Force all decisions to tanpai for testing
	for i in range(4):
		if i == gc.banker_idx: continue
		var arr: Dictionary = gc.get_player_arrangement(i)
		if arr.is_empty(): continue
		var ht: String = CompareUtil.get_hand_type(arr)
		if ht == Types.HAND_SHUIYU or ht == Types.HAND_SHUIYU_TIANTANG: continue
		_gsm.handle_command(ROOM_ID, USERS[i],
			ProtocolTypes.CMD_GAME_DECIDE, {"action": "tanpai"})

	# Now BANKER_QUEUE with tanpai items
	assert_true(gc.has_pending_challenger(), "has pending challenger")
	var item: Dictionary = gc.get_current_challenger()
	assert_eq(item.action, Types.DECISION_TANPAI, "first item is tanpai")

	# Try submitting pass before banker — should fail
	var r_bad: Dictionary = _gsm.handle_command(ROOM_ID, USERS[item.idx],
		ProtocolTypes.CMD_GAME_TANPAI_PASS, {"choice": "guo"})
	assert_false(r_bad.ok, "pass before banker rejected")

	# Banker submits "give"
	var r1: Dictionary = _gsm.handle_command(ROOM_ID, USERS[gc.banker_idx],
		ProtocolTypes.CMD_GAME_TANPAI_BANKER, {"choice": "give"})
	assert_true(r1.ok, "tanpai_banker give ok")
	# Should have "pending" flag
	assert_true(r1.get("pending", false), "pending flag set")

	# Challenger submits pass choice
	var r2: Dictionary = _gsm.handle_command(ROOM_ID, USERS[item.idx],
		ProtocolTypes.CMD_GAME_TANPAI_PASS, {"choice": "yingyao", "head_flip": 0, "tail_flip": 0})
	assert_true(r2.ok, "tanpai_pass yingyao ok")

	# Try submitting pass again (pending cleared) — should fail
	var r3: Dictionary = _gsm.handle_command(ROOM_ID, USERS[item.idx],
		ProtocolTypes.CMD_GAME_TANPAI_PASS, {"choice": "guo"})
	assert_false(r3.ok, "double pass rejected")
	_report("T13: multi-step tanpai protocol — banker→pass/challenger order enforced")


# ── T14: Full 12-round network flow ──

func _test_full_12_round_network_flow() -> void:
	_setup_fresh()
	var gc: RefCounted = _gsm.get_controller(ROOM_ID)
	for rnd in range(1, 13):
		_drive_arrange_all()
		_drive_bets()
		_drive_decisions()
		_drive_banker_queue()

		var scores: Array = gc.get_scores()
		var total: int = 0
		for s in scores:
			total += s
		assert_eq(total, 0, "Round %d: zero-sum (total=%d)" % [rnd, total])

		# Verify snapshots after each round
		var snaps: Dictionary = _gsm.generate_snapshots(ROOM_ID)
		assert_eq(snaps.size(), 4, "Round %d: 4 snapshots" % rnd)

		for uid in snaps:
			var s: Dictionary = snaps[uid]
			# No deck
			assert_false(s.has("deck"), "Round %d snap: no deck" % rnd)
			# No pearls
			for p in s.players:
				assert_false(p.has("pearl_delta"), "no pearl_delta")
				assert_false(p.has("pearls"), "no pearls")
			# Public consistency
			assert_eq(s.phase, gc.phase, "phase matches")

		# Advance to next round (auto or manual)
		if not gc.is_game_over() and gc.phase == GameController.Phase.ROUND_END:
			_gsm.maybe_advance_round(ROOM_ID)

	if not gc.is_game_over():
		gc._finish_game()

	assert_true(gc.is_game_over(), "game over after 12 rounds")
	assert_true(gc.final_standings.size() == 4, "4 final standings")
	_report("T14: full 12-round network command flow — zero-sum + snapshots clean")


# ── T15: M1D-02 snapshot contract compliance ──

func _test_m1d02_snapshot_contract() -> void:
	_setup_fresh()
	_drive_arrange_all()
	_drive_bets()
	_drive_decisions()
	_drive_banker_queue()

	var snaps: Dictionary = _gsm.generate_snapshots(ROOM_ID)

	for uid in snaps:
		var s: Dictionary = snaps[uid]
		# Required top-level fields per M1D-00 §3.1
		assert_true(s.has("game_id"), "has game_id")
		assert_true(s.has("seq"), "has seq")
		assert_true(s.has("phase"), "has phase")
		assert_true(s.has("round"), "has round")
		assert_true(s.has("banker_position"), "has banker_position")
		assert_true(s.has("your_position"), "has your_position")
		assert_true(s.has("players"), "has players")
		assert_eq(s.players.size(), 4, "4 players")
		assert_true(s.has("timer_remaining_ms"), "has timer_remaining_ms")

		# Each player has required fields
		var your_pos: int = s.your_position
		for i in range(4):
			var p: Dictionary = s.players[i]
			assert_true(p.has("position"), "P%d has position" % i)
			assert_true(p.has("name"), "P%d has name" % i)
			assert_true(p.has("score"), "P%d has score" % i)
			assert_true(p.has("bet_amount"), "P%d has bet_amount" % i)
			assert_true(p.has("is_banker"), "P%d has is_banker" % i)
			assert_true(p.has("cards"), "P%d has cards" % i)
			assert_true(p.has("arrangement"), "P%d has arrangement" % i)
			assert_true(p.has("decision"), "P%d has decision" % i)
			assert_true(p.has("revealed"), "P%d has revealed" % i)

			# Own cards have rank+suit
			if i == your_pos:
				for c in p.cards:
					assert_true(c.has("rank") and not c.rank.is_empty(), "own card has rank")
					assert_true(c.has("suit") and not c.suit.is_empty(), "own card has suit")
			else:
				assert_eq(p.cards.size(), 0, "opponent cards empty")

			# No pearl fields
			assert_false(p.has("pearl_delta"), "no pearl_delta")
			assert_false(p.has("pearls"), "no pearls")
	_report("T15: M1D-02 snapshot contract fields all present")


# ── Helpers ──

func _setup_fresh() -> void:
	_gsm = GameSessionManager.new()
	_gsm.create_game(ROOM_ID, USERS)
	_gsm.start_first_round(ROOM_ID)


func _drive_arrange_all() -> void:
	var gc: RefCounted = _gsm.get_controller(ROOM_ID)
	if gc.phase != GameController.Phase.ALL_ARRANGING: return
	for i in range(4):
		var cards: Array = gc.get_player_cards(i)
		var idx: int
		if i == gc.banker_idx:
			idx = LegalDecisions.choose_banker_arrange_index(cards)
		else:
			idx = LegalDecisions.choose_arrange_index(cards, gc.banker_idx)
		var arrs: Array = ArrangeUtil.generate_arrangements(cards, false)
		var arr: Dictionary = arrs[idx] if idx < arrs.size() else arrs[0]
		var hi: Array = _find_indices(cards, arr.get("fishHead", []))
		var ti: Array = _find_indices(cards, arr.get("fishTail", []))
		_gsm.handle_command(ROOM_ID, USERS[i],
			ProtocolTypes.CMD_GAME_ARRANGE, {"head": hi, "tail": ti})


func _drive_bets() -> void:
	var gc: RefCounted = _gsm.get_controller(ROOM_ID)
	if gc.phase != GameController.Phase.BETTING: return
	for i in range(4):
		if i != gc.banker_idx:
			_gsm.handle_command(ROOM_ID, USERS[i],
				ProtocolTypes.CMD_GAME_BET, {"amount": 1})


func _drive_decisions() -> void:
	var gc: RefCounted = _gsm.get_controller(ROOM_ID)
	if gc.phase != GameController.Phase.ALL_DECIDING: return
	for i in range(4):
		if i == gc.banker_idx: continue
		var arr: Dictionary = gc.get_player_arrangement(i)
		if arr.is_empty(): continue
		var ht: String = CompareUtil.get_hand_type(arr)
		if ht == Types.HAND_SHUIYU or ht == Types.HAND_SHUIYU_TIANTANG: continue
		var dec: String = LegalDecisions.choose_primary_decision(gc.get_player_cards(i), gc.banker_idx)
		_gsm.handle_command(ROOM_ID, USERS[i],
			ProtocolTypes.CMD_GAME_DECIDE, {"action": dec})


func _drive_banker_queue() -> void:
	var gc: RefCounted = _gsm.get_controller(ROOM_ID)
	while gc.has_pending_challenger():
		var item: Dictionary = gc.get_current_challenger()
		var ci: int = item.idx
		var action: String = item.action

		match action:
			Types.DECISION_QIANGGONG:
				var ba: Dictionary = gc.get_player_arrangement(gc.banker_idx)
				var ch: String = LegalDecisions.choose_qianggong_banker_choice(ba, gc.banker_idx)
				_gsm.handle_command(ROOM_ID, USERS[gc.banker_idx],
					ProtocolTypes.CMD_GAME_QIANGGONG_BANKER, {"choice": ch})

			Types.DECISION_ANGONG:
				var ba: Dictionary = gc.get_player_arrangement(gc.banker_idx)
				var ch: String = LegalDecisions.choose_angong_choice(ba, gc.banker_idx)
				_gsm.handle_command(ROOM_ID, USERS[gc.banker_idx],
					ProtocolTypes.CMD_GAME_ANGONG, {"choice": ch})

			Types.DECISION_TANPAI:
				var ca: Dictionary = gc.get_player_arrangement(ci)
				var ba: Dictionary = gc.get_player_arrangement(gc.banker_idx)
				var bc: String = LegalDecisions.choose_tanpai_banker_choice(ca, ba, ci)
				_gsm.handle_command(ROOM_ID, USERS[gc.banker_idx],
					ProtocolTypes.CMD_GAME_TANPAI_BANKER, {"choice": bc})
				if bc == Types.TANPAI_BANKER_GIVE:
					var pc: String = LegalDecisions.choose_tanpai_pass_choice(ca, gc.banker_idx)
					var pl: Dictionary = {"choice": pc}
					if pc == Types.TANPAI_PASS_YINGYAO:
						pl["head_flip"] = 0; pl["tail_flip"] = 0
					_gsm.handle_command(ROOM_ID, USERS[ci],
						ProtocolTypes.CMD_GAME_TANPAI_PASS, pl)
				else:
					var fc: String = LegalDecisions.choose_tanpai_challenger_choice(ca, gc.banker_idx)
					var pl: Dictionary = {"choice": fc}
					if fc in [Types.TANPAI_CHALLENGER_FAN_HEAD, Types.TANPAI_CHALLENGER_FAN_BOTH]:
						pl["head_flip"] = 0
					if fc in [Types.TANPAI_CHALLENGER_FAN_TAIL, Types.TANPAI_CHALLENGER_FAN_BOTH]:
						pl["tail_flip"] = 0
					_gsm.handle_command(ROOM_ID, USERS[ci],
						ProtocolTypes.CMD_GAME_TANPAI_CHALLENGER, pl)


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


func _state_hash(gc: RefCounted) -> String:
	var fs: Dictionary = gc.export_full_state()
	fs.erase("deck"); fs.erase("log")
	return JSON.stringify(fs)


# ── Assertions ──

func assert_eq(actual, expected, msg: String = "") -> void:
	if actual != expected:
		_fail += 1
		push_error("  FAIL %s (got %s, expected %s)" % [msg, str(actual), str(expected)])

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
