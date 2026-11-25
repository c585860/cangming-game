#include "render_bake.hpp"
#include "thread_pool.hpp"

#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstring>
#include <limits>
#include <queue>
#include <vector>

namespace cangling {
namespace {

constexpr int kReach = 28;
constexpr int kSkyDistance = 12;
constexpr int kPointReach = 9;
constexpr int kPointSlots = 4;

inline std::uint8_t to_u8(float v) {
    const float clamped = std::clamp(v, 0.0f, 1.0f);
    return static_cast<std::uint8_t>(std::lround(clamped * 255.0f));
}

inline float smoothstep_f(float e0, float e1, float x) {
    const float t = std::clamp((x - e0) / std::max(e1 - e0, 1e-6f), 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}

inline int64_t door_key(int x, int y, int z) {
    return (static_cast<int64_t>(z) * city_size + y) * city_size + x;
}

inline float tile_height(char t) {
    switch (t) {
        case 'Y': return 2.49f;
        case 'g': return 0.48f;
        case 'f': return 0.95f;
        case 'b': return 0.40f;
        case 'c': return 0.65f;
        case 'C': return 0.65f;
        case 't': return 0.60f;
        case 'k': return 0.78f;
        case 'K': return 0.96f;
        case 'q': return 0.48f;
        case 'S': return 0.55f;
        case 'F': return 1.63f;
        case 'P': return 0.84f;
        case 'r': return 1.50f;
        case 'l': return 0.67f;
        case 'h': return 0.73f;
        case 'a': return 0.94f;
        case 'u': return 0.74f;
        case 'L': return 2.24f;
        default: return 0.0f;
    }
}

inline bool is_wall_tile(char t) {
    return t == '#' || t == 'D' || t == 'o' || t == 'w' || t == 'O' || t == '%';
}

inline float portal_weight(char t) {
    if (t == 'w') return 0.48f;
    if (t == 'O') return 0.61f;
    if (t == '%') return 0.68f;
    if (t == 'o') return 0.73f;
    return 0.0f;
}

inline float tile_transmission(char t) {
    if (t == '#' || t == 'D' || t == ' ') return 0.0f;
    if (t == 'w') return 0.72f;
    if (t == 'Y') return 0.48f;
    if (t == 'g' || t == 'f') return 0.80f;
    return 1.0f;
}

struct RGB {
    float r, g, b;
};

inline RGB surface_reflectance(char s, bool &matched) {
    matched = true;
    switch (s) {
        case 'm': return {0.60f, 0.62f, 0.65f};
        case 'p':
        case 'G': return {0.76f, 0.71f, 0.60f};
        case 'j':
        case 'J': return {0.74f, 0.71f, 0.66f};
        case 'R': return {0.84f, 0.25f, 0.24f};
        case 'd': return {0.64f, 0.50f, 0.35f};
        case 'H': return {0.84f, 0.78f, 0.65f};
        case 'N': return {0.76f, 0.54f, 0.36f};
        case 'B': return {0.64f, 0.67f, 0.71f};
        default:
            matched = false;
            return {0.76f, 0.54f, 0.36f};
    }
}

inline RGB furniture_reflectance(char t) {
    switch (t) {
        case 'b': return {0.78f, 0.73f, 0.64f};
        case 'k': return {0.76f, 0.62f, 0.48f};
        case 'K': return {0.72f, 0.58f, 0.44f};
        case 'u': return {0.68f, 0.62f, 0.52f};
        case 'a': return {0.62f, 0.52f, 0.42f};
        case 'h': return {0.55f, 0.42f, 0.34f};
        case 'P': return {0.32f, 0.64f, 0.30f};
        default: return {0.76f, 0.54f, 0.36f};
    }
}

inline char sample_tile(const SectorGridSnapshot &snap, const std::unordered_set<int64_t> &doors,
        const std::unordered_map<int64_t, char> &overrides,
        int wx, int wy, int level) {
    if (wx < 0 || wy < 0 || wx >= city_size || wy >= city_size) return ' ';
    const int64_t dk = door_key(wx, wy, level);
    char t = ' ';
    if (!overrides.empty()) {
        if (const auto it = overrides.find(dk); it != overrides.end()) {
            t = it->second;
            if ((t == 'D' || t == 'w') && !doors.empty() && doors.count(dk)) {
                t = (t == 'D') ? 'o' : 'O';
            }
            return t;
        }
    }
    const int sx = wx / sector_size;
    const int sy = wy / sector_size;
    const Block *blk = snap.at(sx, sy);
    if (!blk) return ' ';
    const int lx = wx - sx * sector_size;
    const int ly = wy - sy * sector_size;
    t = level_tiles(*blk, level)[ly * sector_size + lx];
    if ((t == 'D' || t == 'w') && !doors.empty() && doors.count(dk)) {
        t = (t == 'D') ? 'o' : 'O';
    }
    return t;
}

inline char sample_surface(const SectorGridSnapshot &snap, int wx, int wy, int level) {
    if (wx < 0 || wy < 0 || wx >= city_size || wy >= city_size) return '\0';
    const int sx = wx / sector_size;
    const int sy = wy / sector_size;
    const Block *blk = snap.at(sx, sy);
    if (!blk) return '\0';
    const int lx = wx - sx * sector_size;
    const int ly = wy - sy * sector_size;
    return level_surfaces(*blk, level)[ly * sector_size + lx];
}

inline std::uint8_t sample_column_flags(const SectorGridSnapshot &snap, int wx, int wy, int z, int layers) {
    if (wx < 0 || wy < 0 || wx >= city_size || wy >= city_size) return 0;
    const int sx = wx / sector_size;
    const int sy = wy / sector_size;
    const Block *blk = snap.at(sx, sy);
    if (!blk) return 0;
    const int lx = wx - sx * sector_size;
    const int ly = wy - sy * sector_size;
    const int idx = ly * sector_size + lx;
    int result = 0;
    for (int layer = 0; layer < layers && layer < 4 && z <= std::numeric_limits<int>::max() - layer; ++layer) {
        const int level = z + layer;
        const bool enclosed = enclosed_at(*blk, level, idx);
        bool ceiling = enclosed;
        if (level < std::numeric_limits<int>::max() && enclosed_at(*blk, level + 1, idx)) {
            const char upper = level_tiles(*blk, level + 1)[idx];
            ceiling = upper != 'X' && upper != 'v';
        }
        const int f = int(enclosed) | (int(ceiling) << 1);
        result |= f << (layer * 2);
    }
    return static_cast<std::uint8_t>(result);
}

inline std::uint32_t point_hash(int x, int y, std::uint32_t seed) {
    std::uint32_t n = (static_cast<std::uint32_t>(x) * 0x9e3779b9u) ^
                      (static_cast<std::uint32_t>(y) * 0x85ebca6bu) ^ seed;
    n = (n ^ (n >> 16)) * 0x7feb352du;
    return n ^ (n >> 15);
}

inline int posmod_i(int a, int m) {
    const int r = a % m;
    return r < 0 ? r + m : r;
}

struct LampSpec {
    float z_height;
    float energy;
    float r, g, b;
    float flicker_kind;
    float always_fraction;
};

constexpr LampSpec kLampStreet{2.05f, 26.0f, 1.0f, 0.74f, 0.40f, 1.0f, 0.0f};
constexpr LampSpec kLampHearth{0.82f, 16.5f, 1.0f, 0.48f, 0.18f, 1.0f, 0.55f};
constexpr LampSpec kLampIndoor{1.28f, 12.5f, 1.0f, 0.77f, 0.46f, 1.0f, 0.22f};
constexpr LampSpec kLampMarket{2.05f, 24.0f, 1.0f, 0.76f, 0.42f, 1.0f, 0.0f};
constexpr LampSpec kLampBridge{1.95f, 19.0f, 1.0f, 0.73f, 0.39f, 1.0f, 0.0f};
constexpr LampSpec kLampAltar{1.15f, 19.5f, 0.36f, 0.96f, 0.78f, 2.0f, 0.65f};
constexpr LampSpec kLampHerb{0.35f, 6.0f, 0.45f, 0.94f, 0.74f, 2.0f, 0.28f};

} // namespace

godot::Dictionary RenderBaker::bake_region(City &city, const std::unordered_set<int64_t> &doors,
        const std::unordered_map<int64_t, char> &overrides,
        Rect2i area, int z, int layers, const String &season, double &out_bake_ms) {
    const auto t0 = std::chrono::steady_clock::now();
    godot::Dictionary result;
    const int w = area.size.x;
    const int h = area.size.y;
    const int clamped_layers = std::clamp(layers, 1, 3);
    if (w <= 0 || h <= 0) {
        out_bake_ms = 0.0;
        return result;
    }

    const SectorGridSnapshot snap = city.snapshot_sectors(area);
    const int total = w * h;

    godot::PackedByteArray tiles_buf;
    godot::PackedByteArray surfaces_buf;
    godot::PackedByteArray flags_buf;
    godot::PackedByteArray below_tiles_buf;
    godot::PackedByteArray below_surfaces_buf;
    tiles_buf.resize(total);
    surfaces_buf.resize(total);
    flags_buf.resize(total);
    const bool need_below = z > 0;
    if (need_below) {
        below_tiles_buf.resize(total);
        below_surfaces_buf.resize(total);
    }

    // Store upper layers compactly so aperture_normal and geometry encoding never touch City again.
    std::vector<char> layer_tiles_all(static_cast<std::size_t>(total * clamped_layers), ' ');

    auto *tiles_ptr = tiles_buf.ptrw();
    auto *surf_ptr = surfaces_buf.ptrw();
    auto *flags_ptr = flags_buf.ptrw();
    auto *below_t_ptr = need_below ? below_tiles_buf.ptrw() : nullptr;
    auto *below_s_ptr = need_below ? below_surfaces_buf.ptrw() : nullptr;

    // Pass 1 (parallel): extract tiles, surfaces, lighting column flags, and upper layers.
    ThreadPool::instance().parallel_for(0, h, 4, [&](int y0, int y1) {
        for (int y = y0; y < y1; ++y) {
            const int wy = area.position.y + y;
            for (int x = 0; x < w; ++x) {
                const int wx = area.position.x + x;
                const int idx = y * w + x;
                const char t = sample_tile(snap, doors, overrides, wx, wy, z);
                const char s = sample_surface(snap, wx, wy, z);
                const std::uint8_t f = sample_column_flags(snap, wx, wy, z, clamped_layers);
                tiles_ptr[idx] = static_cast<std::uint8_t>(t);
                surf_ptr[idx] = static_cast<std::uint8_t>(s);
                flags_ptr[idx] = f;
                layer_tiles_all[static_cast<std::size_t>(idx)] = t;
                for (int layer = 1; layer < clamped_layers; ++layer) {
                    layer_tiles_all[static_cast<std::size_t>(layer * total + idx)] =
                        sample_tile(snap, doors, overrides, wx, wy, z + layer);
                }
                if (need_below) {
                    if (t == ' ') {
                        below_t_ptr[idx] = static_cast<std::uint8_t>(sample_tile(snap, doors, overrides, wx, wy, 0));
                        below_s_ptr[idx] = static_cast<std::uint8_t>(sample_surface(snap, wx, wy, 0));
                    } else {
                        below_t_ptr[idx] = static_cast<std::uint8_t>(' ');
                        below_s_ptr[idx] = 0;
                    }
                }
            }
        }
    });

    auto tile_at = [&](int x, int y, int layer) -> char {
        if (x < 0 || y < 0 || x >= w || y >= h || layer < 0 || layer >= clamped_layers) return ' ';
        return layer_tiles_all[static_cast<std::size_t>(layer * total + y * w + x)];
    };
    auto enclosed_at_xy = [&](int x, int y) -> bool {
        if (x < 0 || y < 0 || x >= w || y >= h) return false;
        return (flags_ptr[y * w + x] & 1u) != 0u;
    };
    auto sky_open_at_xy = [&](int x, int y) -> bool {
        if (x < 0 || y < 0 || x >= w || y >= h) return false;
        return (flags_ptr[y * w + x] & 0xAAu) == 0u;
    };
    auto wall_at_xy = [&](int x, int y, int layer) -> bool {
        if (x < 0 || y < 0 || x >= w || y >= h) return false;
        return is_wall_tile(tile_at(x, y, layer));
    };
    auto aperture_normal_xy = [&](int x, int y, int layer) -> Vector2i {
        if (layer == 0) {
            static const std::array<Vector2i, 2> axes{{{1, 0}, {0, 1}}};
            for (const Vector2i axis : axes) {
                const int ax = x + axis.x, ay = y + axis.y;
                const int bx = x - axis.x, by = y - axis.y;
                if (ax >= 0 && ay >= 0 && ax < w && ay < h &&
                    bx >= 0 && by >= 0 && bx < w && by < h &&
                    enclosed_at_xy(ax, ay) != enclosed_at_xy(bx, by) &&
                    !wall_at_xy(ax, ay, 0) && !wall_at_xy(bx, by, 0)) {
                    return axis;
                }
            }
        }
        const int along_x = int(wall_at_xy(x - 1, y, layer)) + int(wall_at_xy(x + 1, y, layer));
        const int along_y = int(wall_at_xy(x, y - 1, layer)) + int(wall_at_xy(x, y + 1, layer));
        return along_y > along_x ? Vector2i{1, 0} : Vector2i{0, 1};
    };

    // Pass 2 (parallel): encode geometry RGBA8 (w * layers x h) and bounce materials RGB8 (w x h).
    godot::PackedByteArray geom_buf;
    geom_buf.resize(w * clamped_layers * h * 4);
    auto *geom_ptr = geom_buf.ptrw();

    godot::PackedByteArray mat_buf;
    mat_buf.resize(total * 3);
    auto *mat_ptr = mat_buf.ptrw();

    RGB grass_col{0.28f, 0.62f, 0.25f};
    if (season == String("summer")) grass_col = {0.24f, 0.58f, 0.22f};
    else if (season == String("autumn")) grass_col = {0.68f, 0.50f, 0.24f};
    else if (season == String("winter")) grass_col = {0.66f, 0.72f, 0.78f};

    constexpr RGB kWood{0.76f, 0.54f, 0.36f};
    constexpr RGB kPlaster{0.84f, 0.78f, 0.65f};
    constexpr RGB kStone{0.64f, 0.67f, 0.71f};

    const int geom_stride = w * clamped_layers;
    ThreadPool::instance().parallel_for(0, h, 4, [&](int y0, int y1) {
        for (int y = y0; y < y1; ++y) {
            for (int x = 0; x < w; ++x) {
                const int idx = y * w + x;
                const char t0 = static_cast<char>(tiles_ptr[idx]);
                const char surf = static_cast<char>(surf_ptr[idx]);
                const std::uint8_t col_flags = flags_ptr[idx];

                // Geometry layers
                for (int layer = 0; layer < clamped_layers; ++layer) {
                    const char t = layer_tiles_all[static_cast<std::size_t>(layer * total + idx)];
                    float height = tile_height(t);
                    std::uint8_t kind = 0;
                    float axis = 0.0f;
                    if (t == '#' || t == 'D') {
                        height = (layer == 0 && surf == 'G') ? 0.95f : 2.5f;
                        kind = 1;
                    } else if ((t == 'w' || t == 'O' || t == '%' || t == 'o') && !(layer == 0 && surf == 'G')) {
                        height = 2.5f;
                        kind = (t == 'w') ? 2 : ((t == 'O' || t == '%') ? 3 : 4);
                        axis = static_cast<float>(aperture_normal_xy(x, y, layer).x);
                    } else if (height > 0.0f) {
                        if (t == 'L') kind = 8;
                        else if (t == 'Y') kind = 5;
                        else if (t == 'g' || t == 'f' || t == 'P') kind = 6;
                        else kind = 7;
                    } else if (layer == 0) {
                        if (surf == 'm' || surf == 'p' || surf == 'G' || surf == 'j' || surf == 'J' || t == '+') {
                            axis = 1.0f;
                        } else if (t == ':' || surf == 'd') {
                            axis = 0.5f;
                        }
                    }
                    const std::uint8_t lf = (col_flags >> (layer * 2)) & 3u;
                    const int g_off = (y * geom_stride + (x + layer * w)) * 4;
                    geom_ptr[g_off + 0] = to_u8(height / 3.0f);
                    geom_ptr[g_off + 1] = kind;
                    geom_ptr[g_off + 2] = to_u8(axis);
                    geom_ptr[g_off + 3] = to_u8(static_cast<float>(lf) / 3.0f);
                }

                // Bounce materials
                const int m_off = idx * 3;
                if (t0 == ' ') {
                    mat_ptr[m_off + 0] = 0;
                    mat_ptr[m_off + 1] = 0;
                    mat_ptr[m_off + 2] = 0;
                } else {
                    RGB col = kWood;
                    if (t0 == '#' || t0 == 'D' || t0 == 'w' || t0 == 'O' || t0 == '%') {
                        col = (surf == 'B') ? kStone : (surf == 'N' ? kWood : kPlaster);
                    } else if (t0 == 'W' || t0 == '~') {
                        col = (t0 == '~') ? RGB{0.22f, 0.72f, 0.78f} : RGB{0.18f, 0.56f, 0.72f};
                    } else if (t0 == '=') {
                        col = {0.76f, 0.58f, 0.38f};
                    } else if (t0 == 's' || t0 == ':') {
                        col = {0.84f, 0.72f, 0.48f};
                    } else if ((t0 == '.' || t0 == 'g' || t0 == 'Y' || t0 == 'f' || t0 == 'L') && surf == '\0') {
                        col = grass_col;
                    } else if (tile_height(t0) > 0.0f && t0 != 'Y' && t0 != 'g' && t0 != 'f' && t0 != 'L') {
                        col = furniture_reflectance(t0);
                    } else {
                        bool matched = false;
                        const RGB sref = surface_reflectance(surf, matched);
                        if (matched) col = sref;
                        else if (t0 == '+') col = {0.72f, 0.68f, 0.58f};
                    }
                    mat_ptr[m_off + 0] = to_u8(col.r);
                    mat_ptr[m_off + 1] = to_u8(col.g);
                    mat_ptr[m_off + 2] = to_u8(col.b);
                }
            }
        }
    });

    // Pass 3: River distance field (RGB8, w x h).
    godot::PackedByteArray river_buf;
    river_buf.resize(total * 3);
    auto *river_ptr = river_buf.ptrw();
    if (z != 0) {
        std::memset(river_ptr, 0, static_cast<std::size_t>(total * 3));
    } else {
        std::vector<int> distance(static_cast<std::size_t>(total), kReach * 2);
        std::vector<int> shore(static_cast<std::size_t>(total), kReach * 2);
        std::vector<std::uint8_t> water(static_cast<std::size_t>(total), 0);
        for (int i = 0; i < total; ++i) {
            const int y = i / w;
            const int x = i % w;
            const char t = static_cast<char>(tiles_ptr[i]);
            if (t == 'W' || t == '~') {
                water[i] = (t == 'W') ? 255 : 112;
                distance[i] = 0;
            } else {
                shore[i] = 0;
            }
            if (x > 0) {
                distance[i] = std::min(distance[i], distance[i - 1] + 1);
                shore[i] = std::min(shore[i], shore[i - 1] + 1);
            }
            if (y > 0) {
                distance[i] = std::min(distance[i], distance[i - w] + 1);
                shore[i] = std::min(shore[i], shore[i - w] + 1);
            }
        }
        for (int i = total - 1; i >= 0; --i) {
            const int y = i / w;
            const int x = i % w;
            if (x + 1 < w) {
                distance[i] = std::min(distance[i], distance[i + 1] + 1);
                shore[i] = std::min(shore[i], shore[i + 1] + 1);
            }
            if (y + 1 < h) {
                distance[i] = std::min(distance[i], distance[i + w] + 1);
                shore[i] = std::min(shore[i], shore[i + w] + 1);
            }
            const float signed_shore = 0.5f + 0.125f * static_cast<float>(std::clamp(shore[i] - distance[i], -4, 4));
            const int off = i * 3;
            river_ptr[off + 0] = to_u8(1.0f - smoothstep_f(0.0f, static_cast<float>(kReach - 3), static_cast<float>(distance[i])));
            river_ptr[off + 1] = water[i];
            river_ptr[off + 2] = to_u8(signed_shore);
        }
    }

    // Pass 4: Sky transport (RG8, w x h).
    godot::PackedByteArray sky_buf;
    sky_buf.resize(total * 2);
    auto *sky_ptr = sky_buf.ptrw();
    std::memset(sky_ptr, 0, static_cast<std::size_t>(total * 2));
    if (z >= 0) {
        // Portal normal encoding: 0 = none, 1 = (1,0), 2 = (0,1)
        std::vector<std::uint8_t> portal_norm(static_cast<std::size_t>(total), 0);
        std::vector<int> portal_indices;
        for (int y = 0; y < h; ++y) {
            for (int x = 0; x < w; ++x) {
                const int idx = y * w + x;
                const char t = static_cast<char>(tiles_ptr[idx]);
                if (enclosed_at_xy(x, y) && portal_weight(t) > 0.0f) {
                    const Vector2i n = aperture_normal_xy(x, y, 0);
                    portal_norm[idx] = (n.x != 0) ? 1 : 2;
                    portal_indices.push_back(idx);
                }
            }
        }

        auto connects_xy = [&](int x, int y) -> bool {
            if (x < 0 || y < 0 || x >= w || y >= h) return false;
            const int idx = y * w + x;
            if ((flags_ptr[idx] & 1u) == 0u) return false;
            const char t = static_cast<char>(tiles_ptr[idx]);
            return t != ' ' && t != '#' && t != 'D' && t != 'w';
        };
        auto can_step_xy = [&](int fx, int fy, int tx, int ty) -> bool {
            if (!connects_xy(tx, ty)) return false;
            const int ax = std::abs(tx - fx);
            const int ay = std::abs(ty - fy);
            const std::uint8_t hn = portal_norm[fy * w + fx];
            const std::uint8_t tn = portal_norm[ty * w + tx];
            const bool h_ok = (hn == 0) || (hn == 1 && ax == 1 && ay == 0) || (hn == 2 && ax == 0 && ay == 1);
            const bool t_ok = (tn == 0) || (tn == 1 && ax == 1 && ay == 0) || (tn == 2 && ax == 0 && ay == 1);
            return h_ok && t_ok;
        };
        auto sky_at_opening = [&](int px, int py, int ox, int oy) -> float {
            const int tx = -oy;
            const int ty = ox;
            float sky = 0.0f;
            for (int lateral : {-1, 0, 1}) {
                float value = 0.0f;
                for (int dist = 1; dist < 5; ++dist) {
                    const int ax = px + ox * dist + tx * lateral * (dist - 1);
                    const int ay = py + oy * dist + ty * lateral * (dist - 1);
                    if (ax < 0 || ay < 0 || ax >= w || ay >= h) break;
                    const char t = static_cast<char>(tiles_ptr[ay * w + ax]);
                    if (enclosed_at_xy(ax, ay) || t == '#' || t == 'D' || t == 'w') break;
                    if (sky_open_at_xy(ax, ay)) {
                        value += 0.25f / (1.0f + static_cast<float>(dist - 1) * 0.16f);
                    }
                }
                sky += value * (lateral == 0 ? 0.50f : 0.25f);
            }
            return sky;
        };

        std::vector<float> levels(static_cast<std::size_t>(total), 0.0f);
        std::vector<int> visit_dist(static_cast<std::size_t>(total), -1);
        std::vector<int> visit_stamp(static_cast<std::size_t>(total), 0);
        int cur_stamp = 0;
        std::vector<int> bfs_q;
        bfs_q.reserve(256);

        auto write_level = [&](int idx, float intensity) {
            const float old = levels[idx];
            levels[idx] = old + (1.0f - old) * intensity;
        };

        static const std::array<Vector2i, 4> kCardinals{{{0, -1}, {-1, 0}, {1, 0}, {0, 1}}};

        for (int pidx : portal_indices) {
            const int px = pidx % w;
            const int py = pidx / w;
            const Vector2i normal = (portal_norm[pidx] == 1) ? Vector2i{1, 0} : Vector2i{0, 1};
            const std::array<Vector2i, 2> dirs{normal, -normal};
            const float pw = portal_weight(static_cast<char>(tiles_ptr[pidx]));
            for (const Vector2i outward : dirs) {
                const int ex = px - outward.x;
                const int ey = py - outward.y;
                if (!connects_xy(ex, ey)) continue;
                const float visible_sky = sky_at_opening(px, py, outward.x, outward.y);
                if (visible_sky <= 0.01f) continue;
                const float strength = pw * visible_sky;
                write_level(pidx, strength);

                ++cur_stamp;
                bfs_q.clear();
                const int eidx = ey * w + ex;
                visit_stamp[eidx] = cur_stamp;
                visit_dist[eidx] = 0;
                visit_stamp[pidx] = cur_stamp;
                visit_dist[pidx] = 0;
                bfs_q.push_back(eidx);

                const float in_x = static_cast<float>(ex - px);
                const float in_y = static_cast<float>(ey - py);
                std::size_t head = 0;
                while (head < bfs_q.size()) {
                    const int cur = bfs_q[head++];
                    const int cx = cur % w;
                    const int cy = cur / w;
                    const int step_cnt = visit_dist[cur];
                    const int ox = cx - ex;
                    const int oy = cy - ey;
                    const float dx = static_cast<float>(ox) + in_x * 0.5f;
                    const float dy = static_cast<float>(oy) + in_y * 0.5f;
                    const float radius = std::sqrt(dx * dx + dy * dy);
                    const float facing = radius > 1e-5f ? std::clamp((dx * in_x + dy * in_y) / radius, 0.0f, 1.0f) : 0.0f;
                    const float detour = static_cast<float>(step_cnt - std::abs(ox) - std::abs(oy));
                    const float dist = radius + std::max(detour, 0.0f) * 0.60f;
                    const float spread = (0.30f + 0.70f * facing) / (1.0f + 0.11f * dist * dist);
                    const float edge = 1.0f - smoothstep_f(static_cast<float>(kSkyDistance - 4),
                        static_cast<float>(kSkyDistance), static_cast<float>(step_cnt));
                    write_level(cur, strength * spread * edge);

                    if (step_cnt + 1 >= kSkyDistance) continue;
                    for (const Vector2i s : kCardinals) {
                        const int nx = cx + s.x;
                        const int ny = cy + s.y;
                        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                        const int nidx = ny * w + nx;
                        if (visit_stamp[nidx] == cur_stamp) continue;
                        if (!can_step_xy(cx, cy, nx, ny)) continue;
                        visit_stamp[nidx] = cur_stamp;
                        visit_dist[nidx] = step_cnt + 1;
                        bfs_q.push_back(nidx);
                    }
                }
            }
        }

        // Incident surfaces + parallel reflection bake
        std::vector<float> incident(static_cast<std::size_t>(total), 0.0f);
        ThreadPool::instance().parallel_for(0, h, 4, [&](int y0, int y1) {
            for (int y = y0; y < y1; ++y) {
                for (int x = 0; x < w; ++x) {
                    const int idx = y * w + x;
                    const float lv = levels[idx];
                    if (lv <= 0.0f || !connects_xy(x, y)) continue;
                    int walls = 0;
                    for (const Vector2i s : kCardinals) {
                        const int nx = x + s.x, ny = y + s.y;
                        if (nx >= 0 && ny >= 0 && nx < w && ny < h) {
                            const char nt = static_cast<char>(tiles_ptr[ny * w + nx]);
                            if (nt == '#' || nt == 'D') ++walls;
                        }
                    }
                    incident[idx] = lv * (1.0f + 0.16f * static_cast<float>(std::min(walls, 2)));
                }
            }
        });

        ThreadPool::instance().parallel_for(0, h, 4, [&](int y0, int y1) {
            for (int y = y0; y < y1; ++y) {
                for (int x = 0; x < w; ++x) {
                    const int idx = y * w + x;
                    const float lv = levels[idx];
                    if (lv <= 0.0f) continue;
                    float refl = 0.0f;
                    if (connects_xy(x, y)) {
                        float total_r = incident[idx] * 0.26f;
                        for (int dy = -1; dy <= 1; ++dy) {
                            for (int dx = -1; dx <= 1; ++dx) {
                                if (dx == 0 && dy == 0) continue;
                                int fx = x, fy = y;
                                const int dir_len_sq = dx * dx + dy * dy;
                                for (int dist = 1; dist < 4; ++dist) {
                                    const int tx = fx + dx;
                                    const int ty = fy + dy;
                                    if (dx != 0 && dy != 0) {
                                        if (!(can_step_xy(fx, fy, fx + dx, fy) && can_step_xy(fx, fy, fx, fy + dy) &&
                                              can_step_xy(fx + dx, fy, tx, ty) && can_step_xy(fx, fy + dy, tx, ty))) {
                                            break;
                                        }
                                    } else if (!can_step_xy(fx, fy, tx, ty)) {
                                        break;
                                    }
                                    const float falloff = 1.0f + static_cast<float>(dir_len_sq * dist * dist);
                                    total_r += incident[ty * w + tx] / falloff;
                                    fx = tx;
                                    fy = ty;
                                }
                            }
                        }
                        refl = 1.0f - std::exp(-total_r * 0.50f);
                    }
                    sky_ptr[idx * 2 + 0] = to_u8(lv);
                    sky_ptr[idx * 2 + 1] = to_u8(refl);
                }
            }
        });
    }

    const auto t1 = std::chrono::steady_clock::now();
    out_bake_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    result["tiles"] = tiles_buf;
    result["surfaces"] = surfaces_buf;
    result["flags"] = flags_buf;
    if (need_below) {
        result["below_tiles"] = below_tiles_buf;
        result["below_surfaces"] = below_surfaces_buf;
    }
    result["geometry"] = geom_buf;
    result["materials"] = mat_buf;
    result["river_field"] = river_buf;
    result["sky_transport"] = sky_buf;
    result["bake_ms"] = out_bake_ms;
    return result;
}

godot::PackedByteArray RenderBaker::bake_ambient(City &city, const std::unordered_set<int64_t> &doors,
        const std::unordered_map<int64_t, char> &overrides,
        Rect2i area, Rect2i region, int z, float outdoor_light, float sun_warmth) {
    godot::PackedByteArray out;
    const int w = area.size.x;
    const int h = area.size.y;
    if (w <= 0 || h <= 0) return out;
    out.resize(w * h * 4);
    auto *ptr = out.ptrw();
    std::memset(ptr, 0, static_cast<std::size_t>(w * h * 4));

    const Rect2i clipped = region.intersection(area);
    if (clipped.size.x <= 0 || clipped.size.y <= 0) return out;

    const SectorGridSnapshot snap = city.snapshot_sectors(area);
    constexpr float kAmbientLow = 3.5f;
    constexpr float kAmbientDim = 5.0f;
    const float inside_blend = smoothstep_f(4.5f, 26.0f, outdoor_light);
    const float inside = (z >= 0) ? (kAmbientLow + (kAmbientDim * 0.8f - kAmbientLow) * inside_blend) : kAmbientLow;
    const float warm = sun_warmth * 0.75f;
    const RGB day_tint{
        1.0f + (1.0f - 1.0f) * warm,
        1.0f + (0.78f - 1.0f) * warm,
        1.0f + (0.57f - 1.0f) * warm
    };

    const int rx0 = clipped.position.x - area.position.x;
    const int ry0 = clipped.position.y - area.position.y;
    const int rx1 = rx0 + clipped.size.x;
    const int ry1 = ry0 + clipped.size.y;

    ThreadPool::instance().parallel_for(ry0, ry1, 4, [&](int y0, int y1) {
        for (int y = y0; y < y1; ++y) {
            const int wy = area.position.y + y;
            for (int x = rx0; x < rx1; ++x) {
                const int wx = area.position.x + x;
                const char tile = sample_tile(snap, doors, overrides, wx, wy, z);
                if (tile == ' ') continue;
                const std::uint8_t flags = sample_column_flags(snap, wx, wy, z, 3);
                const bool enclosed = (flags & 1u) != 0u;
                const bool sky_open = (flags & 0xAAu) == 0u;

                float natural = inside;
                if (z >= 0 && !enclosed) {
                    natural = sky_open ? outdoor_light : (inside + (outdoor_light - inside) * 0.35f);
                } else if (z >= 0 && is_wall_tile(tile)) {
                    const int ey = wy + 1;
                    if (ey < area.position.y + h) {
                        const char ext_tile = sample_tile(snap, doors, overrides, wx, ey, z);
                        const std::uint8_t ext_flags = sample_column_flags(snap, wx, ey, z, 3);
                        const bool ext_enc = (ext_flags & 1u) != 0u;
                        const bool ext_sky = (ext_flags & 0xAAu) == 0u;
                        if (ext_sky && !ext_enc && !is_wall_tile(ext_tile)) {
                            const float fill = (tile == 'w' || tile == 'O' || tile == '%') ? 0.30f : 0.64f;
                            natural = inside + (outdoor_light - inside) * fill;
                        }
                    }
                }
                const float level = std::max(natural - kAmbientLow, 0.0f);
                const float daylight = 1.0f - std::exp(-level / 56.0f);
                const float twilight = 1.0f - std::exp(-level / 9.0f);
                const float hr = 0.74f + (day_tint.r - 0.74f) * twilight;
                const float hg = 0.81f + (day_tint.g - 0.81f) * twilight;
                const float hb = 1.00f + (day_tint.b - 1.00f) * twilight;
                const float bright = 0.23f + twilight * 0.17f + daylight * 0.42f;
                const int off = (y * w + x) * 4;
                ptr[off + 0] = to_u8(hr * bright);
                ptr[off + 1] = to_u8(hg * bright);
                ptr[off + 2] = to_u8(hb * bright);
                ptr[off + 3] = 255;
            }
        }
    });

    return out;
}

godot::Dictionary RenderBaker::bake_point_lights(City &city, const std::unordered_set<int64_t> &doors,
        const std::unordered_map<int64_t, char> &overrides,
        Rect2i area, Rect2i region, int z, const godot::Dictionary &sites, int seed) {
    godot::Dictionary result;
    const int w = area.size.x;
    const int h = area.size.y;
    if (w <= 0 || h <= 0) return result;

    const SectorGridSnapshot snap = city.snapshot_sectors(area);
    const int total = w * h;

    // Flat tile + enclosed cache over area for ultra-fast parallel ray transmission.
    std::vector<char> tiles(static_cast<std::size_t>(total), ' ');
    std::vector<std::uint8_t> enclosed(static_cast<std::size_t>(total), 0);
    ThreadPool::instance().parallel_for(0, h, 4, [&](int y0, int y1) {
        for (int y = y0; y < y1; ++y) {
            const int wy = area.position.y + y;
            for (int x = 0; x < w; ++x) {
                const int wx = area.position.x + x;
                const int idx = y * w + x;
                tiles[idx] = sample_tile(snap, doors, overrides, wx, wy, z);
                enclosed[idx] = sample_column_flags(snap, wx, wy, z, 1) & 1u;
            }
        }
    });

    auto tile_xy = [&](int lx, int ly) -> char {
        if (lx < 0 || ly < 0 || lx >= w || ly >= h) return ' ';
        return tiles[ly * w + lx];
    };
    auto is_bridge_post = [&](int lx, int ly, int wx) -> bool {
        if (tile_xy(lx, ly) != '=') return false;
        const char n = tile_xy(lx, ly - 1);
        const char s = tile_xy(lx, ly + 1);
        const bool edge = (n == '~' || n == 'W' || s == '~' || s == 'W');
        if (!edge) return false;
        const char west = tile_xy(lx - 1, ly);
        const char east = tile_xy(lx + 1, ly);
        const bool near_bank = (lx > 0 && west != '=') || (lx + 1 < w && east != '=');
        return near_bank || posmod_i(wx, 12) == 0;
    };

    struct Source {
        int wx, wy;
        int lx, ly;
        LampSpec spec;
    };
    std::vector<Source> sources;
    std::vector<Vector2i> placed_indoor;
    godot::Dictionary active_emitters;

    const Rect2i source_region = region.grow(kPointReach).intersection(area);
    const std::uint32_t u_seed = static_cast<std::uint32_t>(seed);
    const godot::StringName sn_altar("altar");
    const godot::StringName sn_merchant("merchant");
    const godot::StringName sn_ferryman("ferryman");
    const godot::StringName sn_herb("herb");
    const godot::StringName sn_lantern("lantern");
    const godot::StringName sn_street("street_lamp");
    const godot::StringName sn_hearth("hearth");
    const godot::StringName sn_bridge("bridge_lamp");
    const godot::StringName sn_candle("candle");

    for (int wy = source_region.position.y; wy < source_region.position.y + source_region.size.y; ++wy) {
        const int ly = wy - area.position.y;
        for (int wx = source_region.position.x; wx < source_region.position.x + source_region.size.x; ++wx) {
            const int lx = wx - area.position.x;
            const Vector2i wp(wx, wy);
            bool found = false;
            godot::StringName kind;
            LampSpec spec{};

            if (sites.has(wp)) {
                const godot::StringName site = sites[wp];
                if (site == sn_altar) { found = true; kind = sn_altar; spec = kLampAltar; }
                else if (site == sn_merchant || site == sn_ferryman) { found = true; kind = sn_lantern; spec = kLampMarket; }
                else if (site == sn_herb) { found = true; kind = sn_herb; spec = kLampHerb; }
            }
            if (!found) {
                const char t = tiles[ly * w + lx];
                if (t == 'L') { found = true; kind = sn_street; spec = kLampStreet; }
                else if (t == 'h') { found = true; kind = sn_hearth; spec = kLampHearth; }
                else if (t == '=' && is_bridge_post(lx, ly, wx)) { found = true; kind = sn_bridge; spec = kLampBridge; }
                else if (enclosed[ly * w + lx] && (t == 'l' || t == 'k' || t == 't' || t == 'K')) {
                    const std::uint32_t roll = point_hash(wx, wy, u_seed ^ 0x51a7c3u);
                    if (roll % 3u == 0u) {
                        bool too_close = false;
                        for (const Vector2i other : placed_indoor) {
                            const int dx = other.x - wx;
                            const int dy = other.y - wy;
                            if (dx * dx + dy * dy < 25) {
                                too_close = true;
                                break;
                            }
                        }
                        if (!too_close) {
                            placed_indoor.push_back(wp);
                            found = true;
                            kind = sn_candle;
                            spec = kLampIndoor;
                        }
                    }
                }
            }
            if (found) {
                active_emitters[wp] = kind;
                sources.push_back(Source{wx, wy, lx, ly, spec});
            }
        }
    }

    auto ray_transmission = [&](int sx, int sy, int ex, int ey) -> float {
        int px = sx, py = sy;
        const int dx = std::abs(ex - sx);
        const int dy = std::abs(ey - sy);
        const int step_x = (ex > sx) ? 1 : (ex < sx ? -1 : 0);
        const int step_y = (ey > sy) ? 1 : (ey < sy ? -1 : 0);
        int error = dx - dy;
        float transmission = 1.0f;
        while (px != ex || py != ey) {
            const int prev_x = px;
            const int prev_y = py;
            const int twice = 2 * error;
            if (twice > -dy) {
                error -= dy;
                px += step_x;
            }
            if (twice < dx) {
                error += dx;
                py += step_y;
            }
            if (px != prev_x && py != prev_y) {
                if (tile_transmission(tile_xy(px, prev_y)) == 0.0f &&
                    tile_transmission(tile_xy(prev_x, py)) == 0.0f) {
                    return 0.0f;
                }
            }
            if (px != ex || py != ey) {
                transmission *= tile_transmission(tile_xy(px, py));
                if (transmission <= 0.02f) return 0.0f;
            }
        }
        return transmission;
    };

    // Slots texture: (w * 2) x h RGBA32F
    godot::PackedByteArray slots_buf;
    slots_buf.resize(w * 2 * h * 4 * static_cast<int>(sizeof(float)));
    auto *slots_f = reinterpret_cast<float *>(slots_buf.ptrw());
    std::memset(slots_f, 0, static_cast<std::size_t>(slots_buf.size()));

    const Rect2i clipped = region.intersection(area);
    const int rx0 = clipped.position.x - area.position.x;
    const int ry0 = clipped.position.y - area.position.y;
    const int rx1 = rx0 + clipped.size.x;
    const int ry1 = ry0 + clipped.size.y;

    if (!sources.empty() && rx0 < rx1 && ry0 < ry1) {
        const int stride_f = w * 2 * 4;
        ThreadPool::instance().parallel_for(ry0, ry1, 4, [&](int y0, int y1) {
            for (int ly = y0; ly < y1; ++ly) {
                for (int lx = rx0; lx < rx1; ++lx) {
                    if (tiles[ly * w + lx] == ' ') continue;
                    std::array<float, kPointSlots> best_idx{0.0f, 0.0f, 0.0f, 0.0f};
                    std::array<float, kPointSlots> best_trans{0.0f, 0.0f, 0.0f, 0.0f};
                    std::array<float, kPointSlots> best_rate{0.0f, 0.0f, 0.0f, 0.0f};
                    int count = 0;

                    for (std::size_t si = 0; si < sources.size(); ++si) {
                        const Source &src = sources[si];
                        const int dx = lx - src.lx;
                        const int dy = ly - src.ly;
                        const int d2 = dx * dx + dy * dy;
                        if (d2 >= kPointReach * kPointReach) continue;
                        const float dist = std::sqrt(static_cast<float>(d2));
                        const float trans = ray_transmission(src.lx, src.ly, lx, ly);
                        if (trans <= 0.02f) continue;
                        const float rate = trans * src.spec.energy / (1.0f + dist);
                        int slot = count;
                        while (slot > 0 && best_rate[slot - 1] < rate) {
                            --slot;
                        }
                        if (slot >= kPointSlots) continue;
                        const int move_end = std::min(count, kPointSlots - 1);
                        for (int k = move_end; k > slot; --k) {
                            best_idx[k] = best_idx[k - 1];
                            best_trans[k] = best_trans[k - 1];
                            best_rate[k] = best_rate[k - 1];
                        }
                        best_idx[slot] = static_cast<float>(si + 1);
                        best_trans[slot] = trans;
                        best_rate[slot] = rate;
                        if (count < kPointSlots) ++count;
                    }

                    if (count > 0) {
                        float *idx_px = slots_f + ly * stride_f + lx * 4;
                        float *tr_px = slots_f + ly * stride_f + (lx + w) * 4;
                        for (int k = 0; k < kPointSlots; ++k) {
                            idx_px[k] = best_idx[k];
                            tr_px[k] = best_trans[k];
                        }
                    }
                }
            }
        });
    }

    // Lamps texture: max(1, sources.size()) x 2 RGBA32F
    const int lamp_w = std::max(1, static_cast<int>(sources.size()));
    godot::PackedByteArray lamps_buf;
    lamps_buf.resize(lamp_w * 2 * 4 * static_cast<int>(sizeof(float)));
    auto *lamps_f = reinterpret_cast<float *>(lamps_buf.ptrw());
    std::memset(lamps_f, 0, static_cast<std::size_t>(lamps_buf.size()));
    for (std::size_t i = 0; i < sources.size(); ++i) {
        const Source &s = sources[i];
        float *row0 = lamps_f + i * 4;
        float *row1 = lamps_f + (static_cast<std::size_t>(lamp_w) + i) * 4;
        row0[0] = static_cast<float>(s.lx) + 0.5f;
        row0[1] = static_cast<float>(s.ly) + 0.5f;
        row0[2] = s.spec.z_height;
        row0[3] = s.spec.energy;
        row1[0] = s.spec.r;
        row1[1] = s.spec.g;
        row1[2] = s.spec.b;
        row1[3] = s.spec.flicker_kind + std::clamp(s.spec.always_fraction, 0.0f, 0.92f);
    }

    result["slots"] = slots_buf;
    result["lamps"] = lamps_buf;
    result["lamp_count"] = lamp_w;
    result["emitters"] = active_emitters;
    return result;
}

} // namespace cangling
