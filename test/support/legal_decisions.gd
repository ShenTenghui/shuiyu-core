# Test driver only: chooses legal actions; it is not an AI strategy.
extends RefCounted

const Types = preload("res://脚本/core/types.gd")

static func choose_arrange_index(_cards: Array, _banker: int) -> int:
	return 0

static func choose_banker_arrange_index(_cards: Array) -> int:
	return 0

static func choose_primary_decision(cards: Array, banker: int) -> String:
	var selector: int = banker
	for card in cards:
		selector += Types.RANKS.find(str(card.rank))
	return [Types.DECISION_TANPAI, Types.DECISION_ANGONG, Types.DECISION_QIANGGONG][posmod(selector, 3)]

static func choose_qianggong_banker_choice(_arrangement: Dictionary, _banker: int) -> String:
	return Types.QIANG_GONG_BI_TOU

static func choose_tanpai_banker_choice(_challenger: Dictionary, _banker: Dictionary, challenger_idx: int) -> String:
	return Types.TANPAI_BANKER_GIVE if challenger_idx % 2 == 0 else Types.TANPAI_BANKER_NOT_GIVE

static func choose_tanpai_pass_choice(_arrangement: Dictionary, _banker: int) -> String:
	return Types.TANPAI_PASS_GUO

static func choose_tanpai_challenger_choice(_arrangement: Dictionary, _banker: int) -> String:
	return Types.TANPAI_CHALLENGER_FAN_HEAD

static func choose_tanpai_flip_idx() -> int:
	return 0

static func choose_angong_choice(_arrangement: Dictionary, _banker: int) -> String:
	return Types.ANGONG_OPEN
