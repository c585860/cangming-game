#pragma once

#include <array>
#include <cstddef>
#include <string>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace cangling {

// 4 Cultivation / Martial Path Tabs on the Classic Wuxia MUD Skill Panel:
//   0 = 武学 (Active: 18 foundational Wuxia skills + 2 trade basics = 20 skills, ALL start Lv.0!)
//   1 = 武道 (Reserved grandmaster martial dao tier)
//   2 = 练气 (Reserved qi-refining tier)
//   3 = 仙道 (Reserved immortal dao tier)
enum class SkillRealm : int {
    Wuxue = 0,
    Wudao = 1,
    Lianqi = 2,
    Xiandao = 3,
};

struct SkillRealmDef {
    SkillRealm realm;
    const char *id;
    const char *name;
    const char *subtitle;
    const char *unlock_hint;
    bool unlocked;
};

struct SkillDef {
    const char *id;
    const char *name;
    SkillRealm realm;
    const char *category;
    const char *desc;
    const char *mentor_hint; // Which city master teaches this skill!
    bool supports_jifa;      // Classic MUD enable/jifa slot (激发特殊武功)
};

struct SkillProgress {
    int level = 0;
    int exp = 0;
    std::string enabled_art;
};

inline constexpr std::size_t kSkillRealmCount = 4;
inline constexpr std::size_t kBaseSkillCount = 20;

const std::array<SkillRealmDef, kSkillRealmCount> &skill_realm_catalog();
const std::array<SkillDef, kBaseSkillCount> &base_skill_catalog();
int find_base_skill_index(const std::string &id);
const char *skill_rank_title(int level);
int skill_exp_to_next(int level);

struct SkillSet {
    std::array<SkillProgress, kBaseSkillCount> base{};
    int potential = 30;      // 潜能 (starting spark of insight so player can learn 1-2 basics)
    int combat_exp = 0;      // 江湖阅历 (experience raising potential cap & realm gates)

    void reset_defaults();
    int level_of(const std::string &id) const;
    int total_levels() const;
    int learned_count() const;
    bool has_any_martial_skill() const;
    int potential_cap() const;
    int add_potential(int amount);
    bool spend_potential(int amount);
    void add_combat_exp(int amount);
    bool add_exp(int skill_idx, int amount, bool &leveled_up);
    bool set_jifa(int skill_idx, const std::string &special_art_id);

    // Classic Wuxia MUD learn (<180), slow practice (1..179), and research (>=180) formulas
    static constexpr int kResearchMinLevel = 180;
    int learn_potential_cost(int skill_idx) const;
    int learn_coin_cost(int skill_idx) const;
    int learn_exp_gain(int stat_int) const;
    int research_potential_cost(int skill_idx) const;
    int research_exp_gain(int stat_int) const;

    godot::Array realms_to_array() const;
    godot::Array skills_to_array(const godot::String &realm_filter) const;
    godot::Dictionary summary_dict() const;
    godot::Dictionary save_dict() const;
    void load_dict(const godot::Dictionary &d);
};

} // namespace cangling
