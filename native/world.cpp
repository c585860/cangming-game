#include "world.hpp"
#include "memory_manager.hpp"
#include "render_bake.hpp"
#include "thread_pool.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <string_view>

namespace cangling {
using namespace godot;

CanglingWorld::CanglingWorld() {
    ThreadPool::instance().ensure_started();
    char_state.reset_defaults();
    MemoryManager::instance().register_hook(
        this,
        "city_sector_cache",
        [this]() { return city.memory_bytes(); },
        [this](bool aggressive) {
            return city.trim_cache(aggressive ? 12u : 24u);
        });
}

CanglingWorld::~CanglingWorld() {
    MemoryManager::instance().unregister_owner(this);
}

void CanglingWorld::_bind_methods() {
#define BIND(name, ...) ClassDB::bind_method(D_METHOD(#name, ##__VA_ARGS__), &CanglingWorld::name)
    BIND(setup, "seed"); BIND(get_seed); BIND(get_pos); BIND(get_floor); BIND(get_minutes);
    BIND(advance_time, "amount"); BIND(rest_minutes, "amount", "sleeping");
    BIND(get_quest); BIND(get_herbs); BIND(get_coins); BIND(get_city_size); BIND(get_sector_size); BIND(get_quest_text);
    BIND(get_landmarks); BIND(location, "position"); BIND(overview, "sector"); BIND(road_mask, "sector");
    BIND(city_survey);
    BIND(lighting_column, "position", "z", "layers");
    BIND(terrain_at, "position"); BIND(terrain_at_level, "position", "z"); BIND(surface_at, "position"); BIND(surface_at_level, "position", "z"); BIND(prop_at, "position");
    BIND(props_in_rect, "area"); BIND(active_sites_in_rect, "area"); BIND(prewarm_area, "area");
    BIND(inventory); BIND(items_at, "position"); BIND(take_item_at, "position", "item"); BIND(take_all_at, "position");
    BIND(place_item, "position", "item"); BIND(drop_item, "item");
    BIND(eat_item, "item"); BIND(eat_item_at, "position", "item"); BIND(drink_bottle, "ml");
    BIND(wear_item, "item"); BIND(take_off_item, "worn_index");
    BIND(character_status); BIND(worn_overlays);
    BIND(open_at, "position"); BIND(close_at, "position"); BIND(smash_at, "position"); BIND(climb_at, "position");
    BIND(is_container_open, "position");
    BIND(grab_furniture, "target"); BIND(release_grab); BIND(get_grab_offset); BIND(is_grabbing);
    BIND(wield_item, "item"); BIND(unwield); BIND(apply_item, "item"); BIND(apply_wielded); BIND(read_book, "item");
    BIND(set_move_mode, "mode"); BIND(cycle_move_mode); BIND(toggle_haul); BIND(toggle_safe_mode);
    BIND(list_nearby, "radius"); BIND(compass_summary);
    BIND(water_at, "position"); BIND(water_capacity_at, "position"); BIND(bottle_water); BIND(bottle_capacity);
    BIND(transfer_water, "position", "amount_ml", "fill_bottle");
    BIND(street_curve, "sector", "direction"); BIND(walkable, "position"); BIND(near, "position"); BIND(site_at, "position");
    BIND(move_one, "next"); BIND(route_to, "destination", "interact_with_target");
    BIND(actions_at, "position"); BIND(interact, "position", "action"); BIND(change_floor, "direction");
    BIND(save_game, "path"); BIND(load_game, "path");
    BIND(bake_region_data, "area", "z", "layers", "season");
    BIND(bake_ambient_data, "area", "region", "z", "outdoor_light", "sun_warmth");
    BIND(bake_point_lights_data, "area", "region", "z", "sites", "seed");
    BIND(tick_memory, "delta_sec");
    BIND(trim_memory, "aggressive");
    BIND(perf_stats);
#undef BIND
#define GETTER(name, type) ADD_PROPERTY(PropertyInfo(Variant::type, #name), "", "get_" #name)
    GETTER(seed,INT); GETTER(pos,VECTOR2I); GETTER(floor,INT); GETTER(minutes,INT); GETTER(quest,INT);
    GETTER(herbs,INT); GETTER(coins,INT); GETTER(city_size,VECTOR2I); GETTER(sector_size,INT);
    GETTER(quest_text,STRING); GETTER(landmarks,DICTIONARY);
#undef GETTER
}

void CanglingWorld::advance_time(int amount) {
    if (amount > 0) {
        minutes += amount;
        char_state.advance_minutes(amount, false, false);
    }
}

void CanglingWorld::rest_minutes(int amount, bool sleeping) {
    if (amount > 0) {
        minutes += amount;
        char_state.advance_minutes(amount, !sleeping, sleeping);
    }
}

void CanglingWorld::setup(int64_t new_seed) {
    seed = static_cast<std::uint32_t>(new_seed);
    city.reset(seed);
    pos = start_tile;
    floor = quest = coins = herbs = 0;
    minutes = 440;
    collected.fill(false);
    doors.clear();
    tile_overrides.clear();
    open_containers.clear();
    bash_damage.clear();
    grab_offset = {0, 0};
    clear_items();
    char_state.reset_defaults();
    // Starting traveler provisions: flatbread, tea, portable Tung-oil lamp, tinderbox, bandages & water bottle
    carried[16] = 2; // 芝麻炊饼
    carried[23] = 1; // 江南清茶
    carried[41] = 1; // 桐油手灯
    carried[42] = 1; // 火折子
    carried[46] = 1; // 金创纱布
    carried_water = 500;
}

String CanglingWorld::overview(Vector2i s) const { return String::chr(city.plan.overview(s)); }

String CanglingWorld::surface_at(Vector2i p) {
    return surface_at_level(p, floor);
}

String CanglingWorld::surface_at_level(Vector2i p, int z) {
    const char value = city.surface(p, z);
    return value ? String::chr(value) : String();
}

String CanglingWorld::terrain_at_level(Vector2i p, int z) {
    return String::chr(effective_tile(p, z));
}

Array CanglingWorld::street_curve(Vector2i s, int direction) const {
    Array points;
    if (direction < 0 || direction >= 4 || !city.plan.connected(s, direction)) return points;
    if (city.layout == 1) return Array::make(hub(s), hub(s + steps[direction]));
    for (const auto p : city.plan.road_path(s, direction)) points.append(p);
    return points;
}

String CanglingWorld::terrain_at(Vector2i p) {
    return String::chr(effective_tile(p, floor));
}

bool CanglingWorld::walkable_on(Vector2i p, int z) {
    if (!in_city(p)) return false;
    if (z == 0 && (p == market_tile || p == altar_tile || p == dock_tile)) return false;
    return passable_tile(effective_tile(p, z));
}

bool CanglingWorld::near(Vector2i p) const {
    const auto delta = (pos - p).abs();
    return std::max(delta.x, delta.y) <= 1;
}

bool CanglingWorld::move_one(Vector2i next) {
    if (pos == next || !near(next)) return false;
    const Vector2i delta = next - pos;
    if (delta.x != 0 && delta.y != 0) {
        if (!walkable(pos + Vector2i(delta.x, 0)) && !walkable(pos + Vector2i(0, delta.y))) {
            return false;
        }
    }
    if (grab_offset != Vector2i(0, 0)) {
        return move_grabbed_furniture(next);
    }
    if (!walkable(next)) return false;
    const char tile = effective_tile(next, floor);
    if (tile == 'D') {
        doors.insert(key(next, floor));
        char_state.last_sound = 6;
        advance_time(1);
        return true;
    }
    const Vector2i prev = pos;
    pos = next;
    // CCB movement stance effects (0=Walk, 1=Run, 2=Crouch, 3=Prone)
    int step_cost = (tile == 'O' || tile == '%' || tile == 'b' || tile == 'q' || tile == 'S') ? 2 : 1;
    if (char_state.move_mode == 1) {
        if (char_state.stamina > 300) {
            char_state.spend_stamina(180);
            char_state.last_sound = 14;
            step_cost = 1;
        } else {
            char_state.move_mode = 0;
            char_state.last_sound = 6;
        }
    } else if (char_state.move_mode == 2) {
        char_state.last_sound = 2;
        step_cost = std::max(step_cost, 2);
    } else if (char_state.move_mode == 3) {
        char_state.last_sound = 0;
        step_cost = 3;
    } else {
        char_state.last_sound = (tile == 'O' || tile == '%') ? 10 : 6;
    }
    if (char_state.hauling) {
        haul_items_from(prev, pos);
    }
    advance_time(step_cost);
    return true;
}

String CanglingWorld::wield_item(int item) {
    const String msg = char_state.wield_from_bag(item, carried);
    if (msg.begins_with(String::utf8("你手持了"))) advance_time(1);
    return msg;
}

String CanglingWorld::unwield() {
    const String msg = char_state.unwield_to_bag(carried);
    if (msg.begins_with(String::utf8("你收起了"))) advance_time(1);
    return msg;
}

String CanglingWorld::apply_item(int item) {
    int mins = 0;
    const String msg = char_state.apply_item(item, carried, mins);
    if (mins > 0) advance_time(mins);
    return msg;
}

String CanglingWorld::apply_wielded() {
    if (char_state.wielded < 0) return String::utf8("你目前空手，没有手持物品可以使用。");
    int mins = 0;
    const String msg = char_state.apply_item(char_state.wielded, carried, mins);
    if (mins > 0) advance_time(mins);
    return msg;
}

String CanglingWorld::read_book(int item) {
    if (item < 0 || item >= item_types || (carried[item] <= 0 && char_state.wielded != item)) {
        return String::utf8("你身上没有携带这本书籍。");
    }
    int mins = 0;
    const String msg = char_state.read_book(item, mins);
    if (mins > 0) rest_minutes(mins, false);
    return msg;
}

String CanglingWorld::set_move_mode(int mode) {
    char_state.move_mode = std::clamp(mode, 0, 3);
    return String::utf8("移动姿态切换为：") + char_state.move_mode_label() + String::utf8("。");
}

String CanglingWorld::cycle_move_mode() {
    char_state.move_mode = (char_state.move_mode + 1) % 4;
    return String::utf8("移动姿态切换为：") + char_state.move_mode_label() + String::utf8("。");
}

String CanglingWorld::toggle_haul() {
    if (grab_offset != Vector2i(0, 0)) {
        grab_offset = {0, 0};
    }
    char_state.hauling = !char_state.hauling;
    return char_state.hauling
        ? String::utf8("你开始沿地面拖运脚下物品（移动时将连带地面物品一起拖走，再按 \\ 停止）。")
        : String::utf8("你停止了拖运地面物品。");
}

String CanglingWorld::toggle_safe_mode() {
    char_state.safe_mode = !char_state.safe_mode;
    return char_state.safe_mode
        ? String::utf8("安全模式已开启。")
        : String::utf8("安全模式已关闭。");
}

String CanglingWorld::eat_item(int item) {
    int mins = 0;
    const String msg = char_state.consume_item(item, carried, mins);
    minutes += mins;
    return msg;
}

String CanglingWorld::eat_item_at(Vector2i p, int item) {
    if (!in_city(p) || !near(p) || item < 0 || item >= item_types) return {};
    if (items_on(p)[item] <= 0) return {};
    const auto &def = item_catalog()[item];
    if (def.category != ItemCategory::Food && def.category != ItemCategory::Drink) {
        return String::utf8("这件物品无法食用或饮用。");
    }
    materialize_tile_items(p);
    const int64_t k = key(p, floor);
    auto it = stored_items.find(k);
    if (it == stored_items.end() || it->second[item] <= 0) return {};
    ItemCounts temp{};
    temp[item] = 1;
    int mins = 0;
    const String msg = char_state.consume_item(item, temp, mins);
    if (temp[item] == 0) {
        if (--it->second[item] == 0 && std::none_of(it->second.begin(), it->second.end(), [](int n) { return n != 0; })) {
            stored_items.erase(it);
        }
        minutes += mins;
    }
    return msg;
}

String CanglingWorld::drink_bottle(int ml) {
    if (carried_water <= 0) return String::utf8("行囊水壶已空，可去水缸、水盆或河边取水。");
    const int take = std::min(std::max(ml, 1), carried_water);
    carried_water -= take;
    int mins = 0;
    const String msg = char_state.drink_water(take, mins);
    minutes += mins;
    return msg;
}

String CanglingWorld::wear_item(int item) {
    const String msg = char_state.wear_from_bag(item, carried);
    if (msg.begins_with(String::utf8("你穿上了"))) advance_time(1);
    return msg;
}

String CanglingWorld::take_off_item(int worn_index) {
    const String msg = char_state.take_off_to_bag(worn_index, carried);
    if (msg.begins_with(String::utf8("你脱下了"))) advance_time(1);
    return msg;
}

Dictionary CanglingWorld::character_status() const {
    return char_state.to_dict(carried, carried_water);
}

PackedStringArray CanglingWorld::worn_overlays() const {
    return char_state.worn_overlays();
}

Dictionary CanglingWorld::active_sites_in_rect(Rect2i area) const {
    Dictionary out;
    if (floor != 0) return out;
    if (area.has_point(market_tile)) out[market_tile] = StringName("merchant");
    if (area.has_point(altar_tile)) out[altar_tile] = StringName("altar");
    if (area.has_point(dock_tile)) out[dock_tile] = StringName("ferryman");
    for (std::size_t i = 0; i < herb_tiles.size(); ++i) {
        if (!collected[i] && area.has_point(herb_tiles[i])) {
            out[herb_tiles[i]] = StringName("herb");
        }
    }
    return out;
}

void CanglingWorld::prewarm_area(Rect2i area) {
    const Rect2i clipped = area.intersection(Rect2i(0, 0, city_size, city_size));
    if (clipped.size.x > 0 && clipped.size.y > 0) {
        city.prewarm_sectors(clipped);
    }
}

Dictionary CanglingWorld::bake_region_data(Rect2i area, int z, int layers, const String &season) {
    return RenderBaker::bake_region(city, doors, tile_overrides, area, z, layers, season, last_bake_ms);
}

PackedByteArray CanglingWorld::bake_ambient_data(Rect2i area, Rect2i region, int z, double outdoor_light, double sun_warmth) {
    return RenderBaker::bake_ambient(city, doors, tile_overrides, area, region, z,
        static_cast<float>(outdoor_light), static_cast<float>(sun_warmth));
}

Dictionary CanglingWorld::bake_point_lights_data(Rect2i area, Rect2i region, int z, const Dictionary &sites, int seed_val) {
    return RenderBaker::bake_point_lights(city, doors, tile_overrides, area, region, z, sites, seed_val);
}

bool CanglingWorld::tick_memory(double delta_sec) {
    MemoryManager::instance().tick(delta_sec);
    return MemoryManager::instance().consume_script_trim_signal();
}

int64_t CanglingWorld::trim_memory(bool aggressive) {
    return static_cast<int64_t>(MemoryManager::instance().trim_now(aggressive));
}

Dictionary CanglingWorld::perf_stats() const {
    Dictionary out;
    const auto &pool = ThreadPool::instance();
    const auto mem = MemoryManager::instance().stats();
    out["hardware_threads"] = pool.hardware_threads();
    out["cpu_threads"] = pool.worker_count();
    out["tasks_executed"] = static_cast<int64_t>(pool.tasks_executed());
    out["cached_sectors"] = static_cast<int64_t>(city.cached_sector_count());
    out["memory_kb"] = static_cast<double>(mem.current_bytes) / 1024.0;
    out["auto_freed_kb"] = static_cast<double>(mem.total_freed_bytes) / 1024.0;
    out["auto_trim_count"] = static_cast<int64_t>(mem.auto_trim_count);
    out["last_bake_ms"] = last_bake_ms;
    return out;
}
}
