# game_controller.gd — 服务端权威对局状态机 (M1D-01)
# 唯一对局权威。所有对局数据只由本类写入。
class_name GameController
extends RefCounted

const _GD = preload("res://脚本/server/game_dealer.gd")
const Types = preload("res://脚本/core/types.gd")
const ArrangeUtil = preload("res://脚本/core/arrange.gd")
const CompareUtil = preload("res://脚本/core/compare.gd")
const ScoringUtil = preload("res://脚本/core/scoring.gd")
const CcwUtils = preload("res://脚本/core/ccw_utils.gd")
const EvaluateUtil = preload("res://脚本/core/evaluate.gd")

enum Phase {
	INIT = -1,
	ALL_ARRANGING = 1,
	CROWN = 2,
	BETTING = 3,
	ALL_DECIDING = 4,
	BANKER_QUEUE = 5,
	BANKER_REVEAL = 9,
	ROUND_END = 10,
	GAME_OVER = 12,
}

var game_id: String = ""
var phase: int = Phase.INIT
var current_round: int = 0
var banker_idx: int = 0
var players: Array[Dictionary] = []
var deck: Array = []
var round_results: Array = []
var final_standings: Array = []
var log: Array[String] = []

var _dealer: RefCounted
var _banker_queue: Array = []
var _queue_idx: int = 0
var _ch_state: Dictionary = {}
var _revealed: Array[bool] = []
var _announced: Array[bool] = []
var _round: int = 0
var _games_completed: int = 0
var _rounds_per_cycle: int = 0
var _pending_arrange: int = 0
var _pending_bet: int = 0
var _pending_decide: int = 0


func init(room_id: String, player_names: Array) -> bool:
	if room_id.is_empty(): return false
	if player_names.size() != 4: return false
	var seen: Dictionary = {}
	for nm in player_names:
		if nm.is_empty() or seen.has(nm): return false
		seen[nm] = true

	game_id = room_id
	_dealer = _GD.new()
	_rounds_per_cycle = floori(52.0 / 16.0)

	players.clear()
	for i in range(4):
		players.append({
			"name": player_names[i],
			"position": i,
			"score": 0,
			"cards": [],
			"arrangement": {},
			"bet_amount": 0,
			"decision": "",
			"is_banker": (i == 0),
		})
	banker_idx = 0
	_games_completed = 0

	_add_log("GameController init: %s, players=%s" % [room_id, str(player_names)])
	return true


func start_round() -> void:
	_round += 1
	current_round = _round
	_revealed = [false, false, false, false]
	_announced = [false, false, false, false]
	_ch_state.clear()
	_banker_queue.clear()
	_queue_idx = 0
	round_results.clear()

	for p in players:
		p.cards.clear()
		p.arrangement = {}
		p.decision = ""
		p.bet_amount = 0

	if deck.size() < 16:
		deck = _dealer.shuffle_new()
		_add_log("重新洗牌")

	var deal_r: Dictionary = _dealer.deal_to_all(deck, 4, 4)
	deck = deal_r.remaining
	for i in range(4):
		players[i].cards = deal_r.hands[i]

	phase = Phase.ALL_ARRANGING
	_pending_arrange = 4
	_add_log("第 %d 轮发牌完成" % _round)


func submit_arrangement(player_idx: int, head_indices: Array, tail_indices: Array) -> bool:
	if phase != Phase.ALL_ARRANGING: return false
	if player_idx < 0 or player_idx >= 4: return false
	if head_indices.size() != 2 or tail_indices.size() != 2: return false
	if players[player_idx].cards.size() < 4: return false
	if _pending_arrange <= 0: return false

	var cards: Array = players[player_idx].cards
	var all_idx: Array = head_indices + tail_indices
	if all_idx.size() != 4: return false
	var seen: Dictionary = {}
	for idx in all_idx:
		if idx < 0 or idx >= 4 or seen.has(idx): return false
		seen[idx] = true

	var arrs: Array = ArrangeUtil.generate_arrangements(cards, false)
	var found: int = -1
	for ai in range(arrs.size()):
		var a: Dictionary = arrs[ai]
		var fh: Array = a.get("fishHead", [])
		var ft: Array = a.get("fishTail", [])
		var ok: bool = true
		for hi in range(2):
			if not _card_eq(fh[hi], cards[head_indices[hi]]):
				ok = false; break
		if not ok: continue
		for ti in range(2):
			if not _card_eq(ft[ti], cards[tail_indices[ti]]):
				ok = false; break
		if ok:
			found = ai; break

	if found < 0:
		var chosen: Dictionary = _build_arrangement(cards, head_indices, tail_indices)
		players[player_idx].arrangement = chosen
	else:
		players[player_idx].arrangement = arrs[found]

	_add_log("%s 排列完成" % players[player_idx].name)
	_pending_arrange -= 1
	if _pending_arrange <= 0:
		_advance_from_arranging()
	return true


