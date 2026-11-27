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
        [this]() { return city.memory_bytes() + ccb_overmap.memory_bytes(); },
        [this](bool aggressive) {
            return city.trim_cache(aggressive ? 12u : 24u) +
                   ccb_overmap.trim_cache(aggressive ? 24u : 64u);
        });
}

CanglingWorld::~CanglingWorld() {
    MemoryManager::instance().unregister_owner(this);
}

void CanglingWorld::_bind_methods() {
#define BIND(name, ...) ClassDB::bind_method(D_METHOD(#name, ##__VA_ARGS__), &CanglingWorld::name)
    BIND(setup, "seed"); BIND(setup_with_pack, "pack_id", "seed", "scenario_id");
    BIND(setup_ccb_world, "world_cfg", "char_cfg");
    BIND(list_core_packs); BIND(list_ccb_scenarios);
    BIND(ccb_list_scenarios); BIND(ccb_list_professions, "hobbies_only");
    BIND(ccb_list_starting_traits); BIND(ccb_list_skills);
    BIND(ccb_overmap_slice, "center_omt", "radius"); BIND(ccb_world_to_omt, "world_pos");
    BIND(ccb_render_rect, "area", "z");
    BIND(ccb_advance_moves, "moves"); BIND(ccb_wait_turn);
    BIND(ccb_wait_minutes, "mins"); BIND(ccb_sleep_minutes, "mins");
    BIND(ccb_corpses_at, "position"); BIND(ccb_pulp_at, "position"); BIND(ccb_butcher_at, "position");
    BIND(ccb_recipe_list, "category_filter", "query", "limit"); BIND(ccb_craft_recipe, "recipe_id");
    BIND(ccb_teleport_debug, "target"); BIND(get_ccb_turn_seconds);
    BIND(get_pack_id); BIND(get_pack_name); BIND(is_cataclysm_pack);
    BIND(ccb_db_stats); BIND(ccb_search_items, "query", "subtype_filter", "limit");
    BIND(ccb_status); BIND(ccb_inventory); BIND(ccb_worn); BIND(ccb_items_at, "position");
    BIND(ccb_wield, "item_id"); BIND(ccb_unwield);
    BIND(ccb_wear, "item_id"); BIND(ccb_takeoff, "item_id");
    BIND(ccb_use_item, "item_id"); BIND(ccb_take_item, "position", "item_id");
    BIND(ccb_take_all_at, "position");
    BIND(ccb_drop_item, "item_id"); BIND(ccb_give_item, "item_id", "count");
    BIND(ccb_wash_item, "item_id"); BIND(ccb_reorder_worn, "idx", "delta");
    BIND(ccb_transfer_item, "from_pos", "from_bag", "to_pos", "to_bag", "item_id", "count");
    BIND(ccb_craft_batch, "recipe_id", "batch_count");
    BIND(ccb_pixel_minimap_data, "radius"); BIND(ccb_inspect_tile, "position");
    BIND(ccb_set_overmap_note, "omt", "note"); BIND(ccb_search_overmap, "query", "from_omt", "radius");
    BIND(ccb_debug_spawn_monster, "mtype_id", "target");
    BIND(ccb_tile_radiation, "position"); BIND(ccb_irradiate, "rads", "bypass");
    BIND(ccb_mutate_category, "cat_id"); BIND(ccb_purify); BIND(pop_ccb_messages);
    BIND(monsters_in_rect, "area"); BIND(monster_at, "position");
    BIND(tick_monsters, "steps"); BIND(attack_monster_at, "position");
    BIND(get_kills); BIND(alive_monster_count);
    BIND(inspect_save_meta, "path"); BIND(apply_world_mutation, "mutation");
    BIND(get_seed); BIND(get_pos); BIND(get_floor); BIND(get_minutes);
    BIND(advance_time, "amount"); BIND(rest_minutes, "amount", "sleeping");
    BIND(get_quest); BIND(get_herbs); BIND(get_coins); BIND(get_jobs_done); BIND(npc_list);
    BIND(get_city_size); BIND(get_sector_size); BIND(get_quest_text);
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
    BIND(skill_realms);
    BIND(skill_list, "realm_filter");
    BIND(skill_summary);
    BIND(skill_level, "skill_id");
    BIND(get_potential);
    BIND(get_potential_cap);
    BIND(get_combat_exp);
    BIND(practice_skill, "skill_id");
    BIND(research_skill, "skill_id");
    BIND(set_skill_jifa, "skill_id", "special_art_id");
    BIND(npc_teach_list, "npc_pos");
    BIND(learn_from_npc, "npc_pos", "skill_id");
    BIND(special_art_list);
    BIND(npc_special_teach_list, "npc_pos");
    BIND(learn_special_from_npc, "npc_pos", "art_id");
    BIND(workstation_at, "pos");
    BIND(list_workstations);
    BIND(workstations_in_rect, "area");
    BIND(can_work_at_station, "pos");
    BIND(complete_workstation, "pos");
    BIND(shop_info_at, "npc_pos");
    BIND(buy_item_from, "npc_pos", "item_id");
    BIND(sell_item_to, "npc_pos", "item_id");
    BIND(bank_deposit, "npc_pos", "amount");
    BIND(bank_withdraw, "npc_pos", "amount");
    BIND(rent_inn_room_at, "npc_pos");
    BIND(dazuo_cycle);
    BIND(exert_action, "kind");
    BIND(study_book_cycle, "item_id");
    BIND(craft_env_dict);
    BIND(craft_recipe_list, "category_filter");
    BIND(can_craft_recipe, "recipe_id");
    BIND(complete_craft_recipe, "recipe_id");
    BIND(dismantle_item, "item_id");
    BIND(sync_environment, "ambient_c", "rain_intensity");
    BIND(start_spar, "npc_pos");
    BIND(step_spar_round);
    BIND(stop_spar);
    BIND(spar_status);
    BIND(bounty_list);
    BIND(active_bounty);
    BIND(accept_bounty, "index");
    BIND(abandon_bounty);
    BIND(turn_in_bounty, "npc_pos");
    BIND(notice_board_pos);
    BIND(player_score_dict);
    BIND(get_local_peer_id);
    BIND(set_local_peer_id, "id");
    BIND(get_player_name);
    BIND(set_player_name, "name");
    BIND(export_player_snapshot);
    BIND(apply_remote_snapshot, "peer_id", "snapshot");
    BIND(remove_remote_player, "peer_id");
    BIND(clear_remote_players);
    BIND(remote_player_count);
    BIND(list_remote_players);
    BIND(remote_players_in_rect, "area");
    BIND(submit_player_action, "action");
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
        if (active_pack == CorePackId::Cataclysm) {
            std::vector<String> msgs;
            ccb_state.tick_minute_effects(amount, ccb_overmap.radiation_at(pos), char_state, msgs);
            for (const auto &m : msgs) pending_ccb_messages.append(m);
            // Check zombie corpse revival!
            const auto revived = ccb_state.collect_reviving_corpses(minutes, floor);
            for (const auto &[mid, rpos] : revived) {
                if (monsters.spawn_one(mid, rpos, floor, true)) {
                    const auto *mdef = CcbVanillaDB::instance().find_monster(mid);
                    pending_ccb_messages.append(
                        String::utf8("[尸变复活] 「") +
                        String::utf8(mdef ? mdef->name.c_str() : mid.c_str()) +
                        String::utf8("」的尸体重新爬了起来！"));
                }
            }
        }
    }
}

void CanglingWorld::rest_minutes(int amount, bool sleeping) {
    if (amount > 0) {
        const bool inn_bonus = (active_pack == CorePackId::Cangming &&
                                floor == 1 && pos.x >= 108 && pos.x <= 117 && pos.y >= 104 && pos.y <= 113 &&
                                char_state.inn_room_until_min > minutes);
        char_state.advance_minutes(amount, !sleeping, sleeping, inn_bonus);
        if (active_pack == CorePackId::Cataclysm) {
            std::vector<String> msgs;
            ccb_state.tick_minute_effects(amount, ccb_overmap.radiation_at(pos), char_state, msgs);
            for (const auto &m : msgs) pending_ccb_messages.append(m);
            const auto revived = ccb_state.collect_reviving_corpses(minutes, floor);
            for (const auto &[mid, rpos] : revived) {
                if (monsters.spawn_one(mid, rpos, floor, true)) {
                    const auto *mdef = CcbVanillaDB::instance().find_monster(mid);
                    pending_ccb_messages.append(
                        String::utf8("[尸变复活] 「") +
                        String::utf8(mdef ? mdef->name.c_str() : mid.c_str()) +
                        String::utf8("」的尸体重新爬了起来！"));
                }
            }
        }
    }
}

void CanglingWorld::setup(int64_t new_seed) {
    setup_with_pack(String("cangming"), new_seed, String("evacuee"));
}

void CanglingWorld::setup_with_pack(const String &pack_slug, int64_t new_seed, const String &scenario_id) {
    active_pack = parse_core_pack_id(pack_slug.utf8().get_data());
    active_scenario = scenario_id.is_empty() ? std::string("evacuee") : std::string(scenario_id.utf8().get_data());
    seed = static_cast<std::uint32_t>(new_seed);
    city.reset(seed, generator_version, active_pack);
    floor = quest = herbs = jobs_done = kills = 0;
    minutes = 440;
    collected.fill(false);
    npc_talk_count.fill(0);
    doors.clear();
    tile_overrides.clear();
    open_containers.clear();
    bash_damage.clear();
    grab_offset = {0, 0};
    clear_items();
    char_state.reset_defaults();
    skill_set.reset_defaults();
    spar_session.reset();
    bounty_tracker.reset();
    monsters.clear();
    ccb_spawned_omts.clear();
    ccb_turn_moves = 0;
    ccb_turn_seconds = 0;
    pending_ccb_messages.clear();
    remote_players.clear();

    if (active_pack == CorePackId::Cataclysm) {
        ccb_overmap.reset(seed, world_city_size, world_city_spacing, world_monster_rate);
        const auto *sdef = CcbVanillaDB::instance().find_scenario(active_scenario);
        const std::string start_omt = sdef ? sdef->start_omt : std::string("shelter");
        pos = ccb_overmap.find_scenario_start(start_omt);
        coins = 0;
        carried_water = 500;
        if (player_name == String::utf8("江湖少侠")) {
            player_name = String::utf8("末日幸存者");
        }
        ccb_state.reset(seed, active_scenario);
        ensure_ccb_omt_populated(pos);
    } else {
        pos = start_tile;
        coins = 10;
        if (player_name == String::utf8("末日幸存者")) {
            player_name = String::utf8("江湖少侠");
        }
        char_state.sync_with_skills(skill_set);
        // Starting traveler provisions: flatbread, tea, portable Tung-oil lamp, tinderbox, bandages & water bottle
        carried[16] = 2; // 芝麻炊饼
        carried[23] = 1; // 江南清茶
        carried[41] = 1; // 桐油手灯
        carried[42] = 1; // 火折子
        carried[46] = 1; // 金创纱布
        carried_water = 500;
    }
}

Array CanglingWorld::list_core_packs() const { return list_core_packs_array(); }
Array CanglingWorld::list_ccb_scenarios() const { return list_ccb_scenarios_array(); }
String CanglingWorld::get_pack_id() const { return String::utf8(core_pack_slug(active_pack)); }
String CanglingWorld::get_pack_name() const { return String::utf8(core_pack_info(active_pack).name.c_str()); }

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

String CanglingWorld::location(Vector2i p) {
    if (active_pack == CorePackId::Cataclysm) return ccb_overmap.location_name(p);
    return city.location(p);
}

int CanglingWorld::lighting_column(Vector2i p, int z, int layers) {
    if (active_pack == CorePackId::Cataclysm) {
        return (z == 0 && ccb_overmap.enclosed_at(p)) ? 3 : 0;
    }
    return city.lighting_column(p, z, layers);
}

bool CanglingWorld::walkable_on(Vector2i p, int z) {
    if (!in_bounds(p)) return false;
    if (active_pack == CorePackId::Cangming && z == 0 && is_npc_tile(p)) return false;
    if (active_pack == CorePackId::Cataclysm) {
        if (monsters.has_alive_at(p, z)) return false;
        const char t = effective_tile(p, z);
        if (t == 'o' || t == 'O' || t == '%' || t == 'D') return true;
        return passable_tile(t);
    }
    return passable_tile(effective_tile(p, z));
}

bool CanglingWorld::near(Vector2i p) const {
    const auto delta = (pos - p).abs();
    return std::max(delta.x, delta.y) <= 1;
}

