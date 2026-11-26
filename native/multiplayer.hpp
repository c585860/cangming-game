#pragma once

#include <cstdint>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace cangling {

// Transport-agnostic Multiplayer Peer State for future ENet / WebSocket / Steam Co-op.
// Stored inside CanglingWorld so rendering, spatial queries, and deterministic command
// replication can drop straight in without rewriting single-player game logic.
struct RemotePlayerState {
    int64_t peer_id = 0;
    godot::String name;
    godot::Vector2i pos{0, 0};
    int floor = 0;
    int facing_x = 1;
    int move_mode = 0;
    godot::String posture;
    int wielded = -1;
    godot::PackedStringArray worn_overlays;
    godot::String rank_label;
    int64_t last_sync_ms = 0;

    godot::Dictionary to_dict() const {
        godot::Dictionary d;
        d["peer_id"] = peer_id;
        d["name"] = name;
        d["pos"] = pos;
        d["floor"] = floor;
        d["facing_x"] = facing_x;
        d["move_mode"] = move_mode;
        d["posture"] = posture;
        d["wielded"] = wielded;
        d["worn_overlays"] = worn_overlays;
        d["rank_label"] = rank_label;
        d["last_sync_ms"] = last_sync_ms;
        return d;
    }
};

} // namespace cangling
