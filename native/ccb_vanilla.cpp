#include "ccb_vanilla.hpp"
#include "city.hpp"
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <mutex>

namespace cangling {
using namespace godot;

namespace {

std::vector<std::string> split_char(std::string_view s, char delim) {
    std::vector<std::string> out;
    if (s.empty()) return out;
    std::size_t start = 0;
    while (start <= s.size()) {
        const std::size_t pos = s.find(delim, start);
        if (pos == std::string_view::npos) {
            if (start < s.size()) out.emplace_back(s.substr(start));
            break;
        }
        if (pos > start) out.emplace_back(s.substr(start, pos - start));
        start = pos + 1;
    }
    return out;
}

std::vector<std::string> split_tsv_keep_empty(std::string_view line) {
    std::vector<std::string> out;
    out.reserve(32);
    std::size_t start = 0;
    while (true) {
        const std::size_t pos = line.find('\t', start);
        if (pos == std::string_view::npos) {
            out.emplace_back(line.substr(start));
            break;
        }
        out.emplace_back(line.substr(start, pos - start));
        start = pos + 1;
    }
    return out;
}

int parse_int_safe(const std::string &s, int fallback = 0) {
    if (s.empty()) return fallback;
    char *end = nullptr;
    const long val = std::strtol(s.c_str(), &end, 10);
    if (end == s.c_str()) return fallback;
    return static_cast<int>(val);
}

std::vector<std::string> json_str_array(const Dictionary &d, const char *key) {
    std::vector<std::string> out;
    const Variant v = d.get(key, Variant());
    if (v.get_type() != Variant::ARRAY) return out;
    const Array arr = v;
    out.reserve(static_cast<std::size_t>(arr.size()));
    for (int i = 0; i < arr.size(); ++i) {
        if (arr[i].get_type() == Variant::STRING) {
            out.emplace_back(String(arr[i]).utf8().get_data());
        }
    }
    return out;
}

int json_int(const Dictionary &d, const char *key, int fallback = 0) {
    const Variant v = d.get(key, Variant());
    if (v.get_type() == Variant::INT || v.get_type() == Variant::FLOAT) {
        return static_cast<int>(v);
    }
    return fallback;
}

std::string json_str(const Dictionary &d, const char *key, const char *fallback = "") {
    const Variant v = d.get(key, Variant());
    if (v.get_type() == Variant::STRING) {
        return std::string(String(v).utf8().get_data());
    }
    return fallback ? std::string(fallback) : std::string();
}

std::string to_lower_ascii(std::string_view s) {
    std::string out(s);
    for (char &c : out) {
        if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    }
    return out;
}

const char *part_name_cn(int p) {
    switch (p) {
        case 0: return "头部";
        case 1: return "躯干";
        case 2: return "左臂";
        case 3: return "右臂";
        case 4: return "左腿";
        default: return "右腿";
    }
}

} // namespace

bool CcbItemDef::has_flag(std::string_view f) const {
    return std::find(flags.begin(), flags.end(), f) != flags.end();
}

bool CcbItemDef::has_use_tag(std::string_view u) const {
    return std::find(use_tags.begin(), use_tags.end(), u) != use_tags.end();
}

bool CcbMutationDef::in_category(std::string_view cat) const {
    return std::find(category.begin(), category.end(), cat) != category.end();
}

bool CcbMutationDef::has_flag(std::string_view f) const {
    return std::find(flags.begin(), flags.end(), f) != flags.end();
}

bool CcbMonsterDef::has_flag(std::string_view f) const {
    return std::find(flags.begin(), flags.end(), f) != flags.end();
}

bool CcbMonsterDef::has_special(std::string_view s) const {
    for (const auto &sp : special_attacks) {
        if (sp == s || sp.find(s) != std::string::npos) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// CcbVanillaDB: loads all 10,366 vanilla items, 591 mutations & 1,193 monsters
// ---------------------------------------------------------------------------
const CcbVanillaDB &CcbVanillaDB::instance() {
    static std::mutex mu;
    static CcbVanillaDB db;
    std::lock_guard<std::mutex> lock(mu);
    db.ensure_loaded();
    return db;
}

void CcbVanillaDB::ensure_loaded() {
    if (loaded) return;
    loaded = true;
    load_items_tsv();
    load_mutations_json();
    load_monsters_json();
    load_monsterdrops_json();
    load_harvest_json();
    load_scenarios_json();
    load_professions_json();
    load_skills_json();
    load_recipes_json();
}

void CcbVanillaDB::load_items_tsv() {
    const char *path = "res://packs/cataclysm/vanilla/items.tsv";
    if (!FileAccess::file_exists(path)) return;
    const String content = FileAccess::get_file_as_string(path);
    const std::string raw = content.utf8().get_data();
    items_.reserve(10500);
    item_idx_.reserve(16000);

    std::size_t pos = 0;
    bool first_line = true;
    while (pos < raw.size()) {
        std::size_t nl = raw.find('\n', pos);
        if (nl == std::string::npos) nl = raw.size();
        std::size_t end = nl;
        if (end > pos && raw[end - 1] == '\r') --end;
        const std::string_view line(raw.data() + pos, end - pos);
        pos = nl + 1;

        if (first_line) {
            first_line = false;
            continue;
        }
        if (line.empty()) continue;
        const auto cols = split_tsv_keep_empty(line);
        if (cols.size() < 29) continue;

        CcbItemDef it;
        it.id = cols[0];
        it.name_zh = cols[1];
        it.name_en = cols[2];
        it.subtype = cols[3];
        it.category = cols[4];
        it.weight_g = parse_int_safe(cols[5]);
        it.vol_ml = parse_int_safe(cols[6]);
        it.bash = parse_int_safe(cols[7]);
        it.cut = parse_int_safe(cols[8]);
        it.stab = parse_int_safe(cols[9]);
        it.to_hit = parse_int_safe(cols[10]);
        it.kcal = parse_int_safe(cols[11]);
        it.quench = parse_int_safe(cols[12]);
        it.fun = parse_int_safe(cols[13]);
        it.healthy = parse_int_safe(cols[14]);
        it.comestible_type = cols[15];
        it.covers_mask = parse_int_safe(cols[16]);
        it.encumbrance = parse_int_safe(cols[17]);
        it.warmth = parse_int_safe(cols[18]);
        it.env_resist = parse_int_safe(cols[19]);
        it.storage_ml = parse_int_safe(cols[20]);
        it.armor_bash = parse_int_safe(cols[21]);
        it.armor_cut = parse_int_safe(cols[22]);
        it.armor_stab = parse_int_safe(cols[23]);
        it.coverage = parse_int_safe(cols[24]);
        it.flags = split_char(cols[25], ',');
        for (const auto &kv : split_char(cols[26], ',')) {
            const auto colon = kv.find(':');
            if (colon != std::string::npos) {
                it.vitamins.emplace_back(kv.substr(0, colon), parse_int_safe(kv.substr(colon + 1)));
            }
        }
        it.use_tags = split_char(cols[27], ',');
        it.tile = cols[28];
        if (cols.size() > 29) it.desc = cols[29];

        const int idx = static_cast<int>(items_.size());
        item_idx_[it.id] = idx;
        items_.push_back(std::move(it));
    }
}

void CcbVanillaDB::load_mutations_json() {
    const char *path = "res://packs/cataclysm/vanilla/mutations.json";
    if (!FileAccess::file_exists(path)) return;
    const Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(path));
    if (parsed.get_type() != Variant::DICTIONARY) return;
    const Dictionary root = parsed;

    const Variant cv = root.get("categories", Variant());
    if (cv.get_type() == Variant::ARRAY) {
        const Array carr = cv;
        for (int i = 0; i < carr.size(); ++i) {
            if (carr[i].get_type() != Variant::DICTIONARY) continue;
            const Dictionary cd = carr[i];
            CcbMutationCategoryDef c;
            c.id = json_str(cd, "id");
            c.name = json_str(cd, "name", c.id.c_str());
            c.threshold_mut = json_str(cd, "threshold_mut");
            c.vitamin = json_str(cd, "vitamin");
            c.mutagen_message = json_str(cd, "mutagen_message", "你感到身体正在发生异变。");
            c.threshold_min = json_int(cd, "threshold_min", 2200);
            mut_cat_idx_[c.id] = static_cast<int>(mut_cats_.size());
            mut_cats_.push_back(std::move(c));
        }
    }

    const Variant mv = root.get("mutations", Variant());
    if (mv.get_type() == Variant::ARRAY) {
        const Array marr = mv;
        muts_.reserve(static_cast<std::size_t>(marr.size()));
        for (int i = 0; i < marr.size(); ++i) {
            if (marr[i].get_type() != Variant::DICTIONARY) continue;
            const Dictionary md = marr[i];
            CcbMutationDef m;
            m.id = json_str(md, "id");
            m.name = json_str(md, "name", m.id.c_str());
            m.desc = json_str(md, "desc");
            m.points = json_int(md, "points", 0);
            m.starting_trait = static_cast<bool>(md.get("starting_trait", false));
            m.profession = static_cast<bool>(md.get("profession", false));
            m.valid = static_cast<bool>(md.get("valid", true));
            m.purifiable = static_cast<bool>(md.get("purifiable", true));
            m.threshold = static_cast<bool>(md.get("threshold", false));
            m.threshreq = json_str_array(md, "threshreq");
            m.category = json_str_array(md, "category");
            m.prereqs = json_str_array(md, "prereqs");
            m.prereqs2 = json_str_array(md, "prereqs2");
            m.cancels = json_str_array(md, "cancels");
            m.changes_to = json_str_array(md, "changes_to");
            m.flags = json_str_array(md, "flags");
            m.vitamin_cost = json_int(md, "vitamin_cost", 100);
            mut_idx_[m.id] = static_cast<int>(muts_.size());
            muts_.push_back(std::move(m));
        }
    }
}

void CcbVanillaDB::load_monsters_json() {
    const char *path = "res://packs/cataclysm/vanilla/monsters.json";
    if (!FileAccess::file_exists(path)) return;
    const Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(path));
    if (parsed.get_type() != Variant::DICTIONARY) return;
    const Dictionary root = parsed;
    const Variant mv = root.get("monsters", Variant());
    if (mv.get_type() != Variant::ARRAY) return;
    const Array marr = mv;
    mons_.reserve(static_cast<std::size_t>(marr.size()));
    for (int i = 0; i < marr.size(); ++i) {
        if (marr[i].get_type() != Variant::DICTIONARY) continue;
        const Dictionary md = marr[i];
        CcbMonsterDef m;
        m.id = json_str(md, "id");
        m.name = json_str(md, "name", m.id.c_str());
        m.desc = json_str(md, "desc");
        m.looks_like = json_str(md, "looks_like");
        m.hp = std::max(1, json_int(md, "hp", 70));
        m.speed = std::max(10, json_int(md, "speed", 75));
        m.melee_skill = json_int(md, "melee_skill", 3);
        m.melee_dice = std::max(1, json_int(md, "melee_dice", 2));
        m.melee_dice_sides = std::max(1, json_int(md, "melee_dice_sides", 4));
        m.dodge = json_int(md, "dodge", 0);
        m.armor_bash = json_int(md, "armor_bash", 0);
        m.armor_cut = json_int(md, "armor_cut", 0);
        m.armor_stab = json_int(md, "armor_stab", 0);
        m.vision_day = json_int(md, "vision_day", 30);
        m.vision_night = json_int(md, "vision_night", 5);
        m.aggression = json_int(md, "aggression", 100);
        m.weight_g = std::max(100, json_int(md, "weight_g", 81500));
        m.filthy_drops = static_cast<bool>(md.get("filthy_drops", true));
        m.species = json_str_array(md, "species");
        m.flags = json_str_array(md, "flags");
        m.special_attacks = json_str_array(md, "special_attacks");
        m.harvest = json_str(md, "harvest");
        m.death_drops = json_str(md, "death_drops");
        mon_idx_[m.id] = static_cast<int>(mons_.size());
        mons_.push_back(std::move(m));
    }
}

namespace {

CcbLootEntry parse_loot_entry_dict(const Dictionary &ed) {
    CcbLootEntry e;
    e.item_id = json_str(ed, "i");
    e.group_id = json_str(ed, "g");
    e.prob = json_int(ed, "p", 100);
    const Variant nv = ed.get("n", Variant());
    if (nv.get_type() == Variant::ARRAY) {
        const Array na = nv;
        if (na.size() >= 2) {
            e.count_min = std::max(1, static_cast<int>(na[0]));
            e.count_max = std::max(e.count_min, static_cast<int>(na[1]));
        }
    }
    const Variant dv = ed.get("dm", Variant());
    if (dv.get_type() == Variant::ARRAY) {
        const Array da = dv;
        if (da.size() >= 2) {
            e.dmg_min = std::clamp(static_cast<int>(da[0]), 0, 4);
            e.dmg_max = std::clamp(static_cast<int>(da[1]), e.dmg_min, 4);
            e.has_dmg = true;
        }
    }
    const Variant cv = ed.get("c", Variant());
    if (cv.get_type() == Variant::ARRAY) {
        e.sub_is_collection = true;
        const Array ca = cv;
        e.sub_entries.reserve(static_cast<std::size_t>(ca.size()));
        for (int i = 0; i < ca.size(); ++i) {
            if (ca[i].get_type() == Variant::DICTIONARY) {
                e.sub_entries.push_back(parse_loot_entry_dict(ca[i]));
            }
        }
    }
    const Variant dvv = ed.get("d", Variant());
    if (dvv.get_type() == Variant::ARRAY) {
        e.sub_is_collection = false;
        const Array da = dvv;
        e.sub_entries.reserve(static_cast<std::size_t>(da.size()));
        for (int i = 0; i < da.size(); ++i) {
            if (da[i].get_type() == Variant::DICTIONARY) {
                e.sub_entries.push_back(parse_loot_entry_dict(da[i]));
            }
        }
    }
    return e;
}

} // namespace

void CcbVanillaDB::load_monsterdrops_json() {
    const char *path = "res://packs/cataclysm/vanilla/monsterdrops.json";
    if (!FileAccess::file_exists(path)) return;
    const Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(path));
    if (parsed.get_type() != Variant::DICTIONARY) return;
    const Dictionary root = parsed;
    const Variant gv = root.get("groups", Variant());
    if (gv.get_type() != Variant::DICTIONARY) return;
    const Dictionary gdict = gv;
    const Array keys = gdict.keys();
    loot_groups_.reserve(static_cast<std::size_t>(keys.size()) * 2u);
    for (int i = 0; i < keys.size(); ++i) {
        const String ks = keys[i];
        const Variant v = gdict[ks];
        if (v.get_type() != Variant::DICTIONARY) continue;
        const Dictionary gd = v;
        CcbLootGroup grp;
        grp.is_collection = (json_str(gd, "s", "d") == "c");
        const Variant ev = gd.get("e", Variant());
        if (ev.get_type() == Variant::ARRAY) {
            const Array earr = ev;
            grp.entries.reserve(static_cast<std::size_t>(earr.size()));
            for (int k = 0; k < earr.size(); ++k) {
                if (earr[k].get_type() == Variant::DICTIONARY) {
                    grp.entries.push_back(parse_loot_entry_dict(earr[k]));
                }
            }
        }
        loot_groups_[std::string(ks.utf8().get_data())] = std::move(grp);
    }
}