bool CanglingWorld::move_one(Vector2i next) {
    if (pos == next || !near(next)) return false;

    // Vanilla CCB: breaking free from monster grab & bump-to-attack (strictly turn-based / move-point driven!)
    if (active_pack == CorePackId::Cataclysm) {
        if (monsters.has_alive_at(next, floor)) {
            const Dictionary ar = attack_monster_at(next);
            const String msg = ar.get("message", String());
            if (!msg.is_empty()) pending_ccb_messages.append(msg);
            const int atk_moves = ccb_state.weapon_attack_moves();
            ccb_advance_moves(atk_moves);
            return true;
        }
        if (ccb_state.grab_intensity > 0) {
            const auto mods = ccb_state.compute_mods();
            const int eff_str = std::max(1, char_state.stat_str + mods.str_mod);
            if (ccb_state.rng_range(1, 14) <= eff_str) {
                ccb_state.grab_intensity = 0;
                pending_ccb_messages.append(String::utf8("你用力挣脱了丧尸的抓取！"));
            } else {
                pending_ccb_messages.append(String::utf8("你被紧紧抓住了，未能挣脱！"));
                ccb_advance_moves(100);
                return true;
            }
        }
    }

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
        if (active_pack == CorePackId::Cataclysm) ccb_advance_moves(100);
        return true;
    }
    const Vector2i prev = pos;
    pos = next;
    // CCB movement stance effects (0=Walk, 1=Run, 2=Crouch, 3=Prone)
    int step_moves = 100;
    if (char_state.move_mode == 1) {
        if (char_state.stamina > 300) {
            char_state.spend_stamina(180);
            char_state.last_sound = 14;
            step_moves = 55;
        } else {
            char_state.move_mode = 0;
            char_state.last_sound = 6;
            step_moves = 100;
        }
    } else if (char_state.move_mode == 2) {
        char_state.last_sound = 2;
        step_moves = 145;
    } else if (char_state.move_mode == 3) {
        char_state.last_sound = 0;
        step_moves = 220;
    } else {
        char_state.last_sound = (tile == 'O' || tile == '%') ? 10 : 6;
    }
    if (delta.x != 0 && delta.y != 0) {
        step_moves = (step_moves * 141) / 100; // Diagonal √2 move cost in CCB
    }
    if (char_state.hauling) {
        haul_items_from(prev, pos);
    }
    if (active_pack == CorePackId::Cangming) {
        if (spar_session.active && !near(spar_session.npc_pos)) {
            spar_session.reset();
        }
        bounty_tracker.update_proximity(pos, char_state.spar_total);
    } else {
        ensure_ccb_omt_populated(pos);
        // Step-driven radiation exposure & strict move-point turn advance!
        const float tile_rad = ccb_overmap.radiation_at(pos);
        if (tile_rad > 0.0f) {
            std::vector<String> rmsgs;
            ccb_state.last_tile_rad = tile_rad;
            ccb_state.irradiate(tile_rad * 0.2f, false, rmsgs);
            for (const auto &rm : rmsgs) pending_ccb_messages.append(rm);
        } else {
            ccb_state.last_tile_rad = 0.0f;
        }
        ccb_advance_moves(step_moves);
    }
    return true;
}

String CanglingWorld::wield_item(int item) {
    return char_state.wield_from_bag(item, carried);
}

String CanglingWorld::unwield() {
    return char_state.unwield_to_bag(carried);
}

String CanglingWorld::apply_item(int item) {
    int mins = 0;
    return char_state.apply_item(item, carried, mins);
}

String CanglingWorld::apply_wielded() {
    if (char_state.wielded < 0) return String::utf8("你目前空手，没有手持物品可以使用。");
    int mins = 0;
    return char_state.apply_item(char_state.wielded, carried, mins);
}

String CanglingWorld::read_book(int item) {
    return study_book_cycle(item);
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
    return char_state.consume_item(item, carried, mins);
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
    }
    return msg;
}

String CanglingWorld::drink_bottle(int ml) {
    if (carried_water <= 0) return String::utf8("行囊水壶已空，可去水缸、水盆或河边取水。");
    const int take = std::min(std::max(ml, 1), carried_water);
    carried_water -= take;
    int mins = 0;
    return char_state.drink_water(take, mins);
}

String CanglingWorld::wear_item(int item) {
    return char_state.wear_from_bag(item, carried);
}

String CanglingWorld::take_off_item(int worn_index) {
    return char_state.take_off_to_bag(worn_index, carried);
}

Dictionary CanglingWorld::character_status() const {
    Dictionary d = char_state.to_dict(carried, carried_water);
    d["pack_id"] = get_pack_id();
    d["pack_name"] = get_pack_name();
    d["kills"] = kills;
    d["alive_monsters"] = monsters.alive_count();
    if (active_pack == CorePackId::Cataclysm) {
        const Dictionary cs = ccb_state.status_dict(char_state);
        d["rad"] = cs["rad"];
        d["tile_rad"] = cs["tile_rad"];
        d["rad_badge_color"] = cs["rad_badge_color"];
        d["has_rad_badge"] = cs["has_rad_badge"];
        d["changing"] = cs["changing"];
        d["mutagen_catalyst"] = cs["mutagen_catalyst"];
        d["mutations"] = cs["mutations"];
        d["wounds"] = cs["wounds"];
        d["wielded_name"] = cs["wielded_name"];
        d["str"] = cs["eff_str"];
        d["dex"] = cs["eff_dex"];
        d["int"] = cs["eff_int"];
        d["per"] = cs["eff_per"];
        d["encumbrance"] = cs["encumbrance"];
        d["ccb"] = cs;
    }
    return d;
}

PackedStringArray CanglingWorld::worn_overlays() const {
    if (active_pack == CorePackId::Cataclysm) return ccb_state.worn_overlays();
    return char_state.worn_overlays();
}

Array CanglingWorld::npc_list() const {
    Array out;
    if (active_pack != CorePackId::Cangming) return out;
    for (const auto &npc : kYangzhouNpcs) {
        Dictionary row;
        row["id"] = StringName(npc.id);
        row["name"] = String::utf8(npc.name);
        row["title"] = String::utf8(npc.title);
        row["place"] = String::utf8(npc.title);
        row["pos"] = npc.pos;
        row["job"] = String::utf8(npc.job_label);
        row["job_label"] = String::utf8(npc.job_label);
        row["pay"] = npc.job_pay;
        row["job_pay"] = npc.job_pay;
        out.append(row);
    }
    return out;
}

Dictionary CanglingWorld::active_sites_in_rect(Rect2i area) const {
    Dictionary out;
    if (active_pack != CorePackId::Cangming || floor != 0) return out;
    for (const auto &npc : kYangzhouNpcs) {
        if (area.has_point(npc.pos)) {
            out[npc.pos] = StringName(npc.id);
        }
    }
    if (area.has_point(kNoticeBoardTile)) {
        out[kNoticeBoardTile] = StringName("notice_board");
    }
    return out;
}

void CanglingWorld::prewarm_area(Rect2i area) {
    if (active_pack == CorePackId::Cataclysm) {
        const Vector2i omt0 = CcbOvermapManager::world_to_omt(area.position);
        const Vector2i omt1 = CcbOvermapManager::world_to_omt(area.position + area.size);
        for (int oy = omt0.y; oy <= omt1.y; ++oy) {
            for (int ox = omt0.x; ox <= omt1.x; ++ox) {
                ccb_overmap.chunk_at_omt({ox, oy});
            }
        }
        return;
    }
    const Rect2i clipped = area.intersection(Rect2i(0, 0, city_size, city_size));
    if (clipped.size.x > 0 && clipped.size.y > 0) {
        city.prewarm_sectors(clipped);
    }
}

Dictionary CanglingWorld::bake_region_data(Rect2i area, int z, int layers, const String &season) {
    CcbOvermapManager *om = (active_pack == CorePackId::Cataclysm) ? &ccb_overmap : nullptr;
    return RenderBaker::bake_region(city, doors, tile_overrides, area, z, layers, season, last_bake_ms, om);
}

PackedByteArray CanglingWorld::bake_ambient_data(Rect2i area, Rect2i region, int z, double outdoor_light, double sun_warmth) {
    CcbOvermapManager *om = (active_pack == CorePackId::Cataclysm) ? &ccb_overmap : nullptr;
    return RenderBaker::bake_ambient(city, doors, tile_overrides, area, region, z,
        static_cast<float>(outdoor_light), static_cast<float>(sun_warmth), om);
}

Dictionary CanglingWorld::bake_point_lights_data(Rect2i area, Rect2i region, int z, const Dictionary &sites, int seed_val) {
    CcbOvermapManager *om = (active_pack == CorePackId::Cataclysm) ? &ccb_overmap : nullptr;
    return RenderBaker::bake_point_lights(city, doors, tile_overrides, area, region, z, sites, seed_val, om);
}

// ---------------------------------------------------------------------------
// Classic Wuxia MUD 4-Realm Skill System (武学 / 武道 / 练气 / 仙道)
// ---------------------------------------------------------------------------
Array CanglingWorld::skill_realms() const {
    return skill_set.realms_to_array();
}

Array CanglingWorld::skill_list(const String &realm_filter) const {
    return skill_set.skills_to_array(realm_filter);
}

Dictionary CanglingWorld::skill_summary() const {
    return skill_set.summary_dict();
}

int CanglingWorld::skill_level(const String &skill_id) const {
    return skill_set.level_of(skill_id.utf8().get_data());
}

String CanglingWorld::practice_skill(const String &skill_id) {
    const std::string sid = skill_id.utf8().get_data();
    const int idx = find_base_skill_index(sid);
    if (idx < 0) return String::utf8("未找到该项武学技艺。");
    const auto &def = base_skill_catalog()[static_cast<std::size_t>(idx)];
    const auto &st = skill_set.base[static_cast<std::size_t>(idx)];
    const String sname = String::utf8(def.name);
    if (st.level <= 0) {
        return String::utf8("你尚未习得「") + sname + String::utf8("」，无法凭空练习！请先前往「") +
               String::utf8(def.mentor_hint) + String::utf8("」请教入门。");
    }
    if (char_state.is_starving_for_training()) {
        return String::utf8("你腹中空空、气血虚浮（饱食/水分不足），强行练功恐伤经脉！请先吃些干粮喝口水。");
    }
    if (char_state.is_severely_injured()) {
        return String::utf8("你头部或躯干伤势较重，此时强行练功易动气血，请先用纱布包扎休养！");
    }
    if (char_state.stamina < 450 || char_state.fatigue > 88.0) {
        return String::utf8("你气息急促、耐力不足，先歇息片刻再行练习。");
    }

    // Classic Wuxia MUD slow practice (no potential cost; burns kcal + hydration + stamina!)
    char_state.spend_stamina(450);
    char_state.kcal = std::max(0.0, char_state.kcal - 32.0);
    char_state.hydration = std::max(0.0, char_state.hydration - 2.6);
    char_state.fatigue = std::min(100.0, char_state.fatigue + 1.6);

    double gain_f = 4.0 + static_cast<double>(char_state.stat_int) * 0.25 + static_cast<double>(char_state.focus) * 0.02;
    if (char_state.is_well_fed()) gain_f *= 1.25;
    const bool at_hall = near_martial_training_station(pos);
    if (at_hall) gain_f *= 1.35;
    const int gain = std::max(3, static_cast<int>(std::round(gain_f)));

    bool leveled = false;
    skill_set.add_exp(idx, gain, leveled);
    skill_set.add_combat_exp(2);
    char_state.sync_with_skills(skill_set);

    const auto &after = skill_set.base[static_cast<std::size_t>(idx)];
    const int need = skill_exp_to_next(after.level);
    const String srank = String::utf8(skill_rank_title(after.level));
    const String bonus_tag = at_hall ? String::utf8("（武馆演武加成）") : String();
    if (leveled) {
        return String::utf8("你潜心苦练「") + sname + String::utf8("」") + bonus_tag +
               String::utf8("，水到渠成！境界精进至 ") + String::num_int64(after.level) +
               String::utf8(" 级（") + srank + String::utf8("）！");
    }
    return String::utf8("你缓慢演练了一番「") + sname + String::utf8("」") + bonus_tag +
           String::utf8("，熟练度 +") + String::num_int64(gain) +
           String::utf8("（当前 ") + String::num_int64(after.level) + String::utf8(" 级 · ") +
           String::num_int64(after.exp) + String("/") + String::num_int64(need) + String::utf8("）。");
}

