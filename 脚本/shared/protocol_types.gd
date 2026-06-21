# protocol_types.gd — M1B Day1 Command/Event 类型常量
# 使用 JSON 编码 (非 MessagePack)。M1C 之后按需替换。
class_name ProtocolTypes
extends RefCounted

# ── Command types (Client → Server) ──

const CMD_AUTH_REGISTER  := 1
const CMD_AUTH_LOGIN     := 2
const CMD_AUTH_LOGOUT    := 3
const CMD_AUTH_RESUME    := 4
const CMD_SYSTEM_PING    := 99

# 注意: 没有 CMD_AUTH_VERIFY_TOKEN。
# verify_token 只在 auth.resume 内部由 Godot Headless 调 DB Gateway。
# 客户端永远不直接调 verify_token。

# ── Event types (Server → Client) ──

const EVT_WELCOME         := 0
const EVT_ERROR           := 1
const EVT_PONG            := 99
const EVT_AUTH_LOGGED_IN  := 101
const EVT_AUTH_LOGGED_OUT := 102
const EVT_AUTH_RESUME_OK  := 103

# ── Lobby (M1C Day1) ──

const CMD_LOBBY_ENTER_MATCHMAKING := 10
const CMD_LOBBY_LEAVE_MATCHMAKING := 11

const EVT_LOBBY_STATE_CHANGED         := 200
const EVT_LOBBY_MATCHMAKING_ENTERED   := 201
const EVT_LOBBY_MATCHMAKING_LEFT      := 202

# ── Room (M1C Day2) ──

const CMD_ROOM_LEAVE        := 12

const EVT_ROOM_CREATED      := 300
const EVT_ROOM_LEFT         := 301
const EVT_ROOM_CLOSED       := 302

# ── Auth error codes ──

const ERR_AUTH_INVALID_CREDENTIALS := "AUTH_INVALID_CREDENTIALS"
const ERR_AUTH_EMAIL_EXISTS        := "AUTH_EMAIL_EXISTS"
const ERR_AUTH_TOKEN_EXPIRED       := "AUTH_TOKEN_EXPIRED"
const ERR_AUTH_TOKEN_INVALID       := "AUTH_TOKEN_INVALID"
const ERR_AUTH_TOKEN_REVOKED       := "AUTH_TOKEN_REVOKED"
const ERR_AUTH_WEAK_PASSWORD       := "AUTH_WEAK_PASSWORD"
const ERR_AUTH_ACCOUNT_BANNED      := "AUTH_ACCOUNT_BANNED"
const ERR_AUTH_ACCOUNT_LOCKED      := "AUTH_ACCOUNT_LOCKED"
const ERR_INVALID_PARAMS           := "INVALID_PARAMS"
const ERR_INTERNAL                 := "INTERNAL_ERROR"