void CcbVanillaDB::load_harvest_json() {
    const char *path = "res://packs/cataclysm/vanilla/harvest.json";
    if (!FileAccess::file_exists(path)) return;
    const Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(path));
    if (parsed.get_type() != Variant::DICTIONARY) return;
    const Dictionary root = parsed;
    const Variant hv = root.get("harvest", Variant());
    if (hv.get_type() != Variant::DICTIONARY) return;
    const Dictionary hdict = hv;
    const Array keys = hdict.keys();
    for (int i = 0; i < keys.size(); ++i) {
        const String ks = keys[i];
        const Variant v = hdict[ks];
        if (v.get_type() != Variant::ARRAY) continue;
        const Array arr = v;
        std::vector<CcbHarvestEntry> list;
        for (int k = 0; k < arr.size(); ++k) {
            if (arr[k].get_type() != Variant::DICTIONARY) continue;
            const Dictionary ed = arr[k];
            CcbHarvestEntry he;
            he.drop_id = json_str(ed, "drop");
            he.type = json_str(ed, "type", "flesh");
            const Variant mrv = ed.get("mr", Variant());
            if (mrv.get_type() == Variant::FLOAT || mrv.get_type() == Variant::INT) {
                he.mass_ratio = static_cast<float>(static_cast<double>(mrv));
            }
            const Variant bnv = ed.get("bn", Variant());
            if (bnv.get_type() == Variant::ARRAY) {
                const Array ba = bnv;
                if (ba.size() >= 2) {
                    he.base_min = static_cast<int>(ba[0]);
                    he.base_max = static_cast<int>(ba[1]);
                }
            }
            if (!he.drop_id.empty()) list.push_back(std::move(he));
        }
        if (!list.empty()) {
            harvests_[std::string(ks.utf8().get_data())] = std::move(list);
        }
    }
}

void CcbVanillaDB::eval_loot_entry(
    const CcbLootEntry &ent,
    const std::function<int(int, int)> &rng_range,
    std::vector<CcbItemStack> &out,
    int depth,
    int inherited_dmg_min,
    int inherited_dmg_max,
    bool inherited_has_dmg) const {
    if (depth > 24 || out.size() >= 20u) return;
    const bool use_dmg = ent.has_dmg || inherited_has_dmg;
    const int dmin = ent.has_dmg ? ent.dmg_min : inherited_dmg_min;
    const int dmax = ent.has_dmg ? ent.dmg_max : inherited_dmg_max;
    const int repeats = (ent.count_max > ent.count_min) ? rng_range(ent.count_min, ent.count_max) : std::max(1, ent.count_min);

    if (!ent.item_id.empty()) {
        if (!find_item(ent.item_id)) return;
        const int dmg = use_dmg ? rng_range(dmin, dmax) : 0;
        out.push_back({ent.item_id, std::clamp(repeats, 1, 12), 0, false, std::clamp(dmg, 0, 4)});
        return;
    }
    if (!ent.group_id.empty()) {
        const auto git = loot_groups_.find(ent.group_id);
        if (git == loot_groups_.end()) return;
        for (int r = 0; r < std::min(repeats, 4) && out.size() < 20u; ++r) {
            eval_loot_group(git->second, rng_range, out, depth + 1, dmin, dmax, use_dmg);
        }
        return;
    }
    if (!ent.sub_entries.empty()) {
        CcbLootGroup sub;
        sub.is_collection = ent.sub_is_collection;
        sub.entries = ent.sub_entries;
        for (int r = 0; r < std::min(repeats, 4) && out.size() < 20u; ++r) {
            eval_loot_group(sub, rng_range, out, depth + 1, dmin, dmax, use_dmg);
        }
    }
}

void CcbVanillaDB::eval_loot_group(
    const CcbLootGroup &grp,
    const std::function<int(int, int)> &rng_range,
    std::vector<CcbItemStack> &out,
    int depth,
    int inherited_dmg_min,
    int inherited_dmg_max,
    bool inherited_has_dmg) const {
    if (depth > 24 || grp.entries.empty() || out.size() >= 20u) return;
    if (grp.is_collection) {
        for (const auto &ent : grp.entries) {
            if (out.size() >= 20u) break;
            if (ent.prob >= 100 || rng_range(1, 100) <= ent.prob) {
                eval_loot_entry(ent, rng_range, out, depth, inherited_dmg_min, inherited_dmg_max, inherited_has_dmg);
            }
        }
    } else {
        int total_w = 0;
        for (const auto &ent : grp.entries) total_w += std::max(1, ent.prob);
        if (total_w <= 0) return;
        int roll = rng_range(0, total_w - 1);
        for (const auto &ent : grp.entries) {
            const int w = std::max(1, ent.prob);
            if (roll < w) {
                eval_loot_entry(ent, rng_range, out, depth, inherited_dmg_min, inherited_dmg_max, inherited_has_dmg);
                break;
            }
            roll -= w;
        }
    }
}

std::vector<CcbItemStack> CcbVanillaDB::roll_death_drops(
    const std::string &mtype_id,
    const std::function<int(int, int)> &rng_range) const {
    std::vector<CcbItemStack> out;
    const auto *mdef = find_monster(mtype_id);
    if (!mdef || mdef->death_drops.empty()) return out;
    const auto git = loot_groups_.find(mdef->death_drops);
    if (git == loot_groups_.end()) return out;
    eval_loot_group(git->second, rng_range, out, 0, 0, 0, false);

    // Exact vanilla monster::drop_items_on_death(): clothing dropped by ZOMBIE/FILTHY monsters gets FILTHY + wear!
    if (mdef->filthy_drops) {
        for (auto &st : out) {
            const auto *idef = find_item(st.id);
            if (!idef) continue;
            if (idef->subtype == "ARMOR" || idef->covers_mask != 0) {
                st.filthy = true;
                if (st.damage == 0) st.damage = rng_range(1, 3);
            }
        }
    }
    return out;
}

std::vector<CcbItemStack> CcbVanillaDB::roll_harvest(
    const std::string &mtype_id,
    const std::function<int(int, int)> &rng_range) const {
    std::vector<CcbItemStack> out;
    const auto *mdef = find_monster(mtype_id);
    if (!mdef || mdef->harvest.empty()) return out;
    const auto hit = harvests_.find(mdef->harvest);
    if (hit == harvests_.end()) return out;
    for (const auto &he : hit->second) {
        const auto *idef = find_item(he.drop_id);
        if (!idef) continue;
        int cnt = 0;
        if (he.mass_ratio > 0.0f) {
            const float target_g = static_cast<float>(mdef->weight_g) * he.mass_ratio;
            const float unit_g = static_cast<float>(std::max(50, idef->weight_g));
            cnt = std::max(1, static_cast<int>(std::round(target_g / unit_g)));
            cnt = std::min(cnt, 10);
        } else if (he.base_max > 0) {
            cnt = std::max(1, rng_range(std::max(1, he.base_min), std::min(10, he.base_max)));
        } else {
            cnt = 1;
        }
        if (cnt > 0) {
            out.push_back({he.drop_id, cnt, 0, false, 0});
        }
    }
    return out;
}

void CcbVanillaDB::load_scenarios_json() {
    const char *path = "res://packs/cataclysm/vanilla/scenarios.json";
    if (!FileAccess::file_exists(path)) return;
    const Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(path));
    if (parsed.get_type() != Variant::DICTIONARY) return;
    const Dictionary root = parsed;
    const Variant sv = root.get("scenarios", Variant());
    if (sv.get_type() != Variant::ARRAY) return;
    const Array sarr = sv;
    scenarios_.reserve(static_cast<std::size_t>(sarr.size()));
    for (int i = 0; i < sarr.size(); ++i) {
        if (sarr[i].get_type() != Variant::DICTIONARY) continue;
        const Dictionary sd = sarr[i];
        CcbScenarioDef s;
        s.id = json_str(sd, "id");
        s.name = json_str(sd, "name", s.id.c_str());
        s.desc = json_str(sd, "desc");
        s.points = json_int(sd, "points", 0);
        s.start_name = json_str(sd, "start_name", "避难所");
        s.start_omt = json_str(sd, "start_omt", "shelter");
        s.allowed_locs = json_str_array(sd, "allowed_locs");
        s.professions = json_str_array(sd, "professions");
        s.forced_traits = json_str_array(sd, "forced_traits");
        s.traits = json_str_array(sd, "traits");
        s.flags = json_str_array(sd, "flags");
        scen_idx_[s.id] = static_cast<int>(scenarios_.size());
        scenarios_.push_back(std::move(s));
    }
}

void CcbVanillaDB::load_professions_json() {
    const char *path = "res://packs/cataclysm/vanilla/professions.json";
    if (!FileAccess::file_exists(path)) return;
    const Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(path));
    if (parsed.get_type() != Variant::DICTIONARY) return;
    const Dictionary root = parsed;
    const Variant pv = root.get("professions", Variant());
    if (pv.get_type() != Variant::ARRAY) return;
    const Array parr = pv;
    professions_.reserve(static_cast<std::size_t>(parr.size()));
    for (int i = 0; i < parr.size(); ++i) {
        if (parr[i].get_type() != Variant::DICTIONARY) continue;
        const Dictionary pd = parr[i];
        CcbProfessionDef p;
        p.id = json_str(pd, "id");
        p.name = json_str(pd, "name", p.id.c_str());
        p.desc = json_str(pd, "desc");
        p.points = json_int(pd, "points", 0);
        p.is_hobby = static_cast<bool>(pd.get("is_hobby", false));
        p.worn = json_str_array(pd, "worn");
        p.wielded = json_str(pd, "wielded");
        p.bag = json_str_array(pd, "bag");
        p.traits = json_str_array(pd, "traits");
        p.flags = json_str_array(pd, "flags");
        const Variant skv = pd.get("skills", Variant());
        if (skv.get_type() == Variant::ARRAY) {
            const Array skarr = skv;
            for (int k = 0; k < skarr.size(); ++k) {
                if (skarr[k].get_type() != Variant::DICTIONARY) continue;
                const Dictionary skd = skarr[k];
                const std::string sn = json_str(skd, "name");
                const int lv = json_int(skd, "level", 1);
                if (!sn.empty() && lv > 0) p.skills.emplace_back(sn, lv);
            }
        }
        prof_idx_[p.id] = static_cast<int>(professions_.size());
        professions_.push_back(std::move(p));
    }
}

void CcbVanillaDB::load_skills_json() {
    const char *path = "res://packs/cataclysm/vanilla/skills.json";
    if (!FileAccess::file_exists(path)) return;
    const Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(path));
    if (parsed.get_type() != Variant::DICTIONARY) return;
    const Dictionary root = parsed;
    const Variant sv = root.get("skills", Variant());
    if (sv.get_type() != Variant::ARRAY) return;
    const Array sarr = sv;
    skills_.reserve(static_cast<std::size_t>(sarr.size()));
    for (int i = 0; i < sarr.size(); ++i) {
        if (sarr[i].get_type() != Variant::DICTIONARY) continue;
        const Dictionary sd = sarr[i];
        CcbSkillDef s;
        s.id = json_str(sd, "id");
        s.name = json_str(sd, "name", s.id.c_str());
        s.desc = json_str(sd, "desc");
        s.category = json_str(sd, "category");
        s.sort_rank = json_int(sd, "sort_rank", 10000);
        skill_idx_[s.id] = static_cast<int>(skills_.size());
        skills_.push_back(std::move(s));
    }
}

void CcbVanillaDB::load_recipes_json() {
    const char *path = "res://packs/cataclysm/vanilla/recipes.json";
    if (!FileAccess::file_exists(path)) return;
    const Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(path));
    if (parsed.get_type() != Variant::DICTIONARY) return;
    const Dictionary root = parsed;
    const Variant rv = root.get("recipes", Variant());
    if (rv.get_type() != Variant::ARRAY) return;
    const Array rarr = rv;
    recipes_.reserve(static_cast<std::size_t>(rarr.size()));
    for (int i = 0; i < rarr.size(); ++i) {
        if (rarr[i].get_type() != Variant::DICTIONARY) continue;
        const Dictionary rd = rarr[i];
        CcbRecipeDef r;
        r.id = json_str(rd, "id");
        r.result = json_str(rd, "result");
        r.charges = std::max(1, json_int(rd, "charges", 1));
        r.category = json_str(rd, "category", "CC_OTHER");
        r.subcategory = json_str(rd, "subcategory");
        r.skill_used = json_str(rd, "skill_used", "survival");
        r.difficulty = json_int(rd, "difficulty", 0);
        r.time_min = std::max(1, json_int(rd, "time_min", 5));
        r.autolearn = static_cast<bool>(rd.get("autolearn", false));
        const Variant cv = rd.get("components", Variant());
        if (cv.get_type() == Variant::ARRAY) {
            const Array carr = cv;
            for (int c = 0; c < carr.size(); ++c) {
                if (carr[c].get_type() != Variant::ARRAY) continue;
                const Array alts = carr[c];
                std::vector<std::pair<std::string, int>> slot;
                for (int a = 0; a < alts.size(); ++a) {
                    if (alts[a].get_type() != Variant::ARRAY) continue;
                    const Array pair = alts[a];
                    if (pair.size() >= 2) {
                        slot.emplace_back(String(pair[0]).utf8().get_data(), std::max(1, static_cast<int>(pair[1])));
                    }
                }
                if (!slot.empty()) r.components.push_back(std::move(slot));
            }
        }
        if (r.id.empty() || r.result.empty()) continue;
        recipe_idx_[r.id] = static_cast<int>(recipes_.size());
        recipes_.push_back(std::move(r));
    }
}

const CcbItemDef *CcbVanillaDB::find_item(std::string_view id) const {
    const auto it = item_idx_.find(std::string(id));
    return it == item_idx_.end() ? nullptr : &items_[static_cast<std::size_t>(it->second)];
}