String CanglingWorld::research_skill(const String &skill_id) {
    const std::string sid = skill_id.utf8().get_data();
    const int idx = find_base_skill_index(sid);
    if (idx < 0) return String::utf8("未找到该项武学技艺。");
    const auto &def = base_skill_catalog()[static_cast<std::size_t>(idx)];
    const auto &st = skill_set.base[static_cast<std::size_t>(idx)];
    const String sname = String::utf8(def.name);
    if (st.level <= 0) {
        return String::utf8("你尚未习得「") + sname + String::utf8("」，无法进行研究！");
    }
    if (st.level < SkillSet::kResearchMinLevel) {
        return String::utf8("「") + sname + String::utf8("」当前仅 ") + String::num_int64(st.level) +
               String::utf8(" 级——按江湖规矩，180 级以前须耗潜能请教师傅或缓慢练习，唯有臻至 180 级后方可耗费潜能自行研究突破！");
    }
    const int pot_cost = skill_set.research_potential_cost(idx);
    if (skill_set.potential < pot_cost) {
        return String::utf8("潜能不足（研究需 ") + String::num_int64(pot_cost) +
               String::utf8(" 点，当前仅 ") + String::num_int64(skill_set.potential) + String::utf8(" 点）。");
    }
    if (char_state.is_starving_for_training()) {
        return String::utf8("你腹饥口渴、心神难凝，先吃饱喝足再来潜心研究吧。");
    }
    if (char_state.stamina < 600 || char_state.fatigue > 85.0) {
        return String::utf8("你精力倦乏，先歇息片刻再行研究。");
    }
    skill_set.spend_potential(pot_cost);
    char_state.spend_stamina(600);
    char_state.kcal = std::max(0.0, char_state.kcal - 38.0);
    char_state.hydration = std::max(0.0, char_state.hydration - 3.0);
    char_state.fatigue = std::min(100.0, char_state.fatigue + 2.2);

    const int gain = skill_set.research_exp_gain(char_state.stat_int);
    bool leveled = false;
    skill_set.add_exp(idx, gain, leveled);
    skill_set.add_combat_exp(6);
    char_state.sync_with_skills(skill_set);

    const auto &after = skill_set.base[static_cast<std::size_t>(idx)];
    const int need = skill_exp_to_next(after.level);
    if (leveled) {
        return String::utf8("你耗费 ") + String::num_int64(pot_cost) + String::utf8(" 点潜能潜心研究「") + sname +
               String::utf8("」，豁然开朗！突破至 ") + String::num_int64(after.level) + String::utf8(" 级（") +
               String::utf8(skill_rank_title(after.level)) + String::utf8("）！");
    }
    return String::utf8("你耗费 ") + String::num_int64(pot_cost) + String::utf8(" 点潜能参悟研究「") + sname +
           String::utf8("」，熟练度 +") + String::num_int64(gain) + String::utf8("（") +
           String::num_int64(after.exp) + String("/") + String::num_int64(need) + String::utf8("）。");
}

Array CanglingWorld::npc_teach_list(Vector2i npc_pos) const {
    Array out;
    const NpcDef *npc = npc_at_tile(npc_pos);
    if (npc == nullptr) return out;
    const std::string nid = npc->id;
    const auto &cat = base_skill_catalog();
    for (const auto &spec : master_teach_catalog()) {
        if (nid != spec.npc_id) continue;
        const int idx = find_base_skill_index(spec.skill_id);
        if (idx < 0) continue;
        const auto &def = cat[static_cast<std::size_t>(idx)];
        const auto &st = skill_set.base[static_cast<std::size_t>(idx)];
        const int pot_cost = skill_set.learn_potential_cost(idx);
        const int coin_cost = skill_set.learn_coin_cost(idx);
        const int exp_gain = skill_set.learn_exp_gain(char_state.stat_int);
        bool can = true;
        String reason;
        if (st.level >= spec.max_teach_level) {
            can = false;
            reason = String::utf8("已达此师所授上限");
        } else if (skill_set.potential < pot_cost) {
            can = false;
            reason = String::utf8("潜能不足");
        } else if (coins < coin_cost) {
            can = false;
            reason = String::utf8("铜钱不足");
        } else if (char_state.is_starving_for_training()) {
            can = false;
            reason = String::utf8("腹饥口渴，先吃喝");
        }
        Dictionary row;
        row["id"] = String::utf8(def.id);
        row["name"] = String::utf8(def.name);
        row["category"] = String::utf8(def.category);
        row["desc"] = String::utf8(def.desc);
        row["current_level"] = st.level;
        row["max_teach_level"] = spec.max_teach_level;
        row["pot_cost"] = pot_cost;
        row["coin_cost"] = coin_cost;
        row["exp_gain"] = exp_gain;
        row["can_learn"] = can;
        row["reason"] = reason;
        out.append(row);
    }
    return out;
}

String CanglingWorld::learn_from_npc(Vector2i npc_pos, const String &skill_id) {
    if (!near(npc_pos)) return String::utf8("请走近师傅身旁再行请教。");
    const NpcDef *npc = npc_at_tile(npc_pos);
    if (npc == nullptr) return String::utf8("那里没有可请教的师傅。");
    const std::string sid = skill_id.utf8().get_data();
    const MasterTeachSpec *matched = nullptr;
    for (const auto &spec : master_teach_catalog()) {
        if (std::string_view(spec.npc_id) == npc->id && sid == spec.skill_id) {
            matched = &spec;
            break;
        }
    }
    if (matched == nullptr) return String::utf8(npc->name) + String::utf8("并不传授此项技艺。");
    const int idx = find_base_skill_index(sid);
    if (idx < 0) return String::utf8("未知的技能代号。");
    const auto &def = base_skill_catalog()[static_cast<std::size_t>(idx)];
    auto &st = skill_set.base[static_cast<std::size_t>(idx)];
    const String sname = String::utf8(def.name);

    if (st.level >= matched->max_teach_level) {
        return String::utf8(npc->name) + String::utf8("抚须道：「你在『") + sname +
               String::utf8("』上的造诣已不逊于我所授上限（") + String::num_int64(matched->max_teach_level) +
               String::utf8("级），往后可自行勤加练习或另寻高人！」");
    }
    const int pot_cost = skill_set.learn_potential_cost(idx);
    const int coin_cost = skill_set.learn_coin_cost(idx);
    if (skill_set.potential < pot_cost) {
        return String::utf8("你的潜能不足（请教「") + sname + String::utf8("」需 ") +
               String::num_int64(pot_cost) + String::utf8(" 点潜能，当前仅 ") +
               String::num_int64(skill_set.potential) + String::utf8(" 点）。先去城中工位干活或听书攒潜能吧！");
    }
    if (coins < coin_cost) {
        return String::utf8("铜钱不足（向") + String::utf8(npc->name) + String::utf8("请教需备 ") +
               String::num_int64(coin_cost) + String::utf8(" 文束脩茶资）。");
    }
    if (char_state.is_starving_for_training()) {
        return String::utf8("你此刻饥肠辘辘、精神难集中，先吃些东西喝口水再来请教吧。");
    }
    if (char_state.stamina < 250) {
        return String::utf8("你气息未平，先歇息片刻再来请教。");
    }

    const bool was_unlearned = (st.level == 0);
    skill_set.spend_potential(pot_cost);
    coins -= coin_cost;
    char_state.spend_stamina(250);
    char_state.kcal = std::max(0.0, char_state.kcal - 16.0);
    char_state.hydration = std::max(0.0, char_state.hydration - 1.5);

    bool leveled = false;
    if (was_unlearned) {
        // First lesson cleanly unlocks Lv.1 so the skill immediately appears on the Skill Panel!
        st.level = 1;
        st.exp = 0;
        leveled = true;
    } else {
        const int gain = skill_set.learn_exp_gain(char_state.stat_int);
        skill_set.add_exp(idx, gain, leveled);
    }
    skill_set.add_combat_exp(4);
    char_state.sync_with_skills(skill_set);

    const int need = skill_exp_to_next(st.level);
    if (was_unlearned) {
        return String::utf8("你向") + String::utf8(npc->name) + String::utf8("执礼请教，耗费 ") +
               String::num_int64(pot_cost) + String::utf8(" 点潜能与 ") + String::num_int64(coin_cost) +
               String::utf8(" 文束脩，正式习得「") + sname + String::utf8("」（1 级 · 初学乍练）！现已在技能面板 [J] 显示，并可前往对应工位劳作。");
    }
    if (leveled) {
        return String::utf8(npc->name) + String::utf8("倾囊相授，你耗费 ") + String::num_int64(pot_cost) +
               String::utf8(" 点潜能领悟「") + sname + String::utf8("」，境界晋升至 ") +
               String::num_int64(st.level) + String::utf8(" 级（") + String::utf8(skill_rank_title(st.level)) + String::utf8("）！");
    }
    return String::utf8("你向") + String::utf8(npc->name) + String::utf8("请教「") + sname +
           String::utf8("」，耗潜能 ") + String::num_int64(pot_cost) + String::utf8(" 点，熟练度进展至 ") +
           String::num_int64(st.exp) + String("/") + String::num_int64(need) + String::utf8("。");
}

Dictionary CanglingWorld::workstation_at(Vector2i p) const {
    if (active_pack != CorePackId::Cangming || floor != 0) return Dictionary();
    const WorkstationDef *ws = workstation_at_tile(p);
    if (ws == nullptr) return Dictionary();
    return workstation_to_dict(*ws, skill_set);
}

Array CanglingWorld::list_workstations() const {
    Array out;
    if (active_pack != CorePackId::Cangming) return out;
    for (const auto &ws : workstation_catalog()) {
        out.append(workstation_to_dict(ws, skill_set));
    }
    return out;
}

Array CanglingWorld::workstations_in_rect(Rect2i area) const {
    Array out;
    if (active_pack != CorePackId::Cangming || floor != 0) return out;
    for (const auto &ws : workstation_catalog()) {
        if (area.has_point(ws.pos)) {
            out.append(workstation_to_dict(ws, skill_set));
        }
    }
    return out;
}

Dictionary CanglingWorld::can_work_at_station(Vector2i p) const {
    Dictionary res;
    res["ok"] = false;
    res["reason"] = String();
    if (floor != 0) {
        res["reason"] = String::utf8("该处没有可用的工作设施。");
        return res;
    }
    const WorkstationDef *ws = workstation_at_tile(p);
    if (ws == nullptr) {
        res["reason"] = String::utf8("该处并非工作区设施。");
        return res;
    }
    res["station"] = workstation_to_dict(*ws, skill_set);
    if (!near(p)) {
        res["reason"] = String::utf8("请走近「") + String::utf8(ws->name) + String::utf8("」后再开始劳作。");
        return res;
    }
    if (!skill_meets_station_req(skill_set, *ws)) {
        const String req_txt = Dictionary(res["station"]).get("req_label", String());
        res["reason"] = String::utf8("你尚未习得此工位所需前置技能（") + req_txt +
                        String::utf8("）！请先向") + String::utf8(ws->mentor_hint) + String::utf8("请教入门。");
        return res;
    }
    if (char_state.is_starving_for_training()) {
        res["reason"] = String::utf8("你又饿又渴、手脚发软（饱食或水分不足），先吃点干粮喝口水再来上工吧！");
        return res;
    }
    if (char_state.is_severely_injured()) {
        res["reason"] = String::utf8("你伤势未愈，先包扎歇息再做工吧。");
        return res;
    }
    if (char_state.stamina < ws->stamina_cost || char_state.fatigue > 90.0) {
        res["reason"] = String::utf8("你此刻气喘疲惫、耐力不足，先歇息片刻再继续劳作。");
        return res;
    }
    res["ok"] = true;
    return res;
}

String CanglingWorld::complete_workstation(Vector2i p) {
    const Dictionary chk = can_work_at_station(p);
    if (!static_cast<bool>(chk.get("ok", false))) {
        return chk.get("reason", String::utf8("无法在此工位劳作。"));
    }
    const WorkstationDef *ws = workstation_at_tile(p);
    if (ws == nullptr) return String();

    char_state.spend_stamina(ws->stamina_cost);
    char_state.kcal = std::max(0.0, char_state.kcal - ws->kcal_cost);
    char_state.hydration = std::max(0.0, char_state.hydration - ws->hydration_cost);
    char_state.fatigue = std::min(100.0, char_state.fatigue + 1.4);
    char_state.morale = std::min(50, char_state.morale + 2);

    const double fed_mult = char_state.is_well_fed() ? 1.25 : 1.0;
    const int pot_earned = skill_set.add_potential(static_cast<int>(std::round(ws->pot_gain * fed_mult)));
    skill_set.add_combat_exp(ws->combat_exp_gain);
    coins += ws->coin_pay;
    ++jobs_done;

    // Pick which learned skill gains practical proficiency from this workstation
    int reward_idx = -1;
    if (std::string_view(ws->reward_skill) == "best_martial") {
        int best_lv = 0;
        for (int i = 0; i < 16; ++i) {
            if (skill_set.base[static_cast<std::size_t>(i)].level > best_lv) {
                best_lv = skill_set.base[static_cast<std::size_t>(i)].level;
                reward_idx = i;
            }
        }
    } else {
        reward_idx = find_base_skill_index(ws->reward_skill);
        if (reward_idx >= 0 && skill_set.base[static_cast<std::size_t>(reward_idx)].level <= 0 &&
            ws->alt_skill && ws->alt_skill[0] != '\0') {
            reward_idx = find_base_skill_index(ws->alt_skill);
        }
    }

    String skill_note;
    if (reward_idx >= 0 && skill_set.base[static_cast<std::size_t>(reward_idx)].level > 0) {
        bool leveled = false;
        const int sk_gain = static_cast<int>(std::round(ws->skill_exp_gain * fed_mult));
        skill_set.add_exp(reward_idx, sk_gain, leveled);
        char_state.sync_with_skills(skill_set);
        const char *sname = base_skill_catalog()[static_cast<std::size_t>(reward_idx)].name;
        const int nlv = skill_set.base[static_cast<std::size_t>(reward_idx)].level;
        skill_note = leveled
            ? (String::utf8("，「") + String::utf8(sname) + String::utf8("」精进至 ") + String::num_int64(nlv) + String::utf8(" 级"))
            : (String::utf8("，「") + String::utf8(sname) + String::utf8("」熟练度 +") + String::num_int64(sk_gain));
    }

    return String::utf8("你在「") + String::utf8(ws->name) + String::utf8("」完成了") +
           String::utf8(ws->action_verb) + String::utf8("，领到 ") + String::num_int64(ws->coin_pay) +
           String::utf8(" 文铜钱、潜能 +") + String::num_int64(pot_earned) + skill_note + String::utf8("！");
}

