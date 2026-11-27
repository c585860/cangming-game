extends RefCounted

# Real ENet Multiplayer Session Engine (Godot 4.5 SceneMultiplayer + ENetMultiplayerPeer)
# Supports both Core Packs (Cangming & Cataclysm):
#  - Real UDP ENet transport via dedicated SceneMultiplayer instance (poll-driven, zero tree conflicts!)
#  - Automatic Host -> Client "welcome" handshake syncing active pack_id, seed, minutes & weather!
#  - 10 Hz delta player_snapshot sync + Host relay to all connected peers
#  - Shared world_mutation relay (door open/close, tile smash, monster hit)
#  - Live multiplayer Co-op Chat!

signal mode_changed(new_mode: int)
signal peer_joined(peer_id: int, peer_name: String)
signal peer_left(peer_id: int)
signal remote_snapshot_applied(peer_id: int)
signal welcome_received(pack_id: String, seed_val: int, minutes_val: int, weather_kind: int, host_name: String)
signal world_mutation_applied(mutation: Dictionary)
signal chat_received(peer_id: int, sender: String, text: String)
signal status_message(text: String)

enum Mode { OFFLINE = 0, HOST = 1, CLIENT = 2 }

const PROTOCOL_VERSION := 2
const DEFAULT_PORT := 27015
const DEFAULT_MAX_PEERS := 8
const SYNC_INTERVAL_SEC := 0.10

var mode: int = Mode.OFFLINE
var host_address := "127.0.0.1"
var port := DEFAULT_PORT
var max_peers := DEFAULT_MAX_PEERS
var peer: ENetMultiplayerPeer = null
var mp: SceneMultiplayer = null
var _bound_world: Object = null
var _weather_kind_getter: Callable
var _sync_accum := 0.0
var _last_snapshot_sig := ""
var chat_log: Array[Dictionary] = []


func mode_label() -> String:
	match mode:
		Mode.HOST:
			return "联机房主 (HOST)"
		Mode.CLIENT:
			return "联机客端 (CLIENT)"
		_:
			return "单人离线 (OFFLINE)"


func is_online() -> bool:
	return mode != Mode.OFFLINE


func set_weather_getter(cb: Callable) -> void:
	_weather_kind_getter = cb


func _setup_mp(world: Object) -> void:
	_bound_world = world
	mp = SceneMultiplayer.new()
	mp.root_path = NodePath("/root")
	mp.peer_connected.connect(_on_peer_connected)
	mp.peer_disconnected.connect(_on_peer_disconnected)
	mp.connected_to_server.connect(_on_connected_to_server)
	mp.connection_failed.connect(_on_connection_failed)
	mp.server_disconnected.connect(_on_server_disconnected)
	mp.peer_packet.connect(_on_peer_packet)


func host_session(listen_port := DEFAULT_PORT, peer_limit := DEFAULT_MAX_PEERS, world: Object = null) -> Dictionary:
	leave_session(world)
	port = clampi(listen_port, 1024, 65535)
	max_peers = clampi(peer_limit, 2, 32)
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(port, max_peers)
	if err != OK:
		return {"ok": false, "message": "无法监听 ENet 端口 %d (错误码 %d)。" % [port, err]}
	_setup_mp(world)
	peer = enet
	mp.multiplayer_peer = peer
	if world != null and world.has_method("set_local_peer_id"):
		world.set_local_peer_id(1)
	mode = Mode.HOST
	_last_snapshot_sig = ""
	mode_changed.emit(mode)
	var pname: String = str(world.get_pack_name()) if (world != null and world.has_method("get_pack_name")) else ""
	return {"ok": true, "message": "已开启 ENet 联机房主，监听端口 %d（%s，最多 %d 人）。" % [port, pname, max_peers]}


func join_session(address := "127.0.0.1", target_port := DEFAULT_PORT, world: Object = null) -> Dictionary:
	leave_session(world)
	host_address = address.strip_edges() if not address.strip_edges().is_empty() else "127.0.0.1"
	port = clampi(target_port, 1024, 65535)
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(host_address, port)
	if err != OK:
		return {"ok": false, "message": "无法连接 ENet 主机 %s:%d (错误码 %d)。" % [host_address, port, err]}
	_setup_mp(world)
	peer = enet
	mp.multiplayer_peer = peer
	mode = Mode.CLIENT
	_last_snapshot_sig = ""
	mode_changed.emit(mode)
	return {"ok": true, "message": "正在连接 ENet 联机房 %s:%d ..." % [host_address, port]}


func leave_session(world: Object = null) -> void:
	var w := world if world != null else _bound_world
	if mp != null:
		mp.multiplayer_peer = null
		mp = null
	if peer != null:
		peer.close()
		peer = null
	if w != null and w.has_method("clear_remote_players"):
		w.clear_remote_players()
	if w != null and w.has_method("set_local_peer_id"):
		w.set_local_peer_id(1)
	_bound_world = null
	_last_snapshot_sig = ""
	if mode != Mode.OFFLINE:
		mode = Mode.OFFLINE
		mode_changed.emit(mode)


