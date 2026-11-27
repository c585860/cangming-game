#include "bridge_state.hpp"

#include "cached_options.h"
#include "cata_imgui.h"
#include "catacharset.h"
#include "color.h"
#include "cursesdef.h"
#include "game.h"
#include "game_ui.h"
#include "output.h"
#include "point.h"
#include "ui_manager.h"
#include "wcwidth.h"

#include <algorithm>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

std::unique_ptr<cataimgui::client> imclient;

catacurses::window catacurses::stdscr;
catacurses::window catacurses::newscr;

namespace ccb_bridge {
void load_ccb_base_palette();
}

namespace {

struct BridgeCell {
    uint32_t cp = ' ';
    short fg = 7;
    short bg = 0;
    uint8_t width = 1;
    bool cont = false;
};

struct BridgeWindow {
    point pos = point::zero;
    int width = 0;
    int height = 0;
    point cursor = point::zero;
    short fg = 7;
    short bg = 0;
    bool dirty = true;
    std::vector<BridgeCell> cells;

    void reset_cells() {
        BridgeCell blank;
        cells.assign(static_cast<size_t>(std::max(0, width)) * static_cast<size_t>(std::max(0, height)), blank);
        cursor = point::zero;
        dirty = true;
    }
};

BridgeWindow *as_bw(const catacurses::window &win) {
    return win.get<BridgeWindow>();
}

uint32_t chtype_to_codepoint(const catacurses::chtype ch) {
    switch (ch) {
        case LINE_XOXO: return 0x2502;
        case LINE_OXOX: return 0x2500;
        case LINE_XXOO: return 0x2514;
        case LINE_OXXO: return 0x250C;
        case LINE_OOXX: return 0x2510;
        case LINE_XOOX: return 0x2518;
        case LINE_XXXO: return 0x251C;
        case LINE_XXOX: return 0x2534;
        case LINE_XOXX: return 0x2524;
        case LINE_OXXX: return 0x252C;
        case LINE_XXXX: return 0x253C;
        default: break;
    }
    const std::string s = string_from_int(ch);
    if (s.empty()) {
        return ch > 0 ? static_cast<uint32_t>(ch) : ' ';
    }
    const char *ptr = s.c_str();
    int len = static_cast<int>(s.size());
    const uint32_t cp = UTF8_getch(&ptr, &len);
    return cp == UNKNOWN_UNICODE ? static_cast<uint32_t>(ch) : cp;
}

bool advance_newline(BridgeWindow *w) {
    if (w->cursor.y < w->height - 1) {
        w->cursor.y++;
        w->cursor.x = 0;
        return true;
    }
    return false;
}

void write_cp(BridgeWindow *w, uint32_t cp) {
    if (!w || w->width <= 0 || w->height <= 0) {
        return;
    }
    if (cp == '\n') {
        advance_newline(w);
        return;
    }
    if (cp == '\r') {
        w->cursor.x = 0;
        return;
    }
    if (cp < 0x20) {
        cp = ' ';
    }
    if (w->cursor.x >= w->width) {
        if (!advance_newline(w)) {
            return;
        }
    }
    if (w->cursor.y < 0 || w->cursor.y >= w->height || w->cursor.x < 0 || w->cursor.x >= w->width) {
        return;
    }

    int cw = mk_wcwidth(cp);
    if (cw == 0) {
        return; // skip zero-width combining marks cleanly
    }
    if (cw < 0) {
        cw = 1;
        cp = ' ';
    } else if (cw > 2) {
        cw = 2;
    }

    const size_t row_off = static_cast<size_t>(w->cursor.y) * static_cast<size_t>(w->width);
    // If overwriting the continuation half of a previous wide char, blank its lead cell
    if (w->cursor.x > 0 && w->cells[row_off + static_cast<size_t>(w->cursor.x)].cont) {
        auto &prev = w->cells[row_off + static_cast<size_t>(w->cursor.x - 1)];
        prev.cp = ' ';
        prev.width = 1;
        prev.cont = false;
    }

    // If wide char doesn't fit on the last column of the line, wrap to next line
    if (cw == 2 && w->cursor.x == w->width - 1) {
        auto &last = w->cells[row_off + static_cast<size_t>(w->cursor.x)];
        last.cp = ' ';
        last.fg = w->fg;
        last.bg = w->bg;
        last.width = 1;
        last.cont = false;
        if (!advance_newline(w)) {
            return;
        }
    }

    const size_t r2 = static_cast<size_t>(w->cursor.y) * static_cast<size_t>(w->width);
    BridgeCell &c0 = w->cells[r2 + static_cast<size_t>(w->cursor.x)];
    c0.cp = cp;
    c0.fg = w->fg;
    c0.bg = w->bg;
    c0.width = static_cast<uint8_t>(cw);
    c0.cont = false;

    if (cw == 1) {
        if (w->cursor.x + 1 < w->width && w->cells[r2 + static_cast<size_t>(w->cursor.x + 1)].cont) {
            auto &nxt = w->cells[r2 + static_cast<size_t>(w->cursor.x + 1)];
            nxt.cp = ' ';
            nxt.width = 1;
            nxt.cont = false;
        }
        w->cursor.x++;
        if (w->cursor.x >= w->width) {
            advance_newline(w);
        }
    } else {
        BridgeCell &c1 = w->cells[r2 + static_cast<size_t>(w->cursor.x + 1)];
        c1.cp = 0;
        c1.fg = w->fg;
        c1.bg = w->bg;
        c1.width = 0;
        c1.cont = true;
        if (w->cursor.x + 2 < w->width && w->cells[r2 + static_cast<size_t>(w->cursor.x + 2)].cont) {
            auto &nxt = w->cells[r2 + static_cast<size_t>(w->cursor.x + 2)];
            nxt.cp = ' ';
            nxt.width = 1;
            nxt.cont = false;
        }
        w->cursor.x += 2;
        if (w->cursor.x >= w->width) {
            advance_newline(w);
        }
    }
    w->dirty = true;
}

void write_utf8_string(BridgeWindow *w, const std::string &text) {
    if (!w || text.empty()) {
        return;
    }
    const char *ptr = text.c_str();
    int len = static_cast<int>(text.size());
    while (len > 0) {
        if (*ptr == '\n') {
            advance_newline(w);
            ++ptr;
            --len;
            continue;
        }
        if (*ptr == '\r') {
            w->cursor.x = 0;
            ++ptr;
            --len;
            continue;
        }
        const uint32_t cp = UTF8_getch(&ptr, &len);
        write_cp(w, cp == UNKNOWN_UNICODE ? '?' : cp);
    }
}

void blit_window_to_curses_layer(const catacurses::window &win) {
    const BridgeWindow *w = as_bw(win);
    if (!w || w->width <= 0 || w->height <= 0) {
        return;
    }
    auto &st = ccb_bridge::state();
    if (st.work_cols <= 0 || st.work_rows <= 0) {
        return;
    }

    const bool is_terrain = (g != nullptr && g->w_terrain && win == g->w_terrain);
    if (is_terrain) {
        st.work_terrain_x = w->pos.x;
        st.work_terrain_y = w->pos.y;
        st.work_terrain_w = w->width;
        st.work_terrain_h = w->height;
    }

    for (int wy = 0; wy < w->height; ++wy) {
        const int sy = w->pos.y + wy;
        if (sy < 0 || sy >= st.work_rows) {
            continue;
        }
        const size_t dst_row = static_cast<size_t>(sy) * static_cast<size_t>(st.work_cols);
        const size_t src_row = static_cast<size_t>(wy) * static_cast<size_t>(w->width);
        for (int wx = 0; wx < w->width; ++wx) {
            const int sx = w->pos.x + wx;
            if (sx < 0 || sx >= st.work_cols) {
                continue;
            }
            const BridgeCell &src = w->cells[src_row + static_cast<size_t>(wx)];
            CcbTermCell &dst = st.curses_layer[dst_row + static_cast<size_t>(sx)];
            dst.codepoint = src.cp;
            dst.fg_rgba = st.palette_rgba(src.fg);
            dst.bg_rgba = st.palette_rgba(src.bg);
            dst.width = src.width;
            dst.flags = (is_terrain ? CCB_CELL_TERRAIN : 0u) | (src.cont ? CCB_CELL_CONT : 0u);
            dst.reserved = 0;
        }
    }
}

} // namespace

