# evaluate.gd — Group evaluation for 2-card sets in 水鱼游戏
class_name EvaluateUtils
extends RefCounted

const Constants = preload("res://脚本/core/constants.gd")
const CardUtil = preload("res://脚本/core/card.gd")
const Types = preload("res://脚本/core/types.gd")


# Evaluate a 2-card group — returns PairResult or PointResult
static func evaluate_group(cards: Array) -> Dictionary:
	var c1: Dictionary = cards[0]
	var c2: Dictionary = cards[1]
	var best: Dictionary = c1 if CardUtil.compare_cards(c1, c2) >= 0 else c2

	if c1.rank == c2.rank:
		var pair_key: String = str(c1.rank) + str(c2.rank)
		var pair_rank: int = Constants.PAIR_PRIORITY.get(pair_key, 0)
		return Types.make_pair_result(pair_rank, best, cards)

	var point_val: int = (Constants.RANK_VALUE[c1.rank] + Constants.RANK_VALUE[c2.rank]) % 10
	return Types.make_point_result(point_val, best, cards)


# Compare two groups: 1 (grp1 > grp2), -1, or 0 (equal)
static func compare_groups(grp1: Dictionary, grp2: Dictionary) -> int:
	if grp1.type == Types.GROUP_PAIR and grp2.type == Types.GROUP_PAIR:
		if grp1.pairRank != grp2.pairRank:
			return 1 if grp1.pairRank > grp2.pairRank else -1
		return CardUtil.compare_cards(grp1.bestCard, grp2.bestCard)

	if grp1.type == Types.GROUP_PAIR:
		return 1
	if grp2.type == Types.GROUP_PAIR:
		return -1

	if grp1.point != grp2.point:
		return 1 if grp1.point > grp2.point else -1

	var cmp: int = CardUtil.compare_cards(grp1.bestCard, grp2.bestCard)
	if cmp != 0:
		return cmp
	return CardUtil.compare_cards(grp1.cards[1], grp2.cards[1])


# Human-readable group description
static func get_group_description(grp: Dictionary) -> String:
	if grp.type == Types.GROUP_PAIR:
		return "对" + str(grp.cards[0].rank) + "(" + str(grp.pairRank) + ")"
	return str(grp.point) + "点"
