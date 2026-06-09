# scoring.gd — All settlement formulas for 水鱼游戏
class_name ScoringUtils
extends RefCounted

const CompareUtil = preload("res://脚本/core/compare.gd")
const Types = preload("res://脚本/core/types.gd")


# Check for special hand-type matchups that bypass the decision phase.
# Returns Dictionary { scoreChange, message } or empty {} if no special.
static func try_special_settlement(banker_arr: Dictionary, challenger_arr: Dictionary) -> Dictionary:
	var banker_type: String = CompareUtil.get_hand_type(banker_arr)
	var challenger_type: String = CompareUtil.get_hand_type(challenger_arr)

	# --- Banker has shuiyu_tiantang ---
	if banker_type == Types.HAND_SHUIYU_TIANTANG:
		if challenger_type == Types.HAND_DOUBLE_ZERO:
			return { "scoreChange": -16, "message": "庄家水鱼天下，闲家双零！庄家-16分" }
		if challenger_type == Types.HAND_SHUIYU_TIANTANG:
			var result := CompareUtil.compare_arrangements(banker_arr, challenger_arr)
			if result == Types.COMPARE_BANKER_WIN_BOTH:
				return { "scoreChange": 16, "message": "双方水鱼天下，庄家牌更大！庄家+16分" }
			return { "scoreChange": -16, "message": "双方水鱼天下，闲家牌更大！庄家-16分" }
		if challenger_type == Types.HAND_SHUIYU:
			return { "scoreChange": 8, "message": "庄家水鱼天下，闲家水鱼！庄家+8分" }
		if challenger_type == Types.HAND_NORMAL:
			return { "scoreChange": 8, "message": "庄家水鱼天下，闲家普通牌型！庄家+8分" }

	# --- Challenger has shuiyu_tiantang ---
	if challenger_type == Types.HAND_SHUIYU_TIANTANG:
		if banker_type == Types.HAND_DOUBLE_ZERO:
			return { "scoreChange": 16, "message": "闲家水鱼天下，庄家双零！庄家+16分" }
		if banker_type == Types.HAND_SHUIYU:
			return { "scoreChange": -8, "message": "闲家水鱼天下，庄家水鱼！庄家-8分" }
		if banker_type == Types.HAND_NORMAL:
			return { "scoreChange": -8, "message": "闲家水鱼天下，庄家普通牌型！庄家-8分" }

	# --- Shuiyu vs Double zero ---
	if banker_type == Types.HAND_SHUIYU and challenger_type == Types.HAND_DOUBLE_ZERO:
		return { "scoreChange": -8, "message": "庄家水鱼，闲家双零！庄家-8分" }
	if banker_type == Types.HAND_DOUBLE_ZERO and challenger_type == Types.HAND_SHUIYU:
		return { "scoreChange": 8, "message": "闲家水鱼，庄家双零！庄家+8分" }

	# --- Shuiyu vs Shuiyu ---
	if banker_type == Types.HAND_SHUIYU and challenger_type == Types.HAND_SHUIYU:
		var result := CompareUtil.compare_arrangements(banker_arr, challenger_arr)
		if result == Types.COMPARE_BANKER_LOSE_BOTH:
			return { "scoreChange": -8, "message": "双方水鱼，闲家牌更大！庄家-8分" }
		return { "scoreChange": 4, "message": "双方水鱼，庄家牌更大！庄家+4分" }

	# --- Shuiyu vs Normal ---
	if banker_type == Types.HAND_SHUIYU and challenger_type == Types.HAND_NORMAL:
		return { "scoreChange": 4, "message": "庄家水鱼，闲家普通牌型！庄家+4分" }
	if banker_type == Types.HAND_NORMAL and challenger_type == Types.HAND_SHUIYU:
		return { "scoreChange": -4, "message": "闲家水鱼，庄家普通牌型！庄家-4分" }

	return {}


# Double zero zoushui -> tie
static func settle_double_zero_zoushui() -> Dictionary:
	return { "scoreChange": 0, "message": "闲家双零走水，双方平局！" }


