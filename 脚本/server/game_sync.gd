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
	var revealed_bools: Array = fs.revealed
	var announced_bools: Array = fs.announced

	# 转换为 card_visibility.gd 期望的 int 数组形态
	var revealed_ids: Array = []
	var announced_ids: Array = []
	for i in range(4):
		if revealed_bools[i]: revealed_ids.append(i)
		if announced_bools[i]: announced_ids.append(i)

	# 构建 {idx: challenger_state} 映射
	var challenger_states: Dictionary = {}
	for i in range(4):
		var cs: Dictionary = src_players[i].get("challenger_state", {})
		if not cs.is_empty():
			challenger_states[i] = cs

	var snap_players: Array = []
	for i in range(4):
		var src: Dictionary = src_players[i]
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

		sp.arrangement = _clip_arrangement(src, i, your_pos, phase, revealed_ids, announced_ids, challenger_states)
		sp.decision = _clip_decision(src, i, your_pos, phase, announced_bools)

		if i == your_pos:
			sp.revealed = true
		else:
			sp.revealed = _is_arr_visible_by_pos(i, your_pos, phase, src, revealed_ids, announced_ids)

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


func _clip_arrangement(src: Dictionary, pos: int, your_pos: int, phase: int,
		revealed_ids: Array, announced_ids: Array, challenger_states: Dictionary) -> Dictionary:
	var arr: Dictionary = src.get("arrangement", {})
	if arr.is_empty():
		return {}

	if not _is_arr_visible_by_pos(pos, your_pos, phase, src, revealed_ids, announced_ids):
		return {}

	var flags: Array = _get_face_flags(pos, your_pos, phase, revealed_ids, announced_ids, challenger_states)
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
		"desc": _clip_desc(arr, pos, your_pos, flags),
	}


func _get_face_flags(pos: int, your_pos: int, phase: int,
		revealed_ids: Array, announced_ids: Array, challenger_states: Dictionary) -> Array:
	var temp_player: Dictionary = {"isHuman": (pos == your_pos)}
	return CardVisibility.get_card_flags(pos, temp_player, phase, revealed_ids, announced_ids, challenger_states)


func _is_arr_visible_by_pos(pos: int, your_pos: int, phase: int, src: Dictionary,
		revealed_ids: Array, announced_ids: Array) -> bool:
	if pos == your_pos: return true
	if phase == Types.Phase.GAME_OVER: return true
	if revealed_ids.has(pos) or announced_ids.has(pos): return true
	var cs: Dictionary = src.get("challenger_state", {})
	if cs.get("skipped", false): return true
	if cs.get("doubleZeroChoice") == Types.DOUBLE_ZERO_ZOUSHUI: return true
	return false


# M1D-02 P1: 对手决策仅在宣告后可见
func _clip_decision(src: Dictionary, _cs: Dictionary, pos: int, your_pos: int, phase: int,
		_revealed: Array, announced: Array) -> String:
	if pos == your_pos:
		return src.get("challenger_state", {}).get("decision", "")
	if (announced[pos] if pos < announced.size() else false) or phase == Types.Phase.GAME_OVER:
		return src.get("challenger_state", {}).get("decision", "")
	return ""


func _deep_copy_cards(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		if c is Dictionary:
			out.append({"rank": c.get("rank", ""), "suit": c.get("suit", "")})
	return out


# P1 修复: face_down 的牌不泄露 rank/suit
func _card_to_dict(card, face_down: bool) -> Dictionary:
	if card == null: return {}
	if face_down:
		return {"face_up": false}
	return {
		"rank": card.get("rank", ""),
		"suit": card.get("suit", ""),
		"face_up": true,
	}


func _clip_desc(arr: Dictionary, pos: int, your_pos: int, flags: Array) -> String:
	if pos == your_pos: return arr.get("desc", "")
	if _all_face_down(flags): return ""
	return arr.get("desc", "")


func _all_face_down(flags: Array) -> bool:
	for f in flags:
		if not f: return false
	return true
