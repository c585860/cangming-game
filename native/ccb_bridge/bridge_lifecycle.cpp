#include "bridge_state.hpp"
#include "bridge_tileset_options.hpp"

#include "cached_options.h"
#include "cata_allocator.h"
#include "cata_imgui.h"
#include "compatibility.h"
#include "crash.h"
#include "cursesdef.h"
#include "debug.h"
#include "event.h"
#include "event_bus.h"
#include "filesystem.h"
#include "game.h"
#include "game_constants.h"
#include "game_ui.h"
#include "get_version.h"
#include "input.h"
#include "json.h"
#include "lua_platform_loader.h"
#include "main_menu.h"
#include "mapsharing.h"
#include "options.h"
#include "ordered_static_globals.h"
#include "output.h"
#include "path_info.h"
#include "rng.h"
#include "system_locale.h"
#include "translations.h"
#include "ui_manager.h"

#include <flatbuffers/util.h>
#include <imgui/imgui.h>

#include <clocale>
#include <cstring>
#include <ctime>
#include <exception>
#include <iostream>
#include <locale>
#include <memory>
#include <string>
#include <thread>
#include <vector>

// Avoid snmalloc overriding global operator new/delete inside a host-loaded Windows DLL
void cata::init_allocator() {}

namespace {

std::thread g_worker_thread;
std::string g_base_dir;
std::string g_user_dir;

bool assure_essential_dirs() {
    using namespace PATH_INFO;
    const std::vector<std::string> dirs{
        config_dir(),
        savedir(),
        templatedir(),
        user_font(),
        user_sound().get_unrelative_path().u8string(),
        user_gfx().get_unrelative_path().u8string()
    };
    for (const std::string &d : dirs) {
        if (!assure_dir_exist(d)) {
            return false;
        }
    }
    return true;
}

void worker_main() {
    auto &st = ccb_bridge::state();
    st.running.store(true, std::memory_order_release);
    st.set_status("initializing_runtime");

    try {
        cata::init_allocator();
        ordered_static_globals();
        reset_floating_point_mode();
#if defined(FLATBUFFERS_LOCALE_INDEPENDENT) && (FLATBUFFERS_LOCALE_INDEPENDENT > 0)
        flatbuffers::ClassicLocale::Get();
#endif

        PATH_INFO::init_base_path(g_base_dir);
        PATH_INFO::init_user_dir(g_user_dir);
        PATH_INFO::set_standard_filenames();
        MAP_SHARING::setDefaults();

        if (!dir_exist(PATH_INFO::datadir())) {
            st.set_status("error: datadir not found: " + PATH_INFO::datadir());
            st.running.store(false, std::memory_order_release);
            return;
        }
        assure_dir_exist(PATH_INFO::user_dir());
        assure_dir_exist(PATH_INFO::config_dir());

        setupDebug(DebugOutput::file);
        json_error_output_colors = json_error_output_colors_t::color_tags;

        if (setlocale(LC_ALL, "") != nullptr) {
            try {
                std::locale::global(std::locale(""));
            } catch (...) {
                std::locale::global(std::locale::classic());
            }
        }

        auto log_step = [&](const char *tag) {
            st.set_status(tag);
            std::fprintf(stderr, "[ccb_bridge] %s\n", tag);
            std::fflush(stderr);
        };

        log_step("options_init");
        get_options().init();
        ccb_bridge::enable_native_tileset_options();
        log_step("options_load");
        get_options().load();
        options_manager::update_options_cache();

#if defined(LOCALIZE)
        if (get_option<std::string>("USE_LANG").empty()) {
            log_step("options_set_zh_CN");
            get_options().get_option("USE_LANG").setValue("zh_CN");
            get_options().save();
        }
#endif

        log_step("init_interface");
        FULL_SCREEN_WIDTH = EVEN_MINIMUM_TERM_WIDTH;
        FULL_SCREEN_HEIGHT = EVEN_MINIMUM_TERM_HEIGHT;
        catacurses::init_interface();

        log_step("set_language");
        set_language_from_options();
        rng_set_engine_seed(static_cast<unsigned int>(std::time(nullptr)));

        log_step("init_ui");
        game_ui::init_ui();
        log_step("creating_game_instance");
        g = std::make_unique<game>();

        log_step("loading_static_data");
        g->load_static_data();

        log_step("init_imgui_colors");
        cataimgui::init_colors();
        {
            ImGuiStyle &style = ImGui::GetStyle();
            // In ImTui 1.0 unit = 1 whole character cell; keep WindowBorderSize = 0.0f so it never overwrites text!
            style.WindowBorderSize = 0.0f;
            style.WindowBorderAscii = false;
            style.Colors[ImGuiCol_WindowBg] = ImVec4(0.0f, 0.0f, 0.0f, 1.0f);
            style.Colors[ImGuiCol_PopupBg]  = ImVec4(0.0f, 0.0f, 0.0f, 1.0f);
            style.Colors[ImGuiCol_Text]     = ImVec4(0.95f, 0.95f, 0.95f, 1.0f);
        }
        ImGui::GetPlatformIO().Platform_LocaleDecimalPoint =
            static_cast<unsigned char>(*localeconv()->decimal_point);
        catacurses::curs_set(0);
        assure_essential_dirs();
        replay_buffered_debugmsg_prompts();

        log_step("ready");

        while (!st.shutdown_requested.load(std::memory_order_acquire)) {
            main_menu menu;
            const bool start_game = menu.opening_screen();
            if (!start_game) {
                if (st.shutdown_requested.load(std::memory_order_acquire)) {
                    break;
                }
                // User chose Quit in CCB Main Menu -> park engine cleanly so Godot can return to Core Pack Launcher
                // and re-entering CCB later is instant (0ms reload!).
                st.waiting_resume.store(true, std::memory_order_release);
                st.set_status("paused_in_launcher");
                st.publish_frame();

                std::unique_lock<std::mutex> lk(st.resume_mtx);
                st.resume_cv.wait(lk, [&]() {
                    return st.resume_signal.load(std::memory_order_acquire) ||
                           st.shutdown_requested.load(std::memory_order_acquire);
                });
                st.resume_signal.store(false, std::memory_order_release);
                st.waiting_resume.store(false, std::memory_order_release);
                if (st.shutdown_requested.load(std::memory_order_acquire)) {
                    break;
                }
                st.set_status("ready");
                continue;
            }

            shared_ptr_fast<ui_adaptor> ui = g->create_or_get_main_ui_adaptor();
            get_event_bus().send<event_type::game_begin>(getVersionString());
            while (!st.shutdown_requested.load(std::memory_order_acquire) && !g->do_turn()) {
                // Turn loop driven cleanly by real CCB simulation
            }
            cata::lua_platform::shutdown();
        }
    } catch (const ccb_bridge::ShutdownException &) {
        st.set_status("shutdown");
    } catch (const std::exception &ex) {
        st.set_status(std::string("error: ") + ex.what());
    } catch (...) {
        st.set_status("error: unknown exception in ccb worker");
    }

    // Clean teardown without calling std::exit()
    Json::globally_report_unvisited_members(false);
    cata::lua_platform::shutdown();
    g.reset();
    catacurses::endwin();
    imclient.reset();
    deinitDebug();

    st.waiting_resume.store(false, std::memory_order_release);
    st.running.store(false, std::memory_order_release);
}

} // namespace

