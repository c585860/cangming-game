#pragma once

#include "ccb_bridge_api.h"

#include <array>
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <exception>
#include <mutex>
#include <string>
#include <vector>

namespace ccb_bridge {

struct ShutdownException : public std::exception {
    const char *what() const noexcept override { return "ccb_bridge shutdown requested"; }
};

enum class HostEventKind {
    Key,
    Mouse,
    Resize,
    Shutdown
};

struct HostEvent {
    HostEventKind kind = HostEventKind::Key;
    int key_code = 0;
    std::string utf8_text;
    bool ctrl = false;
    bool alt = false;
    bool shift = false;
    int mouse_action = 0;
    int cell_x = 0;
    int cell_y = 0;
    int wheel = 0;
    int cols = 0;
    int rows = 0;
};

struct TermSnapshot {
    CcbTermHeader header{};
    std::vector<CcbTermCell> cells;
};

struct WorldSnapshot {
    CcbWorldHeader header{};
    std::vector<CcbWorldTile> tiles;
    std::vector<char> strings;
    std::vector<CcbWorldCreature> creatures;
    std::vector<CcbWorldLight> lights;
    std::vector<CcbWorldPathPoint> path_points;
    std::vector<CcbWorldSct> sct_entries;
    std::string worn_csv;
    std::vector<uint8_t> minimap_rgba;
};

struct BridgeState {
    // Lifecycle
    std::atomic<bool> started{false};
    std::atomic<bool> running{false};
    std::atomic<bool> shutdown_requested{false};
    std::atomic<bool> waiting_resume{false};
    std::atomic<bool> resume_signal{false};
    std::atomic<uint64_t> generation{0};

    std::mutex status_mtx;
    std::string status_message = "idle";

    // Input queue
    std::mutex input_mtx;
    std::condition_variable input_cv;
    std::deque<HostEvent> input_queue;

    // Pending resize / logical terminal size
    std::atomic<int> term_cols{160};
    std::atomic<int> term_rows{45};

    // Resume condition variable (when CCB main menu exits to Core Pack Launcher)
    std::mutex resume_mtx;
    std::condition_variable resume_cv;

    // 16-color + 256-color RGBA palette (R | G<<8 | B<<16 | A<<24)
    std::array<uint32_t, 256> palette{};
    std::array<std::pair<short, short>, 256> color_pairs{};

    // Working screen buffer on CCB thread
    int work_cols = 0;
    int work_rows = 0;
    int work_terrain_x = 0;
    int work_terrain_y = 0;
    int work_terrain_w = 0;
    int work_terrain_h = 0;
    int work_cursor_x = 0;
    int work_cursor_y = 0;
    std::vector<CcbTermCell> work_cells;
    std::vector<CcbTermCell> curses_layer; // persistent curses screen before ImTui overlay

    // Published snapshots (locked only on swap/copy)
    std::mutex snap_mtx;
    TermSnapshot published_term;
    WorldSnapshot published_world;

    void set_status(const std::string &msg);
    std::string get_status();
    void init_default_palette();
    uint32_t palette_rgba(int color_idx) const;
    void resize_work_buffers(int cols, int rows);
    void clear_work_buffers();
    void publish_frame();
};

BridgeState &state();

// Populates WorldSnapshot from live CCB game state (called on CCB thread during publish_frame)
void capture_world_snapshot(WorldSnapshot &out, uint64_t gen, bool has_terrain);

// Composites active ImTui windows on top of curses_layer -> work_cells
void composite_imtui_onto_work_buffer();

// Resize helper called from platform_input when HostEventKind::Resize arrives
void apply_host_resize(int cols, int rows);

} // namespace ccb_bridge
