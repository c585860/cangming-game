#include "bridge_state.hpp"

#include "avatar.h"
#include "color.h"
#include "creature.h"
#include "creature_tracker.h"
#include "enums.h"
#include "explosion.h"
#include "explosion_light.h"
#include "game.h"
#include "line.h"
#include "map.h"
#include "units.h"
#include "vfx_emit.h"

#include <algorithm>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>

// Pure geometry identical to upstream src/vfx_emit.cpp so callers & helpers stay 100% compatible.
std::vector<tripoint_bub_ms> vfx_shape_tiles(const vfx_emit &e) {
    std::set<tripoint_bub_ms> out;

    switch (e.shape) {
        case vfx_shape::point:
            out.emplace(e.origin);
            break;

        case vfx_shape::disc: {
            const int r = std::max(0, e.radius);
            for (int dx = -r; dx <= r; ++dx) {
                for (int dy = -r; dy <= r; ++dy) {
                    if (dx * dx + dy * dy <= r * r) {
                        out.emplace(e.origin + point_rel_ms(dx, dy));
                    }
                }
            }
            break;
        }

        case vfx_shape::line: {
            const std::vector<tripoint_bub_ms> spine = line_to(e.origin, e.target);
            const point_rel_ms delta = (e.target - e.origin).xy();
            const point_rel_ms perp(sgn(-delta.y()), sgn(delta.x()));
            const int half = std::max(0, e.radius) / 2;
            for (const tripoint_bub_ms &p : spine) {
                for (int w = -half; w <= half; ++w) {
                    out.emplace(p + point_rel_ms(perp.x() * w, perp.y() * w));
                }
            }
            out.emplace(e.origin);
            break;
        }

        case vfx_shape::cone: {
            const units::angle mid = coord_to_angle(e.origin.raw(), e.target.raw());
            const units::angle half_width = units::from_degrees(e.arc_degrees / 2.0);
            const int reach = std::max(1, e.range);
            for (units::angle a = mid - half_width; a <= mid + half_width; a += 1_degrees) {
                for (int rng = 1; rng <= reach; ++rng) {
                    tripoint potential;
                    calc_ray_end(a, rng, e.origin.raw(), potential);
                    out.emplace(potential);
                }
            }
            break;
        }

        case vfx_shape::num_vfx_shapes:
            break;
    }

    return std::vector<tripoint_bub_ms>(out.begin(), out.end());
}

