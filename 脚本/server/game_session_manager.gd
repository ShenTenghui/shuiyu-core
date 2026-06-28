# game_session_manager.gd — 对局会话协调器 (M1D-03)
# 协调 GameController + GameSync 与 ws_server 之间的生命周期和命令路由。
# 不持有另一份权威对局状态。GameController 仍是唯一写入方。
class_name GameSessionManager
extends RefCounted

const GameController = preload("res://脚本/server/game_controller.gd")
const GameSync = preload("res://脚本/server/game_sync.gd")
const Types = preload("res://脚本/core/types.gd")

var _sessions: Dictionary = {}  # room_id → SessionData


class SessionData:
	var controller: RefCounted   # GameController
	var sync: RefCounted         # GameSync
	var user_to_pos: Dictionary = {}   # user_id → int (0-3)
	var pos_to_user: Array = []        # [user_id, user_id, user_id, user_id]
	# 多步 tanpai 协议暂存
	var pending_tanpai_ci: int = -1           # 当前摊牌挑战者 idx
	var pending_tanpai_banker_choice: String = ""  # "give" | "not_give"

	func _init(p_controller: RefCounted, p_sync: RefCounted,
			p_user_to_pos: Dictionary, p_pos_to_user: Array) -> void:
		controller = p_controller
		sync = p_sync
		user_to_pos = p_user_to_pos
		pos_to_user = p_pos_to_user


# ── Lifecycle ──

func create_game(room_id: String, player_ids: Array[String]) -> bool:
	if room_id.is_empty() or player_ids.size() != 4:
		return false
	if _sessions.has(room_id):
		return false

	var gc: RefCounted = GameController.new()
	if not gc.init(room_id, player_ids):
		return false

	var gs: RefCounted = GameSync.new()

	var utp: Dictionary = {}
	var ptu: Array = []
	for i in range(4):
		utp[player_ids[i]] = i
		ptu.append(player_ids[i])

	_sessions[room_id] = SessionData.new(gc, gs, utp, ptu)
	print("[GSM] game created: %s" % room_id)
	return true


func start_first_round(room_id: String) -> bool:
	var sd: SessionData = _sessions.get(room_id) as SessionData
	if not sd: return false
	sd.controller.start_round()
	return true


func remove_game(room_id: String) -> void:
	_sessions.erase(room_id)
	print("[GSM] game removed: %s" % room_id)


func has_game(room_id: String) -> bool:
	return _sessions.has(room_id)


# ── Queries ──

func get_controller(room_id: String) -> RefCounted:
	var sd: SessionData = _sessions.get(room_id) as SessionData
	return sd.controller if sd else null


func get_sync(room_id: String) -> RefCounted:
	var sd: SessionData = _sessions.get(room_id) as SessionData
	return sd.sync if sd else null


func get_position(room_id: String, user_id: String) -> int:
	var sd: SessionData = _sessions.get(room_id) as SessionData
	if not sd: return -1
	return sd.user_to_pos.get(user_id, -1)


func get_user_at_position(room_id: String, pos: int) -> String:
	var sd: SessionData = _sessions.get(room_id) as SessionData
	if not sd: return ""
	if pos < 0 or pos >= sd.pos_to_user.size(): return ""
	return sd.pos_to_user[pos]


func get_all_user_ids(room_id: String) -> Array:
	var sd: SessionData = _sessions.get(room_id) as SessionData
	if not sd: return []
	return sd.pos_to_user.duplicate()


# ── Snapshots ──

# 生成 4 份裁剪快照并映射到 user_id
func generate_snapshots(room_id: String) -> Dictionary:
	var sd: SessionData = _sessions.get(room_id) as SessionData
	if not sd: return {}

	var snaps: Array = sd.sync.generate_snapshots(sd.controller.export_full_state())
	var result: Dictionary = {}
	for pos in range(4):
		var uid: String = sd.pos_to_user[pos] if pos < sd.pos_to_user.size() else ""
		if not uid.is_empty():
			result[uid] = snaps[pos]
	return result


# ── Command handling ──

# 验证 + 路由。返回 {ok, error}
func handle_command(room_id: String, user_id: String, cmd_type: int, payload: Dictionary) -> Dictionary:
	var sd: SessionData = _sessions.get(room_id) as SessionData
	if not sd:
		return {"ok": false, "error": "GAME_NOT_IN_GAME"}

	var pos: int = sd.user_to_pos.get(user_id, -1)
	if pos < 0:
		return {"ok": false, "error": "GAME_NOT_IN_GAME"}

	var gc: RefCounted = sd.controller
	var state_before: String = _state_snapshot(gc)

	var result: Dictionary
	match cmd_type:
		ProtocolTypes.CMD_GAME_ARRANGE:
			result = _handle_arrange(sd, gc, pos, payload)
		ProtocolTypes.CMD_GAME_BET:
			result = _handle_bet(sd, gc, pos, payload)
		ProtocolTypes.CMD_GAME_DECIDE:
			result = _handle_decide(sd, gc, pos, payload)
		ProtocolTypes.CMD_GAME_TANPAI_BANKER:
			result = _handle_tanpai_banker(sd, gc, pos, payload)
		ProtocolTypes.CMD_GAME_TANPAI_PASS:
			result = _handle_tanpai_pass(sd, gc, pos, payload)
		ProtocolTypes.CMD_GAME_TANPAI_CHALLENGER:
			result = _handle_tanpai_challenger(sd, gc, pos, payload)
		ProtocolTypes.CMD_GAME_ANGONG:
			result = _handle_angong(sd, gc, pos, payload)
		ProtocolTypes.CMD_GAME_QIANGGONG_BANKER:
			result = _handle_qianggong_banker(sd, gc, pos, payload)
		_:
			result = {"ok": false, "error": "GAME_INVALID_ACTION"}

	if not result.ok:
		_verify_state_unchanged(state_before, gc, result.error)
	return result


