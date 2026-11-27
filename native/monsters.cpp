#include "monsters.hpp"
#include "city.hpp"
#include <godot_cpp/variant/variant.hpp>
#include <algorithm>
#include <cmath>

namespace cangling {
using namespace godot;

namespace {

std::string resolve_monster_tile(const std::string &id, const CcbMonsterDef *def) {
    if (id == "mon_zombie" || id == "mon_zombie_runner" || id == "mon_zombie_tough" ||
        id == "mon_zombie_fat" || id == "mon_zombie_cop" || id == "mon_zombie_crawler" ||
        id == "mon_dog") {
        return id;
    }
    if (id.find("dog") != std::string::npos) return "mon_dog";
    if (id.find("cop") != std::string::npos || id.find("soldier") != std::string::npos ||
        id.find("hazmat") != std::string::npos) return "mon_zombie_cop";
    if (id.find("runner") != std::string::npos || id.find("hunter") != std::string::npos) return "mon_zombie_runner";
    if (id.find("tough") != std::string::npos || id.find("brute") != std::string::npos) return "mon_zombie_tough";
    if (id.find("fat") != std::string::npos || id.find("boomer") != std::string::npos) return "mon_zombie_fat";
    if (def && !def->looks_like.empty()) {
        if (def->looks_like == "mon_zombie" || def->looks_like == "mon_dog" ||
            def->looks_like == "mon_zombie_fat" || def->looks_like == "mon_zombie_tough" ||
            def->looks_like == "mon_zombie_runner" || def->looks_like == "mon_zombie_cop") {
            return def->looks_like;
        }
    }
    return "mon_zombie";
}

bool has_line_of_sight(
    Vector2i from,
    Vector2i to,
    int z,
    const std::function<bool(Vector2i, int)> &blocks_sight) {
    int x0 = from.x, y0 = from.y;
    const int x1 = to.x, y1 = to.y;
    const int dx = std::abs(x1 - x0);
    const int dy = std::abs(y1 - y0);
    const int sx = x0 < x1 ? 1 : -1;
    const int sy = y0 < y1 ? 1 : -1;
    int err = dx - dy;
    int guard = 0;
    while ((x0 != x1 || y0 != y1) && guard++ < 48) {
        const int e2 = err * 2;
        if (e2 > -dy) { err -= dy; x0 += sx; }
        if (e2 < dx)  { err += dx; y0 += sy; }
        if (x0 == x1 && y0 == y1) return true;
        if (blocks_sight({x0, y0}, z)) return false;
    }
    return true;
}

const char *body_part_cn(int part) {
    switch (part) {
        case 0: return "头部";
        case 1: return "躯干";
        case 2: return "左臂";
        case 3: return "右臂";
        case 4: return "左腿";
        default: return "右腿";
    }
}

// CCB melee_hit_range approximation: bell-curve centered around hit value
float roll_ccb_bell(CcbSurvivalState &ccb, float base) {
    const float r = static_cast<float>(ccb.rng_range(-30, 30) + ccb.rng_range(-30, 30)) * 0.05f;
    return base + r;
}

Dictionary make_monster_dict(const MonsterInstance &m) {
    const auto *def = CcbVanillaDB::instance().find_monster(m.species_id);
    Dictionary d;
    d["id"] = m.id;
    d["species_id"] = String::utf8(m.species_id.c_str());
    d["name"] = String::utf8(def ? def->name.c_str() : m.species_id.c_str());
    d["tile"] = String::utf8(resolve_monster_tile(m.species_id, def).c_str());
    d["pos"] = m.pos;
    d["floor"] = m.floor;
    d["hp"] = m.hp;
    d["max_hp"] = m.max_hp;
    d["alerted"] = m.alerted;
    d["speed"] = def ? def->speed : 75;
    d["melee_skill"] = def ? def->melee_skill : 3;
    d["dodge"] = def ? def->dodge : 0;
    d["armor_bash"] = def ? def->armor_bash : 0;
    d["armor_cut"] = def ? def->armor_cut : 0;
    d["armor_stab"] = def ? def->armor_stab : 0;
    d["desc"] = String::utf8(def ? def->desc.c_str() : "");
    return d;
}

} // namespace

int64_t MonsterManager::tile_key(Vector2i p, int z) {
    return infinite_tile_key(p, z);
}

void MonsterManager::rebuild_spatial() {
    spatial.clear();
    spatial.reserve(list.size() * 2 + 16);
    for (std::size_t i = 0; i < list.size(); ++i) {
        if (list[i].alive) {
            spatial[tile_key(list[i].pos, list[i].floor)] = static_cast<int>(i);
        }
    }
}

void MonsterManager::clear() {
    list.clear();
    spatial.clear();
    next_id = 1;
}

void MonsterManager::populate_from_spawns(const std::vector<MonsterSpawn> &spawns) {
    clear();
    add_spawns(spawns);
}

void MonsterManager::add_spawns(const std::vector<MonsterSpawn> &spawns) {
    const auto &db = CcbVanillaDB::instance();
    list.reserve(list.size() + spawns.size());
    for (const auto &s : spawns) {
        const int64_t k = tile_key(s.pos, s.floor);
        if (spatial.find(k) != spatial.end()) continue;
        const auto *def = db.find_monster(s.species_id);
        MonsterInstance m;
        m.id = next_id++;
        m.species_id = def ? def->id : std::string("mon_zombie");
        m.pos = s.pos;
        m.floor = s.floor;
        m.max_hp = def ? std::max(10, def->hp) : 80;
        m.hp = m.max_hp;
        m.move_accum = 0;
        m.alerted = false;
        m.alive = true;
        m.last_target = s.pos;
        const int idx = static_cast<int>(list.size());
        list.push_back(std::move(m));
        spatial[k] = idx;
    }
}

bool MonsterManager::spawn_one(const std::string &species_id, Vector2i pos, int z, bool alerted) {
    const int64_t k = tile_key(pos, z);
    if (spatial.find(k) != spatial.end()) return false;
    const auto &db = CcbVanillaDB::instance();
    const auto *def = db.find_monster(species_id);
    MonsterInstance m;
    m.id = next_id++;
    m.species_id = def ? def->id : std::string("mon_zombie");
    m.pos = pos;
    m.floor = z;
    m.max_hp = def ? std::max(10, def->hp) : 80;
    m.hp = m.max_hp;
    m.move_accum = 0;
    m.alerted = alerted;
    m.alive = true;
    m.last_target = pos;
    const int idx = static_cast<int>(list.size());
    list.push_back(std::move(m));
    spatial[k] = idx;
    return true;
}

int MonsterManager::alive_count() const {
    return static_cast<int>(spatial.size());
}

const MonsterInstance *MonsterManager::at(Vector2i p, int z) const {
    const auto it = spatial.find(tile_key(p, z));
    if (it == spatial.end()) return nullptr;
    const MonsterInstance &m = list[static_cast<std::size_t>(it->second)];
    return m.alive ? &m : nullptr;
}

MonsterInstance *MonsterManager::at_mut(Vector2i p, int z) {
    const auto it = spatial.find(tile_key(p, z));
    if (it == spatial.end()) return nullptr;
    MonsterInstance &m = list[static_cast<std::size_t>(it->second)];
    return m.alive ? &m : nullptr;
}

Array MonsterManager::monsters_in_rect(Rect2i area, int z) const {
    Array out;
    for (const auto &m : list) {
        if (!m.alive || m.floor != z) continue;
        if (area.has_point(m.pos)) {
            out.append(make_monster_dict(m));
        }
    }
    return out;
}

Dictionary MonsterManager::monster_dict_at(Vector2i p, int z) const {
    const MonsterInstance *m = at(p, z);
    return m ? make_monster_dict(*m) : Dictionary();
}

MonsterTickResult MonsterManager::tick(
    int steps,
    Vector2i player_pos,
    int player_floor,
    bool is_night,
    CharacterState &char_state,
    CcbSurvivalState &ccb,
    const std::function<bool(Vector2i, int)> &can_step_tile,
    const std::function<bool(Vector2i, int)> &blocks_sight) {
    return tick_moves(steps * 100, player_pos, player_floor, is_night, char_state, ccb, can_step_tile, blocks_sight);
}

MonsterTickResult MonsterManager::tick_moves(
    int moves,
    Vector2i player_pos,
    int player_floor,
    bool is_night,
    CharacterState &char_state,
    CcbSurvivalState &ccb,
    const std::function<bool(Vector2i, int)> &can_step_tile,
    const std::function<bool(Vector2i, int)> &blocks_sight) {
    MonsterTickResult res;
    if (moves <= 0 || list.empty()) return res;
    const auto &db = CcbVanillaDB::instance();
    const auto mods = ccb.compute_mods();
    constexpr int kBubbleRadius = 36;

    for (std::size_t i = 0; i < list.size(); ++i) {
        MonsterInstance &m = list[i];
        if (!m.alive || m.floor != player_floor) continue;
        const int cheb = std::max(std::abs(m.pos.x - player_pos.x), std::abs(m.pos.y - player_pos.y));
        if (cheb > kBubbleRadius) continue;

        ++res.active_count;
        const auto *def = db.find_monster(m.species_id);
        const int m_speed = def ? def->speed : 75;
        const int base_vis = def ? (is_night ? def->vision_night : std::min(def->vision_day, 18)) : (is_night ? 5 : 14);
        const String mname = String::utf8(def ? def->name.c_str() : m.species_id.c_str());

        int eff_vision = base_vis;
        if (char_state.move_mode == 2) eff_vision = std::max(3, eff_vision - 4);
        else if (char_state.move_mode == 3) eff_vision = std::max(2, eff_vision - 6);
        if (char_state.lamp_lit) eff_vision += 5;

        const bool saw_player = (cheb <= eff_vision) && has_line_of_sight(m.pos, player_pos, m.floor, blocks_sight);
        const bool heard_player = (char_state.last_sound > 0) && (cheb <= char_state.last_sound + 4);

        const bool was_alerted = m.alerted;
        if (saw_player) {
            m.alerted = true;
            m.last_target = player_pos;
            if (!was_alerted && char_state.safe_mode && cheb <= 15) {
                res.safe_mode_alert = true;
                res.messages.append(
                    String::utf8("[安全模式] 发现敌对目标「") + mname +
                    String::utf8("」！（按 ! 可切换安全模式）"));
            }
        } else if (heard_player) {
            m.alerted = true;
            m.last_target = player_pos;
        } else if (m.alerted && m.pos == m.last_target) {
            m.alerted = false;
        }
        if (m.alerted) ++res.alerted_count;

        m.move_accum += (m_speed * moves) / 100;
        int sub_actions = 0;
        while (m.move_accum >= 100 && sub_actions++ < 6) {
            m.move_accum -= 100;
            const int cur_cheb = std::max(std::abs(m.pos.x - player_pos.x), std::abs(m.pos.y - player_pos.y));

            // Vanilla CCB Monster Melee Attack vs Player Dodge & Body-Part Armor
            if (cur_cheb <= 1 && m.alerted) {
                const int m_skill = def ? def->melee_skill : 3;
                const float mon_hit = roll_ccb_bell(ccb, static_cast<float>(m_skill) * 2.5f);
                const int eff_dex = std::max(1, char_state.stat_dex + mods.dex_mod);
                float dodge_base = static_cast<float>(ccb.skills.dodge) + static_cast<float>(eff_dex) * 0.5f -
                                   static_cast<float>(ccb.total_worn_encumbrance()) / 15.0f;
                if (ccb.grab_intensity > 0) dodge_base -= 3.0f;
                if (char_state.move_mode == 3) dodge_base -= 4.0f;
                const float player_dodge = std::max(0.0f, dodge_base) * 2.4f;

                ccb.skills.train(5, 8, std::min(10, m_skill + 2));
                if (player_dodge > mon_hit) {
                    res.messages.append(String::utf8("你闪避了「") + mname + String::utf8("」的攻击！"));
                } else {
                    const int part = ccb.rng_range(0, 5);
                    const int dice = def ? def->melee_dice : 2;
                    const int sides = def ? def->melee_dice_sides : 4;
                    int raw_bash = 0;
                    for (int d = 0; d < dice; ++d) raw_bash += ccb.rng_range(1, sides);
                    int raw_cut = (def && (def->has_special("bite") || def->has_special("scratch"))) ? ccb.rng_range(1, 5) : 0;

                    int cov_b = 0, cov_c = 0;
                    const int armor_b = ccb.worn_armor_for_part(part, 0, cov_b) + mods.natural_armor_bash;
                    const int armor_c = ccb.worn_armor_for_part(part, 1, cov_c) + mods.natural_armor_cut;
                    const bool covered = ccb.rng_range(1, 100) <= std::max(cov_b, 20);
                    const int eff_ab = covered ? armor_b : mods.natural_armor_bash;
                    const int eff_ac = covered ? armor_c : mods.natural_armor_cut;

                    const int dealt_b = std::max(0, raw_bash - eff_ab);
                    const int dealt_c = std::max(0, raw_cut - eff_ac);
                    const int total_dmg = dealt_b + dealt_c;

                    if (total_dmg <= 0) {
                        res.messages.append(String::utf8("「") + mname + String::utf8("」击中了你的") +
                                            String::utf8(body_part_cn(part)) + String::utf8("，但被护甲完全挡下！"));
                    } else {
                        char_state.part_hp[static_cast<std::size_t>(part)] =
                            std::max(1, char_state.part_hp[static_cast<std::size_t>(part)] - total_dmg);
                        const int pain_add = std::max(1, total_dmg / 2);
                        char_state.pain = std::min(100, char_state.pain + pain_add);
                        res.player_damaged = true;

                        String extra;
                        if (dealt_c >= 3 && ccb.one_in(2)) {
                            ccb.bleed[static_cast<std::size_t>(part)] =
                                std::min(20, ccb.bleed[static_cast<std::size_t>(part)] + dealt_c);
                            extra += String::utf8(" [流血]");
                        }
                        if (def && def->has_special("bite") && dealt_c > 0 && ccb.one_in(4)) {
                            ccb.bite_min[static_cast<std::size_t>(part)] = std::max(1, ccb.bite_min[static_cast<std::size_t>(part)]);
                            extra += String::utf8(" [深度咬伤!需消毒]");
                        }
                        if (def && def->has_special("grab") && ccb.one_in(3)) {
                            ccb.grab_intensity = std::min(5, ccb.grab_intensity + 2);
                            extra += String::utf8(" [被抓取]");
                        }

                        res.messages.append(
                            String::utf8("「") + mname + String::utf8("」击中你的") +
                            String::utf8(body_part_cn(part)) + String::utf8("（-") +
                            String::num_int64(total_dmg) + String::utf8(" HP，痛+") +
                            String::num_int64(pain_add) + String::utf8("）") + extra);
                    }
                }
                break;
            }

            // Movement step
            Vector2i next = m.pos;
            if (m.alerted) {
                const int dx = (m.last_target.x > m.pos.x) ? 1 : ((m.last_target.x < m.pos.x) ? -1 : 0);
                const int dy = (m.last_target.y > m.pos.y) ? 1 : ((m.last_target.y < m.pos.y) ? -1 : 0);
                const Vector2i candidates[3] = {
                    m.pos + Vector2i(dx, dy),
                    m.pos + Vector2i(dx, 0),
                    m.pos + Vector2i(0, dy),
                };
                for (const Vector2i &cand : candidates) {
                    if (cand == m.pos || cand == player_pos) continue;
                    if (!can_step_tile(cand, m.floor)) continue;
                    if (spatial.find(tile_key(cand, m.floor)) != spatial.end()) continue;
                    next = cand;
                    break;
                }
            } else if (ccb.one_in(4)) {
                static const Vector2i kDirs[4] = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}};
                const Vector2i cand = m.pos + kDirs[ccb.rng_range(0, 3)];
                if (cand != player_pos && can_step_tile(cand, m.floor) &&
                    spatial.find(tile_key(cand, m.floor)) == spatial.end()) {
                    next = cand;
                }
            }

            if (next != m.pos) {
                spatial.erase(tile_key(m.pos, m.floor));
                m.pos = next;
                spatial[tile_key(m.pos, m.floor)] = static_cast<int>(i);
            }
        }
    }

    char_state.last_sound = std::max(0, char_state.last_sound - 3);
    return res;
}

