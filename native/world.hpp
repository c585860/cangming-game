#pragma once

#include "character_state.hpp"
#include "city.hpp"
#include "item_catalog.hpp"
#include "multiplayer.hpp"
#include "skills.hpp"
#include "workstations.hpp"
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
    int coins = 10;
    int jobs_done = 0;
    double last_bake_ms = 0.0;
    std::array<bool, 4> collected{};
    std::array<int, kNpcCount> npc_talk_count{};
    std::unordered_set<int64_t> doors;
    std::unordered_map<int64_t, char> tile_overrides;
    std::unordered_set<int64_t> open_containers;
    std::unordered_map<int64_t, int> bash_damage;
    Vector2i grab_offset{0, 0};

    static constexpr int item_types = kItemCount;
    ItemCounts carried{};
    std::unordered_map<int64_t, ItemCounts> stored_items;
    std::unordered_set<int64_t> collected_props;
    std::unordered_map<int64_t, int> vessel_water;
    int carried_water = 500;
    CharacterState char_state;
    SkillSet skill_set;

    // Multiplayer hook state (offline default: local_peer_id=1, remote_players empty)
    int64_t local_peer_id = 1;
    godot::String player_name = godot::String::utf8("江湖少侠");
    std::unordered_map<int64_t, RemotePlayerState> remote_players;

    String generated_prop(Vector2i p);
    int generated_item(Vector2i p);
    static String item_name(int item);
    static bool is_movable_furniture(char tile);
    static bool is_openable_container(char tile);
    static bool is_climbable_tile(char tile);
    static bool is_smashable_tile(char tile);
    char effective_tile(Vector2i p, int z);
    ItemCounts items_on(Vector2i p);
    void materialize_tile_items(Vector2i p);
    String take_item(Vector2i p, int item);
    bool move_grabbed_furniture(Vector2i next_player_pos);
    void haul_items_from(Vector2i from, Vector2i to);
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
    int get_jobs_done() const { return jobs_done; }
    godot::Array npc_list() const;
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
    Dictionary props_in_rect(Rect2i area);
    Dictionary active_sites_in_rect(Rect2i area) const;
    void prewarm_area(Rect2i area);

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

    // CCB Open/Close, Smash, Climb, Haul, Wield, Apply, Read & Surroundings APIs
    String open_at(Vector2i p);
    String close_at(Vector2i p);
    String smash_at(Vector2i p);
    String climb_at(Vector2i p);
    bool is_container_open(Vector2i p) const;
    String grab_furniture(Vector2i target);
    String release_grab();
    Vector2i get_grab_offset() const { return grab_offset; }
    bool is_grabbing() const { return grab_offset != Vector2i(0, 0); }
    String wield_item(int item);
    String unwield();
    String apply_item(int item);
    String apply_wielded();
    String read_book(int item);
    String set_move_mode(int mode);
    String cycle_move_mode();
    String toggle_haul();
    String toggle_safe_mode();
    godot::Array list_nearby(int radius);
    godot::Array compass_summary();

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

    // Classic Wuxia MUD 4-Realm Skill System (20基础技艺, 开局无显示, <180请教/慢练, >=180研究)
    godot::Array skill_realms() const;
    godot::Array skill_list(const String &realm_filter = String("wuxue")) const;
    Dictionary skill_summary() const;
    int skill_level(const String &skill_id) const;
    int get_potential() const { return skill_set.potential; }
    int get_potential_cap() const { return skill_set.potential_cap(); }
    int get_combat_exp() const { return skill_set.combat_exp; }
    String practice_skill(const String &skill_id);
    String research_skill(const String &skill_id);
    String set_skill_jifa(const String &skill_id, const String &special_art_id);

    // Master NPC Teaching (learn) & 28 Multiplayer Physical Workstations (no lock, 2.5s bar)
    godot::Array npc_teach_list(Vector2i npc_pos) const;
    String learn_from_npc(Vector2i npc_pos, const String &skill_id);
    Dictionary workstation_at(Vector2i p) const;
    godot::Array list_workstations() const;
    godot::Array workstations_in_rect(Rect2i area) const;
    Dictionary can_work_at_station(Vector2i p) const;
    String complete_workstation(Vector2i p);

    // Multiplayer-Ready Sync, Remote Peer & Deterministic Action Interfaces
    int64_t get_local_peer_id() const { return local_peer_id; }
    void set_local_peer_id(int64_t id) { local_peer_id = id > 0 ? id : 1; }
    String get_player_name() const { return player_name; }
    void set_player_name(const String &name);
    Dictionary export_player_snapshot() const;
    bool apply_remote_snapshot(int64_t peer_id, const Dictionary &snapshot);
    void remove_remote_player(int64_t peer_id);
    void clear_remote_players();
    int remote_player_count() const { return static_cast<int>(remote_players.size()); }
    godot::Array list_remote_players() const;
    godot::Array remote_players_in_rect(Rect2i area) const;
    Dictionary submit_player_action(const Dictionary &action);

    // Multi-core CPU render baking & automatic memory management APIs
    Dictionary bake_region_data(Rect2i area, int z, int layers, const String &season);
    godot::PackedByteArray bake_ambient_data(Rect2i area, Rect2i region, int z, double outdoor_light, double sun_warmth);
    Dictionary bake_point_lights_data(Rect2i area, Rect2i region, int z, const Dictionary &sites, int seed_val);
    bool tick_memory(double delta_sec);
    int64_t trim_memory(bool aggressive);
    Dictionary perf_stats() const;
};
}
