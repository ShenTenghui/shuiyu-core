# game_dealer.gd — 洗牌/发牌内部辅助 (M1D-01)
# GameController 调用，返回值由 Controller 写入。Dealer 不持有对局状态。
class_name GameDealer
extends RefCounted

const CardUtil = preload("res://脚本/core/card.gd")


# 创建并洗一副新牌 (52张)
func shuffle_new() -> Array:
	return CardUtil.shuffle_deck(CardUtil.create_deck())


# 从牌堆顶部发 count 张牌。返回 {dealt: Array, remaining: Array}
func deal(deck: Array, count: int) -> Dictionary:
	return CardUtil.deal_cards(deck, count)


# 为 player_count 名玩家各发 cards_per 张牌。返回 {hands: Array[Array], remaining: Array}
func deal_to_all(deck: Array, player_count: int, cards_per: int) -> Dictionary:
	var hands: Array = []
	var d := deck
	for _i in range(player_count):
		var r := CardUtil.deal_cards(d, cards_per)
		hands.append(r.dealt)
		d = r.remaining
	return {"hands": hands, "remaining": d}
