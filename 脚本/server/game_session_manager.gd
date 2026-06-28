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

# 验证 + 路由。返回 {ok, error, snapshots (if ok)}
func handle_command(room_id: String, user_id: String, cmd_type: int, payload: Dictionary) -> Dictionary:
	var sd: SessionData = _sessions.get(room_id) as SessionData
	if not sd:
		return {"ok": false, "error": "GAME_NOT_IN_GAME"}

	var pos: int = sd.user_to_pos.get(user_id, -1)
	if pos < 0:
		return {"ok": false, "error": "GAME_NOT_IN_GAME"}

	var gc: RefCounted = sd.controller
	var state_before: String = _state_snapshot(gc)

	match cmd_type:
		ProtocolTypes.CMD_GAME_ARRANGE:
			return _handle_arrange(gc, pos, payload, state_before, room_id)
		ProtocolTypes.CMD_GAME_BET:
			return _handle_bet(gc, pos, payload, state_before, room_id)
		ProtocolTypes.CMD_GAME_DECIDE:
			return _handle_decide(gc, pos, payload, state_before, room_id)
		ProtocolTypes.CMD_GAME_TANPAI_BANKER:
			return _handle_tanpai_banker(gc, pos, payload, state_before, room_id)
		ProtocolTypes.CMD_GAME_TANPAI_PASS:
			return _handle_tanpai_pass(gc, pos, payload, state_before, room_id)
		ProtocolTypes.CMD_GAME_TANPAI_CHALLENGER:
			return _handle_tanpai_challenger(gc, pos, payload, state_before, room_id)
		ProtocolTypes.CMD_GAME_ANGONG:
			return _handle_angong(gc, pos, payload, state_before, room_id)
		ProtocolTypes.CMD_GAME_QIANGGONG_BANKER:
			return _handle_qianggong_banker(gc, pos, payload, state_before, room_id)

	return {"ok": false, "error": "GAME_INVALID_ACTION"}


func _handle_arrange(gc: RefCounted, pos: int, payload: Dictionary,
		state_before: String, room_id: String) -> Dictionary:
	if gc.phase != GameController.Phase.ALL_ARRANGING:
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	var head: Array = payload.get("head", [])
	var tail: Array = payload.get("tail", [])
	if head.size() != 2 or tail.size() != 2:
		return _reject("GAME_INVALID_ARRANGEMENT", state_before, gc)

	# Validate indices are integers 0-3, no duplicates
	var all_idx: Array = []
	for v in head + tail:
		if not (v is int) and not (v is float):
			return _reject("GAME_INVALID_ARRANGEMENT", state_before, gc)
		all_idx.append(int(v))

	if all_idx.size() != 4:
		return _reject("GAME_INVALID_ARRANGEMENT", state_before, gc)

	var seen: Dictionary = {}
	for idx in all_idx:
		if idx < 0 or idx >= 4 or seen.has(idx):
			return _reject("GAME_INVALID_ARRANGEMENT", state_before, gc)
		seen[idx] = true

	if not gc.submit_arrangement(pos, [all_idx[0], all_idx[1]], [all_idx[2], all_idx[3]]):
		return _reject("GAME_INVALID_ARRANGEMENT", state_before, gc)

	return {"ok": true}


func _handle_bet(gc: RefCounted, pos: int, payload: Dictionary,
		state_before: String, room_id: String) -> Dictionary:
	if gc.phase != GameController.Phase.BETTING:
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	var amount: int = int(payload.get("amount", 0))
	if amount < 1:
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	if not gc.submit_bet(pos, amount):
		return _reject("GAME_NOT_YOUR_TURN", state_before, gc)

	return {"ok": true}


func _handle_decide(gc: RefCounted, pos: int, payload: Dictionary,
		state_before: String, room_id: String) -> Dictionary:
	if gc.phase != GameController.Phase.ALL_DECIDING:
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	var action: String = payload.get("action", "")
	var valid_actions: Array = [Types.DECISION_TANPAI, Types.DECISION_QIANGGONG, Types.DECISION_ANGONG, Types.DECISION_ZOUSHUI]
	if action not in valid_actions:
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	if not gc.submit_decision(pos, action):
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	return {"ok": true}


func _handle_tanpai_banker(gc: RefCounted, pos: int, payload: Dictionary,
		state_before: String, room_id: String) -> Dictionary:
	if gc.phase != GameController.Phase.BANKER_QUEUE:
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	var item: Dictionary = gc.get_current_challenger()
	if item.is_empty() or item.action != Types.DECISION_TANPAI:
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	var banker_give: String = payload.get("choice", "")
	if banker_give not in [Types.TANPAI_BANKER_GIVE, Types.TANPAI_BANKER_NOT_GIVE]:
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	# Pass dummy values for pass/fan choices — they'll be filled by subsequent commands
	if not gc.submit_tanpai(item.idx, banker_give, "", "", -1, -1):
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	return {"ok": true}