# Convenience wrappers for UI panels
func host_from_ui(world: Object, listen_port: int) -> String:
	return str(host_session(listen_port, DEFAULT_MAX_PEERS, world).get("message", ""))


func join_from_ui(world: Object, address: String, target_port: int) -> String:
	return str(join_session(address, target_port, world).get("message", ""))


func disconnect_from_ui(world: Object) -> String:
	leave_session(world)
	return "已断开联机，切回单人离线模式。"


func tick(delta: float, world: Object, facing_x := 1, posture := "") -> void:
	if mp != null:
		mp.poll()
	if mode == Mode.OFFLINE or world == null or mp == null:
		return
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_sync_accum += delta
	if _sync_accum < SYNC_INTERVAL_SEC:
		return
	_sync_accum = 0.0
	sync_local_state(world, facing_x, posture, false)


func sync_local_state(world: Object, facing_x := 1, posture := "", force := false) -> Dictionary:
	if world == null or not world.has_method("export_player_snapshot"):
		return {}
	var snap: Dictionary = world.export_player_snapshot()
	snap["facing_x"] = facing_x
	snap["posture"] = posture
	snap["sync_ms"] = Time.get_ticks_msec()
	var sig := "%s|%d|%d|%s|%d|%s" % [
		str(snap.get("pos", Vector2i.ZERO)),
		int(snap.get("floor", 0)),
		facing_x,
		posture,
		int(snap.get("move_mode", 0)),
		str(snap.get("name", "")),
	]
	if force or sig != _last_snapshot_sig:
		_last_snapshot_sig = sig
		_send_packet({"kind": "player_snapshot", "protocol": PROTOCOL_VERSION, "data": snap}, 0)
	return snap


func broadcast_world_mutation(mutation: Dictionary) -> void:
	if mode == Mode.OFFLINE or mp == null:
		return
	_send_packet({"kind": "world_mutation", "protocol": PROTOCOL_VERSION, "mutation": mutation}, 0)


func receive_remote_snapshot(peer_id: int, snapshot: Dictionary, world: Object) -> bool:
	if world == null or not world.has_method("apply_remote_snapshot"):
		return false
	var existed := false
	for row: Dictionary in world.list_remote_players():
		if int(row.get("peer_id", 0)) == peer_id:
			existed = true
			break
	var ok: bool = world.apply_remote_snapshot(peer_id, snapshot)
	if ok:
		if not existed:
			peer_joined.emit(peer_id, str(snapshot.get("name", "联机同道")))
		remote_snapshot_applied.emit(peer_id)
	return ok


func dispatch_action(world: Object, action_dict: Dictionary) -> Dictionary:
	if world == null or not world.has_method("submit_player_action"):
		return {"ok": false, "message": ""}
	var result: Dictionary = world.submit_player_action(action_dict)
	if mode != Mode.OFFLINE and bool(result.get("ok", false)):
		sync_local_state(world, 1, "", true)
	return result


func send_chat(world: Object, text: String) -> void:
	var clean := text.strip_edges()
	if clean.is_empty() or world == null:
		return
	var pid: int = int(world.get_local_peer_id())
	var pname: String = str(world.get_player_name())
	_record_chat(pid, pname, clean)
	if mode != Mode.OFFLINE:
		_send_packet({"kind": "chat", "protocol": PROTOCOL_VERSION, "peer_id": pid, "name": pname, "text": clean}, 0)


func _record_chat(pid: int, pname: String, clean: String) -> void:
	chat_log.push_front({"peer_id": pid, "name": pname, "text": clean})
	if chat_log.size() > 40:
		chat_log.resize(40)
	chat_received.emit(pid, pname, clean)


func spawn_mock_peer(peer_id: int, peer_name: String, tile_pos: Vector2i, world: Object) -> bool:
	var snap := {
		"peer_id": peer_id,
		"name": peer_name,
		"pos": tile_pos,
		"floor": int(world.floor),
		"facing_x": -1,
		"move_mode": 0,
		"posture": "",
		"wielded": -1,
		"worn_overlays": PackedStringArray(["overlay_worn_tunic", "overlay_worn_pants", "overlay_worn_boots", "overlay_worn_cloak"]),
		"rank_label": "初学乍练",
		"sync_ms": Time.get_ticks_msec(),
	}
	return receive_remote_snapshot(peer_id, snap, world)


