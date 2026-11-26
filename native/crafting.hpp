#pragma once

#include "character_state.hpp"
#include "item_catalog.hpp"
#include "skills.hpp"
#include <array>
#include <cstddef>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace cangling {

inline constexpr std::size_t kRecipeCount = 18;

struct RecipeDef {
    const char *id;
    const char *name;
    const char *category;     // "烹饪", "制药", "锻造", "裁缝抄录"
    const char *req_skill;    // "" or base skill id
    int req_level;
    bool need_hearth;         // Nearby 'h' within radius 2
    bool need_anvil;          // Near 王记铁匠铺锻造区
    int need_water_ml;        // From bottle or nearby water vessel
    const char *tool_key;     // "" or required tool in carried/wielded (waived at matching workshop)
    const char *ing1_key;
    int ing1_cnt;
    const char *ing2_key;
    int ing2_cnt;
    const char *out_key;
    int out_cnt;
    double duration_sec;
    int skill_exp;
    int pot_gain;
    const char *desc;
};

const std::array<RecipeDef, kRecipeCount> &recipe_catalog();
int find_recipe_index(const char *id);

struct CraftEnv {
    bool near_hearth = false;
    bool near_anvil = false;
    bool near_water = false;
    bool near_workshop = false;
};

godot::Dictionary check_can_craft(const RecipeDef &r, const ItemCounts &carried, int bottle_water_ml,
                                  int wielded_id, const SkillSet &skills, const CraftEnv &env);
godot::Array list_recipes_for_player(const ItemCounts &carried, int bottle_water_ml, int wielded_id,
                                     const SkillSet &skills, const CraftEnv &env, const godot::String &category_filter);
godot::String execute_craft(const RecipeDef &r, ItemCounts &carried, int &bottle_water_ml, int wielded_id,
                            CharacterState &ch, SkillSet &skills, const CraftEnv &env);
godot::String dismantle_item_to_rags(int item_id, ItemCounts &carried, CharacterState &ch);

} // namespace cangling
