#include "bridge_state.hpp"

#include "avatar.h"
#include "calendar.h"
#include "character.h"
#include "color.h"
#include "coordinates.h"
#include "creature.h"
#include "creature_tracker.h"
#include "field.h"
#include "game.h"
#include "item.h"
#include "level_cache.h"
#include "lightmap.h"
#include "map.h"
#include "map_memory.h"
#include "mapdata.h"
#include "monster.h"
#include "mtype.h"
#include "npc.h"
#include "output.h"
#include "trap.h"
#include "veh_type.h"
#include "vehicle.h"
#include "vpart_position.h"
#include "weather.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <queue>
#include <unordered_map>

namespace ccb_bridge {

namespace {

class StringInterner {
public:
    StringInterner(std::vector<char> &buf, std::unordered_map<std::string, uint16_t> &map)
        : buf_(buf), map_(map) {
        buf_.clear();
        buf_.push_back('\0'); // index 0 = empty string
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

uint32_t nc_color_to_rgba(const nc_color &col) {
    const auto &st = state();
    const int idx = col.to_color_pair_index();
    short fg = 7;
    if (idx >= 0 && idx < static_cast<int>(st.color_pairs.size())) {
        fg = st.color_pairs[static_cast<size_t>(idx)].first;
    }
    if (col.is_bold() && fg >= 0 && fg < 8) {
        fg = static_cast<short>(fg + 8);
    }
    return st.palette_rgba(fg);
}

uint32_t nc_color_bg_rgba(const nc_color &col) {
    const auto &st = state();
    const int idx = col.to_color_pair_index();
    short bg = 0;
    if (idx >= 0 && idx < static_cast<int>(st.color_pairs.size())) {
        bg = st.color_pairs[static_cast<size_t>(idx)].second;
    }
    if (col.is_blink() && bg >= 0 && bg < 8) {
        bg = static_cast<short>(bg + 8);
    }
    return st.palette_rgba(bg);
}

bool tile_naturally_has_bg(map &here, const tripoint_bub_ms &p, const ter_t &tobj,
                           const furn_t *fobj, const optional_vpart_position &vp,
                           uint32_t bg_rgba, uint32_t black_rgba) {
    if (bg_rgba == black_rgba) {
        return true;
    }
    if (tobj.has_flag(ter_furn_flag::TFLAG_SWIMMABLE) ||
        tobj.has_flag(ter_furn_flag::TFLAG_SHALLOW_WATER) ||
        tobj.has_flag(ter_furn_flag::TFLAG_DEEP_WATER)) {
        return true;
    }
    // Check terrain & furniture natural color backgrounds (color() already resolves the current season!)
    if (nc_color_bg_rgba(tobj.color()) == bg_rgba) {
        return true;
    }
    if (fobj != nullptr && nc_color_bg_rgba(fobj->color()) == bg_rgba) {
        return true;
    }
    if (vp) {
        const vpart_display vd = vp->vehicle().get_display_of_tile(vp->mount_pos3());
        if (nc_color_bg_rgba(vd.color) == bg_rgba) {
            return true;
        }
    }
    const trap &tr = here.tr_at(p);
    if (!tr.is_null() && nc_color_bg_rgba(tr.color) == bg_rgba) {
        return true;
    }
    const field &fld = here.field_at(p);
    if (fld.field_count() > 0) {
        for (const auto &fe : fld) {
            if (nc_color_bg_rgba(fe.second.get_intensity_level().color) == bg_rgba) {
                return true;
            }
        }
    }
    if (here.has_items(p)) {
        for (const item &it : here.i_at(p)) {
            if (nc_color_bg_rgba(it.color()) == bg_rgba) {
                return true;
            }
        }
    }
    return false;
}

uint32_t pack_light_rgb(const light_color_rgb &lc, uint32_t fallback_rgba) {
    if (!lc.is_colored()) {
        return fallback_rgba;
    }
    const float peak = std::max({lc.r, lc.g, lc.b, 0.001f});
    const uint8_t r = static_cast<uint8_t>(std::clamp((lc.r / peak) * 255.0f, 0.0f, 255.0f));
    const uint8_t g8 = static_cast<uint8_t>(std::clamp((lc.g / peak) * 255.0f, 0.0f, 255.0f));
    const uint8_t b = static_cast<uint8_t>(std::clamp((lc.b / peak) * 255.0f, 0.0f, 255.0f));
    return static_cast<uint32_t>(r) | (static_cast<uint32_t>(g8) << 8) |
           (static_cast<uint32_t>(b) << 16) | (0xFFu << 24);
}

// Assigns authentic physical light spectra (RGB little-endian packed in uint32_t) when CCB JSON leaves light_color default
uint32_t classify_emitter_rgba(const std::string &id, const light_color_rgb &lc, uint32_t fallback_rgba) {
    if (lc.is_colored()) {
        return pack_light_rgb(lc, fallback_rgba);
    }
    if (id.find("console") != std::string::npos || id.find("computer") != std::string::npos ||
        id.find("terminal") != std::string::npos || id.find("screen") != std::string::npos) {
        return 0xFFFFDC5Cu; // Crisp cyan-blue CRT/LCD console glow (R=92, G=220, B=255)
    }
    if (id.find("plasma") != std::string::npos || id.find("electric") != std::string::npos ||
        id.find("portal") != std::string::npos || id.find("rift") != std::string::npos) {
        return 0xFFFF80A5u; // Electric violet-cyan arc (R=165, G=128, B=255)
    }
    if (id.find("shroom") != std::string::npos || id.find("fungus") != std::string::npos ||
        id.find("glowstick") != std::string::npos || id.find("atomic") != std::string::npos ||
        id.find("biolume") != std::string::npos || id.find("marloss") != std::string::npos) {
        return 0xFFAFF54Eu; // Bioluminescent emerald-teal (R=78, G=245, B=175)
    }
    if (id.find("flare") != std::string::npos || id.find("alarm") != std::string::npos ||
        id.find("emergency") != std::string::npos || id.find("laser") != std::string::npos ||
        id.find("taillight") != std::string::npos || id.find("brake") != std::string::npos) {
        return 0xFF303EFFu; // Crimson red warning/flare (R=255, G=62, B=48)
    }
    if (id.find("fire") != std::string::npos || id.find("flame") != std::string::npos ||
        id.find("brazier") != std::string::npos || id.find("stove") != std::string::npos ||
        id.find("hearth") != std::string::npos || id.find("forge") != std::string::npos ||
        id.find("kiln") != std::string::npos || id.find("lava") != std::string::npos ||
        id.find("candle") != std::string::npos || id.find("torch") != std::string::npos ||
        id.find("lighter") != std::string::npos) {
        return 0xFF348AFFu; // Warm amber-orange firelight (R=255, G=138, B=52)
    }
    if (id.find("headlight") != std::string::npos || id.find("floodlight") != std::string::npos ||
        id.find("flashlight") != std::string::npos || id.find("headlamp") != std::string::npos ||
        id.find("xenon") != std::string::npos) {
        return 0xFFFFF6EAu; // Crisp daylight-white LED/halogen beam (R=234, G=246, B=255)
    }
    if (id.find("lamp") != std::string::npos || id.find("light") != std::string::npos ||
        id.find("lantern") != std::string::npos || id.find("aisle") != std::string::npos ||
        id.find("dome") != std::string::npos) {
        return 0xFFD0ECFFu; // Warm-white incandescent bulb (R=255, G=236, B=208)
    }
    return fallback_rgba;
}

int angle_to_rot4(units::angle a) {
    const double deg = std::fmod(to_degrees(a) + 360.0, 360.0);
    return (static_cast<int>(std::lround(deg / 90.0)) + 4) & 3;
}

bool is_wall_like(const ter_t &t) {
    return t.has_flag(ter_furn_flag::TFLAG_WALL) ||
           t.has_flag(ter_furn_flag::TFLAG_DOOR) ||
           t.has_flag(ter_furn_flag::TFLAG_WINDOW);
}

// Determines whether a door/window aperture normal faces along X (east-west) vs Y (north-south)
bool compute_aperture_axis_x(const map &here, const tripoint_bub_ms &p) {
    auto wall_at = [&](int dx, int dy) -> bool {
        const tripoint_bub_ms q(p.x() + dx, p.y() + dy, p.z());
        return here.inbounds(q) && is_wall_like(here.ter(q).obj());
    };
    const int along_x = (wall_at(-1, 0) ? 1 : 0) + (wall_at(1, 0) ? 1 : 0);
    const int along_y = (wall_at(0, -1) ? 1 : 0) + (wall_at(0, 1) ? 1 : 0);
    return along_y > along_x;
}

// Classifies physical 3D geometry + bounce reflectance for cangling-city's volumetric/AO/GI pipeline
void classify_tile_lighting(
    const map &here,
    const tripoint_bub_ms &p,
    const ter_t &t,
    const furn_t *f,
    bool has_vehicle,
    int season,
    CcbWorldTile &cell)
{
    const std::string &tid = t.id.str();
    const bool transparent = t.has_flag(ter_furn_flag::TFLAG_TRANSPARENT);
    const bool is_wall = t.has_flag(ter_furn_flag::TFLAG_WALL);
    const bool is_window = t.has_flag(ter_furn_flag::TFLAG_WINDOW) || tid.find("window") != std::string::npos || tid.find("curtain") != std::string::npos;
    const bool is_door = t.has_flag(ter_furn_flag::TFLAG_DOOR) || tid.find("door") != std::string::npos;
    const bool is_tree = t.has_flag(ter_furn_flag::TFLAG_TREE) || tid.find("t_tree") == 0;
    const bool is_shrub = t.has_flag(ter_furn_flag::TFLAG_SHRUB) || tid.find("t_shrub") == 0 || tid.find("t_underbrush") == 0 || tid.find("fence") != std::string::npos;
    const bool is_puddle = (tid == "t_puddle" || tid == "t_puddle_underground");
    const bool is_water = !is_puddle && (t.has_flag(ter_furn_flag::TFLAG_SWIMMABLE) || t.has_flag(ter_furn_flag::TFLAG_SHALLOW_WATER) || t.has_flag(ter_furn_flag::TFLAG_DEEP_WATER));

    if (is_water) {
        cell.flags |= CCB_TILE_IS_WATER;
        if (t.has_flag(ter_furn_flag::TFLAG_DEEP_WATER)) {
            cell.flags |= CCB_TILE_DEEP_WATER;
        }
    }

    float height_m = 0.0f;
    uint8_t kind = CCB_LIGHT_GROUND;

    if (is_window) {
        height_m = 2.50f;
        if (!transparent) {
            // Closed curtains / boarded window acts as solid wall
            kind = CCB_LIGHT_WALL;
        } else if (tid.find("open") != std::string::npos || tid.find("empty") != std::string::npos || tid.find("frame") != std::string::npos || tid.find("broken") != std::string::npos) {
            kind = CCB_LIGHT_WIN_OPEN;
        } else {
            kind = CCB_LIGHT_WIN_CLOSED;
        }
        if (compute_aperture_axis_x(here, p)) {
            cell.flags |= CCB_TILE_APERTURE_X;
        }
    } else if (is_door) {
        height_m = 2.50f;
        if (transparent || tid.find("_o") != std::string::npos || tid.find("open") != std::string::npos) {
            kind = CCB_LIGHT_DOOR_OPEN;
        } else {
            kind = CCB_LIGHT_WALL;
        }
        if (compute_aperture_axis_x(here, p)) {
            cell.flags |= CCB_TILE_APERTURE_X;
        }
    } else if (is_wall || (!transparent && !is_tree && !is_shrub)) {
        height_m = 2.50f;
        kind = CCB_LIGHT_WALL;
    } else if (is_tree) {
        height_m = 2.45f;
        kind = CCB_LIGHT_TREE;
    } else if (is_shrub) {
        height_m = 0.90f;
        kind = CCB_LIGHT_SHRUB;
    } else if (has_vehicle) {
        height_m = 1.45f;
        kind = CCB_LIGHT_FURNITURE;
    } else if (f != nullptr) {
        const bool f_opaque = !f->has_flag(ter_furn_flag::TFLAG_TRANSPARENT);
        const bool f_flat = f->has_flag(ter_furn_flag::TFLAG_FLAT) || f->has_flag(ter_furn_flag::TFLAG_FLAT_SURF);
        if (f->has_flag(ter_furn_flag::TFLAG_SHRUB) || f->id.str().find("bush") != std::string::npos) {
            height_m = 0.72f;
            kind = CCB_LIGHT_SHRUB;
        } else if (f_opaque) {
            height_m = 1.65f;
            kind = CCB_LIGHT_FURNITURE;
        } else if (!f_flat && f->movecost > 0) {
            height_m = 0.78f;
            kind = CCB_LIGHT_FURNITURE;
        }
    }

    cell.light_kind = kind;
    cell.height_u8 = static_cast<uint8_t>(std::clamp(height_m * (255.0f / 3.0f), 0.0f, 255.0f));

    // Physical surface material ID (0..6, encoded in surface_hold_u8 as id * 36) + rich colored GI bounce albedo!
    // 0=Grass/Foliage (SSS + green bounce), 1=Wood (satin sheen + warm amber bounce),
    // 2=Metal/Vehicle/Console (colored metallic specular), 3=Glass/Window (Fresnel reflection + tinted scatter),
    // 4=Water (animated Fresnel + caustics), 5=Concrete/Brick/Stone (mineral relief + wall bounce),
    // 6=Asphalt/Dirt (dry matte -> smooth wet rain reflection!)
    const std::string fid = (f != nullptr) ? f->id.str() : std::string();
    uint8_t mat_id = 6; // default asphalt/dirt
    uint8_t mr = 148, mg = 145, mb = 140;

    const bool is_metal_furn = !fid.empty() && (
        fid.find("console") != std::string::npos ||
        fid.find("locker") != std::string::npos || fid.find("rack") != std::string::npos ||
        fid.find("fridge") != std::string::npos || fid.find("oven") != std::string::npos ||
        fid.find("stove") != std::string::npos || fid.find("safe") != std::string::npos ||
        fid.find("metal") != std::string::npos || fid.find("steel") != std::string::npos ||
        fid.find("sink") != std::string::npos || fid.find("washer") != std::string::npos ||
        fid.find("vending") != std::string::npos || fid.find("trashcan") != std::string::npos);
    const bool is_glass_item = is_window || tid.find("glass") != std::string::npos ||
                               fid.find("glass") != std::string::npos || fid.find("display") != std::string::npos;
    const bool is_metal_ter = tid.find("console") != std::string::npos || tid.find("metal") != std::string::npos ||
                              tid.find("steel") != std::string::npos || tid.find("grate") != std::string::npos ||
                              tid.find("chainfence") != std::string::npos;

    if (is_water) {
        mat_id = 4;
        mr = 48; mg = 168; mb = 208;
    } else if (has_vehicle || is_metal_furn || is_metal_ter) {
        mat_id = 2;
        if (tid.find("console") != std::string::npos || fid.find("console") != std::string::npos) {
            mr = 102; mg = 208; mb = 240;
        } else {
            mr = 152; mg = 162; mb = 174;
        }
    } else if (is_glass_item) {
        mat_id = 3;
        mr = 158; mg = 198; mb = 216;
    } else if (is_tree || is_shrub || tid.find("grass") != std::string::npos || tid.find("moss") != std::string::npos ||
               tid.find("clover") != std::string::npos || (!fid.empty() && (fid.find("bush") != std::string::npos || fid.find("flower") != std::string::npos || fid.find("fern") != std::string::npos))) {
        mat_id = 0;
        if (season == 2) { // autumn warm golden-russet foliage bounce
            mr = 192; mg = 132; mb = 58;
        } else if (season == 3) { // winter crisp cool frost bounce
            mr = 176; mg = 192; mb = 212;
        } else { // vibrant fresh botanical green bounce
            mr = 72; mg = 174; mb = 64;
        }
    } else if (tid.find("brick") != std::string::npos || tid.find("wall_red") != std::string::npos ||
               tid.find("carpet") != std::string::npos) {
        mat_id = 5;
        mr = 205; mg = 102; mb = 82; // rich terracotta-red bounce onto sidewalk!
    } else if (tid.find("concrete") != std::string::npos || tid.find("sidewalk") != std::string::npos ||
               tid.find("stone") != std::string::npos || tid.find("rock") != std::string::npos ||
               tid.find("linoleum") != std::string::npos || tid.find("tile") != std::string::npos) {
        mat_id = 5;
        mr = 186; mg = 184; mb = 180;
    } else if (tid.find("wood") != std::string::npos || tid.find("floor") != std::string::npos ||
               tid.find("door_c") != std::string::npos || tid.find("door_o") != std::string::npos ||
               (!fid.empty() && (fid.find("bench") != std::string::npos || fid.find("table") != std::string::npos ||
                                 fid.find("chair") != std::string::npos || fid.find("desk") != std::string::npos ||
                                 fid.find("bookcase") != std::string::npos || fid.find("counter") != std::string::npos))) {
        mat_id = 1;
        mr = 204; mg = 152; mb = 92; // warm honey-wood indoor GI bounce!
    } else if (tid.find("pavement") != std::string::npos) {
        mat_id = 6;
        mr = 86; mg = 90; mb = 98;
    } else if (tid.find("dirt") != std::string::npos || tid.find("soil") != std::string::npos ||
               tid.find("sand") != std::string::npos || tid.find("mud") != std::string::npos) {
        mat_id = 6;
        mr = 154; mg = 122; mb = 88;
    }

    cell.surface_hold_u8 = static_cast<uint8_t>(mat_id * 36);
    cell.mat_r = mr;
    cell.mat_g = mg;
    cell.mat_b = mb;
}

} // namespace

uint64_t compute_world_state_sig(bool has_terrain, int rad_x, int rad_y) {
    if (!has_terrain || g == nullptr || !g->w_terrain) {
        return 0ULL;
    }
    map &here = get_map();
    avatar &u = get_avatar();
    const tripoint_bub_ms center = g->ter_view_p;
    if (!here.inbounds(center)) {
        return 0ULL;
    }
    const tripoint_bub_ms player_pos = u.pos_bub(here);
    const auto &st = state();

    uint64_t h = 14695981039346656037ULL;
    auto mix = [&](uint64_t v) {
        h ^= v;
        h *= 1099511628211ULL;
    };
    auto mix_str = [&](const std::string &s) {
        mix(static_cast<uint64_t>(s.size()));
        for (unsigned char ch : s) {
            mix(static_cast<uint64_t>(ch));
        }
    };

    mix(static_cast<uint64_t>(to_turns<int>(calendar::turn - calendar::turn_zero)));
    mix(static_cast<uint64_t>(static_cast<uint32_t>(center.x())) | (static_cast<uint64_t>(static_cast<uint32_t>(center.y())) << 32));
    mix(static_cast<uint64_t>(static_cast<uint32_t>(center.z())));
    mix(static_cast<uint64_t>(static_cast<uint32_t>(player_pos.x())) | (static_cast<uint64_t>(static_cast<uint32_t>(player_pos.y())) << 32));
    mix(static_cast<uint64_t>(static_cast<uint32_t>(player_pos.z())));
    mix(static_cast<uint64_t>(static_cast<uint32_t>(u.view_offset.x())) | (static_cast<uint64_t>(static_cast<uint32_t>(u.view_offset.y())) << 32));
    mix(static_cast<uint64_t>(static_cast<uint32_t>(u.view_offset.z())));
    mix(static_cast<uint64_t>(std::lround(u.active_light() * 100.0f)));
    mix(static_cast<uint64_t>((u.is_running() ? 1u : 0u) | (u.is_crouching() ? 2u : 0u) |
                              (u.get_gender() ? 4u : 0u) | (u.controlling_vehicle ? 8u : 0u)));
    mix(static_cast<uint64_t>(static_cast<uint32_t>(rad_x)) | (static_cast<uint64_t>(static_cast<uint32_t>(rad_y)) << 32));

    const weather_manager &wman = get_weather_const();
    mix_str(wman.weather_id.str());
    mix(static_cast<uint64_t>(wman.windspeed) | (static_cast<uint64_t>(wman.winddirection) << 16));
    mix(static_cast<uint64_t>(std::lround(g->natural_light_level(center.z()) * 100.0f)));

    if (const item_location wielded = u.get_wielded_item()) {
        mix_str(wielded->typeId().str());
    } else {
        mix(0x55AAULL);
    }
    const auto vis_worn = u.worn.get_visible_worn_items(u);
    mix(static_cast<uint64_t>(vis_worn.size()));
    for (const item_location &loc : vis_worn) {
        if (loc) {
            mix_str(loc->typeId().str());
        }
    }

    const auto &auto_route = u.get_auto_move_route();
    mix(static_cast<uint64_t>(auto_route.size()));
    if (!auto_route.empty()) {
        const auto &b = auto_route.back();
        mix(static_cast<uint64_t>(static_cast<uint32_t>(b.x())) | (static_cast<uint64_t>(static_cast<uint32_t>(b.y())) << 32));
    }

    mix(static_cast<uint64_t>(SCT.vSCT.size()));
    for (const scrollingcombattext::cSCT &entry : SCT.vSCT) {
        mix(static_cast<uint64_t>(entry.getStep()) | (static_cast<uint64_t>(static_cast<uint32_t>(entry.getPosX())) << 16));
    }
    mix(st.next_vfx_id.load(std::memory_order_relaxed));

    // Hash live unoccluded w_terrain cells in curses_layer so aim lines, cursor moves, hit flashes,
    // explosions, destination 'X' previews, and debug map edits ALWAYS invalidate immediately,
    // while scrolling inside ImGui/curses popups or sidebars skips redundant world captures 100%!
    const int tx0 = std::max(0, st.work_terrain_x);
    const int ty0 = std::max(0, st.work_terrain_y);
    const int tx1 = std::min(st.work_cols, st.work_terrain_x + st.work_terrain_w);
    const int ty1 = std::min(st.work_rows, st.work_terrain_y + st.work_terrain_h);
    mix(static_cast<uint64_t>(tx0) | (static_cast<uint64_t>(ty0) << 16) |
        (static_cast<uint64_t>(tx1) << 32) | (static_cast<uint64_t>(ty1) << 48));
    if (!st.curses_layer.empty() && st.work_cols > 0) {
        for (int y = ty0; y < ty1; ++y) {
            const size_t row = static_cast<size_t>(y) * static_cast<size_t>(st.work_cols);
            for (int x = tx0; x < tx1; ++x) {
                const CcbTermCell &tc = st.curses_layer[row + static_cast<size_t>(x)];
                if ((tc.flags & CCB_CELL_TERRAIN) == 0) {
                    continue;
                }
                const uint64_t cell_pack = static_cast<uint64_t>(tc.codepoint)
                    ^ (static_cast<uint64_t>(tc.fg_rgba) << 17)
                    ^ (static_cast<uint64_t>(tc.bg_rgba) << 33)
                    ^ (static_cast<uint64_t>((y << 10) | x) << 49);
                mix(cell_pack);
            }
        }
    }

    return h ? h : 1ULL;
}

void capture_world_snapshot(WorldSnapshot &out, uint64_t gen, bool has_terrain) {
    out.header = CcbWorldHeader{};
    out.header.generation = gen;
    out.header.valid = 0;

    if (!has_terrain || g == nullptr || !g->w_terrain) {
        return;
    }

    map &here = get_map();
    avatar &u = get_avatar();
    const tripoint_bub_ms player_pos = u.pos_bub(here);
    const tripoint_bub_ms center = g->ter_view_p;
    const int z = center.z();

    if (!here.inbounds(center)) {
        return;
    }

    auto &st_mut = state();
    // Dynamic viewport capture radius (clamped 16..34 x 12..24; ensures 3D mode gets >= 24x20 lighting coverage!)
    int rad_x = std::clamp(st_mut.capture_rad_x.load(std::memory_order_relaxed), 16, 34);
    int rad_y = std::clamp(st_mut.capture_rad_y.load(std::memory_order_relaxed), 12, 24);
    if (st_mut.render3d_enabled.load(std::memory_order_relaxed)) {
        rad_x = std::max(rad_x, 24);
        rad_y = std::max(rad_y, 20);
    }
    const int width = rad_x * 2 + 1;
    const int height = rad_y * 2 + 1;
    const int origin_x = center.x() - rad_x;
    const int origin_y = center.y() - rad_y;

    out.header.origin_x = origin_x;
    out.header.origin_y = origin_y;
    out.header.width = width;
    out.header.height = height;
    out.header.z = z;
    out.header.center_x = center.x();
    out.header.center_y = center.y();
    out.header.player_x = player_pos.x();
    out.header.player_y = player_pos.y();
    out.header.player_z = player_pos.z();
    out.header.turn = to_turns<int>(calendar::turn - calendar::turn_zero);
    out.header.minutes_of_day = to_minutes<int>(time_past_midnight(calendar::turn));
    out.header.season = static_cast<int>(season_of_year(calendar::turn));
    out.header.day_of_season = day_of_season<int>(calendar::turn);
    out.header.daylight_level = g->natural_light_level(z);
    out.header.player_light = u.active_light();
    out.header.player_male = u.get_gender() ? 1 : 0;
    const bool is_looking = (u.view_offset != tripoint_rel_ms::zero);
    out.header.is_looking = is_looking ? 1 : 0;
    out.header.is_underground = (z < 0) ? 1 : 0;
    out.header.player_indoors = here.is_outside(player_pos) ? 0 : 1;
    out.header.player_move_mode = u.is_running() ? 2 : (u.is_crouching() ? 0 : 1);
    out.header.player_mat_id = 6;
    out.header.tree_density_u8 = 0;

    const weather_manager &wman = get_weather_const();
    const rl_vec2d wdir = convert_wind_to_coord(wman.winddirection);
    const float wlen = std::sqrt(static_cast<float>(wdir.x * wdir.x + wdir.y * wdir.y));
    out.header.wind_x = (wlen > 0.001f) ? static_cast<float>(wdir.x) / wlen : 0.85f;
    out.header.wind_y = (wlen > 0.001f) ? static_cast<float>(wdir.y) / wlen : 0.25f;
    out.header.wind_speed = static_cast<float>(wman.windspeed);

    const std::string wid = wman.weather_id.str();
    std::strncpy(out.header.weather_id, wid.c_str(), sizeof(out.header.weather_id) - 1);

    if (const item_location wielded = u.get_wielded_item()) {
        const std::string wld = wielded->typeId().str();
        std::strncpy(out.header.wielded_id, wld.c_str(), sizeof(out.header.wielded_id) - 1);
    }

    // Worn items CSV for authentic player paperdoll overlays
    out.worn_csv.clear();
    for (const item_location &loc : u.worn.get_visible_worn_items(u)) {
        if (!loc) continue;
        if (!out.worn_csv.empty()) out.worn_csv.push_back(',');
        out.worn_csv += loc->typeId().str();
    }

    // Prepare real CCB visibility + map memory caches
    const visibility_variables &vis_vars = here.get_visibility_variables_cache();
    const level_cache &lcache = here.get_cache_ref(z);
    const tripoint_abs_ms abs_min = here.get_abs(tripoint_bub_ms(std::max(0, origin_x), std::max(0, origin_y), z));
    const tripoint_abs_ms abs_max = here.get_abs(tripoint_bub_ms(
        std::min(MAPSIZE_X - 1, origin_x + width - 1),
        std::min(MAPSIZE_Y - 1, origin_y + height - 1), z));
    u.prepare_map_memory_region(abs_min, abs_max);

    static std::unordered_map<std::string, uint16_t> s_intern_map;
    StringInterner intern(out.strings, s_intern_map);
    const size_t tile_count = static_cast<size_t>(width) * static_cast<size_t>(height);
    out.tiles.resize(tile_count);
    if (tile_count > 0) {
        std::memset(out.tiles.data(), 0, tile_count * sizeof(CcbWorldTile));
    }
    out.lights.clear();
    out.path_points.clear();
    out.sct_entries.clear();

    // Pre-index visible creatures in the viewport so transient hit/explosion overlays can classify cleanly
    // and natural monster curses backgrounds (magenta/blue/purple/red mtype colors & status hilites) NEVER draw boxes!
    static std::unordered_map<int64_t, uint32_t> critter_sym_at;
    static std::unordered_map<int64_t, uint32_t> critter_bg_at;
    critter_sym_at.clear();
    critter_bg_at.clear();
    for (const Creature &critter : g->all_creatures()) {
        const tripoint_bub_ms cp = critter.pos_bub(here);
        if (cp.z() != z) continue;
        if (cp.x() < origin_x || cp.x() >= origin_x + width || cp.y() < origin_y || cp.y() >= origin_y + height) {
            continue;
        }
        const int64_t key = (static_cast<int64_t>(cp.y()) << 32) | static_cast<uint32_t>(cp.x());
        const std::string &sym_s = critter.symbol();
        uint32_t sym_cp = '@';
        if (!sym_s.empty()) {
            sym_cp = static_cast<unsigned char>(sym_s[0]);
        }
        critter_sym_at[key] = sym_cp;
        if (const monster *mon = critter.as_monster()) {
            critter_bg_at[key] = nc_color_bg_rgba(mon->type->color);
        } else {
            critter_bg_at[key] = nc_color_bg_rgba(critter.symbol_color());
        }
    }

    const auto &st = state();
    const int tw_x = st.work_terrain_x;
    const int tw_y = st.work_terrain_y;
    const int tw_w = st.work_terrain_w;
    const int tw_h = st.work_terrain_h;
    const int pos_cx = tw_w / 2;
    const int pos_cy = tw_h / 2;
    const uint32_t black_rgba = st.palette_rgba(0);

    for (int ty = 0; ty < height; ++ty) {
        const int my = origin_y + ty;
        for (int tx = 0; tx < width; ++tx) {
            const int mx = origin_x + tx;
            CcbWorldTile &cell = out.tiles[static_cast<size_t>(ty) * static_cast<size_t>(width) + static_cast<size_t>(tx)];
            cell.ter_subtile = 0xFF;
            cell.furn_subtile = 0xFF;
            cell.field_subtile = 0xFF;
            cell.field_rot = 0;
            cell.trap_sub_rot = 0;

            const tripoint_bub_ms p(mx, my, z);
            if (!here.inbounds(p)) {
                cell.vis = CCB_VIS_UNSEEN;
                continue;
            }

            const lit_level ll = lcache.visibility_cache[mx][my];
            const visibility_type vtype = here.get_visibility(ll, vis_vars);
            const bool sees_tile = (vtype == visibility_type::CLEAR) ||
                                   (vtype == visibility_type::LIT) ||
                                   (vtype == visibility_type::DARK && ll != lit_level::BLANK);

            const bool outside = here.is_outside(p);
            if (outside) {
                cell.flags |= CCB_TILE_OUTSIDE;
            } else {
                cell.flags |= CCB_TILE_IS_ROOFED;
            }
            if (!here.is_transparent(p)) {
                cell.flags |= CCB_TILE_OPAQUE;
            }

            // Populate physical lighting geometry even for visible & memorized cells
            const ter_id real_tid = here.ter(p);
            const ter_t &real_tobj = real_tid.obj();
            const furn_id real_fid = here.furn(p);
            const furn_t *real_fobj = (real_fid != furn_str_id::NULL_ID()) ? &real_fid.obj() : nullptr;
            const optional_vpart_position real_vp = here.veh_at(p);

            // Collect 100% WORLD-SPACE physical artificial light emitters regardless of sees_tile!
            // Guarantees lights NEVER pop on/off when player takes 1 step, and NEVER fabricates
            // fake doorway floodlights from outdoor daylight spillover!
            if (out.lights.size() < 96) {
                float best_lum = 0.0f;
                uint32_t best_rgba = 0xFFD0ECFFu; // warm-neutral incandescent default
                uint8_t best_flags = 0u;
                auto is_fire_id = [](const std::string &sid) -> bool {
                    return sid.find("fire") != std::string::npos || sid.find("flame") != std::string::npos ||
                           sid.find("lava") != std::string::npos || sid.find("brazier") != std::string::npos ||
                           sid.find("hearth") != std::string::npos || sid.find("forge") != std::string::npos ||
                           sid.find("kiln") != std::string::npos || sid.find("campfire") != std::string::npos;
                };
                if (real_tobj.light_emitted > 0) {
                    best_lum = std::max(best_lum, static_cast<float>(real_tobj.light_emitted));
                    best_rgba = classify_emitter_rgba(real_tobj.id.str(), real_tobj.light_color, 0xFFD0ECFFu);
                    if (is_fire_id(real_tobj.id.str())) best_flags |= CCB_LIGHT_FLAG_FIRE;
                } else if (real_tobj.id.str().find("console") != std::string::npos &&
                           real_tobj.id.str().find("broken") == std::string::npos) {
                    best_lum = std::max(best_lum, 4.5f);
                    best_rgba = 0xFFFFDC5Cu;
                }
                if (real_fobj != nullptr) {
                    const std::string &fid_s = real_fobj->id.str();
                    if (real_fobj->light_emitted > 0) {
                        const float fl = static_cast<float>(real_fobj->light_emitted);
                        if (fl > best_lum) {
                            best_lum = fl;
                            best_rgba = classify_emitter_rgba(fid_s, real_fobj->light_color, 0xFFD0ECFFu);
                            best_flags = is_fire_id(fid_s) ? CCB_LIGHT_FLAG_FIRE : 0u;
                        }
                    } else if (fid_s.find("console") != std::string::npos &&
                               fid_s.find("broken") == std::string::npos && 4.5f > best_lum) {
                        best_lum = 4.5f;
                        best_rgba = 0xFFFFDC5Cu;
                        best_flags = 0u;
                    }
                }
                const field &wfld = here.field_at(p);
                if (wfld.field_count() > 0) {
                    for (const auto &fe : wfld) {
                        const field_intensity_level &fil = fe.second.get_intensity_level();
                        if (fil.light_emitted > 0) {
                            const float fl = static_cast<float>(fil.light_emitted);
                            if (fl > best_lum) {
                                best_lum = fl;
                                const bool is_f = (fe.first == fd_fire);
                                const uint32_t fld_def = is_f ? 0xFF348AFFu : 0xFFFFD080u;
                                best_rgba = classify_emitter_rgba(fe.first.id().str(), fil.light_color, fld_def);
                                best_flags = is_f ? CCB_LIGHT_FLAG_FIRE : 0u;
                            }
                        }
                    }
                }
                if (here.has_items(p)) {
                    for (const item &it : here.i_at(p)) {
                        float ilum = 0.0f;
                        units::angle iw = 0_degrees, id = 0_degrees;
                        if (it.getlight(ilum, iw, id) && ilum > best_lum) {
                            best_lum = ilum;
                            const uint32_t it_def = (ilum >= 25.0f) ? 0xFFFFF6EAu : 0xFF348AFFu;
                            const std::string it_s = it.typeId().str();
                            best_rgba = classify_emitter_rgba(it_s, light_color_rgb{}, it_def);
                            best_flags = is_fire_id(it_s) ? CCB_LIGHT_FLAG_FIRE : 0u;
                        }
                    }
                }
                if (best_lum > 0.5f) {
                    out.lights.push_back(CcbWorldLight{
                        mx, my, best_lum, best_rgba, 0.0f, 0.0f, -1.0f, best_flags, {0, 0, 0}
                    });
                }
            }

            // Smart diff-based transient animation & overlay capture from w_terrain:
            // Captures explosions, bullets, hit flashes, aiming/throw lines, zone rectangles,
            // cursors, and unseen sound markers with ZERO false positives on rocks/flowers!
            const int sx = tw_x + pos_cx + (mx - center.x());
            const int sy = tw_y + pos_cy + (my - center.y());
            if (sx >= 0 && sx < st.work_cols && sy >= 0 && sy < st.work_rows) {
                const CcbTermCell &tc = st.curses_layer[static_cast<size_t>(sy) * static_cast<size_t>(st.work_cols) + static_cast<size_t>(sx)];
                const uint32_t bg_rgb = tc.bg_rgba & 0x00FFFFFFu;
                const bool has_bg = (tc.bg_rgba != black_rgba && bg_rgb != 0u);
                const uint8_t bg_r = static_cast<uint8_t>(tc.bg_rgba & 0xFFu);
                const uint8_t bg_g = static_cast<uint8_t>((tc.bg_rgba >> 8) & 0xFFu);
                const uint8_t bg_b = static_cast<uint8_t>((tc.bg_rgba >> 16) & 0xFFu);
                const uint8_t fg_r = static_cast<uint8_t>(tc.fg_rgba & 0xFFu);
                const uint8_t fg_g = static_cast<uint8_t>((tc.fg_rgba >> 8) & 0xFFu);
                const uint8_t fg_b = static_cast<uint8_t>((tc.fg_rgba >> 16) & 0xFFu);

                const int64_t ckey = (static_cast<int64_t>(my) << 32) | static_cast<uint32_t>(mx);
                const auto crit_it = critter_sym_at.find(ckey);
                const bool has_critter = (crit_it != critter_sym_at.end());

                uint8_t ov_kind = CCB_OV_NONE;
                if (!sees_tile && tc.codepoint == '?') {
                    ov_kind = CCB_OV_SOUND;
                } else if (tc.codepoint == 0x2199u || tc.codepoint == 0x2196u ||
                           tc.codepoint == 0x2198u || tc.codepoint == 0x2197u) {
                    // Unobscuring cursor arrows ↙↖↘↗
                    ov_kind = CCB_OV_CURSOR;
                } else if (has_bg) {
                    if (tc.codepoint == '~' && bg_g > bg_r + 30) {
                        ov_kind = CCB_OV_ZONE;
                    } else if (has_critter) {
                        // Creatures in CCB curses frequently use magenta/blue/green/white bg for status/attitude/tracking:
                        // NEVER draw a square OV_HIGHLIGHT box around monsters! Only flash genuine red/yellow combat hits
                        // whose bg differs from the creature's own natural mtype background color.
                        const auto bg_it = critter_bg_at.find(ckey);
                        const bool is_natural_cbg = (bg_it != critter_bg_at.end() && bg_it->second == tc.bg_rgba);
                        if (!is_natural_cbg && bg_r > 165 && bg_b < 60) {
                            ov_kind = CCB_OV_HIT_FLASH;
                        }
                    } else if (tc.codepoint == 'X' && bg_g > 110) {
                        ov_kind = CCB_OV_CURSOR;
                    } else {
                        // Exclude look-around center cursor tile (drawn cleanly via corner reticle) & ASCII ground-item hilite bg
                        const bool is_look_center = is_looking && (mx == center.x() && my == center.y());
                        const bool is_item_hilite_bg = here.has_items(p);
                        if (!is_look_center && !is_item_hilite_bg &&
                            !tile_naturally_has_bg(here, p, real_tobj, real_fobj, real_vp, tc.bg_rgba, black_rgba)) {
                            ov_kind = CCB_OV_HIGHLIGHT;
                        }
                    }
                } else if (tc.codepoint != 0 && tc.codepoint != ' ') {
                    // Check if glyph differs from the tile's own terrain/furniture/item/creature ASCII symbol
                    const uint32_t ter_sym = static_cast<uint32_t>(real_tobj.symbol());
                    const uint32_t furn_sym = real_fobj ? static_cast<uint32_t>(real_fobj->symbol()) : 0u;
                    const uint32_t crit_sym = has_critter ? crit_it->second : 0u;
                    const bool matches_base = (tc.codepoint == ter_sym) ||
                                              (furn_sym != 0u && tc.codepoint == furn_sym) ||
                                              (crit_sym != 0u && tc.codepoint == crit_sym);
                    if (!matches_base && !real_vp) {
                        const bool is_fire_col = (fg_r > 150 && fg_b < 90);
                        const bool is_blast_char = (tc.codepoint == '/' || tc.codepoint == '\\' ||
                                                    tc.codepoint == '-' || tc.codepoint == '|' ||
                                                    tc.codepoint == '^' || tc.codepoint == 'v' ||
                                                    tc.codepoint == '<' || tc.codepoint == '>');
                        if (is_fire_col && is_blast_char) {
                            ov_kind = CCB_OV_EXPLOSION;
                        } else if ((tc.codepoint == '*' || tc.codepoint == '#' || tc.codepoint == '`') &&
                                   fg_r > 170 && fg_g < 90 && fg_b < 90) {
                            // Classic draw_bullet_curses c_red '*' / '#' / '`'
                            ov_kind = CCB_OV_BULLET;
                        } else if (tc.codepoint == 'X' && fg_r > 180 && fg_g > 180 && fg_b > 180) {
                            // White 'X' destination/target marker drawn by draw_ter / draw_line
                            ov_kind = CCB_OV_CURSOR;
                        }
                    }
                }

                if (ov_kind != CCB_OV_NONE) {
                    cell.overlay_cp = tc.codepoint;
                    cell.overlay_fg = tc.fg_rgba;
                    cell.overlay_bg = tc.bg_rgba;
                    cell.overlay_kind = ov_kind;
                    cell.flags |= CCB_TILE_HAS_OVERLAY;
                }
            }

            if (sees_tile && ll != lit_level::BLANK && ll != lit_level::DARK) {
                cell.vis = (ll == lit_level::LOW) ? CCB_VIS_DARK : CCB_VIS_VISIBLE;
                cell.lit_level = static_cast<uint8_t>(ll);

                const float raw_amb = std::max(0.0f, here.ambient_light_at(p));
                float norm_amb = std::clamp(raw_amb / 18.0f, 0.0f, 1.0f);
                if (ll == lit_level::BRIGHT || ll == lit_level::BRIGHT_ONLY) {
                    norm_amb = std::max(norm_amb, 0.92f);
                } else if (ll == lit_level::LIT) {
                    norm_amb = std::max(norm_amb, 0.72f);
                } else if (ll == lit_level::LOW) {
                    norm_amb = std::max(norm_amb, 0.35f);
                }
                cell.ambient_light_u8 = static_cast<uint8_t>(std::clamp(norm_amb * 255.0f, 0.0f, 255.0f));

                // Classify 3D geometry & GI bounce albedo for cangling-city SceneLighting
                classify_tile_lighting(here, p, real_tobj, real_fobj, static_cast<bool>(real_vp), out.header.season, cell);

                // Terrain with REAL CCB connect/orientation subtile & rotation!
                cell.ter_str = intern.intern(real_tobj.id.str());
                {
                    int sub = 0;
                    int rot = 0;
                    const auto &conn_g = real_tobj.connect_to_groups;
                    const auto &rot_g = real_tobj.rotate_to_groups;
                    if (conn_g.any()) {
                        map::get_connect_values(p, sub, rot, conn_g, rot_g, {});
                    } else {
                        const std::array<bool, 5> inv = { false, false, false, false, false };
                        map::get_terrain_orientation(p, rot, sub, {}, inv, rot_g);
                    }
                    cell.ter_subtile = static_cast<uint8_t>(std::clamp(sub, 0, 7));
                    cell.ter_rot = static_cast<uint8_t>(rot & 15);
                }

                // Furniture with REAL CCB connect/orientation subtile & rotation!
                if (real_fobj != nullptr) {
                    cell.furn_str = intern.intern(real_fobj->id.str());
                    int fsub = 0;
                    int frot = 0;
                    const auto &fconn = real_fobj->connect_to_groups;
                    const auto &frot_g = real_fobj->rotate_to_groups;
                    if (fconn.any()) {
                        map::get_furn_connect_values(p, fsub, frot, fconn, frot_g, {});
                    } else {
                        const std::array<int, 4> fn = {
                            static_cast<int>(here.furn(p + point::south)),
                            static_cast<int>(here.furn(p + point::east)),
                            static_cast<int>(here.furn(p + point::west)),
                            static_cast<int>(here.furn(p + point::north))
                        };
                        map::get_tile_values_with_ter(p, real_fid.to_i(), fn, fsub, frot, frot_g);
                    }
                    cell.furn_subtile = static_cast<uint8_t>(std::clamp(fsub, 0, 7));
                    cell.furn_rot = static_cast<uint8_t>(frot & 15);
                }

                // Trap with REAL CCB 4-neighbor multitile connection & rotation!
                const trap &tr = here.tr_at(p);
                if (!tr.is_null() && tr.can_see(p, u)) {
                    cell.trap_str = intern.intern(tr.id.str());
                    const std::array<int, 4> tnb = {
                        static_cast<int>(here.tr_at(p + point::south).loadid),
                        static_cast<int>(here.tr_at(p + point::east).loadid),
                        static_cast<int>(here.tr_at(p + point::west).loadid),
                        static_cast<int>(here.tr_at(p + point::north).loadid)
                    };
                    int tsub = 0;
                    int trot = 0;
                    map::get_tile_values(tr.loadid.to_i(), tnb, tsub, trot, 0);
                    const uint8_t packed_sub = static_cast<uint8_t>(std::clamp(tsub, 0, 7) + 1);
                    cell.trap_sub_rot = static_cast<uint8_t>((trot & 0xF) | ((packed_sub & 0xF) << 4));
                }

                // Field (blood, gibs, acid, bile, fire, smoke, electricity) with REAL CCB 4-neighbor autotile subtile & rotation!
                // Fixes fd_blood & 25+ multitile fields rendering as opaque full-tile squares instead of realistic splatters/connections!
                const field &fld = here.field_at(p);
                const field_type_id disp_fld = fld.displayed_field_type();
                if (disp_fld) {
                    cell.field_str = intern.intern(disp_fld.id().str());
                    cell.field_intensity = static_cast<uint8_t>(std::clamp(fld.displayed_intensity(), 1, 3));
                    auto nb_fld_id = [&](const tripoint_bub_ms &q) -> int {
                        if (!here.inbounds(q)) return 0;
                        const field &nf = here.field_at(q);
                        return nf.find_field(disp_fld) != nullptr ? disp_fld.to_i() : 0;
                    };
                    const std::array<int, 4> fnb = {
                        nb_fld_id(p + point::south),
                        nb_fld_id(p + point::east),
                        nb_fld_id(p + point::west),
                        nb_fld_id(p + point::north)
                    };
                    int fsub = 0;
                    int frot = 0;
                    map::get_tile_values(disp_fld.to_i(), fnb, fsub, frot, 0);
                    cell.field_subtile = static_cast<uint8_t>(std::clamp(fsub, 0, 7));
                    cell.field_rot = static_cast<uint8_t>(frot & 15);
                }

                // Vehicle part (exact CCB parity: keep pure vp_<id>[#<variant>] and pack open/broken subtile in high nibble!)
                if (real_vp) {
                    const vehicle &veh = real_vp->vehicle();
                    const vpart_display vd = veh.get_display_of_tile(real_vp->mount_pos3());
                    if (!vd.id.is_null()) {
                        std::string vname = vd.get_tileset_id();
                        if (vname.empty()) {
                            vname = "vp_" + vd.id.str();
                        }
                        const uint8_t vsub = vd.is_open ? 6u : (vd.is_broken ? 7u : 0u);
                        const uint8_t vrot = static_cast<uint8_t>(angle_to_rot4(veh.face.dir() - 270_degrees) & 3);
                        cell.vpart_str = intern.intern(vname);
                        cell.vpart_rot = static_cast<uint8_t>(vrot | (vsub << 4));
                    }
                }

                // Items & Corpses
                if (here.sees_some_items(p, u)) {
                    const map_stack items = here.i_at(p);
                    const int icount = static_cast<int>(items.size());
                    if (icount > 0) {
                        cell.item_count = static_cast<uint16_t>(std::min(icount, 65535));
                        const item *top_it = nullptr;
                        for (const item &it : items) {
                            top_it = &it;
                        }
                        if (top_it != nullptr) {
                            cell.item_str = intern.intern(top_it->typeId().str());
                            if (top_it->is_corpse()) {
                                if (const mtype *mt_mon = top_it->get_mtype()) {
                                    cell.corpse_str = intern.intern("corpse_" + mt_mon->id.str());
                                    cell.flags |= CCB_TILE_HAS_CORPSE;
                                }
                            }
                        }
                    }
                }
            } else {
                // Fog-of-war: consult real CCB map memory!
                classify_tile_lighting(here, p, real_tobj, real_fobj, static_cast<bool>(real_vp), out.header.season, cell);
                const memorized_tile &mem = u.get_memorized_tile(here.get_abs(p));
                const std::string &mem_ter = mem.get_ter_id();
                if (!mem_ter.empty()) {
                    cell.vis = CCB_VIS_MEMORIZED;
                    cell.lit_level = static_cast<uint8_t>(lit_level::MEMORIZED);
                    cell.ter_str = intern.intern(mem_ter);
                    cell.ter_subtile = static_cast<uint8_t>(std::clamp(mem.get_ter_subtile(), 0, 7));
                    cell.ter_rot = static_cast<uint8_t>(mem.get_ter_rotation() & 15);
                    const std::string &mem_dec = mem.get_dec_id();
                    if (!mem_dec.empty()) {
                        if (mem_dec.rfind("vp_", 0) == 0) {
                            cell.vpart_str = intern.intern(mem_dec);
                            const uint8_t msub = static_cast<uint8_t>(std::clamp(mem.get_dec_subtile(), 0, 7));
                            const uint8_t mrot = static_cast<uint8_t>(mem.get_dec_rotation() & 3);
                            cell.vpart_rot = static_cast<uint8_t>(mrot | (msub << 4));
                        } else {
                            cell.furn_str = intern.intern(mem_dec);
                            cell.furn_subtile = static_cast<uint8_t>(std::clamp(mem.get_dec_subtile(), 0, 7));
                            cell.furn_rot = static_cast<uint8_t>(mem.get_dec_rotation() & 15);
                        }
                    }
                } else {
                    cell.vis = CCB_VIS_UNSEEN;
                }
            }
        }
    }

    // 1-tile static terrain fringe along sight-cone edges so the real-time GPU per-pixel raycaster
    // can slice smooth diagonal light/sight beams through doorways & around corners with ZERO 32px stair-steps
    // (populates static ground/wall terrain ONLY — never reveals monsters, items, or secrets behind walls!).
    for (int ty = 0; ty < height; ++ty) {
        const int my = origin_y + ty;
        for (int tx = 0; tx < width; ++tx) {
            const int mx = origin_x + tx;
            CcbWorldTile &cell = out.tiles[static_cast<size_t>(ty) * static_cast<size_t>(width) + static_cast<size_t>(tx)];
            if (cell.vis != CCB_VIS_UNSEEN) continue;
            const tripoint_bub_ms p(mx, my, z);
            if (!here.inbounds(p)) continue;

            const bool cell_is_opaque = (cell.flags & CCB_TILE_OPAQUE) != 0;
            bool touches_open_seen = false;
            for (int dy = -1; dy <= 1 && !touches_open_seen; ++dy) {
                const int ny = ty + dy;
                if (ny < 0 || ny >= height) continue;
                for (int dx = -1; dx <= 1; ++dx) {
                    if (dx == 0 && dy == 0) continue;
                    const int nx = tx + dx;
                    if (nx < 0 || nx >= width) continue;
                    const CcbWorldTile &nb = out.tiles[static_cast<size_t>(ny) * static_cast<size_t>(width) + static_cast<size_t>(nx)];
                    // Never pull unseen opaque solid walls out of dark-vision darkness (only smooth brightly-lit cones & open floors!)
                    const bool nb_ok = cell_is_opaque
                        ? (nb.vis == CCB_VIS_VISIBLE)
                        : (nb.vis == CCB_VIS_VISIBLE || nb.vis == CCB_VIS_DARK);
                    if (nb_ok && (nb.flags & CCB_TILE_OPAQUE) == 0) {
                        touches_open_seen = true;
                        break;
                    }
                }
            }
            if (!touches_open_seen) continue;

            cell.vis = CCB_VIS_FRINGE;
            const ter_id tid = here.ter(p);
            const ter_t &tobj = tid.obj();
            cell.ter_str = intern.intern(tobj.id.str());
            {
                int sub = 0, rot = 0;
                const auto &conn_g = tobj.connect_to_groups;
                const auto &rot_g = tobj.rotate_to_groups;
                if (conn_g.any()) {
                    map::get_connect_values(p, sub, rot, conn_g, rot_g, {});
                } else {
                    const std::array<bool, 5> inv = { false, false, false, false, false };
                    map::get_terrain_orientation(p, rot, sub, {}, inv, rot_g);
                }
                cell.ter_subtile = static_cast<uint8_t>(std::clamp(sub, 0, 7));
                cell.ter_rot = static_cast<uint8_t>(rot & 15);
            }
            const furn_id fid = here.furn(p);
            if (fid != furn_str_id::NULL_ID()) {
                const furn_t &fobj = fid.obj();
                cell.furn_str = intern.intern(fobj.id.str());
                int fsub = 0, frot = 0;
                if (fobj.connect_to_groups.any()) {
                    map::get_furn_connect_values(p, fsub, frot, fobj.connect_to_groups, fobj.rotate_to_groups, {});
                } else {
                    const std::array<int, 4> fn = {
                        static_cast<int>(here.furn(p + point::south)),
                        static_cast<int>(here.furn(p + point::east)),
                        static_cast<int>(here.furn(p + point::west)),
                        static_cast<int>(here.furn(p + point::north))
                    };
                    map::get_tile_values_with_ter(p, fid.to_i(), fn, fsub, frot, fobj.rotate_to_groups);
                }
                cell.furn_subtile = static_cast<uint8_t>(std::clamp(fsub, 0, 7));
                cell.furn_rot = static_cast<uint8_t>(frot & 15);
            }
        }
    }

    // Compute nearby tree canopy density (for forest wind rustle & daytime birds) & player underfoot material ID
    {
        int tree_cnt = 0;
        for (int ty = 0; ty < height; ++ty) {
            const int dy = (origin_y + ty) - player_pos.y();
            if (std::abs(dy) > 14) continue;
            for (int tx = 0; tx < width; ++tx) {
                const int dx = (origin_x + tx) - player_pos.x();
                if (std::abs(dx) > 14) continue;
                const CcbWorldTile &tc = out.tiles[static_cast<size_t>(ty) * static_cast<size_t>(width) + static_cast<size_t>(tx)];
                if (tc.light_kind == CCB_LIGHT_TREE) {
                    ++tree_cnt;
                }
            }
        }
        out.header.tree_density_u8 = static_cast<uint8_t>(std::clamp(tree_cnt * 7, 0, 255));

        const int ptx = player_pos.x() - origin_x;
        const int pty = player_pos.y() - origin_y;
        if (ptx >= 0 && ptx < width && pty >= 0 && pty < height) {
            const CcbWorldTile &pc = out.tiles[static_cast<size_t>(pty) * static_cast<size_t>(width) + static_cast<size_t>(ptx)];
            uint8_t pmat = static_cast<uint8_t>(std::min(6, static_cast<int>(pc.surface_hold_u8) / 36));
            const ter_t &pt_obj = here.ter(player_pos).obj();
            if ((pc.flags & CCB_TILE_IS_WATER) != 0 ||
                ((pt_obj.id.str() == "t_puddle" || pt_obj.id.str() == "t_puddle_underground") && here.has_items(player_pos))) {
                pmat = 4; // water splash
            }
            out.header.player_mat_id = pmat;
        }
    }

    // Active vehicle headlights / aisle / dome lights (world-space, with true directional spotlight cones!)
    for (wrapped_vehicle &vv : here.get_vehicles()) {
        vehicle *v = vv.v;
        if (!v) continue;
        for (const vehicle_part *pt : v->lights()) {
            if (out.lights.size() >= 96) break;
            if (!pt) continue;
            const tripoint_bub_ms src = v->bub_part_pos(here, *pt);
            if (src.z() != z) continue;
            if (src.x() < origin_x || src.x() >= origin_x + width || src.y() < origin_y || src.y() >= origin_y + height) {
                continue;
            }
            const vpart_info &vpi = pt->info();
            const std::string &vpid = vpi.id.str();
            const bool is_cone = vpi.has_flag(VPFLAG_CONE_LIGHT) || vpid.find("headlight") != std::string::npos || vpid.find("searchlight") != std::string::npos;
            const bool is_wide = vpi.has_flag(VPFLAG_WIDE_CONE_LIGHT) || vpid.find("floodlight") != std::string::npos;
            float dx = 0.0f, dy = 0.0f, cone_c = -1.0f;
            uint8_t lflags = 0u;
            if (is_cone || is_wide) {
                const double rad = units::to_radians(v->face.dir() + pt->direction);
                dx = static_cast<float>(std::cos(rad));
                dy = static_cast<float>(std::sin(rad));
                cone_c = is_wide ? 0.48f : 0.78f; // ~61 deg wide floodlight vs ~39 deg focused headlight beam!
                lflags |= CCB_LIGHT_FLAG_SPOTLIGHT;
            }
            const float vlum = std::clamp(static_cast<float>(vpi.bonus) * (is_cone || is_wide ? 0.34f : 0.25f), 4.5f, 30.0f);
            out.lights.push_back(CcbWorldLight{
                src.x(), src.y(), vlum, classify_emitter_rgba(vpid, vpi.light_color, 0xFFFFF4E4u),
                dx, dy, cone_c, lflags, {0, 0, 0}
            });
        }
    }

    // Creatures (Player + Visible Monsters + Visible NPCs)
    out.creatures.clear();
    for (const Creature &critter : g->all_creatures()) {
        const tripoint_bub_ms cp = critter.pos_bub(here);
        if (cp.z() != z) continue;
        if (cp.x() < origin_x || cp.x() >= origin_x + width || cp.y() < origin_y || cp.y() >= origin_y + height) {
            continue;
        }
        const bool is_player = (&critter == &u);
        if (!is_player && !u.sees(here, critter)) {
            continue;
        }
        CcbWorldCreature wc{};
        wc.x = cp.x();
        wc.y = cp.y();
        wc.uid = is_player ? 1u : static_cast<uint32_t>((reinterpret_cast<uintptr_t>(&critter) >> 3) ^ 0x9E3779B9u);
        if (wc.uid == 0u) wc.uid = 2u;
        if (is_player) {
            const bool is_m = u.get_gender();
            wc.flags = CCB_CRITTER_PLAYER | (is_m ? CCB_CRITTER_MALE : 0u);
            wc.sprite_str = intern.intern(is_m ? "player_male" : "player_female");
            wc.hp_pct = 100;
        } else if (const monster *mon = critter.as_monster()) {
            const monster_attitude att = mon->attitude(&u);
            if (att == MATT_ATTACK || att == MATT_FOLLOW) {
                wc.flags |= CCB_CRITTER_HOSTILE;
            } else if (att == MATT_FRIEND) {
                wc.flags |= CCB_CRITTER_FRIENDLY;
            }
            wc.sprite_str = intern.intern(mon->type->id.str());
            const int hp_max = std::max(1, mon->get_hp_max());
            wc.hp_pct = static_cast<uint8_t>(std::clamp((mon->get_hp() * 100) / hp_max, 0, 100));
        } else if (const npc *guy = critter.as_npc()) {
            const bool is_m = guy->get_gender();
            wc.flags = CCB_CRITTER_NPC | (is_m ? CCB_CRITTER_MALE : 0u);
            if (guy->is_enemy()) wc.flags |= CCB_CRITTER_HOSTILE;
            else if (guy->is_ally(u)) wc.flags |= CCB_CRITTER_FRIENDLY;
            wc.sprite_str = intern.intern(is_m ? "npc_male" : "npc_female");
            wc.hp_pct = 100;
            if (const item_location gw = guy->get_wielded_item()) {
                wc.wield_str = intern.intern(gw->typeId().str());
            }
            int w_slot = 0;
            std::vector<const item *> npc_worn;
            guy->worn.inv_dump(npc_worn);
            for (const item *wit : npc_worn) {
                if (!wit || w_slot >= 4) break;
                wc.worn_str[w_slot++] = intern.intern(wit->typeId().str());
            }
        }
        out.creatures.push_back(wc);
    }

    // Real CCB Pixel Minimap RGBA (121x121 centered on player — true FOV + map memory + vehicles + monsters!)
    // Cache the static 14,641-cell terrain/memory base by (turn, player_pos, z) so mouse hover & look-around
    // skip 14,641 map/memory lookups (~100x faster!) and only re-stamp the few live creatures!
    constexpr int MM_RAD = 60;
    constexpr int MM_SIZE = MM_RAD * 2 + 1; // 121
    constexpr size_t MM_BYTES = static_cast<size_t>(MM_SIZE) * static_cast<size_t>(MM_SIZE) * 4u;
    out.header.minimap_size = MM_SIZE;

    static int s_mm_turn = -1;
    static int s_mm_px = -99999, s_mm_py = -99999, s_mm_pz = -99999;
    static std::vector<uint8_t> s_mm_base_cache;

    if (s_mm_base_cache.size() != MM_BYTES || s_mm_turn != out.header.turn ||
        s_mm_px != player_pos.x() || s_mm_py != player_pos.y() || s_mm_pz != z) {
        s_mm_base_cache.assign(MM_BYTES, 0);
        for (int dy = -MM_RAD; dy <= MM_RAD; ++dy) {
            const int my = player_pos.y() + dy;
            for (int dx = -MM_RAD; dx <= MM_RAD; ++dx) {
                const int mx = player_pos.x() + dx;
                const size_t px_off = (static_cast<size_t>(dy + MM_RAD) * MM_SIZE + static_cast<size_t>(dx + MM_RAD)) * 4u;
                const tripoint_bub_ms p(mx, my, z);
                if (!here.inbounds(p)) {
                    s_mm_base_cache[px_off + 3] = 255;
                    continue;
                }
                const lit_level ll = lcache.visibility_cache[mx][my];
                const visibility_type vt = here.get_visibility(ll, vis_vars);
                uint32_t rgba = 0xFF000000u;
                if (vt == visibility_type::CLEAR || vt == visibility_type::LIT) {
                    if (const optional_vpart_position vp = here.veh_at(p)) {
                        const vpart_display vd = vp->vehicle().get_display_of_tile(vp->mount_pos3());
                        rgba = nc_color_to_rgba(vd.color);
                    } else if (const furn_id fid = here.furn(p)) {
                        rgba = nc_color_to_rgba(fid->color());
                    } else {
                        rgba = nc_color_to_rgba(here.ter(p)->color());
                    }
                } else {
                    const memorized_tile &mem = u.get_memorized_tile(here.get_abs(p));
                    if (!mem.get_ter_id().empty()) {
                        uint32_t base = nc_color_to_rgba(here.ter(p)->color());
                        uint8_t r = static_cast<uint8_t>((base & 0xFFu) / 3);
                        uint8_t g8 = static_cast<uint8_t>(((base >> 8) & 0xFFu) / 3);
                        uint8_t b = static_cast<uint8_t>(std::min(255u, ((base >> 16) & 0xFFu) / 2 + 12u));
                        rgba = static_cast<uint32_t>(r) | (static_cast<uint32_t>(g8) << 8) |
                               (static_cast<uint32_t>(b) << 16) | (0xFFu << 24);
                    }
                }
                s_mm_base_cache[px_off + 0] = static_cast<uint8_t>(rgba & 0xFFu);
                s_mm_base_cache[px_off + 1] = static_cast<uint8_t>((rgba >> 8) & 0xFFu);
                s_mm_base_cache[px_off + 2] = static_cast<uint8_t>((rgba >> 16) & 0xFFu);
                s_mm_base_cache[px_off + 3] = 255;
            }
        }
        s_mm_turn = out.header.turn;
        s_mm_px = player_pos.x();
        s_mm_py = player_pos.y();
        s_mm_pz = z;
    }
    out.minimap_rgba.resize(MM_BYTES);
    std::memcpy(out.minimap_rgba.data(), s_mm_base_cache.data(), MM_BYTES);

    uint64_t mm_sig = 14695981039346656037ULL;
    auto mm_mix = [&](uint64_t v) {
        mm_sig ^= v;
        mm_sig *= 1099511628211ULL;
    };
    mm_mix(static_cast<uint64_t>(s_mm_turn));
    mm_mix(static_cast<uint64_t>(static_cast<uint32_t>(s_mm_px)) | (static_cast<uint64_t>(static_cast<uint32_t>(s_mm_py)) << 32));
    mm_mix(static_cast<uint64_t>(static_cast<uint32_t>(s_mm_pz)));

    // Stamp visible creatures & player onto pixel minimap
    for (const Creature &critter : g->all_creatures()) {
        const tripoint_bub_ms cp = critter.pos_bub(here);
        if (cp.z() != z) continue;
        const int dx = cp.x() - player_pos.x();
        const int dy = cp.y() - player_pos.y();
        if (std::abs(dx) > MM_RAD || std::abs(dy) > MM_RAD) continue;
        const bool is_player = (&critter == &u);
        if (!is_player && !u.sees(here, critter)) continue;

        uint8_t r = 255, g8 = 255, b = 255;
        if (!is_player) {
            if (const monster *m = critter.as_monster()) {
                const auto att = m->attitude(&u);
                if (att == MATT_ATTACK || att == MATT_FOLLOW) {
                    r = 255; g8 = 40; b = 40;
                } else {
                    r = 255; g8 = 220; b = 60;
                }
            } else {
                r = 80; g8 = 255; b = 120;
            }
        }
        auto plot = [&](int px, int py) {
            if (px < 0 || px >= MM_SIZE || py < 0 || py >= MM_SIZE) return;
            const size_t o = (static_cast<size_t>(py) * MM_SIZE + static_cast<size_t>(px)) * 4u;
            out.minimap_rgba[o + 0] = r;
            out.minimap_rgba[o + 1] = g8;
            out.minimap_rgba[o + 2] = b;
            out.minimap_rgba[o + 3] = 255;
        };
        const int cx = dx + MM_RAD;
        const int cy = dy + MM_RAD;
        mm_mix(static_cast<uint64_t>(cx) | (static_cast<uint64_t>(cy) << 12) |
               (static_cast<uint64_t>(r) << 24) | (static_cast<uint64_t>(g8) << 32) | (static_cast<uint64_t>(b) << 40));
        plot(cx, cy);
        if (is_player) {
            plot(cx - 1, cy); plot(cx + 1, cy);
            plot(cx, cy - 1); plot(cx, cy + 1);
        }
    }
    if (st_mut.minimap_seq_counter == 0 || mm_sig != st_mut.last_minimap_sig) {
        st_mut.last_minimap_sig = mm_sig;
        ++st_mut.minimap_seq_counter;
    }
    out.header.minimap_seq = st_mut.minimap_seq_counter;

    // Capture active auto-move route from u.get_auto_move_route(), OR synthesize preview route
    // from CCB's highlighted destination_preview / draw_line tiles on w_terrain!
    const auto &auto_route = u.get_auto_move_route();
    if (!auto_route.empty()) {
        for (size_t i = 0; i < auto_route.size() && out.path_points.size() < 256; ++i) {
            if (auto_route[i].z() != z) continue;
            const uint8_t kind = (i + 1 == auto_route.size()) ? CCB_PATH_DESTINATION : CCB_PATH_AUTOMOVE;
            out.path_points.push_back(CcbWorldPathPoint{auto_route[i].x(), auto_route[i].y(), kind, {0, 0, 0}});
        }
    } else {
        // Reconstruct CCB's destination_preview via exact 8-neighbor BFS from player -> destination 'X'
        // through highlighted cells ONLY, so unrelated highlights elsewhere on screen can never pollute the route!
        int dest_tx = -1, dest_ty = -1;
        for (int ty = 0; ty < height; ++ty) {
            for (int tx = 0; tx < width; ++tx) {
                const CcbWorldTile &c = out.tiles[static_cast<size_t>(ty) * static_cast<size_t>(width) + static_cast<size_t>(tx)];
                if ((c.flags & CCB_TILE_HAS_OVERLAY) != 0 && c.overlay_kind == CCB_OV_CURSOR && c.overlay_cp == 'X') {
                    dest_tx = tx;
                    dest_ty = ty;
                    break;
                }
            }
            if (dest_tx >= 0) break;
        }
        const int start_tx = player_pos.x() - origin_x;
        const int start_ty = player_pos.y() - origin_y;
        if (dest_tx >= 0 && start_tx >= 0 && start_tx < width && start_ty >= 0 && start_ty < height) {
            const int total = width * height;
            std::vector<int> parent(static_cast<size_t>(total), -1);
            const int start_idx = start_ty * width + start_tx;
            const int dest_idx = dest_ty * width + dest_tx;
            parent[static_cast<size_t>(start_idx)] = start_idx;

            std::queue<int> q;
            q.push(start_idx);
            static constexpr int DX[8] = {1, -1, 0, 0, 1, 1, -1, -1};
            static constexpr int DY[8] = {0, 0, 1, -1, 1, -1, 1, -1};
            bool reached = false;
            while (!q.empty()) {
                const int cur = q.front();
                q.pop();
                if (cur == dest_idx) {
                    reached = true;
                    break;
                }
                const int cx = cur % width;
                const int cy = cur / width;
                for (int d = 0; d < 8; ++d) {
                    const int nx = cx + DX[d];
                    const int ny = cy + DY[d];
                    if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
                    const int nidx = ny * width + nx;
                    if (parent[static_cast<size_t>(nidx)] != -1) continue;
                    const CcbWorldTile &nc = out.tiles[static_cast<size_t>(nidx)];
                    const bool is_dest = (nidx == dest_idx);
                    const bool is_hl = ((nc.flags & CCB_TILE_HAS_OVERLAY) != 0 && nc.overlay_kind == CCB_OV_HIGHLIGHT);
                    if (!is_dest && !is_hl) continue;
                    parent[static_cast<size_t>(nidx)] = cur;
                    q.push(nidx);
                }
            }

            if (reached) {
                std::vector<int> chain;
                for (int cur = dest_idx; cur != start_idx && cur >= 0; cur = parent[static_cast<size_t>(cur)]) {
                    chain.push_back(cur);
                    if (chain.size() >= 256) break;
                }
                std::reverse(chain.begin(), chain.end());
                for (size_t i = 0; i < chain.size(); ++i) {
                    const int idx = chain[i];
                    const int wx = origin_x + (idx % width);
                    const int wy = origin_y + (idx / width);
                    const bool is_last = (i + 1 == chain.size());
                    out.path_points.push_back(CcbWorldPathPoint{
                        wx, wy,
                        static_cast<uint8_t>(is_last ? CCB_PATH_DESTINATION : CCB_PATH_PREVIEW),
                        {0, 0, 0}
                    });
                    // Clear raw highlight box on tiles consumed by the sleek glowing route renderer
                    CcbWorldTile &rt = out.tiles[static_cast<size_t>(idx)];
                    if (rt.overlay_kind == CCB_OV_HIGHLIGHT || (is_last && rt.overlay_kind == CCB_OV_CURSOR)) {
                        rt.overlay_kind = CCB_OV_NONE;
                        rt.flags &= static_cast<uint8_t>(~CCB_TILE_HAS_OVERLAY);
                    }
                }
            }
        }
    }

    // Capture live Scrolling Combat Text (SCT.vSCT) floating damage / dodge / crit numbers!
    for (const scrollingcombattext::cSCT &entry : SCT.vSCT) {
        if (out.sct_entries.size() >= 64) break;
        const std::string txt = entry.getText("full");
        if (txt.empty()) continue;
        CcbWorldSct sc{};
        sc.x = entry.getPosX();
        sc.y = entry.getPosY();
        const bool is_old = entry.getStep() >= scrollingcombattext::iMaxSteps / 2;
        sc.color_rgba = nc_color_to_rgba(msgtype_to_color(entry.getMsgType("first"), is_old));
        sc.step = static_cast<uint8_t>(std::clamp(entry.getStep(), 0, 255));
        sc.max_steps = static_cast<uint8_t>(std::clamp(scrollingcombattext::iMaxSteps, 1, 255));
        std::strncpy(sc.text, txt.c_str(), sizeof(sc.text) - 1);
        out.sct_entries.push_back(sc);
    }

    out.header.creature_count = static_cast<int32_t>(out.creatures.size());
    out.header.light_count = static_cast<int32_t>(out.lights.size());
    out.header.path_count = static_cast<int32_t>(out.path_points.size());
    out.header.sct_count = static_cast<int32_t>(out.sct_entries.size());
    out.header.string_count = intern.count();
    out.header.string_bytes = static_cast<int32_t>(out.strings.size());
    out.header.valid = 1;
}

} // namespace ccb_bridge
