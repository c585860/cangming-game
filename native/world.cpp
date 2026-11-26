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
    BIND(workstation_at, "pos");
    BIND(list_workstations);
    BIND(workstations_in_rect, "area");
    BIND(can_work_at_station, "pos");
    BIND(complete_workstation, "pos");
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
    }
}

void CanglingWorld::rest_minutes(int amount, bool sleeping) {
    if (amount > 0) {
        char_state.advance_minutes(amount, !sleeping, sleeping);
    }
}

void CanglingWorld::setup(int64_t new_seed) {
    seed = static_cast<std::uint32_t>(new_seed);
    city.reset(seed);
    pos = start_tile;
    floor = quest = herbs = jobs_done = 0;
    coins = 10;
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
    char_state.sync_with_skills(skill_set);
    remote_players.clear();
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
    if (z == 0 && is_npc_tile(p)) return false;
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
        return true;
    }
    const Vector2i prev = pos;
    pos = next;
    // CCB movement stance effects (0=Walk, 1=Run, 2=Crouch, 3=Prone) — real-time clock unaffected by actions
    if (char_state.move_mode == 1) {
        if (char_state.stamina > 300) {
            char_state.spend_stamina(180);
            char_state.last_sound = 14;
        } else {
            char_state.move_mode = 0;
            char_state.last_sound = 6;
        }
    } else if (char_state.move_mode == 2) {
        char_state.last_sound = 2;
    } else if (char_state.move_mode == 3) {
        char_state.last_sound = 0;
    } else {
        char_state.last_sound = (tile == 'O' || tile == '%') ? 10 : 6;
    }
    if (char_state.hauling) {
        haul_items_from(prev, pos);
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
    return char_state.to_dict(carried, carried_water);
}

PackedStringArray CanglingWorld::worn_overlays() const {
    return char_state.worn_overlays();
}

Array CanglingWorld::npc_list() const {
    Array out;
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
    if (floor != 0) return out;
    for (const auto &npc : kYangzhouNpcs) {
        if (area.has_point(npc.pos)) {
            out[npc.pos] = StringName(npc.id);
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
    if (floor != 0) return Dictionary();
    const WorkstationDef *ws = workstation_at_tile(p);
    if (ws == nullptr) return Dictionary();
    return workstation_to_dict(*ws, skill_set);
}

Array CanglingWorld::list_workstations() const {
    Array out;
    for (const auto &ws : workstation_catalog()) {
        out.append(workstation_to_dict(ws, skill_set));
    }
    return out;
}

Array CanglingWorld::workstations_in_rect(Rect2i area) const {
    Array out;
    if (floor != 0) return out;
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
    skill_set.set_jifa(idx, art);
    if (art.empty()) {
        return String::utf8("已取消「") + String::utf8(def.name) + String::utf8("」的激发武功。");
    }
    return String::utf8("已将「") + special_art_id + String::utf8("」激发至「") + String::utf8(def.name) + String::utf8("」。");
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
    return out;
}
}