extern "C" {

CCB_API int ccb_start(const char *base_dir, const char *user_dir, int cols, int rows) {
    auto &st = ccb_bridge::state();
    if (st.running.load(std::memory_order_acquire)) {
        ccb_push_resize(cols, rows);
        if (st.waiting_resume.load(std::memory_order_acquire)) {
            ccb_resume_session();
        }
        return 1;
    }
    if (g_worker_thread.joinable()) {
        g_worker_thread.join();
    }

    g_base_dir = base_dir ? base_dir : "";
    g_user_dir = user_dir ? user_dir : ".";
    st.shutdown_requested.store(false, std::memory_order_release);
    st.waiting_resume.store(false, std::memory_order_release);
    st.resume_signal.store(false, std::memory_order_release);
    st.term_cols.store(cols > 0 ? cols : 160, std::memory_order_relaxed);
    st.term_rows.store(rows > 0 ? rows : 45, std::memory_order_relaxed);
    st.started.store(true, std::memory_order_release);
    st.set_status("starting");

    g_worker_thread = std::thread(worker_main);
    return 1;
}

CCB_API void ccb_shutdown(void) {
    auto &st = ccb_bridge::state();
    st.shutdown_requested.store(true, std::memory_order_release);
    {
        std::lock_guard<std::mutex> lk(st.input_mtx);
        ccb_bridge::HostEvent ev{};
        ev.kind = ccb_bridge::HostEventKind::Shutdown;
        st.input_queue.push_back(ev);
    }
    st.input_cv.notify_all();
    st.resume_cv.notify_all();
    if (g_worker_thread.joinable()) {
        g_worker_thread.join();
    }
}

CCB_API int ccb_is_running(void) {
    return ccb_bridge::state().running.load(std::memory_order_acquire) ? 1 : 0;
}

CCB_API int ccb_is_waiting_resume(void) {
    return ccb_bridge::state().waiting_resume.load(std::memory_order_acquire) ? 1 : 0;
}

CCB_API void ccb_resume_session(void) {
    auto &st = ccb_bridge::state();
    {
        std::lock_guard<std::mutex> lk(st.resume_mtx);
        st.resume_signal.store(true, std::memory_order_release);
    }
    st.resume_cv.notify_all();
}

CCB_API void ccb_request_return_to_launcher(void) {
    auto &st = ccb_bridge::state();
    st.waiting_resume.store(true, std::memory_order_release);
}

CCB_API int ccb_get_status_message(char *buf, int buf_size) {
    if (!buf || buf_size <= 0) return 0;
    const std::string s = ccb_bridge::state().get_status();
    const int n = static_cast<int>(std::min<size_t>(s.size(), static_cast<size_t>(buf_size - 1)));
    std::memcpy(buf, s.data(), static_cast<size_t>(n));
    buf[n] = '\0';
    return n;
}

CCB_API void ccb_push_key(int key_code, const char *utf8_text, int ctrl, int alt, int shift) {
    auto &st = ccb_bridge::state();
    ccb_bridge::HostEvent ev{};
    ev.kind = ccb_bridge::HostEventKind::Key;
    ev.key_code = key_code;
    if (utf8_text && utf8_text[0] != '\0') {
        ev.utf8_text = utf8_text;
    }
    ev.ctrl = ctrl != 0;
    ev.alt = alt != 0;
    ev.shift = shift != 0;
    {
        std::lock_guard<std::mutex> lk(st.input_mtx);
        st.input_queue.push_back(std::move(ev));
    }
    st.input_cv.notify_one();
}

CCB_API void ccb_push_mouse(int action, int cell_x, int cell_y, int wheel) {
    auto &st = ccb_bridge::state();
    ccb_bridge::HostEvent ev{};
    ev.kind = ccb_bridge::HostEventKind::Mouse;
    ev.mouse_action = action;
    ev.cell_x = cell_x;
    ev.cell_y = cell_y;
    ev.wheel = wheel;
    {
        std::lock_guard<std::mutex> lk(st.input_mtx);
        st.input_queue.push_back(std::move(ev));
    }
    st.input_cv.notify_one();
}

CCB_API void ccb_push_resize(int cols, int rows) {
    auto &st = ccb_bridge::state();
    ccb_bridge::HostEvent ev{};
    ev.kind = ccb_bridge::HostEventKind::Resize;
    ev.cols = cols;
    ev.rows = rows;
    {
        std::lock_guard<std::mutex> lk(st.input_mtx);
        st.input_queue.push_back(std::move(ev));
    }
    st.input_cv.notify_one();
}

CCB_API uint64_t ccb_get_generation(void) {
    return ccb_bridge::state().generation.load(std::memory_order_acquire);
}

CCB_API int ccb_copy_terminal_frame(CcbTermHeader *out_header, CcbTermCell *out_cells, int max_cells) {
    auto &st = ccb_bridge::state();
    std::lock_guard<std::mutex> lk(st.snap_mtx);
    if (out_header) {
        *out_header = st.published_term.header;
    }
    const int total = static_cast<int>(st.published_term.cells.size());
    if (out_cells && max_cells > 0 && total > 0) {
        const int copy_n = std::min(total, max_cells);
        std::memcpy(out_cells, st.published_term.cells.data(),
                    static_cast<size_t>(copy_n) * sizeof(CcbTermCell));
        return copy_n;
    }
    return total;
}

CCB_API int ccb_copy_world_snapshot(
    CcbWorldHeader *out_header,
    CcbWorldTile *out_tiles, int max_tiles,
    char *out_strings, int max_strings_bytes,
    CcbWorldCreature *out_creatures, int max_creatures,
    CcbWorldLight *out_lights, int max_lights,
    char *out_worn_csv, int max_worn_bytes,
    uint8_t *out_minimap_rgba, int max_minimap_bytes)
{
    auto &st = ccb_bridge::state();
    std::lock_guard<std::mutex> lk(st.snap_mtx);
    const auto &w = st.published_world;
    if (out_header) {
        *out_header = w.header;
    }
    if (!w.header.valid) {
        return 0;
    }
    if (out_tiles && max_tiles > 0 && !w.tiles.empty()) {
        const int n = std::min(max_tiles, static_cast<int>(w.tiles.size()));
        std::memcpy(out_tiles, w.tiles.data(), static_cast<size_t>(n) * sizeof(CcbWorldTile));
    }
    if (out_strings && max_strings_bytes > 0 && !w.strings.empty()) {
        const int n = std::min(max_strings_bytes, static_cast<int>(w.strings.size()));
        std::memcpy(out_strings, w.strings.data(), static_cast<size_t>(n));
    }
    if (out_creatures && max_creatures > 0 && !w.creatures.empty()) {
        const int n = std::min(max_creatures, static_cast<int>(w.creatures.size()));
        std::memcpy(out_creatures, w.creatures.data(), static_cast<size_t>(n) * sizeof(CcbWorldCreature));
    }
    if (out_lights && max_lights > 0 && !w.lights.empty()) {
        const int n = std::min(max_lights, static_cast<int>(w.lights.size()));
        std::memcpy(out_lights, w.lights.data(), static_cast<size_t>(n) * sizeof(CcbWorldLight));
    }
    if (out_worn_csv && max_worn_bytes > 0) {
        const int n = std::min(max_worn_bytes - 1, static_cast<int>(w.worn_csv.size()));
        if (n > 0) {
            std::memcpy(out_worn_csv, w.worn_csv.data(), static_cast<size_t>(n));
        }
        out_worn_csv[n] = '\0';
    }
    if (out_minimap_rgba && max_minimap_bytes > 0 && !w.minimap_rgba.empty()) {
        const int n = std::min(max_minimap_bytes, static_cast<int>(w.minimap_rgba.size()));
        std::memcpy(out_minimap_rgba, w.minimap_rgba.data(), static_cast<size_t>(n));
    }
    return 1;
}

CCB_API int ccb_copy_world_effects(
    CcbWorldPathPoint *out_path, int max_path,
    CcbWorldSct *out_sct, int max_sct)
{
    auto &st = ccb_bridge::state();
    std::lock_guard<std::mutex> lk(st.snap_mtx);
    const auto &w = st.published_world;
    if (!w.header.valid) {
        return 0;
    }
    if (out_path && max_path > 0 && !w.path_points.empty()) {
        const int n = std::min(max_path, static_cast<int>(w.path_points.size()));
        std::memcpy(out_path, w.path_points.data(), static_cast<size_t>(n) * sizeof(CcbWorldPathPoint));
    }
    if (out_sct && max_sct > 0 && !w.sct_entries.empty()) {
        const int n = std::min(max_sct, static_cast<int>(w.sct_entries.size()));
        std::memcpy(out_sct, w.sct_entries.data(), static_cast<size_t>(n) * sizeof(CcbWorldSct));
    }
    return 1;
}

CCB_API int ccb_get_tileset_config(
    char *out_name, int max_name,
    char *out_dir, int max_dir,
    char *out_json_file, int max_json,
    int *out_use_tiles)
{
    auto &st = ccb_bridge::state();
    if (!st.running.load(std::memory_order_acquire) || st.generation.load(std::memory_order_acquire) == 0) {
        return 0;
    }
    const ccb_bridge::TilesetConfig cfg = ccb_bridge::get_active_tileset_config();
    auto copy_str = [](char *dst, int cap, const std::string &src) {
        if (!dst || cap <= 0) return;
        const int n = static_cast<int>(std::min<size_t>(src.size(), static_cast<size_t>(cap - 1)));
        if (n > 0) std::memcpy(dst, src.data(), static_cast<size_t>(n));
        dst[n] = '\0';
    };
    copy_str(out_name, max_name, cfg.name);
    copy_str(out_dir, max_dir, cfg.dir);
    copy_str(out_json_file, max_json, cfg.json_file);
    if (out_use_tiles) {
        *out_use_tiles = cfg.use_tiles ? 1 : 0;
    }
    return cfg.dir.empty() ? 0 : 1;
}

CCB_API int ccb_copy_looks_like_table(char *out_buf, int max_bytes) {
    auto &st = ccb_bridge::state();
    if (!st.running.load(std::memory_order_acquire) || st.generation.load(std::memory_order_acquire) == 0) {
        return 0;
    }
    const std::string &tbl = ccb_bridge::get_looks_like_table();
    const int total = static_cast<int>(tbl.size());
    if (out_buf && max_bytes > 0 && total > 0) {
        const int n = std::min(total, max_bytes - 1);
        std::memcpy(out_buf, tbl.data(), static_cast<size_t>(n));
        out_buf[n] = '\0';
        return n;
    }
    return total;
}

} // extern "C"
