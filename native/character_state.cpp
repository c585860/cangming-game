#include "character_state.hpp"
#include <godot_cpp/variant/variant.hpp>
#include <algorithm>
#include <cmath>
#include <cstring>

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
    max_part_hp = kBaseMaxPartHp;
    neili = 0;
    max_neili = 0;
    neili_bonus_cap = 0;
    jiali = 0;
    exert_warmth = false;
    body_temp_c = 37.0;
    wetness = 0.0;
    ambient_temp_c = 18.0;
    rain_intensity = 0.0;
    is_indoors = false;
    near_hearth = false;
    bank_coins = 0;
    reputation = 0;
    spar_wins = 0;
    spar_total = 0;
    inn_room_until_min = 0;
    cached_force_lv = 0;
    cached_dodge_lv = 0;
    cached_unarmed_lv = 0;
    cached_medicine_lv = 0;
    cached_cooking_lv = 0;
    cached_weapon_lv = 0;
    part_hp = {max_part_hp, max_part_hp, max_part_hp, max_part_hp, max_part_hp, max_part_hp};
    // Authentic civilian Jiangnan starting outfit: tunic, pants, boots, cloak, pouch
    worn = {6, 8, 12, 10, 15};
}

void CharacterState::sync_with_skills(const SkillSet &skills) {
    cached_force_lv = skills.effective_level_of("force");
    cached_dodge_lv = skills.effective_level_of("dodge");
    cached_unarmed_lv = std::max({skills.effective_level_of("unarmed"), skills.effective_level_of("strike"), skills.effective_level_of("cuff")});
    cached_medicine_lv = skills.level_of("medicine");
    cached_cooking_lv = skills.level_of("cooking");
    cached_weapon_lv = std::max({skills.effective_level_of("sword"), skills.effective_level_of("blade"),
                                 skills.effective_level_of("staff"), skills.effective_level_of("club"),
                                 skills.effective_level_of("spear")});
    const int parry_lv = skills.effective_level_of("parry");
    const int base_force_lv = skills.level_of("force");
    const int old_max = std::max(1, max_part_hp);
    const int next_max = kBaseMaxPartHp + cached_force_lv * 3 + (cached_unarmed_lv + parry_lv) / 2;
    if (next_max != max_part_hp) {
        const int delta = next_max - old_max;
        max_part_hp = next_max;
        for (int &hp : part_hp) {
            if (delta > 0) hp = std::min(max_part_hp, hp + delta);
            else hp = std::clamp(hp, 1, max_part_hp);
        }
    }
    const int max_bonus = std::max(0, cached_force_lv * 15);
    neili_bonus_cap = std::clamp(neili_bonus_cap, 0, max_bonus);
    const int old_neili_max = max_neili;
    max_neili = base_force_lv * 25 + (cached_force_lv - base_force_lv) * 15 + neili_bonus_cap;
    if (max_neili > old_neili_max) {
        neili = std::min(max_neili, neili + (max_neili - old_neili_max));
    } else {
        neili = std::clamp(neili, 0, max_neili);
    }
    if (max_neili <= 0) {
        exert_warmth = false;
        jiali = 0;
    }
}

void CharacterState::update_environment(double ambient_c, double rain, bool indoors, bool hearth) {
    ambient_temp_c = ambient_c;
    rain_intensity = std::clamp(rain, 0.0, 1.0);
    is_indoors = indoors;
    near_hearth = hearth;
}

