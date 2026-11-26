extends RefCounted

# Transport-Agnostic Multiplayer Session Interface for Cangling City (沧灵城)
# Designed so future LAN / Dedicated Server / Steam co-op drops directly onto
# CanglingWorld's snapshot & deterministic action hooks without refactoring gameplay!
#
# Architecture:
#  - Offline single-player (default): 0 network overhead; actions run locally.
#  - Host / Client hooks: Ready for Godot ENetMultiplayerPeer / WebSocketMultiplayerPeer
#    using export_player_snapshot(), apply_remote_snapshot(), and submit_player_action().

signal mode_changed(new_mode: int)
signal peer_joined(peer_id: int, peer_name: String)
signal peer_left(peer_id: int)
signal remote_snapshot_applied(peer_id: int)
signal chat_received(peer_id: int, sender: String, text: String)

enum Mode { OFFLINE = 0, HOST = 1, CLIENT = 2 }

const PROTOCOL_VERSION := 1
const DEFAULT_PORT := 27015
const DEFAULT_MAX_PEERS := 8
const SYNC_INTERVAL_SEC := 0.10

var mode: int = Mode.OFFLINE
var host_address := "127.0.0.1"
var port := DEFAULT_PORT
var max_peers := DEFAULT_MAX_PEERS
var peer: MultiplayerPeer = null
var _sync_accum := 0.0
var _last_snapshot_sig := ""


func mode_label() -> String:
	match mode:
		Mode.HOST:
			return "联机房主 (Host)"
		Mode.CLIENT:
			return "联机客端 (Client)"
		_:
			return "单人离线 (Offline)"


func is_online() -> bool:
	return mode != Mode.OFFLINE


func host_session(listen_port := DEFAULT_PORT, peer_limit := DEFAULT_MAX_PEERS, tree_mp: MultiplayerAPI = null) -> Dictionary:
	leave_session(tree_mp)
	port = clampi(listen_port, 1024, 65535)
	max_peers = clampi(peer_limit, 2, 32)
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(port, max_peers)
	if err != OK:
		return {"ok": false, "message": "无法监听端口 %d (错误码 %d)。" % [port, err]}
	peer = enet
	if tree_mp != null:
		tree_mp.multiplayer_peer = peer
	mode = Mode.HOST
	mode_changed.emit(mode)
	return {"ok": true, "message": "已开启联机房主接口，监听端口 %d（最多 %d 人）。" % [port, max_peers]}


func join_session(address := "127.0.0.1", target_port := DEFAULT_PORT, tree_mp: MultiplayerAPI = null) -> Dictionary:
	leave_session(tree_mp)
	host_address = address.strip_edges() if not address.strip_edges().is_empty() else "127.0.0.1"
	port = clampi(target_port, 1024, 65535)
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(host_address, port)
	if err != OK:
		return {"ok": false, "message": "无法连接 %s:%d (错误码 %d)。" % [host_address, port, err]}
	peer = enet
	if tree_mp != null:
		tree_mp.multiplayer_peer = peer
	mode = Mode.CLIENT
	mode_changed.emit(mode)
	return {"ok": true, "message": "正在通过联机接口连接 %s:%d ..." % [host_address, port]}


func leave_session(tree_mp: MultiplayerAPI = null, world: Object = null) -> void:
	if peer != null:
		peer.close()
		peer = null
	if tree_mp != null and tree_mp.multiplayer_peer != null:
		tree_mp.multiplayer_peer = null
	if world != null and world.has_method("clear_remote_players"):
		world.clear_remote_players()
	if mode != Mode.OFFLINE:
		mode = Mode.OFFLINE
		mode_changed.emit(mode)


func tick(delta: float, world: Object, facing_x := 1, posture := "") -> void:
	if mode == Mode.OFFLINE or world == null:
		return
	_sync_accum += delta
	if _sync_accum < SYNC_INTERVAL_SEC:
		return
	_sync_accum = 0.0
	sync_local_state(world, facing_x, posture)


func sync_local_state(world: Object, facing_x := 1, posture := "") -> Dictionary:
	if world == null or not world.has_method("export_player_snapshot"):
		return {}
	var snap: Dictionary = world.export_player_snapshot()
	snap["facing_x"] = facing_x
	snap["posture"] = posture
	snap["sync_ms"] = Time.get_ticks_msec()
	var sig := "%s|%d|%d|%s|%d" % [
		str(snap.get("pos", Vector2i.ZERO)),
		int(snap.get("floor", 0)),
		facing_x,
		posture,
		int(snap.get("move_mode", 0)),
	]
	if sig != _last_snapshot_sig:
		_last_snapshot_sig = sig
		_broadcast_packet({"kind": "player_snapshot", "protocol": PROTOCOL_VERSION, "data": snap})
	return snap


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
			peer_joined.emit(peer_id, str(snapshot.get("name", "江湖同道")))
		remote_snapshot_applied.emit(peer_id)
	return ok


func dispatch_action(world: Object, action_dict: Dictionary) -> Dictionary:
	# Single choke point for deterministic actions: locally executed now,
	# ready to forward to server authority via RPC when multiplayer is active.
	if world == null or not world.has_method("submit_player_action"):
		return {"ok": false, "message": ""}
	var result: Dictionary = world.submit_player_action(action_dict)
	if mode != Mode.OFFLINE and bool(result.get("ok", false)):
		_broadcast_packet({
			"kind": "player_action",
			"protocol": PROTOCOL_VERSION,
			"peer_id": int(world.get_local_peer_id()),
			"action": action_dict,
		})
	return result


func send_chat(world: Object, text: String) -> void:
	var clean := text.strip_edges()
	if clean.is_empty() or world == null:
		return
	var pid: int = int(world.get_local_peer_id())
	var pname: String = str(world.get_player_name())
	_broadcast_packet({"kind": "chat", "peer_id": pid, "name": pname, "text": clean})
	chat_received.emit(pid, pname, clean)


func spawn_mock_peer(peer_id: int, peer_name: String, tile_pos: Vector2i, world: Object) -> bool:
	# Local developer / verification helper to test remote player sync & rendering offline.
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
	return {
		"protocol_version": PROTOCOL_VERSION,
		"mode": mode,
		"mode_label": mode_label(),
		"host_address": host_address,
		"port": port,
		"max_peers": max_peers,
		"local_peer_id": int(world.get_local_peer_id()) if world != null else 1,
		"player_name": str(world.get_player_name()) if world != null else "江湖少侠",
		"remote_count": int(world.remote_player_count()) if world != null else 0,
		"transport_ready": true,
	}


func _broadcast_packet(_payload: Dictionary) -> void:
	# Hook point for future SceneMultiplayer.send_bytes() / RPC channel dispatch.
	pass