String CanglingWorld::set_skill_jifa(const String &skill_id, const String &special_art_id) {
    const std::string sid = skill_id.utf8().get_data();
    const int idx = find_base_skill_index(sid);
    if (idx < 0) return String::utf8("未找到该项基础武学。");
    const auto &def = base_skill_catalog()[static_cast<std::size_t>(idx)];
    if (!def.supports_jifa) {
        return String::utf8("「") + String::utf8(def.name) + String::utf8("」属杂学根基，无需激发特殊武功。");
    }
    const std::string art = special_art_id.utf8().get_data();
    if (!skill_set.set_jifa(idx, art)) {
        return String::utf8("无法激发该特殊武功（尚未习得或与「") + String::utf8(def.name) + String::utf8("」槽位不匹配）。");
    }
    char_state.sync_with_skills(skill_set);
    if (art.empty()) {
        return String::utf8("已取消「") + String::utf8(def.name) + String::utf8("」的激发武功。");
    }
    const int sp_idx = find_special_art_index(art);
    const String art_name = sp_idx >= 0 ? String::utf8(special_art_catalog()[static_cast<std::size_t>(sp_idx)].name) : special_art_id;
    return String::utf8("已将「") + art_name + String::utf8("」激发至「") + String::utf8(def.name) +
           String::utf8("」（当前有效等级 ") + String::num_int64(skill_set.effective_level_of(sid)) + String::utf8(" 级）！");
}

Array CanglingWorld::special_art_list() const {
    return skill_set.special_arts_to_array();
}

Array CanglingWorld::npc_special_teach_list(Vector2i npc_pos) const {
    Array out;
    const NpcDef *npc = npc_at_tile(npc_pos);
    if (!npc) return out;
    const std::string nid = npc->id;
    const auto &sp_cat = special_art_catalog();
    const auto &b_cat = base_skill_catalog();
    for (std::size_t i = 0; i < kSpecialArtCount; ++i) {
        const auto &def = sp_cat[i];
        if (nid != def.mentor_npc_id) continue;
        const int bidx = find_base_skill_index(def.base_skill_id);
        const int base_lv = bidx >= 0 ? skill_set.base[static_cast<std::size_t>(bidx)].level : 0;
        const auto &st = skill_set.special[i];
        const int pot_cost = skill_set.special_learn_pot_cost(static_cast<int>(i));
        const int coin_cost = skill_set.special_learn_coin_cost(static_cast<int>(i));
        bool can = true;
        String reason;
        if (base_lv < def.req_base_level) {
            can = false;
            reason = String::utf8("需「") + String::utf8(bidx >= 0 ? b_cat[static_cast<std::size_t>(bidx)].name : def.base_skill_id) +
                     String::utf8("」≥ ") + String::num_int64(def.req_base_level) + String::utf8("级");
        } else if (st.level >= def.max_teach_level) {
            can = false;
            reason = String::utf8("已达此师所授上限");
        } else if (st.level >= base_lv) {
            can = false;
            reason = String::utf8("特殊武功不可超过基础等级");
        } else if (skill_set.potential < pot_cost) {
            can = false;
            reason = String::utf8("潜能不足");
        } else if (coins < coin_cost) {
            can = false;
            reason = String::utf8("铜钱不足");
        } else if (char_state.is_starving_for_training()) {
            can = false;
            reason = String::utf8("腹饥口渴，先吃喝");
        }
        Dictionary row;
        row["id"] = String::utf8(def.id);
        row["name"] = String::utf8(def.name);
        row["base_skill_id"] = String::utf8(def.base_skill_id);
        row["base_skill_name"] = bidx >= 0 ? String::utf8(b_cat[static_cast<std::size_t>(bidx)].name) : String();
        row["req_base_level"] = def.req_base_level;
        row["current_level"] = st.level;
        row["max_teach_level"] = def.max_teach_level;
        row["pot_cost"] = pot_cost;
        row["coin_cost"] = coin_cost;
        row["desc"] = String::utf8(def.desc);
        row["can_learn"] = can;
        row["reason"] = reason;
        out.append(row);
    }
    return out;
}

String CanglingWorld::learn_special_from_npc(Vector2i npc_pos, const String &art_id) {
    if (!near(npc_pos)) return String::utf8("请走近师傅身旁再行请教。");
    const NpcDef *npc = npc_at_tile(npc_pos);
    if (!npc) return String::utf8("那里没有可请教的师傅。");
    const std::string aid = art_id.utf8().get_data();
    const int idx = find_special_art_index(aid);
    if (idx < 0) return String::utf8("未知的特殊武功代号。");
    const auto &def = special_art_catalog()[static_cast<std::size_t>(idx)];
    if (std::string_view(npc->id) != def.mentor_npc_id) {
        return String::utf8(npc->name) + String::utf8("并不传授「") + String::utf8(def.name) + String::utf8("」。");
    }
    const int bidx = find_base_skill_index(def.base_skill_id);
    const int base_lv = bidx >= 0 ? skill_set.base[static_cast<std::size_t>(bidx)].level : 0;
    auto &st = skill_set.special[static_cast<std::size_t>(idx)];
    if (base_lv < def.req_base_level) {
        return String::utf8("根基尚浅！请先将对应基础武学练至 ") + String::num_int64(def.req_base_level) + String::utf8(" 级再来请教「") + String::utf8(def.name) + String::utf8("」。");
    }
    if (st.level >= def.max_teach_level) {
        return String::utf8("你在「") + String::utf8(def.name) + String::utf8("」上已达此师所授上限。");
    }
    if (st.level >= base_lv) {
        return String::utf8("你的基础武学等级不足以支撑更高一层的「") + String::utf8(def.name) + String::utf8("」，请先提升基础武学！");
    }
    const int pot_cost = skill_set.special_learn_pot_cost(idx);
    const int coin_cost = skill_set.special_learn_coin_cost(idx);
    if (skill_set.potential < pot_cost) return String::utf8("潜能不足（需 ") + String::num_int64(pot_cost) + String::utf8(" 点）。");
    if (coins < coin_cost) return String::utf8("铜钱不足（需 ") + String::num_int64(coin_cost) + String::utf8(" 文）。");
    if (char_state.is_starving_for_training()) return String::utf8("你此刻饥肠辘辘，先吃饱喝足再来请教吧。");

    const bool was_unlearned = (st.level == 0);
    skill_set.spend_potential(pot_cost);
    coins -= coin_cost;
    char_state.spend_stamina(320);
    char_state.kcal = std::max(0.0, char_state.kcal - 20.0);
    bool leveled = false;
    if (was_unlearned) {
        st.level = 1;
        st.exp = 0;
        leveled = true;
        // Auto-jifa on first unlock if slot is empty!
        if (bidx >= 0 && skill_set.base[static_cast<std::size_t>(bidx)].enabled_art.empty()) {
            skill_set.set_jifa(bidx, aid);
        }
    } else {
        const int gain = skill_set.learn_exp_gain(char_state.stat_int);
        skill_set.add_special_exp(idx, gain, leveled);
    }
    skill_set.add_combat_exp(6);
    char_state.sync_with_skills(skill_set);

    if (was_unlearned) {
        return String::utf8(npc->name) + String::utf8("倾心传授，你正式领悟入门绝学「") + String::utf8(def.name) +
               String::utf8("」（1级），并已自动激发至基础槽位！可在 [J] 技能面板随时调整激发。");
    }
    if (leveled) {
        return String::utf8("你向") + String::utf8(npc->name) + String::utf8("请教「") + String::utf8(def.name) +
               String::utf8("」，精进至 ") + String::num_int64(st.level) + String::utf8(" 级！");
    }
    return String::utf8("你请教「") + String::utf8(def.name) + String::utf8("」，熟练度进展至 ") +
           String::num_int64(st.exp) + String("/") + String::num_int64(skill_exp_to_next(st.level)) + String::utf8("。");
}

// ---------------------------------------------------------------------------
// Phase 1: Shops, Bank, Pawn, Inn, Dazuo, Exert, Specialized Study
// ---------------------------------------------------------------------------
Dictionary CanglingWorld::shop_info_at(Vector2i npc_pos) const {
    Dictionary d;
    const NpcDef *npc = npc_at_tile(npc_pos);
    if (!npc) return d;
    const ShopService svc = shop_service_for_npc(npc->id);
    d["service"] = static_cast<int>(svc);
    d["npc_id"] = String::utf8(npc->id);
    d["npc_name"] = String::utf8(npc->name);
    d["title"] = String::utf8(npc->title);
    d["items"] = shop_catalog_for_npc(npc->id, skill_set);
    d["coins"] = coins;
    d["bank_coins"] = char_state.bank_coins;
    d["inn_active"] = (char_state.inn_room_until_min > minutes);
    return d;
}

String CanglingWorld::buy_item_from(Vector2i npc_pos, int item_id) {
    if (!near(npc_pos)) return String::utf8("请走近掌柜身旁再行交易。");
    const NpcDef *npc = npc_at_tile(npc_pos);
    if (!npc) return String::utf8("那里没有掌柜。");
    return buy_from_npc(npc->id, item_id, coins, carried, char_state);
}

String CanglingWorld::sell_item_to(Vector2i npc_pos, int item_id) {
    if (!near(npc_pos)) return String::utf8("请走近掌柜身旁再行典当。");
    const NpcDef *npc = npc_at_tile(npc_pos);
    if (!npc) return String::utf8("那里没有掌柜。");
    return sell_to_npc(npc->id, item_id, coins, carried, skill_set);
}

String CanglingWorld::bank_deposit(Vector2i npc_pos, int amount) {
    if (!near(npc_pos)) return String::utf8("请走近通济钱庄掌柜身旁办理存银。");
    const NpcDef *npc = npc_at_tile(npc_pos);
    if (!npc || shop_service_for_npc(npc->id) != ShopService::Bank) return String::utf8("此处并非钱庄。");
    return bank_transfer(amount, true, coins, char_state);
}

String CanglingWorld::bank_withdraw(Vector2i npc_pos, int amount) {
    if (!near(npc_pos)) return String::utf8("请走近通济钱庄掌柜身旁办理取银。");
    const NpcDef *npc = npc_at_tile(npc_pos);
    if (!npc || shop_service_for_npc(npc->id) != ShopService::Bank) return String::utf8("此处并非钱庄。");
    return bank_transfer(amount, false, coins, char_state);
}

String CanglingWorld::rent_inn_room_at(Vector2i npc_pos) {
    if (!near(npc_pos)) return String::utf8("请走近客栈店小二身旁开房。");
    const NpcDef *npc = npc_at_tile(npc_pos);
    if (!npc || shop_service_for_npc(npc->id) != ShopService::Inn) return String::utf8("此处并非客栈。");
    return rent_inn_room(coins, minutes, char_state);
}

Dictionary CanglingWorld::dazuo_cycle() {
    const bool quiet = is_pos_indoors(pos, floor) || near_martial_training_station(pos);
    return char_state.dazuo_cycle(skill_set, quiet);
}

String CanglingWorld::exert_action(const String &kind) {
    return char_state.exert_action(kind.utf8().get_data());
}

String CanglingWorld::study_book_cycle(int item_id) {
    const bool academy = (pos.x >= 126 && pos.x <= 135 && pos.y >= 84 && pos.y <= 94) || is_pos_indoors(pos, floor);
    return char_state.study_book_cycle(item_id, carried, skill_set, academy);
}

// ---------------------------------------------------------------------------
// Phase 2: CCB Crafting (&), Dismantle (B), Ambient Temp/Wetness & Sparring
// ---------------------------------------------------------------------------
bool CanglingWorld::is_pos_indoors(Vector2i p, int z) {
    if (active_pack == CorePackId::Cataclysm) return z == 0 && ccb_overmap.enclosed_at(p);
    if (!in_city(p)) return false;
    return city.lighting_column(p, z, 1) > 0 || (effective_tile(p, z) == 'i');
}

bool CanglingWorld::is_pos_near_hearth(Vector2i p, int z) {
    for (int dy = -2; dy <= 2; ++dy) {
        for (int dx = -2; dx <= 2; ++dx) {
            const Vector2i q = p + Vector2i(dx, dy);
            if (in_bounds(q) && effective_tile(q, z) == 'h') return true;
        }
    }
    return false;
}

CraftEnv CanglingWorld::current_craft_env() const {
    CraftEnv env;
    auto *self = const_cast<CanglingWorld *>(this);
    for (int dy = -2; dy <= 2; ++dy) {
        for (int dx = -2; dx <= 2; ++dx) {
            const Vector2i q = pos + Vector2i(dx, dy);
            if (!in_city(q)) continue;
            const char t = self->effective_tile(q, floor);
            if (t == 'h') env.near_hearth = true;
            if (t == 'u' || t == 'a' || t == '~' || t == 'W') env.near_water = true;
            if (floor == 0 && workstation_at_tile(q) != nullptr) env.near_workshop = true;
        }
    }
    // 王记铁匠铺锻造区 (108..117, 152..161)
    if (floor == 0 && pos.x >= 108 && pos.x <= 118 && pos.y >= 151 && pos.y <= 162) {
        env.near_anvil = true;
        env.near_hearth = true;
        env.near_workshop = true;
    }
    return env;
}

