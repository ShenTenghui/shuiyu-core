# card.gd — Deck operations for 水鱼游戏
class_name CardUtils
extends RefCounted

const Constants = preload("res://脚本/core/constants.gd")
const Types = preload("res://脚本/core/types.gd")


# Create a standard 52-card deck (no jokers)
static func create_deck() -> Array:
	var deck := []
	for suit in Types.SUITS:
		for rank in Types.RANKS:
			deck.append({ "rank": rank, "suit": suit })
	return deck


# Fisher-Yates shuffle (immutable — returns new array)
static func shuffle_deck(deck: Array) -> Array:
	var shuffled := deck.duplicate()
	var n := shuffled.size()
	for i in range(n - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	return shuffled


# Deal n cards from the top of the deck
static func deal_cards(deck: Array, n: int) -> Dictionary:
	return {
		"dealt": deck.slice(0, n),
		"remaining": deck.slice(n, deck.size()),
	}


# Card ordering value: rank_priority * 100 + suit_priority
static func card_order(card: Dictionary) -> int:
	return Constants.SINGLE_PRIORITY[card.rank] * 100 + Constants.SUIT_PRIORITY[card.suit]


# Compare two single cards: 1 (card1 > card2), -1, or 0 (equal)
static func compare_cards(card1: Dictionary, card2: Dictionary) -> int:
	var p1: int = Constants.SINGLE_PRIORITY[card1.rank]
	var p2: int = Constants.SINGLE_PRIORITY[card2.rank]
	if p1 != p2:
		return 1 if p1 > p2 else -1
	var s1: int = Constants.SUIT_PRIORITY[card1.suit]
	var s2: int = Constants.SUIT_PRIORITY[card2.suit]
	if s1 != s2:
		return 1 if s1 > s2 else -1
	return 0


# Sort cards descending (strongest first)
static func sort_cards(cards: Array) -> Array:
	var sorted := cards.duplicate()
	sorted.sort_custom(func(a, b): return compare_cards(b, a) < 0)
	return sorted


# Get the card image key (e.g. "A♠")
static func get_card_image_key(card: Dictionary) -> String:
	return str(card.rank) + str(card.suit)