func _advance_from_arranging() -> void:
	phase = Phase.CROWN
	_add_log("加冕")
	phase = Phase.BETTING
	_pending_bet = 0
	for i in range(4):
		if i != banker_idx:
			_pending_bet += 1
	_add_log("--- 下注阶段 ---")


func submit_bet(player_idx: int, amount: int) -> bool:
	if phase != Phase.BETTING: return false
	if player_idx == banker_idx: return false
	if amount < 1: return false

	players[player_idx].bet_amount = clampi(amount, 1, 10)
	_add_log("%s 下注 %d" % [players[player_idx].name, players[player_idx].bet_amount])
	_pending_bet -= 1
	if _pending_bet <= 0:
		_advance_from_betting()
	return true


func _advance_from_betting() -> void:
	phase = Phase.ALL_DECIDING
	_pending_decide = 0

	for i in range(4):
		if i == banker_idx: continue
		var arr: Dictionary = players[i].arrangement
		if arr.is_empty(): continue
		var ht: String = CompareUtil.get_hand_type(arr)
		var cs: Dictionary = _get_cs(i, players[i].cards)
		if ht == Types.HAND_SHUIYU or ht == Types.HAND_SHUIYU_TIANTANG:
			cs.skipped = true
			_ch_state[i] = cs
			_add_log("%s 组成水鱼" % players[i].name)
		else:
			_pending_decide += 1

	if _pending_decide == 0:
		_advance_from_deciding()
	else:
		_add_log("等待 %d 名闲家决策" % _pending_decide)


func submit_decision(player_idx: int, action: String) -> bool:
	if phase != Phase.ALL_DECIDING: return false
	if player_idx == banker_idx: return false
	var arr: Dictionary = players[player_idx].arrangement
	if arr.is_empty(): return false

	var cs: Dictionary = _get_cs(player_idx, players[player_idx].cards)
	var ht: String = CompareUtil.get_hand_type(arr)
	var is_dz: bool = (ht == Types.HAND_DOUBLE_ZERO)

	if cs.skipped: return false

	if is_dz and action == Types.DECISION_ZOUSHUI:
		cs.doubleZeroChoice = Types.DOUBLE_ZERO_ZOUSHUI
		_add_log("%s 双零直接走水" % players[player_idx].name)
	else:
		if is_dz:
			cs.doubleZeroChoice = Types.DOUBLE_ZERO_BU_ZOUSHUI
		cs.decision = action
		_add_log("%s 选择 %s" % [players[player_idx].name, action])

	_ch_state[player_idx] = cs
	_pending_decide -= 1
	if _pending_decide <= 0:
		_advance_from_deciding()
	return true


func _advance_from_deciding() -> void:
	var order: Array = CcwUtils.get_challenger_order(banker_idx)
	for i in order:
		var cs: Dictionary = _ch_state.get(i, {})
		if cs.is_empty(): continue
		if cs.skipped:
			_add_log("%s 组成了水鱼" % players[i].name)
			_announced[i] = true
		elif cs.get("doubleZeroChoice") == Types.DOUBLE_ZERO_ZOUSHUI:
			_add_log("%s 选择双零直接走水" % players[i].name)
			_announced[i] = true
		elif cs.get("decision", "") != "":
			_add_log("%s 选择%s" % [players[i].name, cs.decision])
			_announced[i] = true

	var bk_arr: Dictionary = players[banker_idx].arrangement
	if not bk_arr.is_empty():
		var bk_ht: String = CompareUtil.get_hand_type(bk_arr)
		if bk_ht == Types.HAND_SHUIYU or bk_ht == Types.HAND_SHUIYU_TIANTANG:
			_revealed[banker_idx] = true
			_add_log("庄家水鱼！直接亮牌结算")
			_process_reveal()
			return

	_build_banker_queue()
	if _banker_queue.is_empty():
		_add_log("无需庄家处理")
		_process_reveal()
	else:
		phase = Phase.BANKER_QUEUE
		_queue_idx = 0


