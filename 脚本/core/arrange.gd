# arrange.gd — Arrangement generation for 4-card hands in 水鱼游戏
class_name ArrangeUtils
extends RefCounted

const EvaluateUtil = preload("res://脚本/core/evaluate.gd")


# Generate all valid arrangements from 4 cards.
# Rule: pick 2 for fishHead (C(4,2)=6 combos), remaining 2 are fishTail.
# Fish head must be > fish tail (strictly greater).
static func generate_arrangements(cards: Array) -> Array:
	var arrangements: Array = []
	var combos: Array = [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]]

	for pair in combos:
		var h1: int = pair[0]
		var h2: int = pair[1]
		var head: Array = [cards[h1], cards[h2]]

		# Remaining two are the tail
		var tail_indices: Array = []
		for i in range(4):
			if i != h1 and i != h2:
				tail_indices.append(i)
		var tail: Array = [cards[tail_indices[0]], cards[tail_indices[1]]]

		var head_result: Dictionary = EvaluateUtil.evaluate_group(head)
		var tail_result: Dictionary = EvaluateUtil.evaluate_group(tail)

		# Fish head must be > fish tail
		if EvaluateUtil.compare_groups(head_result, tail_result) > 0:
			var head_desc: String = EvaluateUtil.get_group_description(head_result)
			var tail_desc: String = EvaluateUtil.get_group_description(tail_result)
			arrangements.append({
				"fishHead": head,
				"fishTail": tail,
				"headResult": head_result,
				"tailResult": tail_result,
				"desc": "鱼头: " + str(head[0].rank) + str(head[0].suit) + " " + str(head[1].rank) + str(head[1].suit) + " (" + head_desc + ") → 鱼尾: " + str(tail[0].rank) + str(tail[0].suit) + " " + str(tail[1].rank) + str(tail[1].suit) + " (" + tail_desc + ")",
			})

	# v9.5: 过滤被压制的排列 (dominated arrangements)
	# 排列A压制B: A的头>B的头 且 A的尾>B的尾
	# 被压制的排列永远不会是最优选择
	var filtered: Array = []
	for i in range(arrangements.size()):
		var a: Dictionary = arrangements[i]
		var dominated: bool = false
		for j in range(arrangements.size()):
			if i == j: continue
			var b: Dictionary = arrangements[j]
			var h_cmp: int = EvaluateUtil.compare_groups(b.headResult, a.headResult)
			var t_cmp: int = EvaluateUtil.compare_groups(b.tailResult, a.tailResult)
			# b 在头尾上都 ≥ a, 且至少一处 > → a 被压制
			if h_cmp >= 0 and t_cmp >= 0 and (h_cmp > 0 or t_cmp > 0):
				dominated = true
				break
		if not dominated:
			filtered.append(a)

	# Sort: strongest head first; equal heads → strongest tail first
	filtered.sort_custom(func(a, b):
		var head_cmp: int = EvaluateUtil.compare_groups(b.headResult, a.headResult)
		if head_cmp != 0:
			return head_cmp < 0
		return EvaluateUtil.compare_groups(b.tailResult, a.tailResult) < 0
	)

	return filtered


# Pick the best (first) arrangement
static func pick_best_arrangement(arrangements: Array) -> Dictionary:
	assert(arrangements.size() > 0, "No valid arrangement — this should never happen")
	return arrangements[0]
