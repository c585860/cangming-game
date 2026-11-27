#pragma once

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <string>
#include <string_view>
#include <vector>

namespace cangling {

enum class CorePackId : int {
    Cangming = 0,
    Cataclysm = 1,
};

struct CorePackInfo {
    CorePackId id = CorePackId::Cangming;
    std::string slug;
    std::string name;
    std::string subtitle;
    std::string version;
    std::string author;
    std::string description;
    std::string theme_accent;
    bool has_monsters = false;
    bool has_wuxia_npcs = false;
    std::vector<std::string> features;
};

struct MonsterSpeciesDef {
    std::string id;
    std::string name;
    std::string tile;
    int max_hp = 70;
    int melee_dmg = 9;
    int speed = 75;
    int vision = 12;
    int hear_radius = 18;
    int exp_reward = 12;
    int pot_reward = 8;
    std::string desc;
};

struct ScenarioDef {
    std::string id;
    std::string name;
    std::string desc;
};

CorePackId parse_core_pack_id(std::string_view slug);
const char *core_pack_slug(CorePackId id);
const CorePackInfo &core_pack_info(CorePackId id);
const std::vector<CorePackInfo> &all_core_packs();
const std::vector<MonsterSpeciesDef> &ccb_monster_species();
const std::vector<ScenarioDef> &ccb_scenarios();
int find_monster_species_index(std::string_view species_id);
godot::Array list_core_packs_array();
godot::Array list_ccb_scenarios_array();

} // namespace cangling
