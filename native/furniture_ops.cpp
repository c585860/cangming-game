#include "world.hpp"
#include <algorithm>
#include <string_view>

namespace cangling {
using namespace godot;

namespace {
constexpr std::string_view kMovableFurniture = "qStlCcaubkKrP";
constexpr std::string_view kOpenableContainers = "cCFKr";
constexpr std::string_view kFloorForFurniture = "i.:+=";

const char *furniture_label(char tile) {
    switch (tile) {
        case 'q': return "坐凳";
        case 'S': return "长椅";
        case 't': return "木桌";
        case 'l': return "书案";
        case 'C': return "货箱";
        case 'c': return "木柜";
        case 'a': return "陶缸";
        case 'u': return "水盆";
        case 'b': return "床榻";
        case 'k': return "长案";
        case 'K': return "展柜";
        case 'r': return "书架";
        case 'P': return "盆栽";
        case 'F': return "衣柜";
        default: return "家具";
    }
}
} // namespace

bool CanglingWorld::is_movable_furniture(char tile) {
    return kMovableFurniture.find(tile) != std::string_view::npos;
}

bool CanglingWorld::is_openable_container(char tile) {
    return kOpenableContainers.find(tile) != std::string_view::npos;
}

char CanglingWorld::effective_tile(Vector2i p, int z) {
    if (!in_city(p)) return ' ';
    const int64_t k = key(p, z);
    char tile = '\0';
    if (const auto it = tile_overrides.find(k); it != tile_overrides.end()) {
        tile = it->second;
    } else {
        tile = city.tile(p, z);
    }
    if ((tile == 'D' || tile == 'w') && doors.count(k)) {
        tile = (tile == 'D') ? 'o' : 'O';
    }
    return tile;
}

bool CanglingWorld::is_container_open(Vector2i p) const {
    return open_containers.count(key(p, floor)) != 0;
}

String CanglingWorld::open_at(Vector2i p) {
    if (!in_city(p) || !near(p)) return {};
    const int64_t k = key(p, floor);
    const char raw = effective_tile(p, floor);
    if (raw == 'D') {
        doors.insert(k);
        advance_time(1);
        return String::utf8("你打开了门。");
    }
    if (raw == 'w') {
        doors.insert(k);
        advance_time(1);
        return String::utf8("你推开了窗户。");
    }
    if (is_openable_container(raw)) {
        if (open_containers.count(k)) {
            return String::utf8(furniture_label(raw)) + String::utf8("已经是打开状态。");
        }
        open_containers.insert(k);
        advance_time(1);
        const String contents = fixture_contents(p);
        if (contents.is_empty()) {
            return String::utf8("你打开了") + String::utf8(furniture_label(raw)) + String::utf8("，里面空空如也。");
        }
        return String::utf8("你打开了") + String::utf8(furniture_label(raw)) + String::utf8("，里面放着：") + contents + String::utf8("。");
    }
    return {};
}

String CanglingWorld::close_at(Vector2i p) {
    if (!in_city(p) || !near(p)) return {};
    const int64_t k = key(p, floor);
    const char cur = effective_tile(p, floor);
    if (cur == 'o' && p != pos) {
        doors.erase(k);
        advance_time(1);
        return String::utf8("你关上了门。");
    }
    if (cur == 'O' && p != pos) {
        doors.erase(k);
        advance_time(1);
        return String::utf8("你关上了窗户。");
    }
    if (is_openable_container(cur)) {
        if (!open_containers.erase(k)) {
            return String::utf8(furniture_label(cur)) + String::utf8("本来就是关着的。");
        }
        advance_time(1);
        return String::utf8("你合上了") + String::utf8(furniture_label(cur)) + String::utf8("。");
    }
    return {};
}

String CanglingWorld::grab_furniture(Vector2i target) {
    if (!in_city(target) || !near(target) || target == pos) {
        return String::utf8("只能抓取紧邻身旁的家具。");
    }
    const char tile = effective_tile(target, floor);
    if (!is_movable_furniture(tile)) {
        return String::utf8("这里没有可以拖拽移动的家具。");
    }
    grab_offset = target - pos;
    return String::utf8("你抓住了") + String::utf8(furniture_label(tile)) + String::utf8("（移动即可推拉，再按 G 松手）。");
}

String CanglingWorld::release_grab() {
    if (grab_offset == Vector2i(0, 0)) return {};
    const Vector2i target = pos + grab_offset;
    const char tile = effective_tile(target, floor);
    grab_offset = {0, 0};
    return String::utf8("你松开了") + String::utf8(furniture_label(tile)) + String::utf8("。");
}

bool CanglingWorld::move_grabbed_furniture(Vector2i next_player_pos) {
    const Vector2i furn_from = pos + grab_offset;
    const Vector2i furn_to = next_player_pos + grab_offset;
    const char furn_tile = effective_tile(furn_from, floor);
    if (!is_movable_furniture(furn_tile)) {
        grab_offset = {0, 0};
        return false;
    }

    // Check destination for furniture (pulling into player's current tile is always valid!)
    const bool pulling_into_player = (furn_to == pos);
    if (!pulling_into_player) {
        if (!in_city(furn_to)) return false;
        if (floor == 0 && (furn_to == market_tile || furn_to == altar_tile || furn_to == dock_tile)) return false;
        const char dest_tile = effective_tile(furn_to, floor);
        if (kFloorForFurniture.find(dest_tile) == std::string_view::npos) {
            return false;
        }
    }

    // Also verify player can step onto next_player_pos (unless pushing furniture out of next_player_pos!)
    const bool pushing_from_next = (next_player_pos == furn_from);
    if (!pushing_from_next && !walkable(next_player_pos)) {
        return false;
    }

    // Transfer any materialized items, container state, and water along with the moved furniture!
    const int64_t k_from = key(furn_from, floor);
    const int64_t k_to = key(furn_to, floor);
    const ItemCounts moving_items = items_on(furn_from);
    collected_props.insert(k_from);
    stored_items.erase(k_from);

    // Preserve any existing items on destination tile + add moved furniture's items
    const ItemCounts dest_items = items_on(furn_to);
    collected_props.insert(k_to);
    ItemCounts merged = dest_items;
    bool has_any = false;
    for (int i = 0; i < item_types; ++i) {
        merged[i] = std::min(999, merged[i] + moving_items[i]);
        if (merged[i] > 0) has_any = true;
    }
    if (has_any) stored_items[k_to] = merged;
    else stored_items.erase(k_to);

    if (const auto wit = vessel_water.find(k_from); wit != vessel_water.end()) {
        const int ml = wit->second;
        vessel_water.erase(wit);
        vessel_water[k_to] = ml;
    } else if (furn_tile == 'a' || furn_tile == 'u') {
        const int default_ml = (furn_tile == 'a') ? (5000 * 3 / 4) : (1600 * 3 / 4);
        vessel_water[k_to] = default_ml;
    }

    if (open_containers.erase(k_from)) {
        open_containers.insert(k_to);
    }

    // Restore clean floor under furn_from, and place furn_tile at furn_to
    const bool indoor_from = (city.lighting_column(furn_from, floor, 1) & 1) != 0;
    tile_overrides[k_from] = indoor_from ? 'i' : '.';
    tile_overrides[k_to] = furn_tile;

    pos = next_player_pos;
    advance_time(2); // Dragging furniture takes slightly more effort (CCB-style)
    return true;
}

} // namespace cangling
