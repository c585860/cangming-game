#include "workstations.hpp"
#include <godot_cpp/variant/variant.hpp>
#include <algorithm>
#include <cmath>
#include <cstring>

namespace cangling {
using namespace godot;

const std::array<WorkstationDef, kWorkstationCount> &workstation_catalog() {
    static const std::array<WorkstationDef, kWorkstationCount> kStations{{
        // 1. 醉仙楼后厨工坊 (4 stations — requires 基本厨艺 cooking >= 1)
        {"zx_wok_main",  "醉仙楼·主灶炒锅", "醉仙楼", {129, 154}, "cooking", "", 1,
         "醉仙楼「冼老板」", "掌勺烹炒招牌菜肴", "cooking", 9, 18, 12, 16, 35.0, 3.0, 600, 2.5, false},
        {"zx_wok_stew",  "醉仙楼·副灶炖炉", "醉仙楼", {129, 155}, "cooking", "", 1,
         "醉仙楼「冼老板」", "文火煨炖高汤药膳", "cooking", 9, 18, 12, 16, 32.0, 2.8, 560, 2.5, false},
        {"zx_chop",      "醉仙楼·切菜案板", "醉仙楼", {127, 155}, "cooking", "", 1,
         "醉仙楼「冼老板」", "切配鲜蔬与江南河鲜", "cooking", 8, 16, 10, 15, 28.0, 2.5, 500, 2.5, false},
        {"zx_steamer",   "醉仙楼·温酒蒸笼案", "醉仙楼", {127, 158}, "cooking", "", 1,
         "醉仙楼「冼老板」", "温黄酒蒸蟹粉小笼", "cooking", 8, 17, 11, 15, 30.0, 2.5, 520, 2.5, false},

        // 2. 回春堂药坊 (4 stations — requires 基本药学 medicine >= 1)
        {"hc_sort",      "回春堂·百子分拣柜", "回春堂药铺", {128, 111}, "medicine", "", 1,
         "回春堂「平大夫」", "分拣炮制百草药材", "medicine", 10, 20, 12, 16, 28.0, 2.6, 520, 2.5, false},
        {"hc_grind",     "回春堂·捣药研磨台", "回春堂药铺", {132, 111}, "medicine", "", 1,
         "回春堂「平大夫」", "研杵捣碎金创药粉", "medicine", 10, 20, 12, 16, 32.0, 2.8, 560, 2.5, false},
        {"hc_desk",      "回春堂·切药配伍案", "回春堂药铺", {129, 114}, "medicine", "", 1,
         "回春堂「平大夫」", "按方称量君臣佐使", "medicine", 10, 21, 13, 17, 26.0, 2.4, 480, 2.5, false},
        {"hc_hearth",    "回春堂·文火煎药炉", "回春堂药铺", {127, 115}, "medicine", "", 1,
         "回春堂「平大夫」", "看火煎熬滋补汤剂", "medicine", 11, 21, 13, 17, 30.0, 3.0, 540, 2.5, false},

        // 3. 王记铁匠铺锻造坊 (4 stations — requires 基本锻造 smithing >= 1)
        {"wj_forge_n",   "王记铁匠铺·北锻风炉", "王记铁匠铺", {114, 153}, "smithing", "", 1,
         "王记铁匠铺「王铁匠」", "拉动风箱旺火烧坯", "smithing", 13, 24, 16, 18, 52.0, 4.8, 900, 2.5, false},
        {"wj_forge_s",   "王记铁匠铺·南熔铁炉", "王记铁匠铺", {114, 160}, "smithing", "", 1,
         "王记铁匠铺「王铁匠」", "添炭熔炼精铁生坯", "smithing", 13, 24, 16, 18, 52.0, 4.8, 900, 2.5, false},
        {"wj_quench",    "王记铁匠铺·淬火水槽", "王记铁匠铺", {115, 153}, "smithing", "", 1,
         "王记铁匠铺「王铁匠」", "给通红铁坯蘸水淬火", "smithing", 12, 22, 15, 17, 45.0, 4.2, 820, 2.5, false},
        {"wj_anvil",     "王记铁匠铺·锻铁铁砧", "王记铁匠铺", {113, 156}, "smithing", "", 1,
         "王记铁匠铺「王铁匠」", "抡锤锻打刀剑铁坯", "smithing", 14, 26, 18, 19, 58.0, 5.2, 960, 2.5, false},

        // 4. 文昌书院抄经坊 (4 stations — requires 读书写字 literate >= 1)
        {"wc_desk_w",    "文昌书院·抄书案几(西)", "文昌书院", {129, 90}, "literate", "", 1,
         "文昌书院「顾夫子」", "提笔誊抄经史典籍", "literate", 9, 22, 12, 18, 24.0, 2.2, 420, 2.5, false},
        {"wc_desk_e",    "文昌书院·抄书案几(东)", "文昌书院", {133, 90}, "literate", "", 1,
         "文昌书院「顾夫子」", "研墨校勘江湖风物志", "literate", 9, 22, 12, 18, 24.0, 2.2, 420, 2.5, false},
        {"wc_shelf_w",   "文昌书院·藏书修补架(西)", "文昌书院", {128, 86}, "literate", "", 1,
         "文昌书院「顾夫子」", "整理装订线装古籍", "literate", 8, 20, 11, 16, 22.0, 2.0, 400, 2.5, false},
        {"wc_shelf_e",   "文昌书院·藏书修补架(东)", "文昌书院", {132, 86}, "literate", "", 1,
         "文昌书院「顾夫子」", "编目归档书院藏卷", "literate", 8, 20, 11, 16, 22.0, 2.0, 400, 2.5, false},

        // 5. 扬威武馆演武场 (4 stations — requires any_martial >= 1; also boosts practice +35%!)
        {"yw_dummy_n",   "扬威武馆·北木人桩", "扬威武馆", {98, 124}, "any_martial", "", 1,
         "扬威武馆「陈馆主 / 周教头」", "在木人桩旁助教演武", "best_martial", 10, 25, 18, 18, 44.0, 4.0, 760, 2.5, true},
        {"yw_dummy_s",   "扬威武馆·南木人桩", "扬威武馆", {98, 129}, "any_martial", "", 1,
         "扬威武馆「陈馆主 / 周教头」", "敲打木人桩校对桩法", "best_martial", 10, 25, 18, 18, 44.0, 4.0, 760, 2.5, true},
        {"yw_weapons",   "扬威武馆·兵器演武架", "扬威武馆", {105, 124}, "any_martial", "", 1,
         "扬威武馆「周教头」", "擦拭保养十八般兵器", "best_martial", 11, 24, 17, 17, 40.0, 3.6, 700, 2.5, true},
        {"yw_manual",    "扬威武馆·武谱石案", "扬威武馆", {105, 128}, "any_martial", "", 1,
         "扬威武馆「陈馆主 / 周教头」", "整理拆解武馆桩功图谱", "best_martial", 10, 26, 16, 18, 34.0, 3.0, 620, 2.5, true},

        // 6. 水埠码头漕运区 (4 stations — requires 基本拳脚 unarmed >= 1 OR 基本内功 force >= 1)
        {"dk_crate_n",   "水埠码头·北漕运货箱", "水埠码头", {166, 163}, "unarmed", "force", 1,
         "水埠码头「老船夫」或扬威武馆「陈馆主」", "扛运清点北岸漕运货箱", "unarmed", 13, 22, 16, 16, 52.0, 4.8, 900, 2.5, false},
        {"dk_crate_e",   "水埠码头·东过秤货垛", "水埠码头", {168, 163}, "unarmed", "force", 1,
         "水埠码头「老船夫」或扬威武馆「陈馆主」", "搬货过秤码齐货垛", "unarmed", 13, 22, 16, 16, 52.0, 4.8, 900, 2.5, false},
        {"dk_vat",       "水埠码头·水栈货缸", "水埠码头", {166, 169}, "unarmed", "force", 1,
         "水埠码头「老船夫」或扬威武馆「陈馆主」", "给漕船备装淡水与酒坛", "force", 12, 21, 15, 15, 46.0, 4.2, 820, 2.5, false},
        {"dk_pier",      "水埠码头·临水卸货栈桥", "水埠码头", {164, 166}, "unarmed", "force", 1,
         "水埠码头「老船夫」或扬威武馆「陈馆主」", "牵缆稳舟装卸河运货包", "dodge", 13, 23, 16, 16, 50.0, 4.6, 860, 2.5, false},

        // 7. 利源当铺 & 通济钱庄 (4 stations — requires 读书写字 literate >= 1)
        {"ly_abacus",    "利源当铺·算盘账台", "利源当铺", {115, 128}, "literate", "", 1,
         "文昌书院「顾夫子」或利源当铺「唐掌柜」", "拨打算盘核对典当流水", "literate", 11, 20, 13, 16, 28.0, 2.5, 480, 2.5, false},
        {"ly_vault",     "利源当铺·库房验货箱", "利源当铺", {111, 132}, "literate", "", 1,
         "文昌书院「顾夫子」或利源当铺「唐掌柜」", "查验造册封存典当物件", "literate", 11, 20, 13, 16, 30.0, 2.6, 520, 2.5, false},
        {"tj_counter",   "通济钱庄·点银算账台", "通济钱庄", {138, 113}, "literate", "", 1,
         "文昌书院「顾夫子」或利源当铺「唐掌柜」", "验秤纹银核对银票存根", "literate", 12, 21, 14, 16, 28.0, 2.5, 480, 2.5, false},
        {"tj_chest",     "通济钱庄·银库封箱台", "通济钱庄", {137, 111}, "literate", "", 1,
         "文昌书院「顾夫子」或利源当铺「唐掌柜」", "清点银锭贴封条入库", "literate", 12, 21, 14, 16, 30.0, 2.6, 520, 2.5, false},
    }};
    return kStations;
}

const WorkstationDef *workstation_at_tile(Vector2i p) {
    for (const auto &ws : workstation_catalog()) {
        if (ws.pos == p) return &ws;
    }
    return nullptr;
}

bool near_martial_training_station(Vector2i player_pos) {
    for (const auto &ws : workstation_catalog()) {
        if (!ws.martial_bonus_station) continue;
        const Vector2i d = (player_pos - ws.pos).abs();
        if (std::max(d.x, d.y) <= 2) return true;
    }
    return false;
}

bool skill_meets_station_req(const SkillSet &skills, const WorkstationDef &ws) {
    if (std::strcmp(ws.req_skill, "any_martial") == 0) {
        return skills.has_any_martial_skill();
    }
    if (skills.level_of(ws.req_skill) >= ws.req_level) return true;
    if (ws.alt_skill && ws.alt_skill[0] != '\0' && skills.level_of(ws.alt_skill) >= ws.req_level) return true;
    return false;
}

Dictionary workstation_to_dict(const WorkstationDef &ws, const SkillSet &skills) {
    Dictionary d;
    d["id"] = String::utf8(ws.id);
    d["name"] = String::utf8(ws.name);
    d["district"] = String::utf8(ws.district);
    d["pos"] = ws.pos;
    d["req_skill"] = String::utf8(ws.req_skill);
    d["alt_skill"] = String::utf8(ws.alt_skill);
    d["req_level"] = ws.req_level;
    String req_label;
    if (std::strcmp(ws.req_skill, "any_martial") == 0) {
        req_label = String::utf8("任意基础武学 ≥ 1级");
    } else {
        const int ridx = find_base_skill_index(ws.req_skill);
        req_label = ridx >= 0 ? String::utf8(base_skill_catalog()[static_cast<std::size_t>(ridx)].name) : String::utf8(ws.req_skill);
        if (ws.alt_skill && ws.alt_skill[0] != '\0') {
            const int aidx = find_base_skill_index(ws.alt_skill);
            if (aidx >= 0) {
                req_label += String::utf8(" 或 ") + String::utf8(base_skill_catalog()[static_cast<std::size_t>(aidx)].name);
            }
        }
        req_label += String::utf8(" ≥ ") + String::num_int64(ws.req_level) + String::utf8("级");
    }
    d["req_label"] = req_label;
    d["mentor_hint"] = String::utf8(ws.mentor_hint);
    d["action_verb"] = String::utf8(ws.action_verb);
    d["coin_pay"] = ws.coin_pay;
    d["pot_gain"] = ws.pot_gain;
    d["combat_exp_gain"] = ws.combat_exp_gain;
    d["kcal_cost"] = static_cast<int>(std::round(ws.kcal_cost));
    d["stamina_cost"] = ws.stamina_cost;
    d["duration_sec"] = ws.duration_sec;
    d["martial_bonus_station"] = ws.martial_bonus_station;
    d["unlocked"] = skill_meets_station_req(skills, ws);
    return d;
}

const std::vector<MasterTeachSpec> &master_teach_catalog() {
    static const std::vector<MasterTeachSpec> kTeach{
        // 醉仙楼 · 冼老板
        {"innkeeper",      "cooking",  30},
        // 王记铁匠铺 · 王铁匠
        {"blacksmith",     "smithing", 30},
        {"blacksmith",     "blade",    15},
        {"blacksmith",     "club",     15},
        // 回春堂药铺 · 平大夫
        {"herbalist",      "medicine", 30},
        // 扬威武馆 · 陈馆主 (内轻招架 + 空手六艺)
        {"martial_master", "force",    30},
        {"martial_master", "dodge",    30},
        {"martial_master", "parry",    30},
        {"martial_master", "unarmed",  30},
        {"martial_master", "strike",   30},
        {"martial_master", "cuff",     30},
        {"martial_master", "finger",   30},
        {"martial_master", "claw",     30},
        {"martial_master", "hand",     30},
        // 扬威武馆兵器堂 · 周教头 (兵刃六艺 + 基本暗器)
        {"weapon_coach",   "sword",    30},
        {"weapon_coach",   "blade",    30},
        {"weapon_coach",   "staff",    30},
        {"weapon_coach",   "club",     30},
        {"weapon_coach",   "spear",    30},
        {"weapon_coach",   "whip",     30},
        {"weapon_coach",   "throwing", 30},
        // 文昌书院 · 顾夫子
        {"scholar",        "literate", 30},
        // 利源当铺 · 唐掌柜 (账房识字启蒙)
        {"pawnbroker",     "literate", 10},
        // 水埠码头 · 老船夫 (码头稳步启蒙)
        {"boatman",        "unarmed",  10},
        {"boatman",        "dodge",    10},
        // 春风茶馆 · 说书先生 (评书说文启蒙)
        {"storyteller",    "literate", 10},
    };
    return kTeach;
}

} // namespace cangling
