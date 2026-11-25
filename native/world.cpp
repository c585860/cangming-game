#include "world.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <string_view>

namespace cangling {
using namespace godot;

void CanglingWorld::_bind_methods() {
#define BIND(name, ...) ClassDB::bind_method(D_METHOD(#name, ##__VA_ARGS__), &CanglingWorld::name)
    BIND(setup, "seed"); BIND(get_seed); BIND(get_pos); BIND(get_floor); BIND(get_minutes); BIND(advance_time, "amount"); BIND(get_quest);
    BIND(get_herbs); BIND(get_coins); BIND(get_city_size); BIND(get_sector_size); BIND(get_quest_text);
    BIND(get_landmarks); BIND(location, "position"); BIND(overview, "sector"); BIND(road_mask, "sector");
    BIND(city_survey);
    BIND(lighting_column, "position", "z", "layers");
    BIND(terrain_at, "position"); BIND(terrain_at_level, "position", "z"); BIND(surface_at, "position"); BIND(surface_at_level, "position", "z"); BIND(prop_at, "position");
    BIND(inventory); BIND(place_item,"position","item"); BIND(water_at,"position");
    BIND(water_capacity_at,"position"); BIND(bottle_water); BIND(bottle_capacity);
    BIND(transfer_water,"position","amount_ml","fill_bottle");
    BIND(street_curve, "sector", "direction"); BIND(walkable, "position"); BIND(near, "position"); BIND(site_at, "position");
    BIND(move_one, "next"); BIND(route_to,"destination","interact_with_target");
    BIND(actions_at,"position"); BIND(interact,"position","action"); BIND(change_floor,"direction");
    BIND(save_game,"path"); BIND(load_game,"path");
#undef BIND
#define GETTER(name, type) ADD_PROPERTY(PropertyInfo(Variant::type, #name), "", "get_" #name)
    GETTER(seed,INT); GETTER(pos,VECTOR2I); GETTER(floor,INT); GETTER(minutes,INT); GETTER(quest,INT);
    GETTER(herbs,INT); GETTER(coins,INT); GETTER(city_size,VECTOR2I); GETTER(sector_size,INT);
    GETTER(quest_text,STRING); GETTER(landmarks,DICTIONARY);
#undef GETTER
}

void CanglingWorld::advance_time(int amount) {
    if (amount > 0) minutes += amount;
}

void CanglingWorld::setup(int64_t new_seed) {
    seed = static_cast<std::uint32_t>(new_seed);
    city.reset(seed);
    pos = start_tile;
    floor = quest = coins = herbs = 0;
    minutes = 440;
    collected.fill(false);
    doors.clear();
    clear_items();
}

String CanglingWorld::overview(Vector2i s) const { return String::chr(city.plan.overview(s)); }

String CanglingWorld::surface_at(Vector2i p) {
    return surface_at_level(p,floor);
}

String CanglingWorld::surface_at_level(Vector2i p, int z) {
    const char value = city.surface(p,z);
    return value ? String::chr(value) : String();
}

String CanglingWorld::terrain_at_level(Vector2i p, int z) {
    char tile = city.tile(p,z);
    if ((tile == 'D' || tile == 'w') && doors.count(key(p,z))) tile = tile == 'D' ? 'o' : 'O';
    return String::chr(tile);
}

Array CanglingWorld::street_curve(Vector2i s, int direction) const {
    Array points;
    if (direction < 0 || direction >= 4 || !city.plan.connected(s,direction)) return points;
    if (city.layout == 1) return Array::make(hub(s),hub(s+steps[direction]));
    for (const auto p : city.plan.road_path(s,direction)) points.append(p);
    return points;
}

String CanglingWorld::terrain_at(Vector2i p) {
    char tile = city.tile(p, floor);
    if (tile == 'D' && doors.count(key(p,floor))) tile = 'o';
    if (tile == 'w' && doors.count(key(p,floor))) tile = 'O';
    return String::chr(tile);
}

bool CanglingWorld::walkable_on(Vector2i p, int z) {
    if (!in_city(p)) return false;
    if (z == 0 && (p == market_tile || p == altar_tile || p == dock_tile)) return false;
    return passable_tile(city.tile(p,z));
}

bool CanglingWorld::near(Vector2i p) const {
    const auto delta = (pos-p).abs();
    return delta.x + delta.y <= 1;
}

bool CanglingWorld::move_one(Vector2i next) {
    if (pos == next || !near(next) || !walkable(next)) return false;
    if (city.tile(next,floor) == 'D' && !doors.count(key(next,floor))) {
        doors.insert(key(next,floor));
    } else {
        pos = next;
    }
    ++minutes;
    return true;
}
}
