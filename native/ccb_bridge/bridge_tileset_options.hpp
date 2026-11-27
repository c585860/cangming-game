#pragma once

#include <string>

namespace ccb_bridge {

// Unhides CCB's native USE_TILES and TILES options under Settings -> Graphics
// and discovers all tilesets in gfx/ and user_gfx/ at runtime (zero recompilation).
void enable_native_tileset_options();

// Reads active tileset selection directly from CCB's options & TILESETS registry.
struct TilesetConfig {
    bool use_tiles = true;
    std::string name;
    std::string dir;
    std::string json_file = "tile_config.json";
};
TilesetConfig get_active_tileset_config();

// Builds/returns cached "id=looks_like\n" table across all CCB terrains, furniture,
// items, monsters, fields, and vehicle parts for 100% authentic tileset fallback.
const std::string &get_looks_like_table();

} // namespace ccb_bridge
