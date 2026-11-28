#include "bridge_state.hpp"

#include "avatar.h"
#include "calendar.h"
#include "character.h"
#include "color.h"
#include "coordinates.h"
#include "creature.h"
#include "creature_tracker.h"
#include "enums.h"
#include "field.h"
#include "field_type.h"
#include "game.h"
#include "game_constants.h"
#include "iexamine.h"
#include "item.h"
#include "level_cache.h"
#include "lightmap.h"
#include "line.h"
#include "map.h"
#include "map_memory.h"
#include "map_scale_constants.h"
#include "mapdata.h"
#include "monster.h"
#include "mtype.h"
#include "npc.h"
#include "options.h"
#include "point.h"
#include "smooth_lighting.h"
#include "submap.h"
#include "trap.h"
#include "units.h"
#include "veh_type.h"
#include "vehicle.h"
#include "vpart_position.h"
#include "weather.h"
#include "weather_type.h"

#include <algorithm>
#include <array>
#include <climits>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace ccb_bridge {

namespace {

// Exact physical geometry constants from CCB src/render3d.cpp
constexpr int REGION_RADIUS = 18;
constexpr int REGION_SIZE = REGION_RADIUS * 2 + 1;
constexpr int VIEW_RADIUS = 28; // Crisp 57x57 live view radius around camera center (~3.2k tiles, ultra-fast!)
constexpr int MAX_SCENE_ITEMS = 24576;

constexpr float LEVEL_HEIGHT = 2.6f;
constexpr float FLOOR_THICK = 0.1f;
constexpr float WALL_HEIGHT = LEVEL_HEIGHT - FLOOR_THICK * 0.5f; // 2.55m
constexpr float TREE_HEIGHT = 3.0f;
constexpr float SHRUB_HEIGHT = 0.9f;
constexpr float FURN_QUAD_HEIGHT = 1.2f;
constexpr float PANEL_HEIGHT = 1.4f;
constexpr float PANEL_THICK = 0.1f;
constexpr float FENCE_HEIGHT = 1.5f;
constexpr float CREATURE_BASE_HEIGHT = 1.8f;
constexpr float CHARACTER_SIZE_SCALE = 0.85f;
constexpr float ITEM_HEIGHT = 0.5f;
constexpr float FIELD_DECAL_Z = 0.004f;
constexpr float FIELD_DECAL_STAGGER = 0.0008f;
constexpr float FIELD_RISER_HEIGHT = 1.4f;
constexpr float FIELD_RISER_OFFSET = 0.008f;

constexpr float VEH_DECAL_Z = 0.005f;
constexpr float VEH_PANEL_BASE_Z = 0.02f;
constexpr float VEH_PANEL_ZSCALE = 0.9f;
constexpr float VEH_ROOF_Z = 1.35f;
constexpr float VEH_BODY_BASE = 0.35f;
constexpr float VEH_BODY_PER_SPILL = 0.9f;
constexpr float VEH_PROX_HIDE_DIST = 5.0f;

constexpr int SUBTILE_EDGE = 2; // MULTITILE_TYPE::edge
constexpr int DOLLHOUSE_RADIUS = 12;

class StringInterner3D {
public:
    StringInterner3D(std::vector<char> &buf, std::unordered_map<std::string, uint16_t> &map)
        : buf_(buf), map_(map) {
        buf_.clear();
        buf_.push_back('\0');
        map_.clear();
        count_ = 1;
    }

    uint16_t intern(const std::string &s) {
        if (s.empty()) {
            return 0;
        }
        auto it = map_.find(s);
        if (it != map_.end()) {
            return it->second;
        }
        if (count_ >= 65530) {
            return 0;
        }
        const uint16_t id = static_cast<uint16_t>(count_++);
        map_.emplace(s, id);
        buf_.insert(buf_.end(), s.begin(), s.end());
        buf_.push_back('\0');
        return id;
    }

    int32_t count() const { return count_; }

private:
    std::vector<char> &buf_;
    std::unordered_map<std::string, uint16_t> &map_;
    int32_t count_ = 0;
};

// Exact CCB render3d.cpp pastel terrain hash fallback color
void terrain_hash_color(const int id, float &r, float &g, float &b) {
    const uint32_t h = static_cast<uint32_t>(id) * 2654435761u;
    const float hue = static_cast<float>(h % 360u) / 60.0f;
    const float x = 1.0f - std::fabs(std::fmod(hue, 2.0f) - 1.0f);
    float rr = 0.0f, gg = 0.0f, bb = 0.0f;
    switch (static_cast<int>(hue)) {
        case 0: rr = 1.0f; gg = x; break;
        case 1: rr = x; gg = 1.0f; break;
        case 2: gg = 1.0f; bb = x; break;
        case 3: gg = x; bb = 1.0f; break;
        case 4: rr = x; bb = 1.0f; break;
        default: rr = 1.0f; bb = x; break;
    }
    const float gray = (rr + gg + bb) / 3.0f;
    r = gray + (rr - gray) * 0.55f;
    g = gray + (gg - gray) * 0.55f;
    b = gray + (bb - gray) * 0.55f;
}

uint16_t tile_seed(const tripoint_bub_ms &p) {
    const uint32_t h = static_cast<uint32_t>(p.x() * 73856093) ^
                       static_cast<uint32_t>(p.y() * 19349663) ^
                       static_cast<uint32_t>(p.z() * 83492791);
    return static_cast<uint16_t>((h ^ (h >> 16)) & 0xFFFFu);
}

int angle_to_dir4_3d(const units::angle a) {
    const double deg = std::fmod(to_degrees(a) + 360.0, 360.0);
    return (static_cast<int>(std::lround(deg / 90.0)) + 4) & 3;
}

// --- Exact CCB render3d.cpp terrain & furniture classification helpers ---

bool door_or_window(const ter_t &t) {
    if (t.has_flag(ter_furn_flag::TFLAG_DOOR) ||
        t.has_flag(ter_furn_flag::TFLAG_WINDOW) || !t.open.is_null() ||
        t.has_flag(ter_furn_flag::TFLAG_BARRICADABLE_DOOR) ||
        t.has_flag(ter_furn_flag::TFLAG_BARRICADABLE_DOOR_DAMAGED) ||
        t.has_flag(ter_furn_flag::TFLAG_BARRICADABLE_DOOR_REINFORCED) ||
        (t.has_flag(ter_furn_flag::TFLAG_LOCKED) &&
         !t.has_flag(ter_furn_flag::TFLAG_THIN_OBSTACLE))) {
        return true;
    }
    static const std::string broken_reinforced("BARRICADABLE_DOOR_REINFORCED_DAMAGED");
    return t.has_flag(broken_reinforced);
}

bool joins_wall_line(const ter_t &t) {
    static const int wall_group = get_connect_group("WALL").index;
    return t.connect_to_groups.test(wall_group);
}

bool wall_opening(const ter_t &t) {
    if (t.has_flag(ter_furn_flag::TFLAG_WINDOW) ||
        t.has_flag(ter_furn_flag::TFLAG_DOOR) || t.movecost <= 0 ||
        t.has_flag(ter_furn_flag::TFLAG_WALL) ||
        t.has_flag(ter_furn_flag::TFLAG_THIN_OBSTACLE) ||
        !joins_wall_line(t)) {
        return false;
    }
    return !t.close.is_null() ||
           (t.has_flag(ter_furn_flag::TFLAG_FLAT) &&
            t.has_flag(ter_furn_flag::TFLAG_SUPPORTS_ROOF));
}

bool empty_frame_terrain(const ter_t &t) {
    return t.movecost > 0 && t.open.is_null() && t.close.is_null() &&
           (t.has_flag(ter_furn_flag::TFLAG_WINDOW) || wall_opening(t));
}

bool wall_terrain(const ter_t &t) {
    return t.movecost == 0 && t.has_flag(ter_furn_flag::TFLAG_WALL) &&
           !door_or_window(t) &&
           !t.has_flag(ter_furn_flag::TFLAG_THIN_OBSTACLE);
}

bool flat_utility_terrain(const ter_t &t, const int z) {
    static constexpr std::array<std::string_view, 7> ground_ids = {{
        "t_sewage_pipe", "t_nl_sewage_pipe", "t_nl_sewage_pipe_border",
        "t_LIXA_tube", "t_LIXA_unfolded_tube", "t_LIXA_unfolded_tube_broken",
        "t_gutter"
    }};
    const std::string_view id(t.id.str());
    if (std::find(ground_ids.begin(), ground_ids.end(), id) != ground_ids.end()) {
        return true;
    }
    if (z <= 0) {
        return false;
    }
    static constexpr std::array<std::string_view, 4> roof_ids = {{
        "t_gutter_drop", "t_gutter_downspout",
        "t_vitrified_gutter_drop", "t_vitrified_downspout"
    }};
    return std::find(roof_ids.begin(), roof_ids.end(), id) != roof_ids.end();
}

bool upright_equipment_terrain(const ter_t &t) {
    static constexpr std::array<std::string_view, 2> ids = {{"t_monkey_bars", "t_slide"}};
    return std::find(ids.begin(), ids.end(), std::string_view(t.id.str())) != ids.end();
}

bool skip_untextured_terrain_surface(const ter_t &t) {
    static constexpr std::array<std::string_view, 5> ids = {{
        "t_canvas_roof", "t_treetop", "t_treetop_evergreen",
        "t_treetop_dead", "t_treetop_giant_fern"
    }};
    return std::find(ids.begin(), ids.end(), std::string_view(t.id.str())) != ids.end();
}

bool flat_furniture(const furn_t &f) {
    static constexpr std::array<std::string_view, 13> ids = {{
        "f_tatami",
        "f_groundsheet", "f_large_groundsheet", "f_center_groundsheet", "f_fema_groundsheet",
        "f_skin_groundsheet", "f_large_skin_groundsheet", "f_skin_center_groundsheet",
        "f_fiber_mat", "f_leather_tarp", "f_plastic_groundsheet",
        "f_cardboard_floor", "f_scrap_bridge"
    }};
    return std::find(ids.begin(), ids.end(), std::string_view(f.id.str())) != ids.end();
}

bool wants_layered_face(const map_data_common_t &d) {
    return d.has_flag(ter_furn_flag::TFLAG_LOCKED) ||
           d.has_flag(ter_furn_flag::TFLAG_ALARMED) ||
           d.has_flag(ter_furn_flag::TFLAG_PICKABLE) ||
           d.has_examine(iexamine::safe) ||
           d.has_examine(iexamine::gunsafe_el);
}

template<typename TerAt>
const ter_t *panel_run_end(const tripoint_bub_ms &p, const point &step,
                           const TerAt &get_ter, tripoint_bub_ms &wall_pos) {
    tripoint_bub_ms q = p;
    for (int hop = 0; hop < 32; ++hop) {
        q += step;
        if (!get_map().inbounds(q)) {
            return nullptr;
        }
        const ter_t *nt = get_ter(q);
        if (nt == nullptr) {
            return nullptr;
        }
        if (door_or_window(*nt) || wall_opening(*nt)) {
            continue;
        }
        if (!wall_terrain(*nt)) {
            return nullptr;
        }
        wall_pos = q;
        return nt;
    }
    return nullptr;
}

float creature_size_scale(const creature_size size) {
    switch (size) {
        case creature_size::tiny:   return 0.4f;
        case creature_size::small:  return 0.7f;
        case creature_size::medium: return 1.0f;
        case creature_size::large:  return 1.4f;
        case creature_size::huge:   return 2.0f;
        default:                    return 1.0f;
    }
}

uint8_t memory_preset_from_option(const std::string &opt) {
    if (opt == "color_pixel_sepia_light") return 1;
    if (opt == "color_pixel_sepia_dark")  return 2;
    if (opt == "color_pixel_blue_dark")   return 3;
    return 0; // color_pixel_darken default
}

phase_id field_render_phase(field_type_id id) {
    for (int hop = 0; hop < 4 && id.is_valid(); ++hop) {
        const field_type &st = id.obj();
        if (st.phase != phase_id::PNULL) {
            return st.phase;
        }
        const field_type_str_id ll(st.looks_like);
        if (!ll.is_valid()) {
            break;
        }
        id = ll.id();
    }
    return phase_id::PNULL;
}

struct TileTone {
    float shade = 1.0f;
    float sat = 1.0f;
};

void compute_ter_sub_rot(const map &here, const tripoint_bub_ms &p, const ter_t &t, int &sub, int &rot) {
    sub = 0;
    rot = 0;
    const auto &conn_g = t.connect_to_groups;
    const auto &rot_g = t.rotate_to_groups;
    if (conn_g.any()) {
        map::get_connect_values(p, sub, rot, conn_g, rot_g, {});
    } else {
        const std::array<bool, 5> inv = {false, false, false, false, false};
        map::get_terrain_orientation(p, rot, sub, {}, inv, rot_g);
    }
    sub = std::clamp(sub, 0, 7);
    rot = rot & 15;
}

} // namespace

