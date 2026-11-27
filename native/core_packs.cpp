#include "core_packs.hpp"
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <mutex>

namespace cangling {
using namespace godot;

namespace {

int read_int_field(const Dictionary &d, const char *key, int fallback) {
    const Variant v = d.get(key, Variant());
    if (v.get_type() == Variant::INT || v.get_type() == Variant::FLOAT) {
        return static_cast<int>(v);
    }
    return fallback;
}

std::string read_str_field(const Dictionary &d, const char *key, const char *fallback) {
    const Variant v = d.get(key, Variant());
    if (v.get_type() == Variant::STRING) {
        const String s = v;
        if (!s.is_empty()) return std::string(s.utf8().get_data());
    }
    return fallback ? std::string(fallback) : std::string();
}

void merge_pack_json(CorePackInfo &info, const char *res_path) {
    if (!FileAccess::file_exists(res_path)) return;
    const Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(res_path));
    if (parsed.get_type() != Variant::DICTIONARY) return;
    const Dictionary d = parsed;
    info.name = read_str_field(d, "name", info.name.c_str());
    info.subtitle = read_str_field(d, "subtitle", info.subtitle.c_str());
    info.version = read_str_field(d, "version", info.version.c_str());
    info.author = read_str_field(d, "author", info.author.c_str());
    info.description = read_str_field(d, "description", info.description.c_str());
    info.theme_accent = read_str_field(d, "theme_accent", info.theme_accent.c_str());
    if (d.has("has_monsters")) info.has_monsters = static_cast<bool>(d["has_monsters"]);
    if (d.has("has_wuxia_npcs")) info.has_wuxia_npcs = static_cast<bool>(d["has_wuxia_npcs"]);
    const Variant fv = d.get("features", Variant());
    if (fv.get_type() == Variant::ARRAY) {
        const Array arr = fv;
        if (!arr.is_empty()) {
            info.features.clear();
            for (int i = 0; i < arr.size(); ++i) {
                if (arr[i].get_type() == Variant::STRING) {
                    info.features.emplace_back(String(arr[i]).utf8().get_data());
                }
            }
        }
    }
}

struct PackRegistry {
    std::vector<CorePackInfo> packs;
    std::vector<MonsterSpeciesDef> species;
    std::vector<ScenarioDef> scenarios;
    bool loaded = false;

    void ensure_loaded() {
        if (loaded) return;
        loaded = true;

        // 1. Default Core Packs (overridden by res://packs/*/pack.json when present)
        CorePackInfo cm;
        cm.id = CorePackId::Cangming;
        cm.slug = "cangming";
        cm.name = "沧溟修真 · 沧灵城";
        cm.subtitle = "江南武侠修真开放城镇核心包";
        cm.version = "1.0.0";
        cm.author = "Cangling Studio";
        cm.description = "240×240 纯手工江南水乡沧灵城：20门基础武学、8门高阶绝学与激发、打坐运功、13位江湖人物、28处无锁多人劳作工位、商铺钱庄当铺客栈、擂台切磋与江湖悬赏。";
        cm.theme_accent = "#57d1d6";
        cm.has_monsters = false;
        cm.has_wuxia_npcs = true;
        cm.features = {
            "240×240 江南水乡古镇 · 13位驻城人物 · 28处联机工位",
            "20门基础武学 + 8门激发绝学 + 打坐吐纳/运功疗伤",
            "7大商贸钱庄当铺客栈 · 实时切磋 · 告示牌悬赏",
            "完整共享 GPU 光影、四季雨雪与 ENet 多人联机"
        };
        merge_pack_json(cm, "res://packs/cangming/pack.json");

        CorePackInfo ccb;
        ccb.id = CorePackId::Cataclysm;
        ccb.slug = "cataclysm";
        ccb.name = "大灾变 · CCB 本体";
        ccb.subtitle = "Cataclysm: Cleanwater Bomb 末日生存核心包";
        ccb.version = "1.0.0";
        ccb.author = "Cataclysm-Cleanwater-Bomb";
        ccb.description = "接入 CCB 末日生存本体核心：程序化新英格兰灾变城镇、应急避难所开局、超市/药房/五金/警局/图书馆搜刮、丧尸与变异野犬 AI、安全模式预警、六部位伤痛战斗与完整 GPU 光影天气。";
        ccb.theme_accent = "#e66b4c";
        ccb.has_monsters = true;
        ccb.has_wuxia_npcs = false;
        ccb.features = {
            "程序化 240×240 新英格兰末日城镇与应急避难所",
            "6大经典 CCB 丧尸/变异兽物种 · 视听追踪与安全模式",
            "近战格斗、六部位创伤、战利品掉落与搜刮制作",
            "无缝接入现代沥青街景、GPU 动态光影、雨雪与联机"
        };
        merge_pack_json(ccb, "res://packs/cataclysm/pack.json");

        packs.push_back(std::move(cm));
        packs.push_back(std::move(ccb));

        // 2. Load CCB Core Data (monsters & scenarios) from packs/cataclysm/ccb_core_data.json
        if (FileAccess::file_exists("res://packs/cataclysm/ccb_core_data.json")) {
            const Variant parsed = JSON::parse_string(
                FileAccess::get_file_as_string("res://packs/cataclysm/ccb_core_data.json"));
            if (parsed.get_type() == Variant::DICTIONARY) {
                const Dictionary root = parsed;
                const Variant mv = root.get("monsters", Variant());
                if (mv.get_type() == Variant::ARRAY) {
                    const Array marr = mv;
                    for (int i = 0; i < marr.size(); ++i) {
                        if (marr[i].get_type() != Variant::DICTIONARY) continue;
                        const Dictionary md = marr[i];
                        MonsterSpeciesDef def;
                        def.id = read_str_field(md, "id", "mon_zombie");
                        def.name = read_str_field(md, "name", "普通丧尸");
                        def.tile = read_str_field(md, "tile", def.id.c_str());
                        def.max_hp = read_int_field(md, "hp", 72);
                        def.melee_dmg = read_int_field(md, "melee_dmg", 9);
                        def.speed = read_int_field(md, "speed", 75);
                        def.vision = read_int_field(md, "vision", 12);
                        def.hear_radius = read_int_field(md, "hear_radius", 18);
                        def.exp_reward = read_int_field(md, "exp_reward", 12);
                        def.pot_reward = read_int_field(md, "pot_reward", 8);
                        def.desc = read_str_field(md, "desc", "");
                        species.push_back(std::move(def));
                    }
                }
                const Variant sv = root.get("scenarios", Variant());
                if (sv.get_type() == Variant::ARRAY) {
                    const Array sarr = sv;
                    for (int i = 0; i < sarr.size(); ++i) {
                        if (sarr[i].get_type() != Variant::DICTIONARY) continue;
                        const Dictionary sd = sarr[i];
                        ScenarioDef sc;
                        sc.id = read_str_field(sd, "id", "evacuee");
                        sc.name = read_str_field(sd, "name", "避难所幸存者");
                        sc.desc = read_str_field(sd, "desc", "");
                        scenarios.push_back(std::move(sc));
                    }
                }
            }
        }

        // Built-in fallback guarantees zero failure even if JSON is absent
        if (species.empty()) {
            species = {
                {"mon_zombie", "普通丧尸", "mon_zombie", 72, 9, 70, 12, 18, 12, 8, "普通感染者。"},
                {"mon_zombie_runner", "疾行丧尸", "mon_zombie_runner", 58, 8, 115, 15, 20, 16, 11, "奔跑型丧尸。"},
                {"mon_zombie_tough", "壮硕丧尸", "mon_zombie_tough", 118, 14, 78, 13, 18, 22, 15, "强壮丧尸。"},
                {"mon_zombie_fat", "肥胖丧尸", "mon_zombie_fat", 96, 10, 58, 11, 16, 14, 9, "迟缓厚皮丧尸。"},
                {"mon_zombie_cop", "警装丧尸", "mon_zombie_cop", 105, 13, 85, 14, 20, 24, 16, "警员丧尸。"},
                {"mon_dog", "变异野犬", "mon_dog", 46, 7, 122, 16, 24, 13, 9, "变异流浪犬。"},
            };
        }
        if (scenarios.empty()) {
            scenarios = {
                {"evacuee", "避难所幸存者 (Evacuee)", "在应急避难所中醒来，搜刮城镇求生。"},
                {"scavenger", "废土拾荒客 (Scavenger)", "携带撬棍、手灯与急救绷带开局，适合夜间潜行搜刮。"},
            };
        }
    }
};

PackRegistry &registry() {
    static std::mutex mu;
    static PackRegistry reg;
    std::lock_guard<std::mutex> lock(mu);
    reg.ensure_loaded();
    return reg;
}

} // namespace

