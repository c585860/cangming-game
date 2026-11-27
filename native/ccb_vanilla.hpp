#pragma once

#include "character_state.hpp"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <array>
#include <cstdint>
#include <functional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace cangling {

struct CcbItemDef {
    std::string id;
    std::string name_zh;
    std::string name_en;
    std::string subtype;
    std::string category;
    int weight_g = 0;
    int vol_ml = 0;
    int bash = 0;
    int cut = 0;
    int stab = 0;
    int to_hit = 0;
    int kcal = 0;
    int quench = 0;
    int fun = 0;
    int healthy = 0;
    std::string comestible_type;
    int covers_mask = 0; // bit0=head,1=torso,2=l_arm,3=r_arm,4=l_leg,5=r_leg
    int encumbrance = 0;
    int warmth = 0;
    int env_resist = 0;
    int storage_ml = 0;
    int armor_bash = 0;
    int armor_cut = 0;
    int armor_stab = 0;
    int coverage = 0;
    std::vector<std::string> flags;
    std::vector<std::pair<std::string, int>> vitamins;
    std::vector<std::string> use_tags;
    std::string tile;
    std::string desc;

    bool has_flag(std::string_view f) const;
    bool has_use_tag(std::string_view u) const;
};

struct CcbMutationCategoryDef {
    std::string id;
    std::string name;
    std::string threshold_mut;
    std::string vitamin;
    std::string mutagen_message;
    int threshold_min = 2200;
};

struct CcbMutationDef {
    std::string id;
    std::string name;
    std::string desc;
    int points = 0;
    bool starting_trait = false;
    bool profession = false;
    bool valid = true;
    bool purifiable = true;
    bool threshold = false;
    std::vector<std::string> threshreq;
    std::vector<std::string> category;
    std::vector<std::string> prereqs;
    std::vector<std::string> prereqs2;
    std::vector<std::string> cancels;
    std::vector<std::string> changes_to;
    std::vector<std::string> flags;
    int vitamin_cost = 100;

    bool in_category(std::string_view cat) const;
    bool has_flag(std::string_view f) const;
};

struct CcbScenarioDef {
    std::string id;
    std::string name;
    std::string desc;
    int points = 0;
    std::string start_name;
    std::string start_omt;
    std::vector<std::string> allowed_locs;
    std::vector<std::string> professions;
    std::vector<std::string> forced_traits;
    std::vector<std::string> traits;
    std::vector<std::string> flags;
};

struct CcbProfessionDef {
    std::string id;
    std::string name;
    std::string desc;
    int points = 0;
    bool is_hobby = false;
    std::vector<std::string> worn;
    std::string wielded;
    std::vector<std::string> bag;
    std::vector<std::pair<std::string, int>> skills;
    std::vector<std::string> traits;
    std::vector<std::string> flags;
};

struct CcbSkillDef {
    std::string id;
    std::string name;
    std::string desc;
    std::string category;
    int sort_rank = 10000;
};

struct CcbRecipeDef {
    std::string id;
    std::string result;
    int charges = 1;
    std::string category;
    std::string subcategory;
    std::string skill_used;
    int difficulty = 0;
    int time_min = 5;
    bool autolearn = false;
    // Each component slot is a list of (item_id, count) alternatives
    std::vector<std::vector<std::pair<std::string, int>>> components;
};

struct CcbCorpse {
    int id = 0;
    std::string mtype_id;
    godot::Vector2i pos{0, 0};
    int floor = 0;
    int death_minute = 0;
    bool pulped = false;
    bool butchered = false;
    bool revives = false;
};

struct CcbMonsterDef {
    std::string id;
    std::string name;
    std::string desc;
    std::string looks_like;
    int hp = 70;
    int speed = 75;
    int melee_skill = 3;
    int melee_dice = 2;
    int melee_dice_sides = 4;
    int dodge = 0;
    int armor_bash = 0;
    int armor_cut = 0;
    int armor_stab = 0;
    int vision_day = 30;
    int vision_night = 5;
    int aggression = 100;
    int weight_g = 81500;
    bool filthy_drops = true;
    std::vector<std::string> species;
    std::vector<std::string> flags;
    std::vector<std::string> special_attacks;
    std::string harvest;
    std::string death_drops;

    bool has_flag(std::string_view f) const;
    bool has_special(std::string_view s) const;
};

