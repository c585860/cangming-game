#include "bridge_state.hpp"

#include "cata_imgui.h"
#include "cursesdef.h"
#include "input.h"
#include "output.h"

#include "imtui/imtui.h"
#include "imtui/imtui-impl-ncurses.h"
#include "imgui/imgui.h"
#include "imgui/imgui_internal.h"

#include <algorithm>
#include <chrono>
#include <utility>
#include <vector>

namespace {

std::chrono::steady_clock::time_point g_last_imgui_frame = std::chrono::steady_clock::now();

ImGuiKey ccb_special_key_to_imgui(int c) {
    switch (c) {
        case KEY_DOWN:      return ImGuiKey_DownArrow;
        case KEY_UP:        return ImGuiKey_UpArrow;
        case KEY_LEFT:      return ImGuiKey_LeftArrow;
        case KEY_RIGHT:     return ImGuiKey_RightArrow;
        case KEY_HOME:      return ImGuiKey_Home;
        case KEY_END:       return ImGuiKey_End;
        case KEY_BACKSPACE: return ImGuiKey_Backspace;
        case 8:             return ImGuiKey_Backspace;
        case 127:           return ImGuiKey_Backspace;
        case KEY_DC:        return ImGuiKey_Delete;
        case KEY_PPAGE:     return ImGuiKey_PageUp;
        case KEY_NPAGE:     return ImGuiKey_PageDown;
        case KEY_ENTER:     return ImGuiKey_Enter;
        case '\n':          return ImGuiKey_Enter;
        case '\r':          return ImGuiKey_Enter;
        case '\t':          return ImGuiKey_Tab;
        case KEY_ESCAPE:    return ImGuiKey_Escape;
        default: break;
    }
    if (c >= KEY_F(1) && c <= KEY_F(12)) {
        return static_cast<ImGuiKey>(ImGuiKey_F1 + (c - KEY_F(1)));
    }
    return ImGuiKey_None;
}

} // namespace

void ImTui_ImplNcurses_Init(float /*fps_active*/, float /*fps_idle*/) {
    if (ImGui::GetIO().BackendPlatformUserData == nullptr) {
        ImGui::GetIO().BackendPlatformUserData = new ImTui::ImplImtui_Data();
    }
    ImGui::GetIO().DisplaySize = ImVec2(static_cast<float>(get_window_width()),
                                        static_cast<float>(get_window_height()));
    ImGui::GetIO().KeyRepeatDelay = 0.05f;
    ImGui::GetIO().KeyRepeatRate = 0.05f;
    g_last_imgui_frame = std::chrono::steady_clock::now();
}

void ImTui_ImplNcurses_Shutdown() {
    // ImTui_ImplText_Shutdown owns freeing ImplImtui_Data
}

bool ImTui_ImplNcurses_NewFrame(std::vector<std::pair<int, ImTui::mouse_event>> key_events) {
    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize = ImVec2(static_cast<float>(get_window_width()),
                            static_cast<float>(get_window_height()));

    const auto now = std::chrono::steady_clock::now();
    float dt = std::chrono::duration<float>(now - g_last_imgui_frame).count();
    g_last_imgui_frame = now;
    if (dt <= 0.0f || dt > 0.25f) {
        dt = 1.0f / 60.0f;
    }
    io.DeltaTime = dt;

    // Release one-shot keys from previous tick
    for (int k = static_cast<int>(ImGuiKey_NamedKey_BEGIN); k < static_cast<int>(ImGuiKey_NamedKey_END); ++k) {
        const ImGuiKey key = static_cast<ImGuiKey>(k);
        if (!ImGui::IsAliasKey(key) && ImGui::IsKeyDown(key)) {
            io.AddKeyEvent(key, false);
        }
    }

    bool had_input = false;
    for (const auto &ev : key_events) {
        const int c = ev.first;
        // KEY_MOUSE defined as 0x199 in cata_imgui.cpp under HEADLESS
        if (c == 0x199) {
            io.MousePos = ImVec2(static_cast<float>(ev.second.x), static_cast<float>(ev.second.y));
            const unsigned long b = ev.second.bstate;
            if (b & 0x0002) io.MouseDown[0] = true;
            if (b & 0x0001) io.MouseDown[0] = false;
            if (b & 0x0800) io.MouseDown[1] = true;
            if (b & 0x0400) io.MouseDown[1] = false;
            had_input = true;
            continue;
        }
        const ImGuiKey special = ccb_special_key_to_imgui(c);
        if (special != ImGuiKey_None) {
            io.AddKeyEvent(special, true);
            if (c == KEY_BTAB) {
                io.AddKeyEvent(ImGuiKey_LeftShift, true);
                io.AddKeyEvent(ImGuiKey_Tab, true);
            }
            had_input = true;
        } else if (c >= 32) {
            io.AddInputCharacter(static_cast<unsigned int>(c));
            had_input = true;
        }
    }
    return had_input;
}