Dictionary CanglingWorld::craft_env_dict() {
    const CraftEnv env = current_craft_env();
    Dictionary d;
    d["near_hearth"] = env.near_hearth;
    d["near_anvil"] = env.near_anvil;
    d["near_water"] = env.near_water;
    d["near_workshop"] = env.near_workshop;
    return d;
}

Array CanglingWorld::craft_recipe_list(const String &category_filter) {
    if (active_pack == CorePackId::Cataclysm) {
        return ccb_recipe_list(category_filter, String(), 80);
    }
    return list_recipes_for_player(carried, carried_water, char_state.wielded, skill_set, current_craft_env(), category_filter);
}

Dictionary CanglingWorld::can_craft_recipe(const String &recipe_id) {
    if (active_pack == CorePackId::Cataclysm) {
        Dictionary d;
        d["ok"] = true;
        d["reason"] = String();
        return d;
    }
    const int idx = find_recipe_index(recipe_id.utf8().get_data());
    if (idx < 0) {
        Dictionary d;
        d["ok"] = false;
        d["reason"] = String::utf8("未找到该制作配方。");
        return d;
    }
    return check_can_craft(recipe_catalog()[static_cast<std::size_t>(idx)], carried, carried_water,
                           char_state.wielded, skill_set, current_craft_env());
}

String CanglingWorld::complete_craft_recipe(const String &recipe_id) {
    if (active_pack == CorePackId::Cataclysm) {
        return ccb_craft_recipe(recipe_id);
    }
    const int idx = find_recipe_index(recipe_id.utf8().get_data());
    if (idx < 0) return String::utf8("未找到该制作配方。");
    return execute_craft(recipe_catalog()[static_cast<std::size_t>(idx)], carried, carried_water,
                         char_state.wielded, char_state, skill_set, current_craft_env());
}

String CanglingWorld::dismantle_item(int item_id) {
    return dismantle_item_to_rags(item_id, carried, char_state);
}

void CanglingWorld::sync_environment(double ambient_c, double rain_intensity) {
    char_state.update_environment(ambient_c, rain_intensity, is_pos_indoors(pos, floor), is_pos_near_hearth(pos, floor));
}

Dictionary CanglingWorld::start_spar(Vector2i npc_pos) {
    if (!near(npc_pos)) {
        Dictionary d;
        d["ok"] = false;
        d["message"] = String::utf8("请走近演武对手身旁再抱拳切磋。");
        return d;
    }
    const NpcDef *npc = npc_at_tile(npc_pos);
    if (!npc) {
        Dictionary d;
        d["ok"] = false;
        d["message"] = String::utf8("那里没有可切磋的对手。");
        return d;
    }
    return begin_spar_session(spar_session, npc->id, npc_pos, char_state, skill_set);
}

Dictionary CanglingWorld::step_spar_round() {
    Dictionary res = advance_spar_round(spar_session, char_state, skill_set);
    bounty_tracker.update_proximity(pos, char_state.spar_total);
    return res;
}

String CanglingWorld::stop_spar() {
    return finish_spar_early(spar_session);
}

Dictionary CanglingWorld::spar_status() const {
    return spar_session.to_dict();
}

// ---------------------------------------------------------------------------
// Phase 3: Central Square Bounties & Jianghu Score
// ---------------------------------------------------------------------------
Array CanglingWorld::bounty_list() const {
    return bounty_tracker.list_to_array(carried, char_state.spar_total);
}

Dictionary CanglingWorld::active_bounty() const {
    return bounty_tracker.active_dict(carried, char_state.spar_total);
}

String CanglingWorld::accept_bounty(int index) {
    return bounty_tracker.accept(index, char_state.spar_total);
}

String CanglingWorld::abandon_bounty() {
    return bounty_tracker.abandon();
}

String CanglingWorld::turn_in_bounty(Vector2i npc_pos) {
    if (!near(npc_pos)) return String::utf8("请走近目标人物身旁再交付委托。");
    const NpcDef *npc = npc_at_tile(npc_pos);
    if (!npc) return String::utf8("那里没有可交付委托的人物。");
    const String msg = bounty_tracker.try_turn_in(npc->id, carried, coins, char_state, skill_set);
    return msg.is_empty() ? String::utf8("当前没有需向此人交付的江湖委托。") : msg;
}

Dictionary CanglingWorld::player_score_dict() const {
    Dictionary d;
    const int total_lv = skill_set.total_levels();
    d["name"] = player_name;
    d["title"] = String::utf8(jianghu_title(total_lv, skill_set.combat_exp, char_state.reputation));
    d["reputation"] = char_state.reputation;
    d["coins"] = coins;
    d["bank_coins"] = char_state.bank_coins;
    d["spar_wins"] = char_state.spar_wins;
    d["spar_total"] = char_state.spar_total;
    d["completed_bounties"] = bounty_tracker.completed_count;
    d["jobs_done"] = jobs_done;
    d["total_levels"] = total_lv;
    d["learned_count"] = skill_set.learned_count();
    d["learned_special_count"] = skill_set.learned_special_count();
    d["combat_exp"] = skill_set.combat_exp;
    d["potential"] = skill_set.potential;
    d["potential_cap"] = skill_set.potential_cap();
    d["inn_active"] = (char_state.inn_room_until_min > minutes);
    return d;
}

// ---------------------------------------------------------------------------
// Multiplayer-Ready Sync, Remote Peer & Deterministic Action Hooks
// ---------------------------------------------------------------------------
void CanglingWorld::set_player_name(const String &name) {
    const String trimmed = name.strip_edges();
    player_name = trimmed.is_empty() ? String::utf8("江湖少侠") : trimmed.substr(0, 16);
}

Dictionary CanglingWorld::export_player_snapshot() const {
    Dictionary snap;
    snap["peer_id"] = local_peer_id;
    snap["name"] = player_name;
    snap["pos"] = pos;
    snap["floor"] = floor;
    snap["facing_x"] = 1;
    snap["move_mode"] = char_state.move_mode;
    snap["posture"] = String();
    snap["wielded"] = char_state.wielded;
    snap["worn_overlays"] = char_state.worn_overlays();
    snap["coins"] = coins;
    snap["minutes"] = minutes;
    snap["seed"] = static_cast<int64_t>(seed);
    const Dictionary sk = skill_set.summary_dict();
    snap["rank_label"] = sk.get("overall_rank", String::utf8("初学乍练"));
    snap["skills_summary"] = sk;
    return snap;
}

bool CanglingWorld::apply_remote_snapshot(int64_t peer_id, const Dictionary &snapshot) {
    if (peer_id <= 0 || peer_id == local_peer_id) return false;
    RemotePlayerState &rp = remote_players[peer_id];
    rp.peer_id = peer_id;
    const String rname = snapshot.get("name", String::utf8("江湖同道"));
    rp.name = rname.is_empty() ? String::utf8("江湖同道") : rname;
    const Variant pv = snapshot.get("pos", pos);
    if (pv.get_type() == Variant::VECTOR2I) {
        rp.pos = pv;
    } else if (pv.get_type() == Variant::ARRAY) {
        const Array arr = pv;
        if (arr.size() == 2) rp.pos = Vector2i(arr[0], arr[1]);
    }
    rp.pos.x = std::clamp(rp.pos.x, 0, city_size - 1);
    rp.pos.y = std::clamp(rp.pos.y, 0, city_size - 1);
    rp.floor = static_cast<int>(snapshot.get("floor", 0));
    rp.facing_x = static_cast<int>(snapshot.get("facing_x", 1)) >= 0 ? 1 : -1;
    rp.move_mode = std::clamp(static_cast<int>(snapshot.get("move_mode", 0)), 0, 3);
    rp.posture = snapshot.get("posture", String());
    rp.wielded = static_cast<int>(snapshot.get("wielded", -1));
    const Variant ov = snapshot.get("worn_overlays", Variant());
    if (ov.get_type() == Variant::PACKED_STRING_ARRAY) {
        rp.worn_overlays = ov;
    }
    rp.rank_label = snapshot.get("rank_label", String::utf8("初学乍练"));
    rp.last_sync_ms = static_cast<int64_t>(snapshot.get("sync_ms", 0));
    return true;
}

void CanglingWorld::remove_remote_player(int64_t peer_id) {
    remote_players.erase(peer_id);
}

void CanglingWorld::clear_remote_players() {
    remote_players.clear();
}

Array CanglingWorld::list_remote_players() const {
    Array out;
    for (const auto &[pid, rp] : remote_players) {
        out.append(rp.to_dict());
    }
    return out;
}

Array CanglingWorld::remote_players_in_rect(Rect2i area) const {
    Array out;
    for (const auto &[pid, rp] : remote_players) {
        if (rp.floor == floor && area.has_point(rp.pos)) {
            out.append(rp.to_dict());
        }
    }
    return out;
}

Dictionary CanglingWorld::submit_player_action(const Dictionary &action) {
    // Deterministic command entry point ready for future server-authoritative RPC dispatch.
    Dictionary res;
    res["ok"] = false;
    res["message"] = String();
    const String kind = action.get("type", String());
    if (kind == String("move")) {
        const Variant tv = action.get("target", pos);
        Vector2i next = pos;
        if (tv.get_type() == Variant::VECTOR2I) next = tv;
        const bool moved = move_one(next);
        res["ok"] = moved;
    } else if (kind == String("interact")) {
        const Vector2i target = action.get("target", pos);
        const String verb = action.get("action", String());
        const String msg = interact(target, verb);
        res["ok"] = !msg.is_empty();
        res["message"] = msg;
    } else if (kind == String("practice_skill")) {
        const String sid = action.get("skill_id", String());
        const String msg = practice_skill(sid);
        res["ok"] = !msg.is_empty();
        res["message"] = msg;
    } else if (kind == String("research_skill")) {
        const String sid = action.get("skill_id", String());
        const String msg = research_skill(sid);
        res["ok"] = !msg.is_empty();
        res["message"] = msg;
    } else if (kind == String("learn_from_npc")) {
        const Vector2i target = action.get("target", pos);
        const String sid = action.get("skill_id", String());
        const String msg = learn_from_npc(target, sid);
        res["ok"] = !msg.is_empty();
        res["message"] = msg;
    } else if (kind == String("workstation")) {
        const Vector2i target = action.get("target", pos);
        const String msg = complete_workstation(target);
        res["ok"] = !msg.is_empty();
        res["message"] = msg;
    } else if (kind == String("jifa")) {
        const String sid = action.get("skill_id", String());
        const String art = action.get("special_art_id", String());
        const String msg = set_skill_jifa(sid, art);
        res["ok"] = !msg.is_empty();
        res["message"] = msg;
    } else if (kind == String("learn_special")) {
        const Vector2i target = action.get("target", pos);
        const String aid = action.get("art_id", String());
        const String msg = learn_special_from_npc(target, aid);
        res["ok"] = !msg.is_empty();
        res["message"] = msg;
    } else if (kind == String("craft")) {
        const String rid = action.get("recipe_id", String());
        const String msg = complete_craft_recipe(rid);
        res["ok"] = !msg.is_empty();
        res["message"] = msg;
    } else if (kind == String("study_book")) {
        const int item_id = static_cast<int>(action.get("item_id", -1));
        const String msg = study_book_cycle(item_id);
        res["ok"] = !msg.is_empty();
        res["message"] = msg;
    } else if (kind == String("exert")) {
        const String ek = action.get("kind", String());
        const String msg = exert_action(ek);
        res["ok"] = !msg.is_empty();
        res["message"] = msg;
    }
    res["snapshot"] = export_player_snapshot();
    return res;
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
    out["pack_id"] = get_pack_id();
    out["alive_monsters"] = monsters.alive_count();
    return out;
}

void CanglingWorld::setup_ccb_world(const Dictionary &world_cfg, const Dictionary &char_cfg) {
    world_city_size = std::clamp(static_cast<int>(world_cfg.get("city_size", 8)), 3, 16);
    world_city_spacing = std::clamp(static_cast<int>(world_cfg.get("city_spacing", 4)), 2, 8);
    world_monster_rate = std::clamp(static_cast<float>(static_cast<double>(world_cfg.get("monster_rate", 1.0))), 0.25f, 4.0f);
    const int64_t new_seed = static_cast<int64_t>(world_cfg.get("seed", 20260415));
    const String scen = String(char_cfg.get("scenario_id", String("evacuee")));
    setup_with_pack(String("cataclysm"), new_seed, scen);
    const String cname = String(char_cfg.get("name", String()));
    if (!cname.strip_edges().is_empty()) {
        set_player_name(cname);
    }
    ccb_state.apply_character_config(char_cfg, char_state);
}

Array CanglingWorld::ccb_list_scenarios() const {
    return CcbVanillaDB::instance().list_scenarios_array();
}

