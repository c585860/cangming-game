#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include "ccb_bridge/ccb_bridge_api.h"

#include <cstdint>
#include <vector>

namespace cangling {

class CcbEngine : public godot::RefCounted {
    GDCLASS(CcbEngine, godot::RefCounted)

public:
    CcbEngine();
    ~CcbEngine() override;

    bool load_library();
    bool is_library_loaded() const;
    godot::String get_last_error() const;

    bool start(const godot::String &base_dir, const godot::String &user_dir, int cols, int rows);
    void shutdown();
    void resume_session();
    bool is_running() const;
    bool is_waiting_resume() const;
    godot::String get_status() const;

    void send_key(int key_code, const godot::String &utf8_text, bool ctrl, bool alt, bool shift);
    void send_text_input(const godot::String &utf8_text);
    void send_ime_edit(const godot::String &utf8_edit);
    void send_mouse(int action, int cell_x, int cell_y, int wheel);
    void resize(int cols, int rows);

    int64_t get_generation() const;
    int64_t get_world_generation() const;
    int take_map_zoom_steps() const;
    int64_t get_scene3d_generation() const;
    int64_t get_audio_generation() const;
    void set_world_capture_radius(int rad_x, int rad_y);
    godot::Dictionary get_loading_state() const;
    godot::Dictionary poll_terminal_frame();
    godot::Dictionary poll_world_snapshot();
    void set_render3d_mode(bool enabled, bool same_level_only);
    godot::Dictionary poll_scene3d_snapshot();
    godot::Array poll_audio_events();
    godot::Dictionary synthesize_combat_audio(int kind, int subtype, int variant, int space_mode, bool distant, float tail_scale);
    godot::Dictionary synthesize_ambience_loop(int layer_id);
    godot::PackedByteArray synthesize_combat_pcm(int kind, int subtype, int variant, int space_mode, bool distant, float tail_scale);
    godot::PackedByteArray synthesize_ambience_loop_pcm(int layer_id);
    godot::Dictionary get_tileset_config() const;
    godot::Dictionary get_looks_like_map() const;

    static void shutdown_global_bridge();

protected:
    static void _bind_methods();

private:
    godot::String last_error_;
    uint32_t last_polled_minimap_seq_ = 0;
    std::vector<uint8_t> surf_cls_buf_;
    std::vector<CcbTermCell> term_buf_;
    std::vector<CcbWorldTile> tile_buf_;
    std::vector<char> str_buf_;
    std::vector<CcbWorldCreature> critter_buf_;
    std::vector<CcbWorldLight> light_buf_;
    std::vector<CcbWorldPathPoint> path_buf_;
    std::vector<CcbWorldSct> sct_buf_;
    std::vector<CcbWorldVfx> vfx_buf_;
    std::vector<CcbAudioEvent> audio_buf_;
    std::vector<char> worn_buf_;
    std::vector<uint8_t> minimap_buf_;
    std::vector<CcbScene3DItem> scene3d_items_buf_;
    std::vector<char> scene3d_str_buf_;
    std::vector<CcbScene3DLight> scene3d_lights_buf_;
};

} // namespace cangling
