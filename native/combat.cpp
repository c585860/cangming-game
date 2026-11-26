#include "combat.hpp"
#include "item_catalog.hpp"
#include <godot_cpp/variant/variant.hpp>
#include <algorithm>
#include <cmath>
#include <cstring>

namespace cangling {
using namespace godot;

namespace {
constexpr const char *kPartNames[6] = {"头部", "躯干", "左臂", "右臂", "左腿", "右腿"};

int next_roll(int &state, int mod) {
    state = static_cast<int>((static_cast<std::uint32_t>(state) * 1664525u + 1013904223u) & 0x7fffffffu);
    return mod > 0 ? (state % mod) : 0;
}

std::string active_player_attack_skill(const CharacterState &ch, const SkillSet &skills, String &weapon_label, String &move_label, int &roll_state) {
    const auto &cat = item_catalog();
    if (ch.wielded >= 0 && ch.wielded < kItemCount) {
        const auto &def = cat[ch.wielded];
        if (def.weapon_skill && def.weapon_skill[0] != '\0') {
            weapon_label = String::utf8(def.name);
            const std::string bskill = def.weapon_skill;
            const std::string art = skills.enabled_art_of(bskill);
            if (!art.empty()) {
                const int sp_idx = find_special_art_index(art);
                if (sp_idx >= 0) {
                    const auto &sp = special_art_catalog()[static_cast<std::size_t>(sp_idx)];
                    move_label = String::utf8(sp.move_names[next_roll(roll_state, 3)]);
                    return bskill;
                }
            }
            static constexpr const char *kGenericWeaponMoves[3] = {"直刺中宫", "斜劈横扫", "回锋挑击"};
            move_label = String::utf8(kGenericWeaponMoves[next_roll(roll_state, 3)]);
            return bskill;
        }
    }
    weapon_label = String::utf8("双拳");
    // Pick best learned empty-hand skill
    static constexpr const char *kUnarmedIds[6] = {"unarmed", "strike", "cuff", "finger", "claw", "hand"};
    std::string best = "unarmed";
    int best_eff = -1;
    for (const char *id : kUnarmedIds) {
        const int eff = skills.effective_level_of(id);
        if (eff > best_eff) {
            best_eff = eff;
            best = id;
        }
    }
    const std::string art = skills.enabled_art_of(best);
    if (!art.empty()) {
        const int sp_idx = find_special_art_index(art);
        if (sp_idx >= 0) {
            const auto &sp = special_art_catalog()[static_cast<std::size_t>(sp_idx)];
            move_label = String::utf8(sp.move_names[next_roll(roll_state, 3)]);
            return best;
        }
    }
    static constexpr const char *kGenericHandMoves[3] = {"直拳冲捶", "沉肩靠打", "提膝横劈"};
    move_label = String::utf8(kGenericHandMoves[next_roll(roll_state, 3)]);
    return best;
}
} // namespace

const SparOpponentDef *spar_opponent_for_npc(const char *npc_id) {
    static constexpr SparOpponentDef kOpponents[3] = {
        {"sparring_disciple", "武馆陪练弟子", "扬威入门拳脚", "木棍", 95, 8, 22, 16, 2,
         {"弓步冲拳", "横扫下盘", "斜劈肩头"}},
        {"martial_master", "陈馆主", "扬威长拳与太祖绵掌", "双掌", 185, 22, 40, 30, 5,
         {"排山倒海", "黑虎掏心", "云手翻浪"}},
        {"weapon_coach", "周教头", "青霜剑与杨家枪", "木枪", 190, 24, 42, 32, 5,
         {"灵蛇吐信", "青霜映雪", "回马挑灯"}},
    };
    if (!npc_id) return nullptr;
    for (const auto &op : kOpponents) {
        if (std::strcmp(op.npc_id, npc_id) == 0) return &op;
    }
    return nullptr;
}

void SparSession::reset() {
    active = false;
    npc_id.clear();
    npc_name.clear();
    npc_pos = {0, 0};
    opp_hp = 0;
    opp_max_hp = 100;
    opp_skill_lv = 8;
    rounds = 0;
    player_hits = 0;
    opp_hits = 0;
}

Dictionary SparSession::to_dict() const {
    Dictionary d;
    d["active"] = active;
    d["npc_id"] = String::utf8(npc_id.c_str());
    d["npc_name"] = String::utf8(npc_name.c_str());
    d["npc_pos"] = npc_pos;
    d["opp_hp"] = opp_hp;
    d["opp_max_hp"] = opp_max_hp;
    d["opp_skill_lv"] = opp_skill_lv;
    d["rounds"] = rounds;
    return d;
}

Dictionary begin_spar_session(SparSession &sess, const char *npc_id, Vector2i npc_pos,
                              const CharacterState &ch, const SkillSet &skills) {
    Dictionary res;
    res["ok"] = false;
    const SparOpponentDef *op = spar_opponent_for_npc(npc_id);
    if (!op) {
        res["message"] = String::utf8("此人并不与人切磋比武。");
        return res;
    }
    if (ch.is_severely_injured()) {
        res["message"] = String::utf8("你头胸尚有重伤，先包扎或运功疗伤再上场切磋吧！");
        return res;
    }
    if (ch.is_starving_for_training()) {
        res["message"] = String::utf8("你又饿又渴、下盘发虚，先吃顿饱饭再上台演武！");
        return res;
    }
    if (ch.stamina < 1500) {
        res["message"] = String::utf8("你气息未定、耐力不足，先歇息或运功调息再切磋。");
        return res;
    }
    sess.active = true;
    sess.npc_id = op->npc_id;
    sess.npc_name = op->name;
    sess.npc_pos = npc_pos;
    sess.opp_max_hp = op->max_hp;
    sess.opp_hp = op->max_hp;
    sess.opp_skill_lv = op->skill_lv;
    sess.rounds = 0;
    sess.player_hits = 0;
    sess.opp_hits = 0;
    sess.rng_state = 9187 + skills.combat_exp * 13 + ch.stamina + npc_pos.x * 31;
    res["ok"] = true;
    res["message"] = String::utf8("你抱拳朗声道：「请") + String::utf8(op->name) +
                     String::utf8("赐教！」") + String::utf8(op->name) +
                     String::utf8("微笑还礼，拉开架势（点到为止，随时可按 Esc 或走开收招）。");
    res["session"] = sess.to_dict();
    return res;
}

Dictionary advance_spar_round(SparSession &sess, CharacterState &ch, SkillSet &skills) {
    Dictionary res;
    res["active"] = false;
    res["finished"] = false;
    if (!sess.active) return res;
    const SparOpponentDef *op = spar_opponent_for_npc(sess.npc_id.c_str());
    if (!op) {
        sess.reset();
        return res;
    }

    ++sess.rounds;
    String weapon_lbl, move_lbl;
    const std::string atk_skill = active_player_attack_skill(ch, skills, weapon_lbl, move_lbl, sess.rng_state);
    const int p_atk = skills.effective_level_of(atk_skill);
    const int p_dodge = skills.effective_level_of("dodge");
    const int p_parry = skills.effective_level_of("parry");
    const int p_force = skills.effective_level_of("force");

    // 1. Player attack exchange
    int jiali_used = 0;
    if (ch.jiali > 0 && ch.neili >= ch.jiali) {
        jiali_used = ch.jiali;
        ch.neili -= jiali_used;
    }
    int weapon_dmg = 4;
    if (ch.wielded >= 0 && ch.wielded < kItemCount) {
        weapon_dmg = std::max(4, item_catalog()[ch.wielded].bash_dmg / 2);
    }

    const int p_hit_roll = 58 + (p_atk - sess.opp_skill_lv) * 2 + (ch.stat_dex - 8) * 2 + next_roll(sess.rng_state, 30);
    String log = String::utf8("【第") + String::num_int64(sess.rounds) + String::utf8("合】你使出一招「") +
                 move_lbl + String::utf8("」，") + weapon_lbl + String::utf8("直取") + String::utf8(op->name) + String::utf8("！");

    ch.spend_stamina(320);
    ch.kcal = std::max(0.0, ch.kcal - 12.0);
    ch.hydration = std::max(0.0, ch.hydration - 1.2);

    if (p_hit_roll < 52) {
        log += String::utf8(op->name) + String::utf8("身形微侧，顺势格开来招。");
    } else {
        const int dmg = std::max(4, 6 + p_atk / 2 + weapon_dmg + jiali_used / 2 + p_force / 6 + next_roll(sess.rng_state, 6) - sess.opp_skill_lv / 4);
        sess.opp_hp = std::max(1, sess.opp_hp - dmg);
        ++sess.player_hits;
        const char *op_part = kPartNames[next_roll(sess.rng_state, 6)];
        log += String::utf8("劲风扫中") + String::utf8(op->name) + String::utf8(op_part) +
               String::utf8("（-") + String::num_int64(dmg) + String::utf8("）！");
        if (jiali_used > 0) log += String::utf8("[加力") + String::num_int64(jiali_used) + String::utf8("]");
    }

    // Grant live combat skill practice on the attack skill
    const int atk_idx = find_base_skill_index(atk_skill);
    if (atk_idx >= 0 && skills.base[static_cast<std::size_t>(atk_idx)].level > 0) {
        bool lv_up = false;
        skills.add_exp(atk_idx, 5 + next_roll(sess.rng_state, 4), lv_up);
        const std::string art = skills.enabled_art_of(atk_skill);
        if (!art.empty()) {
            const int sp_idx = find_special_art_index(art);
            if (sp_idx >= 0) {
                bool sp_up = false;
                skills.add_special_exp(sp_idx, 6, sp_up);
            }
        }
    }

    // Check opponent yield (<25% HP)
    if (sess.opp_hp * 100 <= sess.opp_max_hp * 25) {
        ++ch.spar_wins;
        ++ch.spar_total;
        const int pot = skills.add_potential(op->reward_pot);
        skills.add_combat_exp(op->reward_exp);
        ch.reputation += op->reward_rep;
        ch.morale = std::min(50, ch.morale + 6);
        ch.sync_with_skills(skills);
        log += String::utf8(" ") + String::utf8(op->name) + String::utf8("连退两步，抱拳笑道：「好功夫！点到为止，少侠承让！」（潜能 +") +
               String::num_int64(pot) + String::utf8("、阅历 +") + String::num_int64(op->reward_exp) +
               String::utf8("、声望 +") + String::num_int64(op->reward_rep) + String::utf8("）");
        sess.reset();
        res["message"] = log;
        res["finished"] = true;
        res["won"] = true;
        return res;
    }

    // 2. Opponent counterattack exchange (CCB 6 body parts + dodge/parry!)
    const char *op_move = op->moves[next_roll(sess.rng_state, 3)];
    const int op_hit_roll = 55 + (sess.opp_skill_lv - (p_dodge + p_parry) / 2) * 2 + next_roll(sess.rng_state, 28);
    log += String::utf8(" ") + String::utf8(op->name) + String::utf8("反手一招「") + String::utf8(op_move) + String::utf8("」攻来，");
    if (op_hit_roll < 42) {
        log += String::utf8("你足尖一点轻灵闪过！");
        const int didx = find_base_skill_index("dodge");
        if (didx >= 0 && skills.base[static_cast<std::size_t>(didx)].level > 0) {
            bool lv_up = false;
            skills.add_exp(didx, 5, lv_up);
        }
    } else if (op_hit_roll < 56) {
        const int graze = std::max(1, 2 + sess.opp_skill_lv / 8 - p_parry / 6);
        const int part = 2 + next_roll(sess.rng_state, 2); // arms
        ch.part_hp[static_cast<std::size_t>(part)] = std::max(1, ch.part_hp[static_cast<std::size_t>(part)] - graze);
        log += String::utf8("你横架化解大半劲力，") + String::utf8(kPartNames[part]) + String::utf8("微震（-") + String::num_int64(graze) + String::utf8("）。");
        const int pidx = find_base_skill_index("parry");
        if (pidx >= 0 && skills.base[static_cast<std::size_t>(pidx)].level > 0) {
            bool lv_up = false;
            skills.add_exp(pidx, 5, lv_up);
        }
    } else {
        const int part = next_roll(sess.rng_state, 6);
        const int raw = 5 + sess.opp_skill_lv / 3 + next_roll(sess.rng_state, 5) - p_parry / 5 - p_force / 8;
        const int dmg = std::max(3, raw);
        ch.part_hp[static_cast<std::size_t>(part)] = std::max(1, ch.part_hp[static_cast<std::size_t>(part)] - dmg);
        ch.pain = std::min(100, ch.pain + std::max(2, dmg / 3));
        ++sess.opp_hits;
        log += String::utf8("击中你") + String::utf8(kPartNames[part]) + String::utf8("（-") + String::num_int64(dmg) + String::utf8("气血）！");
    }

    // Check player yield (<25% HP on head/torso or exhausted or max 12 rounds draw)
    const bool player_low = (ch.part_hp[0] * 100 <= ch.max_part_hp * 25) || (ch.part_hp[1] * 100 <= ch.max_part_hp * 25) || ch.stamina < 350;
    if (player_low || sess.rounds >= 12) {
        ++ch.spar_total;
        const int pot = skills.add_potential(std::max(8, op->reward_pot / 2));
        const int exp = std::max(6, op->reward_exp / 2);
        skills.add_combat_exp(exp);
        ch.sync_with_skills(skills);
        log += player_low
            ? (String::utf8(" ") + String::utf8(op->name) + String::utf8("及时收招笑道：「点到为止！少侠先包扎调息，下回再战！」（潜能 +") +
               String::num_int64(pot) + String::utf8("、阅历 +") + String::num_int64(exp) + String::utf8("）"))
            : (String::utf8(" 十二合已过，双方各自收招抱拳，势均力敌！（潜能 +") +
               String::num_int64(pot) + String::utf8("、阅历 +") + String::num_int64(exp) + String::utf8("）"));
        sess.reset();
        res["message"] = log;
        res["finished"] = true;
        res["won"] = false;
        return res;
    }

    ch.sync_with_skills(skills);
    res["active"] = true;
    res["message"] = log;
    res["session"] = sess.to_dict();
    return res;
}

String finish_spar_early(SparSession &sess) {
    if (!sess.active) return {};
    const String name = String::utf8(sess.npc_name.c_str());
    sess.reset();
    return String::utf8("你收招抱拳道：「多谢") + name + String::utf8("指点，改日再行切磋！」");
}

} // namespace cangling