const CcbMutationDef *CcbVanillaDB::find_mutation(std::string_view id) const {
    const auto it = mut_idx_.find(std::string(id));
    return it == mut_idx_.end() ? nullptr : &muts_[static_cast<std::size_t>(it->second)];
}

const CcbMutationCategoryDef *CcbVanillaDB::find_mutation_category(std::string_view id) const {
    const auto it = mut_cat_idx_.find(std::string(id));
    return it == mut_cat_idx_.end() ? nullptr : &mut_cats_[static_cast<std::size_t>(it->second)];
}

const CcbMutationCategoryDef *CcbVanillaDB::find_category_by_vitamin(std::string_view vit) const {
    for (const auto &c : mut_cats_) {
        if (!c.vitamin.empty() && c.vitamin == vit) return &c;
    }
    return nullptr;
}

const CcbMonsterDef *CcbVanillaDB::find_monster(std::string_view id) const {
    const auto it = mon_idx_.find(std::string(id));
    return it == mon_idx_.end() ? nullptr : &mons_[static_cast<std::size_t>(it->second)];
}

const CcbScenarioDef *CcbVanillaDB::find_scenario(std::string_view id) const {
    const auto it = scen_idx_.find(std::string(id));
    return it == scen_idx_.end() ? nullptr : &scenarios_[static_cast<std::size_t>(it->second)];
}

const CcbProfessionDef *CcbVanillaDB::find_profession(std::string_view id) const {
    const auto it = prof_idx_.find(std::string(id));
    return it == prof_idx_.end() ? nullptr : &professions_[static_cast<std::size_t>(it->second)];
}

const CcbSkillDef *CcbVanillaDB::find_skill(std::string_view id) const {
    const auto it = skill_idx_.find(std::string(id));
    return it == skill_idx_.end() ? nullptr : &skills_[static_cast<std::size_t>(it->second)];
}

const CcbRecipeDef *CcbVanillaDB::find_recipe(std::string_view id) const {
    const auto it = recipe_idx_.find(std::string(id));
    return it == recipe_idx_.end() ? nullptr : &recipes_[static_cast<std::size_t>(it->second)];
}

Array CcbVanillaDB::list_scenarios_array() const {
    Array out;
    for (const auto &s : scenarios_) {
        Dictionary d;
        d["id"] = String::utf8(s.id.c_str());
        d["name"] = String::utf8(s.name.c_str());
        d["desc"] = String::utf8(s.desc.c_str());
        d["points"] = s.points;
        d["start_name"] = String::utf8(s.start_name.c_str());
        d["start_omt"] = String::utf8(s.start_omt.c_str());
        Array profs;
        for (const auto &p : s.professions) profs.append(String::utf8(p.c_str()));
        d["professions"] = profs;
        Array ftr;
        for (const auto &t : s.forced_traits) ftr.append(String::utf8(t.c_str()));
        d["forced_traits"] = ftr;
        out.append(d);
    }
    return out;
}

Array CcbVanillaDB::list_professions_array(bool hobbies_only) const {
    Array out;
    for (const auto &p : professions_) {
        if (p.is_hobby != hobbies_only) continue;
        Dictionary d;
        d["id"] = String::utf8(p.id.c_str());
        d["name"] = String::utf8(p.name.c_str());
        d["desc"] = String::utf8(p.desc.c_str());
        d["points"] = p.points;
        d["is_hobby"] = p.is_hobby;
        d["wielded"] = String::utf8(p.wielded.c_str());
        Array worn_a, worn_ids_a, bag_a, sk_a, tr_a;
        for (const auto &w : p.worn) {
            const auto *it = find_item(w);
            worn_a.append(it ? String::utf8(it->name_zh.c_str()) : String::utf8(w.c_str()));
            worn_ids_a.append(String::utf8(w.c_str()));
        }
        for (const auto &b : p.bag) {
            const auto *it = find_item(b);
            bag_a.append(it ? String::utf8(it->name_zh.c_str()) : String::utf8(b.c_str()));
        }
        for (const auto &[sn, lv] : p.skills) {
            const auto *sd = find_skill(sn);
            Dictionary skd;
            skd["id"] = String::utf8(sn.c_str());
            skd["name"] = sd ? String::utf8(sd->name.c_str()) : String::utf8(sn.c_str());
            skd["level"] = lv;
            sk_a.append(skd);
        }
        for (const auto &t : p.traits) tr_a.append(String::utf8(t.c_str()));
        d["worn_names"] = worn_a;
        d["worn_ids"] = worn_ids_a;
        d["bag_names"] = bag_a;
        d["skills"] = sk_a;
        d["traits"] = tr_a;
        out.append(d);
    }
    return out;
}

Array CcbVanillaDB::list_starting_traits_array() const {
    Array out;
    for (const auto &m : muts_) {
        if (!m.starting_trait || m.threshold || m.profession) continue;
        Dictionary d;
        d["id"] = String::utf8(m.id.c_str());
        d["name"] = String::utf8(m.name.c_str());
        d["desc"] = String::utf8(m.desc.c_str());
        d["points"] = m.points;
        Array canc;
        for (const auto &c : m.cancels) canc.append(String::utf8(c.c_str()));
        d["cancels"] = canc;
        out.append(d);
    }
    return out;
}

Array CcbVanillaDB::list_skills_array() const {
    Array out;
    for (const auto &s : skills_) {
        Dictionary d;
        d["id"] = String::utf8(s.id.c_str());
        d["name"] = String::utf8(s.name.c_str());
        d["desc"] = String::utf8(s.desc.c_str());
        d["category"] = String::utf8(s.category.c_str());
        out.append(d);
    }
    return out;
}

Dictionary CcbVanillaDB::item_to_dict(const CcbItemDef &def) const {
    Dictionary d;
    d["id"] = String::utf8(def.id.c_str());
    d["name"] = String::utf8(def.name_zh.c_str());
    d["name_en"] = String::utf8(def.name_en.c_str());
    d["subtype"] = String::utf8(def.subtype.c_str());
    d["category"] = String::utf8(def.category.c_str());
    d["weight_g"] = def.weight_g;
    d["vol_ml"] = def.vol_ml;
    d["bash"] = def.bash;
    d["cut"] = def.cut;
    d["stab"] = def.stab;
    d["to_hit"] = def.to_hit;
    d["kcal"] = def.kcal;
    d["quench"] = def.quench;
    d["fun"] = def.fun;
    d["armor_bash"] = def.armor_bash;
    d["armor_cut"] = def.armor_cut;
    d["armor_stab"] = def.armor_stab;
    d["coverage"] = def.coverage;
    d["encumbrance"] = def.encumbrance;
    d["warmth"] = def.warmth;
    d["storage_ml"] = def.storage_ml;
    d["tile"] = String::utf8(def.tile.c_str());
    d["desc"] = String::utf8(def.desc.c_str());
    d["covers_mask"] = def.covers_mask;
    Array flg_a;
    for (const auto &fl : def.flags) flg_a.append(String::utf8(fl.c_str()));
    d["flags"] = flg_a;
    return d;
}

Dictionary CcbVanillaDB::stack_to_dict(const CcbItemStack &st) const {
    const auto *def = find_item(st.id);
    Dictionary d = def ? item_to_dict(*def) : Dictionary();
    d["id"] = String::utf8(st.id.c_str());
    String base_name = def ? String::utf8(def->name_zh.c_str()) : String::utf8(st.id.c_str());
    String prefix;
    if (st.damage == 1) prefix = String::utf8("| ");
    else if (st.damage == 2) prefix = String::utf8("\\ ");
    else if (st.damage == 3) prefix = String::utf8("/ ");
    else if (st.damage >= 4) prefix = String::utf8("X ");
    String suffix = st.filthy ? String::utf8(" (脏污)") : String();
    d["raw_name"] = base_name;
    d["name"] = prefix + base_name + suffix;
    d["count"] = st.count;
    d["filthy"] = st.filthy;
    d["damage"] = st.damage;
    return d;
}

Array CcbVanillaDB::search_items(const String &query, const String &subtype_filter, int limit) const {
    Array out;
    const int cap = std::clamp(limit, 1, 200);
    const std::string q_raw = query.strip_edges().utf8().get_data();
    const std::string q_low = to_lower_ascii(q_raw);
    const std::string sf = subtype_filter.strip_edges().utf8().get_data();

    for (const auto &it : items_) {
        if (!sf.empty() && sf != "ALL" && it.subtype != sf) continue;
        if (!q_low.empty()) {
            const bool match = (to_lower_ascii(it.id).find(q_low) != std::string::npos) ||
                               (to_lower_ascii(it.name_en).find(q_low) != std::string::npos) ||
                               (it.name_zh.find(q_raw) != std::string::npos);
            if (!match) continue;
        }
        out.append(item_to_dict(it));
        if (out.size() >= cap) break;
    }
    return out;
}

Dictionary CcbVanillaDB::db_stats_dict() const {
    Dictionary d;
    d["items"] = item_count();
    d["mutations"] = mutation_count();
    d["mutation_categories"] = mutation_category_count();
    d["monsters"] = monster_count();
    d["scenarios"] = scenario_count();
    d["professions"] = profession_count();
    d["skills"] = skill_count();
    d["recipes"] = recipe_count();
    d["monsterdrop_groups"] = loot_group_count();
    d["harvests"] = harvest_count();
    return d;
}

// ---------------------------------------------------------------------------
// CcbCombatSkills (Vanilla 0..10 skill scale)
// ---------------------------------------------------------------------------
void CcbCombatSkills::reset() {
    melee = bashing = cutting = stabbing = unarmed = dodge = firstaid = survival = 0;
    xp.fill(0);
}

int CcbCombatSkills::level(int idx) const {
    switch (idx) {
        case 0: return melee;
        case 1: return bashing;
        case 2: return cutting;
        case 3: return stabbing;
        case 4: return unarmed;
        case 5: return dodge;
        case 6: return firstaid;
        default: return survival;
    }
}

void CcbCombatSkills::train(int idx, int amount, int cap) {
    if (idx < 0 || idx >= 8 || amount <= 0) return;
    int *lv = nullptr;
    switch (idx) {
        case 0: lv = &melee; break;
        case 1: lv = &bashing; break;
        case 2: lv = &cutting; break;
        case 3: lv = &stabbing; break;
        case 4: lv = &unarmed; break;
        case 5: lv = &dodge; break;
        case 6: lv = &firstaid; break;
        default: lv = &survival; break;
    }
    if (*lv >= cap || *lv >= 10) return;
    xp[static_cast<std::size_t>(idx)] += amount;
    const int need = (*lv + 1) * 100;
    while (*lv < cap && *lv < 10 && xp[static_cast<std::size_t>(idx)] >= need) {
        xp[static_cast<std::size_t>(idx)] -= need;
        ++(*lv);
    }
}

Dictionary CcbCombatSkills::to_dict() const {
    Dictionary d;
    d["melee"] = melee;
    d["bashing"] = bashing;
    d["cutting"] = cutting;
    d["stabbing"] = stabbing;
    d["unarmed"] = unarmed;
    d["dodge"] = dodge;
    d["firstaid"] = firstaid;
    d["survival"] = survival;
    return d;
}

void CcbCombatSkills::load_dict(const Dictionary &d) {
    melee = json_int(d, "melee", 0);
    bashing = json_int(d, "bashing", 0);
    cutting = json_int(d, "cutting", 0);
    stabbing = json_int(d, "stabbing", 0);
    unarmed = json_int(d, "unarmed", 0);
    dodge = json_int(d, "dodge", 0);
    firstaid = json_int(d, "firstaid", 0);
    survival = json_int(d, "survival", 0);
}

// ---------------------------------------------------------------------------
// CcbSurvivalState: Faithful Vanilla CCB Radiation, Mutagen/Mutation & Gear
// ---------------------------------------------------------------------------
int CcbSurvivalState::rng_range(int lo, int hi) {
    if (lo >= hi) return lo;
    rng_state = rng_state * 1664525u + 1013904223u;
    const std::uint32_t span = static_cast<std::uint32_t>(hi - lo + 1);
    return lo + static_cast<int>((rng_state >> 8u) % span);
}

bool CcbSurvivalState::one_in(int n) {
    return n <= 1 || rng_range(0, n - 1) == 0;
}

bool CcbSurvivalState::x_in_y(int x, int y) {
    if (x <= 0) return false;
    if (x >= y) return true;
    return rng_range(0, y - 1) < x;
}

void CcbSurvivalState::reset(std::uint32_t seed, const std::string &scenario_id) {
    bag.clear();
    worn.clear();
    wielded.clear();
    world_items.clear();
    loot_materialized.clear();
    skills.reset();
    rad = 0;
    slow_rad = 0;
    iodine_min = 0;
    pblue_min = 0;
    rad_badge_rad = 0;
    last_tile_rad = 0.0f;
    bleed.fill(0);
    bite_min.fill(0);
    infected_min.fill(0);
    antibiotic_min = 0;
    grab_intensity = 0;
    rad_tick_accum = 0;
    mut_tick_accum = 0;
    rng_state = seed ? seed : 20260415u;
    vitamins.clear();
    mutations.clear();
    changing = false;
    corpses.clear();
    next_corpse_id = 1;
    blood_tiles.clear();
    all_skills.clear();
    seen_omts.clear();
    overmap_notes.clear();
    this->scenario_id = scenario_id.empty() ? std::string("evacuee") : scenario_id;
    profession_id = "unemployed";
    gender = "male";
    age = 25;

    const auto &db = CcbVanillaDB::instance();
    auto give = [&](const char *id, int n) {
        if (db.find_item(id)) add_bag_item(id, n);
    };
    auto equip = [&](const char *id) {
        if (db.find_item(id)) worn.emplace_back(id);
    };

    // Authentic CCB Evacuee / Scavenger starting kit using real vanilla item IDs
    equip("jeans");
    equip("tshirt");
    equip("sneakers");
    equip("backpack");
    equip("rad_badge");

    give("flashlight", 1);
    give("water_clean", 2);
    give("protein_bar_evac", 2);
    give("bandages", 2);
    give("antiseptic", 1);
    give("iodine", 2);
    give("prussian_blue", 2);
    give("geiger_off", 1);

    if (scenario_id == "scavenger") {
        if (db.find_item("crowbar")) wielded = "crowbar";
        equip("jacket_leather");
        give("antibiotics", 1);
        give("iv_mutagen", 1);
        give("iv_mutagen_beast", 1);
        give("purifier", 1);
        skills.melee = 2;
        skills.bashing = 2;
        skills.dodge = 1;
    } else {
        give("pocketknife", 1);
        give("crowbar", 1);
        if (db.find_item("crowbar")) {
            consume_bag_item("crowbar", 1);
            wielded = "crowbar";
        }
    }
}

