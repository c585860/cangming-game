#include "skills.hpp"
#include <godot_cpp/variant/variant.hpp>
#include <algorithm>
#include <cmath>

namespace cangling {
using namespace godot;

const std::array<SkillRealmDef, kSkillRealmCount> &skill_realm_catalog() {
    static const std::array<SkillRealmDef, kSkillRealmCount> kRealms{{
        {SkillRealm::Wuxue,   "wuxue",   "武学", "江湖基础武学 · 市井谋生技艺 · 激发槽位",
         "包含二十门江湖基础技艺与沧灵城入门特殊武功，开局皆为未入门，须拜访师傅消耗潜能请教习得。", true},
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
         "调息吐纳、温养丹田之本。每级提升全身6部位血量上限(+3)、解锁真气内力上限(+25)与打坐运功之效。",
         "扬威武馆 · 陈馆主", true},
        {"dodge",    "基本轻功", SkillRealm::Wuxue, "身法轻功",
         "提纵腾挪、闪避来招之基。提升行走/奔跑移速、切磋闪避率，并大幅降低奔跑与翻越障碍的耐力消耗。",
         "扬威武馆 · 陈馆主 / 水埠码头 · 老船夫", true},
        {"parry",    "基本招架", SkillRealm::Wuxue, "护体招架",
         "格挡卸力、以柔克刚之法。提升全身护体气血根基与切磋招架减伤，可激发特殊招架绝学。",
         "扬威武馆 · 陈馆主", true},
        {"unarmed",  "基本拳脚", SkillRealm::Wuxue, "空手外功",
         "徒手搏击与下盘稳固之根基。增强徒手威力与全身气血，亦可解锁水埠码头漕运工位。",
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
         "识文断字、明理通义。每级提升全技能潜能请教效率(+4%)，解锁高阶典籍研读与书院/当铺/钱庄工位。",
         "文昌书院 · 顾夫子 / 利源当铺 · 唐掌柜", false},
        {"medicine", "基本药学", SkillRealm::Wuxue, "市井谋生",
         "识草辨药、炮制切脉。每级提升包扎疗伤效果(+5%)，解锁回春堂药坊工位与制药配方。",
         "回春堂药铺 · 平大夫", false},
        {"cooking",  "基本厨艺", SkillRealm::Wuxue, "市井谋生",
         "掌勺火候、调鼎烹鲜。每级提升饮食饱食与心境收益(+2%)，解锁醉仙楼后厨工位与热食烹饪。",
         "醉仙楼 · 冼老板", false},
        {"smithing", "基本锻造", SkillRealm::Wuxue, "市井谋生",
         "拉风淬火、百炼打铁。解锁王记铁匠铺锻造工位，亦是打造兵刃与修缮器具之本。",
         "王记铁匠铺 · 王铁匠", false},
    }};
    return kSkills;
}

const std::array<SpecialArtDef, kSpecialArtCount> &special_art_catalog() {
    static const std::array<SpecialArtDef, kSpecialArtCount> kArts{{
        {"yangwei_force", "扬威吐纳功", "force", "martial_master", 10, 30,
         "扬威武馆镇馆入门心法，激发后显著提升打坐真气凝聚速度与运功疗伤之效。",
         {"气沉丹田", "吐纳周天", "潜龙归元"}},
        {"tabo_dodge", "小秦淮踏波步", "dodge", "martial_master", 10, 30,
         "仿江南画舫踏水借力的轻身步法，激发后行步更迅、切磋闪避倍增。",
         {"燕掠画桥", "踏波折柳", "惊鸿照影"}},
        {"tiebi_parry", "铁壁化劲架", "parry", "martial_master", 10, 30,
         "借力卸劲的护体架子功，激发后切磋格挡率与卸力减伤大幅提升。",
         {"沉肘封门", "铁锁横江", "四两拨千斤"}},
        {"changquan", "长拳十路", "unarmed", "martial_master", 10, 30,
         "江湖流传最广的入门套路，起落分明、刚劲利落，最宜初涉武林者立身。",
         {"白鹤亮翅", "黑虎掏心", "二郎担山"}},
        {"taizu_palm", "太祖绵掌", "strike", "martial_master", 10, 30,
         "外柔内刚的入门掌法，掌力绵密透骨，最擅连环进逼。",
         {"推窗望月", "云手翻浪", "排山倒海"}},
        {"qingshuang_sword", "青霜基础剑", "sword", "weapon_coach", 10, 30,
         "寒锋轻灵的江南入门剑法，招式清雅绵密，点刺之间暗藏杀机。",
         {"青霜映雪", "孤舟钓月", "寒梅点露"}},
        {"duanshui_blade", "断水三刀", "blade", "weapon_coach", 10, 30,
         "沉猛利落的入门快刀，借腰身蓄劲顺势劈斩，势若抽刀断水。",
         {"抽刀断水", "横江截浪", "力劈华山"}},
        {"yangjia_spear", "杨家基础枪", "spear", "weapon_coach", 10, 30,
         "中平枪势、扎拦拿挑井然有度，枪出如龙，攻守皆占先机。",
         {"灵蛇吐信", "回马挑灯", "游龙出海"}},
    }};
    return kArts;
}