MonsterAttackResult MonsterManager::player_attack(
    Vector2i target,
    int z,
    CharacterState &char_state,
    CcbSurvivalState &ccb,
    int &kills_counter) {
    MonsterAttackResult res;
    MonsterInstance *m = at_mut(target, z);
    if (!m) return res;

    const auto &db = CcbVanillaDB::instance();
    const auto *mdef = db.find_monster(m->species_id);
    const auto *wdef = ccb.wielded.empty() ? nullptr : db.find_item(ccb.wielded);
    const auto mods = ccb.compute_mods();

    const int eff_str = std::max(1, char_state.stat_str + mods.str_mod);
    const int eff_dex = std::max(1, char_state.stat_dex + mods.dex_mod);
    const String mname = String::utf8(mdef ? mdef->name.c_str() : m->species_id.c_str());
    const String wname = wdef ? String::utf8(wdef->name_zh.c_str()) : String::utf8("空手");

    // 1. Exact CCB hit_roll() vs monster dodge_roll() (melee.cpp:500-542)
    float hit_base = static_cast<float>(ccb.skills.melee) + static_cast<float>(eff_dex) * 0.5f +
                     static_cast<float>(wdef ? wdef->to_hit : 0) -
                     static_cast<float>(ccb.torso_encumbrance()) / 10.0f;
    if (char_state.move_mode == 3) hit_base -= 8.0f;
    else if (char_state.move_mode == 2) hit_base -= 2.0f;
    if (char_state.pain > 20) hit_base -= static_cast<float>(char_state.pain) / 25.0f;

    const float attack_roll = roll_ccb_bell(ccb, hit_base);
    const float mon_dodge = static_cast<float>(mdef ? mdef->dodge : 0) * 1.8f;
    const float hit_spread = attack_roll - mon_dodge;

    char_state.spend_stamina(240);
    char_state.last_sound = 10;
    m->alerted = true;
    m->last_target = target;

    // Train melee + weapon skill (exact melee_train in melee.cpp:635)
    ccb.skills.train(0, 12);
    if (!wdef) ccb.skills.train(4, 16);
    else if (wdef->stab >= wdef->cut && wdef->stab >= wdef->bash && wdef->stab > 0) ccb.skills.train(3, 16);
    else if (wdef->cut >= wdef->bash && wdef->cut > 0) ccb.skills.train(2, 16);
    else ccb.skills.train(1, 16);

    if (hit_spread < -2.5f) {
        res.hit = false;
        res.message = String::utf8("你挥动「") + wname + String::utf8("」攻向「") + mname + String::utf8("」，但打空了！");
        return res;
    }

    // 2. Critical hit determination
    const bool crit = (hit_spread >= 6.5f) || (hit_spread >= 3.5f && ccb.one_in(4));
    res.hit = true;
    res.crit = crit;

    // 3. Multi-type damage calculation (exact roll_melee_damage_internal in melee.cpp:1762)
    float bash_raw = static_cast<float>(wdef ? wdef->bash : 2) +
                     static_cast<float>(ccb.rng_range(eff_str / 2, eff_str));
    const int bash_sk = wdef ? ccb.skills.bashing : ccb.skills.unarmed;
    const float bash_cap = static_cast<float>(2 * eff_str + 2 * bash_sk);
    if (wdef && bash_cap < bash_raw) {
        bash_raw *= (1.0f + (bash_cap / bash_raw)) * 0.5f;
    }
    const float low_cap = std::min(1.0f, static_cast<float>(eff_str) / 20.0f);
    bash_raw = bash_raw * (low_cap + (1.0f - low_cap) * (static_cast<float>(ccb.rng_range(0, 100)) * 0.01f));

    float cut_raw = static_cast<float>(wdef ? wdef->cut : mods.unarmed_cut) *
                    (1.0f + static_cast<float>(ccb.skills.cutting) * 0.05f);
    float stab_raw = static_cast<float>(wdef ? wdef->stab : mods.unarmed_stab) *
                     (1.0f + static_cast<float>(ccb.skills.stabbing) * 0.06f);

    if (crit) {
        bash_raw *= 1.5f;
        cut_raw *= 1.65f;
        stab_raw *= 2.0f;
    }

    // Separate per-damage-type monster armor mitigation (exact damage.cpp)
    const int ab = mdef ? mdef->armor_bash : 0;
    const int ac = mdef ? mdef->armor_cut : 0;
    const int as = std::max(0, (mdef ? mdef->armor_stab : 0) - (crit ? 6 : 2)); // Stab penetrates armor on crit!

    const int dealt_b = std::max(0, static_cast<int>(std::round(bash_raw)) - ab);
    const int dealt_c = std::max(0, static_cast<int>(std::round(cut_raw)) - ac);
    const int dealt_s = std::max(0, static_cast<int>(std::round(stab_raw)) - as);
    const int total_dmg = std::max(1, dealt_b + dealt_c + dealt_s);

    m->hp -= total_dmg;
    res.damage = total_dmg;

    const String crit_tag = crit ? String::utf8("【暴击！】") : String();
    if (m->hp <= 0) {
        m->hp = 0;
        m->alive = false;
        spatial.erase(tile_key(m->pos, m->floor));
        ++kills_counter;
        res.killed = true;
        res.killed_species_id = m->species_id;
        res.drop_pos = m->pos;

        // Authentic vanilla CCB monster death_drops (from monsterdrops.json & monsters.json)!
        res.drops = db.roll_death_drops(m->species_id, [&](int lo, int hi) {
            return ccb.rng_range(lo, hi);
        });
        res.message = crit_tag + String::utf8("你以「") + wname + String::utf8("」击中「") + mname +
                      String::utf8("」（钝") + String::num_int64(dealt_b) + String::utf8("/斩") +
                      String::num_int64(dealt_c) + String::utf8("/刺") + String::num_int64(dealt_s) +
                      String::utf8(" = ") + String::num_int64(total_dmg) + String::utf8("），将其击毙！");
    } else {
        res.message = crit_tag + String::utf8("你以「") + wname + String::utf8("」击中「") + mname +
                      String::utf8("」，造成 ") + String::num_int64(total_dmg) +
                      String::utf8(" 点伤害（剩余 ") + String::num_int64(m->hp) + String("/") +
                      String::num_int64(m->max_hp) + String::utf8("）。");
    }
    return res;
}