void CcbSurvivalState::mark_omt_seen(Vector2i center_omt, int radius) {
    const int r = std::clamp(radius, 1, 12);
    for (int dy = -r; dy <= r; ++dy) {
        for (int dx = -r; dx <= r; ++dx) {
            if (dx * dx + dy * dy <= r * r + 2) {
                seen_omts.insert(infinite_tile_key(center_omt + Vector2i(dx, dy), 0));
            }
        }
    }
}

bool CcbSurvivalState::is_omt_seen(Vector2i omt) const {
    return seen_omts.count(infinite_tile_key(omt, 0)) > 0;
}

void CcbSurvivalState::set_overmap_note(Vector2i omt, const std::string &note) {
    const int64_t k = infinite_tile_key(omt, 0);
    if (note.empty()) overmap_notes.erase(k);
    else overmap_notes[k] = note;
}

std::string CcbSurvivalState::get_overmap_note(Vector2i omt) const {
    const auto it = overmap_notes.find(infinite_tile_key(omt, 0));
    return it == overmap_notes.end() ? std::string() : it->second;
}

void CcbSurvivalState::add_bag_item(const std::string &id, int count, bool filthy, int damage) {
    if (id.empty() || count <= 0) return;
    for (auto &st : bag) {
        if (st.id == id && st.filthy == filthy && st.damage == damage) {
            st.count += count;
            return;
        }
    }
    bag.push_back({id, count, 0, filthy, std::clamp(damage, 0, 4)});
}

bool CcbSurvivalState::consume_bag_item(const std::string &id, int count) {
    for (auto it = bag.begin(); it != bag.end(); ++it) {
        if (it->id == id) {
            if (it->count < count) return false;
            it->count -= count;
            if (it->count <= 0) bag.erase(it);
            return true;
        }
    }
    return false;
}

int CcbSurvivalState::bag_count(const std::string &id) const {
    int total = 0;
    for (const auto &st : bag) {
        if (st.id == id) total += st.count;
    }
    return total;
}

int CcbSurvivalState::total_bag_weight_g() const {
    const auto &db = CcbVanillaDB::instance();
    int total = 0;
    for (const auto &st : bag) {
        if (const auto *def = db.find_item(st.id)) total += def->weight_g * st.count;
    }
    for (const auto &wid : worn) {
        if (const auto *def = db.find_item(wid)) total += def->weight_g;
    }
    if (!wielded.empty()) {
        if (const auto *def = db.find_item(wielded)) total += def->weight_g;
    }
    return total;
}

int CcbSurvivalState::total_bag_vol_ml() const {
    const auto &db = CcbVanillaDB::instance();
    int total = 0;
    for (const auto &st : bag) {
        if (const auto *def = db.find_item(st.id)) total += def->vol_ml * st.count;
    }
    return total;
}

Array CcbSurvivalState::body_part_details(const CharacterState &cs) const {
    static constexpr const char *kPartIds[6] = {"head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"};
    const auto &db = CcbVanillaDB::instance();
    Array out;
    for (int p = 0; p < 6; ++p) {
        const int bit = (1 << p);
        int base_enc = 0;
        int warmth = 0;
        int ab = 0, ac = 0, as = 0;
        int layer_count = 0;
        Array items;
        for (const auto &wid : worn) {
            const auto *def = db.find_item(wid);
            if (!def) continue;
            if (def->covers_mask != 0 && (def->covers_mask & bit) == 0) continue;
            if (def->covers_mask == 0 && p != 1) continue;
            base_enc += def->encumbrance;
            warmth += def->warmth;
            ab += def->armor_bash;
            ac += def->armor_cut;
            as += def->armor_stab;
            ++layer_count;
            items.append(String::utf8(def->name_zh.c_str()));
        }
        // Vanilla layer stacking penalty when > 2 layers on same part
        const int layer_pen = std::max(0, (layer_count - 2) * 5);
        Dictionary d;
        d["id"] = String::utf8(kPartIds[p]);
        d["name"] = String::utf8(part_name_cn(p));
        d["hp"] = cs.part_hp[static_cast<std::size_t>(p)];
        d["max_hp"] = cs.max_part_hp;
        d["encumbrance"] = base_enc;
        d["layer_penalty"] = layer_pen;
        d["total_encumbrance"] = base_enc + layer_pen;
        d["warmth"] = warmth;
        d["armor_bash"] = ab;
        d["armor_cut"] = ac;
        d["armor_stab"] = as;
        d["layer_count"] = layer_count;
        d["items"] = items;
        out.append(d);
    }
    return out;
}

bool CcbSurvivalState::reorder_worn(int idx, int delta) {
    if (idx < 0 || idx >= static_cast<int>(worn.size())) return false;
    const int target = idx + delta;
    if (target < 0 || target >= static_cast<int>(worn.size())) return false;
    std::swap(worn[static_cast<std::size_t>(idx)], worn[static_cast<std::size_t>(target)]);
    return true;
}

String CcbSurvivalState::wash_item_id(const std::string &id) {
    for (auto &st : bag) {
        if (st.id == id && st.filthy) {
            st.filthy = false;
            const auto *def = CcbVanillaDB::instance().find_item(id);
            return String::utf8("你清洗干净了「") +
                   String::utf8(def ? def->name_zh.c_str() : id.c_str()) + String::utf8("」，不再脏污。");
        }
    }
    return String::utf8("该物品并不脏污，无需清洗。");
}

bool CcbSurvivalState::has_worn_flag(std::string_view flag) const {
    const auto &db = CcbVanillaDB::instance();
    for (const auto &wid : worn) {
        if (const auto *def = db.find_item(wid)) {
            if (def->has_flag(flag)) return true;
        }
    }
    return false;
}

int CcbSurvivalState::worn_armor_for_part(int part_idx, int dmg_type, int &coverage_out) const {
    const auto &db = CcbVanillaDB::instance();
    const int bit = (part_idx >= 0 && part_idx < 6) ? (1 << part_idx) : 2;
    int total = 0;
    int best_cov = 0;
    for (const auto &wid : worn) {
        const auto *def = db.find_item(wid);
        if (!def) continue;
        if (def->covers_mask != 0 && (def->covers_mask & bit) == 0) continue;
        best_cov = std::max(best_cov, def->coverage > 0 ? def->coverage : 80);
        if (dmg_type == 0) total += def->armor_bash;
        else if (dmg_type == 1) total += def->armor_cut;
        else total += def->armor_stab;
    }
    coverage_out = best_cov;
    return total;
}

int CcbSurvivalState::total_worn_encumbrance() const {
    const auto &db = CcbVanillaDB::instance();
    int total = 0;
    for (const auto &wid : worn) {
        if (const auto *def = db.find_item(wid)) total += def->encumbrance;
    }
    return total;
}

int CcbSurvivalState::torso_encumbrance() const {
    const auto &db = CcbVanillaDB::instance();
    int total = 0;
    for (const auto &wid : worn) {
        if (const auto *def = db.find_item(wid)) {
            if (def->covers_mask == 0 || (def->covers_mask & 2) != 0) total += def->encumbrance;
        }
    }
    return total;
}

int CcbSurvivalState::total_worn_storage_ml() const {
    const auto &db = CcbVanillaDB::instance();
    int total = 1500;
    for (const auto &wid : worn) {
        if (const auto *def = db.find_item(wid)) total += def->storage_ml;
    }
    return total;
}

int CcbSurvivalState::total_worn_warmth() const {
    const auto &db = CcbVanillaDB::instance();
    int total = 0;
    for (const auto &wid : worn) {
        if (const auto *def = db.find_item(wid)) total += def->warmth;
    }
    return total;
}

// ---------------------------------------------------------------------------
// Vanilla Mutation Engine (mutation.cpp + changing_eocs.json exact rules)
// ---------------------------------------------------------------------------
bool CcbSurvivalState::has_mutation(std::string_view mut_id) const {
    return std::find(mutations.begin(), mutations.end(), mut_id) != mutations.end();
}

bool CcbSurvivalState::has_mutation_flag(std::string_view flag) const {
    const auto &db = CcbVanillaDB::instance();
    for (const auto &mid : mutations) {
        if (const auto *def = db.find_mutation(mid)) {
            if (def->has_flag(flag)) return true;
        }
    }
    return false;
}

int CcbSurvivalState::get_vitamin(const std::string &vit_id) const {
    const auto it = vitamins.find(vit_id);
    return it == vitamins.end() ? 0 : it->second;
}

void CcbSurvivalState::mod_vitamin(const std::string &vit_id, int delta, int max_val) {
    const int cur = get_vitamin(vit_id);
    const int nxt = std::clamp(cur + delta, 0, max_val);
    if (nxt == 0) vitamins.erase(vit_id);
    else vitamins[vit_id] = nxt;
}

int CcbSurvivalState::mutation_height(const std::string &mut_id, int depth) const {
    if (depth > 8) return 1;
    const auto *def = CcbVanillaDB::instance().find_mutation(mut_id);
    if (!def || def->prereqs.empty()) return 1;
    int best = 0;
    for (const auto &p : def->prereqs) {
        best = std::max(best, mutation_height(p, depth + 1));
    }
    return 1 + best;
}

int CcbSurvivalState::get_instability_per_category(const std::string &cat_id) const {
    // Exact mutation.cpp:217 formula
    const auto &db = CcbVanillaDB::instance();
    const bool robust = has_mutation("ROBUST") || has_mutation_flag("ROBUST_GENETIC");
    int mut_count = 0;
    for (const auto &mid : mutations) {
        const auto *def = db.find_mutation(mid);
        if (!def) continue;
        if (def->points > -1 && !def->threshold && !def->category.empty()) {
            const int h = mutation_height(mid);
            if (def->in_category(cat_id) || robust) mut_count += h * 1;
            else mut_count += h * 2;
        }
    }
    return std::max(0, mut_count);
}

bool CcbSurvivalState::roll_bad_mutation(const std::string &cat_id) {
    // Vanilla instability curve: higher instability increases chance of bad mutations
    const int instab = get_instability_per_category(cat_id);
    const int bad_pct = std::clamp(12 + instab * 4, 10, 88);
    return rng_range(1, 100) <= bad_pct;
}

bool CcbSurvivalState::has_threshold() const {
    const auto &db = CcbVanillaDB::instance();
    for (const auto &mid : mutations) {
        if (const auto *def = db.find_mutation(mid); def && def->threshold) return true;
    }
    return false;
}

bool CcbSurvivalState::has_prereqs(const CcbMutationDef &m) const {
    if (!m.threshreq.empty()) {
        bool has_tr = false;
        for (const auto &tr : m.threshreq) {
            if (has_mutation(tr)) { has_tr = true; break; }
        }
        if (!has_tr) return false;
    }
    if (!m.prereqs.empty()) {
        bool ok = false;
        for (const auto &p : m.prereqs) {
            if (has_mutation(p)) { ok = true; break; }
        }
        if (!ok) return false;
    }
    if (!m.prereqs2.empty()) {
        bool ok2 = false;
        for (const auto &p : m.prereqs2) {
            if (has_mutation(p)) { ok2 = true; break; }
        }
        if (!ok2) return false;
    }
    return true;
}

bool CcbSurvivalState::mutate_towards(
    const std::string &mut_id,
    const std::string &cat_id,
    bool use_vitamins,
    std::vector<String> &msgs,
    int depth) {
    if (depth > 5 || has_mutation(mut_id)) return false;
    const auto &db = CcbVanillaDB::instance();
    const auto *def = db.find_mutation(mut_id);
    if (!def) return false;

    // Require threshold if post-threshold mutation
    if (!def->threshreq.empty()) {
        bool ok = false;
        for (const auto &tr : def->threshreq) {
            if (has_mutation(tr)) { ok = true; break; }
        }
        if (!ok) return false;
    }

    // Walk prerequisite chains first (exact mutation.cpp:1815)
    if (!def->prereqs.empty()) {
        bool has_p1 = false;
        for (const auto &p : def->prereqs) {
            if (has_mutation(p)) { has_p1 = true; break; }
        }
        if (!has_p1) {
            const std::string &pick = def->prereqs[static_cast<std::size_t>(rng_range(0, static_cast<int>(def->prereqs.size()) - 1))];
            return mutate_towards(pick, cat_id, use_vitamins, msgs, depth + 1);
        }
    }
    if (!def->prereqs2.empty()) {
        bool has_p2 = false;
        for (const auto &p : def->prereqs2) {
            if (has_mutation(p)) { has_p2 = true; break; }
        }
        if (!has_p2) {
            const std::string &pick = def->prereqs2[static_cast<std::size_t>(rng_range(0, static_cast<int>(def->prereqs2.size()) - 1))];
            return mutate_towards(pick, cat_id, use_vitamins, msgs, depth + 1);
        }
    }

    // Consume category primer vitamin if using vitamins
    if (use_vitamins && !cat_id.empty()) {
        if (const auto *cdef = db.find_mutation_category(cat_id)) {
            if (!cdef->vitamin.empty()) {
                const int cost = std::max(50, def->vitamin_cost);
                if (get_vitamin(cdef->vitamin) < cost) return false;
                mod_vitamin(cdef->vitamin, -cost);
            }
        }
    }

    // Remove conflicting mutations (cancels) and superseded prereqs
    for (const auto &cid : def->cancels) {
        auto it = std::find(mutations.begin(), mutations.end(), cid);
        if (it != mutations.end()) {
            const auto *cdef = db.find_mutation(cid);
            msgs.push_back(String::utf8("[诱变] 你的特征「") +
                           String::utf8(cdef ? cdef->name.c_str() : cid.c_str()) +
                           String::utf8("」被新变异取代消失了！"));
            mutations.erase(it);
        }
    }
    for (const auto &pid : def->prereqs) {
        const auto *pdef = db.find_mutation(pid);
        if (pdef && std::find(pdef->changes_to.begin(), pdef->changes_to.end(), mut_id) != pdef->changes_to.end()) {
            auto it = std::find(mutations.begin(), mutations.end(), pid);
            if (it != mutations.end()) mutations.erase(it);
        }
    }

    mutations.push_back(def->id);
    const String tag = def->threshold ? String::utf8("[跨越阈值]") : String::utf8("[诱变]");
    msgs.push_back(tag + String::utf8(" 你获得了原版变异「") + String::utf8(def->name.c_str()) +
                   String::utf8("」：") + String::utf8(def->desc.c_str()));
    return true;
}

