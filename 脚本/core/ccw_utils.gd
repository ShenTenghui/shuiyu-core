# ccw_utils.gd — Counter-clockwise order and label utilities for 水鱼游戏
class_name CcwUtils
extends RefCounted

const CCW_CYCLE: Array = [0, 3, 1, 2]
const CCW_LABELS: Array = ["庄家", "闲家1", "闲家2", "闲家3"]


# Get challenger indices in CCW order (excludes banker)
static func get_challenger_order(banker_index: int) -> Array:
	var result: Array = []
	var start: int = CCW_CYCLE.find(banker_index)
	for offset in range(1, 4):
		result.append(CCW_CYCLE[(start + offset) % 4])
	return result


# Get all player indices in CCW order (banker first)
static func get_full_order(banker_index: int) -> Array:
	var result: Array = [banker_index]
	var start: int = CCW_CYCLE.find(banker_index)
	for offset in range(1, 4):
		result.append(CCW_CYCLE[(start + offset) % 4])
	return result


# Get human-readable label like "闲家1" or "闲家1（AI1）"
static func get_label(player_index: int, banker_index: int, player_name: String = "") -> String:
	var start: int = CCW_CYCLE.find(banker_index)
	for offset in range(4):
		var i: int = CCW_CYCLE[(start + offset) % 4]
		if i == player_index:
			var label: String = CCW_LABELS[offset]
			if player_name != "":
				return label + "（" + player_name + "）"
			return label
	return player_name


# Get game number (1-based) from banker index
static func get_game_number(banker_index: int) -> int:
	return CCW_CYCLE.find(banker_index) + 1
