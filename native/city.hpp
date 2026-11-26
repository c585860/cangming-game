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

// Compact, 100% handcrafted Cangling City (沧灵城) Jiangnan water-town (240x240 tiles = 4x4 sectors of 60x60)
inline constexpr int city_size = 240;
inline constexpr int sector_size = 60;
inline constexpr int sector_count = city_size / sector_size;
inline constexpr int east_shore = 234;
inline constexpr int generator_version = 5;
inline constexpr int survey_tile_size = 4;

// Player spawns right inside Cangling South Gate (沧灵南门) facing the South Arch Bridge & bustling street
inline const Vector2i start_tile{120, 209};

// 7 Resident Wuxia Starter-Village NPCs in Cangling City (沧灵城)
struct NpcDef {
    const char *id;
    const char *name;
    const char *title;
    Vector2i pos;
    const char *job_label;
    int job_pay;
    int job_minutes;
    int job_stamina;
};

inline constexpr std::size_t kNpcCount = 13;
inline const std::array<NpcDef, kNpcCount> kYangzhouNpcs{{
    {"innkeeper",         "冼老板",       "醉仙楼掌柜",     {126, 157}, "菜肴售卖 · 传授基本厨艺",       0,  15, 0},
    {"blacksmith",        "王铁匠",       "王记铁匠铺",     {114, 157}, "兵刃售卖 · 传授锻造/刀棍",      0,  20, 0},
    {"herbalist",         "平大夫",       "回春堂药铺",     {130, 113}, "丹药售卖 · 传授基本药学",       0,  15, 0},
    {"martial_master",    "陈馆主",       "扬威武馆馆主",   {100, 126}, "内轻空手授艺 · 切磋演武",       0,  20, 0},
    {"weapon_coach",      "周教头",       "扬威武馆教头",   {105, 126}, "兵刃暗器授艺 · 切磋喂招",       0,  20, 0},
    {"scholar",           "顾夫子",       "文昌书院山长",   {130, 88},  "典籍售卖 · 传授读书写字",       0,  15, 0},
    {"pawnbroker",        "唐掌柜",       "利源当铺掌柜",   {114, 130}, "典当收物 · 账房识字启蒙",       0,  15, 0},
    {"boatman",           "老船夫",       "水埠码头",       {167, 166}, "拳脚轻功启蒙 · 漕运交镖",       0,  20, 0},
    {"storyteller",       "说书先生",     "春风茶馆",       {178, 126}, "评书悟潜能 · 清茶点心",         0,  10, 0},
    {"grocer",            "福兴掌柜",     "福兴杂货铺",     {136, 125}, "雨具衣袍行囊 · 杂货百物",       0,  10, 0},
    {"banker",            "钱庄掌柜",     "通济钱庄",       {139, 114}, "存银取银 · 银钱汇兑",           0,  10, 0},
    {"waiter",            "客栈店小二",   "悦来客栈",       {114, 108}, "租二楼上房歇息 · 茶点",         0,  10, 0},
    {"sparring_disciple", "武馆陪练弟子", "扬威武馆演武场", {100, 129}, "入门切磋喂招（点到为止）",      0,  10, 0},
}};

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
inline Tiles &level_tiles(Block &block, int z) {
    if (z == 0) return block.ground;
    if (z == 1) return block.upper;
    if (z == 2) return block.attic;
    auto [it, inserted] = block.extra_levels.try_emplace(z);
    if (inserted) it->second.tiles.fill(' ');
    return it->second.tiles;
}
inline const Tiles &level_tiles(const Block &block, int z) {
    if (z == 0) return block.ground;
    if (z == 1) return block.upper;
    if (z == 2) return block.attic;
    static const Tiles empty = [] { Tiles value{}; value.fill(' '); return value; }();
    const auto it = block.extra_levels.find(z);
    return it == block.extra_levels.end() ? empty : it->second.tiles;
}
inline Tiles &level_surfaces(Block &block, int z) {
    if (z == 0) return block.ground_surface;
    if (z == 1) return block.upper_surface;
    if (z == 2) return block.attic_surface;
    return block.extra_levels[z].surface;
}
inline const Tiles &level_surfaces(const Block &block, int z) {
    if (z == 0) return block.ground_surface;
    if (z == 1) return block.upper_surface;
    if (z == 2) return block.attic_surface;
    static const Tiles empty{};
    const auto it = block.extra_levels.find(z);
    return it == block.extra_levels.end() ? empty : it->second.surface;
}

enum class District { farmland, residential, commerce, central, warehouses, port, river, east_bank };
struct CityPlan {
    std::array<std::uint8_t, sector_count * sector_count> roads{};
    std::array<bool, sector_count> bridges{};
    std::array<int, city_size> shores{};
    Vector2i civic_center{2, 1};
    Vector2i trade_center{2, 2};
    Vector2i orchard_center{0, 0};
    std::array<Vector2i, 3> civic_sites{{{1, 1}, {2, 1}, {1, 2}}};
    std::uint32_t seed = 0;
    void generate(std::uint32_t value);
    District district_at(Vector2i s) const;
    bool connected(Vector2i s, int direction) const;
    int road_mask(Vector2i s) const;
    std::vector<Vector2i> road_path(Vector2i from, int direction) const;
    char overview(Vector2i s) const;
};

// Handcrafted Yangzhou world blueprint (built deterministically once, zero RNG!)
struct YangzhouWorldData {
    std::array<std::vector<char>, 3> tiles;
    std::array<std::vector<char>, 3> surfaces;
    std::array<std::vector<std::uint8_t>, 3> enclosed;
    struct Zone { Rect2i bounds; const char *name; };
    std::vector<Zone> zones;
};
const YangzhouWorldData &yangzhou_world_data();
bool is_npc_tile(Vector2i p);
const NpcDef *npc_at_tile(Vector2i p);

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
    // CCB passable rules: floors, stairs, doors, open/broken windows (climbable), beds, chairs & benches (steppable).
    return std::string_view("Diov^Xs:.+=ObqS%").find(tile) != std::string_view::npos;
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