bool CcbSurvivalState::mutate_category(const std::string &cat_id, bool use_vitamins, std::vector<String> &msgs) {
    const auto &db = CcbVanillaDB::instance();
    const auto *cdef = db.find_mutation_category(cat_id);
    if (!cdef) return mutate_random(false, msgs);

    // Check threshold crossing (mutation.cpp:1372)
    if (use_vitamins && !cdef->threshold_mut.empty() && !has_threshold() && !cdef->vitamin.empty()) {
        if (get_vitamin(cdef->vitamin) >= cdef->threshold_min) {
            if (mutate_towards(cdef->threshold_mut, cat_id, false, msgs)) {
                msgs.push_back(String::utf8(cdef->mutagen_message.c_str()));
                return true;
            }
        }
    }

    const bool want_bad = roll_bad_mutation(cat_id);
    std::vector<std::string> upgrades;
    std::vector<std::string> candidates;

    for (const auto &mid : mutations) {
        if (const auto *cur = db.find_mutation(mid)) {
            for (const auto &up : cur->changes_to) {
                const auto *udef = db.find_mutation(up);
                if (!udef || !udef->valid || has_mutation(up)) continue;
                if (cat_id != "ANY" && !udef->in_category(cat_id)) continue;
                upgrades.push_back(up);
            }
        }
    }

    for (const auto &m : db.all_mutations()) {
        if (!m.valid || m.threshold || has_mutation(m.id)) continue;
        if (cat_id != "ANY" && !m.in_category(cat_id)) continue;
        if (!m.threshreq.empty()) {
            bool ok = false;
            for (const auto &tr : m.threshreq) if (has_mutation(tr)) { ok = true; break; }
            if (!ok) continue;
        }
        if (want_bad && m.points > 0) continue;
        if (!want_bad && m.points < 0) continue;
        candidates.push_back(m.id);
    }

    if (candidates.empty()) {
        for (const auto &m : db.all_mutations()) {
            if (!m.valid || m.threshold || has_mutation(m.id)) continue;
            if (cat_id != "ANY" && !m.in_category(cat_id)) continue;
            candidates.push_back(m.id);
        }
    }

    // Prioritize upgrades 50% of the time (exact mutation.cpp:1324)
    if (!upgrades.empty() && one_in(2)) {
        const std::string &pick = upgrades[static_cast<std::size_t>(rng_range(0, static_cast<int>(upgrades.size()) - 1))];
        if (mutate_towards(pick, cat_id, use_vitamins, msgs)) {
            msgs.push_back(String::utf8(cdef->mutagen_message.c_str()));
            return true;
        }
    }

    if (candidates.empty()) return false;
    for (int tries = 0; tries < 6; ++tries) {
        const std::string &pick = candidates[static_cast<std::size_t>(rng_range(0, static_cast<int>(candidates.size()) - 1))];
        if (mutate_towards(pick, cat_id, use_vitamins, msgs)) {
            msgs.push_back(String::utf8(cdef->mutagen_message.c_str()));
            return true;
        }
    }
    return false;
}

bool CcbSurvivalState::mutate_random(bool use_vitamins, std::vector<String> &msgs) {
    const auto &db = CcbVanillaDB::instance();
    if (use_vitamins) {
        // Weighted pick from non-zero primer vitamins (exact mutation.cpp get_vitamin_weighted_categories)
        std::vector<std::pair<std::string, int>> weighted;
        int total_w = 0;
        for (const auto &[vid, val] : vitamins) {
            if (val <= 0 || vid == "mutagen" || vid == "mutagen_human") continue;
            if (const auto *cat = db.find_category_by_vitamin(vid)) {
                weighted.emplace_back(cat->id, val);
                total_w += val;
            }
        }
        if (total_w > 0) {
            int roll = rng_range(0, total_w - 1);
            for (const auto &[cid, w] : weighted) {
                if (roll < w) return mutate_category(cid, true, msgs);
                roll -= w;
            }
        }
        // Handle purifier vitamin ("mutagen_human")
        if (get_vitamin("mutagen_human") >= 100) {
            mod_vitamin("mutagen_human", -100);
            return purify_one(msgs);
        }
        msgs.push_back(String::utf8("[诱变] 你体内缺乏定向诱变引物，躯体只是一阵抽搐便恢复了平静。"));
        return false;
    }

    // Radiation / chaotic uncategorized mutation: pick from ANY valid non-threshold mutations
    const bool bad = rng_range(1, 100) <= 65; // Radiation skews negative just like CDDA
    std::vector<std::string> pool;
    for (const auto &m : db.all_mutations()) {
        if (!m.valid || m.threshold || !m.threshreq.empty() || has_mutation(m.id)) continue;
        if (bad && m.points > 0) continue;
        pool.push_back(m.id);
    }
    if (pool.empty()) return false;
    const std::string &pick = pool[static_cast<std::size_t>(rng_range(0, static_cast<int>(pool.size()) - 1))];
    return mutate_towards(pick, "ANY", false, msgs);
}

bool CcbSurvivalState::purify_one(std::vector<String> &msgs) {
    const auto &db = CcbVanillaDB::instance();
    std::vector<std::size_t> purifiable_idxs;
    for (std::size_t i = 0; i < mutations.size(); ++i) {
        const auto *def = db.find_mutation(mutations[i]);
        if (def && def->purifiable && !def->threshold) {
            purifiable_idxs.push_back(i);
        }
    }
    if (purifiable_idxs.empty()) {
        msgs.push_back(String::utf8("[净化] 你感到体内的基因逐渐归于纯净（当前无可净化的变异）。"));
        return false;
    }
    const std::size_t idx = purifiable_idxs[static_cast<std::size_t>(rng_range(0, static_cast<int>(purifiable_idxs.size()) - 1))];
    const auto *def = db.find_mutation(mutations[idx]);
    msgs.push_back(String::utf8("[净化] 净化剂清除了你的变异「") +
                   String::utf8(def ? def->name.c_str() : mutations[idx].c_str()) + String::utf8("」！"));
    mutations.erase(mutations.begin() + static_cast<std::ptrdiff_t>(idx));
    return true;
}

// ---------------------------------------------------------------------------
// Vanilla Radiation & Per-Minute Survival Effects (suffer.cpp exact formulas)
// ---------------------------------------------------------------------------
String CcbSurvivalState::rad_badge_color_cn(int badge_rad) {
    if (badge_rad <= 0) return String::utf8("绿色（安全）");
    if (badge_rad < 30) return String::utf8("蓝色（轻微）");
    if (badge_rad < 60) return String::utf8("黄色（警戒）");
    if (badge_rad < 120) return String::utf8("橙色（危险）");
    if (badge_rad < 240) return String::utf8("红色（严重）");
    return String::utf8("黑色（致命）");
}

bool CcbSurvivalState::irradiate(float rads, bool bypass, std::vector<String> &msgs) {
    if (rads <= 0.0f) return false;
    const auto mods = compute_mods();
    if (!bypass) {
        if (mods.rad_immune) {
            return false;
        }
        if (mods.rad_resist) {
            rads /= 4.0f;
        }
    }
    if (iodine_min > 0) {
        // Exact suffer.cpp:1873: rads *= 0.3f + 0.1f * rad_mut
        rads *= 0.3f + 0.1f * static_cast<float>(mods.radioactive_level);
    }

    const int whole = static_cast<int>(std::floor(rads));
    const float frac = rads - static_cast<float>(whole);
    const int rads_max = whole + (rng_range(0, 999) < static_cast<int>(frac * 1000.0f) ? 1 : 0);
    if (rads_max <= 0) return false;

    const int gain = rng_range(0, rads_max);
    if (gain > 0) {
        rad = std::clamp(rad + gain, 0, 2000);
    }

    // Update exposed radiation badge color (exact suffer.cpp:1880-1910)
    if (has_worn_flag("RAD_DETECT")) {
        const String col_before = rad_badge_color_cn(rad_badge_rad);
        rad_badge_rad += rng_range(0, rads_max);
        const String col_after = rad_badge_color_cn(rad_badge_rad);
        if (col_before != col_after) {
            msgs.push_back(String::utf8("[辐射徽章] 你的辐射侦测徽章从") + col_before +
                           String::utf8("变成了") + col_after + String::utf8("！"));
        }
    }
    return true;
}

void CcbSurvivalState::tick_minute_effects(
    int delta_min,
    float tile_rad,
    CharacterState &cs,
    std::vector<String> &msgs) {
    if (delta_min <= 0) return;
    last_tile_rad = tile_rad;
    const auto mods = compute_mods();

    // 1. Environmental + radioactive item leakage radiation
    float leak_rads = tile_rad;
    const auto &db = CcbVanillaDB::instance();
    for (const auto &st : bag) {
        if (const auto *def = db.find_item(st.id)) {
            if (def->has_flag("RADIOACTIVE") && def->has_flag("LEAK_ALWAYS")) {
                leak_rads += (static_cast<float>(def->weight_g) / 250.0f) * static_cast<float>(st.count);
            }
        }
    }
    if (leak_rads > 0.0f) {
        const bool inc = irradiate(leak_rads * static_cast<float>(delta_min), false, msgs);
        if (inc && mods.radiophile && one_in(3)) {
            msgs.push_back(String::utf8("[辐射] 你的血肉因周遭辐射而微微发麻，竟感到一丝奇异的愉悦。"));
        }
    }

    // Timers decay
    if (iodine_min > 0) iodine_min = std::max(0, iodine_min - delta_min);
    if (pblue_min > 0) pblue_min = std::max(0, pblue_min - delta_min);
    if (antibiotic_min > 0) antibiotic_min = std::max(0, antibiotic_min - delta_min);

    // 2. Natural & Prussian-blue radiation clearance (character_health.cpp:1318)
    if (rad > 0) {
        const int clear_rate = (pblue_min > 0) ? 4 : 1;
        rad_tick_accum += delta_min * clear_rate;
        while (rad_tick_accum >= 50 && rad > 0) {
            rad_tick_accum -= 50;
            rad = std::max(0, rad - 1);
        }
    }

    // 3. Radiation sickness periodic checks (exact suffer.cpp:1287-1331)
    if (rad > 0) {
        // Every 15 minutes: radioactive mutation & vomiting
        for (int m = 0; m < delta_min; ++m) {
            if ((m % 15) == 0) {
                if (rad >= 100 && rng_range(100, 10000) < rad) {
                    msgs.push_back(String::utf8("[辐射畸变] 剧烈的电离辐射撕裂并重组了你的基因链！"));
                    mutate_random(false, msgs);
                }
                if (rad > 50 && rng_range(1, 3000) < rad) {
                    cs.kcal = std::max(0.0, cs.kcal - 180.0);
                    cs.hydration = std::max(0.0, cs.hydration - 8.0);
                    cs.morale = std::max(-50, cs.morale - 6);
                    rad = std::max(0, rad - 1);
                    msgs.push_back(String::utf8("[辐射病] 一阵翻江倒海的恶心袭来，你剧烈呕吐起来！"));
                }
            }
            if ((m % 10) == 0 && rad > 200 && x_in_y(rad, 1000)) {
                for (int p = 0; p < 6; ++p) {
                    cs.part_hp[static_cast<std::size_t>(p)] = std::max(1, cs.part_hp[static_cast<std::size_t>(p)] - 1);
                }
                rad = std::max(0, rad - 5);
                msgs.push_back(String::utf8("[急性辐射病] 你的全身细胞正在承受辐射灼伤（全部位 -1 HP）！"));
            }
            if ((m % 30) == 0 && mods.radiogenic && x_in_y(rad, 200)) {
                for (int p = 0; p < 6; ++p) {
                    cs.part_hp[static_cast<std::size_t>(p)] = std::min(cs.max_part_hp, cs.part_hp[static_cast<std::size_t>(p)] + 1);
                }
                if (mods.radioactive_level == 0) rad = std::max(0, rad - 5);
            }
        }
    }

    // 4. Bleeding, Bite & Infection progression (player_hardcoded_effects.cpp)
    for (int p = 0; p < 6; ++p) {
        const std::size_t idx = static_cast<std::size_t>(p);
        if (bleed[idx] > 0) {
            const int dmg = std::max(1, (bleed[idx] * delta_min) / 10);
            cs.part_hp[idx] = std::max(1, cs.part_hp[idx] - dmg);
            bleed[idx] = std::max(0, bleed[idx] - std::max(1, delta_min / 3));
            if (bleed[idx] > 0) {
                msgs.push_back(String::utf8("[流血] 你的") + String::utf8(part_name_cn(p)) +
                               String::utf8("伤口仍在流血（请用绷带包扎）！"));
            }
        }
        if (bite_min[idx] > 0) {
            bite_min[idx] += delta_min;
            if (bite_min[idx] >= 360) { // 6 hours untreated -> infected
                bite_min[idx] = 0;
                infected_min[idx] = 1;
                msgs.push_back(String::utf8("[感染] 你") + String::utf8(part_name_cn(p)) +
                               String::utf8("上未清理的深度咬伤发脓感染了（急需抗生素）！"));
            }
        }
        if (infected_min[idx] > 0) {
            if (antibiotic_min > 0) {
                infected_min[idx] = std::max(0, infected_min[idx] - delta_min * 3);
                if (infected_min[idx] == 0) {
                    msgs.push_back(String::utf8("[康复] 抗生素控制住了你") + String::utf8(part_name_cn(p)) + String::utf8("的伤口感染！"));
                }
            } else {
                infected_min[idx] += delta_min;
                if (infected_min[idx] % 30 < delta_min) {
                    cs.pain = std::min(100, cs.pain + 3);
                    cs.part_hp[idx] = std::max(1, cs.part_hp[idx] - 1);
                }
            }
        }
    }

    // 5. Vanilla Mutagen Catalyst + Primer Processing (changing_eocs.json exact flow)
    mut_tick_accum += delta_min;
    const int cat_vit = get_vitamin("mutagen");
    if (!changing && cat_vit >= 450 && mut_tick_accum >= 30) {
        mut_tick_accum = 0;
        // weighted_list_eocs: changing_failed (2500) vs changing_successful (cat_vit)
        if (rng_range(0, 2500 + cat_vit) < cat_vit) {
            changing = true;
            msgs.push_back(String::utf8("[诱变启动] 你感到全身细胞撕裂重组，骨骼与血肉开始剧烈变形（进入异变态）！"));
            mutate_random(true, msgs);
            mod_vitamin("mutagen", -(60 + rng_range(0, 80)));
        }
    } else if (changing && mut_tick_accum >= 60) {
        mut_tick_accum = 0;
        if (cat_vit >= 300) {
            msgs.push_back(String::utf8("[诱变持续] 一股深沉的翻涌感席卷全身……"));
            mutate_random(true, msgs);
            mod_vitamin("mutagen", -(60 + rng_range(0, 80)));
        } else {
            changing = false;
            vitamins.erase("mutagen");
            msgs.push_back(String::utf8("[诱变结束] 体内诱变催化剂耗尽，异变过程缓缓平息。"));
        }
    }

    // Natural slow vitamin decay (1/h per vitamin.json)
    if (delta_min >= 10) {
        std::vector<std::string> to_erase;
        for (auto &[vk, vv] : vitamins) {
            vv = std::max(0, vv - std::max(1, delta_min / 10));
            if (vv == 0) to_erase.push_back(vk);
        }
        for (const auto &k : to_erase) vitamins.erase(k);
    }
}

