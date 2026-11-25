#pragma once

#include "character_state.hpp"
#include "city.hpp"
#include "item_catalog.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
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
    double last_bake_ms = 0.0;
    std::array<bool, 4> collected{};
    std::unordered_set<int64_t> doors;
    std::unordered_map<int64_t, char> tile_overrides;
    std::unordered_set<int64_t> open_containers;
    Vector2i grab_offset{0, 0};

    static constexpr int item_types = kItemCount;
    ItemCounts carried{};
    std::unordered_map<int64_t, ItemCounts> stored_items;
    std::unordered_set<int64_t> collected_props;
    std::unordered_map<int64_t, int> vessel_water;
    int carried_water = 500;
    CharacterState char_state;

    String generated_prop(Vector2i p);
    int generated_item(Vector2i p);
    static String item_name(int item);
    static bool is_movable_furniture(char tile);
    static bool is_openable_container(char tile);
    char effective_tile(Vector2i p, int z);
    ItemCounts items_on(Vector2i p);
    void materialize_tile_items(Vector2i p);
    String take_item(Vector2i p, int item);
    bool move_grabbed_furniture(Vector2i next_player_pos);
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
    CanglingWorld();
    ~CanglingWorld() override;
    void setup(int64_t new_seed);
    int64_t get_seed() const { return seed; }
    Vector2i get_pos() const { return pos; }
    int get_floor() const { return floor; }
    int get_minutes() const { return minutes; }
    void advance_time(int amount);
    void rest_minutes(int amount, bool sleeping);
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

    // CCB Item, Food/Drink, Wear & Container APIs
    godot::Array inventory() const;
    godot::Array items_at(Vector2i p);
    String take_item_at(Vector2i p, int item) { return take_item(p, item); }
    String take_all_at(Vector2i p);
    String place_item(Vector2i p, int item);
    String drop_item(int item) { return place_item(pos, item); }
    String eat_item(int item);
    String eat_item_at(Vector2i p, int item);
    String drink_bottle(int ml);
    String wear_item(int item);
    String take_off_item(int worn_index);
    Dictionary character_status() const;
    godot::PackedStringArray worn_overlays() const;

    // CCB Open/Close & Furniture Drag APIs
    String open_at(Vector2i p);
    String close_at(Vector2i p);
    bool is_container_open(Vector2i p) const;
    String grab_furniture(Vector2i target);
    String release_grab();
    Vector2i get_grab_offset() const { return grab_offset; }
    bool is_grabbing() const { return grab_offset != Vector2i(0, 0); }

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

    // Multi-core CPU render baking & automatic memory management APIs
    Dictionary bake_region_data(Rect2i area, int z, int layers, const String &season);
    godot::PackedByteArray bake_ambient_data(Rect2i area, Rect2i region, int z, double outdoor_light, double sun_warmth);
    Dictionary bake_point_lights_data(Rect2i area, Rect2i region, int z, const Dictionary &sites, int seed_val);
    bool tick_memory(double delta_sec);
    int64_t trim_memory(bool aggressive);
    Dictionary perf_stats() const;
};
}