void CharacterState::advance_minutes(int delta_minutes, bool resting, bool sleeping, bool inn_bonus) {
    if (delta_minutes <= 0) return;
    const double dm = static_cast<double>(delta_minutes);
    const double kcal_rate = sleeping ? 0.65 : resting ? 0.95 : (move_mode == 1 ? 2.2 : 1.45);
    const double water_rate = sleeping ? 0.045 : resting ? 0.065 : (move_mode == 1 ? 0.14 : 0.095);
    kcal = std::clamp(kcal - dm * kcal_rate, 0.0, 3600.0);
    hydration = std::clamp(hydration - dm * water_rate, 0.0, 120.0);

    // Rain wetness accumulation & drying (CCB weather/clothing/hearth linkage!)
    if (!is_indoors && rain_intensity > 0.05) {
        const double resist = static_cast<double>(total_rain_resist()) / 100.0;
        const double wet_gain = dm * rain_intensity * 4.2 * (1.0 - resist);
        wetness = std::clamp(wetness + wet_gain, 0.0, 100.0);
    } else {
        const double dry_rate = near_hearth ? 7.5 : (is_indoors ? 2.2 : 1.2);
        wetness = std::max(0.0, wetness - dm * dry_rate);
    }

    // Active inner-force cold resistance consumes 1 neili per 2 minutes
    if (exert_warmth) {
        const int nl_cost = std::max(1, delta_minutes / 2);
        if (neili >= nl_cost) neili -= nl_cost;
        else exert_warmth = false;
    }

    // Apparent body temperature (33.0..39.5 C)
    const double cloth_warmth = static_cast<double>(total_warmth() + cached_force_lv / 3);
    const double env_c = ambient_temp_c + (is_indoors ? 4.5 : 0.0) + (near_hearth ? 11.0 : 0.0) +
                         (exert_warmth ? 10.0 : 0.0) + (inn_bonus ? 5.0 : 0.0);
    const double effective_c = env_c + cloth_warmth * 0.22 - wetness * 0.14;
    const double target_body = std::clamp(37.0 + (effective_c - 24.0) * 0.11, 33.5, 39.0);
    const double blend = 1.0 - std::exp(-dm / 16.0);
    body_temp_c = body_temp_c + (target_body - body_temp_c) * blend;
    if (body_temp_c < 35.4) {
        morale = std::max(-50, morale - std::max(1, delta_minutes / 12));
    }

    const int force_regen_bonus = cached_force_lv * 8;
    const int inn_mult = inn_bonus ? 2 : 1;
    if (sleeping) {
        fatigue = std::clamp(fatigue - dm * 0.45 * inn_mult, 0.0, 100.0);
        stamina = std::min(10000, stamina + delta_minutes * (450 + force_regen_bonus) * inn_mult);
    } else if (resting) {
        fatigue = std::clamp(fatigue - dm * 0.16 * inn_mult, 0.0, 100.0);
        stamina = std::min(10000, stamina + delta_minutes * (260 + force_regen_bonus) * inn_mult);
    } else {
        fatigue = std::clamp(fatigue + dm * 0.085, 0.0, 100.0);
        if (move_mode != 1) {
            stamina = std::min(10000, stamina + delta_minutes * (120 + force_regen_bonus / 2));
        }
    }
    // Natural HP & Neili recovery when nourished (boosted by 基本内功), or starvation damage when depleted!
    if (kcal >= 1200.0 && hydration >= 40.0) {
        const int hp_gain = (delta_minutes * (1 + (resting || sleeping ? 1 : 0) + cached_force_lv / 10) * inn_mult) / 10;
        if (hp_gain > 0) {
            for (int &hp : part_hp) hp = std::min(max_part_hp, hp + hp_gain);
        }
        if (max_neili > 0) {
            const int nl_gain = delta_minutes * (1 + (resting || sleeping ? 2 : 0) + cached_force_lv / 6) * inn_mult;
            neili = std::min(max_neili, neili + nl_gain);
        }
    } else if (kcal <= 50.0 || hydration <= 5.0) {
        const int starve_dmg = std::max(1, delta_minutes / 8);
        for (int i = 1; i < 6; ++i) part_hp[i] = std::max(1, part_hp[i] - starve_dmg);
    }
    if (pain > 0) pain = std::max(0, pain - (delta_minutes * (1 + cached_force_lv / 12) * inn_mult) / 4);
    if (focus < 100 && (resting || sleeping)) {
        focus = std::min(120, focus + delta_minutes / 3);
    }
    last_sound = std::max(0, last_sound - delta_minutes * 12);
}

