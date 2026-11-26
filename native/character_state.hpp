#pragma once

#include "item_catalog.hpp"
#include "skills.hpp"
#include <array>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <string>
#include <vector>

namespace cangling {

// Port of CCB Character physiological needs, 6 body parts HP, stats, stamina,
// movement stances (Walk/Run/Crouch/Prone), wielded item, portable lamp, haul mode,
// layered clothing/armor, ambient temperature/wetness, plus Classic Wuxia MUD neili/dazuo/exert/jiali.
struct CharacterState {
    double kcal = 2400.0;       // 0..3600
    double hydration = 100.0;   // 0..120
    double fatigue = 6.0;       // 0..100
    int stamina = 10000;        // 0..10000 (CCB scale -> 5-pip bar)
    int pain = 0;               // 0..100
    int morale = 10;            // -50..50
    int focus = 100;            // 0..120
    int move_mode = 0;          // 0=行走, 1=奔跑, 2=潜行, 3=匍匐
    bool safe_mode = true;
    bool hauling = false;
    bool lamp_lit = false;
    int light_source = 0;       // 0=off, 1=火折子, 2=红油蜡烛, 3=桐油手灯
    int wielded = -1;           // item_id or -1 for bare hands
    int last_sound = 0;         // last sound amplitude generated

    // CCB 4 core stats
    int stat_str = 8;
    int stat_dex = 8;
    int stat_int = 8;
    int stat_per = 8;

    // CCB 6 body part hit points (dynamic max driven by 基本内功/拳脚/招架!)
    static constexpr int kBaseMaxPartHp = 84;
    static constexpr int kMaxPartHp = 84;
    int max_part_hp = kBaseMaxPartHp;
    int neili = 0;
    int max_neili = 0;
    int neili_bonus_cap = 0;    // Extra max_neili condensed via dazuo meditation!
    int jiali = 0;              // 0 / 5 / 15 / 30 inner-force infusion
    bool exert_warmth = false;  // Active inner-force cold resistance
    std::array<int, 6> part_hp{84, 84, 84, 84, 84, 84}; // head, torso, l_arm, r_arm, l_leg, r_leg

    // CCB Body Temperature & Rain Wetness
    double body_temp_c = 37.0;  // 33.0..39.5 C
    double wetness = 0.0;       // 0..100
    double ambient_temp_c = 18.0;
    double rain_intensity = 0.0;
    bool is_indoors = false;
    bool near_hearth = false;

    // Wuxia Economy, Reputation & Inn Room state
    int bank_coins = 0;
    int reputation = 0;
    int spar_wins = 0;
    int spar_total = 0;
    int inn_room_until_min = 0;

    // Cached martial modifiers synced from SkillSet (effective levels!)
    int cached_force_lv = 0;
    int cached_dodge_lv = 0;
    int cached_unarmed_lv = 0;
    int cached_medicine_lv = 0;
    int cached_cooking_lv = 0;
    int cached_weapon_lv = 0;

    std::vector<int> worn;

    void reset_defaults();
    void sync_with_skills(const SkillSet &skills);
    void update_environment(double ambient_c, double rain, bool indoors, bool hearth);
    void advance_minutes(int delta_minutes, bool resting = false, bool sleeping = false, bool inn_bonus = false);
    void spend_stamina(int amount);
    bool is_well_fed() const { return kcal >= 1800.0 && hydration >= 50.0; }
    bool is_starving_for_training() const { return kcal < 700.0 || hydration < 20.0; }
    bool is_severely_injured() const { return part_hp[0] * 100 < max_part_hp * 45 || part_hp[1] * 100 < max_part_hp * 45; }

    int current_speed() const;
    int bash_power() const;
    int carry_weight_g(const ItemCounts &carried, int bottle_water_ml) const;
    int carry_volume_ml(const ItemCounts &carried) const;
    int max_carry_volume_ml() const;
    int total_warmth() const;
    int total_rain_resist() const;
    int total_encumbrance() const;
    int slot_layer_count(WearSlot slot) const;

    godot::String hunger_status() const;
    godot::String thirst_status() const;
    godot::String fatigue_status() const;
    godot::String pain_status() const;
    godot::String temp_status() const;
    godot::String move_mode_label() const;
    godot::String wielded_label() const;

    godot::String wear_from_bag(int item_id, ItemCounts &carried);
    godot::String take_off_to_bag(int worn_index, ItemCounts &carried);
    godot::String wield_from_bag(int item_id, ItemCounts &carried);
    godot::String unwield_to_bag(ItemCounts &carried);
    godot::String consume_item(int item_id, ItemCounts &carried, int &minutes_out);
    godot::String drink_water(int ml, int &minutes_out);
    godot::String apply_item(int item_id, ItemCounts &carried, int &minutes_out);
    godot::String read_book(int item_id, int &minutes_out);

    // Classic Wuxia MUD Dazuo / Exert / Specialized Study
    godot::Dictionary dazuo_cycle(SkillSet &skills, bool quiet_bonus);
    godot::String exert_action(const std::string &kind);
    godot::String study_book_cycle(int item_id, ItemCounts &carried, SkillSet &skills, bool academy_bonus);

    godot::Array worn_list() const;
    godot::PackedStringArray worn_overlays() const;
    godot::Dictionary to_dict(const ItemCounts &carried, int bottle_water_ml) const;

    godot::Dictionary save_dict() const;
    bool load_dict(const godot::Dictionary &d);
};

} // namespace cangling
