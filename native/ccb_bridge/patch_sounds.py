#!/usr/bin/env python3
"""Generates patched sounds_bridge.cpp out-of-tree from upstream CCB src/sounds.cpp (zero upstream edits)."""
import sys
from pathlib import Path

src_path = Path(sys.argv[1])
dst_path = Path(sys.argv[2])
text = src_path.read_text(encoding="utf-8")

def replace_exact(src: str, old: str, new: str, label: str) -> str:
    if old not in src:
        raise RuntimeError(f"patch_sounds.py: failed to find anchor [{label}] in {src_path}")
    return src.replace(old, new, 1)

# 1. Include bridge_state.hpp right after sounds.h
text = replace_exact(
    text,
    '#include "sounds.h"\n',
    '#include "sounds.h"\n#include "bridge_state.hpp"\n',
    "include_bridge_state",
)

# 2. Emit real-time audio events directly from sounds::sound() for explosions, flashbangs, shockwaves, doors, smashes
text = replace_exact(
    text,
    """    sounds_since_last_turn.emplace_back( absolute,
                                         sound_event{ vol, category, description, ambient,
                                                 false, id, variant, seas_str } );
}""",
    """    sounds_since_last_turn.emplace_back( absolute,
                                         sound_event{ vol, category, description, ambient,
                                                 false, id, variant, seas_str } );

    if( !test_mode && !ambient && vol > 0 && g != nullptr && !id.empty() ) {
        const Character &pc = get_player_character();
        const tripoint_bub_ms ppos = pc.pos_bub();
        const int dist = sound_distance( ppos, p );
        const float dx = static_cast<float>( p.x() - ppos.x() );
        const float pan = std::clamp( dx / 18.0f, -0.95f, 0.95f );
        const bool indoors = !get_map().is_outside( ppos );
        uint8_t aflags = indoors ? CCB_AUDIO_FLAG_INDOORS : 0u;
        if( dist > 18 ) {
            aflags |= CCB_AUDIO_FLAG_DISTANT;
        }
        auto &st = ccb_bridge::state();
        if( id == "explosion" ) {
            uint8_t sub = CCB_EXPL_MEDIUM;
            if( variant == "huge" || vol >= 60 ) {
                sub = CCB_EXPL_HUGE;
            } else if( variant == "small" || vol < 12 ) {
                sub = CCB_EXPL_SMALL;
            }
            const float gain = std::clamp( 1.05f - static_cast<float>( dist ) / std::max( 28.0f, static_cast<float>( vol ) * 0.7f ), 0.14f, 1.0f );
            st.push_audio_event( CCB_SFX_EXPLOSION, sub, p.x(), p.y(), p.z(), gain, pan, static_cast<float>( vol ), 0, 0, 0, 0, aflags );
        } else if( id == "misc" && variant == "flashbang" ) {
            const float gain = std::clamp( 1.0f - static_cast<float>( dist ) / 32.0f, 0.15f, 1.0f );
            st.push_audio_event( CCB_SFX_EXPLOSION, CCB_EXPL_FLASHBANG, p.x(), p.y(), p.z(), gain, pan, 12.0f, 0, 0, 0, 0, aflags );
        } else if( id == "misc" && variant == "shockwave" ) {
            const float gain = std::clamp( 1.0f - static_cast<float>( dist ) / 32.0f, 0.15f, 1.0f );
            st.push_audio_event( CCB_SFX_EXPLOSION, CCB_EXPL_SHOCKWAVE, p.x(), p.y(), p.z(), gain, pan, 10.0f, 0, 0, 0, 0, aflags );
        } else if( id == "smash_success" || id == "bash" ) {
            const float gain = std::clamp( 0.85f - static_cast<float>( dist ) / 24.0f, 0.08f, 0.85f );
            if( dist <= 22 ) {
                st.push_audio_event( CCB_SFX_VARIANT, CCB_VAR_SMASH, p.x(), p.y(), p.z(), gain, pan, static_cast<float>( vol ), 0, 0, 0, 0, aflags );
            }
        } else if( id == "open_door" || id == "close_door" ) {
            if( dist <= 14 ) {
                const float gain = std::clamp( 0.65f - static_cast<float>( dist ) / 18.0f, 0.08f, 0.65f );
                st.push_audio_event( CCB_SFX_VARIANT, CCB_VAR_DOOR, p.x(), p.y(), p.z(), gain, pan, 6.0f, 0, 0, 0, 0, aflags );
            }
        }
    }
}""",
    "sounds_sound_hook",
)

