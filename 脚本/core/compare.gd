# compare.gd — Arrangement comparison and hand type detection for 水鱼游戏
class_name CompareUtils
extends RefCounted

const EvaluateUtil = preload("res://脚本/core/evaluate.gd")
const Types = preload("res://脚本/core/types.gd")


# Compare banker vs challenger arrangements.
# Returns: 1=banker wins both, 2=banker wins head loses tail,
#          3=banker loses head wins tail, 4=banker loses both
static func compare_arrangements(banker: Dictionary, challenger: Dictionary) -> int:
	var head_cmp: int = EvaluateUtil.compare_groups(banker.headResult, challenger.headResult)
	var tail_cmp: int = EvaluateUtil.compare_groups(banker.tailResult, challenger.tailResult)

	if head_cmp > 0 and tail_cmp > 0:
		return Types.COMPARE_BANKER_WIN_BOTH
	if head_cmp > 0 and tail_cmp < 0:
		return Types.COMPARE_BANKER_WIN_HEAD_LOSE_TAIL
	if head_cmp < 0 and tail_cmp > 0:
		return Types.COMPARE_BANKER_LOSE_HEAD_WIN_TAIL
	if head_cmp < 0 and tail_cmp < 0:
		return Types.COMPARE_BANKER_LOSE_BOTH

	# Tie-breaking for edge cases
	if head_cmp == 0 and tail_cmp > 0:
		return Types.COMPARE_BANKER_WIN_BOTH
	if head_cmp == 0 and tail_cmp < 0:
		return Types.COMPARE_BANKER_LOSE_BOTH
	if head_cmp > 0 and tail_cmp == 0:
		return Types.COMPARE_BANKER_WIN_BOTH
	if head_cmp < 0 and tail_cmp == 0:
		return Types.COMPARE_BANKER_LOSE_BOTH

	# Complete tie — banker wins by default
	return Types.COMPARE_BANKER_WIN_BOTH


# Detect hand type, strongest to weakest: shuiyu_tiantang > shuiyu > double_zero > normal
static func get_hand_type(arrangement: Dictionary) -> String:
	if arrangement.is_empty() or not arrangement.has("headResult"):
		return Types.HAND_NORMAL
	var head_is_pair: bool = arrangement.headResult.type == Types.GROUP_PAIR
	var tail_is_pair: bool = arrangement.tailResult.type == Types.GROUP_PAIR

	if head_is_pair and tail_is_pair:
		if arrangement.headResult.pairRank == arrangement.tailResult.pairRank:
			return Types.HAND_SHUIYU_TIANTANG
		return Types.HAND_SHUIYU

	if arrangement.headResult.type == Types.GROUP_POINT and arrangement.tailResult.type == Types.GROUP_POINT:
		if arrangement.headResult.point == 0 and arrangement.tailResult.point == 0:
			return Types.HAND_DOUBLE_ZERO

	return Types.HAND_NORMAL


static func get_compare_result_name(result: int) -> String:
	if result == Types.COMPARE_BANKER_WIN_BOTH:
		return "庄家赢头赢尾"
	elif result == Types.COMPARE_BANKER_WIN_HEAD_LOSE_TAIL:
		return "庄家赢头输尾"
	elif result == Types.COMPARE_BANKER_LOSE_HEAD_WIN_TAIL:
		return "庄家输头赢尾"
	elif result == Types.COMPARE_BANKER_LOSE_BOTH:
		return "庄家输头输尾"
	return "未知"


static func get_hand_type_label(ht: String) -> String:
	if ht == Types.HAND_SHUIYU_TIANTANG:
		return "水鱼天下"
	elif ht == Types.HAND_SHUIYU:
		return "水鱼"
	elif ht == Types.HAND_DOUBLE_ZERO:
		return "双零"
	return ""


static func get_hand_type_class(ht: String) -> String:
	if ht == Types.HAND_SHUIYU_TIANTANG:
		return "tiantang"
	elif ht == Types.HAND_SHUIYU:
		return "shuiyu"
	elif ht == Types.HAND_DOUBLE_ZERO:
		return "doublezero"
	return ""