CorePackId parse_core_pack_id(std::string_view slug) {
    if (slug == "cataclysm" || slug == "ccb" || slug == "dda") {
        return CorePackId::Cataclysm;
    }
    return CorePackId::Cangming;
}

const char *core_pack_slug(CorePackId id) {
    return id == CorePackId::Cataclysm ? "cataclysm" : "cangming";
}

const CorePackInfo &core_pack_info(CorePackId id) {
    const auto &all = all_core_packs();
    return all[id == CorePackId::Cataclysm ? 1 : 0];
}

const std::vector<CorePackInfo> &all_core_packs() {
    return registry().packs;
}

const std::vector<MonsterSpeciesDef> &ccb_monster_species() {
    return registry().species;
}

const std::vector<ScenarioDef> &ccb_scenarios() {
    return registry().scenarios;
}

int find_monster_species_index(std::string_view species_id) {
    const auto &sp = ccb_monster_species();
    for (std::size_t i = 0; i < sp.size(); ++i) {
        if (sp[i].id == species_id) return static_cast<int>(i);
    }
    return 0;
}

Array list_core_packs_array() {
    Array out;
    const auto &all = all_core_packs();
    const bool ccb_repo_detected = DirAccess::dir_exists_absolute("res://../Cataclysm-Cleanwater-Bomb/data/json");
    for (const auto &p : all) {
        Dictionary d;
        d["id"] = String::utf8(p.slug.c_str());
        d["name"] = String::utf8(p.name.c_str());
        d["subtitle"] = String::utf8(p.subtitle.c_str());
        d["version"] = String::utf8(p.version.c_str());
        d["author"] = String::utf8(p.author.c_str());
        d["description"] = String::utf8(p.description.c_str());
        d["theme_accent"] = String::utf8(p.theme_accent.c_str());
        d["has_monsters"] = p.has_monsters;
        d["has_wuxia_npcs"] = p.has_wuxia_npcs;
        d["monster_species_count"] = p.has_monsters ? static_cast<int>(ccb_monster_species().size()) : 0;
        d["external_ccb_detected"] = (p.id == CorePackId::Cataclysm) && ccb_repo_detected;
        Array feats;
        for (const auto &f : p.features) {
            feats.append(String::utf8(f.c_str()));
        }
        d["features"] = feats;
        out.append(d);
    }
    return out;
}

Array list_ccb_scenarios_array() {
    Array out;
    for (const auto &sc : ccb_scenarios()) {
        Dictionary d;
        d["id"] = String::utf8(sc.id.c_str());
        d["name"] = String::utf8(sc.name.c_str());
        d["desc"] = String::utf8(sc.desc.c_str());
        out.append(d);
    }
    return out;
}

} // namespace cangling