void capture_scene3d_snapshot(Scene3DSnapshot &out, uint64_t gen, bool has_terrain) {
    out.header = CcbScene3DHeader{};
    out.header.generation = gen;
    out.header.valid = 0;
    out.items.clear();
    out.lights.clear();

    if (!has_terrain || g == nullptr || !g->w_terrain) {
        return;
    }

    map &here = get_map();
    avatar &you = get_avatar();
    const tripoint_bub_ms center = g->ter_view_p;
    if (!here.inbounds(center)) {
        return;
    }
    const tripoint_bub_ms upos = you.pos_bub(here);
    const tripoint_bub_ms observer_pos = here.observer_position(you);
    const int cz = center.z();
    const bool same_level_only = state().render3d_same_level_only.load(std::memory_order_acquire);

    // Prepare multi-Z map memory read window across loaded Z origin (exact CCB render3d.cpp rule)
    you.prepare_map_memory_region(
        here.get_abs(tripoint_bub_ms(0, 0, here.z_origin())),
        here.get_abs(tripoint_bub_ms(MAPSIZE_X - 1, MAPSIZE_Y - 1, here.z_origin())));

    const level_cache &center_cache = here.get_cache_ref(cz);
    const visibility_variables &vis_vars = here.get_visibility_variables_cache();
    const int lowest_vis_z = std::max(std::min(cz, observer_pos.z() - here.observer_z_range(you)), here.min_z());
    const int zmin = same_level_only ? cz : std::max(here.min_z(), cz - 2);
    const int zmax = same_level_only ? cz : std::min(here.max_z(), cz + 6);

    // Calendar sun, daylight, weather clouds, wind, night vision, memory preset
    const float daylight = std::clamp(center_cache.natural_light_level_cache / LIGHT_AMBIENT_LIT, 0.0f, 1.0f);
    const auto sun_aa = sun_azimuth_altitude(calendar::turn);
    const float sun_az = static_cast<float>(units::to_degrees(sun_aa.first)) * 3.14159265f / 180.0f;
    const float sun_alt = static_cast<float>(units::to_degrees(sun_aa.second)) * 3.14159265f / 180.0f;
    const float sun_x = -std::sin(sun_az) * std::cos(sun_alt);
    const float sun_y = std::cos(sun_az) * std::cos(sun_alt);
    const float sun_z = std::sin(sun_alt);
    const bool sun_up = (sun_alt > 0.0f && daylight > 0.05f);

    const weather_manager &weather = get_weather_const();
    const float clear_sun = incident_sunlight(WEATHER_CLEAR);
    const float cur_sun = incident_sunlight(weather.weather_id);
    const float cloudiness = clear_sun > 1e-3f ? std::clamp(1.0f - cur_sun / clear_sun, 0.0f, 1.0f) : 0.5f;
    const rl_vec2d wind_dir = convert_wind_to_coord(weather.winddirection);
    const float wind_spd = static_cast<float>(weather.windspeed) * 0.01f;

    const bool nv_tint = you.get_vision_modes()[NV_GOGGLES] && get_option<bool>("NV_GREEN_TOGGLE");
    const uint8_t mem_preset = memory_preset_from_option(get_option<std::string>("MEMORY_MAP_MODE"));

    out.header.center_x = center.x();
    out.header.center_y = center.y();
    out.header.center_z = cz;
    out.header.player_x = upos.x();
    out.header.player_y = upos.y();
    out.header.player_z = upos.z();
    out.header.season = static_cast<int32_t>(season_of_year(calendar::turn));
    out.header.turn = to_turns<int>(calendar::turn - calendar::turn_zero);
    out.header.daylight = daylight;
    out.header.sun_x = sun_x;
    out.header.sun_y = sun_y;
    out.header.sun_z = sun_z;
    out.header.sun_up = sun_up ? 1.0f : 0.0f;
    out.header.cloudiness = cloudiness;
    out.header.wind_x = static_cast<float>(wind_dir.x) * wind_spd;
    out.header.wind_y = static_cast<float>(wind_dir.y) * wind_spd;
    out.header.nv_active = nv_tint ? 1.0f : 0.0f;
    out.header.nv_floor = smooth_lighting::night_floor;
    out.header.nv_overexpose = smooth_lighting::overexpose_start;
    out.header.memory_preset = mem_preset;
    out.header.same_level_only = same_level_only ? 1 : 0;
    out.header.controlling_vehicle = you.controlling_vehicle ? 1 : 0;
    out.header.is_looking = (you.view_offset != tripoint_rel_ms::zero) ? 1 : 0;
    out.header.veh_ind_x = INT32_MIN;
    out.header.veh_ind_y = INT32_MIN;
    if (you.controlling_vehicle) {
        if (const std::optional<tripoint_rel_ms> ind = g->get_veh_dir_indicator_location(true)) {
            out.header.veh_ind_x = (upos.x() + ind->x()) - center.x();
            out.header.veh_ind_y = (upos.y() + ind->y()) - center.y();
        }
    }

    static std::unordered_map<std::string, uint16_t> s_intern3d_map;
    StringInterner3D intern(out.strings, s_intern3d_map);
    if (out.items.capacity() < 16384) {
        out.items.reserve(16384);
    }

    auto push = [&](uint8_t mode, uint8_t pick, uint16_t sprite_str,
                    float px, float py, float pz, float sx, float sy, float sz,
                    float r, float g8, float b, float sat, uint32_t flags,
                    uint8_t subtile = 0xFF, uint8_t rot = 0, uint16_t seed = 0,
                    float v0 = 0.0f, float v1 = 1.0f, int16_t pad_i16 = 0) {
        if (static_cast<int>(out.items.size()) >= MAX_SCENE_ITEMS) {
            return;
        }
        CcbScene3DItem it{};
        it.px = px;
        it.py = py;
        it.pz = pz;
        it.sx = sx;
        it.sy = sy;
        it.sz = sz;
        it.r = r;
        it.g = g8;
        it.b = b;
        it.sat = sat;
        // Exact CCB mask-eligibility rule (render3d.cpp line 6517)
        if (mode == CCB_3D_MODE_BOX || mode == CCB_3D_MODE_LINEQUAD ||
            mode == CCB_3D_MODE_FLATQUAD || mode == CCB_3D_MODE_LINEQUAD_DECAL) {
            flags |= CCB_3D_FLAG_MASK_ELIGIBLE;
        }
        it.flags = flags;
        it.sprite_str = sprite_str;
        it.mode = mode;
        it.pick = pick;
        it.subtile = subtile;
        it.rot = rot;
        it.v0_u8 = static_cast<uint8_t>(std::clamp(std::lround(v0 * 255.0f), 0l, 255l));
        it.v1_u8 = static_cast<uint8_t>(std::clamp(std::lround(v1 * 255.0f), 0l, 255l));
        it.seed = seed;
        it.pad_i16 = pad_i16;
        out.items.push_back(it);
    };

    const auto tile_visible = [](const level_cache &c, const tripoint_bub_ms &q) {
        const lit_level ll = c.visibility_cache[q.x()][q.y()];
        return ll == lit_level::LOW || ll == lit_level::LIT || ll == lit_level::BRIGHT;
    };

    const auto upper_lit_at = [&](const level_cache &c, const tripoint_bub_ms &q) {
        if (c.seen_cache[q.x()][q.y()] <= 0.0f && c.camera_cache[q.x()][q.y()] <= 0.0f &&
            vis_vars.u_clairvoyance <= 0 && !vis_vars.clairvoyance_field) {
            return lit_level::BLANK;
        }
        return here.apparent_light_at(q, vis_vars);
    };

    const auto tone_for = [&](const level_cache &c, const tripoint_bub_ms &q,
                              const lit_level ll, const bool wall_surface = false) -> TileTone {
        const float apparent = smooth_lighting::needs_apparent_light(ll)
                               ? map::apparent_light_helper(c, q, wall_surface).apparent_light
                               : 0.0f;
        const float light = smooth_lighting::classify_light_cell(ll, apparent, vis_vars.vision_threshold).light;
        const float t = std::clamp(light / smooth_lighting::full_color_light, 0.0f, 1.0f);
        return TileTone{
            smooth_lighting::shadow_shade + (1.0f - smooth_lighting::shadow_shade) * light,
            nv_tint ? std::clamp(light, 0.0f, 1.0f) : t * t * (3.0f - 2.0f * t)
        };
    };

    // Dollhouse cutout mask (exact CCB render3d.cpp lines 2959-2978):
    // Indoor walkable tiles seen within DOLLHOUSE_RADIUS of player make upper roofs translucent ghost slabs!
    std::array<bool, REGION_SIZE * REGION_SIZE> dollhouse{};
    {
        const point pd(upos.x() - center.x(), upos.y() - center.y());
        for (int dy = -REGION_RADIUS; dy <= REGION_RADIUS; ++dy) {
            for (int dx = -REGION_RADIUS; dx <= REGION_RADIUS; ++dx) {
                const tripoint_bub_ms p = center + tripoint(dx, dy, 0);
                if (!here.inbounds(p)) continue;
                const point r = point(dx, dy) - pd;
                if (r.x * r.x + r.y * r.y <= DOLLHOUSE_RADIUS * DOLLHOUSE_RADIUS &&
                    tile_visible(center_cache, p) &&
                    !center_cache.outside_cache[p.x()][p.y()] &&
                    here.move_cost(p) > 0) {
                    dollhouse[static_cast<size_t>((dy + REGION_RADIUS) * REGION_SIZE + (dx + REGION_RADIUS))] = true;
                }
            }
        }
    }

    const uint16_t str_t_floor = intern.intern("t_floor");
    const uint16_t str_highlight_item = intern.intern("highlight_item");
    std::unordered_map<const vehicle *, bool> veh_shell_hidden;

    const auto push_fog_slab = [&](int dx, int dy, float wz) {
        push(CCB_3D_MODE_BOX, CCB_3D_PICK_SOLID, 0,
             static_cast<float>(dx), static_cast<float>(dy), wz - FLOOR_THICK - 0.001f,
             1.0f, 1.0f, FLOOR_THICK,
             0.02f, 0.02f, 0.028f, nv_tint ? 0.0f : 1.0f,
             CCB_3D_FLAG_NO_DISCARD);
    };

    const auto gather_memory_tile = [&](const tripoint_bub_ms &p, int dx, int dy, float wz, bool with_furniture, bool is_cur_z) -> bool {
        const memorized_tile &mt = you.get_memorized_tile(here.get_abs(p));
        const std::string &mem_ter = mt.get_ter_id();
        const std::string &dec_id = mt.get_dec_id();
        if (mem_ter.empty() && dec_id.empty()) {
            return false;
        }
        const uint16_t sd = tile_seed(p);
        const uint32_t mem_f = CCB_3D_FLAG_TEXTURED | CCB_3D_FLAG_MEMORY;

        auto push_mem_furn = [&]() {
            if (!with_furniture || dec_id.empty() || dec_id.rfind("f_", 0) != 0) return;
            const furn_str_id fid(dec_id);
            if (!fid.is_valid()) return;
            const furn_t &fo = fid.obj();
            const uint16_t fstr = intern.intern(dec_id);
            const uint8_t fsub = static_cast<uint8_t>(std::clamp(mt.get_dec_subtile(), 0, 7));
            const uint8_t frot = static_cast<uint8_t>(mt.get_dec_rotation() & 15);
            if (flat_furniture(fo)) {
                push(CCB_3D_MODE_FLATQUAD_DECAL, CCB_3D_PICK_FG, fstr,
                     static_cast<float>(dx), static_cast<float>(dy), wz + 0.004f,
                     1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, mem_f, fsub, frot, sd);
            } else {
                push(CCB_3D_MODE_BILLBOARD_SNAP, CCB_3D_PICK_FG, fstr,
                     static_cast<float>(dx) + 0.5f, static_cast<float>(dy) + 0.5f, wz,
                     1.0f, FURN_QUAD_HEIGHT, 0.0f, 1.0f, 1.0f, 1.0f, 1.0f,
                     mem_f | CCB_3D_FLAG_BASE_DROP | CCB_3D_FLAG_ASPECT_WIDTH, fsub, frot, sd);
            }
        };

        const ter_str_id tid(mem_ter);
        if (mem_ter.empty() || !tid.is_valid()) {
            if (with_furniture && !dec_id.empty()) {
                push_fog_slab(dx, dy, wz);
                push_mem_furn();
                return true;
            }
            return true;
        }
        const ter_t &t = *tid;
        if (t.has_flag(ter_furn_flag::TFLAG_NO_FLOOR)) {
            if (with_furniture && !dec_id.empty()) {
                push_fog_slab(dx, dy, wz);
                push_mem_furn();
            }
            return true;
        }

        const bool is_tree = t.has_flag(ter_furn_flag::TFLAG_TREE);
        const bool is_shrub = t.has_flag(ter_furn_flag::TFLAG_SHRUB);
        const bool is_opening = wall_opening(t);
        const bool is_panel = door_or_window(t) || is_opening;
        const bool is_fence = !is_panel && t.has_flag(ter_furn_flag::TFLAG_THIN_OBSTACLE);
        const bool is_wall = !is_tree && !is_shrub && !is_panel && !is_fence && t.movecost == 0;
        const uint16_t tstr = intern.intern(mem_ter);
        const uint8_t tsub = static_cast<uint8_t>(std::clamp(mt.get_ter_subtile(), 0, 7));
        const uint8_t trot = static_cast<uint8_t>(mt.get_ter_rotation() & 15);
        const uint32_t slw = is_cur_z ? CCB_3D_FLAG_SAME_LEVEL_WALL : 0u;

        // Ground slab
        if (!skip_untextured_terrain_surface(t)) {
            push(CCB_3D_MODE_BOX, CCB_3D_PICK_GROUND, is_panel ? str_t_floor : tstr,
                 static_cast<float>(dx), static_cast<float>(dy), wz - FLOOR_THICK - 0.001f,
                 1.0f, 1.0f, FLOOR_THICK, 1.0f, 1.0f, 1.0f, 1.0f,
                 mem_f | CCB_3D_FLAG_NO_DISCARD, is_panel ? 0xFF : tsub, is_panel ? 0 : trot, sd);
        }
        if (is_wall) {
            push(CCB_3D_MODE_BOX, CCB_3D_PICK_FG, tstr,
                 static_cast<float>(dx), static_cast<float>(dy), wz,
                 1.0f, 1.0f, WALL_HEIGHT, 1.0f, 1.0f, 1.0f, 1.0f,
                 mem_f | slw, SUBTILE_EDGE, 1, sd);
        } else if (is_tree) {
            push(CCB_3D_MODE_XQUAD, CCB_3D_PICK_FG, tstr,
                 static_cast<float>(dx), static_cast<float>(dy), wz,
                 1.0f, 1.0f, TREE_HEIGHT, 1.0f, 1.0f, 1.0f, 1.0f,
                 mem_f | CCB_3D_FLAG_BASE_DROP, 0xFF, 0, sd);
        } else if (is_shrub) {
            push(CCB_3D_MODE_XQUAD, CCB_3D_PICK_FG, tstr,
                 static_cast<float>(dx) + 0.05f, static_cast<float>(dy) + 0.05f, wz,
                 0.9f, 0.9f, SHRUB_HEIGHT, 1.0f, 1.0f, 1.0f, 1.0f,
                 mem_f | CCB_3D_FLAG_BASE_DROP, 0xFF, 0, sd);
        } else if (is_panel && !empty_frame_terrain(t)) {
            const float ph = t.has_flag(ter_furn_flag::TFLAG_WINDOW) ? 0.85f : PANEL_HEIGHT;
            const float pz0 = t.has_flag(ter_furn_flag::TFLAG_WINDOW) ? 0.85f : 0.0f;
            push(CCB_3D_MODE_BOX, CCB_3D_PICK_FG, tstr,
                 static_cast<float>(dx), static_cast<float>(dy) + 0.5f - PANEL_THICK * 0.5f, wz + pz0,
                 1.0f, PANEL_THICK, ph, 1.0f, 1.0f, 1.0f, 1.0f,
                 mem_f | slw, SUBTILE_EDGE, 1, sd);
        } else if (is_fence) {
            const float fh = t.has_flag(ter_furn_flag::TFLAG_TINY) ? 0.35f : FENCE_HEIGHT;
            push(CCB_3D_MODE_LINEQUAD, CCB_3D_PICK_FG, tstr,
                 static_cast<float>(dx) + 0.5f, static_cast<float>(dy) + 0.5f, wz,
                 1.0f, fh, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f,
                 mem_f | slw, SUBTILE_EDGE, 1, sd, 0.0f, 1.0f, 0);
        }
        push_mem_furn();
        return true;
    };

    // Helper for collecting dynamic 3D lights on visible tiles
    auto collect_light_at = [&](const tripoint_bub_ms &p, float fx, float fy, float fz,
                                const ter_t &tobj, const furn_t *fobj) {
        if (out.lights.size() >= 16) return;
        float best_lum = 0.0f;
        float lr = 1.0f, lg = 0.92f, lb = 0.80f;
        if (tobj.light_emitted > 0) {
            best_lum = static_cast<float>(tobj.light_emitted);
        }
        if (fobj && fobj->light_emitted > best_lum) {
            best_lum = static_cast<float>(fobj->light_emitted);
        }
        const field &fld = here.field_at(p);
        if (fld.field_count() > 0) {
            for (const auto &fe : fld) {
                const float fl = static_cast<float>(fe.second.get_intensity_level().light_emitted);
                if (fl > best_lum) {
                    best_lum = fl;
                    if (fe.first == fd_fire) { lr = 1.0f; lg = 0.55f; lb = 0.22f; }
                }
            }
        }
        if (best_lum >= 2.0f) {
            out.lights.push_back(CcbScene3DLight{
                fx + 0.5f, fy + 0.5f, fz + 0.9f,
                std::clamp(best_lum * 0.45f + 2.5f, 3.0f, 14.0f),
                lr, lg, lb, std::clamp(best_lum * 0.08f, 0.25f, 1.6f)
            });
        }
    };

    // Add player's own active flashlight / torch light as a crisp 3D dynamic light
    const float u_light = you.active_light();
    if (u_light > 1.5f) {
        out.lights.push_back(CcbScene3DLight{
            static_cast<float>(upos.x() - center.x()) + 0.5f,
            static_cast<float>(upos.y() - center.y()) + 0.5f,
            static_cast<float>(upos.z() - cz) * LEVEL_HEIGHT + 1.25f,
            std::clamp(u_light * 0.35f + 3.0f, 4.0f, 16.0f),
            0.96f, 0.96f, 1.0f, std::clamp(u_light * 0.05f, 0.35f, 1.35f)
        });
    }

    // ---- Main Multi-Z World Gather Pass (exact CCB render3d.cpp rules!) ----
    for (int zlev = zmin; zlev <= zmax; ++zlev) {
        const int dz = zlev - cz;
        const float wz = static_cast<float>(dz) * LEVEL_HEIGHT;
        const int rad = (dz == 0) ? VIEW_RADIUS : REGION_RADIUS;
        const level_cache &cache = here.get_cache_ref(zlev);
        const bool stale_lower = (dz < 0 && zlev < lowest_vis_z);

        // Coarse skip completely empty/unseen non-view Z-levels
        if (dz != 0) {
            const int x0 = std::max(0, center.x() - rad);
            const int x1 = std::min(MAPSIZE_X - 1, center.x() + rad);
            const int y0 = std::max(0, center.y() - rad);
            const int y1 = std::min(MAPSIZE_Y - 1, center.y() + rad);
            bool any_activity = false;
            if (!stale_lower) {
                for (int y = y0; y <= y1 && !any_activity; ++y) {
                    for (int x = x0; x <= x1; ++x) {
                        if (dz > 0) {
                            if (cache.seen_cache[x][y] > 0.0f || cache.camera_cache[x][y] > 0.0f ||
                                cache.floor_blocked_seen_cache[x][y] > 0.0f) {
                                any_activity = true;
                                break;
                            }
                        } else {
                            const lit_level ll = cache.visibility_cache[x][y];
                            if ((cache.seen_cache[x][y] > 0.0f || cache.camera_cache[x][y] > 0.0f) &&
                                (ll == lit_level::LOW || ll == lit_level::LIT || ll == lit_level::BRIGHT)) {
                                any_activity = true;
                                break;
                            }
                        }
                    }
                }
            }
            if (!any_activity && !you.has_map_memory_in_region(
                    here.get_abs(tripoint_bub_ms(x0, y0, zlev)),
                    here.get_abs(tripoint_bub_ms(x1, y1, zlev)))) {
                continue;
            }
        }

        for (int dy = -rad; dy <= rad; ++dy) {
            for (int dx = -rad; dx <= rad; ++dx) {
                if (static_cast<int>(out.items.size()) >= MAX_SCENE_ITEMS - 16) {
                    break;
                }
                const tripoint_bub_ms p(center.x() + dx, center.y() + dy, zlev);
                if (!here.inbounds(p)) {
                    continue;
                }

                const bool wall_candidate = (dz > 0) && (cache.floor_blocked_seen_cache[p.x()][p.y()] > 0.0f);
                lit_level ll = lit_level::BLANK;
                if (!stale_lower) {
                    if (dz > 0) {
                        ll = upper_lit_at(cache, p);
                    } else if (dz < 0) {
                        if (cache.seen_cache[p.x()][p.y()] > 0.0f || cache.camera_cache[p.x()][p.y()] > 0.0f) {
                            ll = cache.visibility_cache[p.x()][p.y()];
                        }
                    } else {
                        ll = cache.visibility_cache[p.x()][p.y()];
                    }
                }
                const bool visible = (ll == lit_level::LOW || ll == lit_level::LIT || ll == lit_level::BRIGHT);
                const bool seen = (cache.seen_cache[p.x()][p.y()] > 0.0f);
                const bool in_dh = (std::abs(dx) <= REGION_RADIUS && std::abs(dy) <= REGION_RADIUS) &&
                                   dollhouse[static_cast<size_t>((dy + REGION_RADIUS) * REGION_SIZE + (dx + REGION_RADIUS))];

                if (!visible && !wall_candidate) {
                    if (dz == 0) {
                        if (!gather_memory_tile(p, dx, dy, wz, true, true) &&
                            std::max(std::abs(dx), std::abs(dy)) <= REGION_RADIUS) {
                            push_fog_slab(dx, dy, wz);
                        }
                    } else if (!(dz > 0 && in_dh)) {
                        gather_memory_tile(p, dx, dy, wz, dz < 0, false);
                    }
                    continue;
                }

                bool ghost = (dz > 0) && in_dh;
                const bool roof_unseen = (dz > 0) && !seen;
                const maptile mt = here.maptile_at(p);
                const ter_id tid = mt.get_ter();
                const furn_id fid = mt.get_furn();
                if (tid == t_null) {
                    continue;
                }

                bool wall_only = wall_candidate && !visible && here.has_wall_surface(p);
                if (wall_only) {
                    ll = here.apparent_light_on_wall_at(p, vis_vars);
                    wall_only = (ll == lit_level::LOW || ll == lit_level::LIT || ll == lit_level::BRIGHT);
                    if (wall_only) {
                        ghost = false;
                    }
                }
                if (!visible && !wall_only) {
                    if (!(dz > 0 && in_dh)) {
                        gather_memory_tile(p, dx, dy, wz, dz < 0, false);
                    }
                    continue;
                }

                const optional_vpart_position ovp = here.veh_at(p);
                const ter_t &t = tid.obj();
                const furn_t *fobj = (fid != furn_str_id::NULL_ID()) ? &fid.obj() : nullptr;
                const bool open_air = t.has_flag(ter_furn_flag::TFLAG_NO_FLOOR) && (fobj == nullptr);
                if (open_air && !ovp) {
                    continue;
                }

                if (dz == 0 && !wall_only) {
                    collect_light_at(p, static_cast<float>(dx), static_cast<float>(dy), wz, t, fobj);
                }

                const TileTone tone = tone_for(cache, p, ll, wall_only);
                const uint16_t sd = tile_seed(p);
                const uint32_t ghost_f = ghost ? CCB_3D_FLAG_GHOST : 0u;
                const uint32_t slw_f = (dz == 0) ? CCB_3D_FLAG_SAME_LEVEL_WALL : 0u;
                const uint32_t base_f = CCB_3D_FLAG_TEXTURED | ghost_f;

                const bool is_tree = t.has_flag(ter_furn_flag::TFLAG_TREE);
                const bool is_shrub = t.has_flag(ter_furn_flag::TFLAG_SHRUB);
                const bool is_opening = wall_opening(t);
                const bool is_panel = door_or_window(t) || is_opening;
                const bool is_empty_frame = is_panel && empty_frame_terrain(t);
                const bool is_fence = !is_panel && t.has_flag(ter_furn_flag::TFLAG_THIN_OBSTACLE);
                const bool is_flat_utility = is_fence && flat_utility_terrain(t, p.z());
                const bool is_upright_eq = upright_equipment_terrain(t);
                const bool is_wall = !is_tree && !is_shrub && !is_panel && !is_fence && !is_upright_eq && (t.movecost == 0);
                const bool plain_floor = !open_air && !is_tree && !is_shrub && !is_panel && !is_fence && !is_wall && !is_upright_eq;
                const bool shaped = plain_floor || is_flat_utility || is_upright_eq;

                const uint8_t wall_conn = (is_panel || (is_fence && !is_flat_utility))
                    ? here.get_known_connections(p, t.connect_to_groups, {}, dz > 0)
                    : 0u;
                const bool ew_line = (wall_conn & 0x06u) != 0;

                int sub = 0, rot = 0;
                if (shaped) {
                    compute_ter_sub_rot(here, p, t, sub, rot);
                } else if (is_wall || (is_fence && !is_flat_utility) || is_panel) {
                    sub = SUBTILE_EDGE;
                    rot = (is_panel && !ew_line) ? 0 : 1;
                }

                const uint16_t tstr = intern.intern(t.id.str());
                const bool is_window_panel = t.has_flag(ter_furn_flag::TFLAG_WINDOW) && !t.has_flag(ter_furn_flag::TFLAG_DOOR);
                const bool layered_ter = is_panel && !is_empty_frame && !is_opening && wants_layered_face(t);

                // 1. Floor slab (thick 0.1m slab slightly below level base to avoid z-fighting)
                if (!wall_only && !open_air && !is_empty_frame && !skip_untextured_terrain_surface(t) &&
                    ((dz <= 0 && !is_flat_utility) || plain_floor || is_panel)) {
                    const uint16_t gstr = (is_panel) ? str_t_floor : tstr;
                    const uint8_t gpick = plain_floor ? CCB_3D_PICK_GROUND : (is_panel ? CCB_3D_PICK_GROUND : CCB_3D_PICK_BG);
                    const uint8_t gsub = is_panel ? 0xFF : static_cast<uint8_t>(shaped ? sub : 0xFF);
                    const uint8_t grot = is_panel ? 0 : static_cast<uint8_t>(shaped ? rot : 0);
                    push(CCB_3D_MODE_BOX, gpick, gstr,
                         static_cast<float>(dx), static_cast<float>(dy), wz - FLOOR_THICK - 0.001f,
                         1.0f, 1.0f, FLOOR_THICK,
                         tone.shade, tone.shade, tone.shade, tone.sat,
                         base_f | CCB_3D_FLAG_NO_DISCARD, gsub, grot, sd);
                    // Plain floor fg overlay (e.g., road edge trim, water shore, grass tufts over bg)
                    if (plain_floor && !roof_unseen && !ghost) {
                        push(CCB_3D_MODE_FLATQUAD, CCB_3D_PICK_FG, tstr,
                             static_cast<float>(dx), static_cast<float>(dy), wz + 0.003f,
                             1.0f, 1.0f, 1.0f,
                             tone.shade, tone.shade, tone.shade, tone.sat,
                             base_f, static_cast<uint8_t>(sub), static_cast<uint8_t>(rot), sd);
                    }
                }

                // Upper-floor dollhouse ghost columns show ONLY their translucent roof slab
                if (ghost && !wall_only) {
                    continue;
                }

                // Helper: find clamping wall sprite along a door/window run (exact CCB panel_run_end)
                auto find_clamp_wall_str = [&]() -> uint16_t {
                    auto live_ter_at = [&](const tripoint_bub_ms &q) -> const ter_t * {
                        const ter_id nt = here.ter(q);
                        return nt ? &nt.obj() : nullptr;
                    };
                    const point step = ew_line ? point::east : point::north;
                    for (int dir : {1, -1}) {
                        tripoint_bub_ms wp;
                        if (const ter_t *wt = panel_run_end(p, step * dir, live_ter_at, wp)) {
                            return intern.intern(wt->id.str());
                        }
                    }
                    return 0;
                };

                // 2. Terrain vertical objects (trees, shrubs, doors/windows, fences, solid walls)
                if (is_tree && !roof_unseen) {
                    push(CCB_3D_MODE_XQUAD, CCB_3D_PICK_FG, tstr,
                         static_cast<float>(dx), static_cast<float>(dy), wz,
                         1.0f, 1.0f, TREE_HEIGHT,
                         tone.shade, tone.shade, tone.shade, tone.sat,
                         base_f | CCB_3D_FLAG_BASE_DROP, 0xFF, 0, sd);
                } else if (is_shrub && !roof_unseen) {
                    push(CCB_3D_MODE_XQUAD, CCB_3D_PICK_FG, tstr,
                         static_cast<float>(dx) + 0.05f, static_cast<float>(dy) + 0.05f, wz,
                         0.9f, 0.9f, SHRUB_HEIGHT,
                         tone.shade, tone.shade, tone.shade, tone.sat,
                         base_f | CCB_3D_FLAG_BASE_DROP, 0xFF, 0, sd);
                } else if (is_panel) {
                    const float px = ew_line ? static_cast<float>(dx) : (static_cast<float>(dx) + 0.5f - PANEL_THICK * 0.5f);
                    const float py = ew_line ? (static_cast<float>(dy) + 0.5f - PANEL_THICK * 0.5f) : static_cast<float>(dy);
                    const float psx = ew_line ? 1.0f : PANEL_THICK;
                    const float psy = ew_line ? PANEL_THICK : 1.0f;
                    const uint16_t wstr = find_clamp_wall_str();
                    const uint8_t face_pick = layered_ter ? CCB_3D_PICK_BG : CCB_3D_PICK_FG;
                    if (is_window_panel) {
                        constexpr float SILL_H = 0.85f;
                        if (!is_empty_frame) {
                            push(CCB_3D_MODE_BOX, face_pick, tstr, px, py, wz + SILL_H, psx, psy, SILL_H,
                                 tone.shade, tone.shade, tone.shade, tone.sat,
                                 base_f | slw_f, SUBTILE_EDGE, static_cast<uint8_t>(rot), sd);
                        }
                        if (wstr != 0) {
                            // Sill (0 .. SILL_H) and lintel (2*SILL_H .. WALL_HEIGHT) sliced vertically from wall sprite
                            push(CCB_3D_MODE_BOX, CCB_3D_PICK_FG, wstr,
                                 static_cast<float>(dx), static_cast<float>(dy), wz,
                                 1.0f, 1.0f, SILL_H,
                                 tone.shade, tone.shade, tone.shade, tone.sat,
                                 base_f | slw_f, SUBTILE_EDGE, 1, sd,
                                 1.0f - (SILL_H / WALL_HEIGHT), 1.0f);
                            push(CCB_3D_MODE_BOX, CCB_3D_PICK_FG, wstr,
                                 static_cast<float>(dx), static_cast<float>(dy), wz + SILL_H * 2.0f,
                                 1.0f, 1.0f, WALL_HEIGHT - SILL_H * 2.0f,
                                 tone.shade, tone.shade, tone.shade, tone.sat,
                                 base_f | slw_f, SUBTILE_EDGE, 1, sd,
                                 0.0f, 1.0f - (SILL_H * 2.0f / WALL_HEIGHT));
                        }
                    } else {
                        if (!is_empty_frame) {
                            push(CCB_3D_MODE_BOX, face_pick, tstr, px, py, wz, psx, psy, PANEL_HEIGHT,
                                 tone.shade, tone.shade, tone.shade, tone.sat,
                                 base_f | slw_f, SUBTILE_EDGE, static_cast<uint8_t>(rot), sd);
                        }
                        if (wstr != 0) {
                            push(CCB_3D_MODE_BOX, CCB_3D_PICK_FG, wstr,
                                 static_cast<float>(dx), static_cast<float>(dy), wz + PANEL_HEIGHT,
                                 1.0f, 1.0f, WALL_HEIGHT - PANEL_HEIGHT,
                                 tone.shade, tone.shade, tone.shade, tone.sat,
                                 base_f | slw_f, SUBTILE_EDGE, 1, sd,
                                 0.0f, 1.0f - (PANEL_HEIGHT / WALL_HEIGHT));
                        }
                    }
                } else if (is_upright_eq && !roof_unseen) {
                    push(CCB_3D_MODE_BILLBOARD_SNAP, CCB_3D_PICK_FG, tstr,
                         static_cast<float>(dx) + 0.5f, static_cast<float>(dy) + 0.5f, wz,
                         1.0f, FENCE_HEIGHT, 0.0f,
                         tone.shade, tone.shade, tone.shade, tone.sat,
                         base_f | CCB_3D_FLAG_BASE_DROP, static_cast<uint8_t>(sub), static_cast<uint8_t>(rot), sd);
                } else if (is_flat_utility) {
                    push(CCB_3D_MODE_FLATQUAD, CCB_3D_PICK_FG, tstr,
                         static_cast<float>(dx), static_cast<float>(dy), wz + 0.006f,
                         1.0f, 1.0f, 1.0f,
                         tone.shade, tone.shade, tone.shade, tone.sat,
                         base_f, static_cast<uint8_t>(sub), static_cast<uint8_t>(rot), sd);
                } else if (is_fence) {
                    const float fh = t.has_flag(ter_furn_flag::TFLAG_TINY) ? 0.35f : FENCE_HEIGHT;
                    const bool cn = (wall_conn & 8u) != 0;
                    const bool cs = (wall_conn & 1u) != 0;
                    const bool ce = (wall_conn & 2u) != 0;
                    const bool cw = (wall_conn & 4u) != 0;
                    const bool straight = (cn && cs && !ce && !cw) || (ce && cw && !cn && !cs);
                    if (straight || (!cn && !cs && !ce && !cw)) {
                        push(CCB_3D_MODE_LINEQUAD, CCB_3D_PICK_FG, tstr,
                             static_cast<float>(dx) + 0.5f, static_cast<float>(dy) + 0.5f, wz,
                             1.0f, fh, 1.0f,
                             tone.shade, tone.shade, tone.shade, tone.sat,
                             base_f | slw_f, SUBTILE_EDGE, 1, sd, 0.0f, 1.0f, ew_line ? 0 : 1000);
                    } else {
                        const float fcx = static_cast<float>(dx) + 0.5f;
                        const float fcy = static_cast<float>(dy) + 0.5f;
                        const uint32_t hf = base_f | slw_f | CCB_3D_FLAG_HALF_U;
                        if (cn) push(CCB_3D_MODE_LINEQUAD, CCB_3D_PICK_FG, tstr, fcx, fcy - 0.25f, wz, 0.5f, fh, 1.0f, tone.shade, tone.shade, tone.shade, tone.sat, hf, SUBTILE_EDGE, 1, sd, 0.0f, 1.0f, 1000);
                        if (cs) push(CCB_3D_MODE_LINEQUAD, CCB_3D_PICK_FG, tstr, fcx, fcy + 0.25f, wz, 0.5f, fh, 1.0f, tone.shade, tone.shade, tone.shade, tone.sat, hf, SUBTILE_EDGE, 1, sd, 0.0f, 1.0f, 1000);
                        if (ce) push(CCB_3D_MODE_LINEQUAD, CCB_3D_PICK_FG, tstr, fcx + 0.25f, fcy, wz, 0.5f, fh, 1.0f, tone.shade, tone.shade, tone.shade, tone.sat, hf, SUBTILE_EDGE, 1, sd, 0.0f, 1.0f, 0);
                        if (cw) push(CCB_3D_MODE_LINEQUAD, CCB_3D_PICK_FG, tstr, fcx - 0.25f, fcy, wz, 0.5f, fh, 1.0f, tone.shade, tone.shade, tone.shade, tone.sat, hf, SUBTILE_EDGE, 1, sd, 0.0f, 1.0f, 0);
                    }
                } else if (is_wall) {
                    push(CCB_3D_MODE_BOX, CCB_3D_PICK_FG, tstr,
                         static_cast<float>(dx), static_cast<float>(dy), wz,
                         1.0f, 1.0f, WALL_HEIGHT,
                         tone.shade, tone.shade, tone.shade, tone.sat,
                         base_f | slw_f, SUBTILE_EDGE, 1, sd);
                }

                if (wall_only) {
                    continue;
                }

                // 3. Fields (liquid/solid traces -> flat ground decals; gas/plasma -> camera billboards)
                const field &fld_here = mt.get_field();
                if (fld_here.field_count() > 0) {
                    int ordinal = 0;
                    for (const auto &fd_pr : fld_here) {
                        const field_type_id &fdid = fd_pr.first;
                        const field_type &ft = fdid.obj();
                        if (!ft.display_field) {
                            ++ordinal;
                            continue;
                        }
                        const int f_int = std::clamp(fd_pr.second.get_field_intensity(), 1, 3);
                        const uint16_t fd_str = intern.intern(fdid.id().str());
                        const phase_id ph = field_render_phase(fdid);
                        const bool riser = (ph == phase_id::GAS || ph == phase_id::PLASMA);

                        auto nb_fd = [&](const tripoint_bub_ms &q) -> int {
                            if (!here.inbounds(q)) return 0;
                            return here.field_at(q).find_field(fdid) != nullptr ? fdid.to_i() : 0;
                        };
                        const std::array<int, 4> fnb = {
                            nb_fd(p + point::south), nb_fd(p + point::east),
                            nb_fd(p + point::west),  nb_fd(p + point::north)
                        };
                        int fsub = 0, frot = 0;
                        map::get_tile_values(fdid.to_i(), fnb, fsub, frot, 0);
                        const uint8_t packed_sub = static_cast<uint8_t>((std::clamp(fsub, 0, 7) & 0x0F) | ((f_int & 0x0F) << 4));

                        if (riser) {
                            push(CCB_3D_MODE_BILLBOARD, CCB_3D_PICK_FIELD, fd_str,
                                 static_cast<float>(dx) + 0.5f, static_cast<float>(dy) + 0.5f, wz + 0.01f,
                                 1.0f, FIELD_RISER_HEIGHT, FIELD_RISER_OFFSET * static_cast<float>(ordinal % 4),
                                 tone.shade, tone.shade, tone.shade, tone.sat,
                                 base_f | CCB_3D_FLAG_DITHER_ALPHA | CCB_3D_FLAG_ASPECT_WIDTH,
                                 packed_sub, static_cast<uint8_t>(frot & 15), sd);
                        } else {
                            push(CCB_3D_MODE_FLATQUAD, CCB_3D_PICK_FIELD, fd_str,
                                 static_cast<float>(dx), static_cast<float>(dy),
                                 wz + FIELD_DECAL_Z + FIELD_DECAL_STAGGER * static_cast<float>(ordinal % 8),
                                 1.0f, 1.0f, 1.0f,
                                 tone.shade, tone.shade, tone.shade, tone.sat,
                                 base_f | CCB_3D_FLAG_DITHER_ALPHA,
                                 packed_sub, static_cast<uint8_t>(frot & 15), sd);
                        }
                        ++ordinal;
                    }
                }

                // 4. Furniture (cardinal-snapped billboards or flat mats)
                if (!roof_unseen && fobj != nullptr) {
                    const uint16_t fstr = intern.intern(fobj->id.str());
                    int fsub = 0, frot = 0;
                    if (fobj->connect_to_groups.any()) {
                        map::get_furn_connect_values(p, fsub, frot, fobj->connect_to_groups, fobj->rotate_to_groups, {});
                    } else {
                        const std::array<int, 4> fn = {
                            static_cast<int>(here.furn(p + point::south)),
                            static_cast<int>(here.furn(p + point::east)),
                            static_cast<int>(here.furn(p + point::west)),
                            static_cast<int>(here.furn(p + point::north))
                        };
                        map::get_tile_values_with_ter(p, fid.to_i(), fn, fsub, frot, fobj->rotate_to_groups);
                    }
                    fsub = std::clamp(fsub, 0, 7);
                    const bool layered_f = wants_layered_face(*fobj);
                    if (flat_furniture(*fobj)) {
                        push(CCB_3D_MODE_FLATQUAD_DECAL, CCB_3D_PICK_FG, fstr,
                             static_cast<float>(dx), static_cast<float>(dy), wz + 0.004f,
                             1.0f, 1.0f, 1.0f,
                             tone.shade, tone.shade, tone.shade, tone.sat,
                             base_f, static_cast<uint8_t>(fsub), static_cast<uint8_t>(frot & 15), sd);
                    } else {
                        push(CCB_3D_MODE_BILLBOARD_SNAP, layered_f ? CCB_3D_PICK_BG : CCB_3D_PICK_FG, fstr,
                             static_cast<float>(dx) + 0.5f, static_cast<float>(dy) + 0.5f, wz,
                             1.0f, FURN_QUAD_HEIGHT, 0.0f,
                             tone.shade, tone.shade, tone.shade, tone.sat,
                             base_f | CCB_3D_FLAG_BASE_DROP | CCB_3D_FLAG_ASPECT_WIDTH,
                             static_cast<uint8_t>(fsub), static_cast<uint8_t>(frot & 15), sd);
                        if (layered_f) {
                            push(CCB_3D_MODE_BILLBOARD_SNAP, CCB_3D_PICK_FG, fstr,
                                 static_cast<float>(dx) + 0.5f, static_cast<float>(dy) + 0.5f, wz,
                                 1.0f, FURN_QUAD_HEIGHT, 0.02f,
                                 tone.shade, tone.shade, tone.shade, tone.sat,
                                 base_f | CCB_3D_FLAG_BASE_DROP | CCB_3D_FLAG_ASPECT_WIDTH,
                                 static_cast<uint8_t>(fsub), static_cast<uint8_t>(frot & 15), sd);
                        }
                    }
                }

                // 5. Traps (visible floor decals)
                if (!roof_unseen) {
                    const trap &tr = here.tr_at(p);
                    if (!tr.is_null() && tr.can_see(p, you)) {
                        const uint16_t tr_str = intern.intern(tr.id.str());
                        push(CCB_3D_MODE_FLATQUAD, CCB_3D_PICK_FG, tr_str,
                             static_cast<float>(dx), static_cast<float>(dy), wz + 0.005f,
                             1.0f, 1.0f, 1.0f,
                             tone.shade, tone.shade, tone.shade, tone.sat,
                             base_f, 0xFF, 0, sd);
                    }
                }

                // 6. Ground items (camera billboard + highlight_item backdrop)
                if (!roof_unseen && mt.get_item_count() > 0 && here.sees_some_items(p, you)) {
                    const item &itm = mt.get_uppermost_item();
                    std::string istr_s = itm.typeId().str();
                    if (itm.is_corpse()) {
                        if (const mtype *mm = itm.get_mtype()) {
                            istr_s = "corpse_" + mm->id.str();
                        }
                    }
                    const uint16_t istr = intern.intern(istr_s);
                    push(CCB_3D_MODE_BILLBOARD, CCB_3D_PICK_FG, str_highlight_item,
                         static_cast<float>(dx) + 0.5f, static_cast<float>(dy) + 0.5f, wz + 0.02f,
                         1.35f, ITEM_HEIGHT * 1.35f, 0.03f,
                         tone.shade, tone.shade, tone.shade, tone.sat,
                         base_f | CCB_3D_FLAG_ASPECT_WIDTH, 0xFF, 0, sd);
                    push(CCB_3D_MODE_BILLBOARD, CCB_3D_PICK_FG, istr,
                         static_cast<float>(dx) + 0.5f, static_cast<float>(dy) + 0.5f, wz + 0.02f,
                         1.0f, ITEM_HEIGHT, 0.06f,
                         tone.shade, tone.shade, tone.shade, tone.sat,
                         base_f | CCB_3D_FLAG_BASE_DROP | CCB_3D_FLAG_ASPECT_WIDTH, 0xFF, 0, sd);
                }

                // 7. Vehicles (exact CCB proximity-hide shell rule + 3D voxel hull/roof/side-panels!)
                if (!roof_unseen && ovp) {
                    const vehicle &veh = ovp->vehicle();
                    const point_rel_ms mount = ovp->mount_pos();
                    const vpart_display vd = veh.get_display_of_tile(ovp->mount_pos3());
                    if (!vd.id.is_null()) {
                        std::string vname = vd.get_tileset_id();
                        if (vname.empty()) vname = "vp_" + vd.id.str();
                        const uint16_t vstr = intern.intern(vname);
                        const uint8_t vsub = vd.is_open ? 6u : (vd.is_broken ? 7u : 0u);
                        const uint8_t vrota = static_cast<uint8_t>(angle_to_dir4_3d(veh.face.dir() - 270_degrees));

                        bool near_hide = false;
                        auto hit = veh_shell_hidden.find(&veh);
                        if (hit != veh_shell_hidden.end()) {
                            near_hide = hit->second;
                        } else {
                            for (int pi = 0; pi < veh.part_count() && !near_hide; ++pi) {
                                if (veh.part(pi).removed) continue;
                                const tripoint_bub_ms pp = veh.bub_part_pos(here, pi);
                                if (pp.z() == upos.z() &&
                                    std::hypot(static_cast<float>(pp.x() - upos.x()),
                                               static_cast<float>(pp.y() - upos.y())) < VEH_PROX_HIDE_DIST) {
                                    near_hide = true;
                                }
                            }
                            veh_shell_hidden[&veh] = near_hide;
                        }

                        if (near_hide) {
                            // Near player (<5m): show unobstructed flat 2D skin decal
                            push(CCB_3D_MODE_FLATQUAD_DECAL, CCB_3D_PICK_BG, vstr,
                                 static_cast<float>(dx), static_cast<float>(dy), wz + VEH_DECAL_Z,
                                 1.0f, 1.0f, 1.0f, tone.shade, tone.shade, tone.shade, tone.sat,
                                 base_f | CCB_3D_FLAG_VEH_FOOTPRINT, vsub, vrota, sd);
                            push(CCB_3D_MODE_FLATQUAD_DECAL, CCB_3D_PICK_FG, vstr,
                                 static_cast<float>(dx), static_cast<float>(dy), wz + VEH_DECAL_Z + 0.001f,
                                 1.0f, 1.0f, 1.0f, tone.shade, tone.shade, tone.shade, tone.sat,
                                 base_f | CCB_3D_FLAG_VEH_FOOTPRINT, vsub, vrota, sd);
                        } else {
                            // Far (>5m): 3D hull volume + textured top deck + exterior flank panels!
                            bool row_roof = false;
                            for (int rdy = -10; rdy <= 10 && !row_roof; ++rdy) {
                                for (const int rpi : veh.parts_at_relative(mount + point_rel_ms(0, rdy), true, false)) {
                                    const vehicle_part &rp = veh.part(rpi);
                                    if (!rp.removed && rp.info().has_flag(VPFLAG_ROOF)) {
                                        row_roof = true;
                                        break;
                                    }
                                }
                            }
                            const bool is_windshield = vd.id.is_valid() && vd.id->has_flag(VPFLAG_WINDOW);
                            const bool is_door = vd.id.is_valid() && vd.id->has_flag("DOOR");
                            const float hull_h = row_roof ? VEH_ROOF_Z
                                               : (is_windshield || is_door ? VEH_BODY_BASE + VEH_BODY_PER_SPILL * 0.55f
                                                                           : VEH_BODY_BASE + 0.15f);
                            // 3D vehicle body box
                            push(CCB_3D_MODE_BOX, CCB_3D_PICK_GROUND, vstr,
                                 static_cast<float>(dx), static_cast<float>(dy), wz + 0.08f,
                                 1.0f, 1.0f, std::max(0.25f, hull_h - 0.08f),
                                 tone.shade * 0.92f, tone.shade * 0.94f, tone.shade * 0.96f, tone.sat,
                                 base_f, vsub, vrota, sd);
                            // Top deck / roof decal
                            push(CCB_3D_MODE_FLATQUAD_DECAL, CCB_3D_PICK_FG, vstr,
                                 static_cast<float>(dx), static_cast<float>(dy), wz + hull_h + 0.004f,
                                 1.0f, 1.0f, 1.0f, tone.shade, tone.shade, tone.shade, tone.sat,
                                 base_f, vsub, vrota, sd);
                        }
                    }
                }
            }
        }
    }

    // ---- Creatures + Player/NPC Paperdoll Overlays (exact CCB render3d.cpp lines 5200-5360) ----
    creature_tracker &tracker = get_creature_tracker();
    std::vector<tripoint_bub_ms> creature_positions;
    {
        std::unordered_set<tripoint_bub_ms> seen_pos;
        for (const Creature &candidate : g->all_creatures()) {
            const tripoint_bub_ms p = candidate.pos_bub(here);
            const int dz = p.z() - cz;
            const int dx = p.x() - center.x();
            const int dy = p.y() - center.y();
            if (p.z() < zmin || p.z() > zmax || std::abs(dx) > VIEW_RADIUS || std::abs(dy) > VIEW_RADIUS || !here.inbounds(p)) {
                continue;
            }
            if (dz != 0 && (std::abs(dx) > REGION_RADIUS || std::abs(dy) > REGION_RADIUS)) {
                continue;
            }
            if (dz < 0 && p.z() < lowest_vis_z) {
                continue;
            }
            if (dz > 0 && std::abs(dx) <= REGION_RADIUS && std::abs(dy) <= REGION_RADIUS &&
                dollhouse[static_cast<size_t>((dy + REGION_RADIUS) * REGION_SIZE + (dx + REGION_RADIUS))]) {
                continue;
            }
            if (seen_pos.insert(p).second) {
                creature_positions.push_back(p);
            }
        }
    }
    std::sort(creature_positions.begin(), creature_positions.end(),
              [](const tripoint_bub_ms &a, const tripoint_bub_ms &b) {
                  if (a.z() != b.z()) return a.z() < b.z();
                  if (a.y() != b.y()) return a.y() < b.y();
                  return a.x() < b.x();
              });

    for (const tripoint_bub_ms &p : creature_positions) {
        const Creature *critter = tracker.creature_at(p);
        if (!critter) continue;
        const bool is_player = (critter == &you);
        if (!is_player && !you.sees(here, *critter)) continue;

        const int dz = p.z() - cz;
        const float dx = static_cast<float>(p.x() - center.x());
        const float dy = static_cast<float>(p.y() - center.y());
        const float wz = static_cast<float>(dz) * LEVEL_HEIGHT;
        const level_cache &cache = here.get_cache_ref(p.z());
        const lit_level cll = (dz > 0) ? upper_lit_at(cache, p) : cache.visibility_cache[p.x()][p.y()];
        const bool cll_clear = (cll == lit_level::LOW || cll == lit_level::LIT || cll == lit_level::BRIGHT);
        const TileTone tone = cll_clear ? tone_for(cache, p, cll) : TileTone{1.0f, nv_tint ? 0.0f : 1.0f};
        const uint16_t sd = tile_seed(p);

        uint32_t rel_flag = CCB_3D_FLAG_CREATURE_NEUTRAL;
        if (!is_player) {
            switch (critter->attitude_to(you)) {
                case Creature::Attitude::HOSTILE:  rel_flag = CCB_3D_FLAG_CREATURE_HOSTILE;  break;
                case Creature::Attitude::FRIENDLY: rel_flag = CCB_3D_FLAG_CREATURE_FRIENDLY; break;
                default:                           rel_flag = CCB_3D_FLAG_CREATURE_NEUTRAL;  break;
            }
        } else {
            rel_flag = 0u; // Player does not get an enemy/ally silhouette box
        }

        const Character *ch_ptr = critter->as_character();
        const bool is_male = ch_ptr ? ch_ptr->get_gender() : true;
        const float size_sc = creature_size_scale(critter->get_size()) * (ch_ptr ? CHARACTER_SIZE_SCALE : 1.0f);
        const float ch_h = CREATURE_BASE_HEIGHT * size_sc;

        std::string sprite_id;
        if (is_player) {
            sprite_id = is_male ? "player_male" : "player_female";
        } else if (const monster *mon = critter->as_monster()) {
            sprite_id = mon->type->id.str();
        } else if (ch_ptr) {
            sprite_id = is_male ? "npc_male" : "npc_female";
        }
        const uint16_t cstr = intern.intern(sprite_id);
        const uint32_t cf = CCB_3D_FLAG_TEXTURED | CCB_3D_FLAG_BASE_DROP | CCB_3D_FLAG_ASPECT_WIDTH |
                            rel_flag | (ch_ptr ? CCB_3D_FLAG_PAPERDOLL_BODY : 0u) |
                            (is_male ? CCB_3D_FLAG_MALE : 0u);
        push(CCB_3D_MODE_BILLBOARD, CCB_3D_PICK_FG, cstr,
             dx + 0.5f, dy + 0.5f, wz,
             1.0f, ch_h, 0.0f,
             tone.shade, tone.shade, tone.shade, tone.sat, cf, 0xFF, 0, sd);

        // Paperdoll worn & wielded overlays for Player and NPCs (aligned to preceding body sprite!)
        if (ch_ptr) {
            int layer = 0;
            const uint32_t of = CCB_3D_FLAG_TEXTURED | CCB_3D_FLAG_PAPERDOLL_LAYER | rel_flag |
                                (is_male ? CCB_3D_FLAG_MALE : 0u);
            if (is_player) {
                for (const item_location &loc : you.worn.get_visible_worn_items(you)) {
                    if (!loc || layer >= 12) break;
                    ++layer;
                    const uint16_t ostr = intern.intern("overlay_worn_" + loc->typeId().str());
                    push(CCB_3D_MODE_BILLBOARD, CCB_3D_PICK_OVERLAY, ostr,
                         dx + 0.5f, dy + 0.5f, wz,
                         1.0f, ch_h, 0.004f * static_cast<float>(layer),
                         tone.shade, tone.shade, tone.shade, tone.sat, of, 0xFF, 0, sd,
                         0.0f, 1.0f, static_cast<int16_t>(layer));
                }
            } else {
                std::vector<const item *> npc_worn;
                ch_ptr->worn.inv_dump(npc_worn);
                for (const item *wit : npc_worn) {
                    if (!wit || layer >= 6) break;
                    ++layer;
                    const uint16_t ostr = intern.intern("overlay_worn_" + wit->typeId().str());
                    push(CCB_3D_MODE_BILLBOARD, CCB_3D_PICK_OVERLAY, ostr,
                         dx + 0.5f, dy + 0.5f, wz,
                         1.0f, ch_h, 0.004f * static_cast<float>(layer),
                         tone.shade, tone.shade, tone.shade, tone.sat, of, 0xFF, 0, sd,
                         0.0f, 1.0f, static_cast<int16_t>(layer));
                }
            }
            if (const item_location wld = ch_ptr->get_wielded_item()) {
                ++layer;
                const uint16_t ostr = intern.intern("overlay_wielded_" + wld->typeId().str());
                push(CCB_3D_MODE_BILLBOARD, CCB_3D_PICK_OVERLAY, ostr,
                     dx + 0.5f, dy + 0.5f, wz,
                     1.0f, ch_h, 0.004f * static_cast<float>(layer),
                     tone.shade, tone.shade, tone.shade, tone.sat, of, 0xFF, 0, sd,
                     0.0f, 1.0f, static_cast<int16_t>(layer));
            }
        }
    }

    // ---- Game-driven cursors / look-around / targeting highlight from curses terrain ----
    const auto &st = state();
    if (st.work_terrain_w > 0 && st.work_terrain_h > 0 && !st.curses_layer.empty()) {
        const uint16_t str_cursor = intern.intern("cursor");
        const uint16_t str_highlight = intern.intern("highlight");
        const int pos_cx = st.work_terrain_w / 2;
        const int pos_cy = st.work_terrain_h / 2;
        const uint32_t black_rgba = st.palette_rgba(0);
        int cursor_cnt = 0;
        for (int sy_l = 0; sy_l < st.work_terrain_h && cursor_cnt < 48; ++sy_l) {
            const int sy = st.work_terrain_y + sy_l;
            if (sy < 0 || sy >= st.work_rows) continue;
            for (int sx_l = 0; sx_l < st.work_terrain_w && cursor_cnt < 48; ++sx_l) {
                const int sx = st.work_terrain_x + sx_l;
                if (sx < 0 || sx >= st.work_cols) continue;
                const CcbTermCell &tc = st.curses_layer[static_cast<size_t>(sy) * static_cast<size_t>(st.work_cols) + static_cast<size_t>(sx)];
                const int rdx = sx_l - pos_cx;
                const int rdy = sy_l - pos_cy;
                if (std::abs(rdx) > VIEW_RADIUS || std::abs(rdy) > VIEW_RADIUS) continue;
                const bool is_cur_arrow = (tc.codepoint == 0x2199u || tc.codepoint == 0x2196u ||
                                           tc.codepoint == 0x2198u || tc.codepoint == 0x2197u);
                const bool is_x_mark = (tc.codepoint == 'X' && ((tc.fg_rgba & 0xFFu) > 180u || ((tc.bg_rgba >> 8) & 0xFFu) > 110u));
                if (is_cur_arrow || is_x_mark) {
                    push(CCB_3D_MODE_BOX, CCB_3D_PICK_FG, is_x_mark ? str_highlight : str_cursor,
                         static_cast<float>(rdx), static_cast<float>(rdy), 0.004f,
                         1.0f, 1.0f, 0.06f, 1.0f, 1.0f, 1.0f, 1.0f, CCB_3D_FLAG_TEXTURED);
                    ++cursor_cnt;
                } else if (out.header.is_looking && tc.bg_rgba != black_rgba && (tc.bg_rgba & 0x00FFFFFFu) != 0u &&
                           rdx == 0 && rdy == 0) {
                    push(CCB_3D_MODE_BOX, CCB_3D_PICK_FG, str_cursor,
                         0.0f, 0.0f, 0.004f, 1.0f, 1.0f, 0.06f,
                         1.0f, 1.0f, 1.0f, 1.0f, CCB_3D_FLAG_TEXTURED);
                    ++cursor_cnt;
                }
            }
        }
    }

    out.header.item_count = static_cast<int32_t>(out.items.size());
    out.header.light_count = static_cast<int32_t>(out.lights.size());
    out.header.string_count = intern.count();
    out.header.string_bytes = static_cast<int32_t>(out.strings.size());
    out.header.valid = 1;
}

} // namespace ccb_bridge
