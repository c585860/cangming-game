#pragma once

#include "character_state.hpp"
#include "item_catalog.hpp"
#include "skills.hpp"
#include <array>
#include <cstddef>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace cangling {

inline constexpr std::size_t kBountyCount = 5;
inline const godot::Vector2i kNoticeBoardTile{119, 120}; // Right beside Ancient Scholar Tree on Central Square

struct BountyDef {
    const char *id;
    const char *title;
    const char *giver;
    const char *desc;
    godot::Vector2i waypoint_pos; // Optional location to visit first
    godot::Vector2i turnin_pos;   // NPC or landmark to complete at
    const char *turnin_npc_id;
    int coin_reward;
    int pot_reward;
    int exp_reward;
    int rep_reward;
};

const std::array<BountyDef, kBountyCount> &bounty_catalog();
int find_bounty_index(const char *id);

struct BountyTracker {
    int active_index = -1;       // -1 = none
    bool waypoint_done = false;  // Used for escort / rubbing / spar tracking
    int start_spar_total = 0;    // Snapshot when accepting martial_trial
    int completed_count = 0;

    void reset();
    void update_proximity(godot::Vector2i player_pos, int current_spar_total);
    bool is_ready_to_turn_in(const ItemCounts &carried, int current_spar_total) const;
    godot::String accept(int idx, int current_spar_total);
    godot::String abandon();
    godot::String try_turn_in(const char *npc_id, ItemCounts &carried, int &coins,
                              CharacterState &ch, SkillSet &skills);
    godot::Array list_to_array(const ItemCounts &carried, int current_spar_total) const;
    godot::Dictionary active_dict(const ItemCounts &carried, int current_spar_total) const;
    godot::Dictionary save_dict() const;
    void load_dict(const godot::Dictionary &d);
};

} // namespace cangling
