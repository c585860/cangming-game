#include "character_state.hpp"
#include <godot_cpp/variant/variant.hpp>
#include <algorithm>
#include <cmath>

namespace cangling {
using namespace godot;

namespace {
constexpr int kBaseCarryVolumeMl = 2500; // hands + pockets baseline even without bags
constexpr int kMaxLayersPerSlot = 2;
}

void CharacterState::reset_defaults() {
    kcal = 2400.0;
    hydration = 100.0;
    fatigue = 6.0;
    morale = 10;
    worn.clear();
    // Authentic civilian Jiangnan starting outfit:
    // tunic (6), pants (8), boots (12), cloak (10), pouch (15)
    worn = {6, 8, 12, 10, 15};
}

void CharacterState::advance_minutes(int delta_minutes, bool resting, bool sleeping) {
    if (delta_minutes <= 0) return;
    const double dm = static_cast<double>(delta_minutes);
    const double kcal_rate = sleeping ? 0.65 : resting ? 0.95 : 1.45;
    const double water_rate = sleeping ? 0.045 : resting ? 0.065 : 0.095;
    kcal = std::clamp(kcal - dm * kcal_rate, 0.0, 3600.0);
    hydration = std::clamp(hydration - dm * water_rate, 0.0, 120.0);
    if (sleeping) {
        fatigue = std::clamp(fatigue - dm * 0.45, 0.0, 100.0);
    } else if (resting) {
        fatigue = std::clamp(fatigue - dm * 0.16, 0.0, 100.0);
    } else {
        fatigue = std::clamp(fatigue + dm * 0.085, 0.0, 100.0);
    }
}

int CharacterState::carry_weight_g(const ItemCounts &carried, int bottle_water_ml) const {
    const auto &cat = item_catalog();
    int total = 220 + bottle_water_ml; // water bottle + water
    for (int i = 0; i < kItemCount; ++i) {
        total += carried[i] * cat[i].weight_g;
    }
    for (int id : worn) {
        if (id >= 0 && id < kItemCount) total += cat[id].weight_g;
    }
    return total;
}

int CharacterState::carry_volume_ml(const ItemCounts &carried) const {
    const auto &cat = item_catalog();
    int total = 0;
    for (int i = 0; i < kItemCount; ++i) {
        total += carried[i] * cat[i].volume_ml;
    }
    return total;
}

int CharacterState::max_carry_volume_ml() const {
    const auto &cat = item_catalog();
    int total = kBaseCarryVolumeMl;
    for (int id : worn) {
        if (id >= 0 && id < kItemCount) total += cat[id].storage_ml;
    }
    return total;
}

int CharacterState::total_warmth() const {
    const auto &cat = item_catalog();
    int total = 0;
    for (int id : worn) {
        if (id >= 0 && id < kItemCount) total += cat[id].warmth;
    }
    return total;
}

int CharacterState::total_encumbrance() const {
    const auto &cat = item_catalog();
    int total = 0;
    for (int id : worn) {
        if (id >= 0 && id < kItemCount) total += cat[id].encumbrance;
    }
    return total;
}

int CharacterState::slot_layer_count(WearSlot slot) const {
    const auto &cat = item_catalog();
    int count = 0;
    for (int id : worn) {
        if (id >= 0 && id < kItemCount && cat[id].slot == slot) ++count;
    }
    return count;
}

String CharacterState::hunger_status() const {
    if (kcal >= 3000.0) return String::utf8("饱腹");
    if (kcal >= 2200.0) return String::utf8("充实");
    if (kcal >= 1650.0) return String::utf8("正常");
    if (kcal >= 1150.0) return String::utf8("略饿");
    if (kcal >= 700.0) return String::utf8("饥饿");
    if (kcal >= 300.0) return String::utf8("非常饥饿");
    return String::utf8("饥肠辘辘");
}

String CharacterState::thirst_status() const {
    if (hydration >= 105.0) return String::utf8("解渴");
    if (hydration >= 75.0) return String::utf8("正常");
    if (hydration >= 52.0) return String::utf8("口干");
    if (hydration >= 32.0) return String::utf8("口渴");
    if (hydration >= 15.0) return String::utf8("非常口渴");
    return String::utf8("干渴难耐");
}

String CharacterState::fatigue_status() const {
    if (fatigue <= 18.0) return String::utf8("精神饱满");
    if (fatigue <= 40.0) return String::utf8("尚可");
    if (fatigue <= 60.0) return String::utf8("略倦");
    if (fatigue <= 78.0) return String::utf8("疲惫");
    if (fatigue <= 90.0) return String::utf8("困倦");
    return String::utf8("精疲力竭");
}

String CharacterState::wear_from_bag(int item_id, ItemCounts &carried) {
    if (item_id < 0 || item_id >= kItemCount) return {};
    const auto &def = item_catalog()[item_id];
    if (def.category != ItemCategory::Clothing || def.slot == WearSlot::None) {
        return String::utf8("这件物品无法穿戴。");
    }
    if (carried[item_id] <= 0) return String::utf8("行囊中没有这件衣物。");
    if (slot_layer_count(def.slot) >= kMaxLayersPerSlot) {
        return String::utf8("该部位已穿戴多层，请先脱下部分衣物。");
    }
    --carried[item_id];
    worn.push_back(item_id);
    return String::utf8("你穿上了") + String::utf8(def.name) + String::utf8("。");
}

String CharacterState::take_off_to_bag(int worn_index, ItemCounts &carried) {
    if (worn_index < 0 || worn_index >= static_cast<int>(worn.size())) return {};
    const int item_id = worn[static_cast<std::size_t>(worn_index)];
    const auto &def = item_catalog()[item_id];
    worn.erase(worn.begin() + worn_index);
    ++carried[item_id];
    return String::utf8("你脱下了") + String::utf8(def.name) + String::utf8("，收入行囊。");
}

String CharacterState::consume_item(int item_id, ItemCounts &carried, int &minutes_out) {
    if (item_id < 0 || item_id >= kItemCount || carried[item_id] <= 0) return {};
    const auto &def = item_catalog()[item_id];
    if (def.category != ItemCategory::Food && def.category != ItemCategory::Drink) {
        return String::utf8("这件物品无法食用或饮用。");
    }
    --carried[item_id];
    kcal = std::clamp(kcal + static_cast<double>(def.kcal), 0.0, 3600.0);
    hydration = std::clamp(hydration + static_cast<double>(def.quench), 0.0, 120.0);
    morale = std::clamp(morale + def.joy, -50, 50);
    if (def.category == ItemCategory::Drink && def.quench >= 40) {
        fatigue = std::clamp(fatigue - 4.0, 0.0, 100.0);
    }
    const int cost = (def.category == ItemCategory::Food) ? 4 : 2;
    minutes_out += cost;
    advance_minutes(cost, true, false);
    return (def.category == ItemCategory::Food ? String::utf8("你吃下了") : String::utf8("你喝下了")) +
           String::utf8(def.name) + String::utf8("。");
}

String CharacterState::drink_water(int ml, int &minutes_out) {
    if (ml <= 0) return {};
    const double gain = static_cast<double>(ml) * 0.16; // 250 ml -> +40 hydration
    hydration = std::clamp(hydration + gain, 0.0, 120.0);
    minutes_out += 1;
    advance_minutes(1, true, false);
    return String::utf8("你喝下了 ") + String::num_int64(ml) + String::utf8(" 毫升清水，顿时解渴不少。");
}

Array CharacterState::worn_list() const {
    const auto &cat = item_catalog();
    Array out;
    for (std::size_t i = 0; i < worn.size(); ++i) {
        const int id = worn[i];
        if (id < 0 || id >= kItemCount) continue;
        const auto &def = cat[id];
        Dictionary row;
        row["worn_index"] = static_cast<int>(i);
        row["id"] = id;
        row["key"] = def.key;
        row["name"] = String::utf8(def.name);
        row["tile"] = def.tile;
        row["slot"] = String::utf8(wear_slot_label(def.slot));
        row["warmth"] = def.warmth;
        row["encumbrance"] = def.encumbrance;
        row["storage_ml"] = def.storage_ml;
        row["weight_g"] = def.weight_g;
        row["overlay"] = def.overlay;
        out.append(row);
    }
    return out;
}

PackedStringArray CharacterState::worn_overlays() const {
    const auto &cat = item_catalog();
    // Draw order matching paper-doll layering: legs -> feet -> torso -> outer -> back -> head
    constexpr std::array<WearSlot, 6> order{
        WearSlot::Legs, WearSlot::Feet, WearSlot::Torso, WearSlot::Outer, WearSlot::Back, WearSlot::Head
    };
    PackedStringArray result;
    for (WearSlot slot : order) {
        for (int id : worn) {
            if (id < 0 || id >= kItemCount) continue;
            const auto &def = cat[id];
            if (def.slot == slot && def.overlay && def.overlay[0] != '\0') {
                result.append(String(def.overlay));
            }
        }
    }
    return result;
}

Dictionary CharacterState::to_dict(const ItemCounts &carried, int bottle_water_ml) const {
    Dictionary out;
    out["kcal"] = static_cast<int>(std::round(kcal));
    out["kcal_max"] = 3600;
    out["hydration"] = static_cast<int>(std::round(hydration));
    out["fatigue"] = static_cast<int>(std::round(fatigue));
    out["morale"] = morale;
    out["hunger_text"] = hunger_status();
    out["thirst_text"] = thirst_status();
    out["fatigue_text"] = fatigue_status();
    out["warmth"] = total_warmth();
    out["encumbrance"] = total_encumbrance();
    out["carry_volume_ml"] = carry_volume_ml(carried);
    out["max_carry_volume_ml"] = max_carry_volume_ml();
    out["carry_weight_g"] = carry_weight_g(carried, bottle_water_ml);
    out["worn"] = worn_list();
    return out;
}

Dictionary CharacterState::save_dict() const {
    Dictionary d;
    d["kcal"] = kcal;
    d["hydration"] = hydration;
    d["fatigue"] = fatigue;
    d["morale"] = morale;
    Array w;
    for (int id : worn) w.append(id);
    d["worn"] = w;
    return d;
}

bool CharacterState::load_dict(const Dictionary &d) {
    if (d.has("kcal")) kcal = std::clamp(static_cast<double>(d["kcal"]), 0.0, 3600.0);
    if (d.has("hydration")) hydration = std::clamp(static_cast<double>(d["hydration"]), 0.0, 120.0);
    if (d.has("fatigue")) fatigue = std::clamp(static_cast<double>(d["fatigue"]), 0.0, 100.0);
    if (d.has("morale")) morale = std::clamp(static_cast<int>(d["morale"]), -50, 50);
    if (d.get("worn", Variant()).get_type() == Variant::ARRAY) {
        const Array w = d["worn"];
        std::vector<int> next;
        for (int i = 0; i < w.size(); ++i) {
            const int id = static_cast<int>(w[i]);
            if (id >= 0 && id < kItemCount) next.push_back(id);
        }
        worn = std::move(next);
    }
    return true;
}

} // namespace cangling
