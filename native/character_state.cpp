#include "character_state.hpp"
#include <godot_cpp/variant/variant.hpp>
#include <algorithm>
#include <cmath>

namespace cangling {
using namespace godot;

namespace {
constexpr int kBaseCarryVolumeMl = 2500;
constexpr int kMaxLayersPerSlot = 2;
}

void CharacterState::reset_defaults() {
    kcal = 2400.0;
    hydration = 100.0;
    fatigue = 6.0;
    stamina = 10000;
    pain = 0;
    morale = 10;
    focus = 100;
    move_mode = 0;
    safe_mode = true;
    hauling = false;
    lamp_lit = false;
    light_source = 0;
    wielded = -1;
    last_sound = 0;
    stat_str = 8;
    stat_dex = 8;
    stat_int = 8;
    stat_per = 8;
    part_hp = {kMaxPartHp, kMaxPartHp, kMaxPartHp, kMaxPartHp, kMaxPartHp, kMaxPartHp};
    // Authentic civilian Jiangnan starting outfit: tunic, pants, boots, cloak, pouch
    worn = {6, 8, 12, 10, 15};
}

void CharacterState::advance_minutes(int delta_minutes, bool resting, bool sleeping) {
    if (delta_minutes <= 0) return;
    const double dm = static_cast<double>(delta_minutes);
    const double kcal_rate = sleeping ? 0.65 : resting ? 0.95 : (move_mode == 1 ? 2.2 : 1.45);
    const double water_rate = sleeping ? 0.045 : resting ? 0.065 : (move_mode == 1 ? 0.14 : 0.095);
    kcal = std::clamp(kcal - dm * kcal_rate, 0.0, 3600.0);
    hydration = std::clamp(hydration - dm * water_rate, 0.0, 120.0);
    if (sleeping) {
        fatigue = std::clamp(fatigue - dm * 0.45, 0.0, 100.0);
        stamina = std::min(10000, stamina + delta_minutes * 450);
    } else if (resting) {
        fatigue = std::clamp(fatigue - dm * 0.16, 0.0, 100.0);
        stamina = std::min(10000, stamina + delta_minutes * 260);
    } else {
        fatigue = std::clamp(fatigue + dm * 0.085, 0.0, 100.0);
        if (move_mode != 1) {
            stamina = std::min(10000, stamina + delta_minutes * 120);
        }
    }
    if (pain > 0) pain = std::max(0, pain - delta_minutes / 4);
    last_sound = std::max(0, last_sound - delta_minutes * 12);
}

void CharacterState::spend_stamina(int amount) {
    stamina = std::clamp(stamina - amount, 0, 10000);
    if (stamina < 1200 && move_mode == 1) {
        move_mode = 0; // Auto-drop from running when winded (CCB behavior)
    }
}

int CharacterState::current_speed() const {
    int spd = 100;
    if (pain > 10) spd -= pain / 3;
    if (fatigue > 75.0) spd -= 10;
    if (stamina < 2500) spd -= 15;
    if (move_mode == 1) spd += 25;
    else if (move_mode == 2) spd -= 20;
    else if (move_mode == 3) spd -= 45;
    return std::max(40, spd);
}

int CharacterState::bash_power() const {
    int power = stat_str + 2;
    if (wielded >= 0 && wielded < kItemCount) {
        power += item_catalog()[wielded].bash_dmg;
    }
    power -= total_encumbrance() / 8;
    return std::max(4, power);
}

int CharacterState::carry_weight_g(const ItemCounts &carried, int bottle_water_ml) const {
    const auto &cat = item_catalog();
    int total = 220 + bottle_water_ml;
    for (int i = 0; i < kItemCount; ++i) total += carried[i] * cat[i].weight_g;
    for (int id : worn) if (id >= 0 && id < kItemCount) total += cat[id].weight_g;
    if (wielded >= 0 && wielded < kItemCount) total += cat[wielded].weight_g;
    return total;
}

int CharacterState::carry_volume_ml(const ItemCounts &carried) const {
    const auto &cat = item_catalog();
    int total = 0;
    for (int i = 0; i < kItemCount; ++i) total += carried[i] * cat[i].volume_ml;
    return total;
}

int CharacterState::max_carry_volume_ml() const {
    const auto &cat = item_catalog();
    int total = kBaseCarryVolumeMl;
    for (int id : worn) if (id >= 0 && id < kItemCount) total += cat[id].storage_ml;
    return total;
}

int CharacterState::total_warmth() const {
    const auto &cat = item_catalog();
    int total = 0;
    for (int id : worn) if (id >= 0 && id < kItemCount) total += cat[id].warmth;
    return total;
}

int CharacterState::total_encumbrance() const {
    const auto &cat = item_catalog();
    int total = 0;
    for (int id : worn) if (id >= 0 && id < kItemCount) total += cat[id].encumbrance;
    return total;
}

int CharacterState::slot_layer_count(WearSlot slot) const {
    const auto &cat = item_catalog();
    int count = 0;
    for (int id : worn) if (id >= 0 && id < kItemCount && cat[id].slot == slot) ++count;
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
    if (fatigue <= 18.0) return String::utf8("精神");
    if (fatigue <= 40.0) return String::utf8("尚可");
    if (fatigue <= 60.0) return String::utf8("略倦");
    if (fatigue <= 78.0) return String::utf8("疲惫");
    if (fatigue <= 90.0) return String::utf8("困倦");
    return String::utf8("精疲力竭");
}

String CharacterState::pain_status() const {
    if (pain <= 0) return String::utf8("无痛");
    if (pain <= 15) return String::utf8("微痛");
    if (pain <= 35) return String::utf8("疼痛");
    return String::utf8("剧痛");
}

String CharacterState::move_mode_label() const {
    switch (move_mode) {
        case 1: return String::utf8("奔跑");
        case 2: return String::utf8("潜行");
        case 3: return String::utf8("匍匐");
        default: return String::utf8("行走");
    }
}

String CharacterState::wielded_label() const {
    if (wielded < 0 || wielded >= kItemCount) return String::utf8("空手");
    String s = String::utf8(item_catalog()[wielded].name);
    if (wielded == 41 && lamp_lit) s += String::utf8("（已点亮）");
    return s;
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

String CharacterState::wield_from_bag(int item_id, ItemCounts &carried) {
    if (item_id < 0 || item_id >= kItemCount || carried[item_id] <= 0) return {};
    if (wielded >= 0 && wielded < kItemCount) {
        ++carried[wielded];
        if (wielded == 41) lamp_lit = false;
    }
    --carried[item_id];
    wielded = item_id;
    return String::utf8("你手持了") + String::utf8(item_catalog()[item_id].name) + String::utf8("。");
}

String CharacterState::unwield_to_bag(ItemCounts &carried) {
    if (wielded < 0 || wielded >= kItemCount) return String::utf8("你当前本来就是空手。");
    const String name = String::utf8(item_catalog()[wielded].name);
    ++carried[wielded];
    if (wielded == 41) lamp_lit = false;
    wielded = -1;
    return String::utf8("你收起了手中的") + name + String::utf8("。");
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
    const double gain = static_cast<double>(ml) * 0.16;
    hydration = std::clamp(hydration + gain, 0.0, 120.0);
    minutes_out += 1;
    advance_minutes(1, true, false);
    return String::utf8("你喝下了 ") + String::num_int64(ml) + String::utf8(" 毫升清水，顿时解渴不少。");
}

String CharacterState::apply_item(int item_id, ItemCounts &carried, int &minutes_out) {
    const bool from_hand = (item_id == wielded && item_id >= 0);
    if (item_id < 0 || item_id >= kItemCount || (!from_hand && carried[item_id] <= 0)) return {};
    const auto &def = item_catalog()[item_id];
    // Portable dynamic light sources: 1=火折子(42), 2=红油蜡烛(47), 3=桐油手灯(41)
    if (item_id == 42 || item_id == 47 || item_id == 41) {
        const int next_kind = (item_id == 42) ? 1 : (item_id == 47 ? 2 : 3);
        const bool turning_on = (light_source != next_kind);
        light_source = turning_on ? next_kind : 0;
        lamp_lit = (light_source > 0);
        minutes_out += 1;
        if (turning_on) {
            if (item_id == 42) return String::utf8("你拔开竹帽轻吹火折子，橘红火苗跃动，照亮了身周。");
            if (item_id == 47) return String::utf8("你点燃了红油蜡烛，摇曳的烛光照亮了四周。");
            return String::utf8("你点亮了桐油手灯，暖黄灯火透过灯罩洒向四周。");
        }
        return String::utf8("你熄灭了") + String::utf8(def.name) + String::utf8("。");
    }
    // Bandage (46) or Rag (44): heal limbs & ease pain!
    if (item_id == 46 || item_id == 44) {
        if (!from_hand) --carried[item_id];
        else wielded = -1;
        const int heal = (item_id == 46) ? 18 : 8;
        for (int &hp : part_hp) hp = std::min(kMaxPartHp, hp + heal);
        pain = std::max(0, pain - (item_id == 46 ? 12 : 4));
        minutes_out += 3;
        return String::utf8("你用") + String::utf8(def.name) + String::utf8("仔细包扎了伤处，气血舒缓了不少。");
    }
    // Book (29): read!
    if (def.category == ItemCategory::Book) {
        return read_book(item_id, minutes_out);
    }
    // Food / drink fallback
    if (def.category == ItemCategory::Food || def.category == ItemCategory::Drink) {
        if (!from_hand) return consume_item(item_id, carried, minutes_out);
        ItemCounts tmp{}; tmp[item_id] = 1;
        const String res = consume_item(item_id, tmp, minutes_out);
        if (tmp[item_id] == 0) wielded = -1;
        return res;
    }
    return String::utf8(def.name) + String::utf8("暂无可直接激活的效果，可手持（w）或存放。");
}

String CharacterState::read_book(int item_id, int &minutes_out) {
    if (item_id < 0 || item_id >= kItemCount || item_catalog()[item_id].category != ItemCategory::Book) {
        return String::utf8("这件物品并非书籍典籍。");
    }
    minutes_out += 15;
    advance_minutes(15, true, false);
    morale = std::clamp(morale + 6, -50, 50);
    focus = std::min(120, focus + 5);
    return String::utf8("你静心翻阅《") + String::utf8(item_catalog()[item_id].name) +
           String::utf8("》一刻钟，见识渐长，心境颇为安宁。");
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
    out["stamina"] = stamina;
    out["pain"] = pain;
    out["pain_text"] = pain_status();
    out["morale"] = morale;
    out["focus"] = focus;
    out["speed"] = current_speed();
    out["move_mode"] = move_mode;
    out["move_mode_text"] = move_mode_label();
    out["safe_mode"] = safe_mode;
    out["hauling"] = hauling;
    out["lamp_lit"] = lamp_lit;
    out["light_source"] = light_source;
    out["light_name"] = String::utf8(light_source == 1 ? "火折子" : light_source == 2 ? "红油蜡烛" : light_source == 3 ? "桐油手灯" : "");
    out["wielded_id"] = wielded;
    out["wielded_text"] = wielded_label();
    out["bash_power"] = bash_power();
    out["last_sound"] = last_sound;
    out["str"] = stat_str;
    out["dex"] = stat_dex;
    out["int"] = stat_int;
    out["per"] = stat_per;
    Array hp_arr;
    for (int h : part_hp) hp_arr.append(h);
    out["part_hp"] = hp_arr;
    out["max_part_hp"] = kMaxPartHp;
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
    d["stamina"] = stamina;
    d["pain"] = pain;
    d["morale"] = morale;
    d["move_mode"] = move_mode;
    d["wielded"] = wielded;
    d["lamp_lit"] = lamp_lit;
    d["light_source"] = light_source;
    Array hp;
    for (int h : part_hp) hp.append(h);
    d["part_hp"] = hp;
    Array w;
    for (int id : worn) w.append(id);
    d["worn"] = w;
    return d;
}

bool CharacterState::load_dict(const Dictionary &d) {
    if (d.has("kcal")) kcal = std::clamp(static_cast<double>(d["kcal"]), 0.0, 3600.0);
    if (d.has("hydration")) hydration = std::clamp(static_cast<double>(d["hydration"]), 0.0, 120.0);
    if (d.has("fatigue")) fatigue = std::clamp(static_cast<double>(d["fatigue"]), 0.0, 100.0);
    if (d.has("stamina")) stamina = std::clamp(static_cast<int>(d["stamina"]), 0, 10000);
    if (d.has("pain")) pain = std::clamp(static_cast<int>(d["pain"]), 0, 100);
    if (d.has("morale")) morale = std::clamp(static_cast<int>(d["morale"]), -50, 50);
    if (d.has("move_mode")) move_mode = std::clamp(static_cast<int>(d["move_mode"]), 0, 3);
    if (d.has("wielded")) {
        const int wi = static_cast<int>(d["wielded"]);
        wielded = (wi >= 0 && wi < kItemCount) ? wi : -1;
    }
    if (d.has("light_source")) {
        light_source = std::clamp(static_cast<int>(d["light_source"]), 0, 3);
        lamp_lit = (light_source > 0);
    } else if (d.has("lamp_lit")) {
        lamp_lit = static_cast<bool>(d["lamp_lit"]);
        light_source = lamp_lit ? 3 : 0;
    }
    if (d.get("part_hp", Variant()).get_type() == Variant::ARRAY) {
        const Array hp = d["part_hp"];
        for (int i = 0; i < std::min<int>(hp.size(), 6); ++i) {
            part_hp[i] = std::clamp(static_cast<int>(hp[i]), 1, kMaxPartHp);
        }
    }
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