func _build_banker_queue() -> void:
	_banker_queue.clear()
	var order: Array = CcwUtils.get_challenger_order(banker_idx)
	for action in [Types.DECISION_TANPAI, Types.DECISION_ANGONG, Types.DECISION_QIANGGONG]:
		for i in order:
			var cs: Dictionary = _ch_state.get(i, {})
			if cs.is_empty() or cs.skipped: continue
			if cs.get("doubleZeroChoice") == Types.DOUBLE_ZERO_ZOUSHUI: continue
			if cs.decision == action:
				_banker_queue.append({"idx": i, "action": action})


func has_pending_challenger() -> bool:
	return phase == Phase.BANKER_QUEUE and _queue_idx < _banker_queue.size()


func get_current_challenger() -> Dictionary:
	if not has_pending_challenger(): return {}
	var item: Dictionary = _banker_queue[_queue_idx]
	var i: int = item.idx
	return {"idx": i, "name": players[i].name, "action": item.action}


func submit_qianggong(challenger_idx: int, banker_choice: String) -> bool:
	if phase != Phase.BANKER_QUEUE: return false
	var item: Dictionary = _current_item()
	if item.is_empty() or item.idx != challenger_idx: return false
	if item.action != Types.DECISION_QIANGGONG: return false

	var cs: Dictionary = _ch_state[challenger_idx]
	cs.qianggong_banker_choice = banker_choice
	_ch_state[challenger_idx] = cs
	_revealed[challenger_idx] = true
	_add_log("庄家选择 %s" % banker_choice)
	_queue_idx += 1
	_check_queue_done()
	return true


func submit_tanpai(challenger_idx: int, banker_give: String, pass_choice: String, fan_choice: String, head_flip: int = -1, tail_flip: int = -1) -> bool:
	if phase != Phase.BANKER_QUEUE: return false
	var item: Dictionary = _current_item()
	if item.is_empty() or item.idx != challenger_idx: return false
	if item.action != Types.DECISION_TANPAI: return false

	var cs: Dictionary = _ch_state[challenger_idx]
	cs.tanpaiBankerChoice = banker_give

	if banker_give == Types.TANPAI_BANKER_GIVE:
		cs.tanpaiPassChoice = pass_choice
		if pass_choice == Types.TANPAI_PASS_YINGYAO:
			cs.tanpai_head_flip_idx = maxi(0, head_flip)
			cs.tanpai_tail_flip_idx = maxi(0, tail_flip)
	else:
		cs.tanpaiChallengerChoice = fan_choice
		if fan_choice == Types.TANPAI_CHALLENGER_FAN_HEAD:
			cs.tanpai_head_flip_idx = maxi(0, head_flip)
		elif fan_choice == Types.TANPAI_CHALLENGER_FAN_TAIL:
			cs.tanpai_tail_flip_idx = maxi(0, tail_flip)
		elif fan_choice == Types.TANPAI_CHALLENGER_FAN_BOTH:
			cs.tanpai_head_flip_idx = maxi(0, head_flip)
			cs.tanpai_tail_flip_idx = maxi(0, tail_flip)

	_revealed[challenger_idx] = true
	_ch_state[challenger_idx] = cs
	_add_log("摊牌: banker=%s" % banker_give)
	_queue_idx += 1
	_check_queue_done()
	return true


func submit_angong(challenger_idx: int, banker_choice: String) -> bool:
	if phase != Phase.BANKER_QUEUE: return false
	var item: Dictionary = _current_item()
	if item.is_empty() or item.idx != challenger_idx: return false
	if item.action != Types.DECISION_ANGONG: return false

	var cs: Dictionary = _ch_state[challenger_idx]
	cs.angongChoice = banker_choice
	if banker_choice == Types.ANGONG_OPEN:
		_revealed[challenger_idx] = true
	_ch_state[challenger_idx] = cs
	_add_log("暗攻: banker=%s" % banker_choice)
	_queue_idx += 1
	_check_queue_done()
	return true


func _check_queue_done() -> void:
	if _queue_idx >= _banker_queue.size():
		_process_reveal()