void explosion_handler::play_vfx(const vfx_emit &e) {
    auto &st = ccb_bridge::state();

    // Classify CCB's gunfire/beam/impact/blast VFX into photorealistic GPU VFX + HDR Dynamic Point Lights
    uint8_t kind = CCB_VFX_BLAST;
    uint32_t rgba = 0xFF44B4FFu; // R=255, G=180, B=68 warm incandescent amber-orange
    float radius = static_cast<float>(std::max(1, e.radius));
    float light_i = 18.0f;
    uint16_t delay_ms = 0;
    uint8_t caliber = CCB_CALIBER_DEFAULT;
    uint8_t shot_idx = 0;
    uint8_t flags = 0;

    if (g != nullptr && !get_map().is_outside(e.origin)) {
        flags |= CCB_VFX_FLAG_INDOORS;
    }

    const bool sync_shot = st.has_recent_shot_context();

    if (e.light == explosion_lights::muzzle_flash) {
        kind = CCB_VFX_MUZZLE_FLASH;
        rgba = 0xFF46C2FFu; // Hot photographic amber-gold muzzle flame (R=255, G=194, B=70)
        radius = 8.5f;
        light_i = 22.0f;
        if (sync_shot) {
            delay_ms = st.active_shot_delay_ms;
            caliber = st.active_gun_caliber;
            shot_idx = st.active_shot_index;
            flags |= st.active_vfx_flags;
            switch (caliber) {
                case CCB_CALIBER_SUPPRESSED:
                    radius = 3.8f;
                    light_i = 6.5f;
                    rgba = 0xFF88A8CCu; // Dim warm gas puff
                    break;
                case CCB_CALIBER_PISTOL:
                    radius = 7.2f;
                    light_i = 18.0f;
                    break;
                case CCB_CALIBER_RIFLE:
                    radius = 10.0f;
                    light_i = 26.0f;
                    break;
                case CCB_CALIBER_SHOTGUN:
                    radius = 11.5f;
                    light_i = 30.0f;
                    rgba = 0xFF38A4FFu;
                    break;
                case CCB_CALIBER_HEAVY:
                    radius = 13.5f;
                    light_i = 36.0f;
                    rgba = 0xFF42C0FFu;
                    break;
                default:
                    break;
            }
        }
    } else if (e.light == explosion_lights::bullet_tracer) {
        kind = CCB_VFX_TRACER;
        rgba = 0xFF88DCFFu; // Incandescent tracer gold-white
        radius = 2.8f;
        light_i = 5.5f;
        if (sync_shot) {
            delay_ms = st.active_shot_delay_ms;
            caliber = st.active_gun_caliber;
            shot_idx = st.active_shot_index;
            st.active_tracer_emitted = true;
        }
    } else if (e.light == explosion_lights::beam_laser) {
        kind = CCB_VFX_BEAM_LASER;
        rgba = 0xFF3830FFu; // Crimson laser
        radius = 6.5f;
        light_i = 16.0f;
        caliber = CCB_CALIBER_ENERGY;
        if (sync_shot) {
            delay_ms = st.active_shot_delay_ms;
            shot_idx = st.active_shot_index;
            st.active_tracer_emitted = true;
        }
    } else if (e.light == explosion_lights::beam_plasma) {
        kind = CCB_VFX_BEAM_PLASMA;
        rgba = 0xFFFFB058u; // Electric plasma cyan
        radius = 8.0f;
        light_i = 20.0f;
        caliber = CCB_CALIBER_ENERGY;
        if (sync_shot) {
            delay_ms = st.active_shot_delay_ms;
            shot_idx = st.active_shot_index;
            st.active_tracer_emitted = true;
        }
    } else if (e.light == explosion_lights::beam_lightning) {
        kind = CCB_VFX_BEAM_LIGHTNING;
        rgba = 0xFFFFE290u; // Arc lightning blue-white
        radius = 8.5f;
        light_i = 22.0f;
        caliber = CCB_CALIBER_ENERGY;
        if (sync_shot) {
            delay_ms = st.active_shot_delay_ms;
            shot_idx = st.active_shot_index;
            st.active_tracer_emitted = true;
        }
    } else if (e.light == explosion_lights::impact_spark) {
        kind = CCB_VFX_IMPACT_SPARK;
        rgba = 0xFF50C8FFu; // Metallic ricochet spark
        radius = 4.0f;
        light_i = 9.0f;
        if (sync_shot) {
            delay_ms = static_cast<uint16_t>(std::min<int>(6500, static_cast<int>(st.active_shot_delay_ms) + 26));
            caliber = st.active_gun_caliber;
            shot_idx = st.active_shot_index;
        }
    } else if (e.light == explosion_lights::flashbang_blast) {
        kind = CCB_VFX_FLASHBANG;
        rgba = 0xFFF8FCFFu; // Blinding white flash
        radius = std::max(7.0f, static_cast<float>(e.radius) * 1.5f);
        light_i = 42.0f;
    } else if (e.light == explosion_lights::emp_blast) {
        kind = CCB_VFX_EMP;
        rgba = 0xFFFF9868u; // Blue-violet EMP pulse
        radius = std::max(5.0f, static_cast<float>(e.radius) * 1.4f);
        light_i = 24.0f;
    } else {
        // Generic explosion / spell blast / cone: sample recipe's primary color when valid
        kind = CCB_VFX_BLAST;
        flags |= CCB_VFX_FLAG_FIERY;
        if (e.light.is_valid()) {
            const explosion_light &rec = e.light.obj();
            rgba = static_cast<uint32_t>(rec.color_a[0])
                 | (static_cast<uint32_t>(rec.color_a[1]) << 8)
                 | (static_cast<uint32_t>(rec.color_a[2]) << 16)
                 | (0xFFu << 24);
        }
        radius = std::max(3.5f, static_cast<float>(std::max(e.radius, e.range)));
        light_i = std::clamp(16.0f + radius * 3.8f, 20.0f, 52.0f);
    }

    int ox = e.origin.x();
    int oy = e.origin.y();
    int tx = e.target.x();
    int ty = e.target.y();

    // For muzzle flashes, ranged.cpp nudges e.origin 1 tile toward the aim and sets e.target == e.origin.
    // Recover shooter direction from the avatar or adjacent creature so the muzzle flash plume aims forward!
    if (kind == CCB_VFX_MUZZLE_FLASH && ox == tx && oy == ty && g != nullptr) {
        const tripoint_bub_ms av = get_avatar().pos_bub();
        if (av.z() == e.origin.z() && std::abs(av.x() - ox) <= 1 && std::abs(av.y() - oy) <= 1 && (av.x() != ox || av.y() != oy)) {
            tx = ox + (ox - av.x()) * 3;
            ty = oy + (oy - av.y()) * 3;
        } else {
            const creature_tracker &ct = get_creature_tracker();
            for (int dy = -1; dy <= 1; ++dy) {
                for (int dx = -1; dx <= 1; ++dx) {
                    if (dx == 0 && dy == 0) continue;
                    if (ct.creature_at(tripoint_bub_ms(ox + dx, oy + dy, e.origin.z())) != nullptr) {
                        tx = ox - dx * 3;
                        ty = oy - dy * 3;
                        break;
                    }
                }
            }
        }
    }

    st.push_vfx_event(
        kind,
        ox, oy,
        tx, ty,
        e.origin.z(),
        radius, light_i, rgba,
        static_cast<uint16_t>(std::clamp(e.arc_degrees, 0, 360)),
        delay_ms,
        caliber,
        shot_idx,
        flags
    );
    // Publish immediately so Godot starts the 60fps muzzle flash, tracer, blast & GPU point light with 0ms lag!
    st.publish_frame();
}