struct CcbLootEntry {
    std::string item_id;
    std::string group_id;
    int prob = 100;
    int count_min = 1;
    int count_max = 1;
    int dmg_min = 0;
    int dmg_max = 0;
    bool has_dmg = false;
    bool sub_is_collection = false;
    std::vector<CcbLootEntry> sub_entries;
};

struct CcbLootGroup {
    bool is_collection = false;
    std::vector<CcbLootEntry> entries;
};

struct CcbHarvestEntry {
    std::string drop_id;
    std::string type;
    float mass_ratio = 0.0f;
    int base_min = 0;
    int base_max = 0;
};

struct CcbItemStack {
    std::string id;
    int count = 1;
    int irradiation = 0;
    bool filthy = false;
    int damage = 0; // 0=intact, 1=scratched, 2=damaged, 3=torn, 4=shredded
};

class CcbVanillaDB {
    bool loaded = false;
    std::vector<CcbItemDef> items_;
    std::unordered_map<std::string, int> item_idx_;
    std::vector<CcbMutationCategoryDef> mut_cats_;
    std::unordered_map<std::string, int> mut_cat_idx_;
    std::vector<CcbMutationDef> muts_;
    std::unordered_map<std::string, int> mut_idx_;
    std::vector<CcbMonsterDef> mons_;
    std::unordered_map<std::string, int> mon_idx_;
    std::vector<CcbScenarioDef> scenarios_;
    std::unordered_map<std::string, int> scen_idx_;
    std::vector<CcbProfessionDef> professions_;
    std::unordered_map<std::string, int> prof_idx_;
    std::vector<CcbSkillDef> skills_;
    std::unordered_map<std::string, int> skill_idx_;
    std::vector<CcbRecipeDef> recipes_;
    std::unordered_map<std::string, int> recipe_idx_;
    std::unordered_map<std::string, CcbLootGroup> loot_groups_;
    std::unordered_map<std::string, std::vector<CcbHarvestEntry>> harvests_;

    void load_items_tsv();
    void load_mutations_json();
    void load_monsters_json();
    void load_monsterdrops_json();
    void load_harvest_json();
    void load_scenarios_json();
    void load_professions_json();
    void load_skills_json();
    void load_recipes_json();

    void eval_loot_group(
        const CcbLootGroup &grp,
        const std::function<int(int, int)> &rng_range,
        std::vector<CcbItemStack> &out,
        int depth,
        int inherited_dmg_min,
        int inherited_dmg_max,
        bool inherited_has_dmg) const;

    void eval_loot_entry(
        const CcbLootEntry &ent,
        const std::function<int(int, int)> &rng_range,
        std::vector<CcbItemStack> &out,
        int depth,
        int inherited_dmg_min,
        int inherited_dmg_max,
        bool inherited_has_dmg) const;

public:
    static const CcbVanillaDB &instance();
    void ensure_loaded();

    int item_count() const { return static_cast<int>(items_.size()); }
    int mutation_count() const { return static_cast<int>(muts_.size()); }
    int mutation_category_count() const { return static_cast<int>(mut_cats_.size()); }
    int monster_count() const { return static_cast<int>(mons_.size()); }
    int scenario_count() const { return static_cast<int>(scenarios_.size()); }
    int profession_count() const { return static_cast<int>(professions_.size()); }
    int skill_count() const { return static_cast<int>(skills_.size()); }
    int recipe_count() const { return static_cast<int>(recipes_.size()); }
    int loot_group_count() const { return static_cast<int>(loot_groups_.size()); }
    int harvest_count() const { return static_cast<int>(harvests_.size()); }

    std::vector<CcbItemStack> roll_death_drops(const std::string &mtype_id, const std::function<int(int, int)> &rng_range) const;
    std::vector<CcbItemStack> roll_harvest(const std::string &mtype_id, const std::function<int(int, int)> &rng_range) const;

    const CcbItemDef *find_item(std::string_view id) const;
    const CcbMutationDef *find_mutation(std::string_view id) const;
    const CcbMutationCategoryDef *find_mutation_category(std::string_view id) const;
    const CcbMutationCategoryDef *find_category_by_vitamin(std::string_view vit) const;
    const CcbMonsterDef *find_monster(std::string_view id) const;
    const CcbScenarioDef *find_scenario(std::string_view id) const;
    const CcbProfessionDef *find_profession(std::string_view id) const;
    const CcbSkillDef *find_skill(std::string_view id) const;
    const CcbRecipeDef *find_recipe(std::string_view id) const;
    const std::vector<CcbMutationDef> &all_mutations() const { return muts_; }
    const std::vector<CcbMutationCategoryDef> &all_mutation_categories() const { return mut_cats_; }
    const std::vector<CcbItemDef> &all_items() const { return items_; }
    const std::vector<CcbRecipeDef> &all_recipes() const { return recipes_; }
    const std::vector<CcbSkillDef> &all_skills_defs() const { return skills_; }