func _process_reveal() -> void:
	phase = Phase.BANKER_REVEAL
	round_results.clear()

	var bk_arr: Dictionary = players[banker_idx].arrangement
	var bk_ht: String = CompareUtil.get_hand_type(bk_arr)
	var bk_shuiyu: bool = (bk_ht == Types.HAND_SHUIYU or bk_ht == Types.HAND_SHUIYU_TIANTANG)

	var bk_reveals: bool = bk_shuiyu
	if not bk_reveals:
		var bk_dz: bool = (bk_ht == Types.HAND_DOUBLE_ZERO)
		for i in range(4):
			if i == banker_idx: continue
			var cs: Dictionary = _ch_state.get(i, {})
			if cs.is_empty(): continue
			if _has_comparison(cs, i):
				if bk_dz and cs.skipped: continue
				bk_reveals = true
				break

	if bk_reveals:
		_revealed[banker_idx] = true
		_add_log("--- 庄家亮牌 ---")
	else:
		_add_log("--- 庄家无需亮牌 ---")

	for i in range(4):
		if i == banker_idx: continue
		var cs: Dictionary = _ch_state.get(i, {})
		if cs.is_empty(): continue
		var r: Dictionary = _settle_one(i, cs, bk_shuiyu)
		if not r.is_empty():
			round_results.append(r)

	phase = Phase.ROUND_END
	for r in round_results:
		_add_log(r.get("message", ""))

	_add_log("--- 第 %d 轮结算完成 ---" % _round)

	if _round % _rounds_per_cycle == 0:
		banker_idx = [3, 2, 0, 1][banker_idx]
		for p in players:
			p.is_banker = (p.position == banker_idx)
		_games_completed += 1

	if _games_completed > 4:
		_finish_game()


func is_game_over() -> bool:
	return phase == Phase.GAME_OVER


func _finish_game() -> void:
	phase = Phase.GAME_OVER
	final_standings.clear()
	for p in players:
		final_standings.append({
			"name": p.name,
			"position": p.position,
			"total_score": p.score,
		})
	final_standings.sort_custom(func(a, b): return a.total_score > b.total_score)
	_add_log("=== 大局结束！===")
	for j in range(final_standings.size()):
		var s: Dictionary = final_standings[j]
		_add_log("第%d名: %s (%d分)" % [j + 1, s.name, s.total_score])


func get_player_cards(player_idx: int) -> Array:
	if player_idx < 0 or player_idx >= 4: return []
	return players[player_idx].cards.duplicate()


func get_player_arrangement(player_idx: int) -> Dictionary:
	if player_idx < 0 or player_idx >= 4: return {}
	return players[player_idx].arrangement.duplicate()


func is_revealed(player_idx: int) -> bool:
	if player_idx < 0 or player_idx >= 4: return false
	return _revealed[player_idx]


func get_scores() -> Array:
	var s: Array = []
	for p in players:
		s.append(p.score)
	return s


func _get_cs(idx: int, cards: Array) -> Dictionary:
	if _ch_state.has(idx): return _ch_state[idx]
	return {
		"playerId": idx,
		"cards": cards.duplicate(),
		"skipped": false,
		"doubleZeroChoice": "",
		"decision": "",
		"tanpai_head_flip_idx": -1,
		"tanpai_tail_flip_idx": -1,
	}


func _current_item() -> Dictionary:
	if _queue_idx >= _banker_queue.size(): return {}
	return _banker_queue[_queue_idx]


func _has_comparison(cs: Dictionary, ch_idx: int) -> bool:
	var bk_arr: Dictionary = players[banker_idx].arrangement
	if bk_arr.is_empty(): return false
	var bk_ht: String = CompareUtil.get_hand_type(bk_arr)
	var bk_shuiyu: bool = (bk_ht == Types.HAND_SHUIYU or bk_ht == Types.HAND_SHUIYU_TIANTANG)

	if cs.skipped:
		return not ScoringUtil.try_special_settlement(bk_arr, players[ch_idx].arrangement).is_empty()
	if cs.get("doubleZeroChoice") == Types.DOUBLE_ZERO_ZOUSHUI:
		return false
	var dec: String = cs.decision
	if dec == Types.DECISION_QIANGGONG: return true
	if dec == Types.DECISION_ANGONG:
		if cs.get("angongChoice") == Types.ANGONG_OPEN: return true
		if bk_shuiyu:
			return CompareUtil.get_hand_type(players[ch_idx].arrangement) == Types.HAND_DOUBLE_ZERO
		return false
	if dec == Types.DECISION_TANPAI:
		if cs.get("tanpaiBankerChoice") == Types.TANPAI_BANKER_NOT_GIVE:
			var ch: String = cs.get("tanpaiChallengerChoice", "")
			return ch == Types.TANPAI_CHALLENGER_FAN_HEAD or ch == Types.TANPAI_CHALLENGER_FAN_TAIL or ch == Types.TANPAI_CHALLENGER_FAN_BOTH
		return cs.get("tanpaiPassChoice") == Types.TANPAI_PASS_YINGYAO
	return false