CcbDerivedMods CcbSurvivalState::compute_mods() const {
    CcbDerivedMods m;

    // 1. Exact effects.json:4817 radiation sickness stat & speed scaling (int_dur_factor = 10s -> intensity = rad/10)
    if (rad > 0) {
        const double intensity = static_cast<double>(rad) / 10.0;
        m.speed_mod -= static_cast<int>(std::floor(intensity * 0.2));
        m.str_mod -= static_cast<int>(std::floor(intensity * 0.125));
        m.dex_mod -= static_cast<int>(std::floor(intensity * 0.09));
        m.int_mod -= static_cast<int>(std::floor(intensity * 0.1));
        m.per_mod -= static_cast<int>(std::floor(intensity * 0.083));
    }

    // 2. Worn radiation gear
    if (has_worn_flag("RAD_PROOF") || has_worn_flag("POWERARMOR_COMPATIBLE")) m.rad_immune = true;
    if (has_worn_flag("RAD_RESIST") || has_worn_flag("GAS_PROOF")) m.rad_resist = true;

    // 3. Active vanilla mutations modifiers
    for (const auto &mid : mutations) {
        if (mid == "STR_UP" || mid == "STR_ALPHA") m.str_mod += 1;
        else if (mid == "STR_UP_2") m.str_mod += 2;
        else if (mid == "STR_UP_3") m.str_mod += 4;
        else if (mid == "STR_UP_4") m.str_mod += 7;
        else if (mid == "DEX_UP" || mid == "DEX_ALPHA") m.dex_mod += 1;
        else if (mid == "DEX_UP_2") m.dex_mod += 2;
        else if (mid == "DEX_UP_3") m.dex_mod += 4;
        else if (mid == "INT_UP" || mid == "INT_ALPHA") m.int_mod += 1;
        else if (mid == "INT_UP_2") m.int_mod += 2;
        else if (mid == "PER_UP" || mid == "PER_ALPHA") m.per_mod += 1;
        else if (mid == "PER_UP_2") m.per_mod += 2;
        else if (mid == "QUICK") m.speed_mod += 10;
        else if (mid == "FLEET" || mid == "FLEET2") m.speed_mod += 15;
        else if (mid == "SLOWRUNNER") m.speed_mod -= 15;
        else if (mid == "TOUGH") m.hp_bonus += 16;
        else if (mid == "TOUGH2") m.hp_bonus += 24;
        else if (mid == "TOUGH3") m.hp_bonus += 32;
        else if (mid == "FLIMSY") m.hp_bonus -= 20;
        else if (mid == "GLASSJAW") m.hp_bonus -= 16;
        else if (mid == "THICK_SKIN" || mid == "FUR") { m.natural_armor_bash += 1; m.natural_armor_cut += 2; }
        else if (mid == "SCALES" || mid == "CHITIN") { m.natural_armor_bash += 2; m.natural_armor_cut += 5; m.natural_armor_stab += 4; }
        else if (mid == "CHITIN2" || mid == "CHITIN3") { m.natural_armor_bash += 4; m.natural_armor_cut += 9; m.natural_armor_stab += 8; }
        else if (mid == "CLAWS" || mid == "CLAWS_RAT" || mid == "CLAWS_RETRACT") { m.unarmed_cut += 7; }
        else if (mid == "CLAWS_ST" || mid == "TALONS") { m.unarmed_stab += 10; }
        else if (mid == "FANGS") { m.unarmed_stab += 5; }
        else if (mid == "NIGHTVISION") m.night_vision_bonus += 4;
        else if (mid == "NIGHTVISION2") m.night_vision_bonus += 8;
        else if (mid == "NIGHTVISION3") m.night_vision_bonus += 14;
        else if (mid == "RADIOGENIC") m.radiogenic = true;
        else if (mid == "RADIOPHILE") m.radiophile = true;
        else if (mid == "RADIOACTIVE1") m.radioactive_level = std::max(m.radioactive_level, 1);
        else if (mid == "RADIOACTIVE2") m.radioactive_level = std::max(m.radioactive_level, 2);
        else if (mid == "RADIOACTIVE3") m.radioactive_level = std::max(m.radioactive_level, 3);
        else if (mid == "ROBUST") m.robust_genetics = true;
    }
    if (has_mutation_flag("ROBUST_GENETIC")) m.robust_genetics = true;
    return m;
}

// ---------------------------------------------------------------------------
// Vanilla CCB Item Actions (Wield / Wear / Eat / Drink / Inject / Apply)
// ---------------------------------------------------------------------------
String CcbSurvivalState::wield_item_id(const std::string &id) {
    const auto *def = CcbVanillaDB::instance().find_item(id);
    if (!def) return String::utf8("未知的 CCB 原版物品。");
    if (!consume_bag_item(id, 1)) return String::utf8("背包中没有这件物品。");
    if (!wielded.empty()) add_bag_item(wielded, 1);
    wielded = id;
    return String::utf8("你手持了「") + String::utf8(def->name_zh.c_str()) +
           String::utf8("」（钝击 ") + String::num_int64(def->bash) +
           String::utf8(" / 斩击 ") + String::num_int64(def->cut) +
           String::utf8(" / 穿刺 ") + String::num_int64(def->stab) + String::utf8("）。");
}

String CcbSurvivalState::unwield_item() {
    if (wielded.empty()) return String::utf8("你目前本来就是空手。");
    const auto *def = CcbVanillaDB::instance().find_item(wielded);
    const String nm = def ? String::utf8(def->name_zh.c_str()) : String::utf8(wielded.c_str());
    add_bag_item(wielded, 1);
    wielded.clear();
    return String::utf8("你将「") + nm + String::utf8("」收回了行囊。");
}

String CcbSurvivalState::wear_item_id(const std::string &id) {
    const auto *def = CcbVanillaDB::instance().find_item(id);
    if (!def) return String::utf8("未知的 CCB 原版物品。");
    if (def->subtype != "ARMOR" && def->covers_mask == 0 && !def->has_flag("RAD_DETECT")) {
        return String::utf8("「") + String::utf8(def->name_zh.c_str()) + String::utf8("」无法穿戴。");
    }
    // Check if the only copy in bag is FILTHY (authentic vanilla CCB refusal!)
    bool has_clean = false;
    bool has_filthy = false;
    for (const auto &st : bag) {
        if (st.id == id) {
            if (st.filthy) has_filthy = true;
            else has_clean = true;
        }
    }
    if (!has_clean && has_filthy) {
        return String::utf8("这件「") + String::utf8(def->name_zh.c_str()) +
               String::utf8("」太脏污了 (脏污)！在原版大灾变中需先清洗后才能穿戴。");
    }
    if (!has_clean) return String::utf8("背包中没有这件装备。");
    for (auto it = bag.begin(); it != bag.end(); ++it) {
        if (it->id == id && !it->filthy) {
            it->count -= 1;
            if (it->count <= 0) bag.erase(it);
            break;
        }
    }
    worn.push_back(id);
    return String::utf8("你穿戴上了「") + String::utf8(def->name_zh.c_str()) +
           String::utf8("」（防钝/斩/刺 ") + String::num_int64(def->armor_bash) + String("/") +
           String::num_int64(def->armor_cut) + String("/") + String::num_int64(def->armor_stab) +
           String::utf8("，累赘 ") + String::num_int64(def->encumbrance) + String::utf8("）。");
}

String CcbSurvivalState::takeoff_item_id(const std::string &id) {
    auto it = std::find(worn.begin(), worn.end(), id);
    if (it == worn.end()) return String::utf8("你当前并未穿戴该装备。");
    const auto *def = CcbVanillaDB::instance().find_item(id);
    const String nm = def ? String::utf8(def->name_zh.c_str()) : String::utf8(id.c_str());
    worn.erase(it);
    add_bag_item(id, 1);
    return String::utf8("你脱下了「") + nm + String::utf8("」。");
}

String CcbSurvivalState::use_or_consume_item(
    const std::string &id,
    CharacterState &cs,
    std::vector<String> &extra_msgs) {
    const auto *def = CcbVanillaDB::instance().find_item(id);
    if (!def) return String::utf8("未知的 CCB 物品。");
    const bool in_bag = bag_count(id) > 0;
    const bool is_wield = (wielded == id);
    if (!in_bag && !is_wield) return String::utf8("你身上没有这件物品。");

    const String nm = String::utf8(def->name_zh.c_str());

    // 1. Geiger Counter (exact iuse.cpp:2902)
    if (def->has_use_tag("geiger") || id.find("geiger") != std::string::npos) {
        return String::utf8("[盖革计数器] 个人累计辐射剂量：") + String::num_int64(rad) +
               String::utf8(" mSv；当前脚下环境辐射：") + String::num(last_tile_rad, 1) +
               String::utf8(" mSv/分。");
    }

    // 2. Flashlight / Portable Light
    if (id.find("flashlight") != std::string::npos || id.find("lantern") != std::string::npos ||
        id.find("lighter") != std::string::npos) {
        cs.lamp_lit = !cs.lamp_lit;
        cs.light_source = cs.lamp_lit ? 3 : 0;
        return cs.lamp_lit
            ? (String::utf8("你打开了「") + nm + String::utf8("」，光束照亮了前方的黑暗。"))
            : (String::utf8("你关闭了「") + nm + String::utf8("」。"));
    }

    // 3. Medical: Bandages / Antiseptic / First Aid
    if (def->has_use_tag("heal") || id.find("bandage") != std::string::npos || id.find("firstaid") != std::string::npos ||
        id.find("antiseptic") != std::string::npos || id.find("disinfectant") != std::string::npos) {
        if (in_bag) consume_bag_item(id, 1);
        const bool is_disinfect = (id.find("antiseptic") != std::string::npos || id.find("disinfectant") != std::string::npos);
        if (is_disinfect) {
            bool cleaned = false;
            for (int p = 0; p < 6; ++p) {
                if (bite_min[static_cast<std::size_t>(p)] > 0) {
                    bite_min[static_cast<std::size_t>(p)] = 0;
                    cleaned = true;
                }
            }
            skills.train(6, 20);
            return cleaned
                ? (String::utf8("你用「") + nm + String::utf8("」彻底消毒了深层咬伤，防止了感染恶化！"))
                : (String::utf8("你涂抹了「") + nm + String::utf8("」消毒皮肤。"));
        }
        int worst = 0;
        for (int p = 1; p < 6; ++p) {
            if (cs.part_hp[static_cast<std::size_t>(p)] < cs.part_hp[static_cast<std::size_t>(worst)]) worst = p;
        }
        const int heal = 12 + skills.firstaid * 3 + (id.find("firstaid") != std::string::npos ? 14 : 0);
        cs.part_hp[static_cast<std::size_t>(worst)] = std::min(cs.max_part_hp, cs.part_hp[static_cast<std::size_t>(worst)] + heal);
        bleed[static_cast<std::size_t>(worst)] = 0;
        cs.pain = std::max(0, cs.pain - 6);
        skills.train(6, 25);
        return String::utf8("你用「") + nm + String::utf8("」包扎了") + String::utf8(part_name_cn(worst)) +
               String::utf8("（止血并恢复 +") + String::num_int64(heal) + String::utf8(" HP）。");
    }

    // 4. Comestibles, Drugs, Radiation Medicine, Mutagens & Purifiers!
    if (def->subtype == "COMESTIBLE" || !def->vitamins.empty() || def->has_use_tag("consume_drug") ||
        def->has_use_tag("antibiotic") || def->has_flag("MUTAGEN_CATALYST") || def->has_flag("MUTAGEN_PRIMER")) {
        if (in_bag) consume_bag_item(id, 1);

        if (def->kcal > 0) cs.kcal = std::min(3600.0, cs.kcal + static_cast<double>(def->kcal));
        if (def->quench != 0) cs.hydration = std::clamp(cs.hydration + static_cast<double>(def->quench) * 1.2, 0.0, 120.0);
        if (def->fun != 0) cs.morale = std::clamp(cs.morale + def->fun, -50, 50);

        // Radiation drugs (iodine / prussian_blue)
        if (def->has_use_tag("eff:iodine") || id == "iodine") {
            iodine_min = std::max(iodine_min, 360);
            return String::utf8("你服下了「") + nm + String::utf8("」（6小时内大幅降低辐射吸收率，原版碘片机制）。");
        }
        if (def->has_use_tag("eff:pblue") || id == "prussian_blue") {
            pblue_min = std::max(pblue_min, 360);
            rad = std::max(0, rad - 15);
            return String::utf8("你服下了「") + nm + String::utf8("」（已清除部分体内放射性核素，并持续加速排毒）。");
        }
        if (def->has_use_tag("antibiotic") || id.find("antibiotic") != std::string::npos) {
            antibiotic_min = std::max(antibiotic_min, 720);
            return String::utf8("你服下了「") + nm + String::utf8("」（12小时内持续抑制并治愈伤口感染）。");
        }

        // Irradiated food check
        if (def->has_flag("IRRADIATED")) {
            irradiate(12.0f, true, extra_msgs);
        }

        // Vanilla Vitamins (Mutagenic Catalyst + Primers + Purifier!)
        bool had_mutagen = false;
        String vit_summary;
        for (const auto &[vk, vv] : def->vitamins) {
            if (vk == "mutagen" || vk.rfind("mutagen_", 0) == 0) {
                had_mutagen = true;
                const int cap = (vk == "mutagen_alpha") ? 5000 : 2500;
                mod_vitamin(vk, vv, cap);
                if (!vit_summary.is_empty()) vit_summary += String::utf8("，");
                vit_summary += String::utf8(vk.c_str()) + String::utf8(" +") + String::num_int64(vv);
            }
        }
        if (id == "mutagen") {
            // Mutagenic slurry gives catalyst directly
            had_mutagen = true;
            mod_vitamin("mutagen", 550, 2500);
            vit_summary = String::utf8("mutagen +550");
        }
        if (id == "purifier" || id == "iv_purifier") {
            had_mutagen = true;
            purify_one(extra_msgs);
            if (id == "iv_purifier") purify_one(extra_msgs);
            vitamins.erase("mutagen");
            changing = false;
            return String::utf8("你使用了「") + nm + String::utf8("」，体内游离诱变剂已被中和净化！");
        }
        if (had_mutagen) {
            // Immediately check if catalyst + primer ready to initiate changing or trigger mutation!
            const int cat_v = get_vitamin("mutagen");
            if (cat_v >= 450 && !changing) {
                changing = true;
                extra_msgs.push_back(String::utf8("[诱变启动] 诱变催化剂浓度达到阈值（") +
                                     String::num_int64(cat_v) + String::utf8("/2500），基因重组开始！"));
                mutate_random(true, extra_msgs);
                mod_vitamin("mutagen", -(60 + rng_range(0, 80)));
            }
            return String::utf8("你注射/服用了「") + nm + String::utf8("」（") + vit_summary +
                   String::utf8("；当前催化剂 ") + String::num_int64(get_vitamin("mutagen")) + String::utf8("）。");
        }

        return String::utf8("你食用/服用了「") + nm + String::utf8("」（热量 +") +
               String::num_int64(def->kcal) + String::utf8("，解渴 +") + String::num_int64(def->quench) + String::utf8("）。");
    }

    return String::utf8("「") + nm + String::utf8("」无法直接使用（可尝试装备穿戴或手持作为武器）。");
}