    godot::Array list_scenarios_array() const;
    godot::Array list_professions_array(bool hobbies_only) const;
    godot::Array list_starting_traits_array() const;
    godot::Array list_skills_array() const;
    godot::Array search_items(const godot::String &query, const godot::String &subtype_filter, int limit) const;
    godot::Dictionary item_to_dict(const CcbItemDef &def) const;
    godot::Dictionary stack_to_dict(const CcbItemStack &st) const;
    godot::Dictionary db_stats_dict() const;
};

struct CcbDerivedMods {
    int str_mod = 0;
    int dex_mod = 0;
    int int_mod = 0;
    int per_mod = 0;
    int speed_mod = 0;
    int hp_bonus = 0;
    int natural_armor_bash = 0;
    int natural_armor_cut = 0;
    int natural_armor_stab = 0;
    int unarmed_cut = 0;
    int unarmed_stab = 0;
    int night_vision_bonus = 0;
    bool rad_immune = false;
    bool rad_resist = false;
    bool radiogenic = false;
    bool radiophile = false;
    int radioactive_level = 0;
    bool robust_genetics = false;
};

struct CcbCombatSkills {
    int melee = 0;
    int bashing = 0;
    int cutting = 0;
    int stabbing = 0;
    int unarmed = 0;
    int dodge = 0;
    int firstaid = 0;
    int survival = 0;
    std::array<int, 8> xp{}; // 0..100 per skill

    void reset();
    void train(int skill_idx, int amount, int cap = 10);
    int level(int skill_idx) const;
    godot::Dictionary to_dict() const;
    void load_dict(const godot::Dictionary &d);
};

struct CcbSurvivalState {
    // Vanilla CCB String-ID Inventory, Worn & Wielded
    std::vector<CcbItemStack> bag;
    std::vector<std::string> worn;
    std::string wielded;
    std::unordered_map<int64_t, std::vector<CcbItemStack>> world_items;
    std::unordered_map<int64_t, bool> loot_materialized;

    // Vanilla CCB Combat Skills (0..10)
    CcbCombatSkills skills;

    // Vanilla CCB Radiation State (suffer.cpp + character_health.cpp)
    int rad = 0;            // 0..2000 mSv
    int slow_rad = 0;       // 0..999 accumulator
    int iodine_min = 0;     // potassium iodide timer
    int pblue_min = 0;      // Prussian blue timer
    int rad_badge_rad = 0;  // personal dosimetry badge irradiation
    float last_tile_rad = 0.0f;

    // Vanilla CCB Wounds & Effects (player_hardcoded_effects.cpp)
    std::array<int, 6> bleed{};        // bleed intensity per body part
    std::array<int, 6> bite_min{};     // untreated deep bite minutes
    std::array<int, 6> infected_min{}; // active infection minutes
    int antibiotic_min = 0;
    int grab_intensity = 0;
    int rad_tick_accum = 0;
    int mut_tick_accum = 0;
    std::uint32_t rng_state = 1337u;

    // Vanilla CCB Mutation & Mutagen Vitamins (mutation.cpp + changing_eocs.json)
    std::unordered_map<std::string, int> vitamins; // "mutagen", "mutagen_beast", etc.
    std::vector<std::string> mutations;
    bool changing = false; // CHANGING state when mutagenic catalyst >= 450

    // Vanilla CCB Corpses & Blood Fields (corpse revival / pulp / butcher)
    std::vector<CcbCorpse> corpses;
    int next_corpse_id = 1;
    std::unordered_map<int64_t, int> blood_tiles; // infinite_tile_key -> intensity 1..3

    // Character Creator Metadata & Full Vanilla Skill Map
    std::string scenario_id = "evacuee";
    std::string profession_id = "unemployed";
    std::string gender = "male";
    int age = 25;
    std::unordered_map<std::string, int> all_skills;

    // Overmap Fog-of-War & User Notes (exact vanilla overmap_ui.cpp!)
    std::unordered_set<int64_t> seen_omts;
    std::unordered_map<int64_t, std::string> overmap_notes;