Array CanglingWorld::ccb_list_professions(bool hobbies_only) const {
    return CcbVanillaDB::instance().list_professions_array(hobbies_only);
}

Array CanglingWorld::ccb_list_starting_traits() const {
    return CcbVanillaDB::instance().list_starting_traits_array();
}

Array CanglingWorld::ccb_list_skills() const {
    return CcbVanillaDB::instance().list_skills_array();
}

Dictionary CanglingWorld::ccb_overmap_slice(Vector2i center_omt, int radius) {
    Dictionary out = ccb_overmap.overmap_slice(center_omt, radius);
    const int r = std::clamp(radius, 1, 40);
    const int side = r * 2 + 1;
    Array seen_rows;
    Dictionary notes;
    for (int dy = -r; dy <= r; ++dy) {
        Array srow;
        for (int dx = -r; dx <= r; ++dx) {
            const Vector2i omt = center_omt + Vector2i(dx, dy);
            srow.append(ccb_state.is_omt_seen(omt));
            const std::string nt = ccb_state.get_overmap_note(omt);
            if (!nt.empty()) {
                notes[String::num_int64(omt.x) + String(",") + String::num_int64(omt.y)] = String::utf8(nt.c_str());
            }
        }
        seen_rows.append(srow);
    }
    out["seen"] = seen_rows;
    out["notes"] = notes;
    return out;
}

Vector2i CanglingWorld::ccb_world_to_omt(Vector2i wp) const {
    return CcbOvermapManager::world_to_omt(wp);
}

void CanglingWorld::ensure_ccb_omt_populated(Vector2i center_wp) {
    if (active_pack != CorePackId::Cataclysm) return;
    const Vector2i c_omt = CcbOvermapManager::world_to_omt(center_wp);
    const int hour = (minutes / 60) % 24;
    const int sight_r = (hour < 6 || hour >= 20) ? 2 : 5;
    ccb_state.mark_omt_seen(c_omt, sight_r);
    const auto &db = CcbVanillaDB::instance();
    for (int dy = -2; dy <= 2; ++dy) {
        for (int dx = -2; dx <= 2; ++dx) {
            const Vector2i omt = c_omt + Vector2i(dx, dy);
            const int64_t ok = infinite_tile_key(omt, 0);
            if (!ccb_spawned_omts.insert(ok).second) continue;
            const auto ch = ccb_overmap.chunk_at_omt(omt);
            // Stream authentic vanilla OMT monsters lazily!
            monsters.add_spawns(ch->monster_spawns);
            // Materialize authentic vanilla OMT item spawns from mapgen_omt.json!
            const Vector2i base_wp = omt * kOmtSize;
            for (const auto &sp : ch->item_spawns) {
                if (sp.items.empty()) continue;
                const Vector2i wp = base_wp + Vector2i(sp.lx, sp.ly);
                const int64_t tk = key(wp, 0);
                ccb_state.loot_materialized[tk] = true;
                const std::uint32_t h = (static_cast<std::uint32_t>(wp.x) * 374761393u) ^
                                        (static_cast<std::uint32_t>(wp.y) * 668265263u) ^ seed;
                const std::string &pick = sp.items[h % sp.items.size()];
                if (db.find_item(pick)) {
                    ccb_state.world_items[tk].push_back({pick, 1, 0});
                }
            }
        }
    }
}

Dictionary CanglingWorld::ccb_render_rect(Rect2i area, int z) {
    Dictionary out;
    if (active_pack != CorePackId::Cataclysm || area.size.x <= 0 || area.size.y <= 0) return out;
    const int x0 = area.position.x;
    const int y0 = area.position.y;
    const int w = area.size.x;
    const int h = area.size.y;

    // Pre-fetch OMT chunks covering area
    const Vector2i omt0 = CcbOvermapManager::world_to_omt({x0, y0});
    const Vector2i omt1 = CcbOvermapManager::world_to_omt({x0 + w - 1, y0 + h - 1});
    const int ox_span = std::max(1, omt1.x - omt0.x + 1);
    const int oy_span = std::max(1, omt1.y - omt0.y + 1);
    std::vector<std::shared_ptr<const OmtChunk>> grid(static_cast<std::size_t>(ox_span * oy_span));
    for (int oy = omt0.y; oy <= omt1.y; ++oy) {
        for (int ox = omt0.x; ox <= omt1.x; ++ox) {
            grid[static_cast<std::size_t>((oy - omt0.y) * ox_span + (ox - omt0.x))] = ccb_overmap.chunk_at_omt({ox, oy});
        }
    }

    std::unordered_map<std::string, int> tmap;
    std::unordered_map<std::string, int> fmap;
    PackedStringArray tpal;
    PackedStringArray fpal;
    fmap[""] = 0;
    fpal.append(String());

    PackedInt32Array tidx;
    PackedInt32Array fidx;
    tidx.resize(w * h);
    fidx.resize(w * h);
    int32_t *tp = tidx.ptrw();
    int32_t *fp = fidx.ptrw();

    auto get_ti = [&](const std::string &s) -> int {
        const auto it = tmap.find(s);
        if (it != tmap.end()) return it->second;
        const int id = tpal.size();
        tmap[s] = id;
        tpal.append(String::utf8(s.c_str()));
        return id;
    };
    auto get_fi = [&](const std::string &s) -> int {
        const auto it = fmap.find(s);
        if (it != fmap.end()) return it->second;
        const int id = fpal.size();
        fmap[s] = id;
        fpal.append(String::utf8(s.c_str()));
        return id;
    };

    const auto &db = CcbVanillaDB::instance();
    Array ground_items;
    Array blood_arr;

    for (int ly = 0; ly < h; ++ly) {
        const int wy = y0 + ly;
        const int oy = CcbOvermapManager::world_to_omt({0, wy}).y;
        const int cy = wy - oy * kOmtSize;
        for (int lx = 0; lx < w; ++lx) {
            const int wx = x0 + lx;
            const int ox = CcbOvermapManager::world_to_omt({wx, 0}).x;
            const int cx = wx - ox * kOmtSize;
            const auto &ch = grid[static_cast<std::size_t>((oy - omt0.y) * ox_span + (ox - omt0.x))];
            const std::size_t cidx = static_cast<std::size_t>(cy * kOmtSize + cx);
            std::string ter = ch->terrain[cidx];
            std::string furn = ch->furniture[cidx];

            const int64_t dk = key({wx, wy}, z);
            if (!tile_overrides.empty()) {
                if (const auto oit = tile_overrides.find(dk); oit != tile_overrides.end()) {
                    const char ov = oit->second;
                    if (ov == '%') { ter = "t_window_frame"; furn.clear(); }
                    else if (ov == 'i') { ter = "t_floor"; furn.clear(); }
                    else if (ov == '.') { ter = "t_grass"; furn.clear(); }
                }
            }
            if (!doors.empty() && doors.count(dk)) {
                if (ter.find("t_door") != std::string::npos) ter = "t_door_o";
                else if (ter.find("t_window") != std::string::npos) ter = "t_window_open";
            }

            tp[ly * w + lx] = get_ti(ter);
            fp[ly * w + lx] = get_fi(furn);

            if (const auto bit = ccb_state.blood_tiles.find(dk); bit != ccb_state.blood_tiles.end() && bit->second > 0) {
                Dictionary bd;
                bd["pos"] = Vector2i(wx, wy);
                bd["intensity"] = bit->second;
                blood_arr.append(bd);
            }
            if (const auto wit = ccb_state.world_items.find(dk); wit != ccb_state.world_items.end() && !wit->second.empty()) {
                const auto &top = wit->second.front();
                const auto *idef = db.find_item(top.id);
                Dictionary idict;
                idict["pos"] = Vector2i(wx, wy);
                idict["id"] = String::utf8(top.id.c_str());
                idict["tile"] = String::utf8((idef && !idef->tile.empty()) ? idef->tile.c_str() : top.id.c_str());
                idict["count"] = static_cast<int>(wit->second.size());
                ground_items.append(idict);
            }
        }
    }

    Array corpse_arr;
    for (const auto &c : ccb_state.corpses) {
        if (c.butchered || c.floor != z || !area.has_point(c.pos)) continue;
        const auto *mdef = db.find_monster(c.mtype_id);
        Dictionary cd;
        cd["pos"] = c.pos;
        cd["mtype_id"] = String::utf8(c.mtype_id.c_str());
        cd["name"] = String::utf8(mdef ? mdef->name.c_str() : c.mtype_id.c_str());
        cd["pulped"] = c.pulped;
        cd["tile"] = String("corpse_") + String::utf8(c.mtype_id.c_str());
        corpse_arr.append(cd);
    }

    out["origin"] = Vector2i(x0, y0);
    out["size"] = Vector2i(w, h);
    out["ter_palette"] = tpal;
    out["furn_palette"] = fpal;
    out["ter_idx"] = tidx;
    out["furn_idx"] = fidx;
    out["corpses"] = corpse_arr;
    out["blood"] = blood_arr;
    out["items"] = ground_items;
    return out;
}

Dictionary CanglingWorld::ccb_advance_moves(int moves) {
    Dictionary out;
    out["messages"] = Array();
    out["safe_mode_alert"] = false;
    out["player_damaged"] = false;
    if (active_pack != CorePackId::Cataclysm || moves <= 0) return out;

    // 1. Scale moves by player speed (vanilla: speed 100 = 100 moves/sec)
    const auto mods = ccb_state.compute_mods();
    const int eff_speed = std::clamp(100 + mods.speed_mod - char_state.pain / 2, 35, 160);
    const int world_moves = std::max(10, (moves * 100) / eff_speed);

    ccb_turn_moves += world_moves;
    const int delta_sec = ccb_turn_moves / 100;
    ccb_turn_moves %= 100;
    ccb_turn_seconds += delta_sec;
    const int delta_min = ccb_turn_seconds / 60;
    ccb_turn_seconds %= 60;

    // 2. Tick monsters strictly proportional to exact world_moves!
    const int hour = (minutes / 60) % 24;
    const bool is_night = (hour < 6 || hour >= 20);
    const auto mres = monsters.tick_moves(
        world_moves, pos, floor, is_night, char_state, ccb_state,
        [this](Vector2i p, int z) {
            const char t = effective_tile(p, z);
            return passable_tile(t) && t != 'D';
        },
        [this](Vector2i p, int z) {
            const char t = effective_tile(p, z);
            return t == '#' || t == 'D';
        });
    for (int i = 0; i < mres.messages.size(); ++i) pending_ccb_messages.append(mres.messages[i]);

    // 3. Advance minute-based vanilla systems (hunger/thirst/radiation/bleed/bite/infection/mutagen/revival)
    if (delta_min > 0) {
        advance_time(delta_min);
    }

    out["messages"] = mres.messages;
    out["player_damaged"] = mres.player_damaged;
    out["safe_mode_alert"] = mres.safe_mode_alert;
    out["delta_min"] = delta_min;
    out["world_moves"] = world_moves;
    return out;
}

Dictionary CanglingWorld::ccb_wait_turn() {
    if (active_pack != CorePackId::Cataclysm) return Dictionary();
    char_state.last_sound = 0;
    char_state.stamina = std::min(10000, char_state.stamina + 90);
    return ccb_advance_moves(100);
}

Dictionary CanglingWorld::ccb_wait_minutes(int mins) {
    Dictionary out;
    out["completed_min"] = 0;
    out["interrupted"] = false;
    if (active_pack != CorePackId::Cataclysm || mins <= 0) return out;
    const int total = std::clamp(mins, 1, 360);
    int done = 0;
    for (int m = 0; m < total; ++m) {
        // Tick monsters & survival effects per minute, stopping immediately on alert or damage!
        const Dictionary step = ccb_advance_moves(6000);
        ++done;
        if (static_cast<bool>(step.get("safe_mode_alert", false)) || static_cast<bool>(step.get("player_damaged", false))) {
            out["interrupted"] = true;
            break;
        }
    }
    out["completed_min"] = done;
    return out;
}

Dictionary CanglingWorld::ccb_sleep_minutes(int mins) {
    Dictionary out;
    out["completed_min"] = 0;
    out["interrupted"] = false;
    if (active_pack != CorePackId::Cataclysm || mins <= 0) return out;
    const int total = std::clamp(mins, 10, 480);
    int done = 0;
    for (int m = 0; m < total; m += 5) {
        const int chunk = std::min(5, total - m);
        minutes += chunk;
        rest_minutes(chunk, true);
        const Dictionary t = tick_monsters(2);
        done += chunk;
        if (static_cast<bool>(t.get("player_damaged", false)) || static_cast<bool>(t.get("safe_mode_alert", false))) {
            out["interrupted"] = true;
            break;
        }
    }
    out["completed_min"] = done;
    return out;
}

Array CanglingWorld::ccb_corpses_at(Vector2i p) const {
    if (active_pack != CorePackId::Cataclysm) return Array();
    return ccb_state.corpses_at(p, floor);
}

String CanglingWorld::ccb_pulp_at(Vector2i p) {
    if (active_pack != CorePackId::Cataclysm || !near(p)) return String();
    const String msg = ccb_state.pulp_corpse_at(p, floor);
    if (!msg.is_empty()) {
        char_state.spend_stamina(180);
        char_state.last_sound = 12;
        ccb_advance_moves(150);
    }
    return msg;
}

