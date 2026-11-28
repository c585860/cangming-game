#include "bridge_state.hpp"

#include "avatar.h"
#include "game.h"
#include "imgui/imgui.h"
#include "imgui/imgui_internal.h"
#include "ui_manager.h"

#include <algorithm>
#include <cstring>

namespace ccb_bridge {

static constexpr uint32_t pack_rgba(uint8_t r, uint8_t g, uint8_t b, uint8_t a = 255) {
    return static_cast<uint32_t>(r)
         | (static_cast<uint32_t>(g) << 8)
         | (static_cast<uint32_t>(b) << 16)
         | (static_cast<uint32_t>(a) << 24);
}

BridgeState &state() {
    static BridgeState instance;
    return instance;
}

void BridgeState::set_status(const std::string &msg) {
    std::lock_guard<std::mutex> lk(status_mtx);
    status_message = msg;
}

std::string BridgeState::get_status() {
    std::lock_guard<std::mutex> lk(status_mtx);
    return status_message;
}

void BridgeState::push_vfx_event(uint8_t kind, int ox, int oy, int tx, int ty, int z,
                                 float radius, float light_intensity, uint32_t color_rgba,
                                 uint16_t arc_deg, uint16_t delay_ms, uint8_t caliber_class,
                                 uint8_t shot_index, uint8_t flags) {
    CcbWorldVfx ev{};
    ev.id = next_vfx_id.fetch_add(1, std::memory_order_relaxed);
    ev.ox = ox;
    ev.oy = oy;
    ev.tx = tx;
    ev.ty = ty;
    ev.z = z;
    ev.radius = radius;
    ev.light_intensity = light_intensity;
    ev.color_rgba = color_rgba;
    ev.arc_deg = arc_deg;
    ev.delay_ms = delay_ms;
    ev.kind = kind;
    ev.caliber_class = caliber_class;
    ev.shot_index = shot_index;
    ev.flags = flags;
    std::lock_guard<std::mutex> lk(vfx_mtx);
    vfx_ring.push_back(ev);
    while (vfx_ring.size() > 96) {
        vfx_ring.pop_front();
    }
}

void BridgeState::push_audio_event(uint8_t kind, uint8_t subtype, int x, int y, int z,
                                   float volume, float pan, float radius,
                                   uint64_t burst_id, uint16_t rpm, uint16_t delay_ms,
                                   uint8_t shot_index, uint8_t flags) {
    CcbAudioEvent ev{};
    ev.id = next_audio_id.fetch_add(1, std::memory_order_relaxed);
    ev.burst_id = burst_id;
    ev.x = x;
    ev.y = y;
    ev.z = z;
    ev.rpm = rpm;
    ev.delay_ms = delay_ms;
    ev.volume = std::clamp(volume, 0.0f, 1.5f);
    ev.pan = std::clamp(pan, -1.0f, 1.0f);
    ev.radius = radius;
    ev.kind = kind;
    ev.subtype = subtype;
    ev.shot_index = shot_index;
    ev.flags = flags;
    std::lock_guard<std::mutex> lk(audio_mtx);
    audio_ring.push_back(ev);
    while (audio_ring.size() > 128) {
        audio_ring.pop_front();
    }
}

bool BridgeState::has_recent_shot_context() const {
    if (active_burst_id == 0) {
        return false;
    }
    const auto elapsed = std::chrono::steady_clock::now() - active_shot_wall_tp;
    return elapsed <= std::chrono::milliseconds(180);
}

void BridgeState::init_default_palette() {
    // Classic Cataclysm-DDA base_colors.json defaults (indices 0..15)
    static constexpr uint8_t base16[16][3] = {
        {0, 0, 0},       // 0 BLACK
        {196, 0, 0},     // 1 RED
        {0, 196, 0},     // 2 GREEN
        {196, 180, 30},  // 3 BROWN
        {0, 0, 196},     // 4 BLUE
        {196, 0, 180},   // 5 MAGENTA
        {0, 170, 200},   // 6 CYAN
        {196, 196, 196}, // 7 GRAY
        {96, 96, 96},    // 8 DGRAY
        {255, 50, 50},   // 9 LRED
        {50, 255, 50},   // 10 LGREEN
        {255, 255, 50},  // 11 YELLOW
        {80, 130, 255},  // 12 LBLUE
        {255, 80, 255},  // 13 LMAGENTA
        {80, 255, 255},  // 14 LCYAN
        {255, 255, 255}  // 15 WHITE
    };
    for (int i = 0; i < 16; ++i) {
        palette[i] = pack_rgba(base16[i][0], base16[i][1], base16[i][2], 255);
    }
    // 6x6x6 xterm color cube (16..231)
    static constexpr uint8_t cube[6] = {0, 95, 135, 175, 215, 255};
    for (int i = 16; i < 232; ++i) {
        int v = i - 16;
        int r = v / 36;
        int g = (v % 36) / 6;
        int b = v % 6;
        palette[i] = pack_rgba(cube[r], cube[g], cube[b], 255);
    }
    // 24-step grayscale ramp (232..255)
    for (int i = 232; i < 256; ++i) {
        uint8_t lv = static_cast<uint8_t>(8 + (i - 232) * 10);
        palette[i] = pack_rgba(lv, lv, lv, 255);
    }
    for (auto &p : color_pairs) {
        p = {7, 0};
    }
}

uint32_t BridgeState::palette_rgba(int color_idx) const {
    if (color_idx < 0) color_idx = 0;
    if (color_idx >= 256) color_idx = color_idx & 255;
    return palette[static_cast<size_t>(color_idx)];
}

void BridgeState::resize_work_buffers(int cols, int rows) {
    cols = std::max(80, cols);
    rows = std::max(24, rows);
    work_cols = cols;
    work_rows = rows;
    CcbTermCell blank{};
    blank.codepoint = ' ';
    blank.fg_rgba = palette_rgba(7);
    blank.bg_rgba = palette_rgba(0);
    blank.width = 1;
    blank.flags = 0;
    curses_layer.assign(static_cast<size_t>(cols) * static_cast<size_t>(rows), blank);
    work_cells = curses_layer;
}

void BridgeState::clear_work_buffers() {
    CcbTermCell blank{};
    blank.codepoint = ' ';
    blank.fg_rgba = palette_rgba(7);
    blank.bg_rgba = palette_rgba(0);
    blank.width = 1;
    blank.flags = 0;
    std::fill(curses_layer.begin(), curses_layer.end(), blank);
    std::fill(work_cells.begin(), work_cells.end(), blank);
    work_terrain_x = 0;
    work_terrain_y = 0;
    work_terrain_w = 0;
    work_terrain_h = 0;
}

void BridgeState::publish_frame() {
    if (work_cols <= 0 || work_rows <= 0) {
        return;
    }

    // Start from curses backing layer, then composite any active ImTui windows on top
    work_cells = curses_layer;
    composite_imtui_onto_work_buffer();

    // Detect if any terrain cells survived unoccluded on screen
    bool has_terrain = false;
    int tmin_x = work_cols, tmin_y = work_rows, tmax_x = -1, tmax_y = -1;
    for (int y = 0; y < work_rows; ++y) {
        const size_t row_off = static_cast<size_t>(y) * static_cast<size_t>(work_cols);
        for (int x = 0; x < work_cols; ++x) {
            if ((work_cells[row_off + static_cast<size_t>(x)].flags & CCB_CELL_TERRAIN) != 0) {
                has_terrain = true;
                if (x < tmin_x) tmin_x = x;
                if (y < tmin_y) tmin_y = y;
                if (x > tmax_x) tmax_x = x;
                if (y > tmax_y) tmax_y = y;
            }
        }
    }

    CcbTermHeader hdr{};
    hdr.generation = generation.load(std::memory_order_relaxed);
    hdr.cols = work_cols;
    hdr.rows = work_rows;
    if (has_terrain && tmax_x >= tmin_x && tmax_y >= tmin_y) {
        hdr.terrain_x = tmin_x;
        hdr.terrain_y = tmin_y;
        hdr.terrain_w = tmax_x - tmin_x + 1;
        hdr.terrain_h = tmax_y - tmin_y + 1;
        hdr.has_terrain = 1;
    } else {
        hdr.terrain_x = work_terrain_x;
        hdr.terrain_y = work_terrain_y;
        hdr.terrain_w = work_terrain_w;
        hdr.terrain_h = work_terrain_h;
        hdr.has_terrain = 0;
    }
    int cur_x = work_cursor_x;
    int cur_y = work_cursor_y;
    bool has_active_imgui = false;
    bool imgui_wants_text = false;
    if (ImGui::GetCurrentContext() != nullptr && GImGui != nullptr) {
        for (int i = 0; i < GImGui->Windows.Size; ++i) {
            const ImGuiWindow *w = GImGui->Windows[i];
            if (w && w->Active && !w->Hidden && !w->Collapsed && w->Size.x > 0.0f && w->Size.y > 0.0f) {
                has_active_imgui = true;
                break;
            }
        }
        imgui_wants_text = ImGui::GetIO().WantTextInput;
        if (imgui_wants_text) {
            const ImVec2 ime_pos = GImGui->PlatformImeData.InputPos;
            if (ime_pos.x > 0.0f || ime_pos.y > 0.0f) {
                cur_x = std::clamp(static_cast<int>(ime_pos.x), 0, std::max(0, work_cols - 1));
                cur_y = std::clamp(static_cast<int>(ime_pos.y), 0, std::max(0, work_rows - 1));
            }
        }
    }
    // When an ImGui menu/dialog is active, trust ImGui's WantTextInput strictly so normal menu hotkeys
    // (like wishitem / Esc / Debug menu) never get hijacked by OS Pinyin IME!
    if (has_active_imgui && !imgui_wants_text) {
        work_cursor_active = false;
    }
    const bool want_text = has_active_imgui ? imgui_wants_text : work_cursor_active;
    hdr.cursor_x = cur_x;
    hdr.cursor_y = cur_y;
    hdr.in_game = (g != nullptr && g->w_terrain) ? 1 : 0;
    hdr.is_looking = (g != nullptr && g->w_terrain && get_avatar().view_offset != tripoint_rel_ms::zero) ? 1 : 0;
    hdr.paused = waiting_resume.load(std::memory_order_relaxed) ? 1 : 0;
    hdr.want_text_input = want_text ? 1 : 0;
    hdr.pad_hdr[0] = hdr.pad_hdr[1] = hdr.pad_hdr[2] = 0;

    const bool want_world = has_terrain && (hdr.in_game != 0);
    const bool en3d = render3d_enabled.load(std::memory_order_acquire);
    const bool same_lvl = render3d_same_level_only.load(std::memory_order_acquire);
    const bool force_w = force_world_refresh.exchange(false, std::memory_order_acq_rel);

    int rad_x = std::clamp(capture_rad_x.load(std::memory_order_relaxed), 16, 34);
    int rad_y = std::clamp(capture_rad_y.load(std::memory_order_relaxed), 12, 24);
    if (en3d) {
        rad_x = std::max(rad_x, 24);
        rad_y = std::max(rad_y, 20);
    }

    const uint64_t wsig = want_world ? compute_world_state_sig(has_terrain, rad_x, rad_y) : 0ULL;
    bool captured_world = false;
    uint64_t next_wgen = world_generation.load(std::memory_order_relaxed);
    if (want_world && (force_w || !last_world_valid || wsig != last_world_sig)) {
        next_wgen += 1;
        capture_world_snapshot(work_world, next_wgen, has_terrain);
        if (work_world.header.valid) {
            last_world_sig = wsig;
            last_world_valid = true;
            captured_world = true;
        }
    } else if (!hdr.in_game) {
        last_world_valid = false;
        last_world_sig = 0;
    }

    bool captured_3d = false;
    uint64_t next_3dgen = scene3d_generation.load(std::memory_order_relaxed);
    if (en3d && want_world) {
        const uint64_t s3d_sig = wsig ^ (same_lvl ? 0x9E3779B97F4A7C15ULL : 0x517CC1B727220A95ULL);
        if (force_w || !last_scene3d_valid || s3d_sig != last_scene3d_sig) {
            next_3dgen += 1;
            capture_scene3d_snapshot(work_scene3d, next_3dgen, has_terrain);
            if (work_scene3d.header.valid) {
                last_scene3d_sig = s3d_sig;
                last_scene3d_valid = true;
                captured_3d = true;
            }
        }
    } else if (!en3d || !hdr.in_game) {
        last_scene3d_valid = false;
        last_scene3d_sig = 0;
    }

    const bool term_changed =
        (published_term.cells.size() != work_cells.size()) ||
        (published_term.header.cols != hdr.cols) ||
        (published_term.header.rows != hdr.rows) ||
        (published_term.header.terrain_x != hdr.terrain_x) ||
        (published_term.header.terrain_y != hdr.terrain_y) ||
        (published_term.header.terrain_w != hdr.terrain_w) ||
        (published_term.header.terrain_h != hdr.terrain_h) ||
        (published_term.header.cursor_x != hdr.cursor_x) ||
        (published_term.header.cursor_y != hdr.cursor_y) ||
        (published_term.header.has_terrain != hdr.has_terrain) ||
        (published_term.header.in_game != hdr.in_game) ||
        (published_term.header.is_looking != hdr.is_looking) ||
        (published_term.header.paused != hdr.paused) ||
        (published_term.header.want_text_input != hdr.want_text_input) ||
        (!work_cells.empty() && std::memcmp(published_term.cells.data(), work_cells.data(),
                                            work_cells.size() * sizeof(CcbTermCell)) != 0);

    if (!term_changed && !captured_world && !captured_3d && !force_w && generation.load(std::memory_order_relaxed) > 0) {
        return;
    }

    const uint64_t next_gen = term_changed
        ? (generation.load(std::memory_order_relaxed) + 1)
        : generation.load(std::memory_order_relaxed);
    hdr.generation = next_gen;

    {
        std::lock_guard<std::mutex> lk(snap_mtx);
        if (term_changed) {
            published_term.header = hdr;
            published_term.cells.resize(work_cells.size());
            if (!work_cells.empty()) {
                std::memcpy(published_term.cells.data(), work_cells.data(),
                            work_cells.size() * sizeof(CcbTermCell));
            }
            generation.store(next_gen, std::memory_order_release);
        }
        if (captured_world) {
            std::swap(published_world, work_world);
            world_generation.store(next_wgen, std::memory_order_release);
        } else if (!hdr.in_game) {
            published_world.header.valid = 0;
        }
        if (captured_3d) {
            std::swap(published_scene3d, work_scene3d);
            scene3d_generation.store(next_3dgen, std::memory_order_release);
        } else if (!en3d || !hdr.in_game) {
            published_scene3d.header.valid = 0;
            if (!en3d && !published_scene3d.items.empty()) {
                published_scene3d.items.clear();
                published_scene3d.items.shrink_to_fit();
                published_scene3d.strings.clear();
                published_scene3d.strings.shrink_to_fit();
                published_scene3d.lights.clear();
                published_scene3d.lights.shrink_to_fit();
                work_scene3d.items.clear();
                work_scene3d.items.shrink_to_fit();
                work_scene3d.strings.clear();
                work_scene3d.strings.shrink_to_fit();
                work_scene3d.lights.clear();
                work_scene3d.lights.shrink_to_fit();
            }
        }
    }
}

} // namespace ccb_bridge
