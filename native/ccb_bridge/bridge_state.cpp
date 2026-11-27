#include "bridge_state.hpp"

#include "avatar.h"
#include "game.h"
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

    const uint64_t next_gen = generation.fetch_add(1, std::memory_order_relaxed) + 1;

    CcbTermHeader hdr{};
    hdr.generation = next_gen;
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
    hdr.cursor_x = work_cursor_x;
    hdr.cursor_y = work_cursor_y;
    hdr.in_game = (g != nullptr && g->w_terrain) ? 1 : 0;
    hdr.is_looking = (g != nullptr && g->w_terrain && get_avatar().view_offset != tripoint_rel_ms::zero) ? 1 : 0;
    hdr.paused = waiting_resume.load(std::memory_order_relaxed) ? 1 : 0;

    WorldSnapshot next_world;
    capture_world_snapshot(next_world, next_gen, has_terrain);

    {
        std::lock_guard<std::mutex> lk(snap_mtx);
        published_term.header = hdr;
        published_term.cells = work_cells;
        if (next_world.header.valid) {
            published_world = std::move(next_world);
        } else if (!hdr.in_game) {
            published_world.header.valid = 0;
        }
    }
}

} // namespace ccb_bridge
