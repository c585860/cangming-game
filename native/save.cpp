#include "world.hpp"
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/json.hpp>
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

bool CanglingWorld::save_game(const String &path) const {
    Dictionary data;
    data["version"] = 6;
    data["generator"] = city.layout;
    data["seed"] = static_cast<int64_t>(seed);
    data["pos"] = Array::make(pos.x, pos.y);
    data["floor"] = floor;
    data["minutes"] = minutes;
    data["quest"] = quest;
    data["herbs"] = herbs;
    data["coins"] = coins;
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
    if (!entry(data, "version", 1, 6) || !entry(data, "quest", 0, 4) || !entry(data, "minutes", 0, 1000000000) ||
        !entry(data, "herbs", 0, 4) || !entry(data, "coins", 0, 1000000000) || data.get("collected", Variant()).get_type() != Variant::ARRAY) return false;
    const int version = data["version"];
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
        if (coords.size() != 2 || !integer(coords[0], 0, city_size - 1) || !integer(coords[1], 0, city_size - 1)) return false;
        next_pos = Vector2i(coords[0], coords[1]);
        for (int i = 0; i < picked.size(); ++i) {
            if (!integer(picked[i], 0, 3)) return false;
            next_collected[static_cast<int>(picked[i])] = true;
        }
        const Array saved_doors = data["doors"];
        City restored;
        restored.reset(next_seed, next_layout);
        for (int i = 0; i < saved_doors.size(); ++i) {
            if (saved_doors[i].get_type() != Variant::INT) return false;
            const int64_t k = saved_doors[i];
            next_doors.insert(k);
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
    city.reset(next_seed, next_layout);
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
    char_state.reset_defaults();
    if (version >= 6 && data.get("character", Variant()).get_type() == Variant::DICTIONARY) {
        char_state.load_dict(data["character"]);
    }
    return true;
}
}