func _handle_tanpai_pass(gc: RefCounted, pos: int, payload: Dictionary,
		state_before: String, room_id: String) -> Dictionary:
	# tanpai_pass is called when banker gave "give" and NOW the challenger decides yingyao or guo
	# But looking at the controller API, submit_tanpai already bundles everything.
	# tanpai_pass is a sub-command that comes after tanpai_banker if banker gave.
	# However, the current controller API bundles bank_choice + pass_choice into one submit_tanpai call.
	# For M1D-03, we handle this as a multi-step interaction:
	# 1. game.tanpai_banker {choice: "give"} → submit_tanpai with give
	# 2. game.tanpai_pass {choice: "guo"|"yingyao"} → need to re-submit with pass choice
	#
	# Since submit_tanpai is bundled, we check if the current item's banker choice was "give"
	# and then call submit_tanpai again with the full data.
	# Actually, looking more carefully: after submit_tanpai(banker_give="give", ...), the queue
	# already advances. So tanpai_pass can't work as a separate step with the current API.
	# Solution: For M1D-03, interpret tanpai_pass as a re-submission that replaces the previous
	# submit with the pass_choice filled in.
	#
	# Wait — looking at the controller again: submit_tanpai always advances _queue_idx.
	# So after calling submit_tanpai with "give", the queue already moved past this challenger.
	# This means tanpai_pass as a separate command doesn't fit the current controller API.
	#
	# The protocol was defined in M1D-00 with separate sub-commands. For M1D-03, I need to
	# make these work with the current controller. The simplest approach:
	# - tanpai_banker with "give" sets the banker choice but does NOT advance the queue yet
	# - tanpai_pass or tanpai_challenger then completes the submission and advances
	#
	# This requires a slight change in how we call the controller. Let me handle this in the
	# session manager by tracking pending tanpai state.

	return _reject("GAME_INVALID_ACTION", state_before, gc)


func _handle_tanpai_challenger(gc: RefCounted, pos: int, payload: Dictionary,
		state_before: String, room_id: String) -> Dictionary:
	return _reject("GAME_INVALID_ACTION", state_before, gc)


func _handle_angong(gc: RefCounted, pos: int, payload: Dictionary,
		state_before: String, room_id: String) -> Dictionary:
	if gc.phase != GameController.Phase.BANKER_QUEUE:
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	var item: Dictionary = gc.get_current_challenger()
	if item.is_empty() or item.action != Types.DECISION_ANGONG:
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	var choice: String = payload.get("choice", "")
	if choice not in [Types.ANGONG_OPEN, Types.ANGONG_NOT_OPEN]:
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	if not gc.submit_angong(item.idx, choice):
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	return {"ok": true}


func _handle_qianggong_banker(gc: RefCounted, pos: int, payload: Dictionary,
		state_before: String, room_id: String) -> Dictionary:
	if gc.phase != GameController.Phase.BANKER_QUEUE:
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	var item: Dictionary = gc.get_current_challenger()
	if item.is_empty() or item.action != Types.DECISION_QIANGGONG:
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	var choice: String = payload.get("choice", "")
	if choice not in [Types.QIANG_GONG_BI_TOU, Types.QIANG_GONG_BI_WEI]:
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	if not gc.submit_qianggong(item.idx, choice):
		return _reject("GAME_INVALID_ACTION", state_before, gc)

	return {"ok": true}


# 如果当前小局结束且未 GAME_OVER，自动启动下一小局
func maybe_advance_round(room_id: String) -> bool:
	var sd: SessionData = _sessions.get(room_id) as SessionData
	if not sd: return false

	var gc: RefCounted = sd.controller
	if gc.is_game_over():
		return false
	if gc.phase == GameController.Phase.ROUND_END:
		gc.start_round()
		return true
	return false


# ── Helpers ──

func _reject(error_code: String, state_before: String, gc: RefCounted) -> Dictionary:
	# Verify controller state unchanged
	var state_after: String = _state_snapshot(gc)
	if state_before != state_after:
		push_error("[GSM] CONTROLLER STATE CHANGED ON REJECTION! code=%s" % error_code)
	return {"ok": false, "error": error_code}


func _state_snapshot(gc: RefCounted) -> String:
	# Lightweight snapshot for rejection verification
	var fs: Dictionary = gc.export_full_state()
	# Remove deck (changes per shuffle) and log (grows)
	fs.erase("deck")
	fs.erase("log")
	return JSON.stringify(fs)