int find_base_skill_index(const std::string &id) {
    const auto &cat = base_skill_catalog();
    for (std::size_t i = 0; i < cat.size(); ++i) {
        if (id == cat[i].id) return static_cast<int>(i);
    }
    return -1;
}

int find_special_art_index(const std::string &id) {
    const auto &cat = special_art_catalog();
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

const char *jianghu_title(int total_levels, int combat_exp, int reputation) {
    const int score = total_levels * 4 + combat_exp / 8 + reputation * 6;
    if (score < 20) return "初出茅庐";
    if (score < 80) return "初涉江湖";
    if (score < 220) return "略有所成";
    if (score < 480) return "沧灵少侠";
    if (score < 900) return "声名鹊起";
    if (score < 1600) return "江南名侠";
    return "一代宗师";
}

int skill_exp_to_next(int level) {
    const int lv = std::max(0, level) + 1;
    return lv * lv * 10;
}

void SkillSet::reset_defaults() {
    // Authentic Wuxia MUD zero-start: ALL 20 base skills and 8 special arts begin at Lv.0!
    for (std::size_t i = 0; i < kBaseSkillCount; ++i) {
        base[i].level = 0;
        base[i].exp = 0;
        base[i].enabled_art.clear();
    }
    for (std::size_t i = 0; i < kSpecialArtCount; ++i) {
        special[i].level = 0;
        special[i].exp = 0;
        special[i].enabled_art.clear();
    }
    potential = 30;
    combat_exp = 0;
}

int SkillSet::level_of(const std::string &id) const {
    const int idx = find_base_skill_index(id);
    return idx >= 0 ? base[static_cast<std::size_t>(idx)].level : 0;
}

int SkillSet::special_level_of(const std::string &id) const {
    const int idx = find_special_art_index(id);
    return idx >= 0 ? special[static_cast<std::size_t>(idx)].level : 0;
}

int SkillSet::effective_level_of(const std::string &base_id) const {
    const int idx = find_base_skill_index(base_id);
    if (idx < 0) return 0;
    const auto &st = base[static_cast<std::size_t>(idx)];
    if (st.level <= 0) return 0;
    if (!st.enabled_art.empty()) {
        const int sp_lv = special_level_of(st.enabled_art);
        if (sp_lv > 0) {
            return st.level + (sp_lv * 2 + 1) / 3;
        }
    }
    return st.level;
}

std::string SkillSet::enabled_art_of(const std::string &base_id) const {
    const int idx = find_base_skill_index(base_id);
    if (idx < 0) return {};
    return base[static_cast<std::size_t>(idx)].enabled_art;
}

int SkillSet::total_levels() const {
    int sum = 0;
    for (const auto &s : base) sum += s.level;
    for (const auto &s : special) sum += s.level;
    return sum;
}

int SkillSet::learned_count() const {
    int count = 0;
    for (const auto &s : base) if (s.level > 0) ++count;
    return count;
}

int SkillSet::learned_special_count() const {
    int count = 0;
    for (const auto &s : special) if (s.level > 0) ++count;
    return count;
}

bool SkillSet::has_any_martial_skill() const {
    for (std::size_t i = 0; i < 16; ++i) {
        if (base[i].level > 0) return true;
    }
    return false;
}

int SkillSet::potential_cap() const {
    return 120 + total_levels() * 12 + combat_exp / 4;
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
    if (amount > 0) combat_exp = std::min(99999999, combat_exp + amount);
}

bool SkillSet::add_exp(int skill_idx, int amount, bool &leveled_up) {
    leveled_up = false;
    if (skill_idx < 0 || skill_idx >= static_cast<int>(kBaseSkillCount) || amount <= 0) return false;
    auto &st = base[static_cast<std::size_t>(skill_idx)];
    st.exp += amount;
    while (st.level < 300) {
        const int need = skill_exp_to_next(st.level);
        if (st.exp < need) break;
        st.exp -= need;
        ++st.level;
        leveled_up = true;
    }
    return true;
}

bool SkillSet::add_special_exp(int art_idx, int amount, bool &leveled_up) {
    leveled_up = false;
    if (art_idx < 0 || art_idx >= static_cast<int>(kSpecialArtCount) || amount <= 0) return false;
    auto &st = special[static_cast<std::size_t>(art_idx)];
    st.exp += amount;
    while (st.level < 300) {
        const int need = skill_exp_to_next(st.level);
        if (st.exp < need) break;
        st.exp -= need;
        ++st.level;
        leveled_up = true;
    }
    return true;
}

bool SkillSet::set_jifa(int skill_idx, const std::string &special_art_id) {
    if (skill_idx < 0 || skill_idx >= static_cast<int>(kBaseSkillCount)) return false;
    const auto &def = base_skill_catalog()[static_cast<std::size_t>(skill_idx)];
    if (!def.supports_jifa) return false;
    if (special_art_id.empty()) {
        base[static_cast<std::size_t>(skill_idx)].enabled_art.clear();
        return true;
    }
    const int sp_idx = find_special_art_index(special_art_id);
    if (sp_idx < 0) return false;
    const auto &sp_def = special_art_catalog()[static_cast<std::size_t>(sp_idx)];
    if (std::string(sp_def.base_skill_id) != def.id) return false;
    if (special[static_cast<std::size_t>(sp_idx)].level <= 0) return false;
    base[static_cast<std::size_t>(skill_idx)].enabled_art = special_art_id;
    return true;
}

int SkillSet::learn_potential_cost(int skill_idx) const {
    if (skill_idx < 0 || skill_idx >= static_cast<int>(kBaseSkillCount)) return 10;
    const int lv = base[static_cast<std::size_t>(skill_idx)].level;
    if (lv == 0) return 10;
    return 8 + lv / 4;
}

int SkillSet::learn_coin_cost(int skill_idx) const {
    if (skill_idx < 0 || skill_idx >= static_cast<int>(kBaseSkillCount)) return 3;
    const int lv = base[static_cast<std::size_t>(skill_idx)].level;
    if (lv == 0) return 3;
    return 2 + lv / 5;
}

int SkillSet::learn_exp_gain(int stat_int) const {
    const int lit = level_of("literate");
    const double mult = 1.0 + static_cast<double>(lit) * 0.04;
    return std::max(14, static_cast<int>(std::round((16.0 + static_cast<double>(stat_int) * 2.0) * mult)));
}

int SkillSet::special_learn_pot_cost(int art_idx) const {
    if (art_idx < 0 || art_idx >= static_cast<int>(kSpecialArtCount)) return 16;
    const int lv = special[static_cast<std::size_t>(art_idx)].level;
    if (lv == 0) return 16;
    return 12 + lv / 3;
}

int SkillSet::special_learn_coin_cost(int art_idx) const {
    if (art_idx < 0 || art_idx >= static_cast<int>(kSpecialArtCount)) return 6;
    const int lv = special[static_cast<std::size_t>(art_idx)].level;
    if (lv == 0) return 6;
    return 4 + lv / 4;
}

int SkillSet::research_potential_cost(int skill_idx) const {
    if (skill_idx < 0 || skill_idx >= static_cast<int>(kBaseSkillCount)) return 25;
    const int lv = base[static_cast<std::size_t>(skill_idx)].level;
    return 24 + std::max(0, lv - kResearchMinLevel) / 3;
}

int SkillSet::research_exp_gain(int stat_int) const {
    const int lit = level_of("literate");
    const double mult = 1.0 + static_cast<double>(lit) * 0.03;
    return std::max(26, static_cast<int>(std::round((30.0 + static_cast<double>(stat_int) * 2.5) * mult)));
}

Array SkillSet::realms_to_array() const {
    Array out;
    for (const auto &r : skill_realm_catalog()) {
        Dictionary d;
        d["id"] = String::utf8(r.id);
        d["name"] = String::utf8(r.name);
        d["subtitle"] = String::utf8(r.subtitle);
        d["unlock_hint"] = String::utf8(r.unlock_hint);
        d["unlocked"] = r.unlocked;
        d["count"] = (r.realm == SkillRealm::Wuxue) ? learned_count() : 0;
        d["total_catalog"] = (r.realm == SkillRealm::Wuxue) ? static_cast<int>(kBaseSkillCount) : 0;
        out.append(d);
    }
    return out;
}

Array SkillSet::skills_to_array(const String &realm_filter) const {
    Array out;
    const std::string filt = realm_filter.utf8().get_data();
    const auto &cat = base_skill_catalog();
    const auto &sp_cat = special_art_catalog();
    for (std::size_t i = 0; i < kBaseSkillCount; ++i) {
        const auto &def = cat[i];
        const auto &st = base[i];
        // STRICT ZERO-START: Unlearned skills (level == 0) are HIDDEN until learned from a city master!
        if (st.level <= 0) continue;
        const char *rid = skill_realm_catalog()[static_cast<std::size_t>(def.realm)].id;
        if (!filt.empty() && filt != "all" && filt != rid) continue;
        const int need = skill_exp_to_next(st.level);
        const int eff = effective_level_of(def.id);
        String enabled_name;
        if (!st.enabled_art.empty()) {
            const int sp_idx = find_special_art_index(st.enabled_art);
            if (sp_idx >= 0) enabled_name = String::utf8(sp_cat[static_cast<std::size_t>(sp_idx)].name);
        }
        Array avail_arts;
        if (def.supports_jifa) {
            for (std::size_t si = 0; si < kSpecialArtCount; ++si) {
                if (std::string(sp_cat[si].base_skill_id) == def.id && special[si].level > 0) {
                    Dictionary sd;
                    sd["id"] = String::utf8(sp_cat[si].id);
                    sd["name"] = String::utf8(sp_cat[si].name);
                    sd["level"] = special[si].level;
                    sd["enabled"] = (st.enabled_art == sp_cat[si].id);
                    avail_arts.append(sd);
                }
            }
        }
        Dictionary row;
        row["id"] = String::utf8(def.id);
        row["name"] = String::utf8(def.name);
        row["realm"] = String::utf8(rid);
        row["category"] = String::utf8(def.category);
        row["desc"] = String::utf8(def.desc);
        row["mentor_hint"] = String::utf8(def.mentor_hint);
        row["supports_jifa"] = def.supports_jifa;
        row["level"] = st.level;
        row["effective_level"] = eff;
        row["exp"] = st.exp;
        row["exp_need"] = need;
        row["rank"] = String::utf8(skill_rank_title(st.level));
        row["enabled_art"] = String::utf8(st.enabled_art.c_str());
        row["enabled_art_name"] = enabled_name;
        row["available_arts"] = avail_arts;
        row["can_practice"] = (st.level >= 1 && st.level < kResearchMinLevel);
        row["can_research"] = (st.level >= kResearchMinLevel);
        row["research_pot_cost"] = research_potential_cost(static_cast<int>(i));
        out.append(row);
    }
    return out;
}

Array SkillSet::special_arts_to_array() const {
    Array out;
    const auto &sp_cat = special_art_catalog();
    const auto &b_cat = base_skill_catalog();
    for (std::size_t i = 0; i < kSpecialArtCount; ++i) {
        const auto &st = special[i];
        if (st.level <= 0) continue;
        const auto &def = sp_cat[i];
        const int bidx = find_base_skill_index(def.base_skill_id);
        const bool is_enabled = (bidx >= 0 && base[static_cast<std::size_t>(bidx)].enabled_art == def.id);
        Dictionary row;
        row["id"] = String::utf8(def.id);
        row["name"] = String::utf8(def.name);
        row["base_skill_id"] = String::utf8(def.base_skill_id);
        row["base_skill_name"] = bidx >= 0 ? String::utf8(b_cat[static_cast<std::size_t>(bidx)].name) : String();
        row["level"] = st.level;
        row["exp"] = st.exp;
        row["exp_need"] = skill_exp_to_next(st.level);
        row["rank"] = String::utf8(skill_rank_title(st.level));
        row["enabled"] = is_enabled;
        row["desc"] = String::utf8(def.desc);
        out.append(row);
    }
    return out;
}

Dictionary SkillSet::summary_dict() const {
    int max_lv = 0;
    for (const auto &s : base) max_lv = std::max(max_lv, s.level);
    for (const auto &s : special) max_lv = std::max(max_lv, s.level);
    Dictionary d;
    d["total_levels"] = total_levels();
    d["max_level"] = max_lv;
    d["learned_count"] = learned_count();
    d["learned_special_count"] = learned_special_count();
    d["base_count"] = static_cast<int>(kBaseSkillCount);
    d["potential"] = potential;
    d["potential_cap"] = potential_cap();
    d["combat_exp"] = combat_exp;
    d["research_min_level"] = kResearchMinLevel;
    d["overall_rank"] = String::utf8(skill_rank_title(max_lv));
    d["active_realm"] = String::utf8("武学");
    return d;
}

Dictionary SkillSet::save_dict() const {
    Dictionary d;
    d["potential"] = potential;
    d["combat_exp"] = combat_exp;
    Dictionary levels;
    const auto &cat = base_skill_catalog();
    for (std::size_t i = 0; i < kBaseSkillCount; ++i) {
        if (base[i].level <= 0 && base[i].exp <= 0 && base[i].enabled_art.empty()) continue;
        Dictionary entry;
        entry["lv"] = base[i].level;
        entry["exp"] = base[i].exp;
        if (!base[i].enabled_art.empty()) entry["art"] = String::utf8(base[i].enabled_art.c_str());
        levels[String::utf8(cat[i].id)] = entry;
    }
    d["base"] = levels;
    Dictionary sp_levels;
    const auto &sp_cat = special_art_catalog();
    for (std::size_t i = 0; i < kSpecialArtCount; ++i) {
        if (special[i].level <= 0 && special[i].exp <= 0) continue;
        Dictionary entry;
        entry["lv"] = special[i].level;
        entry["exp"] = special[i].exp;
        sp_levels[String::utf8(sp_cat[i].id)] = entry;
    }
    d["special"] = sp_levels;
    return d;
}

void SkillSet::load_dict(const Dictionary &d) {
    reset_defaults();
    if (d.has("potential")) potential = std::max(0, static_cast<int>(d["potential"]));
    if (d.has("combat_exp")) combat_exp = std::max(0, static_cast<int>(d["combat_exp"]));
    if (d.get("base", Variant()).get_type() == Variant::DICTIONARY) {
        const Dictionary levels = d["base"];
        const auto &cat = base_skill_catalog();
        for (std::size_t i = 0; i < kBaseSkillCount; ++i) {
            const String key = String::utf8(cat[i].id);
            if (!levels.has(key)) continue;
            const Variant v = levels[key];
            if (v.get_type() != Variant::DICTIONARY) continue;
            const Dictionary entry = v;
            base[i].level = std::clamp(static_cast<int>(entry.get("lv", 0)), 0, 300);
            base[i].exp = std::max(0, static_cast<int>(entry.get("exp", 0)));
            const String art = entry.get("art", String());
            base[i].enabled_art = art.utf8().get_data();
        }
    }
    if (d.get("special", Variant()).get_type() == Variant::DICTIONARY) {
        const Dictionary sp_levels = d["special"];
        const auto &sp_cat = special_art_catalog();
        for (std::size_t i = 0; i < kSpecialArtCount; ++i) {
            const String key = String::utf8(sp_cat[i].id);
            if (!sp_levels.has(key)) continue;
            const Variant v = sp_levels[key];
            if (v.get_type() != Variant::DICTIONARY) continue;
            const Dictionary entry = v;
            special[i].level = std::clamp(static_cast<int>(entry.get("lv", 0)), 0, 300);
            special[i].exp = std::max(0, static_cast<int>(entry.get("exp", 0)));
        }
    }
    // Sanitize enabled_art against learned special arts
    for (std::size_t i = 0; i < kBaseSkillCount; ++i) {
        if (!base[i].enabled_art.empty() && special_level_of(base[i].enabled_art) <= 0) {
            base[i].enabled_art.clear();
        }
    }
}

} // namespace cangling