# 3. Replace the no-op !SDL_SOUND sfx::* stubs with real bridge audio + burst synchronization hooks!
old_stubs = """void sfx::play_variant_sound( std::string_view, std::string_view, int, units::angle, double,
                              double ) { }
void sfx::play_variant_sound( std::string_view, std::string_view, int ) { }
void sfx::play_ambient_variant_sound( std::string_view, std::string_view, int, channel, int,
                                      double, int ) { }
void sfx::play_activity_sound( std::string_view, std::string_view, int ) { }
void sfx::end_activity_sounds() { }
void sfx::generate_gun_sound( const Character &, const item &, int, int,
                              std::chrono::steady_clock::time_point ) { }
void sfx::generate_melee_sound( const item &, const tripoint_bub_ms &, const tripoint_bub_ms &,
                                bool, bool,
                                std::string_view ) { }
void sfx::do_hearing_loss( int ) { }
void sfx::remove_hearing_loss() { }
void sfx::do_projectile_hit( const Creature & ) { }
void sfx::do_footstep( const Character & ) { }"""

new_hooks = """namespace {
void ccb_emit_variant_sfx( std::string_view id, std::string_view variant, int volume, float pan )
{
    if( test_mode || g == nullptr || volume <= 0 ) {
        return;
    }
    const Character &pc = get_player_character();
    const tripoint_bub_ms ppos = pc.pos_bub();
    const bool indoors = !get_map().is_outside( ppos );
    const uint8_t aflags = indoors ? CCB_AUDIO_FLAG_INDOORS : 0u;
    const float gain = std::clamp( static_cast<float>( volume ) / 100.0f, 0.12f, 1.0f );
    auto &st = ccb_bridge::state();

    if( id == "explosion" ) {
        uint8_t sub = ( variant == "huge" ) ? CCB_EXPL_HUGE : ( variant == "small" ? CCB_EXPL_SMALL : CCB_EXPL_MEDIUM );
        st.push_audio_event( CCB_SFX_EXPLOSION, sub, ppos.x(), ppos.y(), ppos.z(), gain, pan, 16.0f, 0, 0, 0, 0, aflags );
    } else if( id == "reload" || id == "reload_gun" || variant == "reload" ) {
        st.push_audio_event( CCB_SFX_VARIANT, CCB_VAR_RELOAD, ppos.x(), ppos.y(), ppos.z(), gain * 0.72f, pan, 4.0f, 0, 0, 0, 0, aflags );
    } else if( id == "smash_success" || id == "bash" || id == "bash_default" ) {
        st.push_audio_event( CCB_SFX_VARIANT, CCB_VAR_SMASH, ppos.x(), ppos.y(), ppos.z(), gain * 0.78f, pan, 8.0f, 0, 0, 0, 0, aflags );
    } else if( id == "open_door" || id == "close_door" ) {
        st.push_audio_event( CCB_SFX_VARIANT, CCB_VAR_DOOR, ppos.x(), ppos.y(), ppos.z(), gain * 0.62f, pan, 5.0f, 0, 0, 0, 0, aflags );
    } else if( id == "misc" && variant == "flashbang" ) {
        st.push_audio_event( CCB_SFX_EXPLOSION, CCB_EXPL_FLASHBANG, ppos.x(), ppos.y(), ppos.z(), gain, pan, 12.0f, 0, 0, 0, 0, aflags );
    } else if( id == "misc" && variant == "shockwave" ) {
        st.push_audio_event( CCB_SFX_EXPLOSION, CCB_EXPL_SHOCKWAVE, ppos.x(), ppos.y(), ppos.z(), gain, pan, 10.0f, 0, 0, 0, 0, aflags );
    }
}
} // namespace

void sfx::play_variant_sound( std::string_view id, std::string_view variant, int volume, units::angle angle, double,
                              double )
{
    const float rad = static_cast<float>( units::to_radians( angle ) );
    const float pan = std::clamp( std::sin( rad ), -0.95f, 0.95f );
    ccb_emit_variant_sfx( id, variant, volume, pan );
}
void sfx::play_variant_sound( std::string_view id, std::string_view variant, int volume )
{
    ccb_emit_variant_sfx( id, variant, volume, 0.0f );
}
void sfx::play_ambient_variant_sound( std::string_view, std::string_view, int, channel, int,
                                      double, int ) { }
void sfx::play_activity_sound( std::string_view, std::string_view, int ) { }
void sfx::end_activity_sounds() { }

void sfx::generate_gun_sound( const Character &source_arg, const item &firing, int rpm,
                              int shot_index, std::chrono::steady_clock::time_point burst_start )
{
    if( test_mode || g == nullptr ) {
        return;
    }
    const Character &pc = get_player_character();
    const tripoint_bub_ms src = source_arg.pos_bub();
    const tripoint_bub_ms ppos = pc.pos_bub();
    const int dist = sound_distance( ppos, src );
    const bool indoors = !get_map().is_outside( ppos );
    const float pan = ( src == ppos ) ? 0.0f : std::clamp( static_cast<float>( src.x() - ppos.x() ) / 18.0f, -0.95f, 0.95f );

    const std::string skill_s = firing.gun_skill().str();
    const std::string gun_s = firing.typeId().str();
    const ammotype atype = firing.loaded_ammo().ammo_type();
    const std::string ammo_s = atype.is_null() ? std::string() : atype.str();

    bool suppressed = false;
    if( skill_s != "archery" ) {
        const auto mods = firing.gunmods();
        for( const item *gm : mods ) {
            if( gm && gm->type && gm->type->gunmod && gm->type->gunmod->loudness_multiplier < 0.85f ) {
                suppressed = true;
                break;
            }
        }
        if( gun_s.find( "silenc" ) != std::string::npos || gun_s.find( "suppress" ) != std::string::npos ||
            gun_s.find( "mp5sd" ) != std::string::npos || gun_s.find( "vss" ) != std::string::npos ||
            gun_s.find( "val" ) != std::string::npos ) {
            suppressed = true;
        }
    }

    auto has_ci = []( const std::string &hay, const char *needle ) {
        return hay.find( needle ) != std::string::npos;
    };

    uint8_t sub = CCB_GUN_RIFLE;
    uint8_t cal = CCB_CALIBER_RIFLE;
    bool has_casing = true;

    if( skill_s == "archery" || has_ci( gun_s, "bow" ) || has_ci( gun_s, "sling" ) ) {
        sub = CCB_GUN_BOW;
        cal = CCB_CALIBER_SUPPRESSED;
        has_casing = false;
    } else if( has_ci( gun_s, "flamethrower" ) || ammo_s == "flammable" ) {
        sub = CCB_GUN_FLAMETHROWER;
        cal = CCB_CALIBER_SHOTGUN;
        has_casing = false;
    } else if( skill_s == "launcher" || has_ci( ammo_s, "40x" ) || has_ci( ammo_s, "66mm" ) ||
               has_ci( ammo_s, "rpg" ) || has_ci( ammo_s, "atgm" ) || has_ci( ammo_s, "rocket" ) ) {
        sub = CCB_GUN_LAUNCHER;
        cal = CCB_CALIBER_HEAVY;
        has_casing = false;
    } else if( has_ci( gun_s, "plasma" ) || has_ci( ammo_s, "plasma" ) ) {
        sub = CCB_GUN_PLASMA;
        cal = CCB_CALIBER_ENERGY;
        has_casing = false;
    } else if( has_ci( gun_s, "laser" ) || has_ci( ammo_s, "laser" ) || has_ci( gun_s, "v29" ) || has_ci( gun_s, "a7" ) ) {
        sub = CCB_GUN_LASER;
        cal = CCB_CALIBER_ENERGY;
        has_casing = false;
    } else if( has_ci( gun_s, "lightning" ) || has_ci( gun_s, "tesla" ) || has_ci( gun_s, "tazer" ) || has_ci( gun_s, "rail" ) ) {
        sub = CCB_GUN_LIGHTNING;
        cal = CCB_CALIBER_ENERGY;
        has_casing = false;
    } else if( skill_s == "shotgun" || has_ci( ammo_s, "shot" ) ) {
        sub = CCB_GUN_SHOTGUN;
        cal = CCB_CALIBER_SHOTGUN;
    } else if( has_ci( ammo_s, "50bmg" ) || has_ci( ammo_s, "20x" ) || has_ci( ammo_s, "30mm" ) ||
               has_ci( ammo_s, "120mm" ) || has_ci( gun_s, "barrett" ) || has_ci( gun_s, "m2browning" ) ||
               has_ci( gun_s, "browning" ) || has_ci( gun_s, "minigun" ) || has_ci( ammo_s, "338" ) ) {
        sub = CCB_GUN_HEAVY;
        cal = CCB_CALIBER_HEAVY;
    } else if( skill_s == "smg" ) {
        sub = CCB_GUN_SMG;
        cal = CCB_CALIBER_PISTOL;
    } else if( skill_s == "pistol" ) {
        sub = CCB_GUN_PISTOL;
        cal = CCB_CALIBER_PISTOL;
        if( has_ci( gun_s, "revolver" ) || has_ci( gun_s, "sw_" ) || has_ci( gun_s, "colt_saa" ) || has_ci( gun_s, "ruger_redhawk" ) ) {
            has_casing = false;
        }
    } else {
        sub = CCB_GUN_RIFLE;
        cal = CCB_CALIBER_RIFLE;
    }

    if( suppressed && sub != CCB_GUN_BOW && sub != CCB_GUN_LASER && sub != CCB_GUN_PLASMA && sub != CCB_GUN_LIGHTNING ) {
        sub = CCB_GUN_SUPPRESSED;
        cal = CCB_CALIBER_SUPPRESSED;
    }

    auto &st = ccb_bridge::state();
    const auto now_tp = std::chrono::steady_clock::now();
    const bool continuing_burst =
        ( shot_index > 0 ) &&
        ( st.active_burst_id != 0 ) &&
        ( ( rpm > 0 && burst_start == st.active_burst_origin_tp ) ||
          ( now_tp - st.active_shot_wall_tp <= std::chrono::milliseconds( 450 ) ) );

    uint64_t burst_id = st.active_burst_id;
    int eff_shot_idx = 0;
    if( !continuing_burst ) {
        burst_id = st.next_burst_id.fetch_add( 1, std::memory_order_relaxed );
        eff_shot_idx = 0;
        st.active_burst_id = burst_id;
        st.active_burst_origin_tp = burst_start;
    } else {
        eff_shot_idx = std::max<int>( shot_index, static_cast<int>( st.active_shot_index ) + 1 );
    }

    int eff_rpm = rpm;
    if( eff_rpm <= 0 ) {
        switch( sub ) {
            case CCB_GUN_SMG:     eff_rpm = 820; break;
            case CCB_GUN_RIFLE:   eff_rpm = 700; break;
            case CCB_GUN_HEAVY:   eff_rpm = 520; break;
            case CCB_GUN_PISTOL:  eff_rpm = 400; break;
            case CCB_GUN_SHOTGUN: eff_rpm = 200; break;
            default:              eff_rpm = 600; break;
        }
    } else {
        eff_rpm = std::clamp( eff_rpm, 90, 1500 );
    }

    const int interval_ms = std::clamp( 60000 / eff_rpm, 42, 260 );
    const uint16_t delay_ms = static_cast<uint16_t>( std::min( eff_shot_idx * interval_ms, 6500 ) );

    uint8_t aflags = 0;
    if( indoors ) aflags |= CCB_AUDIO_FLAG_INDOORS;
    if( dist > 16 ) aflags |= CCB_AUDIO_FLAG_DISTANT;
    if( suppressed ) aflags |= CCB_AUDIO_FLAG_SUPPRESSED;
    if( has_casing && src == ppos ) aflags |= CCB_AUDIO_FLAG_HAS_CASING;

    // Store synchronized burst state so make_gun_flash_effect() and projectile_attack() match 1:1!
    st.active_shot_delay_ms = delay_ms;
    st.active_shot_rpm = static_cast<uint16_t>( eff_rpm );
    st.active_shot_index = static_cast<uint8_t>( std::min( eff_shot_idx, 255 ) );
    st.active_gun_caliber = cal;
    st.active_vfx_flags = indoors ? CCB_VFX_FLAG_INDOORS : 0u;
    st.active_tracer_emitted = false;
    st.active_shot_wall_tp = now_tp;

    const float gain = ( src == ppos )
        ? 1.0f
        : std::clamp( 1.0f - static_cast<float>( dist ) / 34.0f, 0.14f, 0.92f );

    st.push_audio_event(
        CCB_SFX_GUNSHOT, sub,
        src.x(), src.y(), src.z(),
        gain, pan, static_cast<float>( eff_rpm ),
        burst_id, static_cast<uint16_t>( eff_rpm ), delay_ms,
        st.active_shot_index, aflags
    );
}

void sfx::generate_melee_sound( const item &weapon, const tripoint_bub_ms &source,
                                const tripoint_bub_ms &target, bool hit, bool targ_mon,
                                std::string_view material )
{
    if( test_mode || g == nullptr ) {
        return;
    }
    const Character &pc = get_player_character();
    const tripoint_bub_ms ppos = pc.pos_bub();
    const int dist = sound_distance( ppos, source );
    if( dist > 16 ) {
        return;
    }
    const bool indoors = !get_map().is_outside( ppos );
    const uint8_t aflags = indoors ? CCB_AUDIO_FLAG_INDOORS : 0u;
    const float pan = std::clamp( static_cast<float>( target.x() - ppos.x() ) / 14.0f, -0.95f, 0.95f );
    const float gain = std::clamp( 0.85f - static_cast<float>( dist ) / 20.0f, 0.12f, 0.85f );
    auto &st = ccb_bridge::state();
    const float weight_hint = weapon.is_null() ? 1.0f : static_cast<float>( std::clamp<int>( weapon.volume() / 250_ml, 1, 12 ) );
    st.push_audio_event( CCB_SFX_MELEE, CCB_MELEE_SWING, source.x(), source.y(), source.z(), gain * 0.65f, pan, weight_hint, 0, 0, 0, 0, aflags );
    if( hit ) {
        const uint8_t hit_sub = ( targ_mon && material == "steel" ) ? CCB_MELEE_HIT_METAL : CCB_MELEE_HIT_FLESH;
        st.push_audio_event( CCB_SFX_MELEE, hit_sub, target.x(), target.y(), target.z(), gain, pan, weight_hint, 0, 0, 38, 0, aflags );
    }
}

void sfx::do_hearing_loss( int ) { }
void sfx::remove_hearing_loss() { }

void sfx::do_projectile_hit( const Creature &target )
{
    if( test_mode || g == nullptr ) {
        return;
    }
    const Character &pc = get_player_character();
    const tripoint_bub_ms ppos = pc.pos_bub();
    const tripoint_bub_ms tpos = target.pos_bub();
    const int dist = sound_distance( ppos, tpos );
    if( dist > 26 ) {
        return;
    }
    static const material_id ccb_mat_steel( "steel" );
    static const material_id ccb_mat_stone( "stone" );
    uint8_t sub = CCB_HIT_FLESH;
    if( target.is_monster() ) {
        const monster &mon = dynamic_cast<const monster &>( target );
        if( mon.made_of( ccb_mat_steel ) ) {
            sub = CCB_HIT_METAL;
        } else if( mon.made_of( ccb_mat_stone ) ) {
            sub = CCB_HIT_WALL;
        }
    }
    auto &st = ccb_bridge::state();
    const uint16_t delay_ms = st.has_recent_shot_context()
        ? static_cast<uint16_t>( std::min<int>( 6500, static_cast<int>( st.active_shot_delay_ms ) + 28 ) )
        : 0u;
    const float pan = std::clamp( static_cast<float>( tpos.x() - ppos.x() ) / 18.0f, -0.95f, 0.95f );
    const float gain = std::clamp( 0.82f - static_cast<float>( dist ) / 28.0f, 0.12f, 0.82f );
    const uint8_t aflags = !get_map().is_outside( ppos ) ? CCB_AUDIO_FLAG_INDOORS : 0u;
    st.push_audio_event( CCB_SFX_PROJECTILE_HIT, sub, tpos.x(), tpos.y(), tpos.z(), gain, pan, 4.0f, st.active_burst_id, 0, delay_ms, st.active_shot_index, aflags );
}

void sfx::do_footstep( const Character &ch )
{
    if( test_mode || g == nullptr ) {
        return;
    }
    const Character &pc = get_player_character();
    if( &ch != &pc ) {
        return;
    }
    const tripoint_bub_ms ppos = pc.pos_bub();
    const bool indoors = !get_map().is_outside( ppos );
    ccb_bridge::state().push_audio_event( CCB_SFX_FOOTSTEP, 1u, ppos.x(), ppos.y(), ppos.z(), 0.28f, 0.0f, 1.0f, 0, 0, 0, 0, indoors ? CCB_AUDIO_FLAG_INDOORS : 0u );
}"""

text = replace_exact(text, old_stubs, new_hooks, "sfx_headless_hooks")

dst_path.parent.mkdir(parents=True, exist_ok=True)
if not dst_path.exists() or dst_path.read_text(encoding="utf-8") != text:
    dst_path.write_text(text, encoding="utf-8")