int get_window_width() {
    return TERMX;
}

int get_window_height() {
    return TERMY;
}

catacurses::window catacurses::newwin(int nlines, int ncols, const point &begin) {
    if (begin.x < 0 || begin.y < 0) {
        return window();
    }
    if (ncols == 0) {
        ncols = std::max(1, TERMX - begin.x);
    }
    if (nlines == 0) {
        nlines = std::max(1, TERMY - begin.y);
    }
    auto *w = new BridgeWindow();
    w->pos = begin;
    w->width = ncols;
    w->height = nlines;
    w->reset_cells();
    return catacurses::window(std::shared_ptr<void>(w, [](void *p) {
        delete static_cast<BridgeWindow *>(p);
    }));
}

void catacurses::wnoutrefresh(const window &win) {
    blit_window_to_curses_layer(win);
}

void catacurses::wrefresh(const window &win) {
    wnoutrefresh(win);
    doupdate();
}

void catacurses::werase(const window &win) {
    if (BridgeWindow *w = as_bw(win)) {
        w->reset_cells();
    }
}

int catacurses::getmaxx(const window &win) {
    const BridgeWindow *w = as_bw(win);
    return w ? w->width : 0;
}

int catacurses::getmaxy(const window &win) {
    const BridgeWindow *w = as_bw(win);
    return w ? w->height : 0;
}

