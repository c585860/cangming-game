#include "skills.hpp"
#include <godot_cpp/variant/variant.hpp>
#include <algorithm>
#include <cmath>

namespace cangling {
using namespace godot;

const std::array<SkillRealmDef, kSkillRealmCount> &skill_realm_catalog() {
    static const std::array<SkillRealmDef, kSkillRealmCount> kRealms{{
        {SkillRealm::Wuxue,   "wuxue",   "武学", "江湖基础武学 · 市井谋生技艺 · 激发槽位",
         "包含二十门江湖基础技艺，开局皆为未入门，须拜访沧灵城中各路师傅消耗潜能请教习得。", true},
        {SkillRealm::Wudao,   "wudao",   "武道", "宗师意境 · 气血贯通 · 破境神通",
         "需基本内功、基本轻功与任意一门兵刃/拳脚臻至宗师境后方可叩开武道之门。", false},
        {SkillRealm::Lianqi,  "lianqi",  "练气", "纳灵入体 · 周天吐纳 · 筑基灵根",
         "待寻得灵脉机缘与吐纳法门后开启，引天地灵气洗髓易筋。", false},
        {SkillRealm::Xiandao, "xiandao", "仙道", "御剑乘风 · 法诀道术 · 大道法则",
         "渡劫踏虚之境，暂未开放。留待后续大世界篇章解锁。", false},
    }};
    return kRealms;
}

const std::array<SkillDef, kBaseSkillCount> &base_skill_catalog() {
    static const std::array<SkillDef, kBaseSkillCount> kSkills{{
        {"force",    "基本内功", SkillRealm::Wuxue, "内功心法",
         "调息吐纳、温养丹田之本。每级提升全身6部位血量上限(+3)、解锁真气内力上限(+25)与御寒回血之效。",
         "扬威武馆 · 陈馆主", true},
        {"dodge",    "基本轻功", SkillRealm::Wuxue, "身法轻功",
         "提纵腾挪、闪避来招之基。提升行走/奔跑移速并大幅降低奔跑与翻越障碍的耐力消耗。",
         "扬威武馆 · 陈馆主 / 水埠码头 · 老船夫", true},
        {"parry",    "基本招架", SkillRealm::Wuxue, "护体招架",
         "格挡卸力、以柔克刚之法。提升全身护体气血根基，可激发各派招式化解敌袭。",
         "扬威武馆 · 陈馆主", true},
        {"unarmed",  "基本拳脚", SkillRealm::Wuxue, "空手外功",
         "徒手搏击与下盘稳固之根基。增强徒手破障威力与全身气血，亦可解锁水埠码头漕运工位。",
         "扬威武馆 · 陈馆主 / 水埠码头 · 老船夫", true},
        {"strike",   "基本掌法", SkillRealm::Wuxue, "空手外功",
         "吐劲发掌、绵密浑厚，掌风起处刚柔并济，适合激发各派掌法绝学。",
         "扬威武馆 · 陈馆主", true},
        {"cuff",     "基本拳法", SkillRealm::Wuxue, "空手外功",
         "冲捶崩拳、寸劲发力，出拳沉雄刚猛，重在贴身破架。",
         "扬威武馆 · 陈馆主", true},
        {"finger",   "基本指法", SkillRealm::Wuxue, "空手外功",
         "凝劲于指、凌空点穴，专攻要害经脉，精微凌厉。",
         "扬威武馆 · 陈馆主", true},
        {"claw",     "基本爪法", SkillRealm::Wuxue, "空手外功",
         "擒拿分筋、错骨锁脉，招式刁钻迅捷，克制轻灵身法。",
         "扬威武馆 · 陈馆主", true},
        {"hand",     "基本手法", SkillRealm::Wuxue, "空手外功",
         "拆招拿腕、借力打力，讲求顺势化劲与近身擒控。",
         "扬威武馆 · 陈馆主", true},
        {"sword",    "基本剑法", SkillRealm::Wuxue, "兵刃外功",
         "点刺挑劈、轻灵飘逸，剑走轻锋，江湖名门正派最重之艺。",
         "扬威武馆 · 周教头", true},
        {"blade",    "基本刀法", SkillRealm::Wuxue, "兵刃外功",
         "劈砍剁削、大开大合，刀势沉猛霸道，短兵交接最易占先。",
         "扬威武馆 · 周教头 / 王记铁匠铺 · 王铁匠", true},
        {"staff",    "基本杖法", SkillRealm::Wuxue, "兵刃外功",
         "扫砸挑拨、势大力沉，兼有长兵之威与镇岳之势。",
         "扬威武馆 · 周教头", true},
        {"club",     "基本棍法", SkillRealm::Wuxue, "兵刃外功",
         "崩点扫劈、进退有度，横扫一片，攻守兼备。",
         "扬威武馆 · 周教头 / 王记铁匠铺 · 王铁匠", true},
        {"spear",    "基本枪法", SkillRealm::Wuxue, "兵刃外功",
         "扎拦拿挑、游龙出海，百兵之王，一寸长一寸强。",
         "扬威武馆 · 周教头", true},
        {"whip",     "基本鞭法", SkillRealm::Wuxue, "兵刃外功",
         "抽缠抖卷、软硬相生，长短兼备而变幻奇诡。",
         "扬威武馆 · 周教头", true},
        {"throwing", "基本暗器", SkillRealm::Wuxue, "远程绝技",
         "听声辨位、袖箭飞蝗，先发制人于数丈之外。",
         "扬威武馆 · 周教头", true},
        {"literate", "读书写字", SkillRealm::Wuxue, "文雅杂学",
         "识文断字、明理通义。每级提升全技能潜能学习效率(+4%)，解锁文昌书院与当铺钱庄工位。",
         "文昌书院 · 顾夫子 / 利源当铺 · 唐掌柜", false},
        {"medicine", "基本药学", SkillRealm::Wuxue, "市井谋生",
         "识草辨药、炮制切脉。每级提升包扎疗伤效果(+5%)，解锁回春堂药坊全部工位。",
         "回春堂药铺 · 平大夫", false},
        {"cooking",  "基本厨艺", SkillRealm::Wuxue, "市井谋生",
         "掌勺火候、调鼎烹鲜。每级提升饮食饱食与心境收益(+2%)，解锁醉仙楼后厨全部工位。",
         "醉仙楼 · 冼老板", false},
        {"smithing", "基本锻造", SkillRealm::Wuxue, "市井谋生",
         "拉风淬火、百炼打铁。解锁王记铁匠铺全部锻造工位，亦是日后打造修缮神兵之本。",
         "王记铁匠铺 · 王铁匠", false},
    }};
    return kSkills;
}

int find_base_skill_index(const std::string &id) {
    const auto &cat = base_skill_catalog();
    for (std::size_t i = 0; i < cat.size(); ++i) {
        if (id == cat[i].id) return static_cast<int>(i);
    }
    return -1;
}

const char *skill_rank_title(int level) {
    if (level <= 0) return "未入门";
    if (level < 10) return "初学乍练";
    if (level < 20) return "粗通皮毛";
    if (level < 35) return "半生不熟";
    if (level < 50) return "马马虎虎";
    if (level < 70) return "驾轻就熟";
    if (level < 95) return "出类拔萃";
    if (level < 125) return "神乎其技";
    if (level < 160) return "出神入化";
    if (level < 200) return "登峰造极";
    if (level < 260) return "深不可测";
    return "返璞归真";
}

int skill_exp_to_next(int level) {
    const int lv = std::max(0, level) + 1;
    return lv * lv * 10;
}

void SkillSet::reset_defaults() {
    // Authentic Wuxia MUD zero-start: ALL 20 skills begin at Lv.0 (unlearned)!
    for (std::size_t i = 0; i < kBaseSkillCount; ++i) {
        base[i].level = 0;
        base[i].exp = 0;
        base[i].enabled_art.clear();
    }
    potential = 30;
    combat_exp = 0;
}

int SkillSet::level_of(const std::string &id) const {
    const int idx = find_base_skill_index(id);
    if (idx < 0) return 0;
    return base[static_cast<std::size_t>(idx)].level;
}

int SkillSet::total_levels() const {
    int sum = 0;
    for (const auto &st : base) sum += st.level;
    return sum;
}

int SkillSet::learned_count() const {
    int c = 0;
    for (const auto &st : base) if (st.level > 0) ++c;
    return c;
}

bool SkillSet::has_any_martial_skill() const {
    // First 16 skills are martial arts (force..throwing)
    for (std::size_t i = 0; i < 16 && i < kBaseSkillCount; ++i) {
        if (base[i].level > 0) return true;
    }
    return false;
}

int SkillSet::potential_cap() const {
    return 200 + combat_exp / 2 + total_levels() * 12;
}

int SkillSet::add_potential(int amount) {
    if (amount <= 0) return 0;
    const int cap = potential_cap();
    const int before = potential;
    potential = std::min(cap, potential + amount);
    return potential - before;
}

bool SkillSet::spend_potential(int amount) {
    if (amount <= 0) return true;
    if (potential < amount) return false;
    potential -= amount;
    return true;
}

void SkillSet::add_combat_exp(int amount) {
    if (amount > 0) combat_exp = std::min(1000000000, combat_exp + amount);
}

int SkillSet::learn_potential_cost(int skill_idx) const {
    if (skill_idx < 0 || skill_idx >= static_cast<int>(kBaseSkillCount)) return 10;
    const int lv = base[static_cast<std::size_t>(skill_idx)].level;
    if (lv == 0) return 10; // Clean starter unlock cost!
    return 8 + lv / 2;
}

int SkillSet::learn_coin_cost(int skill_idx) const {
    if (skill_idx < 0 || skill_idx >= static_cast<int>(kBaseSkillCount)) return 2;
    const int lv = base[static_cast<std::size_t>(skill_idx)].level;
    return lv == 0 ? 3 : 2;
}

int SkillSet::learn_exp_gain(int stat_int) const {
    const int lit = level_of("literate");
    const double raw = (12.0 + static_cast<double>(stat_int) * 1.2) * (1.0 + 0.04 * static_cast<double>(lit));
    return std::max(10, static_cast<int>(std::floor(raw)));
}

int SkillSet::research_potential_cost(int skill_idx) const {
    if (skill_idx < 0 || skill_idx >= static_cast<int>(kBaseSkillCount)) return 30;
    const int lv = base[static_cast<std::size_t>(skill_idx)].level;
    return std::max(24, 18 + lv / 10);
}

int SkillSet::research_exp_gain(int stat_int) const {
    const int lit = level_of("literate");
    const double raw = (24.0 + static_cast<double>(stat_int) * 2.2) * (1.0 + 0.04 * static_cast<double>(lit));
    return std::max(20, static_cast<int>(std::floor(raw)));
}

bool SkillSet::add_exp(int skill_idx, int amount, bool &leveled_up) {
    leveled_up = false;
    if (skill_idx < 0 || skill_idx >= static_cast<int>(kBaseSkillCount) || amount <= 0) return false;
    auto &st = base[static_cast<std::size_t>(skill_idx)];
    st.exp += amount;
    while (st.level < 999) {
        const int need = skill_exp_to_next(st.level);
        if (st.exp < need) break;
        st.exp -= need;
        st.level += 1;
        leveled_up = true;
    }
    return true;
}

bool SkillSet::set_jifa(int skill_idx, const std::string &special_art_id) {
    if (skill_idx < 0 || skill_idx >= static_cast<int>(kBaseSkillCount)) return false;
    if (!base_skill_catalog()[static_cast<std::size_t>(skill_idx)].supports_jifa) return false;
    base[static_cast<std::size_t>(skill_idx)].enabled_art = special_art_id;
    return true;
}

Array SkillSet::realms_to_array() const {
    Array out;
    const int learned = learned_count();
    const int total_lv = total_levels();
    for (const auto &r : skill_realm_catalog()) {
        Dictionary d;
        d["id"] = String::utf8(r.id);
        d["name"] = String::utf8(r.name);
        d["subtitle"] = String::utf8(r.subtitle);
        d["unlock_hint"] = String::utf8(r.unlock_hint);
        d["unlocked"] = r.unlocked;
        d["skill_count"] = r.realm == SkillRealm::Wuxue ? static_cast<int>(kBaseSkillCount) : 0;
        d["learned_count"] = r.realm == SkillRealm::Wuxue ? learned : 0;
        d["total_level"] = r.realm == SkillRealm::Wuxue ? total_lv : 0;
        out.append(d);
    }
    return out;
}

Array SkillSet::skills_to_array(const String &realm_filter) const {
    Array out;
    const std::string filt = realm_filter.utf8().get_data();
    const auto &cat = base_skill_catalog();
    const auto &realms = skill_realm_catalog();
    for (std::size_t i = 0; i < kBaseSkillCount; ++i) {
        const auto &st = base[i];
        if (st.level <= 0) continue; // Classic MUD rule: unlearned skills do NOT appear on panel!
        const auto &def = cat[i];
        const char *rid = realms[static_cast<std::size_t>(def.realm)].id;
        if (!filt.empty() && filt != "all" && filt != rid) continue;
        const int need = skill_exp_to_next(st.level);
        Dictionary row;
        row["index"] = static_cast<int>(i);
        row["id"] = String::utf8(def.id);
        row["name"] = String::utf8(def.name);
        row["realm"] = String::utf8(rid);
        row["realm_name"] = String::utf8(realms[static_cast<std::size_t>(def.realm)].name);
        row["category"] = String::utf8(def.category);
        row["desc"] = String::utf8(def.desc);
        row["mentor_hint"] = String::utf8(def.mentor_hint);
        row["level"] = st.level;
        row["exp"] = st.exp;
        row["exp_next"] = need;
        row["progress"] = need > 0 ? static_cast<double>(st.exp) / static_cast<double>(need) : 0.0;
        row["rank"] = String::utf8(skill_rank_title(st.level));
        row["supports_jifa"] = def.supports_jifa;
        row["jifa"] = String::utf8(st.enabled_art.c_str());
        row["can_research"] = st.level >= kResearchMinLevel;
        row["research_pot_cost"] = research_potential_cost(static_cast<int>(i));
        out.append(row);
    }
    return out;
}

Dictionary SkillSet::summary_dict() const {
    int max_lv = 0;
    const char *top_name = "初入江湖";
    const auto &cat = base_skill_catalog();
    for (std::size_t i = 0; i < kBaseSkillCount; ++i) {
        if (base[i].level > max_lv) {
            max_lv = base[i].level;
            top_name = cat[i].name;
        }
    }
    Dictionary out;
    out["learned"] = learned_count();
    out["total_skills"] = static_cast<int>(kBaseSkillCount);
    out["total_level"] = total_levels();
    out["highest_level"] = max_lv;
    out["highest_skill"] = String::utf8(top_name);
    out["overall_rank"] = String::utf8(max_lv > 0 ? skill_rank_title(max_lv) : "初入江湖");
    out["potential"] = potential;
    out["potential_cap"] = potential_cap();
    out["combat_exp"] = combat_exp;
    return out;
}

Dictionary SkillSet::save_dict() const {
    Dictionary out;
    out["potential"] = potential;
    out["combat_exp"] = combat_exp;
    Dictionary map;
    const auto &cat = base_skill_catalog();
    for (std::size_t i = 0; i < kBaseSkillCount; ++i) {
        Dictionary entry;
        entry["level"] = base[i].level;
        entry["exp"] = base[i].exp;
        if (!base[i].enabled_art.empty()) {
            entry["jifa"] = String::utf8(base[i].enabled_art.c_str());
        }
        map[String::utf8(cat[i].id)] = entry;
    }
    out["entries"] = map;
    return out;
}

void SkillSet::load_dict(const Dictionary &d) {
    reset_defaults();
    if (d.has("potential")) potential = std::max(0, static_cast<int>(d["potential"]));
    if (d.has("combat_exp")) combat_exp = std::max(0, static_cast<int>(d["combat_exp"]));
    const Dictionary map = d.get("entries", Variant()).get_type() == Variant::DICTIONARY ? Dictionary(d["entries"]) : d;
    const auto &cat = base_skill_catalog();
    for (std::size_t i = 0; i < kBaseSkillCount; ++i) {
        const String k = String::utf8(cat[i].id);
        if (!map.has(k)) continue;
        const Variant v = map[k];
        if (v.get_type() != Variant::DICTIONARY) continue;
        const Dictionary entry = v;
        base[i].level = std::clamp(static_cast<int>(entry.get("level", 0)), 0, 999);
        base[i].exp = std::max(0, static_cast<int>(entry.get("exp", 0)));
        const String j = entry.get("jifa", String());
        base[i].enabled_art = j.utf8().get_data();
    }
}

} // namespace cangling