func _settle_one(ch_idx: int, cs: Dictionary, bk_shuiyu: bool) -> Dictionary:
	var ch_arr: Dictionary = players[ch_idx].arrangement
	if ch_arr.is_empty(): return {}

	if cs.skipped:
		var sp: Dictionary = ScoringUtil.try_special_settlement(players[banker_idx].arrangement, ch_arr)
		if not sp.is_empty():
			return _apply_sp(ch_idx, sp)
		var comp: int = CompareUtil.compare_arrangements(players[banker_idx].arrangement, ch_arr)
		var sc: int = 0
		var msg: String = "平局"
		if comp > 0: sc = 1; msg = "庄家胜"
		elif comp < 0: sc = -1; msg = "闲家胜"
		return _apply_sp(ch_idx, {"scoreChange": sc, "message": msg})

	if cs.get("doubleZeroChoice") == Types.DOUBLE_ZERO_ZOUSHUI:
		return _apply_sp(ch_idx, ScoringUtil.settle_double_zero_zoushui())

	if bk_shuiyu:
		var sp: Dictionary = ScoringUtil.try_special_settlement(players[banker_idx].arrangement, ch_arr)
		if sp.is_empty():
			var is_tt: bool = (CompareUtil.get_hand_type(players[banker_idx].arrangement) == Types.HAND_SHUIYU_TIANTANG)
			sp = {"scoreChange": 8 if is_tt else 4, "message": "庄家%s碾压！" % ("水鱼天下" if is_tt else "水鱼")}
		return _apply_sp(ch_idx, sp)

	var comp: int = CompareUtil.compare_arrangements(players[banker_idx].arrangement, ch_arr)
	var dec_sp: Dictionary = _settle_decision(cs, comp)
	if not dec_sp.is_empty():
		return _apply_sp(ch_idx, dec_sp)
	return {}


func _apply_sp(ch_idx: int, sp: Dictionary) -> Dictionary:
	var sc: int = sp.get("scoreChange", 0)
	players[banker_idx].score += sc
	players[ch_idx].score -= sc
	return {
		"challenger_idx": ch_idx,
		"challenger_name": players[ch_idx].name,
		"scoreChange": sc,
		"message": sp.get("message", ""),
	}


func _settle_decision(cs: Dictionary, comp: int) -> Dictionary:
	var dec: String = cs.decision
	if dec == Types.DECISION_QIANGGONG:
		return ScoringUtil.settle_qianggong(comp, cs.get("qianggong_banker_choice", ""))
	if dec == Types.DECISION_TANPAI:
		if cs.get("tanpaiBankerChoice") == Types.TANPAI_BANKER_GIVE:
			if cs.get("tanpaiPassChoice") == Types.TANPAI_PASS_GUO:
				return ScoringUtil.settle_tanpai_guo()
			return ScoringUtil.settle_tanpai_yingyao(comp)
		else:
			var ch: String = cs.get("tanpaiChallengerChoice", "")
			if ch == Types.TANPAI_CHALLENGER_RENSHU: return ScoringUtil.settle_tanpai_renshu()
			if ch == Types.TANPAI_CHALLENGER_FAN_HEAD: return ScoringUtil.settle_tanpai_fan_head(comp)
			if ch == Types.TANPAI_CHALLENGER_FAN_TAIL: return ScoringUtil.settle_tanpai_fan_tail(comp)
			if ch == Types.TANPAI_CHALLENGER_FAN_BOTH: return ScoringUtil.settle_tanpai_fan_both(comp)
	if dec == Types.DECISION_ANGONG:
		if cs.get("angongChoice") == Types.ANGONG_NOT_OPEN:
			return ScoringUtil.settle_angong_not_open()
		return ScoringUtil.settle_angong_open(comp)
	return {}


func _card_eq(a: Dictionary, b: Dictionary) -> bool:
	return a.get("rank") == b.get("rank") and a.get("suit") == b.get("suit")


func _build_arrangement(cards: Array, head_idx: Array, tail_idx: Array) -> Dictionary:
	var fh: Array = [cards[head_idx[0]], cards[head_idx[1]]]
	var ft: Array = [cards[tail_idx[0]], cards[tail_idx[1]]]
	var hr: Dictionary = EvaluateUtil.evaluate_group(fh)
	var tr: Dictionary = EvaluateUtil.evaluate_group(ft)
	return {
		"fishHead": fh,
		"fishTail": ft,
		"headResult": hr,
		"tailResult": tr,
		"desc": "%s + %s" % [hr.get("type", "?"), tr.get("type", "?")],
	}


func _add_log(msg: String) -> void:
	log.append(msg)
	print("[GC:%s] %s" % [game_id, msg])