# Qianggong settlement — banker chooses which door(s) to compare
# bi_tou: challenger must win head → ±2
# bi_wei: challenger must win tail → ±2
# bi_shuang: challenger must win both → +4/-2 (asymmetric: banker punishes more for wrong call)
static func settle_qianggong(compare_result: int, banker_choice: String) -> Dictionary:
	var head_won: bool = (compare_result == Types.COMPARE_BANKER_LOSE_HEAD_WIN_TAIL or compare_result == Types.COMPARE_BANKER_LOSE_BOTH)
	var tail_won: bool = (compare_result == Types.COMPARE_BANKER_WIN_HEAD_LOSE_TAIL or compare_result == Types.COMPARE_BANKER_LOSE_BOTH)
	var both_won: bool = (compare_result == Types.COMPARE_BANKER_LOSE_BOTH)

	if banker_choice == Types.QIANG_GONG_BI_TOU:
		if head_won:
			return { "scoreChange": -2, "message": "[强攻·比头] 闲家鱼头胜，强攻成功！闲家+2，庄家-2" }
		return { "scoreChange": 2, "message": "[强攻·比头] 闲家鱼头败，强攻失败！庄家+2，闲家-2" }

	if banker_choice == Types.QIANG_GONG_BI_WEI:
		if tail_won:
			return { "scoreChange": -2, "message": "[强攻·比尾] 闲家鱼尾胜，强攻成功！闲家+2，庄家-2" }
		return { "scoreChange": 2, "message": "[强攻·比尾] 闲家鱼尾败，强攻失败！庄家+2，闲家-2" }

	# bi_shuang: asymmetric — challenger +4 if wins both, -2 if loses
	if both_won:
		return { "scoreChange": -4, "message": "[强攻·比双] 闲家两门皆胜！闲家+4，庄家-4" }
	return { "scoreChange": 2, "message": "[强攻·比双] 闲家未全胜，强攻失败！庄家+2，闲家-2" }


# Angong — banker does NOT open (challenger auto +1)
static func settle_angong_not_open() -> Dictionary:
	return { "scoreChange": -1, "message": "[暗攻] 庄家不开牌，闲家暗攻得手+1，庄家-1" }


# Angong — banker opens
static func settle_angong_open(compare_result: int) -> Dictionary:
	if compare_result == Types.COMPARE_BANKER_LOSE_BOTH:
		return { "scoreChange": -3, "message": "[暗攻] 庄家开牌，闲家暗攻成功（两门都赢）+3！" }
	return { "scoreChange": 3, "message": "[暗攻] 庄家开牌，闲家暗攻失败，庄家+3！" }


# Tanpai — given pass -> guo (tie)
static func settle_tanpai_guo() -> Dictionary:
	return { "scoreChange": 0, "message": "[摊牌] 闲家选择过，双方平局" }


# Tanpai — given pass -> yingyao (force compare)
static func settle_tanpai_yingyao(compare_result: int) -> Dictionary:
	if compare_result == Types.COMPARE_BANKER_LOSE_BOTH:
		return { "scoreChange": -2, "message": "[硬要] 硬要成功（两门都赢）！闲家+2，庄家-2" }
	return { "scoreChange": 2, "message": "[硬要] 硬要失败，庄家+2，闲家-2" }


# Tanpai — not given pass -> renshu (surrender)
static func settle_tanpai_renshu() -> Dictionary:
	return { "scoreChange": 1, "message": "[认输] 闲家认输，庄家+1，闲家-1" }


# Tanpai — not given pass -> fan_head
# Success if banker's head loses (compare 3 or 4)
static func settle_tanpai_fan_head(compare_result: int) -> Dictionary:
	if compare_result == Types.COMPARE_BANKER_LOSE_HEAD_WIN_TAIL or compare_result == Types.COMPARE_BANKER_LOSE_BOTH:
		return { "scoreChange": -2, "message": "[反鱼头] 反鱼头成功！闲家+2，庄家-2" }
	return { "scoreChange": 2, "message": "[反鱼头] 反鱼头失败，庄家+2，闲家-2" }


# Tanpai — not given pass -> fan_tail
# Success if banker's tail loses (compare 2 or 4)
static func settle_tanpai_fan_tail(compare_result: int) -> Dictionary:
	if compare_result == Types.COMPARE_BANKER_WIN_HEAD_LOSE_TAIL or compare_result == Types.COMPARE_BANKER_LOSE_BOTH:
		return { "scoreChange": -2, "message": "[反鱼尾] 反鱼尾成功！闲家+2，庄家-2" }
	return { "scoreChange": 2, "message": "[反鱼尾] 反鱼尾失败，庄家+2，闲家-2" }


# Tanpai — not given pass -> fan_both
static func settle_tanpai_fan_both(compare_result: int) -> Dictionary:
	if compare_result == Types.COMPARE_BANKER_LOSE_BOTH:
		return { "scoreChange": -4, "message": "[反双] 反双成功（两门都赢）！闲家+4，庄家-4" }
	return { "scoreChange": 4, "message": "[反双] 反双失败，庄家+4，闲家-4" }
