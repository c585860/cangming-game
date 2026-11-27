#include "bridge_tileset_options.hpp"

#include "cached_options.h"
#include "cata_path.h"
#include "debug.h"
#include "field_type.h"
#include "filesystem.h"
#include "item_factory.h"
#include "itype.h"
#include "mapdata.h"
#include "monstergenerator.h"
#include "mtype.h"
#include "options.h"
#include "path_info.h"
#include "translations.h"
#include "veh_type.h"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <map>
#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

// Defined in CCB's src/options.cpp (populated by options_manager::build_tilesets_list())
extern std::map<std::string, cata_path> TILESETS;

namespace ccb_bridge {

namespace {

std::mutex g_ts_mtx;
std::string g_looks_like_cache;
size_t g_looks_like_ter_count = 0;

std::string trim_copy(const std::string &s) {
    size_t b = 0;
    while (b < s.size() && (s[b] == ' ' || s[b] == '\t' || s[b] == '\r' || s[b] == '\n')) {
        ++b;
    }
    size_t e = s.size();
    while (e > b && (s[e - 1] == ' ' || s[e - 1] == '\t' || s[e - 1] == '\r' || s[e - 1] == '\n')) {
        --e;
    }
    return s.substr(b, e - b);
}

struct ParsedTilesetTxt {
    std::string name;
    std::string view;
    std::string json_file = "tile_config.json";
};

ParsedTilesetTxt parse_tileset_txt(const std::filesystem::path &dir) {
    ParsedTilesetTxt out;
    const std::filesystem::path txt = dir / "tileset.txt";
    std::ifstream fin(txt);
    if (!fin.is_open()) {
        return out;
    }
    std::string line;
    while (std::getline(fin, line)) {
        const std::string t = trim_copy(line);
        if (t.empty() || t[0] == '#') {
            continue;
        }
        const size_t colon = t.find(':');
        if (colon == std::string::npos) {
            continue;
        }
        const std::string key = trim_copy(t.substr(0, colon));
        const std::string val = trim_copy(t.substr(colon + 1));
        if (key == "NAME") {
            out.name = val;
        } else if (key == "VIEW") {
            out.view = val;
        } else if (key == "JSON" && !val.empty()) {
            out.json_file = val;
        }
    }
    return out;
}

// Also discovers any drop-in tileset folder that contains tile_config.json even without tileset.txt,
// AND verifies all entries in TILESETS actually have a valid tile_config.json.
void discover_extra_tileset_folders(std::vector<options_manager::id_and_option> &items) {
    std::unordered_set<std::string> seen_ids;
    for (const auto &kv : items) {
        seen_ids.insert(kv.first);
    }

    const std::vector<std::filesystem::path> roots = {
        PATH_INFO::user_gfx().get_unrelative_path(),
        PATH_INFO::gfxdir().get_unrelative_path(),
    };

    for (const auto &root : roots) {
        std::error_code ec;
        if (!std::filesystem::exists(root, ec) || !std::filesystem::is_directory(root, ec)) {
            continue;
        }
        for (const auto &entry : std::filesystem::directory_iterator(root, ec)) {
            if (!entry.is_directory(ec)) {
                continue;
            }
            const std::filesystem::path dir = entry.path();
            const std::string folder_name = dir.filename().u8string();
            if (folder_name.empty() || folder_name[0] == '.') {
                continue;
            }
            const ParsedTilesetTxt meta = parse_tileset_txt(dir);
            const std::string json_file = meta.json_file.empty() ? "tile_config.json" : meta.json_file;
            if (!std::filesystem::exists(dir / json_file, ec)) {
                continue;
            }
            const std::string ts_id = meta.name.empty() ? folder_name : meta.name;
            const std::string ts_view = meta.view.empty() ? folder_name : meta.view;
            if (TILESETS.find(ts_id) == TILESETS.end()) {
                TILESETS.emplace(ts_id, cata_path(cata_path::root_path::unknown, dir));
            }
            if (seen_ids.insert(ts_id).second) {
                items.emplace_back(ts_id, no_translation(ts_view));
            }
        }
    }
}

} // namespace

void enable_native_tileset_options() {
    std::lock_guard<std::mutex> lk(g_ts_mtx);
    options_manager &om = get_options();
    if (!om.has_option("USE_TILES") || !om.has_option("TILES")) {
        return;
    }

    // Preserve CCB's already-scanned tilesets from build_tilesets_list() and augment with any
    // drop-in tile_config.json directories placed in gfx/ or user_gfx/ without recompilation.
    std::vector<options_manager::id_and_option> items = om.get_option("TILES").getItems();
    discover_extra_tileset_folders(items);
    if (items.empty()) {
        return;
    }

    // Prefer UNDEAD_PEOPLE (MSX++UndeadPeopleEdition) as initial default if installed, else UltimateCataclysm.
    std::string default_ts = items.front().first;
    for (const auto &it : items) {
        if (it.first == "UNDEAD_PEOPLE") {
            default_ts = it.first;
            break;
        }
    }
    if (default_ts != "UNDEAD_PEOPLE") {
        for (const auto &it : items) {
            if (it.first == "UltimateCataclysm") {
                default_ts = it.first;
                break;
            }
        }
    }

    // Replace USE_TILES and TILES in-place on the "graphics" page with COPT_NO_HIDE so they
    // appear natively in CCB Settings -> Graphics -> Tileset Options (zero upstream CCB edits!).
    // addOptionToPage() sees the option is already on the page and skips duplicating it while
    // emitting a debugmsg; temporarily toggling test_mode + capture_debugmsg_during ensures
    // it is neither logged as an error nor queued as a startup popup.
    const bool prev_test_mode = test_mode;
    test_mode = true;
    (void)capture_debugmsg_during([&]() {
        om.add(
            "USE_TILES", "graphics",
            to_translation("Use tiles"),
            to_translation("If true, renders the map using graphical tilesets with Godot GPU lighting."),
            true,
            options_manager::COPT_NO_HIDE
        );
        om.add(
            "TILES", "graphics",
            to_translation("Choose tileset"),
            to_translation("Choose the tileset you want to use (drop new packs into gfx/ to auto-detect)."),
            items,
            default_ts,
            options_manager::COPT_NO_HIDE
        );
    });
    test_mode = prev_test_mode;
    om.get_option("TILES").setPrerequisite("USE_TILES");
}

TilesetConfig get_active_tileset_config() {
    std::lock_guard<std::mutex> lk(g_ts_mtx);
    TilesetConfig cfg;
    options_manager &om = get_options();
    if (!om.has_option("TILES")) {
        return cfg;
    }

    cfg.use_tiles = om.has_option("USE_TILES") ? get_option<bool>("USE_TILES") : true;
    cfg.name = get_option<std::string>("TILES");

    auto it = TILESETS.find(cfg.name);
    if (it == TILESETS.end() && !TILESETS.empty()) {
        it = TILESETS.find("UNDEAD_PEOPLE");
        if (it == TILESETS.end()) {
            it = TILESETS.begin();
        }
        cfg.name = it->first;
    }

    if (it != TILESETS.end()) {
        const std::filesystem::path dir = it->second.get_unrelative_path();
        cfg.dir = dir.u8string();
        const ParsedTilesetTxt meta = parse_tileset_txt(dir);
        if (!meta.json_file.empty()) {
            cfg.json_file = meta.json_file;
        }
    }
    return cfg;
}

const std::string &get_looks_like_table() {
    std::lock_guard<std::mutex> lk(g_ts_mtx);
    const size_t cur_ter_count = ter_t::count();
    if (cur_ter_count > 1 && cur_ter_count == g_looks_like_ter_count && !g_looks_like_cache.empty()) {
        return g_looks_like_cache;
    }
    g_looks_like_cache.clear();
    if (cur_ter_count <= 1) {
        return g_looks_like_cache;
    }
    g_looks_like_cache.reserve(256 * 1024);

    auto append_pair = [&](const std::string &id, const std::string &ll) {
        if (id.empty() || ll.empty() || id == ll) {
            return;
        }
        g_looks_like_cache.append(id);
        g_looks_like_cache.push_back('=');
        g_looks_like_cache.append(ll);
        g_looks_like_cache.push_back('\n');
    };

    for (size_t i = 0; i < ter_t::count(); ++i) {
        const ter_t &t = ter_id(i).obj();
        append_pair(t.id.str(), t.looks_like);
    }
    for (size_t i = 0; i < furn_t::count(); ++i) {
        const furn_t &f = furn_id(i).obj();
        append_pair(f.id.str(), f.looks_like);
    }
    for (const field_type &ft : field_types::get_all()) {
        append_pair(ft.id.str(), ft.looks_like);
    }
    for (const mtype &m : MonsterGenerator::generator().get_all_mtypes()) {
        append_pair(m.id.str(), m.looks_like);
    }
    for (const itype *it : item_controller->all()) {
        if (it != nullptr) {
            append_pair(it->get_id().str(), it->looks_like.str());
        }
    }
    for (const vpart_info &vp : vehicles::parts::get_all()) {
        const std::string vp_id = "vp_" + vp.id.str();
        if (!vp.looks_like.empty()) {
            const std::string &ll = vp.looks_like;
            if (ll.rfind("vp_", 0) == 0 || ll.rfind("f_", 0) == 0 || ll.rfind("t_", 0) == 0) {
                append_pair(vp_id, ll);
            } else if (vpart_id(ll).is_valid()) {
                append_pair(vp_id, "vp_" + ll);
            } else {
                // Furniture/item looks_like fallback (matches tile_lookup.cpp:277, e.g. f_oven / f_fridge)
                append_pair(vp_id, ll);
            }
        }
    }

    g_looks_like_ter_count = cur_ter_count;
    return g_looks_like_cache;
}

} // namespace ccb_bridge