int catacurses::getbegx(const window &win) {
    const BridgeWindow *w = as_bw(win);
    return w ? w->pos.x : 0;
}

int catacurses::getbegy(const window &win) {
    const BridgeWindow *w = as_bw(win);
    return w ? w->pos.y : 0;
}

int catacurses::getcurx(const window &win) {
    const BridgeWindow *w = as_bw(win);
    return w ? w->cursor.x : 0;
}

int catacurses::getcury(const window &win) {
    const BridgeWindow *w = as_bw(win);
    return w ? w->cursor.y : 0;
}

void catacurses::wattron(const window &win, const nc_color &attrs) {
    BridgeWindow *w = as_bw(win);
    if (!w) {
        return;
    }
    const int pair_idx = attrs.to_color_pair_index();
    const auto &pairs = ccb_bridge::state().color_pairs;
    short fg = 7;
    short bg = 0;
    if (pair_idx >= 0 && pair_idx < static_cast<int>(pairs.size())) {
        fg = pairs[static_cast<size_t>(pair_idx)].first;
        bg = pairs[static_cast<size_t>(pair_idx)].second;
    }
    if (attrs.is_bold() && fg >= 0 && fg < 8) {
        fg = static_cast<short>(fg + 8);
    }
    if (attrs.is_blink() && bg >= 0 && bg < 8) {
        bg = static_cast<short>(bg + 8);
    }
    w->fg = fg;
    w->bg = bg;
}

void catacurses::wattroff(const window &win, const nc_color) {
    if (BridgeWindow *w = as_bw(win)) {
        w->fg = 7;
        w->bg = 0;
    }
}

void catacurses::wmove(const window &win, const point &p) {
    BridgeWindow *w = as_bw(win);
    if (!w) {
        return;
    }
    if (p.x >= 0 && p.x < w->width && p.y >= 0 && p.y < w->height) {
        w->cursor = p;
    }
    if (win == newscr) {
        ccb_bridge::state().work_cursor_x = p.x;
        ccb_bridge::state().work_cursor_y = p.y;
    }
}

void catacurses::mvwprintw(const window &win, const point &p, const std::string &text) {
    BridgeWindow *w = as_bw(win);
    if (!w || p.x < 0 || p.y < 0 || p.x >= w->width || p.y >= w->height) {
        return;
    }
    w->cursor = p;
    write_utf8_string(w, text);
}

void catacurses::wprintw(const window &win, const std::string &text) {
    write_utf8_string(as_bw(win), text);
}

void catacurses::refresh() {
    wrefresh(stdscr);
}

void refresh_display() {
    ccb_bridge::state().publish_frame();
}

void drain_renderer_recovery() {}
void refresh_mouse_config() {}

void catacurses::doupdate() {
    refresh_display();
}

void catacurses::clear() {
    wclear(stdscr);
}

void catacurses::erase() {
    werase(stdscr);
}

void catacurses::endwin() {
    ui_manager::reset();
}