# ── Individual command handlers ──

func _handle_arrange(sd: SessionData, gc: RefCounted, pos: int, payload: Dictionary) -> Dictionary:
	if gc.phase != GameController.Phase.ALL_ARRANGING:
		return _err("GAME_INVALID_ACTION")

	var head: Array = payload.get("head", [])
	var tail: Array = payload.get("tail", [])
	if head.size() != 2 or tail.size() != 2:
		return _err("GAME_INVALID_ARRANGEMENT")

	var all_idx: Array = []
	for v in head + tail:
		if not (v is int) and not (v is float):
			return _err("GAME_INVALID_ARRANGEMENT")
		all_idx.append(int(v))

	var seen: Dictionary = {}
	for idx in all_idx:
		if idx < 0 or idx >= 4 or seen.has(idx):
			return _err("GAME_INVALID_ARRANGEMENT")
		seen[idx] = true

	if not gc.submit_arrangement(pos, [all_idx[0], all_idx[1]], [all_idx[2], all_idx[3]]):
		return _err("GAME_INVALID_ARRANGEMENT")

	return {"ok": true}


func _handle_bet(sd: SessionData, gc: RefCounted, pos: int, payload: Dictionary) -> Dictionary:
	if gc.phase != GameController.Phase.BETTING:
		return _err("GAME_INVALID_ACTION")
	if pos == gc.banker_idx:
		return _err("GAME_NOT_YOUR_TURN")

	var amount: int = int(payload.get("amount", 0))
	if amount < 1:
		return _err("GAME_INVALID_ACTION")

	if not gc.submit_bet(pos, amount):
		return _err("GAME_NOT_YOUR_TURN")

	return {"ok": true}


func _handle_decide(sd: SessionData, gc: RefCounted, pos: int, payload: Dictionary) -> Dictionary:
	if gc.phase != GameController.Phase.ALL_DECIDING:
		return _err("GAME_INVALID_ACTION")
	if pos == gc.banker_idx:
		return _err("GAME_NOT_YOUR_TURN")

	var action: String = payload.get("action", "")
	var valid: Array = [Types.DECISION_TANPAI, Types.DECISION_QIANGGONG, Types.DECISION_ANGONG, Types.DECISION_ZOUSHUI]
	if action not in valid:
		return _err("GAME_INVALID_ACTION")

	if not gc.submit_decision(pos, action):
		return _err("GAME_INVALID_ACTION")

	return {"ok": true}


func _handle_tanpai_banker(sd: SessionData, gc: RefCounted, pos: int, payload: Dictionary) -> Dictionary:
	if gc.phase != GameController.Phase.BANKER_QUEUE:
		return _err("GAME_INVALID_ACTION")
	if pos != gc.banker_idx:
		return _err("GAME_NOT_YOUR_TURN")

	var item: Dictionary = gc.get_current_challenger()
	if item.is_empty() or item.action != Types.DECISION_TANPAI:
		return _err("GAME_INVALID_ACTION")

	var banker_choice: String = payload.get("choice", "")
	if banker_choice not in [Types.TANPAI_BANKER_GIVE, Types.TANPAI_BANKER_NOT_GIVE]:
		return _err("GAME_INVALID_ACTION")

	# 暂存 banker 选择，等待 pass 或 challenger 子命令提交
	sd.pending_tanpai_ci = item.idx
	sd.pending_tanpai_banker_choice = banker_choice
	return {"ok": true, "pending": true}


func _handle_tanpai_pass(sd: SessionData, gc: RefCounted, pos: int, payload: Dictionary) -> Dictionary:
	if sd.pending_tanpai_ci < 0 or sd.pending_tanpai_banker_choice != Types.TANPAI_BANKER_GIVE:
		return _err("GAME_INVALID_ACTION")
	if pos != sd.pending_tanpai_ci:
		return _err("GAME_NOT_YOUR_TURN")

	var pass_choice: String = payload.get("choice", "")
	if pass_choice not in [Types.TANPAI_PASS_GUO, Types.TANPAI_PASS_YINGYAO]:
		return _err("GAME_INVALID_ACTION")

	var h_flip: int = -1
	var t_flip: int = -1
	if pass_choice == Types.TANPAI_PASS_YINGYAO:
		h_flip = clampi(int(payload.get("head_flip", 0)), 0, 1)
		t_flip = clampi(int(payload.get("tail_flip", 0)), 0, 1)

	var ci: int = sd.pending_tanpai_ci
	_clear_pending_tanpai(sd)

	if not gc.submit_tanpai(ci, Types.TANPAI_BANKER_GIVE, pass_choice, "", h_flip, t_flip):
		return _err("GAME_INVALID_ACTION")

	return {"ok": true}


