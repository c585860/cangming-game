#pragma once

#include "ccb_vanilla.hpp"
#include "character_state.hpp"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <cstdint>
#include <functional>
#include <string>
#include <unordered_map>
#include <vector>

namespace cangling {

struct MonsterSpawn {
    std::string species_id;
    godot::Vector2i pos{0, 0};
    int floor = 0;
};

struct MonsterInstance {
    int id = 0;
    std::string species_id;
    godot::Vector2i pos{0, 0};
    int floor = 0;
    int hp = 70;
    int max_hp = 70;
    int move_accum = 0;
    bool alerted = false;
    bool alive = true;
    godot::Vector2i last_target{0, 0};
};

struct MonsterTickResult {
    godot::Array messages;
    bool player_damaged = false;
    bool safe_mode_alert = false;
    int active_count = 0;
    int alerted_count = 0;
};

struct MonsterAttackResult {
    bool hit = false;
    bool crit = false;
    bool killed = false;
    int damage = 0;
    std::string killed_species_id;
    std::vector<CcbItemStack> drops;
    godot::Vector2i drop_pos{0, 0};
    godot::String message;
};

class MonsterManager {
    std::vector<MonsterInstance> list;
    std::unordered_map<int64_t, int> spatial; // key(pos, floor) -> index in list
    int next_id = 1;

    static int64_t tile_key(godot::Vector2i p, int z);
    void rebuild_spatial();

public:
    void clear();
    void populate_from_spawns(const std::vector<MonsterSpawn> &spawns);
    void add_spawns(const std::vector<MonsterSpawn> &spawns);
    bool spawn_one(const std::string &species_id, godot::Vector2i pos, int z, bool alerted = true);
    int alive_count() const;
    int total_count() const { return static_cast<int>(list.size()); }

    const MonsterInstance *at(godot::Vector2i p, int z) const;
    MonsterInstance *at_mut(godot::Vector2i p, int z);
    bool has_alive_at(godot::Vector2i p, int z) const { return at(p, z) != nullptr; }

    godot::Array monsters_in_rect(godot::Rect2i area, int z) const;
    godot::Dictionary monster_dict_at(godot::Vector2i p, int z) const;

    MonsterTickResult tick(
        int steps,
        godot::Vector2i player_pos,
        int player_floor,
        bool is_night,
        CharacterState &char_state,
        CcbSurvivalState &ccb,
        const std::function<bool(godot::Vector2i, int)> &can_step_tile,
        const std::function<bool(godot::Vector2i, int)> &blocks_sight);

    MonsterTickResult tick_moves(
        int moves,
        godot::Vector2i player_pos,
        int player_floor,
        bool is_night,
        CharacterState &char_state,
        CcbSurvivalState &ccb,
        const std::function<bool(godot::Vector2i, int)> &can_step_tile,
        const std::function<bool(godot::Vector2i, int)> &blocks_sight);

    MonsterAttackResult player_attack(
        godot::Vector2i target,
        int z,
        CharacterState &char_state,
        CcbSurvivalState &ccb,
        int &kills_counter);

    bool apply_remote_hit(godot::Vector2i target, int z, int dmg);

    godot::Array save_array() const;
    void load_array(const godot::Array &arr);
};

} // namespace cangling
