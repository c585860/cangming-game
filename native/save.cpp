#include "world.hpp"
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <limits>
#include <string_view>

namespace cangling {
using namespace godot;
namespace {
bool integer(const Variant &value, int64_t low, int64_t high) {
    if (value.get_type() != Variant::INT && value.get_type() != Variant::FLOAT) return false;
    const double n = static_cast<double>(value);
    return n >= low && n <= high && n == static_cast<int64_t>(n);
}

bool entry(const Dictionary &obj, const char *name, int64_t low, int64_t high) {
    return integer(obj.get(name, Variant()), low, high);
}
}

Dictionary CanglingWorld::inspect_save_meta(const String &path) const {
    Dictionary out;
    out["exists"] = false;
    if (!FileAccess::file_exists(path)) return out;
    const Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(path));
    if (parsed.get_type() != Variant::DICTIONARY) return out;
    const Dictionary data = parsed;
    const String pslug = data.get("pack_id", String("cangming"));
    const CorePackId pid = parse_core_pack_id(pslug.utf8().get_data());
    out["exists"] = true;
    out["path"] = path;
    out["version"] = data.get("version", 1);
    out["pack_id"] = String::utf8(core_pack_slug(pid));
    out["pack_name"] = String::utf8(core_pack_info(pid).name.c_str());
    out["player_name"] = data.get("player_name", pid == CorePackId::Cataclysm ? String::utf8("末日幸存者") : String::utf8("江湖少侠"));
    out["seed"] = data.get("seed", 0);
    out["minutes"] = data.get("minutes", 440);
    out["coins"] = data.get("coins", 0);
    out["kills"] = data.get("kills", 0);
    if (data.get("ccb_state", Variant()).get_type() == Variant::DICTIONARY) {
        const Dictionary cs = data["ccb_state"];
        out["rad"] = cs.get("rad", 0);
        const Variant mv = cs.get("mutations", Variant());
        out["mutations_count"] = (mv.get_type() == Variant::ARRAY) ? Array(mv).size() : 0;
    } else {
        out["rad"] = 0;
        out["mutations_count"] = 0;
    }
    return out;
}

bool CanglingWorld::save_game(const String &path) const {
    Dictionary data;
    data["version"] = 10;
    data["pack_id"] = String::utf8(core_pack_slug(active_pack));
    data["scenario"] = String::utf8(active_scenario.c_str());
    data["generator"] = city.layout;
    data["seed"] = static_cast<int64_t>(seed);
    data["pos"] = Array::make(pos.x, pos.y);
    data["floor"] = floor;
    data["minutes"] = minutes;
    data["quest"] = quest;
    data["herbs"] = herbs;
    data["coins"] = coins;
    data["jobs_done"] = jobs_done;
    data["kills"] = kills;
    data["player_name"] = player_name;
    data["skills"] = skill_set.save_dict();
    data["bounties"] = bounty_tracker.save_dict();
    if (active_pack == CorePackId::Cataclysm) {
        data["monsters"] = monsters.save_array();
        data["ccb_state"] = ccb_state.save_dict();
    }
    Array picked;
    for (std::size_t i = 0; i < collected.size(); ++i) if (collected[i]) picked.push_back(static_cast<int>(i));
    data["collected"] = picked;
    Array opened;
    for (int64_t d : doors) opened.push_back(d);
    data["doors"] = opened;
    data["items"] = item_state();
    data["character"] = char_state.save_dict();
    Array overrides;
    for (const auto &[k, ch] : tile_overrides) overrides.push_back(Array::make(k, static_cast<int>(ch)));
    data["tile_overrides"] = overrides;
    Array containers;
    for (int64_t c : open_containers) containers.push_back(c);
    data["open_containers"] = containers;
    const auto temporary = path + String(".tmp");
    const auto file = FileAccess::open(temporary, FileAccess::WRITE);
    if (file.is_null()) return false;
    const bool ok = file->store_string(JSON::stringify(data));
    file->close();
    return ok && DirAccess::rename_absolute(temporary, path) == OK;
}