func status_dict(world: Object) -> Dictionary:
	var m_str := "HOST" if mode == Mode.HOST else ("CLIENT" if mode == Mode.CLIENT else "OFFLINE")
	return {
		"protocol_version": PROTOCOL_VERSION,
		"mode": m_str,
		"mode_int": mode,
		"mode_label": mode_label(),
		"host_address": host_address,
		"port": port,
		"max_peers": max_peers,
		"local_peer_id": int(world.get_local_peer_id()) if world != null else 1,
		"player_name": str(world.get_player_name()) if world != null else "江湖少侠",
		"remote_count": int(world.remote_player_count()) if world != null else 0,
		"connected": peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED,
	}


func _send_packet(payload: Dictionary, target_peer := 0) -> void:
	if mp == null or peer == null:
		return
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var raw := var_to_bytes(payload)
	mp.send_bytes(raw, target_peer, MultiplayerPeer.TRANSFER_MODE_RELIABLE)


func _on_peer_connected(id: int) -> void:
	if mode == Mode.HOST and _bound_world != null:
		var wkind := -1
		if _weather_kind_getter.is_valid():
			wkind = int(_weather_kind_getter.call())
		var welcome := {
			"kind": "welcome",
			"protocol": PROTOCOL_VERSION,
			"pack_id": str(_bound_world.get_pack_id()) if _bound_world.has_method("get_pack_id") else "cangming",
			"seed": int(_bound_world.seed),
			"minutes": int(_bound_world.minutes),
			"weather_kind": wkind,
			"host_name": str(_bound_world.get_player_name()),
		}
		_send_packet(welcome, id)
		# Immediately send host's own snapshot to the newcomer!
		var snap: Dictionary = _bound_world.export_player_snapshot()
		snap["sync_ms"] = Time.get_ticks_msec()
		_send_packet({"kind": "player_snapshot", "protocol": PROTOCOL_VERSION, "data": snap}, id)
		status_message.emit("联机玩家 (节点 %d) 加入了房间！" % id)


func _on_peer_disconnected(id: int) -> void:
	if _bound_world != null and _bound_world.has_method("remove_remote_player"):
		_bound_world.remove_remote_player(id)
	peer_left.emit(id)
	status_message.emit("联机玩家 (节点 %d) 离开了房间。" % id)


func _on_connected_to_server() -> void:
	if mp != null and _bound_world != null and _bound_world.has_method("set_local_peer_id"):
		_bound_world.set_local_peer_id(mp.get_unique_id())
	status_message.emit("已成功连接 ENet 主机 %s:%d（节点 %d）！" % [host_address, port, mp.get_unique_id() if mp != null else 0])
	if _bound_world != null:
		sync_local_state(_bound_world, 1, "", true)


func _on_connection_failed() -> void:
	status_message.emit("连接 ENet 主机 %s:%d 失败。" % [host_address, port])
	leave_session(_bound_world)


func _on_server_disconnected() -> void:
	status_message.emit("与房主断开连接，已切回单人模式。")
	leave_session(_bound_world)


func _on_peer_packet(from_id: int, packet: PackedByteArray) -> void:
	var decoded = bytes_to_var(packet)
	if typeof(decoded) != TYPE_DICTIONARY:
		return
	var payload: Dictionary = decoded
	var kind: String = str(payload.get("kind", ""))

	if kind == "welcome" and mode == Mode.CLIENT:
		welcome_received.emit(
			str(payload.get("pack_id", "cangming")),
			int(payload.get("seed", 0)),
			int(payload.get("minutes", 440)),
			int(payload.get("weather_kind", -1)),
			str(payload.get("host_name", "房主"))
		)
		if _bound_world != null:
			sync_local_state(_bound_world, 1, "", true)
		return

	if kind == "player_snapshot":
		var snap: Dictionary = payload.get("data", {})
		var sender_pid := int(snap.get("peer_id", from_id))
		if sender_pid <= 0:
			sender_pid = from_id
		if _bound_world != null:
			receive_remote_snapshot(sender_pid, snap, _bound_world)
		# Host relays snapshot to all other clients
		if mode == Mode.HOST and mp != null:
			for other_id: int in mp.get_peers():
				if other_id != from_id:
					_send_packet(payload, other_id)
		return

	if kind == "world_mutation":
		var mut: Dictionary = payload.get("mutation", {})
		if _bound_world != null and _bound_world.has_method("apply_world_mutation"):
			if _bound_world.apply_world_mutation(mut):
				world_mutation_applied.emit(mut)
		if mode == Mode.HOST and mp != null:
			for other_id: int in mp.get_peers():
				if other_id != from_id:
					_send_packet(payload, other_id)
		return

	if kind == "chat":
		var spid := int(payload.get("peer_id", from_id))
		var sname := str(payload.get("name", "联机同道"))
		var txt := str(payload.get("text", ""))
		_record_chat(spid, sname, txt)
		if mode == Mode.HOST and mp != null:
			for other_id: int in mp.get_peers():
				if other_id != from_id:
					_send_packet(payload, other_id)
