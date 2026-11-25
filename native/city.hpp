#pragma once

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <array>
#include <bitset>
#include <cstddef>
#include <cstdint>
#include <list>
#include <limits>
#include <memory>
#include <mutex>
#include <random>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace cangling {
using godot::Dictionary;
using godot::Rect2i;
using godot::String;
using godot::Vector2i;

inline constexpr int city_size = 1500;
inline constexpr int sector_size = 60;
inline constexpr int sector_count = city_size / sector_size;
inline constexpr int east_shore = 1376;
inline constexpr int generator_version = 3;
inline constexpr int survey_tile_size = 10;
inline const Vector2i start_tile{1201, 1384};
inline const Vector2i market_tile{1217, 1337};
inline const Vector2i altar_tile{1156, 1364};
inline const Vector2i dock_tile{1331, 1322};
inline const std::array<Vector2i, 4> herb_tiles{{{1325,1345},{1328,1353},{1326,1362},{1328,1368}}};
inline const std::array<Vector2i, 4> steps{{{0,-1},{-1,0},{1,0},{0,1}}};

using Tiles = std::array<char, sector_size * sector_size>;
using BuildingFootprint = std::bitset<sector_size * sector_size>;
struct Plot { Rect2i bounds; const char *name; };
struct Block {
    Tiles ground;
    Tiles upper;
    Tiles attic;
    Tiles ground_surface{};
    Tiles upper_surface{};
    Tiles attic_surface{};
    std::array<BuildingFootprint, 3> enclosed_stories{};
    struct ExtraLevel {
        Tiles tiles{};
        Tiles surface{};
        BuildingFootprint enclosed{};
    };
    std::unordered_map<int, ExtraLevel> extra_levels;
    std::vector<Plot> plots;
};
inline void mark_enclosed_story(Block &block, int z, Vector2i p) {
    const int i = p.y * sector_size + p.x;
    if (z >= 0 && z < 3) block.enclosed_stories[z].set(i);
    else {
        auto [level, inserted] = block.extra_levels.try_emplace(z);
        if (inserted) level->second.tiles.fill(' ');
        level->second.enclosed.set(i);
    }
}
inline bool enclosed_at(const Block &block, int z, int i) {
    if (z >= 0 && z < 3) return block.enclosed_stories[z].test(i);
    const auto level = block.extra_levels.find(z);
    return level != block.extra_levels.end() && level->second.enclosed.test(i);
}
inline Tiles &level_tiles( Block &block, int z ) {
    if( z == 0 ) return block.ground;
    if( z == 1 ) return block.upper;
    if( z == 2 ) return block.attic;
    auto [it, inserted] = block.extra_levels.try_emplace( z );
    if( inserted ) it->second.tiles.fill( ' ' );
    return it->second.tiles;
}
inline const Tiles &level_tiles( const Block &block, int z ) {
    if( z == 0 ) return block.ground;
    if( z == 1 ) return block.upper;
    if( z == 2 ) return block.attic;
    static const Tiles empty = [] { Tiles value{}; value.fill( ' ' ); return value; }();
    const auto it = block.extra_levels.find( z );
    return it == block.extra_levels.end() ? empty : it->second.tiles;
}
inline Tiles &level_surfaces( Block &block, int z ) {
    if( z == 0 ) return block.ground_surface;
    if( z == 1 ) return block.upper_surface;
    if( z == 2 ) return block.attic_surface;
    return block.extra_levels[z].surface;
}
inline const Tiles &level_surfaces( const Block &block, int z ) {
    if( z == 0 ) return block.ground_surface;
    if( z == 1 ) return block.upper_surface;
    if( z == 2 ) return block.attic_surface;
    static const Tiles empty{};
    const auto it = block.extra_levels.find( z );
    return it == block.extra_levels.end() ? empty : it->second.surface;
}

enum class District { farmland, residential, commerce, central, warehouses, port, river, east_bank };
struct CityPlan {
    std::array<std::uint8_t, sector_count * sector_count> roads{};
    std::array<bool, sector_count> bridges{};
    std::array<int, city_size> shores{};
    Vector2i civic_center;
    Vector2i trade_center;
    Vector2i orchard_center;
    std::array<Vector2i, 3> civic_sites;
    std::uint32_t seed = 0;
    void generate(std::uint32_t value);
    District district_at(Vector2i s) const;
    bool connected(Vector2i s, int direction) const;
    int road_mask(Vector2i s) const;
    std::vector<Vector2i> road_path(Vector2i from, int direction) const;
    char overview(Vector2i s) const;
};
const char *district_name(District district);
bool south_gate_column(int x);
void fill_streets(Block &block, Vector2i sector, const CityPlan &plan);
void shape_streets(Block &block, Vector2i sector, const CityPlan &plan);
std::uint32_t sector_seed(std::uint32_t seed, Vector2i sector);
int random_int(std::mt19937 &rng, int low, int high);
void build_plot(Block &block, Vector2i origin, const char *kind, std::mt19937 &rng);
void build_street_plot(Block &block, Vector2i origin, const char *kind, std::mt19937 &rng);
void build_specialty_plot(Block &block, Vector2i origin, const char *kind, std::mt19937 &rng, bool keep_footprint);
void repair_windows(Block &block);
inline bool passable_tile(char tile) {
    // CCB passable rules: floors, stairs, doors, open windows (climbable), beds, chairs & benches (steppable).
    return std::string_view("Diov^Xs:.+=ObqS").find(tile) != std::string_view::npos;
}
inline char &tile_ref(Tiles &tiles, int x, int y) { return tiles[y * sector_size + x]; }
inline bool in_city(Vector2i p) { return p.x >= 0 && p.y >= 0 && p.x < city_size && p.y < city_size; }
inline Vector2i sector_at(Vector2i p) { return {p.x / sector_size, p.y / sector_size}; }
inline Vector2i hub(Vector2i sector) { return sector * sector_size + Vector2i(1, 1); }

struct SectorGridSnapshot {
    int min_sx = 0;
    int min_sy = 0;
    int cols = 0;
    int rows = 0;
    std::vector<std::shared_ptr<const Block>> blocks;

    const Block *at(int sx, int sy) const {
        const int lx = sx - min_sx;
        const int ly = sy - min_sy;
        if (lx < 0 || ly < 0 || lx >= cols || ly >= rows) return nullptr;
        return blocks[static_cast<std::size_t>(ly * cols + lx)].get();
    }
};

class City {
    std::uint32_t seed = 0;
    mutable std::mutex cache_mutex;
    std::list<int> recent;
    struct Cached { std::shared_ptr<const Block> block; std::list<int>::iterator position; };
    std::unordered_map<int, Cached> cache;
    std::shared_ptr<const Block> block_at(Vector2i sector);
    std::shared_ptr<const Block> try_cached(Vector2i sector) const;
public:
    CityPlan plan;
    int layout = generator_version;
    void reset(std::uint32_t new_seed, int version = generator_version);
    std::shared_ptr<Block> generate_block(Vector2i sector) const;
    void prewarm_sectors(Rect2i area);
    SectorGridSnapshot snapshot_sectors(Rect2i area);
    std::size_t cached_sector_count() const;
    std::size_t memory_bytes() const;
    std::size_t trim_cache(std::size_t keep_recent);
    char tile(Vector2i p, int floor);
    int lighting_column(Vector2i p, int floor, int layers);
    char surface(Vector2i p, int floor);
    String location(Vector2i p);
    godot::PackedByteArray survey();
    Dictionary landmarks() const;
};
}