String CanglingWorld::ccb_butcher_at(Vector2i p) {
    if (active_pack != CorePackId::Cataclysm || !near(p)) return String();
    const String msg = ccb_state.butcher_corpse_at(p, floor, char_state);
    if (msg.find(String::utf8("解剖了")) >= 0) {
        ccb_advance_moves(6000 * 10); // 10 minutes vanilla quick butcher
    }
    return msg;
}

Array CanglingWorld::ccb_recipe_list(const String &category_filter, const String &query, int limit) const {
    return ccb_state.recipe_list(category_filter, query, limit);
}

String CanglingWorld::ccb_craft_recipe(const String &recipe_id) {
    if (active_pack != CorePackId::Cataclysm) return String();
    int tmin = 0;
    const String msg = ccb_state.craft_recipe(recipe_id.utf8().get_data(), char_state, tmin);
    if (tmin > 0) {
        ccb_advance_moves(tmin * 6000);
    }
    return msg;
}

void CanglingWorld::ccb_teleport_debug(Vector2i target) {
    if (active_pack != CorePackId::Cataclysm) return;
    pos = target;
    ensure_ccb_omt_populated(pos);
}

// ---------------------------------------------------------------------------
// Vanilla CCB Core Pack APIs (10,366 items, 591 mutations, radiation, combat)
// ---------------------------------------------------------------------------
Dictionary CanglingWorld::ccb_db_stats() const {
    return CcbVanillaDB::instance().db_stats_dict();
}

Array CanglingWorld::ccb_search_items(const String &query, const String &subtype_filter, int limit) const {
    return CcbVanillaDB::instance().search_items(query, subtype_filter, limit);
}

Dictionary CanglingWorld::ccb_status() const {
    return ccb_state.status_dict(char_state);
}

Array CanglingWorld::ccb_inventory() const {
    return ccb_state.bag_to_array();
}

Array CanglingWorld::ccb_worn() const {
    return ccb_state.worn_to_array();
}

void CanglingWorld::ensure_ccb_loot_at(Vector2i p) {
    if (active_pack != CorePackId::Cataclysm) return;
    ensure_ccb_omt_populated(p);
    const int64_t k = key(p, floor);
    if (ccb_state.loot_materialized[k]) return;
    ccb_state.loot_materialized[k] = true;

    const char tile = effective_tile(p, floor);
    if (std::string_view("FCrKktb").find(tile) == std::string_view::npos) return;

    const auto &db = CcbVanillaDB::instance();
    const String loc = location(p);
    const std::uint32_t h = (static_cast<std::uint32_t>(p.x) * 374761393u) ^
                            (static_cast<std::uint32_t>(p.y) * 668265263u) ^ seed;
    auto push_if = [&](const char *id, int n) {
        if (db.find_item(id)) ccb_state.world_items[k].push_back({id, n, 0});
    };

    if (loc.find(String::utf8("避难所")) >= 0) {
        static constexpr const char *kEvacPool[] = {"protein_bar_evac", "water_clean", "blanket", "bandages", "flashlight", "matches", "pocketknife", "rag"};
        push_if(kEvacPool[h % 8], 1);
    } else if (loc.find(String::utf8("药房")) >= 0) {
        static constexpr const char *kMedPool[] = {"bandages", "antiseptic", "antibiotics", "aspirin", "firstaid", "iodine", "cotton_ball", "saline", "vitamins"};
        push_if(kMedPool[h % 9], 1);
    } else if (loc.find(String::utf8("超市")) >= 0) {
        static constexpr const char *kFoodPool[] = {"water_clean", "protein_bar_evac", "jerky", "beans_cooked", "apple", "bread", "chocolate", "soda"};
        push_if(kFoodPool[h % 8], 1 + static_cast<int>(h % 2));
    } else if (loc.find(String::utf8("五金")) >= 0) {
        static constexpr const char *kToolPool[] = {"crowbar", "hatchet", "machete", "pipe", "hammer", "flashlight", "screwdriver", "duct_tape"};
        push_if(kToolPool[h % 8], 1);
    } else if (loc.find(String::utf8("警局")) >= 0) {
        static constexpr const char *kCopPool[] = {"kevlar", "helmet_riot", "baton", "flashlight", "bandages", "holster", "backpack"};
        push_if(kCopPool[h % 7], 1);
    } else if (loc.find(String::utf8("核废料")) >= 0 || loc.find(String::utf8("实验室")) >= 0) {
        static constexpr const char *kLabPool[] = {"geiger_off", "hazmat_suit", "prussian_blue", "iodine", "iv_mutagen", "purifier", "rad_badge"};
        push_if(kLabPool[h % 7], 1);
    } else {
        static constexpr const char *kHousePool[] = {"water_clean", "bandages", "rag", "pocketknife", "bread", "flashlight", "jacket_leather", "jeans", "backpack"};
        if ((h % 3) != 0) push_if(kHousePool[h % 9], 1);
    }
}

Array CanglingWorld::ccb_items_at(Vector2i p) {
    Array out;
    if (active_pack != CorePackId::Cataclysm) return out;
    ensure_ccb_loot_at(p);
    const auto it = ccb_state.world_items.find(key(p, floor));
    if (it == ccb_state.world_items.end()) return out;
    const auto &db = CcbVanillaDB::instance();
    for (const auto &st : it->second) {
        out.append(db.stack_to_dict(st));
    }
    return out;
}

String CanglingWorld::ccb_wield(const String &item_id) {
    return ccb_state.wield_item_id(item_id.utf8().get_data());
}

String CanglingWorld::ccb_unwield() {
    return ccb_state.unwield_item();
}

String CanglingWorld::ccb_wear(const String &item_id) {
    return ccb_state.wear_item_id(item_id.utf8().get_data());
}

String CanglingWorld::ccb_takeoff(const String &item_id) {
    return ccb_state.takeoff_item_id(item_id.utf8().get_data());
}

String CanglingWorld::ccb_use_item(const String &item_id) {
    std::vector<String> extra;
    const String msg = ccb_state.use_or_consume_item(item_id.utf8().get_data(), char_state, extra);
    for (const auto &e : extra) pending_ccb_messages.append(e);
    return msg;
}

String CanglingWorld::ccb_take_item(Vector2i p, const String &item_id) {
    if (active_pack != CorePackId::Cataclysm || !near(p)) return String();
    ensure_ccb_loot_at(p);
    const int64_t k = key(p, floor);
    auto it = ccb_state.world_items.find(k);
    if (it == ccb_state.world_items.end()) return String();
    const std::string sid = item_id.utf8().get_data();
    for (auto vit = it->second.begin(); vit != it->second.end(); ++vit) {
        if (vit->id == sid) {
            ccb_state.add_bag_item(vit->id, vit->count, vit->filthy, vit->damage);
            const auto *def = CcbVanillaDB::instance().find_item(vit->id);
            const String nm = def ? String::utf8(def->name_zh.c_str()) : item_id;
            const String fl = vit->filthy ? String::utf8(" (脏污)") : String();
            const int cnt = vit->count;
            it->second.erase(vit);
            ccb_advance_moves(50);
            return String::utf8("你拾取了「") + nm + fl + String::utf8("」×") + String::num_int64(cnt) + String::utf8("。");
        }
    }
    return String();
}

String CanglingWorld::ccb_take_all_at(Vector2i p) {
    if (active_pack != CorePackId::Cataclysm || !near(p)) return String();
    ensure_ccb_loot_at(p);
    const int64_t k = key(p, floor);
    auto it = ccb_state.world_items.find(k);
    if (it == ccb_state.world_items.end() || it->second.empty()) return String::utf8("该处没有可拾取的物品。");
    int count = 0;
    for (const auto &st : it->second) {
        ccb_state.add_bag_item(st.id, st.count, st.filthy, st.damage);
        count += st.count;
    }
    it->second.clear();
    ccb_advance_moves(std::min(400, 40 * std::max(1, count)));
    return String::utf8("你拾取了该处的全部 ") + String::num_int64(count) + String::utf8(" 件物品。");
}

String CanglingWorld::ccb_drop_item(const String &item_id) {
    const std::string sid = item_id.utf8().get_data();
    bool filthy = false;
    int damage = 0;
    for (auto it = ccb_state.bag.begin(); it != ccb_state.bag.end(); ++it) {
        if (it->id == sid) {
            filthy = it->filthy;
            damage = it->damage;
            it->count -= 1;
            if (it->count <= 0) ccb_state.bag.erase(it);
            ccb_state.world_items[key(pos, floor)].push_back({sid, 1, 0, filthy, damage});
            ccb_advance_moves(40);
            const auto *def = CcbVanillaDB::instance().find_item(sid);
            return String::utf8("你丢下了「") + String::utf8(def ? def->name_zh.c_str() : sid.c_str()) + String::utf8("」。");
        }
    }
    return String::utf8("行囊中没有这件物品。");
}

String CanglingWorld::ccb_wash_item(const String &item_id) {
    const String msg = ccb_state.wash_item_id(item_id.utf8().get_data());
    if (msg.find(String::utf8("清洗干净")) >= 0) {
        ccb_advance_moves(6000 * 5);
    }
    return msg;
}

bool CanglingWorld::ccb_reorder_worn(int idx, int delta) {
    return ccb_state.reorder_worn(idx, delta);
}

String CanglingWorld::ccb_transfer_item(Vector2i from_pos, bool from_bag, Vector2i to_pos, bool to_bag, const String &item_id, int count) {
    if (active_pack != CorePackId::Cataclysm) return String();
    const std::string sid = item_id.utf8().get_data();
    const int want = std::max(1, count);
    bool filthy = false;
    int damage = 0;
    int moved = 0;

    if (from_bag) {
        for (auto it = ccb_state.bag.begin(); it != ccb_state.bag.end(); ++it) {
            if (it->id == sid) {
                moved = std::min(want, it->count);
                filthy = it->filthy;
                damage = it->damage;
                it->count -= moved;
                if (it->count <= 0) ccb_state.bag.erase(it);
                break;
            }
        }
    } else {
        if (!near(from_pos)) return String::utf8("目标格距离太远。");
        ensure_ccb_loot_at(from_pos);
        auto map_it = ccb_state.world_items.find(key(from_pos, floor));
        if (map_it != ccb_state.world_items.end()) {
            for (auto vit = map_it->second.begin(); vit != map_it->second.end(); ++vit) {
                if (vit->id == sid) {
                    moved = std::min(want, vit->count);
                    filthy = vit->filthy;
                    damage = vit->damage;
                    vit->count -= moved;
                    if (vit->count <= 0) map_it->second.erase(vit);
                    break;
                }
            }
        }
    }
    if (moved <= 0) return String::utf8("来源处未找到该物品。");

    if (to_bag) {
        ccb_state.add_bag_item(sid, moved, filthy, damage);
    } else {
        if (!near(to_pos)) {
            // Rollback
            if (from_bag) ccb_state.add_bag_item(sid, moved, filthy, damage);
            else ccb_state.world_items[key(from_pos, floor)].push_back({sid, moved, 0, filthy, damage});
            return String::utf8("目标格距离太远。");
        }
        ccb_state.world_items[key(to_pos, floor)].push_back({sid, moved, 0, filthy, damage});
    }
    ccb_advance_moves(50);
    const auto *def = CcbVanillaDB::instance().find_item(sid);
    return String::utf8("已移动「") + String::utf8(def ? def->name_zh.c_str() : sid.c_str()) +
           String::utf8("」×") + String::num_int64(moved) + String::utf8("。");
}

String CanglingWorld::ccb_craft_batch(const String &recipe_id, int batch_count) {
    if (active_pack != CorePackId::Cataclysm) return String();
    const int n = std::clamp(batch_count, 1, 20);
    int done = 0;
    int total_min = 0;
    String last_msg;
    for (int i = 0; i < n; ++i) {
        int tmin = 0;
        last_msg = ccb_state.craft_recipe(recipe_id.utf8().get_data(), char_state, tmin);
        if (tmin <= 0) break;
        ++done;
        total_min += tmin;
    }
    if (done == 0) return last_msg;
    // Vanilla batch time saving (~10-20% faster on batches)
    const int eff_min = (done > 1) ? std::max(1, static_cast<int>(std::round(static_cast<double>(total_min) * 0.85))) : total_min;
    ccb_advance_moves(eff_min * 6000);
    if (done == 1) return last_msg;
    return String::utf8("批量制作完成 ×") + String::num_int64(done) + String::utf8("（耗时 ") +
           String::num_int64(eff_min) + String::utf8(" 分钟）。");
}