// ---------------------------------------------------------------------------
// UI Views & Save/Load Serialization
// ---------------------------------------------------------------------------
Array CcbSurvivalState::bag_to_array() const {
    Array out;
    const auto &db = CcbVanillaDB::instance();
    for (const auto &st : bag) {
        out.append(db.stack_to_dict(st));
    }
    return out;
}

Array CcbSurvivalState::worn_to_array() const {
    Array out;
    const auto &db = CcbVanillaDB::instance();
    for (std::size_t i = 0; i < worn.size(); ++i) {
        const auto &wid = worn[i];
        const auto *def = db.find_item(wid);
        Dictionary d = def ? db.item_to_dict(*def) : Dictionary();
        d["id"] = String::utf8(wid.c_str());
        if (!def) d["name"] = String::utf8(wid.c_str());
        d["layer_index"] = static_cast<int>(i);
        out.append(d);
    }
    return out;
}

Dictionary CcbSurvivalState::status_dict(const CharacterState &cs) const {
    const auto &db = CcbVanillaDB::instance();
    const auto mods = compute_mods();
    Dictionary d;
    d["rad"] = rad;
    d["tile_rad"] = last_tile_rad;
    d["iodine_min"] = iodine_min;
    d["pblue_min"] = pblue_min;
    d["antibiotic_min"] = antibiotic_min;
    d["rad_badge_rad"] = rad_badge_rad;
    d["rad_badge_color"] = rad_badge_color_cn(rad_badge_rad);
    d["has_rad_badge"] = has_worn_flag("RAD_DETECT");
    d["rad_resist"] = mods.rad_resist;
    d["rad_immune"] = mods.rad_immune;
    d["changing"] = changing;
    d["grab_intensity"] = grab_intensity;
    d["mutagen_catalyst"] = get_vitamin("mutagen");
    d["wielded_id"] = String::utf8(wielded.c_str());
    const auto *wdef = wielded.empty() ? nullptr : db.find_item(wielded);
    d["wielded_name"] = wdef ? String::utf8(wdef->name_zh.c_str()) : String::utf8("空手");
    d["wielded_bash"] = wdef ? wdef->bash : 0;
    d["wielded_cut"] = wdef ? wdef->cut : 0;
    d["wielded_stab"] = wdef ? wdef->stab : 0;
    d["eff_str"] = std::max(1, cs.stat_str + mods.str_mod);
    d["eff_dex"] = std::max(1, cs.stat_dex + mods.dex_mod);
    d["eff_int"] = std::max(1, cs.stat_int + mods.int_mod);
    d["eff_per"] = std::max(1, cs.stat_per + mods.per_mod);
    d["speed_mod"] = mods.speed_mod;
    d["encumbrance"] = total_worn_encumbrance();
    d["torso_encumbrance"] = torso_encumbrance();
    d["carry_weight_g"] = total_bag_weight_g();
    d["max_weight_g"] = std::max(15000, (13000 + std::max(1, cs.stat_str + mods.str_mod) * 4000));
    d["carry_vol_ml"] = total_bag_vol_ml();
    d["max_vol_ml"] = std::max(1500, 1500 + total_worn_storage_ml());
    d["skills"] = skills.to_dict();
    const auto *scdef = db.find_scenario(scenario_id);
    const auto *prdef = db.find_profession(profession_id);
    d["scenario_id"] = String::utf8(scenario_id.c_str());
    d["scenario_name"] = scdef ? String::utf8(scdef->name.c_str()) : String::utf8(scenario_id.c_str());
    d["profession_id"] = String::utf8(profession_id.c_str());
    d["profession_name"] = prdef ? String::utf8(prdef->name.c_str()) : String::utf8(profession_id.c_str());
    d["gender"] = String::utf8(gender.c_str());
    d["age"] = age;
    d["body_parts"] = body_part_details(cs);
    Array sk_full;
    for (const auto &sd : db.all_skills_defs()) {
        Dictionary skd;
        skd["id"] = String::utf8(sd.id.c_str());
        skd["name"] = String::utf8(sd.name.c_str());
        skd["desc"] = String::utf8(sd.desc.c_str());
        skd["category"] = String::utf8(sd.category.c_str());
        skd["level"] = skill_level_by_id(sd.id);
        sk_full.append(skd);
    }
    d["all_skills"] = sk_full;

    Array mut_arr;
    for (const auto &mid : mutations) {
        const auto *mdef = db.find_mutation(mid);
        Dictionary md;
        md["id"] = String::utf8(mid.c_str());
        md["name"] = mdef ? String::utf8(mdef->name.c_str()) : String::utf8(mid.c_str());
        md["desc"] = mdef ? String::utf8(mdef->desc.c_str()) : String();
        md["points"] = mdef ? mdef->points : 0;
        md["threshold"] = mdef ? mdef->threshold : false;
        md["purifiable"] = mdef ? mdef->purifiable : true;
        mut_arr.append(md);
    }
    d["mutations"] = mut_arr;

    Dictionary vit_dict;
    for (const auto &[vk, vv] : vitamins) {
        vit_dict[String::utf8(vk.c_str())] = vv;
    }
    d["vitamins"] = vit_dict;

    Array wounds;
    for (int p = 0; p < 6; ++p) {
        const std::size_t idx = static_cast<std::size_t>(p);
        if (bleed[idx] > 0 || bite_min[idx] > 0 || infected_min[idx] > 0) {
            Dictionary w;
            w["part"] = String::utf8(part_name_cn(p));
            w["bleed"] = bleed[idx];
            w["bite"] = bite_min[idx] > 0;
            w["infected"] = infected_min[idx] > 0;
            wounds.append(w);
        }
    }
    d["wounds"] = wounds;
    d["db_stats"] = db.db_stats_dict();
    return d;
}

Dictionary CcbSurvivalState::save_dict() const {
    Dictionary d;
    d["rad"] = rad;
    d["iodine_min"] = iodine_min;
    d["pblue_min"] = pblue_min;
    d["antibiotic_min"] = antibiotic_min;
    d["rad_badge_rad"] = rad_badge_rad;
    d["changing"] = changing;
    d["wielded"] = String::utf8(wielded.c_str());
    d["skills"] = skills.to_dict();

    Array bag_arr;
    for (const auto &st : bag) {
        bag_arr.append(Array::make(String::utf8(st.id.c_str()), st.count, st.filthy ? 1 : 0, st.damage));
    }
    d["bag"] = bag_arr;

    Array worn_arr;
    for (const auto &wid : worn) worn_arr.append(String::utf8(wid.c_str()));
    d["worn"] = worn_arr;

    Array mut_arr;
    for (const auto &mid : mutations) mut_arr.append(String::utf8(mid.c_str()));
    d["mutations"] = mut_arr;

    Dictionary vit_d;
    for (const auto &[vk, vv] : vitamins) vit_d[String::utf8(vk.c_str())] = vv;
    d["vitamins"] = vit_d;

    Array bl, bi, inf;
    for (int p = 0; p < 6; ++p) {
        bl.append(bleed[static_cast<std::size_t>(p)]);
        bi.append(bite_min[static_cast<std::size_t>(p)]);
        inf.append(infected_min[static_cast<std::size_t>(p)]);
    }
    d["bleed"] = bl;
    d["bite_min"] = bi;
    d["infected_min"] = inf;

    Array corp_arr;
    for (const auto &c : corpses) {
        if (c.butchered) continue;
        Dictionary cd;
        cd["id"] = c.id;
        cd["mtype_id"] = String::utf8(c.mtype_id.c_str());
        cd["x"] = c.pos.x;
        cd["y"] = c.pos.y;
        cd["z"] = c.floor;
        cd["death_min"] = c.death_minute;
        cd["pulped"] = c.pulped;
        cd["revives"] = c.revives;
        corp_arr.append(cd);
    }
    d["corpses"] = corp_arr;
    return d;
}

void CcbSurvivalState::load_dict(const Dictionary &d) {
    rad = json_int(d, "rad", 0);
    iodine_min = json_int(d, "iodine_min", 0);
    pblue_min = json_int(d, "pblue_min", 0);
    antibiotic_min = json_int(d, "antibiotic_min", 0);
    rad_badge_rad = json_int(d, "rad_badge_rad", 0);
    changing = static_cast<bool>(d.get("changing", false));
    wielded = json_str(d, "wielded");
    if (d.get("skills", Variant()).get_type() == Variant::DICTIONARY) {
        skills.load_dict(d["skills"]);
    }
    bag.clear();
    if (d.get("bag", Variant()).get_type() == Variant::ARRAY) {
        const Array arr = d["bag"];
        for (int i = 0; i < arr.size(); ++i) {
            if (arr[i].get_type() != Variant::ARRAY) continue;
            const Array pair = arr[i];
            if (pair.size() >= 2) {
                const bool fl = pair.size() >= 3 && static_cast<int>(pair[2]) != 0;
                const int dm = pair.size() >= 4 ? static_cast<int>(pair[3]) : 0;
                add_bag_item(String(pair[0]).utf8().get_data(), static_cast<int>(pair[1]), fl, dm);
            }
        }
    }
    worn = json_str_array(d, "worn");
    mutations = json_str_array(d, "mutations");
    vitamins.clear();
    if (d.get("vitamins", Variant()).get_type() == Variant::DICTIONARY) {
        const Dictionary vd = d["vitamins"];
        const Array keys = vd.keys();
        for (int i = 0; i < keys.size(); ++i) {
            const std::string k = String(keys[i]).utf8().get_data();
            vitamins[k] = static_cast<int>(vd[keys[i]]);
        }
    }
    if (d.get("bleed", Variant()).get_type() == Variant::ARRAY) {
        const Array arr = d["bleed"];
        for (int p = 0; p < 6 && p < arr.size(); ++p) bleed[static_cast<std::size_t>(p)] = static_cast<int>(arr[p]);
    }
    if (d.get("bite_min", Variant()).get_type() == Variant::ARRAY) {
        const Array arr = d["bite_min"];
        for (int p = 0; p < 6 && p < arr.size(); ++p) bite_min[static_cast<std::size_t>(p)] = static_cast<int>(arr[p]);
    }
    if (d.get("infected_min", Variant()).get_type() == Variant::ARRAY) {
        const Array arr = d["infected_min"];
        for (int p = 0; p < 6 && p < arr.size(); ++p) infected_min[static_cast<std::size_t>(p)] = static_cast<int>(arr[p]);
    }
    corpses.clear();
    if (d.get("corpses", Variant()).get_type() == Variant::ARRAY) {
        const Array arr = d["corpses"];
        for (int i = 0; i < arr.size(); ++i) {
            if (arr[i].get_type() != Variant::DICTIONARY) continue;
            const Dictionary cd = arr[i];
            CcbCorpse c;
            c.id = json_int(cd, "id", next_corpse_id++);
            next_corpse_id = std::max(next_corpse_id, c.id + 1);
            c.mtype_id = json_str(cd, "mtype_id", "mon_zombie");
            c.pos = Vector2i(json_int(cd, "x", 0), json_int(cd, "y", 0));
            c.floor = json_int(cd, "z", 0);
            c.death_minute = json_int(cd, "death_min", 0);
            c.pulped = static_cast<bool>(cd.get("pulped", false));
            c.butchered = static_cast<bool>(cd.get("butchered", false));
            c.revives = static_cast<bool>(cd.get("revives", true));
            corpses.push_back(std::move(c));
        }
    }
}

