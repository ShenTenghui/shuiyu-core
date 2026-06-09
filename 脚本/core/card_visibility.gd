# card_visibility.gd — Card face-up/down rules for 水鱼游戏
class_name CardVisibility
extends RefCounted

const Types = preload("res://脚本/core/types.gd")
const CompareUtil = preload("res://脚本/core/compare.gd")


static func get_card_flags(idx: int, player: Dictionary, phase: int, revealed_ids: Array, announced_ids: Array, challenger_states: Dictionary) -> Array:
	if player.get("isHuman", false): return [false, false, false, false]
	if phase == Types.Phase.GAME_OVER: return [false, false, false, false]
	if revealed_ids.has(idx):
		if phase == Types.Phase.BANKER_REVEAL or phase == Types.Phase.GAME_OVER:
			return [false, false, false, false]
	if not announced_ids.has(idx): return [true, true, true, true]
	var cs: Dictionary = challenger_states.get(idx, {})
	if cs.is_empty(): return [true, true, true, true]
	if cs.get("skipped", false) or cs.get("doubleZeroChoice") == Types.DOUBLE_ZERO_ZOUSHUI:
		return [false, false, false, false]
	var dec: String = str(cs.get("decision", ""))
	if dec == Types.DECISION_QIANGGONG:
		if revealed_ids.has(idx): return [false, false, false, false]
		return [true, true, true, true]
	if dec == Types.DECISION_ANGONG:
		if revealed_ids.has(idx): return [false, false, false, false]
		return [true, true, true, true]
	if dec == Types.DECISION_TANPAI:
		var h_flip: int = cs.get("tanpai_head_flip_idx", -1)
		var t_flip: int = cs.get("tanpai_tail_flip_idx", -1)
		if h_flip >= 0 or t_flip >= 0:
			return [h_flip == 0, h_flip == 1, t_flip == 0, t_flip == 1]
		return [false, false, false, false]
	return [true, true, true, true]


static func should_reveal_challenger(ch_idx: int, cs: Dictionary, banker_arr: Dictionary) -> bool:
	if cs.get("skipped", false): return true
	if cs.get("doubleZeroChoice") == Types.DOUBLE_ZERO_ZOUSHUI: return true

	var dec: String = str(cs.get("decision", ""))
	if banker_arr.is_empty(): return false
	var banker_hand: String = CompareUtil.get_hand_type(banker_arr)
	var banker_shuiyu: bool = (banker_hand == Types.HAND_SHUIYU or banker_hand == Types.HAND_SHUIYU_TIANTANG)

	if dec == Types.DECISION_QIANGGONG: return true
	if dec == Types.DECISION_TANPAI: return true

	if dec == Types.DECISION_ANGONG:
		if cs.get("angongChoice") == Types.ANGONG_OPEN: return true
		if banker_shuiyu:
			var ch_arr: Dictionary = cs.get("arrangement", {})
			if ch_arr.is_empty(): return false
			return CompareUtil.get_hand_type(ch_arr) == Types.HAND_DOUBLE_ZERO
		return false
	return false


enum CompareMode { FULL, HEAD_ONLY, TAIL_ONLY, NONE }

static func get_compare_mode(cs: Dictionary) -> Dictionary:
	if cs.is_empty(): return {"mode": CompareMode.FULL, "has_head": true, "has_tail": true}
	if cs.get("skipped", false) or cs.get("doubleZeroChoice") == Types.DOUBLE_ZERO_ZOUSHUI:
		return {"mode": CompareMode.NONE, "has_head": false, "has_tail": false}
	var dec: String = str(cs.get("decision", ""))
	if dec == Types.DECISION_QIANGGONG:
		var bk_choice: String = str(cs.get("qianggong_banker_choice", ""))
		if bk_choice == Types.QIANG_GONG_BI_TOU:
			return {"mode": CompareMode.HEAD_ONLY, "has_head": true, "has_tail": false}
		if bk_choice == Types.QIANG_GONG_BI_WEI:
			return {"mode": CompareMode.TAIL_ONLY, "has_head": false, "has_tail": true}
		return {"mode": CompareMode.FULL, "has_head": true, "has_tail": true}
	if dec == Types.DECISION_TANPAI:
		var ch_choice: String = str(cs.get("tanpaiChallengerChoice", ""))
		var pass_choice: String = str(cs.get("tanpaiPassChoice", ""))
		if ch_choice == Types.TANPAI_CHALLENGER_FAN_HEAD:
			return {"mode": CompareMode.HEAD_ONLY, "has_head": true, "has_tail": false}
		if ch_choice == Types.TANPAI_CHALLENGER_FAN_TAIL:
			return {"mode": CompareMode.TAIL_ONLY, "has_head": false, "has_tail": true}
		if ch_choice == Types.TANPAI_CHALLENGER_RENSHU or pass_choice == Types.TANPAI_PASS_GUO:
			return {"mode": CompareMode.NONE, "has_head": false, "has_tail": false}
		return {"mode": CompareMode.FULL, "has_head": true, "has_tail": true}
	if dec == Types.DECISION_ANGONG:
		if cs.get("angongChoice") == Types.ANGONG_NOT_OPEN:
			return {"mode": CompareMode.NONE, "has_head": false, "has_tail": false}
		return {"mode": CompareMode.FULL, "has_head": true, "has_tail": true}
	return {"mode": CompareMode.FULL, "has_head": true, "has_tail": true}