Dictionary CanglingWorld::ccb_pixel_minimap_data(int radius) {
    Dictionary out;
    if (active_pack != CorePackId::Cataclysm) return out;
    const int r = std::clamp(radius, 16, 60);
    const int side = r * 2 + 1;
    PackedByteArray rgba;
    rgba.resize(side * side * 4);
    uint8_t *dst = rgba.ptrw();

    const int x0 = pos.x - r;
    const int y0 = pos.y - r;
    const Vector2i omt0 = CcbOvermapManager::world_to_omt({x0, y0});
    const Vector2i omt1 = CcbOvermapManager::world_to_omt({x0 + side - 1, y0 + side - 1});
    const int ox_span = std::max(1, omt1.x - omt0.x + 1);
    const int oy_span = std::max(1, omt1.y - omt0.y + 1);
    std::vector<std::shared_ptr<const OmtChunk>> grid(static_cast<std::size_t>(ox_span * oy_span));
    for (int oy = omt0.y; oy <= omt1.y; ++oy) {
        for (int ox = omt0.x; ox <= omt1.x; ++ox) {
            grid[static_cast<std::size_t>((oy - omt0.y) * ox_span + (ox - omt0.x))] = ccb_overmap.chunk_at_omt({ox, oy});
        }
    }

    auto put_px = [&](int lx, int ly, uint8_t cr, uint8_t cg, uint8_t cb) {
        if (lx < 0 || ly < 0 || lx >= side || ly >= side) return;
        const int off = (ly * side + lx) * 4;
        dst[off + 0] = cr;
        dst[off + 1] = cg;
        dst[off + 2] = cb;
        dst[off + 3] = 255;
    };

    for (int ly = 0; ly < side; ++ly) {
        const int wy = y0 + ly;
        const int oy = CcbOvermapManager::world_to_omt({0, wy}).y;
        const int cy = wy - oy * kOmtSize;
        for (int lx = 0; lx < side; ++lx) {
            const int wx = x0 + lx;
            const int ox = CcbOvermapManager::world_to_omt({wx, 0}).x;
            const int cx = wx - ox * kOmtSize;
            const auto &ch = grid[static_cast<std::size_t>((oy - omt0.y) * ox_span + (ox - omt0.x))];
            const std::size_t cidx = static_cast<std::size_t>(cy * kOmtSize + cx);
            const std::string &ter = ch->terrain[cidx];
            const std::string &furn = ch->furniture[cidx];

            // Vanilla pixel_minimap.cpp semantic colors
            uint8_t cr = 22, cg = 28, cb = 22;
            if (ter.find("wall") != std::string::npos || ter.find("fence") != std::string::npos) {
                cr = 175; cg = 175; cb = 175;
            } else if (ter.find("door") != std::string::npos) {
                cr = 180; cg = 115; cb = 55;
            } else if (ter.find("window") != std::string::npos) {
                cr = 90; cg = 195; cb = 220;
            } else if (ter.find("water") != std::string::npos) {
                cr = 35; cg = 95; cb = 195;
            } else if (ter.find("tree") != std::string::npos || ter.find("shrub") != std::string::npos) {
                cr = 26; cg = 105; cb = 36;
            } else if (ter.find("pavement") != std::string::npos || ter.find("sidewalk") != std::string::npos) {
                cr = 62; cg = 64; cb = 68;
            } else if (ter.find("floor") != std::string::npos || ter.find("linoleum") != std::string::npos || ter.find("carpet") != std::string::npos) {
                cr = 46; cg = 44; cb = 42;
            } else if (ter.find("grass") != std::string::npos || ter.find("dirt") != std::string::npos) {
                cr = 30; cg = 58; cb = 28;
            }
            if (!furn.empty()) {
                cr = 128; cg = 96; cb = 64;
            }
            const int64_t dk = key({wx, wy}, floor);
            if (const auto wit = ccb_state.world_items.find(dk); wit != ccb_state.world_items.end() && !wit->second.empty()) {
                cr = static_cast<uint8_t>(std::min(255, int(cr) + 65));
                cg = static_cast<uint8_t>(std::min(255, int(cg) + 60));
            }
            put_px(lx, ly, cr, cg, cb);
        }
    }

    // Corpses (dark crimson)
    for (const auto &c : ccb_state.corpses) {
        if (c.butchered || c.floor != floor) continue;
        put_px(c.pos.x - x0, c.pos.y - y0, 130, 35, 35);
    }
    // Live hostile monsters (bright red beacon, 2x2 highlight)
    const Array mons = monsters.monsters_in_rect(Rect2i(x0, y0, side, side), floor);
    for (int i = 0; i < mons.size(); ++i) {
        const Dictionary md = mons[i];
        const Vector2i mp = md.get("pos", Vector2i(0, 0));
        const int lx = mp.x - x0;
        const int ly = mp.y - y0;
        put_px(lx, ly, 255, 45, 45);
        put_px(lx + 1, ly, 220, 30, 30);
    }
    // Player beacon (bright white + green cross at center)
    put_px(r, r, 255, 255, 255);
    put_px(r - 1, r, 80, 255, 110);
    put_px(r + 1, r, 80, 255, 110);
    put_px(r, r - 1, 80, 255, 110);
    put_px(r, r + 1, 80, 255, 110);

    out["width"] = side;
    out["height"] = side;
    out["rgba"] = rgba;
    return out;
}

Dictionary CanglingWorld::ccb_inspect_tile(Vector2i p) {
    Dictionary out;
    if (active_pack != CorePackId::Cataclysm) return out;
    out["pos"] = p;
    out["distance"] = std::max(std::abs(p.x - pos.x), std::abs(p.y - pos.y));
    out["location"] = location(p);
    const std::string ter = ccb_overmap.terrain_at(p);
    const std::string furn = ccb_overmap.furniture_at(p);
    out["terrain_id"] = String::utf8(ter.c_str());
    out["furniture_id"] = String::utf8(furn.c_str());
    out["walkable"] = walkable_on(p, floor);
    out["radiation"] = static_cast<double>(ccb_overmap.radiation_at(p));
    out["monster"] = monster_at(p);
    out["corpses"] = ccb_corpses_at(p);
    out["items"] = ccb_items_at(p);
    out["blood"] = ccb_state.blood_tiles.count(key(p, floor)) ? ccb_state.blood_tiles[key(p, floor)] : 0;
    return out;
}

void CanglingWorld::ccb_set_overmap_note(Vector2i omt, const String &note) {
    ccb_state.set_overmap_note(omt, note.strip_edges().utf8().get_data());
}

Array CanglingWorld::ccb_search_overmap(const String &query, Vector2i from_omt, int radius) {
    Array out;
    const std::string q_raw = query.strip_edges().utf8().get_data();
    if (q_raw.empty()) return out;
    const int r = std::clamp(radius, 5, 60);
    for (int dy = -r; dy <= r; ++dy) {
        for (int dx = -r; dx <= r; ++dx) {
            const Vector2i omt = from_omt + Vector2i(dx, dy);
            if (!ccb_state.is_omt_seen(omt)) continue;
            const OmtCell c = ccb_overmap.cell_at_omt(omt);
            const String nm = String::utf8(CcbOvermapManager::omt_kind_name_cn(c.kind));
            const String nt = String::utf8(ccb_state.get_overmap_note(omt).c_str());
            if (nm.findn(query) >= 0 || nt.findn(query) >= 0) {
                Dictionary d;
                d["omt"] = omt;
                d["name"] = nm;
                d["note"] = nt;
                d["dist"] = std::abs(dx) + std::abs(dy);
                out.append(d);
                if (out.size() >= 30) return out;
            }
        }
    }
    return out;
}

bool CanglingWorld::ccb_debug_spawn_monster(const String &mtype_id, Vector2i target) {
    if (active_pack != CorePackId::Cataclysm) return false;
    return monsters.spawn_one(mtype_id.utf8().get_data(), target, floor, true);
}

String CanglingWorld::ccb_give_item(const String &item_id, int count) {
    const std::string sid = item_id.utf8().get_data();
    const auto *def = CcbVanillaDB::instance().find_item(sid);
    if (!def) return String::utf8("未在 CCB 物品库中找到该物品 ID。");
    const int n = std::clamp(count, 1, 99);
    ccb_state.add_bag_item(sid, n);
    return String::utf8("已获得原版物品「") + String::utf8(def->name_zh.c_str()) +
           String::utf8("」×") + String::num_int64(n) + String::utf8("。");
}

double CanglingWorld::ccb_tile_radiation(Vector2i p) const {
    if (active_pack == CorePackId::Cataclysm) {
        return static_cast<double>(const_cast<CcbOvermapManager &>(ccb_overmap).radiation_at(p));
    }
    return static_cast<double>(city.radiation_at(p));
}

Array CanglingWorld::ccb_irradiate(double rads, bool bypass) {
    std::vector<String> msgs;
    ccb_state.irradiate(static_cast<float>(rads), bypass, msgs);
    Array out;
    for (const auto &m : msgs) out.append(m);
    return out;
}

Array CanglingWorld::ccb_mutate_category(const String &cat_id) {
    std::vector<String> msgs;
    ccb_state.mutate_category(cat_id.utf8().get_data(), false, msgs);
    Array out;
    for (const auto &m : msgs) out.append(m);
    return out;
}

Array CanglingWorld::ccb_purify() {
    std::vector<String> msgs;
    ccb_state.purify_one(msgs);
    Array out;
    for (const auto &m : msgs) out.append(m);
    return out;
}

Array CanglingWorld::pop_ccb_messages() {
    Array out = pending_ccb_messages.duplicate();
    pending_ccb_messages.clear();
    return out;
}

Array CanglingWorld::monsters_in_rect(Rect2i area) const {
    if (active_pack != CorePackId::Cataclysm) return Array();
    return monsters.monsters_in_rect(area, floor);
}

Dictionary CanglingWorld::monster_at(Vector2i p) const {
    if (active_pack != CorePackId::Cataclysm) return Dictionary();
    return monsters.monster_dict_at(p, floor);
}

Dictionary CanglingWorld::tick_monsters(int steps) {
    Dictionary out;
    if (active_pack != CorePackId::Cataclysm) {
        out["messages"] = Array();
        out["active_count"] = 0;
        return out;
    }
    const int hour = (minutes / 60) % 24;
    const bool is_night = (hour < 6 || hour >= 20);
    const auto res = monsters.tick(
        steps, pos, floor, is_night, char_state, ccb_state,
        [this](Vector2i p, int z) {
            if (!in_bounds(p)) return false;
            const char t = effective_tile(p, z);
            return passable_tile(t) && t != 'D';
        },
        [this](Vector2i p, int z) {
            if (!in_bounds(p)) return true;
            const char t = effective_tile(p, z);
            return t == '#' || t == 'D';
        });
    out["messages"] = res.messages;
    out["player_damaged"] = res.player_damaged;
    out["safe_mode_alert"] = res.safe_mode_alert;
    out["active_count"] = res.active_count;
    out["alerted_count"] = res.alerted_count;
    return out;
}

Dictionary CanglingWorld::attack_monster_at(Vector2i p) {
    Dictionary out;
    out["hit"] = false;
    out["killed"] = false;
    out["damage"] = 0;
    out["message"] = String();
    if (active_pack != CorePackId::Cataclysm || !near(p)) return out;
    const auto res = monsters.player_attack(p, floor, char_state, ccb_state, kills);
    if (res.hit) {
        ccb_state.add_blood(p, floor, res.killed ? 2 : 1);
    }
    Array drop_items_arr;
    if (res.killed) {
        // Spawn real vanilla corpse + blood + ALL vanilla death_drops (with FILTHY/damage flags)!
        ccb_state.spawn_corpse(res.killed_species_id.empty() ? std::string("mon_zombie") : res.killed_species_id,
                               res.drop_pos, floor, minutes);
        const auto &db = CcbVanillaDB::instance();
        for (const auto &dst : res.drops) {
            ccb_state.world_items[key(res.drop_pos, floor)].push_back(dst);
            drop_items_arr.append(db.stack_to_dict(dst));
        }
    }
    out["hit"] = res.hit;
    out["crit"] = res.crit;
    out["killed"] = res.killed;
    out["damage"] = res.damage;
    out["message"] = res.message;
    out["drop_items"] = drop_items_arr;
    out["drop_item_id"] = drop_items_arr.is_empty() ? String() : String(Dictionary(drop_items_arr[0]).get("id", String()));
    return out;
}

bool CanglingWorld::apply_world_mutation(const Dictionary &mut) {
    const String kind = mut.get("kind", String());
    const Variant pv = mut.get("pos", Vector2i(-1, -1));
    Vector2i p(-1, -1);
    if (pv.get_type() == Variant::VECTOR2I) p = pv;
    else if (pv.get_type() == Variant::ARRAY) {
        const Array a = pv;
        if (a.size() >= 2) p = Vector2i(a[0], a[1]);
    }
    const int z = static_cast<int>(mut.get("floor", floor));
    if (!in_bounds(p)) return false;

    if (kind == String("door_open")) {
        doors.insert(key(p, z));
        return true;
    }
    if (kind == String("door_close")) {
        doors.erase(key(p, z));
        return true;
    }
    if (kind == String("tile_override")) {
        const int ch = static_cast<int>(mut.get("tile", static_cast<int>('.')));
        tile_overrides[key(p, z)] = static_cast<char>(ch);
        return true;
    }
    if (kind == String("monster_hit")) {
        const int dmg = static_cast<int>(mut.get("damage", 0));
        return monsters.apply_remote_hit(p, z, dmg);
    }
    return false;
}
}
