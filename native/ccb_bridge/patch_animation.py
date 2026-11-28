#!/usr/bin/env python3
"""Generates patched animation_bridge.cpp out-of-tree from upstream CCB src/animation.cpp (zero upstream edits)."""
import re
import sys
from pathlib import Path

src_path = Path(sys.argv[1])
dst_path = Path(sys.argv[2])
text = src_path.read_text(encoding="utf-8")

def replace_exact(src: str, old: str, new: str, label: str) -> str:
    if old not in src:
        raise RuntimeError(f"patch_animation.py: failed to find anchor [{label}] in {src_path}")
    return src.replace(old, new, 1)

# 1. Include bridge_state.hpp & bridge_tileset_options.hpp
text = replace_exact(
    text,
    '#include "animation.h"\n',
    '#include "animation.h"\n#include "bridge_state.hpp"\n#include "bridge_tileset_options.hpp"\n#include <cmath>\n',
    "include_bridge_headers",
)

# 2. Hook explosion_handler::draw_explosion in !TILES branch -> emit photorealistic GPU VFX without legacy ASCII sleep!
text = replace_exact(
    text,
    """#else
void explosion_handler::draw_explosion( const tripoint_bub_ms &p, const int r, const nc_color &col )
{
    draw_explosion_curses( *g, p, r, col );
}
#endif""",
    """#else
static uint32_t ccb_nc_color_to_blast_rgba( const nc_color &col )
{
    if( col == c_blue || col == c_light_blue ) {
        return 0xFFFF9850u; // electric/shockwave blue
    }
    if( col == c_cyan || col == c_light_cyan ) {
        return 0xFFFFE068u; // plasma/EMP cyan
    }
    if( col == c_green || col == c_light_green ) {
        return 0xFF44E870u; // acid/bio green
    }
    if( col == c_magenta || col == c_pink ) {
        return 0xFFD858FFu; // arcane/nether magenta
    }
    if( col == c_white ) {
        return 0xFFF2F8FFu; // blinding white flash
    }
    return 0xFF3890FFu; // R=255, G=144, B=56 fiery explosive orange
}

void explosion_handler::draw_explosion( const tripoint_bub_ms &p, const int r, const nc_color &col )
{
    if( test_mode ) {
        return;
    }
    if( ccb_bridge::get_active_tileset_config().use_tiles ) {
        const float rad = std::max( 1.5f, static_cast<float>( r ) );
        const uint32_t rgba = ccb_nc_color_to_blast_rgba( col );
        const bool fiery = ( col != c_blue && col != c_light_blue && col != c_cyan && col != c_light_cyan && col != c_green && col != c_light_green );
        uint8_t flags = fiery ? CCB_VFX_FLAG_FIERY : 0u;
        if( g != nullptr && !get_map().is_outside( p ) ) {
            flags |= CCB_VFX_FLAG_INDOORS;
        }
        auto &st = ccb_bridge::state();
        st.push_vfx_event(
            CCB_VFX_BLAST,
            p.x(), p.y(), p.x(), p.y(), p.z(),
            rad, std::clamp( 18.0f + rad * 4.5f, 22.0f, 56.0f ),
            rgba, 360, 0, CCB_CALIBER_HEAVY, 0, flags
        );
        st.publish_frame();
        return;
    }
    draw_explosion_curses( *g, p, r, col );
}
#endif""",
    "draw_explosion_hook",
)

# 3. Hook explosion_handler::draw_custom_explosion in !TILES branch -> emit photorealistic blast with exact epicenter & radius!
text = replace_exact(
    text,
    """#else
    ( void )light_effect;
    ( void )epicenter;
    ( void )circular_shockwave;
    ( void )shock_target;
    ( void )arc_degrees;
#endif""",
    """#else
    if( ccb_bridge::get_active_tileset_config().use_tiles && !all_area.empty() ) {
        avatar &pc = get_avatar();
        const int target_z = epicenter.has_value() ? epicenter->z() : pc.posz();
        double sum_x = 0.0;
        double sum_y = 0.0;
        int cnt = 0;
        for( const auto &pr : all_area ) {
            if( pr.first.z() == target_z ) {
                sum_x += pr.first.x();
                sum_y += pr.first.y();
                ++cnt;
            }
        }
        if( cnt > 0 ) {
            const int cx = epicenter.has_value() ? epicenter->x() : static_cast<int>( std::lround( sum_x / cnt ) );
            const int cy = epicenter.has_value() ? epicenter->y() : static_cast<int>( std::lround( sum_y / cnt ) );
            float max_r = 1.5f;
            for( const auto &pr : all_area ) {
                if( pr.first.z() != target_z ) {
                    continue;
                }
                const float d = std::hypot( static_cast<float>( pr.first.x() - cx ), static_cast<float>( pr.first.y() - cy ) );
                if( d > max_r ) {
                    max_r = d;
                }
            }
            uint8_t kind = CCB_VFX_BLAST;
            uint32_t rgba = 0xFF3892FFu; // fiery explosion orange
            uint8_t flags = CCB_VFX_FLAG_FIERY;
            if( light_effect == explosion_lights::flashbang_blast ) {
                kind = CCB_VFX_FLASHBANG;
                rgba = 0xFFF8FCFFu;
                flags = 0u;
            } else if( light_effect == explosion_lights::emp_blast ) {
                kind = CCB_VFX_EMP;
                rgba = 0xFFFF9868u;
                flags = 0u;
            } else if( light_effect.is_valid() ) {
                const explosion_light &rec = light_effect.obj();
                rgba = static_cast<uint32_t>( rec.color_a[0] )
                     | ( static_cast<uint32_t>( rec.color_a[1] ) << 8 )
                     | ( static_cast<uint32_t>( rec.color_a[2] ) << 16 )
                     | ( 0xFFu << 24 );
            } else {
                const auto it_c = all_area.find( tripoint_bub_ms( cx, cy, target_z ) );
                if( it_c != all_area.end() ) {
                    rgba = ccb_nc_color_to_blast_rgba( it_c->second );
                }
            }
            if( g != nullptr && !get_map().is_outside( tripoint_bub_ms( cx, cy, target_z ) ) ) {
                flags |= CCB_VFX_FLAG_INDOORS;
            }
            const int tx = shock_target.has_value() ? shock_target->x() : cx;
            const int ty = shock_target.has_value() ? shock_target->y() : cy;
            auto &st = ccb_bridge::state();
            st.push_vfx_event(
                kind, cx, cy, tx, ty, target_z,
                max_r, std::clamp( 20.0f + max_r * 4.5f, 24.0f, 60.0f ),
                rgba, static_cast<uint16_t>( std::clamp( arc_degrees, 0.0, 360.0 ) ),
                0, CCB_CALIBER_HEAVY, 0, flags
            );
            st.publish_frame();
            return;
        }
    }
    ( void )circular_shockwave;
#endif""",
    "draw_custom_explosion_hook",
)