void ImTui_ImplNcurses_DrawScreen(bool /*active*/) {
    // Compositing happens deterministically inside BridgeState::publish_frame()
    ccb_bridge::state().publish_frame();
}

void ImTui_ImplNcurses_UploadColorPair(short /*p*/, short /*f*/, short /*b*/) {}
void ImTui_ImplNcurses_SetAllocedPairCount(short /*p*/) {}

bool ImTui_ImplNcurses_ProcessEvent() {
    return true;
}

namespace ccb_bridge {

void composite_imtui_onto_work_buffer() {
    if (!ImGui::GetCurrentContext() || GImGui == nullptr) {
        return;
    }
    ImTui::ImplImtui_Data *bd = ImTui::ImTui_Impl_GetBackendData();
    if (!bd || bd->Screen.data == nullptr || bd->Screen.nx <= 0 || bd->Screen.ny <= 0) {
        return;
    }

    auto &st = state();
    const ImTui::TScreen &scr = bd->Screen;
    const int cols = st.work_cols;
    const int rows = st.work_rows;

    // Composite every active, visible, non-collapsed ImGui window onto work_cells
    for (int i = 0; i < GImGui->Windows.Size; ++i) {
        const ImGuiWindow *imwin = GImGui->Windows[i];
        if (!imwin || !imwin->Active || imwin->Hidden || imwin->Collapsed) {
            continue;
        }
        if (imwin->Size.x <= 0.0f || imwin->Size.y <= 0.0f) {
            continue;
        }

        const int x0 = std::max(0, static_cast<int>(imwin->Pos.x));
        const int y0 = std::max(0, static_cast<int>(imwin->Pos.y));
        const int x1 = std::min(cols, std::min(scr.nx, static_cast<int>(imwin->Pos.x + imwin->Size.x + 0.5f)));
        const int y1 = std::min(rows, std::min(scr.ny, static_cast<int>(imwin->Pos.y + imwin->Size.y + 0.5f)));

        for (int y = y0; y < y1; ++y) {
            const size_t dst_row = static_cast<size_t>(y) * static_cast<size_t>(cols);
            const size_t src_row = static_cast<size_t>(y) * static_cast<size_t>(scr.nx);
            for (int x = x0; x < x1; ++x) {
                const ImTui::TCell &tc = scr.data[src_row + static_cast<size_t>(x)];
                CcbTermCell &dst = st.work_cells[dst_row + static_cast<size_t>(x)];
                uint32_t cp = tc.ch;
                uint8_t cw = tc.chwidth;
                if (cp == 0) {
                    cp = ' ';
                    cw = 1;
                }
                if (cw == 0) {
                    cw = 1;
                }
                uint32_t fg_col = (tc.fg == 0 && cp > 32) ? st.palette_rgba(7) : st.palette_rgba(tc.fg);
                uint32_t bg_col = st.palette_rgba(tc.bg);
                if (cp > 32) {
                    const int fr = static_cast<int>(fg_col & 0xFFu);
                    const int fg8 = static_cast<int>((fg_col >> 8) & 0xFFu);
                    const int fb = static_cast<int>((fg_col >> 16) & 0xFFu);
                    const int br = static_cast<int>(bg_col & 0xFFu);
                    const int bg8 = static_cast<int>((bg_col >> 8) & 0xFFu);
                    const int bb = static_cast<int>((bg_col >> 16) & 0xFFu);
                    const int fluma = (fr * 299 + fg8 * 587 + fb * 114) / 1000;
                    const int bluma = (br * 299 + bg8 * 587 + bb * 114) / 1000;
                    if (bluma > 180 && fluma > 155) {
                        fg_col = st.palette_rgba(0); // crisp black text on bright white/yellow/cyan button
                    } else if (bluma < 35 && fluma < 35) {
                        fg_col = st.palette_rgba(7); // prevent invisible black-on-black text
                    }
                }
                dst.codepoint = cp;
                dst.fg_rgba = fg_col;
                dst.bg_rgba = bg_col;
                dst.width = cw;
                dst.flags = CCB_CELL_IMGUI; // clears CCB_CELL_TERRAIN!
                dst.reserved = 0;

                if (cw == 2 && x + 1 < x1) {
                    CcbTermCell &nxt = st.work_cells[dst_row + static_cast<size_t>(x + 1)];
                    nxt.codepoint = 0;
                    nxt.fg_rgba = dst.fg_rgba;
                    nxt.bg_rgba = dst.bg_rgba;
                    nxt.width = 0;
                    nxt.flags = CCB_CELL_IMGUI | CCB_CELL_CONT;
                    nxt.reserved = 0;
                    ++x;
                }
            }
        }
    }
}

} // namespace ccb_bridge
