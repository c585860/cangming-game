#include "crafting.hpp"
#include <godot_cpp/variant/variant.hpp>
#include <algorithm>
#include <cmath>
#include <cstring>

namespace cangling {
using namespace godot;

const std::array<RecipeDef, kRecipeCount> &recipe_catalog() {
    static const std::array<RecipeDef, kRecipeCount> kRecipes{{
        // --- 烹饪 (6) ---
        {"cook_yangchun", "热煮扬州阳春面", "烹饪", "cooking", 1, true, false, 200, "iron_pot",
         "noodles", 1, "salt", 1, "yangchun_noodles", 1, 2.5, 16, 6,
         "炉灶铁锅下干挂面加少许盐花，煮成热气腾腾的阳春面。"},
        {"cook_lion_head", "烹制红烧狮子头", "烹饪", "cooking", 5, true, false, 150, "iron_pot",
         "dried_meat", 2, "salt", 1, "lion_head", 1, 3.0, 24, 10,
         "以酱肉剁糜文火煨炖，成菜油润喷香、极补饱食与心境。"},
        {"cook_herb_tea", "煎煮清露草茶", "烹饪", "cooking", 1, true, false, 250, "",
         "herb_bundle", 1, "", 0, "herb_tea", 1, 2.0, 12, 4,
         "清水入灶煎煮干草药，温饮生津解乏。"},
        {"cook_meat_bun", "烤制酱肉炊饼", "烹饪", "cooking", 1, true, false, 0, "",
         "flatbread", 1, "dried_meat", 1, "rice_bowl", 2, 2.2, 14, 5,
         "将酱肉夹入烘热的炊饼中，饱腹耐饥。"},
        {"cook_clean_water", "烧开竹筒清水", "烹饪", "", 0, true, false, 250, "",
         "", 0, "", 0, "clean_water", 1, 2.0, 6, 2,
         "借炉火煮沸清水装入竹筒，随时解渴。"},
        {"cook_warm_tea", "冲泡江南清茶", "烹饪", "", 0, true, false, 200, "",
         "herb_bundle", 1, "clean_water", 1, "tea_cup", 2, 2.0, 8, 3,
         "以热沸水冲泡清茶两盏，提神醒脑。"},

        // --- 制药 (4) ---
        {"med_bandage", "炮制金创纱布", "制药", "medicine", 1, false, false, 0, "",
         "cloth_rag", 2, "herb_bundle", 1, "bandage", 2, 2.5, 16, 6,
         "将洁净碎布浸入止血草药汁，制成两卷金创纱布。"},
        {"med_salve", "调制跌打活血膏", "制药", "medicine", 4, false, false, 0, "",
         "herb_bundle", 2, "clay_bottle", 1, "trauma_salve", 1, 3.0, 22, 9,
         "捣药配伍装入青瓷小瓶，外敷可大幅回复六部位气血并止痛。"},
        {"med_qi_powder", "炼制培元行气散", "制药", "medicine", 8, true, false, 100, "",
         "herb_bundle", 3, "clay_bottle", 1, "qi_powder", 1, 3.5, 28, 12,
         "文火焙干三份草药研成细散，服之立复真气内力与耐力。"},
        {"med_rag_strip", "整修救急布带", "制药", "", 0, false, false, 0, "",
         "towel", 1, "", 0, "cloth_rag", 3, 1.8, 6, 2,
         "将棉布手巾撕成三条洁净碎布条以备包扎或制药。"},

        // --- 锻造 (4) ---
        {"smith_darts", "淬锻铁蒺藜飞镖", "锻造", "smithing", 1, false, true, 0, "",
         "ceramic_shard", 2, "wood_plank", 1, "iron_darts", 1, 2.8, 18, 8,
         "在铁匠铺风炉铁砧上锻打成形，适合基本暗器演练。"},
        {"smith_club", "打磨齐眉白蜡棍", "锻造", "smithing", 1, false, false, 0, "",
         "wood_plank", 2, "rope", 1, "waxwood_club", 1, 2.6, 16, 7,
         "精选木料削圆缠麻，制成趁手齐眉长棍。"},
        {"smith_sword", "锻造青锋铁剑", "锻造", "smithing", 6, false, true, 0, "",
         "cleaver", 1, "wood_plank", 1, "iron_sword", 1, 3.5, 26, 12,
         "熔锻废铁重铸三尺青锋，出鞘寒光凛冽。"},
        {"smith_blade", "锻造精钢柳叶刀", "锻造", "smithing", 6, false, true, 0, "",
         "hatchet", 1, "wood_plank", 1, "willow_blade", 1, 3.5, 26, 12,
         "回炉淬火改打单刃柳叶刀，劈斩沉猛。"},

        // --- 裁缝抄录 (4) ---
        {"copy_notes", "手抄武学心得", "裁缝抄录", "literate", 3, false, false, 0, "",
         "ink_paper", 1, "", 0, "martial_notes", 1, 2.5, 18, 8,
         "研墨抄录一卷修行心得，可供日后自阅悟潜能或赠予同道。"},
        {"sew_pouch", "缝制腰间荷包", "裁缝抄录", "", 0, false, false, 0, "",
         "cloth_rag", 3, "rope", 1, "pouch", 1, 2.5, 10, 4,
         "用棉布条与细绳缝成腰间荷包，扩充随身携物容积。"},
        {"sew_bag", "缝制青布行囊", "裁缝抄录", "", 0, false, false, 0, "",
         "cloth_rag", 5, "rope", 2, "cloth_bag", 1, 3.2, 14, 6,
         "拼缝厚实棉布与麻绳背带，大幅扩容至 14 升。"},
        {"make_tinder", "自制竹筒火折子", "裁缝抄录", "", 0, false, false, 0, "",
         "wood_plank", 1, "cloth_rag", 1, "tinderbox", 1, 2.0, 8, 3,
         "卷入引火布芯制成便携火折子，夜行照明无忧。"},
    }};
    return kRecipes;
}

int find_recipe_index(const char *id) {
    if (!id) return -1;
    const auto &cat = recipe_catalog();
    for (std::size_t i = 0; i < cat.size(); ++i) {
        if (std::strcmp(cat[i].id, id) == 0) return static_cast<int>(i);
    }
    return -1;
}

Dictionary check_can_craft(const RecipeDef &r, const ItemCounts &carried, int bottle_water_ml,
                           int wielded_id, const SkillSet &skills, const CraftEnv &env) {
    Dictionary res;
    res["ok"] = false;
    String reason;

    if (r.req_skill && r.req_skill[0] != '\0' && r.req_level > 0) {
        const int lv = skills.level_of(r.req_skill);
        if (lv < r.req_level) {
            const int bidx = find_base_skill_index(r.req_skill);
            const char *sname = bidx >= 0 ? base_skill_catalog()[static_cast<std::size_t>(bidx)].name : r.req_skill;
            reason = String::utf8("需要「") + String::utf8(sname) + String::utf8("」≥ ") + String::num_int64(r.req_level) + String::utf8(" 级");
            res["reason"] = reason;
            return res;
        }
    }
    if (r.need_hearth && !env.near_hearth) {
        res["reason"] = String::utf8("需靠近青砖炉灶（如醉仙楼/回春堂/民居灶台）");
        return res;
    }
    if (r.need_anvil && !env.near_anvil) {
        res["reason"] = String::utf8("需在王记铁匠铺锻造炉砧旁操作");
        return res;
    }
    if (r.need_water_ml > 0 && !env.near_water && bottle_water_ml < r.need_water_ml) {
        res["reason"] = String::utf8("缺少清水（需水壶 ≥ ") + String::num_int64(r.need_water_ml) + String::utf8("ml 或靠近水缸水盆）");
        return res;
    }
    if (r.tool_key && r.tool_key[0] != '\0' && !env.near_workshop) {
        const int tid = find_item_by_key(r.tool_key);
        const bool has_tool = (tid >= 0 && (carried[tid] > 0 || wielded_id == tid));
        if (!has_tool && tid >= 0) {
            res["reason"] = String::utf8("缺少器具「") + String::utf8(item_catalog()[tid].name) + String::utf8("」（或站在工坊旁免具）");
            return res;
        }
    }
    if (r.ing1_key && r.ing1_key[0] != '\0' && r.ing1_cnt > 0) {
        const int id1 = find_item_by_key(r.ing1_key);
        if (id1 < 0 || carried[id1] < r.ing1_cnt) {
            res["reason"] = String::utf8("材料不足：需「") + String::utf8(id1 >= 0 ? item_catalog()[id1].name : r.ing1_key) +
                            String::utf8("」×") + String::num_int64(r.ing1_cnt);
            return res;
        }
    }
    if (r.ing2_key && r.ing2_key[0] != '\0' && r.ing2_cnt > 0) {
        const int id2 = find_item_by_key(r.ing2_key);
        if (id2 < 0 || carried[id2] < r.ing2_cnt) {
            res["reason"] = String::utf8("材料不足：需「") + String::utf8(id2 >= 0 ? item_catalog()[id2].name : r.ing2_key) +
                            String::utf8("」×") + String::num_int64(r.ing2_cnt);
            return res;
        }
    }
    res["ok"] = true;
    res["reason"] = String();
    return res;
}

Array list_recipes_for_player(const ItemCounts &carried, int bottle_water_ml, int wielded_id,
                              const SkillSet &skills, const CraftEnv &env, const String &category_filter) {
    Array out;
    const std::string filt = category_filter.utf8().get_data();
    const auto &cat = item_catalog();
    for (const auto &r : recipe_catalog()) {
        if (!filt.empty() && filt != "all" && filt != "全部" && filt != r.category) continue;
        const Dictionary chk = check_can_craft(r, carried, bottle_water_ml, wielded_id, skills, env);
        Dictionary row;
        row["id"] = String::utf8(r.id);
        row["name"] = String::utf8(r.name);
        row["category"] = String::utf8(r.category);
        row["desc"] = String::utf8(r.desc);
        row["can_craft"] = static_cast<bool>(chk.get("ok", false));
        row["reason"] = chk.get("reason", String());
        const double dur = env.near_workshop ? (r.duration_sec * 0.72) : r.duration_sec;
        row["duration_sec"] = dur;
        String req_txt = String::utf8("无前置");
        if (r.req_skill && r.req_skill[0] != '\0' && r.req_level > 0) {
            const int bidx = find_base_skill_index(r.req_skill);
            req_txt = String::utf8(bidx >= 0 ? base_skill_catalog()[static_cast<std::size_t>(bidx)].name : r.req_skill) +
                      String::utf8(" ≥ ") + String::num_int64(r.req_level) + String::utf8("级");
        }
        row["req_label"] = req_txt;
        String ing_txt;
        if (r.ing1_key && r.ing1_key[0] != '\0') {
            const int i1 = find_item_by_key(r.ing1_key);
            if (i1 >= 0) ing_txt += String::utf8(cat[i1].name) + String::utf8("×") + String::num_int64(r.ing1_cnt) +
                                    String("(") + String::num_int64(carried[i1]) + String(")");
        }
        if (r.ing2_key && r.ing2_key[0] != '\0') {
            const int i2 = find_item_by_key(r.ing2_key);
            if (i2 >= 0) {
                if (!ing_txt.is_empty()) ing_txt += String::utf8(" + ");
                ing_txt += String::utf8(cat[i2].name) + String::utf8("×") + String::num_int64(r.ing2_cnt) +
                           String("(") + String::num_int64(carried[i2]) + String(")");
            }
        }
        if (r.need_water_ml > 0) {
            if (!ing_txt.is_empty()) ing_txt += String::utf8(" + ");
            ing_txt += String::utf8("清水 ") + String::num_int64(r.need_water_ml) + String("ml");
        }
        if (ing_txt.is_empty()) ing_txt = String::utf8("仅需设施/清水");
        row["ingredients"] = ing_txt;
        const int oid = find_item_by_key(r.out_key);
        row["output_label"] = (oid >= 0 ? String::utf8(cat[oid].name) : String::utf8(r.out_key)) +
                              String::utf8(" ×") + String::num_int64(r.out_cnt);
        out.append(row);
    }
    return out;
}

String execute_craft(const RecipeDef &r, ItemCounts &carried, int &bottle_water_ml, int wielded_id,
                     CharacterState &ch, SkillSet &skills, const CraftEnv &env) {
    const Dictionary chk = check_can_craft(r, carried, bottle_water_ml, wielded_id, skills, env);
    if (!static_cast<bool>(chk.get("ok", false))) {
        return chk.get("reason", String::utf8("制作条件未满足。"));
    }
    if (ch.is_starving_for_training()) {
        return String::utf8("你又饿又渴、精力难继，先吃些干粮喝口水再动手制作。");
    }
    const int oid = find_item_by_key(r.out_key);
    if (oid < 0) return String::utf8("未知产物。");

    if (r.ing1_key && r.ing1_key[0] != '\0' && r.ing1_cnt > 0) {
        const int i1 = find_item_by_key(r.ing1_key);
        if (i1 >= 0) carried[i1] -= r.ing1_cnt;
    }
    if (r.ing2_key && r.ing2_key[0] != '\0' && r.ing2_cnt > 0) {
        const int i2 = find_item_by_key(r.ing2_key);
        if (i2 >= 0) carried[i2] -= r.ing2_cnt;
    }
    if (r.need_water_ml > 0 && !env.near_water) {
        bottle_water_ml = std::max(0, bottle_water_ml - r.need_water_ml);
    }

    carried[oid] = std::min(999, carried[oid] + r.out_cnt);
    ch.spend_stamina(380);
    ch.kcal = std::max(0.0, ch.kcal - 18.0);
    ch.hydration = std::max(0.0, ch.hydration - 1.5);
    ch.morale = std::min(50, ch.morale + 3);
    const int pot = skills.add_potential(r.pot_gain);
    skills.add_combat_exp(4);

    String sk_note;
    if (r.req_skill && r.req_skill[0] != '\0') {
        const int bidx = find_base_skill_index(r.req_skill);
        if (bidx >= 0 && skills.base[static_cast<std::size_t>(bidx)].level > 0) {
            bool lv = false;
            skills.add_exp(bidx, r.skill_exp, lv);
            ch.sync_with_skills(skills);
            const char *sname = base_skill_catalog()[static_cast<std::size_t>(bidx)].name;
            sk_note = lv
                ? (String::utf8("，「") + String::utf8(sname) + String::utf8("」精进至 ") +
                   String::num_int64(skills.base[static_cast<std::size_t>(bidx)].level) + String::utf8(" 级"))
                : (String::utf8("，「") + String::utf8(sname) + String::utf8("」熟练度 +") + String::num_int64(r.skill_exp));
        }
    }
    return String::utf8("你亲手制成了「") + String::utf8(item_catalog()[oid].name) + String::utf8("」×") +
           String::num_int64(r.out_cnt) + String::utf8("，潜能 +") + String::num_int64(pot) + sk_note + String::utf8("！");
}

String dismantle_item_to_rags(int item_id, ItemCounts &carried, CharacterState &ch) {
    if (item_id < 0 || item_id >= kItemCount || carried[item_id] <= 0) {
        return String::utf8("行囊中没有这件物品。");
    }
    const auto &def = item_catalog()[item_id];
    const bool can_tear = (def.category == ItemCategory::Clothing || def.category == ItemCategory::Bedding ||
                           std::strcmp(def.key, "towel") == 0);
    if (!can_tear) {
        return String::utf8("「") + String::utf8(def.name) + String::utf8("」无法拆解为碎布条。");
    }
    const int rag_id = find_item_by_key("cloth_rag");
    if (rag_id < 0) return {};
    const int yield = (def.weight_g >= 700) ? 4 : (def.weight_g >= 300 ? 3 : 2);
    --carried[item_id];
    carried[rag_id] = std::min(999, carried[rag_id] + yield);
    ch.spend_stamina(180);
    return String::utf8("你将「") + String::utf8(def.name) + String::utf8("」拆解撕成 ") +
           String::num_int64(yield) + String::utf8(" 条碎布条（可用于包扎或制药）。");
}

} // namespace cangling