    void mark_omt_seen(godot::Vector2i center_omt, int radius);
    bool is_omt_seen(godot::Vector2i omt) const;
    void set_overmap_note(godot::Vector2i omt, const std::string &note);
    std::string get_overmap_note(godot::Vector2i omt) const;

    void reset(std::uint32_t seed, const std::string &scenario_id);
    void apply_character_config(const godot::Dictionary &cfg, CharacterState &cs);
    int weapon_attack_moves() const;
    godot::PackedStringArray worn_overlays() const;

    // Corpse & Blood operations
    void add_blood(godot::Vector2i p, int z, int intensity = 1);
    void spawn_corpse(const std::string &mtype_id, godot::Vector2i p, int z, int current_minute);
    bool has_corpse_at(godot::Vector2i p, int z) const;
    godot::Array corpses_at(godot::Vector2i p, int z) const;
    godot::String pulp_corpse_at(godot::Vector2i p, int z);
    godot::String butcher_corpse_at(godot::Vector2i p, int z, CharacterState &cs);
    std::vector<std::pair<std::string, godot::Vector2i>> collect_reviving_corpses(int current_minute, int z);

    // Vanilla CCB Crafting (2,823 recipes)
    int skill_level_by_id(const std::string &sid) const;
    godot::Array recipe_list(const godot::String &category_filter, const godot::String &query, int limit) const;
    godot::String craft_recipe(const std::string &recipe_id, CharacterState &cs, int &out_time_min);
    int rng_range(int lo, int hi);
    bool one_in(int n);
    bool x_in_y(int x, int y);

    // Inventory helpers
    void add_bag_item(const std::string &id, int count = 1, bool filthy = false, int damage = 0);
    bool consume_bag_item(const std::string &id, int count = 1);
    int bag_count(const std::string &id) const;
    int total_bag_weight_g() const;
    int total_bag_vol_ml() const;
    bool has_worn_flag(std::string_view flag) const;
    int worn_armor_for_part(int part_idx, int dmg_type, int &coverage_out) const; // 0=bash,1=cut,2=stab
    int total_worn_encumbrance() const;
    int torso_encumbrance() const;
    int total_worn_storage_ml() const;
    int total_worn_warmth() const;
    godot::Array body_part_details(const CharacterState &cs) const;
    bool reorder_worn(int idx, int delta);
    godot::String wash_item_id(const std::string &id);

    // Mutation helpers (exact mutation.cpp rules)
    bool has_mutation(std::string_view mut_id) const;
    bool has_mutation_flag(std::string_view flag) const;
    int get_vitamin(const std::string &vit_id) const;
    void mod_vitamin(const std::string &vit_id, int delta, int max_val = 2500);
    int mutation_height(const std::string &mut_id, int depth = 0) const;
    int get_instability_per_category(const std::string &cat_id) const;
    bool roll_bad_mutation(const std::string &cat_id);
    bool has_prereqs(const CcbMutationDef &m) const;
    bool has_threshold() const;
    bool mutate_towards(const std::string &mut_id, const std::string &cat_id, bool use_vitamins, std::vector<godot::String> &msgs, int depth = 0);
    bool mutate_category(const std::string &cat_id, bool use_vitamins, std::vector<godot::String> &msgs);
    bool mutate_random(bool use_vitamins, std::vector<godot::String> &msgs);
    bool purify_one(std::vector<godot::String> &msgs);

    // Radiation helpers (exact suffer.cpp rules)
    static godot::String rad_badge_color_cn(int badge_rad);
    bool irradiate(float rads, bool bypass, std::vector<godot::String> &msgs);
    void tick_minute_effects(int delta_min, float tile_rad, CharacterState &cs, std::vector<godot::String> &msgs);

    // Derived vanilla stat/speed/armor/rad modifiers from mutations + radiation
    CcbDerivedMods compute_mods() const;

    // Vanilla item actions
    godot::String wield_item_id(const std::string &id);
    godot::String unwield_item();
    godot::String wear_item_id(const std::string &id);
    godot::String takeoff_item_id(const std::string &id);
    godot::String use_or_consume_item(const std::string &id, CharacterState &cs, std::vector<godot::String> &extra_msgs);

    // Serialization & UI views
    godot::Array bag_to_array() const;
    godot::Array worn_to_array() const;
    godot::Dictionary status_dict(const CharacterState &cs) const;
    godot::Dictionary save_dict() const;
    void load_dict(const godot::Dictionary &d);
};

} // namespace cangling
