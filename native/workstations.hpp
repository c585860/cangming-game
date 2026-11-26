#pragma once

#include "skills.hpp"
#include <array>
#include <cstddef>
#include <vector>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace cangling {

// Physical multiplayer-ready workstation facilities placed throughout Cangling City's
// 7 work districts (28 total independent stations, NO occupation lock so co-op players
// can freely work side-by-side or share facilities seamlessly with a 2.5s progress bar).
struct WorkstationDef {
    const char *id;
    const char *name;
    const char *district;
    godot::Vector2i pos;
    const char *req_skill;      // Required base skill ID, or "any_martial"
    const char *alt_skill;      // Optional alternative skill ID ("" if none)
    int req_level;
    const char *mentor_hint;    // Friendly guidance when player hasn't learned prerequisite yet
    const char *action_verb;
    const char *reward_skill;   // Skill receiving proficiency on completion (or "best_martial")
    int coin_pay;
    int pot_gain;
    int combat_exp_gain;
    int skill_exp_gain;
    double kcal_cost;
    double hydration_cost;
    int stamina_cost;
    double duration_sec;
    bool martial_bonus_station; // Standing beside this grants +35% practice efficiency
};

struct MasterTeachSpec {
    const char *npc_id;
    const char *skill_id;
    int max_teach_level;
};

inline constexpr std::size_t kWorkstationCount = 28;

const std::array<WorkstationDef, kWorkstationCount> &workstation_catalog();
const WorkstationDef *workstation_at_tile(godot::Vector2i p);
bool near_martial_training_station(godot::Vector2i player_pos);
bool skill_meets_station_req(const SkillSet &skills, const WorkstationDef &ws);
godot::Dictionary workstation_to_dict(const WorkstationDef &ws, const SkillSet &skills);

const std::vector<MasterTeachSpec> &master_teach_catalog();

} // namespace cangling