bool MonsterManager::apply_remote_hit(Vector2i target, int z, int dmg) {
    MonsterInstance *m = at_mut(target, z);
    if (!m || dmg <= 0) return false;
    m->alerted = true;
    m->hp -= dmg;
    if (m->hp <= 0) {
        m->hp = 0;
        m->alive = false;
        spatial.erase(tile_key(m->pos, m->floor));
    }
    return true;
}

Array MonsterManager::save_array() const {
    Array out;
    for (const auto &m : list) {
        if (!m.alive) continue;
        Dictionary d;
        d["id"] = m.id;
        d["sid"] = String::utf8(m.species_id.c_str());
        d["x"] = m.pos.x;
        d["y"] = m.pos.y;
        d["z"] = m.floor;
        d["hp"] = m.hp;
        d["max_hp"] = m.max_hp;
        d["a"] = m.alerted ? 1 : 0;
        out.append(d);
    }
    return out;
}

void MonsterManager::load_array(const Array &arr) {
    clear();
    list.reserve(static_cast<std::size_t>(arr.size()));
    for (int i = 0; i < arr.size(); ++i) {
        if (arr[i].get_type() != Variant::DICTIONARY) continue;
        const Dictionary d = arr[i];
        MonsterInstance m;
        m.id = static_cast<int>(d.get("id", next_id));
        next_id = std::max(next_id, m.id + 1);
        const String sid = d.get("sid", String("mon_zombie"));
        m.species_id = sid.is_empty() ? std::string("mon_zombie") : std::string(sid.utf8().get_data());
        m.pos = Vector2i(
            static_cast<int>(d.get("x", 0)),
            static_cast<int>(d.get("y", 0)));
        m.floor = static_cast<int>(d.get("z", 0));
        m.max_hp = std::max(10, static_cast<int>(d.get("max_hp", 80)));
        m.hp = std::clamp(static_cast<int>(d.get("hp", m.max_hp)), 1, m.max_hp);
        m.alerted = static_cast<int>(d.get("a", 0)) != 0;
        m.alive = true;
        m.last_target = m.pos;
        list.push_back(std::move(m));
    }
    rebuild_spatial();
}

} // namespace cangling
