#pragma once

#include "city.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <unordered_set>
#include <unordered_map>
#include <cstdint>

namespace cangling {
class CanglingWorld : public godot::RefCounted {
    GDCLASS(CanglingWorld, godot::RefCounted)

    City city;
    std::uint32_t seed = 0;
    Vector2i pos = start_tile;
    int floor = 0;
    int minutes = 440;
    int quest = 0;
    int herbs = 0;
    int coins = 0;
    std::array<bool, 4> collected{};
    std::unordered_set<int64_t> doors;
    static constexpr int item_types = 10;
    using ItemCounts = std::array<int,item_types>;
    ItemCounts carried{};
    std::unordered_map<int64_t,ItemCounts> stored_items;
    std::unordered_set<int64_t> collected_props;
    std::unordered_map<int64_t,int> vessel_water;
    int carried_water = 0;
    String generated_prop(Vector2i p);
    int generated_item(Vector2i p);
    static String item_name(int item);
    ItemCounts items_on(Vector2i p);
    String take_item(Vector2i p, int item);
    Dictionary item_state() const;
    bool restore_item_state(const Dictionary &state, City &loaded);
    void clear_items();
    static int64_t key(Vector2i p, int z) { return (static_cast<int64_t>(z) * city_size + p.y) * city_size + p.x; }
    godot::StringName site(Vector2i p);
    bool walkable_on(Vector2i p, int z);
    std::vector<Vector2i> local_path(Vector2i from, Vector2i to, Rect2i bounds, int z);
    std::vector<Vector2i> sector_path(Vector2i from, Vector2i to) const;
    std::vector<Vector2i> find_path(Vector2i to);
    String run_quest_action(Vector2i target, const godot::StringName &kind);
    String fixture_contents(Vector2i p);
protected:
    static void _bind_methods();
public:
    void setup(int64_t new_seed);
    int64_t get_seed() const { return seed; }
    Vector2i get_pos() const { return pos; }
    int get_floor() const { return floor; }
    int get_minutes() const { return minutes; }
    void advance_time(int amount);
    int get_quest() const { return quest; }
    int get_herbs() const { return herbs; }
    int get_coins() const { return coins; }
    Vector2i get_city_size() const { return {city_size, city_size}; }
    int get_sector_size() const { return sector_size; }
    String get_quest_text() const;
    Dictionary get_landmarks() const { return city.landmarks(); }
    String location(Vector2i p) { return city.location(p); }
    String overview(Vector2i sector) const;
    godot::PackedByteArray city_survey() { return city.survey(); }
    int road_mask(Vector2i sector) const { return city.plan.road_mask(sector); }
    String terrain_at(Vector2i p);
    String terrain_at_level(Vector2i p, int z);
    int lighting_column(Vector2i p, int z, int layers) { return city.lighting_column(p, z, layers); }
    String surface_at(Vector2i p);
    String surface_at_level(Vector2i p, int z);
    String prop_at(Vector2i p);
    godot::Array inventory() const;
    String place_item(Vector2i p, int item);
    int water_at(Vector2i p);
    int water_capacity_at(Vector2i p);
    int bottle_water() const { return carried_water; }
    int bottle_capacity() const { return 750; }
    String transfer_water(Vector2i p, int amount, bool fill_bottle);
    godot::Array street_curve(Vector2i sector, int direction) const;
    bool walkable(Vector2i p) { return walkable_on(p, floor); }
    bool near(Vector2i p) const;
    godot::StringName site_at(Vector2i p) { return site(p); }
    bool move_one(Vector2i next);
    godot::Array route_to(Vector2i dest, bool interact_with_target);
    Dictionary actions_at(Vector2i p);
    String interact(Vector2i p, const String &action);
    String change_floor(int direction);
    bool save_game(const String &path) const;
    bool load_game(const String &path);
};
}