void CharacterState::spend_stamina(int amount) {
    const double mult = 1.0 - std::min(0.40, static_cast<double>(cached_dodge_lv) * 0.015);
    const int eff = std::max(1, static_cast<int>(std::round(static_cast<double>(amount) * mult)));
    stamina = std::clamp(stamina - eff, 0, 10000);
    if (stamina < 1200 && move_mode == 1) {
        move_mode = 0;
    }
}

int CharacterState::current_speed() const {
    int spd = 100 + std::min(40, cached_dodge_lv / 2);
    if (pain > 10) spd -= pain / 3;
    if (fatigue > 75.0) spd -= 10;
    if (stamina < 2500) spd -= 15;
    if (kcal < 400.0 || hydration < 15.0) spd -= 12;
    if (body_temp_c < 35.5) spd -= 10;
    else if (body_temp_c < 36.2) spd -= 4;
    if (wetness > 65.0) spd -= 5;
    if (move_mode == 1) spd += 25;
    else if (move_mode == 2) spd -= 20;
    else if (move_mode == 3) spd -= 45;
    return std::max(40, spd);
}

int CharacterState::bash_power() const {
    int power = stat_str + 2 + jiali / 3;
    if (wielded >= 0 && wielded < kItemCount) {
        power += item_catalog()[wielded].bash_dmg + cached_weapon_lv / 2;
    } else {
        power += cached_unarmed_lv / 2;
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

int CharacterState::total_rain_resist() const {
    const auto &cat = item_catalog();
    int total = 0;
    for (int id : worn) if (id >= 0 && id < kItemCount) total += cat[id].rain_resist;
    return std::min(95, total);
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

String CharacterState::temp_status() const {
    String base;
    if (body_temp_c < 35.2) base = String::utf8("刺骨");
    else if (body_temp_c < 36.0) base = String::utf8("寒冷");
    else if (body_temp_c < 36.5) base = String::utf8("微凉");
    else if (body_temp_c <= 37.6) base = String::utf8("舒适");
    else if (body_temp_c <= 38.2) base = String::utf8("暖和");
    else base = String::utf8("燥热");

    if (wetness >= 60.0) base += String::utf8("[湿透]");
    else if (wetness >= 22.0) base += String::utf8("[潮湿]");
    if (exert_warmth) base += String::utf8("[御寒]");
    else if (near_hearth) base += String::utf8("[烤火]");
    return base;
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
    const double cook_mult = (def.category == ItemCategory::Food) ? (1.0 + static_cast<double>(cached_cooking_lv) * 0.02) : 1.0;
    kcal = std::clamp(kcal + static_cast<double>(def.kcal) * cook_mult, 0.0, 3600.0);
    hydration = std::clamp(hydration + static_cast<double>(def.quench), 0.0, 120.0);
    morale = std::clamp(morale + static_cast<int>(std::round(static_cast<double>(def.joy) * cook_mult)), -50, 50);
    // Warm dishes & wine warm the body slightly
    if (std::strcmp(def.key, "lion_head") == 0 || std::strcmp(def.key, "yangchun_noodles") == 0 ||
        std::strcmp(def.key, "daughter_wine") == 0 || std::strcmp(def.key, "rice_bowl") == 0) {
        body_temp_c = std::min(37.6, body_temp_c + 0.5);
        stamina = std::min(10000, stamina + 1200);
    }
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
    // Towel (48): dry off rain wetness
    if (item_id == 48) {
        if (wetness <= 1.0) return String::utf8("你身上本就干爽，无需擦拭。");
        wetness = std::max(0.0, wetness - 45.0);
        return String::utf8("你取出棉布手巾擦干衣袂上的雨水，顿觉清爽暖和。");
    }
    // Bandage (46), Rag (44), or Trauma Salve (60): heal 6 limbs & ease pain
    if (item_id == 46 || item_id == 44 || std::strcmp(def.key, "trauma_salve") == 0) {
        if (!from_hand) --carried[item_id];
        else wielded = -1;
        const double med_mult = 1.0 + static_cast<double>(cached_medicine_lv) * 0.05;
        const double base_heal = (std::strcmp(def.key, "trauma_salve") == 0) ? 34.0 : (item_id == 46 ? 18.0 : 8.0);
        const double base_pain = (std::strcmp(def.key, "trauma_salve") == 0) ? 24.0 : (item_id == 46 ? 12.0 : 4.0);
        const int heal = static_cast<int>(std::round(base_heal * med_mult));
        for (int &hp : part_hp) hp = std::min(max_part_hp, hp + heal);
        pain = std::max(0, pain - static_cast<int>(std::round(base_pain * med_mult)));
        minutes_out += 3;
        return String::utf8("你用「") + String::utf8(def.name) + String::utf8("」细心敷伤包扎，全身气血回复 +") +
               String::num_int64(heal) + String::utf8("，痛感大减。");
    }
    // Qi Powder (61): restore neili + stamina + cut fatigue
    if (std::strcmp(def.key, "qi_powder") == 0) {
        if (!from_hand) --carried[item_id];
        else wielded = -1;
        const double med_mult = 1.0 + static_cast<double>(cached_medicine_lv) * 0.04;
        const int nl_add = static_cast<int>(std::round(45.0 * med_mult));
        if (max_neili > 0) neili = std::min(max_neili, neili + nl_add);
        stamina = std::min(10000, stamina + 2500);
        fatigue = std::max(0.0, fatigue - 12.0);
        morale = std::min(50, morale + 4);
        return String::utf8("你服下一包「培元行气散」，丹田一股暖流化开（内力 +") +
               String::num_int64(max_neili > 0 ? nl_add : 0) + String::utf8("，耐力大复、倦意顿消）！");
    }
    if (def.category == ItemCategory::Book) {
        return read_book(item_id, minutes_out);
    }
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
           String::utf8("》，见识渐长，心境颇为安宁。");
}

Dictionary CharacterState::dazuo_cycle(SkillSet &skills, bool quiet_bonus) {
    Dictionary res;
    res["ok"] = false;
    res["continue"] = false;
    const int base_force = skills.level_of("force");
    if (base_force <= 0) {
        res["message"] = String::utf8("你尚未习得「基本内功」，不知如何吐纳行气！请先赴扬威武馆向陈馆主请教。");
        return res;
    }
    if (is_starving_for_training()) {
        res["message"] = String::utf8("你腹饥口渴、丹田空虚，难以继续打坐吐纳，先吃饱喝足吧。");
        return res;
    }
    if (stamina < 450) {
        res["message"] = String::utf8("你气息已乏，缓缓收功调息。");
        return res;
    }
    const int eff_force = skills.effective_level_of("force");
    const bool has_special = !skills.enabled_art_of("force").empty();
    const double mult = (quiet_bonus ? 1.25 : 1.0) * (has_special ? 1.30 : 1.0) * (is_well_fed() ? 1.15 : 1.0);
    const int gain = std::max(8, static_cast<int>(std::round((10.0 + static_cast<double>(eff_force) * 1.4) * mult)));

    spend_stamina(420);
    kcal = std::max(0.0, kcal - 14.0);
    hydration = std::max(0.0, hydration - 1.2);
    fatigue = std::max(0.0, fatigue - 1.5);
    morale = std::min(50, morale + 1);

    String msg;
    const int max_bonus = std::max(0, eff_force * 15);
    if (neili < max_neili) {
        const int before = neili;
        neili = std::min(max_neili, neili + gain);
        msg = String::utf8("你盘膝运起小周天吐纳，真气归元（内力 +") + String::num_int64(neili - before) +
              String::utf8("，当前 ") + String::num_int64(neili) + String("/") + String::num_int64(max_neili) + String::utf8("）。");
        res["continue"] = true;
    } else if (neili_bonus_cap < max_bonus) {
        const int cap_add = std::min(max_bonus - neili_bonus_cap, has_special ? 4 : 2);
        neili_bonus_cap += cap_add;
        sync_with_skills(skills);
        neili = max_neili;
        msg = String::utf8("你丹田充盈，将多余真气徐徐凝炼冲关！内力上限永久精进 +") + String::num_int64(cap_add) +
              String::utf8("（当前上限 ") + String::num_int64(max_neili) + String::utf8("）！");
        res["continue"] = (neili_bonus_cap < max_bonus);
    } else {
        msg = String::utf8("你周天圆满，内力与凝炼修为皆已臻当前瓶颈，缓缓吐出一口浊气收功。");
        res["continue"] = false;
    }

    // Small passive 基本内功 & special force exp during meditation
    const int fidx = find_base_skill_index("force");
    if (fidx >= 0) {
        bool lv = false;
        skills.add_exp(fidx, 4, lv);
    }
    const std::string sp = skills.enabled_art_of("force");
    if (!sp.empty()) {
        const int sidx = find_special_art_index(sp);
        if (sidx >= 0) {
            bool lv = false;
            skills.add_special_exp(sidx, 5, lv);
        }
    }
    sync_with_skills(skills);
    res["ok"] = true;
    res["message"] = msg;
    return res;
}

String CharacterState::exert_action(const std::string &kind) {
    if (max_neili <= 0) {
        return String::utf8("你尚未习得「基本内功」，体内尚无真气可运！请先赴扬威武馆向陈馆主请教。");
    }
    if (kind == "recover") {
        constexpr int cost = 15;
        if (neili < cost) return String::utf8("内力不足（运功调息需 15 点内力）。");
        neili -= cost;
        stamina = std::min(10000, stamina + 2800 + cached_force_lv * 40);
        fatigue = std::max(0.0, fatigue - 10.0);
        return String::utf8("你深吸一口气运功调息，耗内力 15 点，顿时气息平复、耐力大涨！");
    }
    if (kind == "heal") {
        constexpr int cost = 25;
        if (neili < cost) return String::utf8("内力不足（运功疗伤需 25 点内力）。");
        neili -= cost;
        const int heal = 12 + cached_force_lv;
        for (int &hp : part_hp) hp = std::min(max_part_hp, hp + heal);
        pain = std::max(0, pain - (10 + cached_force_lv / 2));
        return String::utf8("你盘膝运功导引真气游走经脉，全身六部位气血各复 +") + String::num_int64(heal) +
               String::utf8("，痛感随之消散！");
    }
    if (kind == "warmth") {
        exert_warmth = !exert_warmth;
        if (exert_warmth) {
            if (neili < 5) {
                exert_warmth = false;
                return String::utf8("内力不足，无法催动真气御寒。");
            }
            body_temp_c = std::min(37.4, body_temp_c + 0.7);
            return String::utf8("你暗运丹田纯阳真气护体御寒，寒湿之气顿时退避三舍！");
        }
        return String::utf8("你散去护体御寒真气，恢复自然呼吸。");
    }
    if (kind == "jiali_cycle") {
        static constexpr int kLevels[4] = {0, 5, 15, 30};
        int cur = 0;
        for (int i = 0; i < 4; ++i) if (jiali == kLevels[i]) cur = i;
        jiali = kLevels[(cur + 1) % 4];
        if (jiali == 0) return String::utf8("你收回拳锋掌劲，运功加力已归零（0）。");
        return String::utf8("你暗提真气贯注招式，当前出招加力设为：") + String::num_int64(jiali) + String::utf8(" 点。");
    }
    return String::utf8("未知的运功法门。");
}

String CharacterState::study_book_cycle(int item_id, ItemCounts &carried, SkillSet &skills, bool academy_bonus) {
    if (item_id < 0 || item_id >= kItemCount || carried[item_id] <= 0) {
        return String::utf8("行囊中没有这卷典籍。");
    }
    const auto &def = item_catalog()[item_id];
    if (def.category != ItemCategory::Book) return String::utf8("这件物品并非典籍。");
    if (is_starving_for_training()) return String::utf8("你又饿又渴、眼花心浮，先吃些东西再来精读吧。");

    // Hand-copied martial notes: consumable instant insight!
    if (def.book_skill && std::strcmp(def.book_skill, "notes_pot") == 0) {
        --carried[item_id];
        const int pot = skills.add_potential(14);
        focus = std::min(120, focus + 8);
        morale = std::min(50, morale + 5);
        return String::utf8("你细细研读了这卷「手抄武学心得」，融会贯通后将旧卷收起（潜能 +") +
               String::num_int64(pot) + String::utf8("、专注 +8）！");
    }

    // Generic lore scroll (江南风物野史)
    if (!def.book_skill || def.book_skill[0] == '\0') {
        const int pot = skills.add_potential(academy_bonus ? 6 : 4);
        morale = std::min(50, morale + 7);
        focus = std::min(120, focus + 6);
        kcal = std::max(0.0, kcal - 8.0);
        return String::utf8("你潜心翻阅《") + String::utf8(def.name) + String::utf8("》，心旷神怡，另悟得潜能 +") +
               String::num_int64(pot) + String::utf8("。");
    }

    const int lit_lv = skills.level_of("literate");
    if (lit_lv < def.book_min_lit) {
        return String::utf8("《") + String::utf8(def.name) + String::utf8("》字句深奥，需「读书写字」≥ ") +
               String::num_int64(def.book_min_lit) + String::utf8(" 级方可领悟（当前 ") +
               String::num_int64(lit_lv) + String::utf8(" 级，先去文昌书院请教顾夫子或读《三字经·千字文》）。");
    }
    const int sidx = find_base_skill_index(def.book_skill);
    if (sidx < 0) return String::utf8("书中所述技艺晦涩难辨。");
    const auto &sdef = base_skill_catalog()[static_cast<std::size_t>(sidx)];
    auto &st = skills.base[static_cast<std::size_t>(sidx)];
    if (st.level >= def.book_max_lv) {
        return String::utf8("你对「") + String::utf8(sdef.name) + String::utf8("」的领悟已超出《") +
               String::utf8(def.name) + String::utf8("》所载上限（") + String::num_int64(def.book_max_lv) + String::utf8(" 级）。");
    }
    if (focus < 15) {
        return String::utf8("你心神倦怠、专注不足，歇息片刻或听段评书再来研读吧。");
    }

    focus = std::max(0, focus - 10);
    kcal = std::max(0.0, kcal - 12.0);
    hydration = std::max(0.0, hydration - 1.2);
    fatigue = std::min(100.0, fatigue + 1.4);

    const bool was_unlearned = (st.level == 0);
    const double mult = (academy_bonus ? 1.25 : 1.0) * (1.0 + static_cast<double>(lit_lv) * 0.03);
    const int gain = std::max(14, static_cast<int>(std::round((14.0 + static_cast<double>(stat_int) * 1.6) * mult)));
    bool leveled = false;
    if (was_unlearned) {
        st.level = 1;
        st.exp = 0;
        leveled = true;
    } else {
        skills.add_exp(sidx, gain, leveled);
    }
    skills.add_combat_exp(3);
    sync_with_skills(skills);

    if (was_unlearned) {
        return String::utf8("你伏案精读《") + String::utf8(def.name) + String::utf8("》，豁然开窍，正式入门「") +
               String::utf8(sdef.name) + String::utf8("」（1 级）！");
    }
    if (leveled) {
        return String::utf8("你精读《") + String::utf8(def.name) + String::utf8("》颇有心得，「") +
               String::utf8(sdef.name) + String::utf8("」晋升至 ") + String::num_int64(st.level) + String::utf8(" 级！");
    }
    return String::utf8("你精读《") + String::utf8(def.name) + String::utf8("》，「") +
           String::utf8(sdef.name) + String::utf8("」熟练度 +") + String::num_int64(gain) + String::utf8("（") +
           String::num_int64(st.exp) + String("/") + String::num_int64(skill_exp_to_next(st.level)) + String::utf8("）。");
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
        row["rain_resist"] = def.rain_resist;
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
    out["max_part_hp"] = max_part_hp;
    out["neili"] = neili;
    out["max_neili"] = max_neili;
    out["neili_bonus_cap"] = neili_bonus_cap;
    out["jiali"] = jiali;
    out["exert_warmth"] = exert_warmth;
    out["body_temp_c"] = body_temp_c;
    out["wetness"] = static_cast<int>(std::round(wetness));
    out["temp_text"] = temp_status();
    out["rain_resist"] = total_rain_resist();
    out["bank_coins"] = bank_coins;
    out["reputation"] = reputation;
    out["spar_wins"] = spar_wins;
    out["spar_total"] = spar_total;
    out["inn_room_until_min"] = inn_room_until_min;
    out["well_fed"] = is_well_fed();
    out["starving_for_training"] = is_starving_for_training();
    out["severely_injured"] = is_severely_injured();
    out["hunger_text"] = hunger_status();
    out["thirst_text"] = thirst_status();
    out["fatigue_text"] = fatigue_status();
    out["warmth"] = total_warmth() + cached_force_lv / 3;
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
    d["focus"] = focus;
    d["move_mode"] = move_mode;
    d["wielded"] = wielded;
    d["lamp_lit"] = lamp_lit;
    d["light_source"] = light_source;
    d["max_part_hp"] = max_part_hp;
    d["neili"] = neili;
    d["max_neili"] = max_neili;
    d["neili_bonus_cap"] = neili_bonus_cap;
    d["jiali"] = jiali;
    d["exert_warmth"] = exert_warmth;
    d["body_temp_c"] = body_temp_c;
    d["wetness"] = wetness;
    d["bank_coins"] = bank_coins;
    d["reputation"] = reputation;
    d["spar_wins"] = spar_wins;
    d["spar_total"] = spar_total;
    d["inn_room_until_min"] = inn_room_until_min;
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
    if (d.has("focus")) focus = std::clamp(static_cast<int>(d["focus"]), 0, 120);
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
    if (d.has("max_part_hp")) max_part_hp = std::clamp(static_cast<int>(d["max_part_hp"]), kBaseMaxPartHp, 9999);
    if (d.has("neili_bonus_cap")) neili_bonus_cap = std::max(0, static_cast<int>(d["neili_bonus_cap"]));
    if (d.has("max_neili")) max_neili = std::max(0, static_cast<int>(d["max_neili"]));
    if (d.has("neili")) neili = std::clamp(static_cast<int>(d["neili"]), 0, std::max(max_neili, 99999));
    if (d.has("jiali")) jiali = std::clamp(static_cast<int>(d["jiali"]), 0, 30);
    if (d.has("exert_warmth")) exert_warmth = static_cast<bool>(d["exert_warmth"]);
    if (d.has("body_temp_c")) body_temp_c = std::clamp(static_cast<double>(d["body_temp_c"]), 33.0, 39.5);
    if (d.has("wetness")) wetness = std::clamp(static_cast<double>(d["wetness"]), 0.0, 100.0);
    if (d.has("bank_coins")) bank_coins = std::max(0, static_cast<int>(d["bank_coins"]));
    if (d.has("reputation")) reputation = std::max(0, static_cast<int>(d["reputation"]));
    if (d.has("spar_wins")) spar_wins = std::max(0, static_cast<int>(d["spar_wins"]));
    if (d.has("spar_total")) spar_total = std::max(0, static_cast<int>(d["spar_total"]));
    if (d.has("inn_room_until_min")) inn_room_until_min = std::max(0, static_cast<int>(d["inn_room_until_min"]));
    if (d.get("part_hp", Variant()).get_type() == Variant::ARRAY) {
        const Array hp = d["part_hp"];
        for (int i = 0; i < std::min<int>(hp.size(), 6); ++i) {
            part_hp[i] = std::clamp(static_cast<int>(hp[i]), 1, max_part_hp);
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
