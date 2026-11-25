#pragma once

#include "item_catalog.hpp"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <vector>

namespace cangling {

// Port of CCB Character physiological needs (kcal hunger, hydration thirst, fatigue)
// and layered clothing/wear system (warmth, encumbrance, storage capacity, visual overlays).
struct CharacterState {
    double kcal = 2400.0;       // 0..3600 (healthy range 1800..2800)
    double hydration = 100.0;   // 0..120  (100 = hydrated, <40 = thirsty)
    double fatigue = 8.0;       // 0..100  (0 = rested, >60 = tired)
    int morale = 10;            // -50..50
    std::vector<int> worn;      // item IDs currently worn in layer order

    void reset_defaults();
    void advance_minutes(int delta_minutes, bool resting = false, bool sleeping = false);

    int carry_weight_g(const ItemCounts &carried, int bottle_water_ml) const;
    int carry_volume_ml(const ItemCounts &carried) const;
    int max_carry_volume_ml() const;
    int total_warmth() const;
    int total_encumbrance() const;
    int slot_layer_count(WearSlot slot) const;

    godot::String hunger_status() const;
    godot::String thirst_status() const;
    godot::String fatigue_status() const;

    godot::String wear_from_bag(int item_id, ItemCounts &carried);
    godot::String take_off_to_bag(int worn_index, ItemCounts &carried);
    godot::String consume_item(int item_id, ItemCounts &carried, int &minutes_out);
    godot::String drink_water(int ml, int &minutes_out);

    godot::Array worn_list() const;
    godot::PackedStringArray worn_overlays() const;
    godot::Dictionary to_dict(const ItemCounts &carried, int bottle_water_ml) const;

    godot::Dictionary save_dict() const;
    bool load_dict(const godot::Dictionary &d);
};

} // namespace cangling