bool CanglingWorld::load_game(const String &path) {
    if (!FileAccess::file_exists(path)) return false;
    const Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(path));
    if (parsed.get_type() != Variant::DICTIONARY) return false;
    const Dictionary data = parsed;
    if (!entry(data, "version", 1, 10) || !entry(data, "quest", 0, 4) || !entry(data, "minutes", 0, 1000000000) ||
        !entry(data, "herbs", 0, 4) || !entry(data, "coins", 0, 1000000000) || data.get("collected", Variant()).get_type() != Variant::ARRAY) return false;
    const int version = data["version"];
    const String pack_slug = (version >= 10 && data.get("pack_id", Variant()).get_type() == Variant::STRING)
        ? String(data["pack_id"]) : String("cangming");
    const CorePackId next_pack = parse_core_pack_id(pack_slug.utf8().get_data());
    const String next_scen = (version >= 10 && data.get("scenario", Variant()).get_type() == Variant::STRING)
        ? String(data["scenario"]) : String("evacuee");

    const Array picked = data["collected"];
    std::array<bool, 4> next_collected{};
    std::unordered_set<int64_t> next_doors;
    std::unordered_map<int64_t, char> next_overrides;
    std::unordered_set<int64_t> next_containers;
    auto next_seed = seed;
    Vector2i next_pos = start_tile;
    int next_floor = 0;
    int next_layout = generator_version;
    if (version >= 3) {
        if (!entry(data, "generator", 1, generator_version)) return false;
        next_layout = data["generator"];
        if (!entry(data, "seed", 0, std::numeric_limits<std::uint32_t>::max()) ||
            !entry(data, "floor", version >= 5 ? std::numeric_limits<int>::min() : 0, version >= 5 ? std::numeric_limits<int>::max() : 1) ||
            data.get("pos", Variant()).get_type() != Variant::ARRAY || data.get("doors", Variant()).get_type() != Variant::ARRAY) return false;
        next_seed = static_cast<int64_t>(data["seed"]);
        next_floor = data["floor"];
        const Array coords = data["pos"];
        const int64_t cmin = (next_pack == CorePackId::Cataclysm) ? -8000000LL : 0LL;
        const int64_t cmax = (next_pack == CorePackId::Cataclysm) ? 8000000LL : static_cast<int64_t>(city_size - 1);
        if (coords.size() != 2 || !integer(coords[0], cmin, cmax) || !integer(coords[1], cmin, cmax)) return false;
        next_pos = Vector2i(coords[0], coords[1]);
        for (int i = 0; i < picked.size(); ++i) {
            if (!integer(picked[i], 0, 3)) return false;
            next_collected[static_cast<int>(picked[i])] = true;
        }
        const Array saved_doors = data["doors"];
        City restored;
        restored.reset(next_seed, next_layout, next_pack);
        for (int i = 0; i < saved_doors.size(); ++i) {
            if (saved_doors[i].get_type() != Variant::INT && saved_doors[i].get_type() != Variant::FLOAT) return false;
            next_doors.insert(static_cast<int64_t>(saved_doors[i]));
        }
        if (version >= 6 && data.get("tile_overrides", Variant()).get_type() == Variant::ARRAY) {
            const Array ov = data["tile_overrides"];
            for (int i = 0; i < ov.size(); ++i) {
                if (ov[i].get_type() != Variant::ARRAY) continue;
                const Array pair = ov[i];
                if (pair.size() == 2) next_overrides[static_cast<int64_t>(pair[0])] = static_cast<char>(static_cast<int>(pair[1]));
            }
        }
        if (version >= 6 && data.get("open_containers", Variant()).get_type() == Variant::ARRAY) {
            const Array oc = data["open_containers"];
            for (int i = 0; i < oc.size(); ++i) next_containers.insert(static_cast<int64_t>(oc[i]));
        }
        if (version >= 4 && (data.get("items", Variant()).get_type() != Variant::DICTIONARY ||
            !restore_item_state(data["items"], restored))) return false;
    } else {
        static const std::array<Vector2i, 4> legacy1{{{15,16},{17,18},{16,21},{19,22}}};
        static const std::array<Vector2i, 4> legacy2{{{110,68},{113,73},{110,79},{113,82}}};
        const auto &positions = version == 1 ? legacy1 : legacy2;
        for (int i = 0; i < picked.size(); ++i) {
            if (picked[i].get_type() != Variant::ARRAY) return false;
            const Array coords = picked[i];
            if (coords.size() != 2 || !integer(coords[0], 0, city_size - 1) || !integer(coords[1], 0, city_size - 1)) return false;
            const Vector2i point(coords[0], coords[1]);
            for (std::size_t j = 0; j < positions.size(); ++j) if (point == positions[j]) next_collected[j] = true;
        }
    }
    if (version < 4) clear_items();
    active_pack = next_pack;
    active_scenario = next_scen.utf8().get_data();
    city.reset(next_seed, next_layout, active_pack);
    seed = next_seed;
    pos = next_pos;
    floor = next_floor;
    collected = next_collected;
    doors = std::move(next_doors);
    tile_overrides = std::move(next_overrides);
    open_containers = std::move(next_containers);
    bash_damage.clear();
    grab_offset = {0, 0};
    quest = data["quest"];
    minutes = data["minutes"];
    herbs = data["herbs"];
    coins = data["coins"];
    jobs_done = entry(data, "jobs_done", 0, 1000000000) ? static_cast<int>(data["jobs_done"]) : 0;
    kills = entry(data, "kills", 0, 1000000000) ? static_cast<int>(data["kills"]) : 0;
    npc_talk_count.fill(0);
    char_state.reset_defaults();
    if (version >= 6 && data.get("character", Variant()).get_type() == Variant::DICTIONARY) {
        char_state.load_dict(data["character"]);
    }
    skill_set.reset_defaults();
    if (version >= 7 && data.get("skills", Variant()).get_type() == Variant::DICTIONARY) {
        skill_set.load_dict(data["skills"]);
    }
    bounty_tracker.reset();
    if (version >= 9 && data.get("bounties", Variant()).get_type() == Variant::DICTIONARY) {
        bounty_tracker.load_dict(data["bounties"]);
    }
    monsters.clear();
    ccb_spawned_omts.clear();
    ccb_turn_moves = 0;
    ccb_turn_seconds = 0;
    pending_ccb_messages.clear();
    if (active_pack == CorePackId::Cataclysm) {
        ccb_overmap.reset(seed, world_city_size, world_city_spacing, world_monster_rate);
        ccb_state.reset(seed, active_scenario);
        if (version >= 10 && data.get("ccb_state", Variant()).get_type() == Variant::DICTIONARY) {
            ccb_state.load_dict(data["ccb_state"]);
        }
        if (version >= 10 && data.get("monsters", Variant()).get_type() == Variant::ARRAY) {
            monsters.load_array(data["monsters"]);
        }
        ensure_ccb_omt_populated(pos);
    }
    spar_session.reset();
    char_state.sync_with_skills(skill_set);
    if (version >= 7 && data.get("player_name", Variant()).get_type() == Variant::STRING) {
        set_player_name(data["player_name"]);
    }
    remote_players.clear();
    return true;
}
}
