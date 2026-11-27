#include "ccb_engine_gd.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cstring>
#include <string>

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

namespace cangling {

namespace {

struct BridgeFuncs {
#if defined(_WIN32)
    HMODULE module = nullptr;
#endif
    int (*ccb_start)(const char *, const char *, int, int) = nullptr;
    void (*ccb_shutdown)(void) = nullptr;
    int (*ccb_is_running)(void) = nullptr;
    int (*ccb_is_waiting_resume)(void) = nullptr;
    void (*ccb_resume_session)(void) = nullptr;
    int (*ccb_get_status_message)(char *, int) = nullptr;
    void (*ccb_push_key)(int, const char *, int, int, int) = nullptr;
    void (*ccb_push_mouse)(int, int, int, int) = nullptr;
    void (*ccb_push_resize)(int, int) = nullptr;
    uint64_t (*ccb_get_generation)(void) = nullptr;
    int (*ccb_copy_terminal_frame)(CcbTermHeader *, CcbTermCell *, int) = nullptr;
    int (*ccb_copy_world_snapshot)(
        CcbWorldHeader *, CcbWorldTile *, int, char *, int,
        CcbWorldCreature *, int, CcbWorldLight *, int,
        char *, int, uint8_t *, int) = nullptr;
    int (*ccb_copy_world_effects)(CcbWorldPathPoint *, int, CcbWorldSct *, int) = nullptr;
    int (*ccb_get_tileset_config)(char *, int, char *, int, char *, int, int *) = nullptr;
    int (*ccb_copy_looks_like_table)(char *, int) = nullptr;
    bool loaded = false;
};

BridgeFuncs g_bridge;

template<typename Fn>
bool resolve_sym(
#if defined(_WIN32)
    HMODULE mod,
#endif
    const char *name, Fn &out) {
#if defined(_WIN32)
    out = reinterpret_cast<Fn>(GetProcAddress(mod, name));
    return out != nullptr;
#else
    (void)name;
    out = nullptr;
    return false;
#endif
}

static void anchor_for_module_lookup() {}

bool ensure_bridge_loaded(std::string &err_out) {
    if (g_bridge.loaded) {
        return true;
    }
#if defined(_WIN32)
    HMODULE self_mod = nullptr;
    if (!GetModuleHandleExW(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            reinterpret_cast<LPCWSTR>(&anchor_for_module_lookup),
            &self_mod)) {
        err_out = "GetModuleHandleExW failed for cangling.dll";
        return false;
    }
    wchar_t path_buf[MAX_PATH * 4] = {};
    DWORD len = GetModuleFileNameW(self_mod, path_buf, MAX_PATH * 4);
    if (len == 0) {
        err_out = "GetModuleFileNameW failed";
        return false;
    }
    std::wstring dll_path(path_buf, len);
    const size_t slash = dll_path.find_last_of(L"\\/");
    if (slash != std::wstring::npos) {
        dll_path = dll_path.substr(0, slash + 1) + L"ccb_bridge.dll";
    } else {
        dll_path = L"ccb_bridge.dll";
    }

    HMODULE mod = LoadLibraryExW(dll_path.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!mod) {
        DWORD code = GetLastError();
        err_out = "LoadLibraryW(ccb_bridge.dll) failed, Win32 error=" + std::to_string(code);
        return false;
    }

    bool ok = true;
    ok &= resolve_sym(mod, "ccb_start", g_bridge.ccb_start);
    ok &= resolve_sym(mod, "ccb_shutdown", g_bridge.ccb_shutdown);
    ok &= resolve_sym(mod, "ccb_is_running", g_bridge.ccb_is_running);
    ok &= resolve_sym(mod, "ccb_is_waiting_resume", g_bridge.ccb_is_waiting_resume);
    ok &= resolve_sym(mod, "ccb_resume_session", g_bridge.ccb_resume_session);
    ok &= resolve_sym(mod, "ccb_get_status_message", g_bridge.ccb_get_status_message);
    ok &= resolve_sym(mod, "ccb_push_key", g_bridge.ccb_push_key);
    ok &= resolve_sym(mod, "ccb_push_mouse", g_bridge.ccb_push_mouse);
    ok &= resolve_sym(mod, "ccb_push_resize", g_bridge.ccb_push_resize);
    ok &= resolve_sym(mod, "ccb_get_generation", g_bridge.ccb_get_generation);
    ok &= resolve_sym(mod, "ccb_copy_terminal_frame", g_bridge.ccb_copy_terminal_frame);
    ok &= resolve_sym(mod, "ccb_copy_world_snapshot", g_bridge.ccb_copy_world_snapshot);
    ok &= resolve_sym(mod, "ccb_copy_world_effects", g_bridge.ccb_copy_world_effects);
    ok &= resolve_sym(mod, "ccb_get_tileset_config", g_bridge.ccb_get_tileset_config);
    ok &= resolve_sym(mod, "ccb_copy_looks_like_table", g_bridge.ccb_copy_looks_like_table);
    if (!ok) {
        FreeLibrary(mod);
        err_out = "Missing exported symbol(s) in ccb_bridge.dll";
        return false;
    }
    g_bridge.module = mod;
    g_bridge.loaded = true;
    return true;
#else
    err_out = "ccb_bridge dynamic loading is currently configured for Windows";
    return false;
#endif
}

} // namespace

CcbEngine::CcbEngine() = default;
CcbEngine::~CcbEngine() = default;

void CcbEngine::shutdown_global_bridge() {
    if (g_bridge.loaded && g_bridge.ccb_shutdown) {
        g_bridge.ccb_shutdown();
    }
}

bool CcbEngine::load_library() {
    std::string err;
    if (!ensure_bridge_loaded(err)) {
        last_error_ = godot::String::utf8(err.c_str());
        return false;
    }
    last_error_ = "";
    return true;
}

bool CcbEngine::is_library_loaded() const {
    return g_bridge.loaded;
}

godot::String CcbEngine::get_last_error() const {
    return last_error_;
}

bool CcbEngine::start(const godot::String &base_dir, const godot::String &user_dir, int cols, int rows) {
    if (!load_library()) {
        return false;
    }
    const godot::CharString b = base_dir.utf8();
    const godot::CharString u = user_dir.utf8();
    return g_bridge.ccb_start(b.get_data(), u.get_data(), cols, rows) != 0;
}

void CcbEngine::shutdown() {
    if (g_bridge.loaded && g_bridge.ccb_shutdown) {
        g_bridge.ccb_shutdown();
    }
}

void CcbEngine::resume_session() {
    if (g_bridge.loaded && g_bridge.ccb_resume_session) {
        g_bridge.ccb_resume_session();
    }
}

bool CcbEngine::is_running() const {
    return g_bridge.loaded && g_bridge.ccb_is_running && g_bridge.ccb_is_running() != 0;
}

bool CcbEngine::is_waiting_resume() const {
    return g_bridge.loaded && g_bridge.ccb_is_waiting_resume && g_bridge.ccb_is_waiting_resume() != 0;
}

godot::String CcbEngine::get_status() const {
    if (!g_bridge.loaded || !g_bridge.ccb_get_status_message) {
        return last_error_.is_empty() ? godot::String("unloaded") : last_error_;
    }
    char buf[512] = {};
    g_bridge.ccb_get_status_message(buf, sizeof(buf));
    return godot::String::utf8(buf);
}

void CcbEngine::send_key(int key_code, const godot::String &utf8_text, bool ctrl, bool alt, bool shift) {
    if (!g_bridge.loaded || !g_bridge.ccb_push_key) return;
    const godot::CharString u = utf8_text.utf8();
    g_bridge.ccb_push_key(key_code, u.get_data(), ctrl ? 1 : 0, alt ? 1 : 0, shift ? 1 : 0);
}

void CcbEngine::send_mouse(int action, int cell_x, int cell_y, int wheel) {
    if (!g_bridge.loaded || !g_bridge.ccb_push_mouse) return;
    g_bridge.ccb_push_mouse(action, cell_x, cell_y, wheel);
}

void CcbEngine::resize(int cols, int rows) {
    if (!g_bridge.loaded || !g_bridge.ccb_push_resize) return;
    g_bridge.ccb_push_resize(cols, rows);
}

int64_t CcbEngine::get_generation() const {
    if (!g_bridge.loaded || !g_bridge.ccb_get_generation) return 0;
    return static_cast<int64_t>(g_bridge.ccb_get_generation());
}

godot::Dictionary CcbEngine::poll_terminal_frame() {
    godot::Dictionary res;
    if (!g_bridge.loaded || !g_bridge.ccb_copy_terminal_frame) {
        res["valid"] = false;
        return res;
    }

    CcbTermHeader hdr{};
    const int needed = g_bridge.ccb_copy_terminal_frame(&hdr, nullptr, 0);
    if (needed <= 0 || hdr.cols <= 0 || hdr.rows <= 0) {
        res["valid"] = false;
        res["generation"] = static_cast<int64_t>(hdr.generation);
        res["paused"] = hdr.paused != 0;
        return res;
    }

    term_buf_.resize(static_cast<size_t>(needed));
    const int copied = g_bridge.ccb_copy_terminal_frame(&hdr, term_buf_.data(), needed);

    godot::PackedByteArray bytes;
    const int64_t byte_len = static_cast<int64_t>(copied) * static_cast<int64_t>(sizeof(CcbTermCell));
    bytes.resize(byte_len);
    if (byte_len > 0) {
        std::memcpy(bytes.ptrw(), term_buf_.data(), static_cast<size_t>(byte_len));
    }

    res["valid"] = true;
    res["generation"] = static_cast<int64_t>(hdr.generation);
    res["cols"] = hdr.cols;
    res["rows"] = hdr.rows;
    res["terrain_rect"] = godot::Rect2i(hdr.terrain_x, hdr.terrain_y, hdr.terrain_w, hdr.terrain_h);
    res["cursor"] = godot::Vector2i(hdr.cursor_x, hdr.cursor_y);
    res["has_terrain"] = hdr.has_terrain != 0;
    res["in_game"] = hdr.in_game != 0;
    res["is_looking"] = hdr.is_looking != 0;
    res["paused"] = hdr.paused != 0;
    res["cells"] = bytes;
    return res;
}

godot::Dictionary CcbEngine::poll_world_snapshot() {
    godot::Dictionary res;
    if (!g_bridge.loaded || !g_bridge.ccb_copy_world_snapshot) {
        res["valid"] = false;
        return res;
    }

    CcbWorldHeader hdr{};
    if (!g_bridge.ccb_copy_world_snapshot(&hdr, nullptr, 0, nullptr, 0, nullptr, 0, nullptr, 0, nullptr, 0, nullptr, 0) || !hdr.valid) {
        res["valid"] = false;
        return res;
    }

    const int tile_count = hdr.width * hdr.height;
    const int str_bytes = std::max(1, hdr.string_bytes);
    const int critter_count = std::max(1, hdr.creature_count);
    const int light_count = std::max(1, hdr.light_count);
    const int mm_bytes = std::max(4, hdr.minimap_size * hdr.minimap_size * 4);

    tile_buf_.resize(static_cast<size_t>(std::max(1, tile_count)));
    str_buf_.resize(static_cast<size_t>(str_bytes));
    critter_buf_.resize(static_cast<size_t>(critter_count));
    light_buf_.resize(static_cast<size_t>(light_count));
    worn_buf_.resize(4096);
    minimap_buf_.resize(static_cast<size_t>(mm_bytes));

    if (!g_bridge.ccb_copy_world_snapshot(
            &hdr,
            tile_buf_.data(), static_cast<int>(tile_buf_.size()),
            str_buf_.data(), static_cast<int>(str_buf_.size()),
            critter_buf_.data(), static_cast<int>(critter_buf_.size()),
            light_buf_.data(), static_cast<int>(light_buf_.size()),
            worn_buf_.data(), static_cast<int>(worn_buf_.size()),
            minimap_buf_.data(), static_cast<int>(minimap_buf_.size())) || !hdr.valid) {
        res["valid"] = false;
        return res;
    }

    // Unpack interned string table
    godot::PackedStringArray strings;
    strings.resize(hdr.string_count);
    int s_idx = 0;
    int off = 0;
    while (s_idx < hdr.string_count && off < hdr.string_bytes) {
        const char *p = str_buf_.data() + off;
        const size_t slen = strnlen(p, static_cast<size_t>(hdr.string_bytes - off));
        strings.set(s_idx++, godot::String::utf8(p, static_cast<int>(slen)));
        off += static_cast<int>(slen) + 1;
    }

    // Raw packed tiles (48 bytes each) + C++ GPU Texture Packing (geom_rgba, mat_rgba, vis_rgba with
    // precomputed 4-bit neighbor edge-clamp mask, rain_mask_r8, and 64-bit world_light_hash).
    // Replaces ~17,500 interpreted GDScript decode_u8 calls + 2,500-entry Dictionary rebuilds per turn (<0.02ms in C++!).
    godot::PackedByteArray tiles_bytes;
    const int64_t t_blen = static_cast<int64_t>(tile_count) * static_cast<int64_t>(sizeof(CcbWorldTile));
    tiles_bytes.resize(t_blen);
    if (t_blen > 0) {
        std::memcpy(tiles_bytes.ptrw(), tile_buf_.data(), static_cast<size_t>(t_blen));
    }

    godot::PackedByteArray geom_rgba;
    godot::PackedByteArray mat_rgba;
    godot::PackedByteArray vis_rgba;
    godot::PackedByteArray rain_mask;
    uint64_t world_light_hash = 14695981039346656037ULL;
    auto fnv_mix = [&](uint64_t v) {
        world_light_hash ^= v;
        world_light_hash *= 1099511628211ULL;
    };
    // Hash geometry inside a 4-tile coarse world-snapped box (invariant when player walks 1..3 tiles!)
    const int coarse_x0 = (hdr.center_x - 20) & ~3;
    const int coarse_y0 = (hdr.center_y - 16) & ~3;
    const int coarse_x1 = coarse_x0 + 44;
    const int coarse_y1 = coarse_y0 + 36;
    fnv_mix(static_cast<uint64_t>(static_cast<uint32_t>(coarse_x0)));
    fnv_mix(static_cast<uint64_t>(static_cast<uint32_t>(coarse_y0)));
    fnv_mix(static_cast<uint64_t>(static_cast<uint32_t>(hdr.z)));
    fnv_mix(static_cast<uint64_t>(hdr.is_underground));

    bool has_water = false;
    bool has_overlays = false;
    if (tile_count > 0 && hdr.width > 0 && hdr.height > 0) {
        geom_rgba.resize(static_cast<int64_t>(tile_count) * 4);
        mat_rgba.resize(static_cast<int64_t>(tile_count) * 4);
        vis_rgba.resize(static_cast<int64_t>(tile_count) * 4);
        rain_mask.resize(static_cast<int64_t>(tile_count));

        uint8_t *gp = geom_rgba.ptrw();
        uint8_t *mp = mat_rgba.ptrw();
        uint8_t *vp = vis_rgba.ptrw();
        uint8_t *rp = rain_mask.ptrw();

        std::vector<uint8_t> surf_cls(static_cast<size_t>(tile_count), 0);
        static constexpr uint8_t A_LUT[4] = { 0, 85, 170, 255 };
        static constexpr uint8_t MAT_A_LUT[7] = { 0, 36, 73, 109, 146, 182, 219 };

        for (int i = 0; i < tile_count; ++i) {
            const CcbWorldTile &t = tile_buf_[static_cast<size_t>(i)];
            const uint8_t vis = t.vis;
            const uint8_t flags = t.flags;
            const uint8_t lkind = t.light_kind;
            const bool outside = (flags & CCB_TILE_OUTSIDE) != 0;
            const bool is_opaque = (flags & CCB_TILE_OPAQUE) != 0 || lkind == CCB_LIGHT_WALL;
            const bool roofed = (flags & CCB_TILE_IS_ROOFED) != 0 || !outside;
            const bool is_ap_x = (flags & CCB_TILE_APERTURE_X) != 0;

            if ((flags & CCB_TILE_HAS_OVERLAY) != 0 && t.overlay_kind != 0) {
                has_overlays = true;
            }
            if ((flags & CCB_TILE_IS_WATER) != 0 && vis != CCB_VIS_UNSEEN) {
                has_water = true;
            }

            // Rain/snow occlusion mask (255 = indoors or unseen -> discard precipitation on GPU)
            rp[i] = (!outside || (vis != CCB_VIS_DARK && vis != CCB_VIS_VISIBLE)) ? 255 : 0;

            const uint8_t b_byte = (lkind >= CCB_LIGHT_WIN_CLOSED && lkind <= CCB_LIGHT_DOOR_OPEN && is_ap_x) ? 255 : 0;
            const uint8_t a_bits = static_cast<uint8_t>((outside ? 0 : 1) | (roofed ? 2 : 0));
            const int g4 = i * 4;
            gp[g4 + 0] = t.height_u8;
            gp[g4 + 1] = lkind;
            gp[g4 + 2] = b_byte;
            gp[g4 + 3] = A_LUT[a_bits & 3];

            int mat_id = static_cast<int>(t.surface_hold_u8) / 36;
            if (mat_id < 0) mat_id = 0;
            if (mat_id > 6) mat_id = 6;
            mp[g4 + 0] = t.mat_r;
            mp[g4 + 1] = t.mat_g;
            mp[g4 + 2] = t.mat_b;
            mp[g4 + 3] = MAT_A_LUT[mat_id];

            // Surface class for zero-bleed wall clamping (0=outdoor, 1=indoor, 2=wall/aperture)
            surf_cls[static_cast<size_t>(i)] = (lkind >= CCB_LIGHT_WALL && lkind <= CCB_LIGHT_DOOR_OPEN)
                ? 2u : (outside ? 0u : 1u);

            uint8_t vis_u8 = 0;
            uint8_t explored_bit = 0;
            if (vis == CCB_VIS_FRINGE) {
                vis_u8 = 64;
            } else if (vis == CCB_VIS_MEMORIZED) {
                vis_u8 = 128;
                explored_bit = 1;
            } else if (vis == CCB_VIS_DARK) {
                vis_u8 = 192;
                explored_bit = 1;
            } else if (vis == CCB_VIS_VISIBLE) {
                vis_u8 = 255;
                explored_bit = 1;
            }
            uint8_t water_u8 = 0;
            if ((flags & CCB_TILE_IS_WATER) != 0) {
                water_u8 = ((flags & CCB_TILE_DEEP_WATER) != 0) ? 255 : 160;
            }

            vp[g4 + 0] = vis_u8;
            vp[g4 + 1] = is_opaque ? 255 : 0;
            vp[g4 + 2] = explored_bit;
            vp[g4 + 3] = water_u8;

            // Hash geometry & reflectance ONLY inside the 4-tile coarse world-snapped box (100% walk-invariant!)
            const int wx_t = hdr.origin_x + (i % hdr.width);
            const int wy_t = hdr.origin_y + (i / hdr.width);
            if (wx_t >= coarse_x0 && wx_t < coarse_x1 && wy_t >= coarse_y0 && wy_t < coarse_y1) {
                const uint64_t pack_gm = static_cast<uint64_t>(gp[g4 + 0])
                    | (static_cast<uint64_t>(gp[g4 + 1]) << 8)
                    | (static_cast<uint64_t>(gp[g4 + 2]) << 16)
                    | (static_cast<uint64_t>(gp[g4 + 3]) << 24)
                    | (static_cast<uint64_t>(mp[g4 + 0]) << 32)
                    | (static_cast<uint64_t>(mp[g4 + 1]) << 40)
                    | (static_cast<uint64_t>(mp[g4 + 2]) << 48)
                    | (static_cast<uint64_t>(mp[g4 + 3]) << 56);
                fnv_mix(pack_gm ^ (static_cast<uint64_t>(wx_t & 0xFFFF) << 17) ^ (static_cast<uint64_t>(wy_t & 0xFFFF) << 33));
            }
        }

        // Precompute 4-bit neighbor surface-class mismatch mask into vis_rgba.B bits 4..7
        // Eliminates 4 texelFetch(geom_tex) per full-res pixel on GPU (~240M texture taps/sec saved!)
        const int gw = hdr.width;
        const int gh = hdr.height;
        for (int ty = 0; ty < gh; ++ty) {
            const int row = ty * gw;
            const int row_u = (ty > 0 ? ty - 1 : 0) * gw;
            const int row_d = (ty + 1 < gh ? ty + 1 : gh - 1) * gw;
            for (int tx = 0; tx < gw; ++tx) {
                const int idx = row + tx;
                const uint8_t c0 = surf_cls[static_cast<size_t>(idx)];
                const int lx = (tx > 0) ? (tx - 1) : 0;
                const int rx = (tx + 1 < gw) ? (tx + 1) : (gw - 1);
                uint8_t emask = 0;
                if (surf_cls[static_cast<size_t>(row + lx)] != c0) emask |= 16u;  // -X
                if (surf_cls[static_cast<size_t>(row + rx)] != c0) emask |= 32u;  // +X
                if (surf_cls[static_cast<size_t>(row_u + tx)] != c0) emask |= 64u; // -Y
                if (surf_cls[static_cast<size_t>(row_d + tx)] != c0) emask |= 128u; // +Y
                vp[idx * 4 + 2] |= emask;
            }
        }
    }

    // Hash dynamic world light emitters into world_light_hash too
    fnv_mix(static_cast<uint64_t>(hdr.light_count));
    for (int i = 0; i < hdr.light_count; ++i) {
        const auto &l = light_buf_[static_cast<size_t>(i)];
        fnv_mix(static_cast<uint64_t>(static_cast<uint32_t>(l.x)) | (static_cast<uint64_t>(static_cast<uint32_t>(l.y)) << 32));
        fnv_mix(static_cast<uint64_t>(l.color_rgba) | (static_cast<uint64_t>(static_cast<int>(l.intensity * 10.0f)) << 32));
    }

    // Creatures
    godot::Array creatures;
    for (int i = 0; i < hdr.creature_count; ++i) {
        const auto &c = critter_buf_[static_cast<size_t>(i)];
        godot::Dictionary cd;
        cd["x"] = c.x;
        cd["y"] = c.y;
        cd["uid"] = static_cast<int64_t>(c.uid);
        cd["sprite"] = (c.sprite_str < strings.size()) ? strings[c.sprite_str] : godot::String();
        cd["flags"] = static_cast<int>(c.flags);
        cd["hp_pct"] = static_cast<int>(c.hp_pct);
        if (c.wield_str > 0 && c.wield_str < strings.size()) {
            cd["wielded"] = strings[c.wield_str];
        }
        godot::PackedStringArray cworn;
        for (int w = 0; w < 4; ++w) {
            if (c.worn_str[w] > 0 && c.worn_str[w] < strings.size()) {
                cworn.push_back(strings[c.worn_str[w]]);
            }
        }
        if (cworn.size() > 0) {
            cd["worn"] = cworn;
        }
        creatures.push_back(cd);
    }

    // Dynamic light emitters
    godot::Array lights;
    for (int i = 0; i < hdr.light_count; ++i) {
        const auto &l = light_buf_[static_cast<size_t>(i)];
        godot::Dictionary ld;
        ld["x"] = l.x;
        ld["y"] = l.y;
        ld["intensity"] = l.intensity;
        ld["rgba"] = static_cast<int64_t>(l.color_rgba);
        lights.push_back(ld);
    }

    // Worn items array
    godot::PackedStringArray worn_ids;
    godot::String worn_str = godot::String::utf8(worn_buf_.data());
    if (!worn_str.is_empty()) {
        worn_ids = worn_str.split(",", false);
    }

    // Pixel minimap RGBA bytes
    godot::PackedByteArray mm_arr;
    const int actual_mm_bytes = hdr.minimap_size * hdr.minimap_size * 4;
    mm_arr.resize(actual_mm_bytes);
    if (actual_mm_bytes > 0) {
        std::memcpy(mm_arr.ptrw(), minimap_buf_.data(), static_cast<size_t>(actual_mm_bytes));
    }

    res["valid"] = true;
    res["generation"] = static_cast<int64_t>(hdr.generation);
    res["origin"] = godot::Vector2i(hdr.origin_x, hdr.origin_y);
    res["size"] = godot::Vector2i(hdr.width, hdr.height);
    res["z"] = hdr.z;
    res["center"] = godot::Vector2i(hdr.center_x, hdr.center_y);
    res["player"] = godot::Vector2i(hdr.player_x, hdr.player_y);
    res["player_z"] = hdr.player_z;
    res["turn"] = hdr.turn;
    res["minutes"] = hdr.minutes_of_day;
    res["season"] = hdr.season;
    res["day_of_season"] = hdr.day_of_season;
    res["daylight"] = hdr.daylight_level;
    res["player_light"] = hdr.player_light;
    res["player_male"] = hdr.player_male != 0;
    res["is_looking"] = hdr.is_looking != 0;
    res["is_underground"] = hdr.is_underground != 0;
    res["weather"] = godot::String::utf8(hdr.weather_id);
    res["wielded"] = godot::String::utf8(hdr.wielded_id);
    res["worn"] = worn_ids;
    res["strings"] = strings;
    res["tiles"] = tiles_bytes;
    res["tile_stride"] = static_cast<int>(sizeof(CcbWorldTile));
    res["geom_rgba"] = geom_rgba;
    res["mat_rgba"] = mat_rgba;
    res["vis_rgba"] = vis_rgba;
    res["rain_mask"] = rain_mask;
    res["world_light_hash"] = static_cast<int64_t>(world_light_hash);
    res["has_water"] = has_water;
    res["has_overlays"] = has_overlays;
    // Auto-move route, destination preview & scrolling combat text (SCT)
    godot::Array path_points;
    godot::Array sct_entries;
    if (g_bridge.ccb_copy_world_effects && (hdr.path_count > 0 || hdr.sct_count > 0)) {
        path_buf_.resize(static_cast<size_t>(std::max(1, hdr.path_count)));
        sct_buf_.resize(static_cast<size_t>(std::max(1, hdr.sct_count)));
        if (g_bridge.ccb_copy_world_effects(
                path_buf_.data(), static_cast<int>(path_buf_.size()),
                sct_buf_.data(), static_cast<int>(sct_buf_.size()))) {
            for (int i = 0; i < hdr.path_count; ++i) {
                const auto &pp = path_buf_[static_cast<size_t>(i)];
                godot::Dictionary pd;
                pd["x"] = pp.x;
                pd["y"] = pp.y;
                pd["kind"] = static_cast<int>(pp.kind);
                path_points.push_back(pd);
            }
            for (int i = 0; i < hdr.sct_count; ++i) {
                const auto &sc = sct_buf_[static_cast<size_t>(i)];
                godot::Dictionary sd;
                sd["x"] = sc.x;
                sd["y"] = sc.y;
                sd["rgba"] = static_cast<int64_t>(sc.color_rgba);
                sd["step"] = static_cast<int>(sc.step);
                sd["max_steps"] = static_cast<int>(sc.max_steps);
                sd["text"] = godot::String::utf8(sc.text);
                sct_entries.push_back(sd);
            }
        }
    }

    res["creatures"] = creatures;
    res["lights"] = lights;
    res["path_points"] = path_points;
    res["sct"] = sct_entries;
    res["minimap_size"] = hdr.minimap_size;
    res["minimap_rgba"] = mm_arr;
    return res;
}

godot::Dictionary CcbEngine::get_tileset_config() const {
    godot::Dictionary res;
    res["valid"] = false;
    res["use_tiles"] = true;
    res["name"] = godot::String();
    res["dir"] = godot::String();
    res["json_file"] = godot::String("tile_config.json");
    if (!g_bridge.loaded || !g_bridge.ccb_get_tileset_config) {
        return res;
    }
    char name_buf[256] = {};
    char dir_buf[2048] = {};
    char json_buf[256] = {};
    int use_t = 1;
    if (g_bridge.ccb_get_tileset_config(name_buf, sizeof(name_buf), dir_buf, sizeof(dir_buf), json_buf, sizeof(json_buf), &use_t) != 0) {
        res["valid"] = true;
        res["use_tiles"] = use_t != 0;
        res["name"] = godot::String::utf8(name_buf);
        res["dir"] = godot::String::utf8(dir_buf);
        res["json_file"] = godot::String::utf8(json_buf);
    }
    return res;
}

godot::Dictionary CcbEngine::get_looks_like_map() const {
    godot::Dictionary res;
    if (!g_bridge.loaded || !g_bridge.ccb_copy_looks_like_table) {
        return res;
    }
    const int needed = g_bridge.ccb_copy_looks_like_table(nullptr, 0);
    if (needed <= 0) {
        return res;
    }
    std::string raw(static_cast<size_t>(needed) + 1u, '\0');
    const int copied = g_bridge.ccb_copy_looks_like_table(raw.data(), static_cast<int>(raw.size()));
    int pos = 0;
    while (pos < copied) {
        int nl = pos;
        while (nl < copied && raw[static_cast<size_t>(nl)] != '\n') {
            ++nl;
        }
        int eq = pos;
        while (eq < nl && raw[static_cast<size_t>(eq)] != '=') {
            ++eq;
        }
        if (eq > pos && eq + 1 < nl) {
            godot::String k = godot::String::utf8(raw.data() + pos, eq - pos);
            godot::String v = godot::String::utf8(raw.data() + eq + 1, nl - (eq + 1));
            res[k] = v;
        }
        pos = nl + 1;
    }
    return res;
}

void CcbEngine::_bind_methods() {
    using namespace godot;
    ClassDB::bind_method(D_METHOD("load_library"), &CcbEngine::load_library);
    ClassDB::bind_method(D_METHOD("is_library_loaded"), &CcbEngine::is_library_loaded);
    ClassDB::bind_method(D_METHOD("get_last_error"), &CcbEngine::get_last_error);
    ClassDB::bind_method(D_METHOD("start", "base_dir", "user_dir", "cols", "rows"), &CcbEngine::start);
    ClassDB::bind_method(D_METHOD("shutdown"), &CcbEngine::shutdown);
    ClassDB::bind_method(D_METHOD("resume_session"), &CcbEngine::resume_session);
    ClassDB::bind_method(D_METHOD("is_running"), &CcbEngine::is_running);
    ClassDB::bind_method(D_METHOD("is_waiting_resume"), &CcbEngine::is_waiting_resume);
    ClassDB::bind_method(D_METHOD("get_status"), &CcbEngine::get_status);
    ClassDB::bind_method(D_METHOD("send_key", "key_code", "utf8_text", "ctrl", "alt", "shift"), &CcbEngine::send_key);
    ClassDB::bind_method(D_METHOD("send_mouse", "action", "cell_x", "cell_y", "wheel"), &CcbEngine::send_mouse);
    ClassDB::bind_method(D_METHOD("resize", "cols", "rows"), &CcbEngine::resize);
    ClassDB::bind_method(D_METHOD("get_generation"), &CcbEngine::get_generation);
    ClassDB::bind_method(D_METHOD("poll_terminal_frame"), &CcbEngine::poll_terminal_frame);
    ClassDB::bind_method(D_METHOD("poll_world_snapshot"), &CcbEngine::poll_world_snapshot);
    ClassDB::bind_method(D_METHOD("get_tileset_config"), &CcbEngine::get_tileset_config);
    ClassDB::bind_method(D_METHOD("get_looks_like_map"), &CcbEngine::get_looks_like_map);
}

} // namespace cangling