void catacurses::wborder(const window &win, const chtype ls, const chtype rs, const chtype ts,
                         const chtype bs, const chtype tl, const chtype tr, const chtype bl,
                         const chtype br) {
    BridgeWindow *w = as_bw(win);
    if (!w || w->width < 2 || w->height < 2) {
        return;
    }
    const point saved = w->cursor;
    const chtype c_ls = ls ? ls : LINE_XOXO;
    const chtype c_rs = rs ? rs : LINE_XOXO;
    const chtype c_ts = ts ? ts : LINE_OXOX;
    const chtype c_bs = bs ? bs : LINE_OXOX;
    const chtype c_tl = tl ? tl : LINE_OXXO;
    const chtype c_tr = tr ? tr : LINE_OOXX;
    const chtype c_bl = bl ? bl : LINE_XXOO;
    const chtype c_br = br ? br : LINE_XOOX;

    mvwvline(win, point(0, 1), c_ls, w->height - 2);
    mvwvline(win, point(w->width - 1, 1), c_rs, w->height - 2);
    mvwhline(win, point(1, 0), c_ts, w->width - 2);
    mvwhline(win, point(1, w->height - 1), c_bs, w->width - 2);
    mvwaddch(win, point(0, 0), c_tl);
    mvwaddch(win, point(w->width - 1, 0), c_tr);
    mvwaddch(win, point(0, w->height - 1), c_bl);
    mvwaddch(win, point(w->width - 1, w->height - 1), c_br);
    w->cursor = saved;
    wattroff(win, c_white);
}

void catacurses::mvwhline(const window &win, const point &p, const chtype ch, const int n) {
    const chtype c = ch ? ch : LINE_OXOX;
    for (int i = 0; i < n; ++i) {
        mvwaddch(win, p + point(i, 0), c);
    }
}

void catacurses::mvwvline(const window &win, const point &p, const chtype ch, const int n) {
    const chtype c = ch ? ch : LINE_XOXO;
    for (int j = 0; j < n; ++j) {
        mvwaddch(win, p + point(0, j), c);
    }
}

void catacurses::mvwaddch(const window &win, const point &p, const chtype ch) {
    BridgeWindow *w = as_bw(win);
    if (!w || p.x < 0 || p.y < 0 || p.x >= w->width || p.y >= w->height) {
        return;
    }
    w->cursor = p;
    waddch(win, ch);
}

void catacurses::waddch(const window &win, const chtype ch) {
    write_cp(as_bw(win), chtype_to_codepoint(ch));
}

void catacurses::wredrawln(const window &, const int, const int) {}

void catacurses::wclear(const window &win) {
    werase(win);
}

void catacurses::curs_set(const int) {}

void catacurses::init_pair(const short pair, const base_color f, const base_color b) {
    auto &pairs = ccb_bridge::state().color_pairs;
    if (pair >= 0 && pair < static_cast<short>(pairs.size())) {
        pairs[static_cast<size_t>(pair)] = {static_cast<short>(f), static_cast<short>(b)};
    }
    if (imclient) {
        imclient->upload_color_pair(pair, static_cast<int>(f), static_cast<int>(b));
    }
}

void catacurses::resizeterm() {
    auto &st = ccb_bridge::state();
    TERMX = std::max(80, st.term_cols.load(std::memory_order_relaxed));
    TERMY = std::max(24, st.term_rows.load(std::memory_order_relaxed));
    stdscr = newwin(TERMY, TERMX, point::zero);
    newscr = newwin(TERMY, TERMX, point::zero);
    st.resize_work_buffers(TERMX, TERMY);
    game_ui::init_ui();
    ui_manager::screen_resized();
    refresh_display();
}

void catacurses::init_interface() {
    auto &st = ccb_bridge::state();
    ccb_bridge::load_ccb_base_palette();
    TERMX = std::max(80, st.term_cols.load(std::memory_order_relaxed));
    TERMY = std::max(24, st.term_rows.load(std::memory_order_relaxed));
    stdscr = newwin(TERMY, TERMX, point::zero);
    newscr = newwin(TERMY, TERMX, point::zero);
    st.resize_work_buffers(TERMX, TERMY);
    imclient = std::make_unique<cataimgui::client>();
    init_colors();
}

bool catacurses::supports_256_colors() {
    return true;
}

void ensure_term_size();
void check_encoding();
void ensure_term_size() {}
void check_encoding() {}
void set_title(const std::string &) {}

namespace ccb_bridge {
void apply_host_resize(int cols, int rows) {
    cols = std::max(80, cols);
    rows = std::max(24, rows);
    auto &st = state();
    if (st.work_cols == cols && st.work_rows == rows) {
        return;
    }
    st.term_cols.store(cols, std::memory_order_relaxed);
    st.term_rows.store(rows, std::memory_order_relaxed);
    catacurses::resizeterm();
}
} // namespace ccb_bridge
