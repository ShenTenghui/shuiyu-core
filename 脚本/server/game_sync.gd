# game_sync.gd — 状态快照与牌面裁剪 (M1D-02)
# 只读从 GameController.export_full_state() 生成四份裁剪快照。
class_name GameSync
extends RefCounted

const CardVisibility = preload("res://脚本/core/card_visibility.gd")
const Types = preload("res://脚本/core/types.gd")

var _seq: int = 0


func generate_snapshots(full_state: Dictionary) -> Array:
	var snapshots: Array = []
	_seq += 1
	for receiver_pos in range(4):
		snapshots.append(_build_snapshot(full_state, receiver_pos))
	return snapshots


func _build_snapshot(fs: Dictionary, your_pos: int) -> Dictionary:
	var src_players: Array = fs.players
	var phase: int = fs.phase
	var revealed: Array = fs.revealed
	var announced: Array = fs.announced

	var snap_players: Array = []
	for i in range(4):
		var src: Dictionary = src_players[i]
		var cs: Dictionary = src.get("challenger_state", {})
		var sp: Dictionary = {
			"position": src.position,
			"name": src.name,
			"score": src.score,
			"bet_amount": src.bet_amount,
			"is_banker": src.is_banker,
		}

		if i == your_pos:
			sp.cards = _deep_copy_cards(src.get("cards", []))
		else:
			sp.cards = []

		sp.arrangement = _clip_arrangement(src, cs, i, your_pos, phase, revealed, announced)
		sp.decision = _clip_decision(src, cs, i, your_pos, phase, revealed, announced)

		# revealed: receiver perspective
		if i == your_pos:
			sp.revealed = true
		else:
			sp.revealed = _is_arr_visible(i, your_pos, phase, cs, revealed, announced)

		snap_players.append(sp)

	return {
		"game_id": fs.game_id,
		"seq": _seq,
		"phase": phase,
		"round": fs.current_round,
		"banker_position": fs.banker_idx,
		"your_position": your_pos,
		"players": snap_players,
		"timer_remaining_ms": 0,
	}


func _clip_arrangement(src: Dictionary, cs: Dictionary, pos: int, your_pos: int, phase: int, revealed: Array, announced: Array) -> Dictionary:
	var arr: Dictionary = src.get("arrangement", {})
	if arr.is_empty():
		return {}

	if not _is_arr_visible(pos, your_pos, phase, cs, revealed, announced):
		return {}

	var flags: Array = _get_face_flags(pos, your_pos, phase, cs, revealed, announced)
	var fh: Array = arr.get("fishHead", [])
	var ft: Array = arr.get("fishTail", [])

	var head_out: Array = []
	for hi in range(fh.size()):
		var fd: bool = flags[hi] if hi < flags.size() else true
		head_out.append(_card_to_dict(fh[hi], fd))

	var tail_out: Array = []
	for ti in range(ft.size()):
		var fd: bool = flags[ti + 2] if (ti + 2) < flags.size() else true
		tail_out.append(_card_to_dict(ft[ti], fd))

	return {
		"head": head_out,
		"tail": tail_out,
		"desc": arr.get("desc", "") if not (pos != your_pos and _all_face_down(flags)) else "",
	}


func _get_face_flags(pos: int, your_pos: int, phase: int, cs: Dictionary, revealed: Array, announced: Array) -> Array:
	var temp_player: Dictionary = {"isHuman": (pos == your_pos)}
	var cs_copy: Dictionary = {}
	for key in cs.keys():
		cs_copy[key] = cs[key]
	return CardVisibility.get_card_flags(pos, temp_player, phase, revealed, announced, cs_copy)


func _is_arr_visible(pos: int, your_pos: int, phase: int, cs: Dictionary, revealed: Array, announced: Array) -> bool:
	if pos == your_pos: return true
	if phase == Types.Phase.GAME_OVER: return true
	if revealed[pos] or announced[pos]: return true
	if cs.get("skipped", false): return true
	if cs.get("doubleZeroChoice") == Types.DOUBLE_ZERO_ZOUSHUI: return true
	return false


# M1D-02 P1: 对手决策仅在宣告后可见；自己始终可见自己。
func _clip_decision(src: Dictionary, cs: Dictionary, pos: int, your_pos: int, phase: int, _revealed: Array, announced: Array) -> String:
	if pos == your_pos:
		return cs.get("decision", "")
	if announced[pos] or phase == Types.Phase.GAME_OVER:
		return cs.get("decision", "")
	return ""


func _deep_copy_cards(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		if c is Dictionary:
			out.append({"rank": c.get("rank", ""), "suit": c.get("suit", "")})
	return out


func _card_to_dict(card, face_down: bool) -> Dictionary:
	if card == null: return {}
	return {"rank": card.get("rank", ""), "suit": card.get("suit", ""), "face_up": not face_down}


func _all_face_down(flags: Array) -> bool:
	for f in flags:
		if not f: return false
	return true
