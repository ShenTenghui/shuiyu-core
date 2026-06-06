# constants.gd — Shared constants for 水鱼游戏

# -- Visual / UI --
const FONT_PATH: String = "res://资源/ruiziaoyunjingshenshoujinjian-shanchanggui.ttf"
const GOLD: Color = Color(0.992, 0.871, 0.561, 1.0)
const DIM_COLOR: Color = Color(0.2, 0.2, 0.2, 1.0)
const CARD_W: float = 104.63
const CARD_H: float = 144.17
const CARD_SEP: float = 27.0

# -- Card value lookup tables --

# Point values: A=1, 2-9=face, 10/J/Q/K=0
const RANK_VALUE := {
	"2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9,
	"10": 0, "J": 0, "Q": 0, "K": 0, "A": 1,
}

# Single card priority for tie-breaking: A=14 highest, 2=2 lowest
const SINGLE_PRIORITY := {
	"A": 14, "K": 13, "Q": 12, "J": 11, "10": 10,
	"9": 9, "8": 8, "7": 7, "6": 6, "5": 5,
	"4": 4, "3": 3, "2": 2,
}

# Suit priority: ♠ > ♥ > ♣ > ♦
const SUIT_PRIORITY := {
	"♠": 4, "♥": 3, "♣": 2, "♦": 1,
}

# Pair priority: AA=14, KK=13, ..., 22=2
const PAIR_PRIORITY := {
	"AA": 14, "KK": 13, "QQ": 12, "JJ": 11, "1010": 10,
	"99": 9, "88": 8, "77": 7, "66": 6, "55": 5,
	"44": 4, "33": 3, "22": 2,
}

# Rank display names
const RANK_DISPLAY := {
	"2": "2", "3": "3", "4": "4", "5": "5", "6": "6", "7": "7", "8": "8", "9": "9",
	"10": "10", "J": "J", "Q": "Q", "K": "K", "A": "A",
}
