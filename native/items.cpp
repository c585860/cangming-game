#include "world.hpp"
#include <algorithm>
#include <limits>
#include <string_view>

namespace cangling {
using namespace godot;
namespace {
constexpr int max_stack = 999;

int number(const Variant &value, int low, int high) {
    if (value.get_type() != Variant::INT && value.get_type() != Variant::FLOAT) return -1;
    const double n = static_cast<double>(value);
    return n >= low && n <= high && n == static_cast<int>(n) ? static_cast<int>(n) : -1;
}

int capacity(char tile) { return tile == 'a' ? 5000 : tile == 'u' ? 1600 : 0; }

int64_t number64(const Variant &value) {
    if (value.get_type() != Variant::INT && value.get_type() != Variant::FLOAT) return std::numeric_limits<int64_t>::min();
    return static_cast<int64_t>(value);
}

Vector2i decode_key(int64_t key, int &z) {
    const int x = static_cast<int>((key % city_size + city_size) % city_size);
    const int64_t row = (key - x) / city_size;
    const int y = static_cast<int>((row % city_size + city_size) % city_size);
    const int64_t level = (row - y) / city_size;
    if (level < std::numeric_limits<int>::min() || level > std::numeric_limits<int>::max()) {
        z = std::numeric_limits<int>::min();
    } else {
        z = static_cast<int>(level);
    }
    return {x, y};
}

Dictionary make_item_dict(int i, int count) {
    const auto &def = item_catalog()[i];
    Dictionary row;
    row["id"] = i;
    row["key"] = def.key;
    row["name"] = String::utf8(def.name);
    row["count"] = count;
    row["tile"] = def.tile;
    row["category"] = String::utf8(category_label(def.category));
    row["is_food"] = (def.category == ItemCategory::Food);
    row["is_drink"] = (def.category == ItemCategory::Drink);
    row["is_clothing"] = (def.category == ItemCategory::Clothing);
    row["is_tool"] = (def.category == ItemCategory::Tool);
    row["is_book"] = (def.category == ItemCategory::Book);
    row["is_medical"] = (def.category == ItemCategory::Medical);
    row["is_weapon"] = (def.category == ItemCategory::Weapon);
    row["bash_dmg"] = def.bash_dmg;
    row["base_price"] = def.base_price;
    row["rain_resist"] = def.rain_resist;
    row["weapon_skill"] = String::utf8(def.weapon_skill);
    row["book_skill"] = String::utf8(def.book_skill);
    row["book_min_lit"] = def.book_min_lit;
    row["book_max_lv"] = def.book_max_lv;
    row["weight_g"] = def.weight_g;
    row["volume_ml"] = def.volume_ml;
    row["kcal"] = def.kcal;
    row["quench"] = def.quench;
    row["joy"] = def.joy;
    row["slot"] = String::utf8(wear_slot_label(def.slot));
    row["warmth"] = def.warmth;
    row["encumbrance"] = def.encumbrance;
    row["storage_ml"] = def.storage_ml;
    row["desc"] = String::utf8(def.desc);
    return row;
}
} // namespace

String CanglingWorld::item_name(int i) {
    if (i < 0 || i >= item_types) return {};
    return String::utf8(item_catalog()[i].name);
}

int CanglingWorld::generated_item(Vector2i p) {
    const auto prop = generated_prop(p);
    if (prop.is_empty()) return -1;
    const auto &cat = item_catalog();
    for (int i = 0; i < item_types; ++i) {
        if (prop == cat[i].key) return i;
    }
    return -1;
}

ItemCounts CanglingWorld::items_on(Vector2i p) {
    if (!in_city(p)) return {};
    const int64_t k = key(p, floor);
    ItemCounts count{};
    if (const auto it = stored_items.find(k); it != stored_items.end()) count = it->second;
    if (!collected_props.count(k) && city.layout >= 2) {
        const ItemCounts spawned = spawn_contextual_items(effective_tile(p, floor), city.surface(p, floor), seed, p, floor);
        for (int i = 0; i < item_types; ++i) count[i] += spawned[i];
    }
    return count;
}

void CanglingWorld::materialize_tile_items(Vector2i p) {
    if (!in_city(p)) return;
    const int64_t k = key(p, floor);
    if (collected_props.count(k)) return;
    const ItemCounts combined = items_on(p);
    collected_props.insert(k);
    if (std::any_of(combined.begin(), combined.end(), [](int n) { return n > 0; })) {
        stored_items[k] = combined;
    }
}

String CanglingWorld::prop_at(Vector2i p) {
    const char tile = effective_tile(p, floor);
    // Keep closed opaque wardrobes/cabinets/trunks clean outside until opened, while showing open-surface items on tables/beds/counters/floors!
    if (is_openable_container(tile) && !is_container_open(p) && tile != 'r') {
        return {};
    }
    const auto count = items_on(p);
    const auto &cat = item_catalog();
    for (int i = 0; i < item_types; ++i) {
        if (count[i]) return cat[i].tile;
    }
    return {};
}

Dictionary CanglingWorld::props_in_rect(Rect2i area) {
    Dictionary out;
    const Rect2i clipped = area.intersection(Rect2i(0, 0, city_size, city_size));
    if (clipped.size.x <= 0 || clipped.size.y <= 0) return out;
    const SectorGridSnapshot snap = city.snapshot_sectors(clipped);
    const auto &cat = item_catalog();
    const bool allow_spawn = (city.layout >= 2);
    const int x0 = clipped.position.x;
    const int y0 = clipped.position.y;
    const int x1 = x0 + clipped.size.x;
    const int y1 = y0 + clipped.size.y;

    for (int y = y0; y < y1; ++y) {
        const int sy = y / sector_size;
        const int ly = y - sy * sector_size;
        for (int x = x0; x < x1; ++x) {
            const Vector2i p(x, y);
            const int64_t k = key(p, floor);
            char tile = ' ';
            char surf = '\0';
            const int sx = x / sector_size;
            const Block *blk = snap.at(sx, sy);
            const int lidx = ly * sector_size + (x - sx * sector_size);
            if (blk) {
                tile = level_tiles(*blk, floor)[lidx];
                surf = level_surfaces(*blk, floor)[lidx];
            }
            if (!tile_overrides.empty()) {
                if (const auto ov = tile_overrides.find(k); ov != tile_overrides.end()) {
                    tile = ov->second;
                }
            }
            if ((tile == 'D' || tile == 'w') && !doors.empty() && doors.count(k)) {
                tile = (tile == 'D') ? 'o' : 'O';
            }
            if (tile == ' ' || tile == 'F') continue;
            if (is_openable_container(tile) && open_containers.count(k) == 0 && tile != 'r') continue;

            // Fast skip: tiles with no stored_items and non-spawning terrain (grass, roads, walls, water, floor)
            const auto sit = stored_items.find(k);
            const bool has_stored = (sit != stored_items.end());
            const bool can_spawn_here = allow_spawn && (collected_props.count(k) == 0) &&
                (tile == 'b' || tile == 't' || tile == 'l' || tile == 'k' || tile == 'r' ||
                 tile == 'c' || tile == 'C' || tile == 'K' || tile == 'q' || tile == 'S' ||
                 tile == 'h' || tile == 'u');
            if (!has_stored && !can_spawn_here) continue;

            ItemCounts counts{};
            if (has_stored) counts = sit->second;
            if (can_spawn_here) {
                const ItemCounts spawned = spawn_contextual_items(tile, surf, seed, p, floor);
                for (int i = 0; i < item_types; ++i) counts[i] += spawned[i];
            }
            for (int i = 0; i < item_types; ++i) {
                if (counts[i] > 0) {
                    out[p] = String(cat[i].tile);
                    break;
                }
            }
        }
    }
    return out;
}

Array CanglingWorld::inventory() const {
    Array result;
    for (int i = 0; i < item_types; ++i) {
        if (!carried[i]) continue;
        result.append(make_item_dict(i, carried[i]));
    }
    return result;
}

Array CanglingWorld::items_at(Vector2i p) {
    Array result;
    if (!in_city(p) || !items_exposed(p)) return result;
    const auto count = items_on(p);
    for (int i = 0; i < item_types; ++i) {
        if (!count[i]) continue;
        result.append(make_item_dict(i, count[i]));
    }
    return result;
}

bool CanglingWorld::items_exposed(Vector2i p) {
    const char tile = effective_tile(p, floor);
    return !is_openable_container(tile) || tile == 'r' || is_container_open(p);
}

int CanglingWorld::transfer_pickup(Vector2i p, int item, int requested, String &reason) {
    if (!in_city(p) || !near(p)) {
        reason = String::utf8("距离太远");
        return 0;
    }
    if (!items_exposed(p)) {
        reason = String::utf8("容器已关闭");
        return 0;
    }
    const int available = items_on(p)[item];
    const int stack_space = std::max(0, max_stack - carried[item]);
    const int unit_volume = item_catalog()[item].volume_ml;
    const int space = std::max(0, char_state.max_carry_volume_ml() - char_state.carry_volume_ml(carried));
    const int fitting = unit_volume > 0 ? space / unit_volume : requested;
    const int moved = std::min({requested, available, stack_space, fitting});
    if (moved < requested) {
        if (moved == available) reason = String::utf8("来源余量不足");
        else if (moved == stack_space) reason = String::utf8("同类堆叠已满");
        else reason = String::utf8("行囊容积不足");
    }
    if (moved == 0) return 0;

    materialize_tile_items(p);
    auto source = stored_items.find(key(p, floor));
    source->second[item] -= moved;
    carried[item] += moved;
    if (source->second[item] == 0 && std::none_of(source->second.begin(), source->second.end(), [](int n) { return n > 0; })) {
        stored_items.erase(source);
    }
    return moved;
}

Array CanglingWorld::pickup_items(const Array &requests) {
    Array results;
    for (int index = 0; index < requests.size(); ++index) {
        const Variant entry = requests[index];
        const Dictionary row = entry.get_type() == Variant::DICTIONARY ? Dictionary(entry) : Dictionary();
        const Variant tile = row.get("position", Variant()), level = row.get("floor", Variant());
        const int item = number(row.get("item", Variant()), 0, item_types - 1);
        const int requested = number(row.get("quantity", Variant()), 1, std::numeric_limits<int>::max());
        int moved = 0;
        String reason;
        if (item < 0 || requested < 1 || tile.get_type() != Variant::VECTOR2I || level.get_type() != Variant::INT) {
            reason = String::utf8("拾取条目无效");
        } else if (static_cast<int64_t>(level) != floor) {
            reason = String::utf8("来源位于其他楼层");
        } else {
            moved = transfer_pickup(tile, item, requested, reason);
        }
        Dictionary result;
        result["requested"] = std::max(0, requested);
        result["moved"] = moved;
        result["reason"] = reason;
        results.append(result);
    }
    return results;
}

String CanglingWorld::take_item(Vector2i p, int item) {
    if (item < 0 || item >= item_types || !in_city(p) || !near(p)) return {};
    String reason;
    if (transfer_pickup(p, item, 1, reason) == 0) return reason;
    return String::utf8("你拿起了") + item_name(item) + String::utf8("。");
}

String CanglingWorld::take_all_at(Vector2i p) {
    if (!in_city(p) || !near(p)) return {};
    if (!items_exposed(p)) return String::utf8("容器已关闭。");
    const auto counts = items_on(p);
    int requested = 0, picked = 0;
    String reason;
    for (int item = 0; item < item_types; ++item) {
        if (counts[item] == 0) continue;
        requested += counts[item];
        picked += transfer_pickup(p, item, counts[item], reason);
    }
    if (requested == 0) return String::utf8("此处没有可拾取的物品。");
    String msg = String::utf8("共拾取了 ") + String::num_int64(picked) + String::utf8(" 件物品。");
    if (picked < requested) {
        msg += String::utf8("剩余 ") + String::num_int64(requested - picked) + String::utf8(" 件留在原处。") + reason;
    }
    return msg;
}

String CanglingWorld::place_item(Vector2i p, int i) {
    if (!in_city(p) || !near(p) || i < 0 || i >= item_types || !carried[i]) return {};
    const char tile = effective_tile(p, floor);
    if (p != pos && std::string_view("btckKlruCaFqSi.:+=").find(tile) == std::string_view::npos) return {};
    materialize_tile_items(p);
    auto &count = stored_items[key(p, floor)][i];
    if (count >= max_stack) return String::utf8("这里已经堆不下了。");
    ++count;
    --carried[i];
    return String::utf8("你放下了") + item_name(i) + String::utf8("。");
}

int CanglingWorld::water_capacity_at(Vector2i p) { return capacity(effective_tile(p, floor)); }

int CanglingWorld::water_at(Vector2i p) {
    const int limit = water_capacity_at(p);
    if (limit == 0) return 0;
    const auto it = vessel_water.find(key(p, floor));
    return it != vessel_water.end() ? it->second : limit * 3 / 4;
}

String CanglingWorld::transfer_water(Vector2i p, int amount, bool fill_bottle) {
    const int limit = water_capacity_at(p);
    if (limit == 0 || !near(p) || amount <= 0) return {};
    const int original = water_at(p);
    const int available = fill_bottle ? std::min(original, bottle_capacity() - carried_water) :
                          std::min(carried_water, limit - original);
    const int moved = std::min(amount, available);
    if (!moved) return String::utf8("无水可倒，或容器已满。");
    const int delta = fill_bottle ? moved : -moved;
    carried_water += delta;
    vessel_water[key(p, floor)] = original - delta;
    return (fill_bottle ? String::utf8("你装入水壶 ") : String::utf8("你倒回容器 ")) +
           String::num_int64(moved) + String::utf8(" 毫升水。");
}

void CanglingWorld::clear_items() {
    carried.fill(0);
    stored_items.clear();
    collected_props.clear();
    vessel_water.clear();
    carried_water = 0;
}

Dictionary CanglingWorld::item_state() const {
    Dictionary data;
    Array bag, taken, placed, water;
    for (int count : carried) bag.append(count);
    for (int64_t k : collected_props) taken.append(k);
    for (const auto &[k, counts] : stored_items) {
        for (int i = 0; i < item_types; ++i) {
            if (counts[i]) placed.append(Array::make(static_cast<int64_t>(k), i, counts[i]));
        }
    }
    for (const auto &[k, count] : vessel_water) water.append(Array::make(static_cast<int64_t>(k), count));
    data["bag"] = bag;
    data["taken"] = taken;
    data["placed"] = placed;
    data["water"] = water;
    data["bottle_ml"] = carried_water;
    return data;
}

bool CanglingWorld::restore_item_state(const Dictionary &data, City &loaded) {
    for (const char *name : {"bag", "taken", "placed", "water"}) {
        if (data.get(name, Variant()).get_type() != Variant::ARRAY) return false;
    }
    const Array bag = data["bag"], taken = data["taken"], placed = data["placed"], water = data["water"];
    ItemCounts next_bag{};
    decltype(collected_props) next_taken;
    decltype(stored_items) next_placed;
    decltype(vessel_water) next_water;
    const int bottle = number(data.get("bottle_ml", Variant()), 0, bottle_capacity());
    if (bottle < 0 || bag.size() > item_types) return false;
    for (int i = 0; i < bag.size(); ++i) {
        next_bag[i] = number(bag[i], 0, max_stack);
        if (next_bag[i] < 0) return false;
    }
    for (int i = 0; i < taken.size(); ++i) {
        const int64_t k = number64(taken[i]);
        if (k == std::numeric_limits<int64_t>::min()) return false;
        int z = 0;
        const Vector2i p = decode_key(k, z);
        if (!in_city(p) || z == std::numeric_limits<int>::min()) return false;
        next_taken.insert(k);
    }
    for (int i = 0; i < placed.size(); ++i) {
        if (placed[i].get_type() != Variant::ARRAY) return false;
        const Array row = placed[i];
        if (row.size() != 3) return false;
        const int64_t k = number64(row[0]);
        const int item = number(row[1], 0, item_types - 1), n = number(row[2], 1, max_stack);
        int z = 0;
        const Vector2i p = decode_key(k, z);
        if (k == std::numeric_limits<int64_t>::min() || !in_city(p) || z == std::numeric_limits<int>::min() || item < 0 || n < 0) return false;
        next_placed[k][item] = n;
    }
    for (int i = 0; i < water.size(); ++i) {
        if (water[i].get_type() != Variant::ARRAY) return false;
        const Array row = water[i];
        if (row.size() != 2) return false;
        const int64_t k = number64(row[0]);
        if (k == std::numeric_limits<int64_t>::min()) return false;
        int z = 0;
        const Vector2i p = decode_key(k, z);
        if (!in_city(p) || z == std::numeric_limits<int>::min()) return false;
        const int limit = capacity(loaded.tile(p, z));
        const int n = number(row[1], 0, std::max(limit, 5000));
        if (n < 0) return false;
        next_water[k] = n;
    }
    carried = next_bag;
    stored_items = std::move(next_placed);
    vessel_water = std::move(next_water);
    collected_props = std::move(next_taken);
    carried_water = bottle;
    return true;
}
}
