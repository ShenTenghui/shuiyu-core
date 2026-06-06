# types.gd — Core type definitions for 水鱼游戏
# Data structures are plain Dictionaries matching the TS shapes exactly.

# -- Phase enum (integer-based, GDScript convention) --
enum Phase {
	DEALING = 0,
	ALL_ARRANGING = 1,
	BETTING = 3,
	ALL_DECIDING = 4,
	BANKER_QUEUE = 5,
	BANKER_REVEAL = 9,
	ANNOUNCING = 10,
	GAME_OVER = 12,
}

# -- HandType string constants --
const HAND_SHUIYU_TIANTANG := "shuiyu_tiantang"
const HAND_SHUIYU := "shuiyu"
const HAND_DOUBLE_ZERO := "double_zero"
const HAND_NORMAL := "normal"

# -- Decision string constants --
const DECISION_QIANGGONG := "qianggong"
const DECISION_ANGONG := "angong"
const DECISION_TANPAI := "tanpai"

# -- Tanpai choices --
const TANPAI_BANKER_GIVE := "give"
const TANPAI_BANKER_NOT_GIVE := "not_give"
const TANPAI_CHALLENGER_RENSHU := "renshu"
const TANPAI_CHALLENGER_FAN_HEAD := "fan_head"
const TANPAI_CHALLENGER_FAN_TAIL := "fan_tail"
const TANPAI_CHALLENGER_FAN_BOTH := "fan_both"
const TANPAI_PASS_GUO := "guo"
const TANPAI_PASS_YINGYAO := "yingyao"

# -- Angong choices --
const ANGONG_OPEN := "open"
const ANGONG_NOT_OPEN := "not_open"

# -- Double zero choices --
const DOUBLE_ZERO_ZOUSHUI := "zoushui"
const DOUBLE_ZERO_BU_ZOUSHUI := "bu_zoushui"

# -- CompareResult constants (1-4 as in TS) --
const COMPARE_BANKER_WIN_BOTH := 1
const COMPARE_BANKER_WIN_HEAD_LOSE_TAIL := 2
const COMPARE_BANKER_LOSE_HEAD_WIN_TAIL := 3
const COMPARE_BANKER_LOSE_BOTH := 4

# -- GroupResult types --
const GROUP_PAIR := "pair"
const GROUP_POINT := "point"

# -- Suit symbols (kept as strings matching TS) --
const SUITS := ["♠", "♥", "♣", "♦"]

# -- Rank strings (kept as strings matching TS) --
const RANKS := ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]


# Helper: create a Card dictionary
static func make_card(rank: String, suit: String) -> Dictionary:
	return { "rank": rank, "suit": suit }


# Helper: create a GroupResult (pair)
static func make_pair_result(pair_rank: int, best_card: Dictionary, cards: Array) -> Dictionary:
	return { "type": GROUP_PAIR, "pairRank": pair_rank, "bestCard": best_card, "cards": cards }


# Helper: create a GroupResult (point)
static func make_point_result(point: int, best_card: Dictionary, cards: Array) -> Dictionary:
	return { "type": GROUP_POINT, "point": point, "bestCard": best_card, "cards": cards }