void CcbSurvivalState::apply_character_config(const Dictionary &cfg, CharacterState &cs) {
    const auto &db = CcbVanillaDB::instance();
    bag.clear();
    worn.clear();
    wielded.clear();
    mutations.clear();
    all_skills.clear();
    skills.reset();

    scenario_id = json_str(cfg, "scenario_id", "evacuee");
    profession_id = json_str(cfg, "profession_id", "unemployed");
    gender = json_str(cfg, "gender", "male");
    age = std::clamp(json_int(cfg, "age", 25), 16, 75);

    cs.stat_str = std::clamp(json_int(cfg, "str", 8), 4, 20);
    cs.stat_dex = std::clamp(json_int(cfg, "dex", 8), 4, 20);
    cs.stat_int = std::clamp(json_int(cfg, "int", 8), 4, 20);
    cs.stat_per = std::clamp(json_int(cfg, "per", 8), 4, 20);

    auto add_skill = [&](const std::string &sid, int delta) {
        all_skills[sid] = std::clamp(all_skills[sid] + delta, 0, 10);
        if (sid == "melee") skills.melee = all_skills[sid];
        else if (sid == "bashing") skills.bashing = all_skills[sid];
        else if (sid == "cutting") skills.cutting = all_skills[sid];
        else if (sid == "stabbing") skills.stabbing = all_skills[sid];
        else if (sid == "unarmed") skills.unarmed = all_skills[sid];
        else if (sid == "dodge") skills.dodge = all_skills[sid];
        else if (sid == "firstaid") skills.firstaid = all_skills[sid];
        else if (sid == "survival") skills.survival = all_skills[sid];
    };

    // Apply scenario forced traits
    if (const auto *sc = db.find_scenario(scenario_id)) {
        for (const auto &ft : sc->forced_traits) {
            if (!has_mutation(ft)) mutations.push_back(ft);
        }
    }

    // Apply profession worn, wielded, bag, skills, traits
    if (const auto *pr = db.find_profession(profession_id)) {
        for (const auto &w : pr->worn) {
            if (db.find_item(w)) worn.push_back(w);
        }
        if (!pr->wielded.empty() && db.find_item(pr->wielded)) {
            wielded = pr->wielded;
        }
        for (const auto &b : pr->bag) {
            if (db.find_item(b)) add_bag_item(b, 1);
        }
        for (const auto &[sn, lv] : pr->skills) add_skill(sn, lv);
        for (const auto &tr : pr->traits) {
            if (!has_mutation(tr)) mutations.push_back(tr);
        }
    }

    // Apply hobbies / backgrounds
    for (const auto &hid : json_str_array(cfg, "hobbies")) {
        if (const auto *hb = db.find_profession(hid)) {
            for (const auto &[sn, lv] : hb->skills) add_skill(sn, lv);
            for (const auto &tr : hb->traits) {
                if (!has_mutation(tr)) mutations.push_back(tr);
            }
            for (const auto &b : hb->bag) {
                if (db.find_item(b)) add_bag_item(b, 1);
            }
        }
    }

    // Apply chosen starting traits
    for (const auto &tid : json_str_array(cfg, "traits")) {
        if (db.find_mutation(tid) && !has_mutation(tid)) {
            mutations.push_back(tid);
        }
    }

    // Apply chosen skill points
    const Variant skv = cfg.get("skills", Variant());
    if (skv.get_type() == Variant::DICTIONARY) {
        const Dictionary skd = skv;
        const Array keys = skd.keys();
        for (int i = 0; i < keys.size(); ++i) {
            const std::string sid = String(keys[i]).utf8().get_data();
            const int lv = static_cast<int>(skd[keys[i]]);
            if (lv > 0) add_skill(sid, lv);
        }
    }

    // Ensure baseline vanilla clothes if profession had none (e.g. unemployed fallback)
    if (worn.empty()) {
        for (const char *id : {"jeans", "tshirt", "sneakers", "backpack"}) {
            if (db.find_item(id)) worn.emplace_back(id);
        }
    }
    if (bag.empty()) {
        for (const char *id : {"water_clean", "protein_bar_evac", "bandages", "flashlight"}) {
            if (db.find_item(id)) add_bag_item(id, 1);
        }
    }
}

int CcbSurvivalState::weapon_attack_moves() const {
    if (wielded.empty()) return 70; // Vanilla unarmed speed ~70 moves
    const auto *def = CcbVanillaDB::instance().find_item(wielded);
    if (!def) return 90;
    // Vanilla CCB attack_speed formula: 65 + volume(ml)/62.5 + weight(g)/60 (clamped 60..180)
    const int mv = 65 + def->vol_ml / 62 + def->weight_g / 60;
    return std::clamp(mv, 60, 180);
}

PackedStringArray CcbSurvivalState::worn_overlays() const {
    PackedStringArray out;
    for (const auto &wid : worn) {
        out.append(String("overlay_worn_") + String::utf8(wid.c_str()));
    }
    if (!wielded.empty()) {
        out.append(String("overlay_wielded_") + String::utf8(wielded.c_str()));
    }
    return out;
}

void CcbSurvivalState::add_blood(Vector2i p, int z, int intensity) {
    const int64_t k = infinite_tile_key(p, z);
    blood_tiles[k] = std::clamp(blood_tiles[k] + intensity, 1, 3);
}

void CcbSurvivalState::spawn_corpse(const std::string &mtype_id, Vector2i p, int z, int current_minute) {
    const auto *def = CcbVanillaDB::instance().find_monster(mtype_id);
    CcbCorpse c;
    c.id = next_corpse_id++;
    c.mtype_id = mtype_id;
    c.pos = p;
    c.floor = z;
    c.death_minute = current_minute;
    c.pulped = false;
    c.butchered = false;
    c.revives = def ? def->has_flag("REVIVES") : true;
    corpses.push_back(std::move(c));
    add_blood(p, z, 2);
}

bool CcbSurvivalState::has_corpse_at(Vector2i p, int z) const {
    for (const auto &c : corpses) {
        if (!c.butchered && c.pos == p && c.floor == z) return true;
    }
    return false;
}

Array CcbSurvivalState::corpses_at(Vector2i p, int z) const {
    Array out;
    const auto &db = CcbVanillaDB::instance();
    for (const auto &c : corpses) {
        if (c.butchered || c.pos != p || c.floor != z) continue;
        const auto *def = db.find_monster(c.mtype_id);
        Dictionary d;
        d["id"] = c.id;
        d["mtype_id"] = String::utf8(c.mtype_id.c_str());
        d["name"] = String::utf8(def ? def->name.c_str() : c.mtype_id.c_str()) +
                    (c.pulped ? String::utf8("的尸体（已捣烂）") : String::utf8("的尸体"));
        d["pulped"] = c.pulped;
        d["revives"] = c.revives && !c.pulped;
        d["death_minute"] = c.death_minute;
        d["tile"] = String("corpse_") + String::utf8(c.mtype_id.c_str());
        out.append(d);
    }
    return out;
}

String CcbSurvivalState::pulp_corpse_at(Vector2i p, int z) {
    const auto &db = CcbVanillaDB::instance();
    for (auto &c : corpses) {
        if (!c.butchered && !c.pulped && c.pos == p && c.floor == z) {
            c.pulped = true;
            add_blood(p, z, 1);
            const auto *def = db.find_monster(c.mtype_id);
            return String::utf8("你狠狠捣烂了「") +
                   String::utf8(def ? def->name.c_str() : c.mtype_id.c_str()) +
                   String::utf8("」的尸体，它不会再复活了！");
        }
    }
    return String();
}

String CcbSurvivalState::butcher_corpse_at(Vector2i p, int z, CharacterState &cs) {
    const auto &db = CcbVanillaDB::instance();
    for (auto it = corpses.begin(); it != corpses.end(); ++it) {
        if (!it->butchered && it->pos == p && it->floor == z) {
            const auto *def = db.find_monster(it->mtype_id);
            const String mname = String::utf8(def ? def->name.c_str() : it->mtype_id.c_str());
            const int64_t k = infinite_tile_key(p, z);
            auto yields = db.roll_harvest(it->mtype_id, [&](int lo, int hi) { return rng_range(lo, hi); });
            if (yields.empty()) {
                const bool is_zombie = def && (std::find(def->species.begin(), def->species.end(), "ZOMBIE") != def->species.end());
                const char *meat_id = is_zombie ? "meat_tainted_human" : "meat";
                if (db.find_item(meat_id)) yields.push_back({meat_id, 2, 0, false, 0});
                else if (db.find_item("meat_tainted")) yields.push_back({"meat_tainted", 2, 0, false, 0});
                if (db.find_item("bone_tainted") && is_zombie) yields.push_back({"bone_tainted", 2, 0, false, 0});
                else if (db.find_item("bone")) yields.push_back({"bone", 2, 0, false, 0});
            }
            String summary;
            for (const auto &st : yields) {
                world_items[k].push_back(st);
                const auto *idef = db.find_item(st.id);
                if (!summary.is_empty()) summary += String::utf8("、");
                summary += String::utf8(idef ? idef->name_zh.c_str() : st.id.c_str()) +
                           String::utf8("×") + String::num_int64(st.count);
            }
            add_blood(p, z, 2);
            cs.spend_stamina(300);
            skills.train(7, 18); // survival
            corpses.erase(it);
            return String::utf8("你解剖了「") + mname + String::utf8("」的尸体，获得了：") + summary + String::utf8("。");
        }
    }
    return String::utf8("此处没有可解剖的尸体。");
}

std::vector<std::pair<std::string, Vector2i>> CcbSurvivalState::collect_reviving_corpses(int current_minute, int z) {
    std::vector<std::pair<std::string, Vector2i>> revived;
    for (auto it = corpses.begin(); it != corpses.end(); ) {
        // Vanilla CCB zombies revive ~180..360 minutes after death unless pulped!
        if (!it->butchered && !it->pulped && it->revives && it->floor == z &&
            (current_minute - it->death_minute) >= 180) {
            revived.emplace_back(it->mtype_id, it->pos);
            it = corpses.erase(it);
        } else {
            ++it;
        }
    }
    return revived;
}

int CcbSurvivalState::skill_level_by_id(const std::string &sid) const {
    if (sid == "melee") return skills.melee;
    if (sid == "bashing") return skills.bashing;
    if (sid == "cutting") return skills.cutting;
    if (sid == "stabbing") return skills.stabbing;
    if (sid == "unarmed") return skills.unarmed;
    if (sid == "dodge") return skills.dodge;
    if (sid == "firstaid") return skills.firstaid;
    if (sid == "survival") return skills.survival;
    const auto it = all_skills.find(sid);
    return it == all_skills.end() ? 0 : it->second;
}

Array CcbSurvivalState::recipe_list(const String &category_filter, const String &query, int limit) const {
    Array out;
    const auto &db = CcbVanillaDB::instance();
    const int cap = std::clamp(limit, 1, 120);
    const std::string cat_f = category_filter.strip_edges().utf8().get_data();
    const std::string q_raw = query.strip_edges().utf8().get_data();
    const std::string q_low = to_lower_ascii(q_raw);

    // Build quick bag lookup
    std::unordered_map<std::string, int> inv;
    for (const auto &st : bag) inv[st.id] += st.count;

    auto craftable_check = [&](const CcbRecipeDef &r) -> bool {
        if (skill_level_by_id(r.skill_used) < r.difficulty) return false;
        for (const auto &slot : r.components) {
            bool ok = false;
            for (const auto &[iid, cnt] : slot) {
                if (inv[iid] >= cnt) { ok = true; break; }
            }
            if (!ok) return false;
        }
        return true;
    };

    // Sort craftable recipes first
    std::vector<std::pair<bool, const CcbRecipeDef *>> matches;
    for (const auto &r : db.all_recipes()) {
        if (!cat_f.empty() && cat_f != "ALL" && r.category != cat_f) continue;
        const auto *res_def = db.find_item(r.result);
        if (!res_def) continue;
        if (!q_low.empty()) {
            const bool m = (to_lower_ascii(r.result).find(q_low) != std::string::npos) ||
                           (to_lower_ascii(res_def->name_en).find(q_low) != std::string::npos) ||
                           (res_def->name_zh.find(q_raw) != std::string::npos);
            if (!m) continue;
        }
        matches.emplace_back(craftable_check(r), &r);
    }
    std::stable_sort(matches.begin(), matches.end(), [](const auto &a, const auto &b) {
        if (a.first != b.first) return a.first > b.first;
        return a.second->difficulty < b.second->difficulty;
    });

    for (const auto &[can_make, r] : matches) {
        const auto *res_def = db.find_item(r->result);
        Dictionary d;
        d["id"] = String::utf8(r->id.c_str());
        d["result"] = String::utf8(r->result.c_str());
        d["name"] = String::utf8(res_def->name_zh.c_str());
        d["category"] = String::utf8(r->category.c_str());
        d["subcategory"] = String::utf8(r->subcategory.c_str());
        d["result_info"] = db.item_to_dict(*res_def);
        Array comp_rows;
        for (std::size_t si = 0; si < r->components.size(); ++si) {
            Array alts_arr;
            for (const auto &[iid, cnt] : r->components[si]) {
                const auto *idef = db.find_item(iid);
                Dictionary cd;
                cd["id"] = String::utf8(iid.c_str());
                cd["name"] = String::utf8(idef ? idef->name_zh.c_str() : iid.c_str());
                cd["need"] = cnt;
                cd["have"] = inv[iid];
                alts_arr.append(cd);
            }
            comp_rows.append(alts_arr);
        }
        d["comp_slots"] = comp_rows;
        const auto *skd = db.find_skill(r->skill_used);
        d["skill_id"] = String::utf8(r->skill_used.c_str());
        d["skill_name"] = skd ? String::utf8(skd->name.c_str()) : String::utf8(r->skill_used.c_str());
        d["difficulty"] = r->difficulty;
        d["player_skill"] = skill_level_by_id(r->skill_used);
        d["time_min"] = r->time_min;
        d["can_craft"] = can_make;
        d["charges"] = r->charges;
        String reqs;
        for (std::size_t si = 0; si < r->components.size(); ++si) {
            if (si > 0) reqs += String::utf8(" + ");
            const auto &[iid, cnt] = r->components[si][0];
            const auto *idef = db.find_item(iid);
            const int have = inv[iid];
            reqs += String::utf8(idef ? idef->name_zh.c_str() : iid.c_str()) +
                    String("(") + String::num_int64(have) + String("/") + String::num_int64(cnt) + String(")");
        }
        d["requirements"] = reqs;
        d["desc"] = String::utf8(res_def->desc.c_str());
        out.append(d);
        if (out.size() >= cap) break;
    }
    return out;
}

String CcbSurvivalState::craft_recipe(const std::string &recipe_id, CharacterState &cs, int &out_time_min) {
    out_time_min = 0;
    const auto &db = CcbVanillaDB::instance();
    const auto *r = db.find_recipe(recipe_id);
    if (!r) return String::utf8("未找到该原版合成配方。");
    if (skill_level_by_id(r->skill_used) < r->difficulty) {
        return String::utf8("技能等级不足，无法制作该物品。");
    }
    // Verify & pick matching component per slot
    std::vector<std::pair<std::string, int>> to_consume;
    for (const auto &slot : r->components) {
        bool ok = false;
        for (const auto &[iid, cnt] : slot) {
            if (bag_count(iid) >= cnt) {
                to_consume.emplace_back(iid, cnt);
                ok = true;
                break;
            }
        }
        if (!ok) return String::utf8("行囊中缺少必需材料，无法制作。");
    }
    for (const auto &[iid, cnt] : to_consume) {
        consume_bag_item(iid, cnt);
    }
    add_bag_item(r->result, r->charges);
    out_time_min = r->time_min;
    cs.spend_stamina(std::min(600, r->time_min * 15));
    if (all_skills[r->skill_used] < r->difficulty + 2) {
        all_skills[r->skill_used] = std::min(10, all_skills[r->skill_used] + (one_in(3) ? 1 : 0));
    }
    const auto *res_def = db.find_item(r->result);
    return String::utf8("你花费 ") + String::num_int64(r->time_min) + String::utf8(" 分钟制作完成了「") +
           String::utf8(res_def ? res_def->name_zh.c_str() : r->result.c_str()) +
           String::utf8("」×") + String::num_int64(r->charges) + String::utf8("。");
}

} // namespace cangling
