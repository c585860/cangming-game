#pragma once

#include "monsters.hpp"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <array>
#include <cstdint>
#include <list>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace cangling {

inline constexpr int kOmtSize = 24;
inline constexpr int kOvermapSize = 180; // Vanilla CCB OMAPX = OMAPY = 180 OMTs per Overmap

enum class OmtKind : std::uint8_t {
    Field = 0,
    Forest,
    ForestCamp,
    River,
    Road,
    Bridge,
    Shelter,
    House,
    Grocery,
    Pharmacy,
    Hardware,
    GunStore,
    PoliceStation,
    FireStation,
    Library,
    GasStation,
    Warehouse,
    ToxicDump,
};

struct OmtCell {
    OmtKind kind = OmtKind::Field;
    std::uint8_t rot = 0;       // 0, 1, 2, 3 (90-degree clockwise steps)
    std::uint8_t variant = 0;
    std::uint8_t road_mask = 0; // bit0=N, bit1=E, bit2=S, bit3=W
};

struct OmtItemSpawn {
    int lx = 0;
    int ly = 0;
    std::vector<std::string> items;
};

struct OmtTemplate {
    std::string id;
    OmtKind kind = OmtKind::Field;
    std::vector<std::string> ter_legend;
    std::vector<std::string> furn_legend;
    std::array<std::uint16_t, kOmtSize * kOmtSize> ter_idx{};
    std::array<std::uint16_t, kOmtSize * kOmtSize> furn_idx{};
    godot::Vector2i start_local{12, 12};
    std::vector<OmtItemSpawn> spawns;
};

struct OmtChunk {
    godot::Vector2i omt_coord{0, 0};
    OmtKind kind = OmtKind::Field;
    std::array<std::string, kOmtSize * kOmtSize> terrain;
    std::array<std::string, kOmtSize * kOmtSize> furniture;
    std::array<char, kOmtSize * kOmtSize> compat_tile;
    std::array<std::uint8_t, kOmtSize * kOmtSize> enclosed{};
    std::vector<OmtItemSpawn> item_spawns;
    std::vector<MonsterSpawn> monster_spawns;
    godot::Vector2i start_local{12, 12};
    float base_rad = 0.0f;
};

struct OvermapRegion {
    godot::Vector2i om_coord{0, 0};
    std::array<OmtCell, kOvermapSize * kOvermapSize> cells;
};

class CcbOvermapManager {
    std::uint32_t seed_ = 1337u;
    int city_size_opt_ = 8;
    int city_spacing_opt_ = 4;
    float monster_rate_ = 1.0f;

    mutable std::mutex mutex_;
    std::unordered_map<int64_t, std::shared_ptr<const OvermapRegion>> om_cache_;
    std::list<int64_t> chunk_lru_;
    struct CachedChunk {
        std::shared_ptr<const OmtChunk> chunk;
        std::list<int64_t>::iterator it;
    };
    std::unordered_map<int64_t, CachedChunk> chunk_cache_;

    static void ensure_templates_loaded();
    static int64_t pair_key(int x, int y);
    static int floor_div(int a, int b);
    static int floor_mod(int a, int b);

    std::shared_ptr<const OvermapRegion> get_overmap_locked(int om_x, int om_y);
    std::shared_ptr<OmtChunk> build_chunk(godot::Vector2i omt_coord, const OmtCell &cell) const;

public:
    void reset(std::uint32_t seed, int city_size_opt = 8, int city_spacing_opt = 4, float monster_rate = 1.0f);
    std::uint32_t seed() const { return seed_; }

    static godot::Vector2i world_to_omt(godot::Vector2i wp);
    static godot::Vector2i world_to_local(godot::Vector2i wp);
    static OmtKind parse_omt_kind(const std::string &name);
    static const char *omt_kind_name_cn(OmtKind k);
    static char omt_kind_glyph(OmtKind k, std::uint8_t road_mask);
    static const char *omt_kind_color_hex(OmtKind k);

    OmtCell cell_at_omt(godot::Vector2i omt_coord);
    std::shared_ptr<const OmtChunk> chunk_at_omt(godot::Vector2i omt_coord);
    std::shared_ptr<const OmtChunk> chunk_at_world(godot::Vector2i wp);

    std::string terrain_at(godot::Vector2i wp);
    std::string furniture_at(godot::Vector2i wp);
    char compat_tile_at(godot::Vector2i wp);
    bool enclosed_at(godot::Vector2i wp);
    float radiation_at(godot::Vector2i wp);
    godot::String location_name(godot::Vector2i wp);

    bool is_terrain_walkable(const std::string &ter, const std::string &furn) const;
    bool is_terrain_opaque(const std::string &ter, const std::string &furn) const;

    godot::Vector2i find_scenario_start(const std::string &start_omt_name);
    godot::Dictionary overmap_slice(godot::Vector2i center_omt, int radius);

    std::size_t cached_chunk_count() const;
    std::size_t memory_bytes() const;
    std::size_t trim_cache(std::size_t keep_recent);
};

} // namespace cangling