func _handle_tanpai_challenger(sd: SessionData, gc: RefCounted, pos: int, payload: Dictionary) -> Dictionary:
	if sd.pending_tanpai_ci < 0 or sd.pending_tanpai_banker_choice != Types.TANPAI_BANKER_NOT_GIVE:
		return _err("GAME_INVALID_ACTION")
	if pos != sd.pending_tanpai_ci:
		return _err("GAME_NOT_YOUR_TURN")

	var fan_choice: String = payload.get("choice", "")
	var valid_fan: Array = [
		Types.TANPAI_CHALLENGER_RENSHU,
		Types.TANPAI_CHALLENGER_FAN_HEAD,
		Types.TANPAI_CHALLENGER_FAN_TAIL,
		Types.TANPAI_CHALLENGER_FAN_BOTH,
	]
	if fan_choice not in valid_fan:
		return _err("GAME_INVALID_ACTION")

	var h_flip: int = -1
	var t_flip: int = -1
	if fan_choice == Types.TANPAI_CHALLENGER_FAN_HEAD or fan_choice == Types.TANPAI_CHALLENGER_FAN_BOTH:
		h_flip = clampi(int(payload.get("head_flip", 0)), 0, 1)
	if fan_choice == Types.TANPAI_CHALLENGER_FAN_TAIL or fan_choice == Types.TANPAI_CHALLENGER_FAN_BOTH:
		t_flip = clampi(int(payload.get("tail_flip", 0)), 0, 1)

	var ci: int = sd.pending_tanpai_ci
	_clear_pending_tanpai(sd)

	if not gc.submit_tanpai(ci, Types.TANPAI_BANKER_NOT_GIVE, "", fan_choice, h_flip, t_flip):
		return _err("GAME_INVALID_ACTION")

	return {"ok": true}


func _handle_angong(sd: SessionData, gc: RefCounted, pos: int, payload: Dictionary) -> Dictionary:
	if gc.phase != GameController.Phase.BANKER_QUEUE:
		return _err("GAME_INVALID_ACTION")
	if pos != gc.banker_idx:
		return _err("GAME_NOT_YOUR_TURN")

	var item: Dictionary = gc.get_current_challenger()
	if item.is_empty() or item.action != Types.DECISION_ANGONG:
		return _err("GAME_INVALID_ACTION")

	var choice: String = payload.get("choice", "")
	if choice not in [Types.ANGONG_OPEN, Types.ANGONG_NOT_OPEN]:
		return _err("GAME_INVALID_ACTION")

	if not gc.submit_angong(item.idx, choice):
		return _err("GAME_INVALID_ACTION")

	return {"ok": true}


func _handle_qianggong_banker(sd: SessionData, gc: RefCounted, pos: int, payload: Dictionary) -> Dictionary:
	if gc.phase != GameController.Phase.BANKER_QUEUE:
		return _err("GAME_INVALID_ACTION")
	if pos != gc.banker_idx:
		return _err("GAME_NOT_YOUR_TURN")

	var item: Dictionary = gc.get_current_challenger()
	if item.is_empty() or item.action != Types.DECISION_QIANGGONG:
		return _err("GAME_INVALID_ACTION")

	var choice: String = payload.get("choice", "")
	if choice not in [Types.QIANG_GONG_BI_TOU, Types.QIANG_GONG_BI_WEI]:
		return _err("GAME_INVALID_ACTION")

	if not gc.submit_qianggong(item.idx, choice):
		return _err("GAME_INVALID_ACTION")

	return {"ok": true}


# ── Round auto-advance ──

# 如果当前小局结束且未 GAME_OVER，自动启动下一小局
func maybe_advance_round(room_id: String) -> bool:
	var sd: SessionData = _sessions.get(room_id) as SessionData
	if not sd: return false
	var gc: RefCounted = sd.controller
	if gc.is_game_over(): return false
	if gc.phase == GameController.Phase.ROUND_END:
		gc.start_round()
		return true
	return false


# ── Helpers ──

func _err(code: String) -> Dictionary:
	return {"ok": false, "error": code}


func _clear_pending_tanpai(sd: SessionData) -> void:
	sd.pending_tanpai_ci = -1
	sd.pending_tanpai_banker_choice = ""


func _verify_state_unchanged(state_before: String, gc: RefCounted, error_code: String) -> void:
	var state_after: String = _state_snapshot(gc)
	if state_before != state_after:
		push_error("[GSM] CONTROLLER STATE CHANGED ON REJECTION! code=%s" % error_code)


func _state_snapshot(gc: RefCounted) -> String:
	var fs: Dictionary = gc.export_full_state()
	fs.erase("deck")
	fs.erase("log")
	return JSON.stringify(fs)
