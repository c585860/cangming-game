#pragma once

#include "bounties.hpp"
#include "ccb_overmap.hpp"
#include "ccb_vanilla.hpp"
#include "character_state.hpp"
#include "city.hpp"
#include "combat.hpp"
#include "core_packs.hpp"
#include "crafting.hpp"
#include "item_catalog.hpp"
#include "monsters.hpp"
#include "multiplayer.hpp"
#include "shops.hpp"
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
    SparSession spar_session;
    BountyTracker bounty_tracker;

    // Dual Core-Pack State (Cangming vs Cataclysm: Cleanwater Bomb)
    CorePackId active_pack = CorePackId::Cangming;
    std::string active_scenario = "evacuee";
    CcbOvermapManager ccb_overmap;
    std::unordered_set<int64_t> ccb_spawned_omts;
    int ccb_turn_moves = 0;
    int ccb_turn_seconds = 0;
    int world_city_size = 8;
    int world_city_spacing = 4;
    float world_monster_rate = 1.0f;
    MonsterManager monsters;
    CcbSurvivalState ccb_state;
    int kills = 0;
    godot::Array pending_ccb_messages;
    void ensure_ccb_loot_at(Vector2i p);
    void ensure_ccb_omt_populated(Vector2i center_wp);

    CraftEnv current_craft_env() const;
    bool is_pos_indoors(Vector2i p, int z);
    bool is_pos_near_hearth(Vector2i p, int z);

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
    int64_t key(Vector2i p, int z) const {
        if (active_pack == CorePackId::Cataclysm) return infinite_tile_key(p, z);
        return (static_cast<int64_t>(z) * city_size + p.y) * city_size + p.x;
    }
    bool in_bounds(Vector2i p) const {
        return active_pack == CorePackId::Cataclysm || in_city(p);
    }
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
    void setup_with_pack(const String &pack_slug, int64_t new_seed, const String &scenario_id = String("evacuee"));
    godot::Array list_core_packs() const;
    godot::Array list_ccb_scenarios() const;
    String get_pack_id() const;
    String get_pack_name() const;
    bool is_cataclysm_pack() const { return active_pack == CorePackId::Cataclysm; }

    // Vanilla CCB Core Pack APIs (10,366 items, 591 mutations, radiation, vanilla melee combat, infinite Overmap, turn-based engine, corpses)
    void setup_ccb_world(const Dictionary &world_cfg, const Dictionary &char_cfg);
    godot::Array ccb_list_scenarios() const;
    godot::Array ccb_list_professions(bool hobbies_only) const;
    godot::Array ccb_list_starting_traits() const;
    godot::Array ccb_list_skills() const;
    Dictionary ccb_overmap_slice(Vector2i center_omt, int radius);
    Vector2i ccb_world_to_omt(Vector2i wp) const;
    Dictionary ccb_render_rect(Rect2i area, int z);
    Dictionary ccb_advance_moves(int moves);
    Dictionary ccb_wait_turn();
    Dictionary ccb_wait_minutes(int mins);
    Dictionary ccb_sleep_minutes(int mins);
    godot::Array ccb_corpses_at(Vector2i p) const;
    String ccb_pulp_at(Vector2i p);
    String ccb_butcher_at(Vector2i p);
    godot::Array ccb_recipe_list(const String &category_filter, const String &query, int limit) const;
    String ccb_craft_recipe(const String &recipe_id);
    void ccb_teleport_debug(Vector2i target);
    int get_ccb_turn_seconds() const { return ccb_turn_seconds; }

    Dictionary ccb_db_stats() const;
    godot::Array ccb_search_items(const String &query, const String &subtype_filter, int limit) const;
    Dictionary ccb_status() const;
    godot::Array ccb_inventory() const;
    godot::Array ccb_worn() const;
    godot::Array ccb_items_at(Vector2i p);
    String ccb_wield(const String &item_id);
    String ccb_unwield();
    String ccb_wear(const String &item_id);
    String ccb_takeoff(const String &item_id);
    String ccb_use_item(const String &item_id);
    String ccb_take_item(Vector2i p, const String &item_id);
    String ccb_take_all_at(Vector2i p);
    String ccb_drop_item(const String &item_id);
    String ccb_give_item(const String &item_id, int count);
    String ccb_wash_item(const String &item_id);
    bool ccb_reorder_worn(int idx, int delta);
    String ccb_transfer_item(Vector2i from_pos, bool from_bag, Vector2i to_pos, bool to_bag, const String &item_id, int count);
    String ccb_craft_batch(const String &recipe_id, int batch_count);
    Dictionary ccb_pixel_minimap_data(int radius);
    Dictionary ccb_inspect_tile(Vector2i p);
    void ccb_set_overmap_note(Vector2i omt, const String &note);
    godot::Array ccb_search_overmap(const String &query, Vector2i from_omt, int radius);
    bool ccb_debug_spawn_monster(const String &mtype_id, Vector2i target);
    double ccb_tile_radiation(Vector2i p) const;
    godot::Array ccb_irradiate(double rads, bool bypass);
    godot::Array ccb_mutate_category(const String &cat_id);
    godot::Array ccb_purify();
    godot::Array pop_ccb_messages();

    godot::Array monsters_in_rect(Rect2i area) const;
    Dictionary monster_at(Vector2i p) const;
    Dictionary tick_monsters(int steps);
    Dictionary attack_monster_at(Vector2i p);
    int get_kills() const { return kills; }
    int alive_monster_count() const { return monsters.alive_count(); }

    Dictionary inspect_save_meta(const String &path) const;
    bool apply_world_mutation(const Dictionary &mut);

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
    String location(Vector2i p);
    String overview(Vector2i sector) const;
    godot::PackedByteArray city_survey() { return city.survey(); }
    int road_mask(Vector2i sector) const { return city.plan.road_mask(sector); }
    String terrain_at(Vector2i p);
    String terrain_at_level(Vector2i p, int z);
    int lighting_column(Vector2i p, int z, int layers);
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
    godot::Array special_art_list() const;
    godot::Array npc_special_teach_list(Vector2i npc_pos) const;
    String learn_special_from_npc(Vector2i npc_pos, const String &art_id);
    Dictionary workstation_at(Vector2i p) const;
    godot::Array list_workstations() const;
    godot::Array workstations_in_rect(Rect2i area) const;
    Dictionary can_work_at_station(Vector2i p) const;
    String complete_workstation(Vector2i p);

    // Phase 1: Shops, Bank, Pawn, Inn, Dazuo, Exert, Specialized Study
    Dictionary shop_info_at(Vector2i npc_pos) const;
    String buy_item_from(Vector2i npc_pos, int item_id);
    String sell_item_to(Vector2i npc_pos, int item_id);
    String bank_deposit(Vector2i npc_pos, int amount);
    String bank_withdraw(Vector2i npc_pos, int amount);
    String rent_inn_room_at(Vector2i npc_pos);
    Dictionary dazuo_cycle();
    String exert_action(const String &kind);
    String study_book_cycle(int item_id);

    // Phase 2: CCB Crafting (&), Dismantle (B), Ambient Temp/Wetness & Wuxia Sparring
    Dictionary craft_env_dict();
    godot::Array craft_recipe_list(const String &category_filter);
    Dictionary can_craft_recipe(const String &recipe_id);
    String complete_craft_recipe(const String &recipe_id);
    String dismantle_item(int item_id);
    void sync_environment(double ambient_c, double rain_intensity);
    Dictionary start_spar(Vector2i npc_pos);
    Dictionary step_spar_round();
    String stop_spar();
    Dictionary spar_status() const;

    // Phase 3: Central Square Notice Board Bounties & Jianghu Score
    godot::Array bounty_list() const;
    Dictionary active_bounty() const;
    String accept_bounty(int index);
    String abandon_bounty();
    String turn_in_bounty(Vector2i npc_pos);
    Vector2i notice_board_pos() const { return kNoticeBoardTile; }
    Dictionary player_score_dict() const;

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
