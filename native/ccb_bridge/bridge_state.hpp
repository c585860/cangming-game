#pragma once

#include "ccb_bridge_api.h"

#include <array>
#include <atomic>
#include <chrono>
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
    TextInput,
    ImeEdit,
    Mouse,
    Resize,
    Refresh3D,
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

struct Scene3DSnapshot {
    CcbScene3DHeader header{};
    std::vector<CcbScene3DItem> items;
    std::vector<char> strings;
    std::vector<CcbScene3DLight> lights;
};

struct BridgeState {
    // Lifecycle
    std::atomic<bool> started{false};
    std::atomic<bool> running{false};
    std::atomic<bool> shutdown_requested{false};
    std::atomic<bool> waiting_resume{false};
    std::atomic<bool> resume_signal{false};
    std::atomic<uint64_t> generation{0};
    std::atomic<uint64_t> world_generation{0};
    std::atomic<uint64_t> scene3d_generation{0};
    std::atomic<int> capture_rad_x{22};
    std::atomic<int> capture_rad_y{16};
    std::atomic<bool> force_world_refresh{false};

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
    bool work_cursor_active = false;
    std::vector<CcbTermCell> work_cells;
    std::vector<CcbTermCell> curses_layer; // persistent curses screen before ImTui overlay

    // Vanilla loading screen state (gfx/loading_screens/ artwork + tips + real-time steps)
    std::mutex loading_mtx;
    CcbLoadingState loading_state{};

    // Transient gunfire / muzzle flash / beam / explosion VFX ring buffer
    std::mutex vfx_mtx;
    std::deque<CcbWorldVfx> vfx_ring;
    std::atomic<uint64_t> next_vfx_id{1};

    // Real-time physical combat & world audio event ring buffer (gunshots, bursts, explosions, hits)
    std::mutex audio_mtx;
    std::deque<CcbAudioEvent> audio_ring;
    std::atomic<uint64_t> next_audio_id{1};
    std::atomic<uint64_t> next_burst_id{1};

    // Active burst synchronization context (set on CCB worker thread in generate_gun_sound, read in play_vfx / do_projectile_hit)
    uint64_t active_burst_id = 0;
    uint16_t active_shot_delay_ms = 0;
    uint16_t active_shot_rpm = 0;
    uint8_t  active_shot_index = 0;
    uint8_t  active_gun_caliber = CCB_CALIBER_DEFAULT;
    uint8_t  active_vfx_flags = 0;
    bool     active_tracer_emitted = false;
    std::chrono::steady_clock::time_point active_burst_origin_tp{};
    std::chrono::steady_clock::time_point active_shot_wall_tp{};

    // Published snapshots (locked only on swap/copy) + reusable worker-thread double buffers (zero heap churn!)
    std::mutex snap_mtx;
    TermSnapshot published_term;
    WorldSnapshot published_world;
    Scene3DSnapshot published_scene3d;
    WorldSnapshot work_world;
    Scene3DSnapshot work_scene3d;

    // Worker-thread change detection signatures (skip full 2D/3D world recapture during menu/sidebar-only updates!)
    uint64_t last_world_sig = 0;
    bool     last_world_valid = false;
    uint64_t last_scene3d_sig = 0;
    bool     last_scene3d_valid = false;
    uint64_t last_minimap_sig = 0;
    uint32_t minimap_seq_counter = 0;

    // Live Godot 3D renderer mode flags (zero cost when render3d_enabled == false)
    std::atomic<bool> render3d_enabled{false};
    std::atomic<bool> render3d_same_level_only{false};
    std::atomic<bool> render3d_refresh_requested{false};

    void set_status(const std::string &msg);
    std::string get_status();
    void push_vfx_event(uint8_t kind, int ox, int oy, int tx, int ty, int z,
                        float radius, float light_intensity, uint32_t color_rgba,
                        uint16_t arc_deg = 0, uint16_t delay_ms = 0,
                        uint8_t caliber_class = CCB_CALIBER_DEFAULT,
                        uint8_t shot_index = 0, uint8_t flags = 0);
    void push_audio_event(uint8_t kind, uint8_t subtype, int x, int y, int z,
                          float volume, float pan, float radius,
                          uint64_t burst_id = 0, uint16_t rpm = 0, uint16_t delay_ms = 0,
                          uint8_t shot_index = 0, uint8_t flags = 0);
    bool has_recent_shot_context() const;
    void init_default_palette();
    uint32_t palette_rgba(int color_idx) const;
    void resize_work_buffers(int cols, int rows);
    void clear_work_buffers();
    void publish_frame();
};

BridgeState &state();

// Fast signature of live world + visible w_terrain curses state (skips redundant captures when only menus/sidebar update)
uint64_t compute_world_state_sig(bool has_terrain, int rad_x, int rad_y);

// Populates WorldSnapshot from live CCB game state (called on CCB thread during publish_frame)
void capture_world_snapshot(WorldSnapshot &out, uint64_t gen, bool has_terrain);

// Populates multi-Z Scene3DSnapshot using CCB's exact 3D renderer logic (called only when render3d_enabled)
void capture_scene3d_snapshot(Scene3DSnapshot &out, uint64_t gen, bool has_terrain);

// Composites active ImTui windows on top of curses_layer -> work_cells
void composite_imtui_onto_work_buffer();

// Resize helper called from platform_input when HostEventKind::Resize arrives
void apply_host_resize(int cols, int rows);

} // namespace ccb_bridge
