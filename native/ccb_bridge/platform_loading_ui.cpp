#include "bridge_state.hpp"

#include "cached_options.h"
#include "filesystem.h"
#include "input.h"
#include "loading_ui.h"
#include "loading_ui_random.h"
#include "mod_manager.h"
#include "path_info.h"
#include "worldfactory.h"

#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

namespace {

struct BridgeLoadingState {
    loading_ui::random_choices choices;
    std::string tip;
    std::string image_path;
};

BridgeLoadingState *g_blui = nullptr;

void copy_cstr(char *dst, size_t cap, const std::string &src) {
    if (!dst || cap == 0) return;
    const size_t n = std::min(src.size(), cap - 1);
    if (n > 0) {
        std::memcpy(dst, src.data(), n);
    }
    dst[n] = '\0';
}

std::string pick_loading_image_path(loading_ui::random_choices &choices) {
    std::vector<cata_path> imgs;
    bool only_mod_loading_screens = false;

    if (world_generator && world_generator->active_world) {
        std::vector<mod_id> &active_mod_list = world_generator->active_world->active_mod_order;
        for (mod_id &some_mod : active_mod_list) {
            if (!some_mod.is_valid()) {
                continue;
            }
            const MOD_INFORMATION &mod = *some_mod;
            if (mod.disable_other_loading_screens) {
                only_mod_loading_screens = true;
                imgs.clear();
            }
            for (const std::string &img_name : mod.loading_images) {
                for (cata_path &img_path : get_files_from_path(img_name, mod.path, true)) {
                    imgs.emplace_back(img_path);
                }
            }
            if (only_mod_loading_screens) {
                break;
            }
        }
    }

    if (imgs.empty() || !only_mod_loading_screens) {
        const cata_path load_screens_directory = PATH_INFO::gfxdir() / "loading_screens";
        for (cata_path &img_path : get_files_from_path("loading_img", load_screens_directory, true)) {
            imgs.emplace_back(img_path);
        }
    }

    if (imgs.empty()) {
        return {};
    }
    const cata_path chosen = choices.image(imgs);
    return chosen.get_unrelative_path().u8string();
}

} // namespace

void loading_ui::show(const std::string &context, const std::string &step) {
    if (test_mode) {
        return;
    }
    if (g_blui == nullptr) {
        g_blui = new BridgeLoadingState();
        g_blui->tip = g_blui->choices.tip();
        g_blui->image_path = pick_loading_image_path(g_blui->choices);
    } else if (g_blui->image_path.empty()) {
        g_blui->image_path = pick_loading_image_path(g_blui->choices);
    }

    auto &st = ccb_bridge::state();
    {
        std::lock_guard<std::mutex> lk(st.loading_mtx);
        st.loading_state.seq += 1;
        st.loading_state.active = 1;
        copy_cstr(st.loading_state.image_path, sizeof(st.loading_state.image_path), g_blui->image_path);
        copy_cstr(st.loading_state.tip, sizeof(st.loading_state.tip), g_blui->tip);
        copy_cstr(st.loading_state.context, sizeof(st.loading_state.context), context);
        copy_cstr(st.loading_state.step, sizeof(st.loading_state.step), step);
    }
    // Bump generation so Godot immediately repaints live loading progress & artwork!
    st.generation.fetch_add(1, std::memory_order_release);
    inp_mngr.pump_events();
}

void loading_ui::done() {
    auto &st = ccb_bridge::state();
    {
        std::lock_guard<std::mutex> lk(st.loading_mtx);
        st.loading_state.seq += 1;
        st.loading_state.active = 0;
        st.loading_state.context[0] = '\0';
        st.loading_state.step[0] = '\0';
    }
    if (g_blui != nullptr) {
        delete g_blui;
        g_blui = nullptr;
    }
    st.generation.fetch_add(1, std::memory_order_release);
}

void loading_ui::release_gpu_resources() {
    // Godot manages the GPU loading texture lifecycle cleanly on the main thread
}