# 4. In tiles mode, don't let draw_bullet_curses / draw_bullet_line block the worker thread during burst gunfire!
text = replace_exact(
    text,
    """#else
void game::draw_bullet( const tripoint_bub_ms &t, const int i,
                        const std::vector<tripoint_bub_ms> &trajectory,
                        const char bullet, std::string_view /*custom_sprite*/ )
{
    draw_bullet_curses( m, t, bullet, &trajectory[i] );
}
#endif""",
    """#else
void game::draw_bullet( const tripoint_bub_ms &t, const int i,
                        const std::vector<tripoint_bub_ms> &trajectory,
                        const char bullet, std::string_view /*custom_sprite*/ )
{
    if( ccb_bridge::get_active_tileset_config().use_tiles ) {
        // GPU tracer VFX handles projectiles asynchronously at 60fps synced to burst RPM!
        if( i == static_cast<int>( trajectory.size() ) - 1 && trajectory.size() >= 2 ) {
            auto &st = ccb_bridge::state();
            if( !st.active_tracer_emitted ) {
                const uint16_t delay_ms = st.has_recent_shot_context() ? st.active_shot_delay_ms : 0u;
                const uint8_t cal = st.has_recent_shot_context() ? st.active_gun_caliber : CCB_CALIBER_DEFAULT;
                const uint8_t sidx = st.has_recent_shot_context() ? st.active_shot_index : 0u;
                const uint32_t col = ( bullet == '#' ) ? 0xFF3888FFu : 0xFF88DCFFu;
                st.push_vfx_event(
                    CCB_VFX_TRACER,
                    trajectory.front().x(), trajectory.front().y(),
                    trajectory.back().x(), trajectory.back().y(),
                    t.z(), 2.8f, 5.5f, col, 0, delay_ms, cal, sidx, 0
                );
                st.active_tracer_emitted = true;
                st.publish_frame();
            }
        }
        return;
    }
    draw_bullet_curses( m, t, bullet, &trajectory[i] );
}
#endif""",
    "draw_bullet_hook",
)

m_dbl = re.search(
    r"#else\s*\nvoid game::draw_bullet_line\(\s*const std::vector<tripoint_bub_ms>\s*&trajectory,\s*const char\s*/\*bullet\*/,\s*\n\s*std::string_view\s*/\*custom_sprite\*/\s*\)\s*\n\{\s*\n\s*if\(\s*trajectory\.size\(\)\s*<\s*2\s*\)\s*\{\s*\n\s*return;\s*\n\s*\}",
    text,
)
if not m_dbl:
    raise RuntimeError(f"patch_animation.py: failed to find anchor [draw_bullet_line_hook] in {src_path}")
text = text[:m_dbl.start()] + """#else
void game::draw_bullet_line( const std::vector<tripoint_bub_ms> &trajectory, const char bullet,
                             std::string_view /*custom_sprite*/ )
{
    if( trajectory.size() < 2 ) {
        return;
    }
    if( ccb_bridge::get_active_tileset_config().use_tiles ) {
        auto &st = ccb_bridge::state();
        if( !st.active_tracer_emitted ) {
            const uint16_t delay_ms = st.has_recent_shot_context() ? st.active_shot_delay_ms : 0u;
            const uint8_t cal = st.has_recent_shot_context() ? st.active_gun_caliber : CCB_CALIBER_DEFAULT;
            const uint8_t sidx = st.has_recent_shot_context() ? st.active_shot_index : 0u;
            const uint32_t col = ( bullet == '#' ) ? 0xFF3888FFu : 0xFF88DCFFu;
            st.push_vfx_event(
                CCB_VFX_TRACER,
                trajectory.front().x(), trajectory.front().y(),
                trajectory.back().x(), trajectory.back().y(),
                trajectory.front().z(), 2.8f, 5.5f, col, 0, delay_ms, cal, sidx, 0
            );
            st.active_tracer_emitted = true;
            st.publish_frame();
        }
        return;
    }""" + text[m_dbl.end():]

dst_path.parent.mkdir(parents=True, exist_ok=True)
if not dst_path.exists() or dst_path.read_text(encoding="utf-8") != text:
    dst_path.write_text(text, encoding="utf-8")
