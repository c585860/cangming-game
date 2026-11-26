#pragma once

#include "character_state.hpp"
#include "skills.hpp"
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <string>

namespace cangling {

struct SparOpponentDef {
    const char *npc_id;
    const char *name;
    const char *style_name;
    const char *weapon_name;
    int max_hp;
    int skill_lv;
    int reward_pot;
    int reward_exp;
    int reward_rep;
    const char *moves[3];
};

const SparOpponentDef *spar_opponent_for_npc(const char *npc_id);

struct SparSession {
    bool active = false;
    std::string npc_id;
    std::string npc_name;
    godot::Vector2i npc_pos{0, 0};
    int opp_hp = 0;
    int opp_max_hp = 100;
    int opp_skill_lv = 8;
    int rounds = 0;
    int player_hits = 0;
    int opp_hits = 0;
    int rng_state = 1;

    void reset();
    godot::Dictionary to_dict() const;
};

godot::Dictionary begin_spar_session(SparSession &sess, const char *npc_id, godot::Vector2i npc_pos,
                                     const CharacterState &ch, const SkillSet &skills);
godot::Dictionary advance_spar_round(SparSession &sess, CharacterState &ch, SkillSet &skills);
godot::String finish_spar_early(SparSession &sess);

} // namespace cangling
