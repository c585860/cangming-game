#pragma once

#include "item_catalog.hpp"
#include <array>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <vector>

namespace cangling {

// Port of CCB Character physiological needs, 6 body parts HP, stats, stamina,
// movement stances (Walk/Run/Crouch/Prone), wielded item, portable lamp, haul mode,
// and layered clothing/armor system.
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

    // CCB 6 body part hit points (0..84)
    static constexpr int kMaxPartHp = 84;
    std::array<int, 6> part_hp{84, 84, 84, 84, 84, 84}; // head, torso, l_arm, r_arm, l_leg, r_leg

    std::vector<int> worn;

    void reset_defaults();
    void advance_minutes(int delta_minutes, bool resting = false, bool sleeping = false);
    void spend_stamina(int amount);

    int current_speed() const;
    int bash_power() const;
    int carry_weight_g(const ItemCounts &carried, int bottle_water_ml) const;
    int carry_volume_ml(const ItemCounts &carried) const;
    int max_carry_volume_ml() const;
    int total_warmth() const;
    int total_encumbrance() const;
    int slot_layer_count(WearSlot slot) const;

    godot::String hunger_status() const;
    godot::String thirst_status() const;
    godot::String fatigue_status() const;
    godot::String pain_status() const;
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

    godot::Array worn_list() const;
    godot::PackedStringArray worn_overlays() const;
    godot::Dictionary to_dict(const ItemCounts &carried, int bottle_water_ml) const;

    godot::Dictionary save_dict() const;
    bool load_dict(const godot::Dictionary &d);
};

} // namespace cangling
