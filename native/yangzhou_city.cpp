#include "city.hpp"
#include <algorithm>
#include <cmath>
#include <cstring>

namespace cangling {
namespace {

// ---------------------------------------------------------------------------
// 100% Handcrafted Classic Wuxia MUD × Historic Yangzhou Master Blueprint
// Cangling City (沧灵城) — 240 x 240 tiles, ZERO RNG!
//
// Architectural Grammar:
//  1. Classic Wuxia MUD Mental Compass (侠客行 / 北侠扬州城):
//     - Central Square (沧灵中央广场 + 古槐树) at (120, 120)
//     - 4 Themed Main Streets (十里长街, 4 tiles wide):
//       * 南大街: 利源当铺, 王记铁匠铺, 醉仙楼, 英雄祠, 南门石拱桥, 沧灵南门
//       * 东关大街: 回春堂药铺, 通济钱庄, 福兴杂货铺, 东关石拱桥, 春风茶馆, 水埠码头, 沧灵东门
//       * 北大街: 悦来客栈, 文昌阁, 文昌书院, 沧灵府衙, 沧灵北门
//       * 西市大街: 扬威武馆, 镇远镖局, 西市里弄, 沧灵西门
//  2. Real Historic Yangzhou Morphology (东关街 / 仁丰里 / 小秦淮河 / 瘦西湖):
//     - 1 Main S-Curve Canal (小秦淮玉带主河) + 3 Graceful Tributary Water-Alleys
//       (南水弄, 西水弄, 东水弄) + NW Cuiwei Lake & Five-Pavilion Bridge.
//     - "One River, One Street" (一河一街): North/West bank of main canal has a 1-tile
//       stone towpath; South/East banks & creeks have stepped pillow-on-water houses
//       with wooden lattice windows overlooking the water.
//     - Fishbone Alleys (仁丰里鱼骨支弄): 2-tile T-junction residential lanes spaced
//       every 12-13 tiles so two rows of 5-6 tile deep houses sit back-to-back with
//       ZERO wasted plazas and ZERO doors facing walls!
//  3. Hard Street-First Invariants (Zero Door-Against-Wall Guarantee):
//     - Every house MUST open its door strictly onto an existing passable road_mask tile
//       (NEVER blind fallback, NEVER into water, NEVER into a neighbor's wall).
//     - Every door reserves its exterior landing tile in door_apron_mask so no later
//       house, wall, tree, or lantern can EVER obstruct an existing doorway.
//     - Post-build topology pass verifies every 'D' tile across all 240x240 tiles.
// ---------------------------------------------------------------------------

struct Builder {
    YangzhouWorldData data;
    std::vector<std::uint8_t> water_mask;
    std::vector<std::uint8_t> creek_mask;
    std::vector<std::uint8_t> road_mask;
    std::vector<std::uint8_t> door_apron_mask;
    std::vector<Vector2i> all_river_pts;

    Builder() {
        const std::size_t n = static_cast<std::size_t>(city_size * city_size);
        for (int z = 0; z < 3; ++z) {
            data.tiles[z].assign(n, z == 0 ? '.' : ' ');
            data.surfaces[z].assign(n, '\0');
            data.enclosed[z].assign(n, 0);
        }
        water_mask.assign(n, 0);
        creek_mask.assign(n, 0);
        road_mask.assign(n, 0);
        door_apron_mask.assign(n, 0);
    }

    static bool valid(int x, int y) {
        return x >= 0 && y >= 0 && x < city_size && y < city_size;
    }

    static std::size_t idx(int x, int y) {
        return static_cast<std::size_t>(y * city_size + x);
    }

    static int det_hash(int x, int y, int salt = 0) {
        std::uint32_t n = static_cast<std::uint32_t>(x) * 374761393u +
                          static_cast<std::uint32_t>(y) * 668265263u +
                          static_cast<std::uint32_t>(salt) * 1442695041u;
        n = (n ^ (n >> 13u)) * 1274126177u;
        return static_cast<int>((n ^ (n >> 16u)) & 0x7fffffffu);
    }

    char get_tile(int x, int y, int z = 0) const {
        if (!valid(x, y)) return ' ';
        return data.tiles[z][idx(x, y)];
    }

    void set(int x, int y, char t, char s = '\0', int z = 0, bool enc = false) {
        if (!valid(x, y) || z < 0 || z >= 3) return;
        const std::size_t i = idx(x, y);
        data.tiles[z][i] = t;
        if (s != '\0' || z == 0) data.surfaces[z][i] = s;
        data.enclosed[z][i] = enc ? 1 : 0;
    }

    void fill(int x0, int y0, int x1, int y1, char t, char s = '\0', int z = 0, bool enc = false) {
        for (int y = y0; y <= y1; ++y)
            for (int x = x0; x <= x1; ++x) set(x, y, t, s, z, enc);
    }

    void reserve_open_area(int x0, int y0, int x1, int y1) {
        for (int y = y0; y <= y1; ++y)
            for (int x = x0; x <= x1; ++x)
                if (valid(x, y)) {
                    road_mask[idx(x, y)] = 1;
                    door_apron_mask[idx(x, y)] = 1;
                }
    }

    void add_zone(int x0, int y0, int x1, int y1, const char *name) {
        data.zones.push_back({Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1), name});
    }

    // Strict check: a street tile is a valid exterior doorway landing ONLY if it is
    // committed road_mask, dry, unenclosed, and clean walkable stone (':' or '+').
    bool is_valid_door_landing(int x, int y) const {
        if (!valid(x, y)) return false;
        const std::size_t i = idx(x, y);
        if (!road_mask[i] || water_mask[i] || data.enclosed[0][i]) return false;
        const char t = data.tiles[0][i];
        return t == ':' || t == '+';
    }

    bool area_is_clear_for_house(int x0, int y0, int x1, int y1) const {
        if (x0 < 25 || y0 < 25 || x1 > 214 || y1 > 214) return false;
        if (x0 < 94 && y0 < 78) return false; // Preserve NW Cuiwei Lake willow park
        for (int y = y0; y <= y1; ++y) {
            for (int x = x0; x <= x1; ++x) {
                const std::size_t i = idx(x, y);
                if (water_mask[i] || road_mask[i] || door_apron_mask[i] || data.enclosed[0][i]) return false;
                const char t = data.tiles[0][i];
                if (t != ':' && t != '.') return false;
            }
        }
        return true;
    }

    // Pick a roof/wall style ('H'/'B'/'N') contrasting with adjacent wall-to-wall buildings
    // so every row-house receives its own distinct pitched roof & white stepped 马头墙!
    char pick_contrasting_style(int x0, int y0, int x1, int y1, int seed_idx) const {
        int counts[3] = {0, 0, 0};
        auto sample_n = [&](int x, int y) {
            if (!valid(x, y) || !data.enclosed[0][idx(x, y)]) return;
            const char s = data.surfaces[0][idx(x, y)];
            if (s == 'H') ++counts[0];
            else if (s == 'B') ++counts[1];
            else if (s == 'N') ++counts[2];
        };
        for (int x = x0; x <= x1; ++x) { sample_n(x, y0 - 1); sample_n(x, y1 + 1); }
        for (int y = y0; y <= y1; ++y) { sample_n(x0 - 1, y); sample_n(x1 + 1, y); }
        const char order[3] = {'H', 'B', 'N'};
        int best = seed_idx % 3;
        int best_c = counts[best];
        for (int k = 0; k < 3; ++k) {
            const int idx_s = (seed_idx + k) % 3;
            if (counts[idx_s] < best_c) {
                best_c = counts[idx_s];
                best = idx_s;
            }
        }
        return order[best];
    }

    void carve_spline_river(const std::vector<Vector2i> &pts, double half_w, bool closed_loop, bool is_tributary = false) {
        if (pts.size() < 2) return;
        const int n = static_cast<int>(pts.size());
        auto pt_at = [&](int i) -> Vector2i {
            if (closed_loop) return pts[static_cast<std::size_t>(((i % n) + n) % n)];
            return pts[static_cast<std::size_t>(std::clamp(i, 0, n - 1))];
        };
        const int segs = closed_loop ? n : (n - 1);
        const int steps_per_seg = 56;
        const int r_ceil = static_cast<int>(std::ceil(half_w + 1.5));

        for (int s = 0; s < segs; ++s) {
            const Vector2i p0 = pt_at(s - 1);
            const Vector2i p1 = pt_at(s);
            const Vector2i p2 = pt_at(s + 1);
            const Vector2i p3 = pt_at(s + 2);
            for (int k = 0; k <= steps_per_seg; ++k) {
                const double t = static_cast<double>(k) / static_cast<double>(steps_per_seg);
                const double t2 = t * t, t3 = t2 * t;
                const double cx = 0.5 * ((2.0 * p1.x) + (-p0.x + p2.x) * t +
                    (2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x) * t2 +
                    (-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x) * t3);
                const double cy = 0.5 * ((2.0 * p1.y) + (-p0.y + p2.y) * t +
                    (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t2 +
                    (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * t3);
                const int icx = static_cast<int>(std::round(cx));
                const int icy = static_cast<int>(std::round(cy));
                if (k % 6 == 0 && valid(icx, icy)) all_river_pts.push_back({icx, icy});
                for (int dy = -r_ceil; dy <= r_ceil; ++dy) {
                    for (int dx = -r_ceil; dx <= r_ceil; ++dx) {
                        const int gx = icx + dx, gy = icy + dy;
                        if (!valid(gx, gy)) continue;
                        const double dist = std::hypot(static_cast<double>(gx) - cx, static_cast<double>(gy) - cy);
                        if (dist <= half_w) {
                            const char cur = get_tile(gx, gy, 0);
                            const char nt = (dist <= std::max(0.75, half_w - 1.0)) ? 'W' : '~';
                            if (cur != 'W' || nt == 'W') set(gx, gy, nt, '\0', 0, false);
                            water_mask[idx(gx, gy)] = 1;
                            if (is_tributary) creek_mask[idx(gx, gy)] = 1;
                        }
                    }
                }
            }
        }
    }

    void carve_cuiwei_lake() {
        const double cx = 61.0, cy = 52.0;
        for (int y = 29; y <= 75; ++y) {
            for (int x = 29; x <= 93; ++x) {
                const double dx = (static_cast<double>(x) - cx) / 27.0;
                const double dy = (static_cast<double>(y) - cy) / 18.5;
                const double ang = std::atan2(dy, dx);
                const double wobble = 0.08 * std::sin(ang * 3.0 + 0.5) + 0.05 * std::cos(ang * 5.0 - 0.8);
                const double r = std::hypot(dx, dy) + wobble;
                if (r <= 1.0) {
                    set(x, y, r <= 0.85 ? 'W' : '~', '\0', 0, false);
                    water_mask[idx(x, y)] = 1;
                }
            }
        }
        for (int y = 26; y <= 77; ++y) {
            for (int x = 26; x <= 93; ++x) {
                if (water_mask[idx(x, y)]) continue;
                const int h = (x * 17 + y * 31) % 19;
                if (h == 0 || h == 6) set(x, y, 'Y', '\0', 0, false);
                else if (h == 11) set(x, y, 'g', '\0', 0, false);
            }
        }
        add_zone(30, 30, 92, 74, "翠微湖 · 五亭桥");
    }

    // "One River, One Street" (一河一街):
    // 1-tile stone towpath on the NORTH/WEST bank of the main river ONLY;
    // South/East banks & tributary creeks have ZERO road buffer so houses sit FLUSH over water!
    void build_river_quays() {
        for (int y = 25; y <= 214; ++y) {
            for (int x = 25; x <= 214; ++x) {
                if (water_mask[idx(x, y)]) continue;
                const bool s_w = valid(x, y + 1) && water_mask[idx(x, y + 1)];
                const bool e_w = valid(x + 1, y) && water_mask[idx(x + 1, y)];
                if (s_w || e_w) {
                    const bool is_main = (s_w && !creek_mask[idx(x, y + 1)]) || (e_w && !creek_mask[idx(x + 1, y)]);
                    if (is_main) {
                        set(x, y, ':', 'p', 0, false);
                        road_mask[idx(x, y)] = 1;
                    }
                }
            }
        }
    }

    void build_road_rect(int x0, int y0, int x1, int y1, bool main_ave) {
        for (int y = y0; y <= y1; ++y) {
            for (int x = x0; x <= x1; ++x) {
                if (!valid(x, y) || water_mask[idx(x, y)]) continue;
                set(x, y, main_ave ? '+' : ':', main_ave ? 'm' : 'p', 0, false);
                road_mask[idx(x, y)] = 1;
            }
        }
    }

    void build_arch_bridge(int x0, int y0, int x1, int y1, bool vertical_span, const char *name, bool main_ave = false) {
        if (vertical_span) {
            int min_wy = y1, max_wy = y0;
            for (int y = y0; y <= y1; ++y)
                for (int x = x0; x <= x1; ++x)
                    if (valid(x, y) && water_mask[idx(x, y)]) {
                        min_wy = std::min(min_wy, y);
                        max_wy = std::max(max_wy, y);
                    }
            for (int y = y0; y <= y1; ++y) {
                const bool on_deck = (min_wy <= max_wy) && (y >= min_wy && y <= max_wy);
                for (int x = x0; x <= x1; ++x) {
                    if (!valid(x, y)) continue;
                    set(x, y, on_deck ? '=' : (main_ave ? '+' : ':'), on_deck ? '=' : (main_ave ? 'm' : 'p'), 0, false);
                    road_mask[idx(x, y)] = 1;
                }
            }
        } else {
            int min_wx = x1, max_wx = x0;
            for (int y = y0; y <= y1; ++y)
                for (int x = x0; x <= x1; ++x)
                    if (valid(x, y) && water_mask[idx(x, y)]) {
                        min_wx = std::min(min_wx, x);
                        max_wx = std::max(max_wx, x);
                    }
            for (int y = y0; y <= y1; ++y) {
                for (int x = x0; x <= x1; ++x) {
                    if (!valid(x, y)) continue;
                    const bool on_deck = (min_wx <= max_wx) && (x >= min_wx && x <= max_wx);
                    set(x, y, on_deck ? '=' : (main_ave ? '+' : ':'), on_deck ? '=' : (main_ave ? 'm' : 'p'), 0, false);
                    road_mask[idx(x, y)] = 1;
                }
            }
        }
        if (name && name[0] != '\0') add_zone(x0, y0, x1, y1, name);
    }

    void build_story_box(int x0, int y0, int x1, int y1, int z, char style, char floor_surf = '\0') {
        const char fs = floor_surf ? floor_surf : style;
        for (int y = y0; y <= y1; ++y) {
            for (int x = x0; x <= x1; ++x) {
                const bool edge = (x == x0 || x == x1 || y == y0 || y == y1);
                set(x, y, edge ? '#' : 'i', edge ? style : fs, z, true);
            }
        }
    }

    void place_door(int dx, int dy, int ox, int oy, int z, char style) {
        set(dx, dy, 'D', style, z, true);
        if (z == 0 && valid(ox, oy)) {
            door_apron_mask[idx(ox, oy)] = 1;
            if (!water_mask[idx(ox, oy)] && !data.enclosed[0][idx(ox, oy)]) {
                const char ot = get_tile(ox, oy, 0);
                if (ot != ':' && ot != '+') set(ox, oy, ':', 'p', 0, false);
                road_mask[idx(ox, oy)] = 1;
            }
        }
    }

    // Automatically carve wooden lattice windows ('w') on ANY wall edge facing water (枕河花窗!)
    void add_waterside_windows(int x0, int y0, int x1, int y1, int z, char style) {
        auto faces_water = [&](int x, int y) -> bool {
            for (int dy = -2; dy <= 2; ++dy) {
                for (int dx = -2; dx <= 2; ++dx) {
                    if (std::abs(dx) + std::abs(dy) > 2 || !valid(x + dx, y + dy)) continue;
                    if (water_mask[idx(x + dx, y + dy)]) return true;
                }
            }
            return false;
        };
        for (int x = x0 + 1; x <= x1 - 1; ++x) {
            if (get_tile(x, y0, z) == '#' && faces_water(x, y0) && ((x - x0) % 2 == 1)) set(x, y0, 'w', style, z, true);
            if (get_tile(x, y1, z) == '#' && faces_water(x, y1) && ((x - x0) % 2 == 1)) set(x, y1, 'w', style, z, true);
        }
        for (int y = y0 + 1; y <= y1 - 1; ++y) {
            if (get_tile(x0, y, z) == '#' && faces_water(x0, y) && ((y - y0) % 2 == 1)) set(x0, y, 'w', style, z, true);
            if (get_tile(x1, y, z) == '#' && faces_water(x1, y) && ((y - y0) % 2 == 1)) set(x1, y, 'w', style, z, true);
        }
    }

    void carve_courtyard(int x0, int y0, int x1, int y1, char surround_style, bool with_tree = true) {
        for (int x = x0 - 1; x <= x1 + 1; ++x) {
            if (valid(x, y0 - 1) && data.enclosed[0][idx(x, y0 - 1)])
                set(x, y0 - 1, (x == (x0 + x1) / 2) ? 'D' : ((x - x0) % 2 == 0 ? 'w' : '#'), surround_style, 0, true);
            if (valid(x, y1 + 1) && data.enclosed[0][idx(x, y1 + 1)])
                set(x, y1 + 1, (x == (x0 + x1) / 2) ? 'D' : ((x - x0) % 2 == 0 ? 'w' : '#'), surround_style, 0, true);
        }
        for (int y = y0; y <= y1; ++y) {
            if (valid(x0 - 1, y) && data.enclosed[0][idx(x0 - 1, y)])
                set(x0 - 1, y, (y == (y0 + y1) / 2) ? 'D' : ((y - y0) % 2 == 0 ? 'w' : '#'), surround_style, 0, true);
            if (valid(x1 + 1, y) && data.enclosed[0][idx(x1 + 1, y)])
                set(x1 + 1, y, (y == (y0 + y1) / 2) ? 'D' : ((y - y0) % 2 == 0 ? 'w' : '#'), surround_style, 0, true);
        }
        for (int y = y0; y <= y1; ++y) {
            for (int x = x0; x <= x1; ++x) {
                set(x, y, ':', 'p', 0, false);
                set(x, y, ' ', '\0', 1, false);
                set(x, y, ' ', '\0', 2, false);
            }
        }
        reserve_open_area(x0, y0, x1, y1);
        const int mx = (x0 + x1) / 2, my = (y0 + y1) / 2;
        if (x1 - x0 >= 3 && y1 - y0 >= 3) {
            set(mx, my, with_tree ? 'Y' : 'P', 'p', 0, false);
        }
    }

    void place_windows_h(int y, int x0, int x1, int step, int z, char style) {
        for (int x = x0; x <= x1; x += step)
            if (get_tile(x, y, z) == '#') set(x, y, 'w', style, z, true);
    }

    void place_windows_v(int x, int y0, int y1, int step, int z, char style) {
        for (int y = y0; y <= y1; y += step)
            if (get_tile(x, y, z) == '#') set(x, y, 'w', style, z, true);
    }

    void build_table_set(int tx, int ty, int z, char floor_surf) {
        set(tx, ty, 't', floor_surf, z, true);
        if (get_tile(tx - 1, ty, z) == 'i') set(tx - 1, ty, 'q', floor_surf, z, true);
        if (get_tile(tx + 1, ty, z) == 'i') set(tx + 1, ty, 'q', floor_surf, z, true);
    }

    // -----------------------------------------------------------------------
    // STAGE 1: OUTER MOAT, CITY WALLS & 4 GATEWAYS
    // -----------------------------------------------------------------------
    void build_moat_and_walls() {
        fill(25, 25, 214, 214, ':', 'p', 0, false);
        fill(25, 25, 93, 77, '.', '\0', 0, false);

        for (int y = 0; y < city_size; ++y) {
            for (int x = 0; x < city_size; ++x) {
                const bool in_outer = (x >= 11 && x <= 228 && y >= 11 && y <= 228);
                const bool in_inner = (x >= 19 && x <= 220 && y >= 19 && y <= 220);
                if (in_outer && !in_inner) {
                    const bool deep = (x >= 13 && x <= 226 && y >= 13 && y <= 226) &&
                                      !(x >= 17 && x <= 222 && y >= 17 && y <= 222);
                    set(x, y, deep ? 'W' : '~', '\0', 0, false);
                    water_mask[idx(x, y)] = 1;
                }
            }
        }
        for (int i = 6; i < city_size - 6; i += 6) {
            set(i, 6, 'Y', '\0', 0, false);
            set(i, 233, 'Y', '\0', 0, false);
            set(6, i, 'Y', '\0', 0, false);
            set(233, i, 'Y', '\0', 0, false);
        }

        fill(23, 23, 216, 24, '#', 'B', 0, false);
        fill(23, 215, 216, 216, '#', 'B', 0, false);
        fill(23, 23, 24, 216, '#', 'B', 0, false);
        fill(215, 23, 216, 216, '#', 'B', 0, false);

        // 沧灵南门 (4-tile main gate road: x=118..121)
        build_road_rect(118, 200, 121, 238, true);
        build_arch_bridge(118, 220, 121, 229, true, "南护城石拱桥", true);
        fill(118, 214, 121, 217, '+', 'm', 0, false);
        build_story_box(113, 212, 117, 217, 0, 'B', 'B');
        build_story_box(113, 212, 117, 217, 1, 'B', 'B');
        place_door(117, 214, 118, 214, 0, 'B');
        set(115, 214, '^', 'B', 0, true);
        set(115, 214, 'v', 'B', 1, true);
        build_story_box(122, 212, 126, 217, 0, 'B', 'B');
        build_story_box(122, 212, 126, 217, 1, 'B', 'B');
        place_door(122, 214, 121, 214, 0, 'B');
        set(124, 214, '^', 'B', 0, true);
        set(124, 214, 'v', 'B', 1, true);
        reserve_open_area(117, 205, 122, 211);
        set(117, 209, 'L', 'm', 0, false);
        set(122, 209, 'L', 'm', 0, false);
        add_zone(113, 206, 126, 220, "沧灵南门");

        // 北门, 西门, 东门
        build_road_rect(118, 1, 121, 32, true);
        build_arch_bridge(118, 10, 121, 19, true, "北护城石拱桥", true);
        fill(118, 22, 121, 25, '+', 'm', 0, false);
        build_story_box(113, 22, 117, 27, 0, 'B', 'B');
        build_story_box(122, 22, 126, 27, 0, 'B', 'B');
        place_door(117, 24, 118, 24, 0, 'B');
        place_door(122, 24, 121, 24, 0, 'B');
        add_zone(113, 20, 126, 29, "沧灵北门");

        build_road_rect(1, 118, 32, 121, true);
        build_arch_bridge(10, 118, 19, 121, false, "西护城石拱桥", true);
        fill(22, 118, 25, 121, '+', 'm', 0, false);
        build_story_box(22, 113, 27, 117, 0, 'B', 'B');
        build_story_box(22, 122, 27, 126, 0, 'B', 'B');
        place_door(24, 117, 24, 118, 0, 'B');
        place_door(24, 122, 24, 121, 0, 'B');
        add_zone(20, 113, 29, 126, "沧灵西门");

        build_road_rect(208, 118, 238, 121, true);
        build_arch_bridge(220, 118, 229, 121, false, "东护城石拱桥", true);
        fill(214, 118, 217, 121, '+', 'm', 0, false);
        build_story_box(212, 113, 217, 117, 0, 'B', 'B');
        build_story_box(212, 122, 217, 126, 0, 'B', 'B');
        place_door(214, 117, 214, 118, 0, 'B');
        place_door(214, 122, 214, 121, 0, 'B');
        add_zone(210, 113, 220, 126, "沧灵东门");
    }

    // -----------------------------------------------------------------------
    // STAGE 2: WATERWAYS, BRIDGES, CROSS MAIN STREETS & FISHBONE ALLEYS
    // -----------------------------------------------------------------------
    void build_waterways_streets_and_fishbones() {
        carve_cuiwei_lake();

        // Main S-Curve Xiaoqinhuai / Jade Belt River (12 cruising boats water-locked here!)
        const std::vector<Vector2i> jade_loop = {
            {84, 58}, {100, 69}, {120, 72}, {144, 70}, {164, 80},
            {172, 98}, {166, 120}, {154, 138}, {155, 158}, {162, 174},
            {156, 192}, {135, 196}, {120, 193}, {98, 196}, {74, 188},
            {62, 168}, {54, 144}, {65, 120}, {58, 96}, {61, 70}
        };
        carve_spline_river(jade_loop, 3.85, true, false);

        // 3 Orderly Yangzhou Tributary Water-Alleys (南水弄, 西水弄, 东水弄 — 4 tiles wide!)
        carve_spline_river({{64, 172}, {88, 175}, {116, 174}, {138, 175}, {159, 174}}, 1.95, false, true);
        carve_spline_river({{56, 144}, {44, 146}, {30, 144}, {14, 144}}, 1.95, false, true);
        carve_spline_river({{168, 97}, {184, 96}, {193, 114}, {194, 142}, {193, 171}, {204, 182}, {225, 182}}, 2.0, false, true);

        build_river_quays();

        // 1. Classic Wuxia MUD Cross Main Streets (十里长街, 4 tiles wide)
        build_road_rect(118, 26, 121, 214, true);
        build_road_rect(26, 118, 214, 121, true);

        // 2. Central Square (沧灵中央广场 — 10x10 with ancient scholar tree!)
        fill(115, 115, 124, 124, '+', 'p', 0, false);
        reserve_open_area(115, 115, 124, 124);
        set(120, 120, 'Y', 'p', 0, false);
        set(116, 116, 'L', 'p', 0, false); set(123, 116, 'L', 'p', 0, false);
        set(116, 123, 'S', 'p', 0, false); set(123, 123, 'S', 'p', 0, false);
        add_zone(115, 115, 124, 124, "沧灵中央广场");

        // 3. Clean District Collector Spines (坊内主巷, 2 tiles wide — ZERO conflicting double-grids!)
        build_road_rect(96,  48,  212, 49,  false); // North collector (府前—仁丰北)
        build_road_rect(27,  95,  212, 96,  false); // Mid-North collector (文昌南—西市北—仁丰南)
        build_road_rect(27,  145, 212, 146, false); // Mid-South collector (青莲桥—茶烟桥)
        build_road_rect(27,  183, 212, 184, false); // South collector (南水弄南岸巷)

        build_road_rect(40,  78,  41,  212, false); // Far-West spine
        build_road_rect(94,  74,  95,  212, false); // West Market spine
        build_road_rect(143, 28,  144, 212, false); // Inner-East spine (廿四桥—醉仙水桥)
        build_road_rect(171, 28,  172, 212, false); // Dongguan spine (东关南北长巷)
        build_road_rect(204, 28,  205, 212, false); // Far-East spine

        // 4. Real Yangzhou "Fishbone" Alleys (仁丰里鱼骨支弄 — 2-tile T-junction lanes spaced 12-13 tiles apart!)
        //    Each band between two fishbone lanes is 10-12 tiles thick = TWO 5-6 tile back-to-back rows of houses!
        //    ZERO empty center voids, ZERO doors against walls!
        // (a) 仁丰里 (NE: horizontal fishbone lanes branching off x=171..172 & x=143..144)
        for (int fy : {34, 61, 79}) {
            build_road_rect(145, fy, 170, fy + 1, false);
        }
        for (int fy : {35, 62, 80, 107}) {
            build_road_rect(173, fy, 203, fy + 1, false);
        }
        for (int fy : {36, 63, 81, 107}) {
            build_road_rect(206, fy, 212, fy + 1, false);
        }
        // (b) 东关水市坊 (SE: staggered horizontal fishbone lanes east of Xiaoqinhuai River)
        for (int fy : {132, 158, 170, 198}) {
            build_road_rect(173, fy, 203, fy + 1, false);
        }
        for (int fy : {133, 158, 197}) {
            build_road_rect(206, fy, 212, fy + 1, false);
        }
        // (c) 府前文昌坊 (North-Central: clean horizontal lanes off North Street x=118..121)
        for (int fy : {34, 60}) {
            build_road_rect(96, fy, 117, fy + 1, false);
            build_road_rect(122, fy, 142, fy + 1, false);
        }
        build_road_rect(96,  81, 114, 82, false);
        build_road_rect(125, 81, 142, 82, false);
        // (d) 西市武坊 (West: staggered fishbone lanes off x=40..41 and x=94..95)
        for (int fy : {82, 107, 132, 158, 170, 198}) {
            build_road_rect(27, fy, 39, fy + 1, false);
            build_road_rect(42, fy + 1, 93, fy + 2, false);
        }
        // (e) 南水烟火坊 & 中街市井坊 (Mid-South & Far-South clean alleys!)
        build_road_rect(96,  133, 107, 134, false); // Behind 扬威武馆 / 利源当铺
        build_road_rect(96,  162, 117, 163, false); // South of 王记铁匠铺
        build_road_rect(122, 162, 142, 163, false); // South of 醉仙楼
        build_road_rect(96,  198, 142, 199, false); // South of South Main River
        build_road_rect(145, 198, 170, 199, false); // SE near South Main River
        // Vertical micro-connectors in mid-blocks so every lane loops cleanly
        build_road_rect(157, 36, 158, 61, false);
        build_road_rect(187, 36, 188, 94, false);
        build_road_rect(187, 122, 188, 182, false);
        build_road_rect(72,  82,  73,  117, false);
        build_road_rect(72,  122, 73,  170, false);
        build_road_rect(72,  185, 73,  212, false);
        build_road_rect(106, 185, 107, 212, false);
        build_road_rect(132, 185, 133, 212, false);

        // 5. 22 STONE ARCH BRIDGES (Weathered bluestone arch bridges across every waterway crossing!)
        build_arch_bridge(34, 51, 88, 53, false, "五亭桥", false);
        for (int px : {43, 52, 61, 70, 79}) {
            fill(px - 2, 49, px + 2, 55, '=', '=', 0, false);
            set(px - 2, 49, 'L', '=', 0, false); set(px + 2, 49, 'L', '=', 0, false);
            set(px - 2, 55, 'L', '=', 0, false); set(px + 2, 55, 'L', '=', 0, false);
        }
        set(61, 51, 't', '=', 0, false); set(60, 51, 'q', '=', 0, false); set(62, 51, 'q', '=', 0, false);

        // Main Street Arch Bridges
        build_arch_bridge(118, 188, 121, 198, true,  "南门石拱桥", true);
        build_arch_bridge(118, 170, 121, 179, true,  "南巷水桥",   true);
        build_arch_bridge(118, 67,  121, 77,  true,  "府前石拱桥", true);
        build_arch_bridge(161, 118, 172, 121, false, "东关石拱桥", true);
        build_arch_bridge(189, 118, 199, 121, false, "东水弄桥",   true);
        build_arch_bridge(59,  118, 70,  121, false, "西市石拱桥", true);

        // Collector & Alley Arch Bridges
        build_arch_bridge(149, 157, 161, 159, false, "虹桥",       false);
        build_arch_bridge(148, 145, 160, 146, false, "青莲桥",     false);
        build_arch_bridge(166, 95,  178, 96,  false, "画舫桥",     false);
        build_arch_bridge(188, 145, 199, 146, false, "茶烟小桥",   false);
        build_arch_bridge(189, 158, 199, 159, false, "东关水桥",   false);
        build_arch_bridge(188, 170, 198, 171, false, "水埠小桥",   false);
        build_arch_bridge(143, 171, 144, 180, true,  "醉仙水桥",   false);
        build_arch_bridge(143, 65,  144, 76,  true,  "廿四桥",     false);
        build_arch_bridge(94,  171, 95,  180, true,  "铁巷小桥",   false);
        build_arch_bridge(94,  189, 95,  201, true,  "南水石桥",   false);
        build_arch_bridge(52,  145, 62,  146, false, "西溪步桥",   false);
        build_arch_bridge(56,  159, 68,  160, false, "柳荫桥",     false);
        build_arch_bridge(53,  95,  64,  96,  false, "垂柳桥",     false);
        build_arch_bridge(40,  141, 41,  150, true,  "西水弄桥",   false);
        build_arch_bridge(204, 178, 205, 187, true,  "南水门桥",   false);
    }

    // -----------------------------------------------------------------------
    // STAGE 3: CLASSIC WUXIA MUD YANGZHOU LANDMARKS & FRONT-SHOP/BACK-HOUSE STORES
    // Every building is street-front with its door locked strictly onto road_mask!
    // -----------------------------------------------------------------------
    void build_classic_wuxia_landmarks() {
        // --- NORTH STREET (北大街: 悦来客栈, 文昌阁, 文昌书院, 沧灵府衙) ---

        // 1. 悦来客栈 — Cozy 2-story inn right beside Central Square (108..117, 104..113)
        build_story_box(108, 104, 117, 113, 0, 'N', 'N');
        place_door(117, 109, 118, 109, 0, 'N');
        place_windows_v(117, 106, 111, 2, 0, 'N');
        place_windows_h(113, 110, 115, 2, 0, 'N');
        set(113, 107, 'k', 'N', 0, true); set(113, 108, 'k', 'N', 0, true);
        build_table_set(111, 111, 0, 'N');
        set(110, 106, 'h', 'N', 0, true); set(115, 106, '^', 'N', 0, true);
        build_story_box(109, 105, 116, 112, 1, 'N', 'N');
        set(115, 106, 'v', 'N', 1, true);
        set(111, 106, 'b', 'N', 1, true); set(111, 110, 'b', 'N', 1, true);
        add_zone(108, 104, 117, 113, "悦来客栈");

        // 2. 文昌阁 — Iconic 3-story octagonal-cross pavilion straddling North Street (115..124, 83..93)
        build_story_box(117, 83, 122, 93, 0, 'N', 'N');
        build_story_box(115, 85, 124, 91, 0, 'N', 'N');
        fill(118, 86, 121, 90, 'i', 'N', 0, true);
        place_door(119, 93, 119, 94, 0, 'N');
        place_door(119, 83, 119, 82, 0, 'N');
        place_door(115, 88, 114, 88, 0, 'N');
        place_door(124, 88, 125, 88, 0, 'N');
        reserve_open_area(114, 87, 114, 89);
        reserve_open_area(125, 87, 125, 89);
        set(121, 87, '^', 'N', 0, true);
        build_story_box(116, 84, 123, 92, 1, 'N', 'N');
        set(121, 87, 'X', 'N', 1, true);
        build_story_box(118, 86, 121, 90, 2, 'N', 'N');
        set(120, 87, 'v', 'N', 2, true);
        add_zone(115, 83, 124, 93, "文昌阁");

        // 3. 文昌书院 — Classic MUD Academy right beside Wenchang Pavilion (126..135, 84..94)
        build_story_box(126, 84, 135, 94, 0, 'H', 'H');
        place_door(130, 94, 130, 95, 0, 'H');
        place_windows_h(94, 128, 133, 2, 0, 'H');
        set(128, 86, 'r', 'H', 0, true); set(130, 86, 'r', 'H', 0, true); set(132, 86, 'r', 'H', 0, true);
        build_table_set(129, 90, 0, 'H');
        build_table_set(133, 90, 0, 'H');
        add_zone(126, 84, 135, 94, "文昌书院");

        // 4. 沧灵府衙 — North-axis courtyard Yamen (112..127, 33..47)
        build_story_box(112, 33, 127, 47, 0, 'B', 'B');
        carve_courtyard(116, 39, 123, 44, 'B', true);
        place_door(119, 47, 119, 48, 0, 'B');
        set(120, 36, 'l', 'B', 0, true); set(120, 35, 'q', 'B', 0, true);
        set(125, 35, '^', 'B', 0, true);
        build_story_box(114, 34, 125, 38, 1, 'B', 'B');
        set(124, 35, 'v', 'B', 1, true);
        add_zone(112, 33, 127, 47, "沧灵府衙");

        // --- SOUTH STREET (南大街: 利源当铺, 英雄祠, 王记铁匠铺, 醉仙楼) ---

        // 5. 利源当铺 — West of South Street near Square (109..117, 126..134)
        build_story_box(109, 126, 117, 134, 0, 'B', 'B');
        place_door(117, 130, 118, 130, 0, 'B');
        place_windows_v(117, 128, 132, 2, 0, 'B');
        set(115, 128, 'k', 'B', 0, true); set(115, 129, 'k', 'B', 0, true);
        set(115, 131, 'k', 'B', 0, true); set(115, 132, 'k', 'B', 0, true);
        set(114, 130, 'i', 'B', 0, true); // 唐掌柜 @ (114, 130)
        set(111, 128, 'K', 'B', 0, true); set(111, 132, 'C', 'B', 0, true);
        add_zone(109, 126, 117, 134, "利源当铺");

        // 6. 英雄祠 (武庙) — East of South Street near Square (122..130, 126..134)
        build_story_box(122, 126, 130, 134, 0, 'N', 'N');
        place_door(122, 130, 121, 130, 0, 'N');
        place_windows_v(122, 128, 132, 2, 0, 'N');
        set(128, 130, 'l', 'N', 0, true);
        set(127, 128, 'L', 'N', 0, true); set(127, 132, 'L', 'N', 0, true);
        add_zone(122, 126, 130, 134, "英雄祠");

        // 7. 王记铁匠铺 — Cozy civilian home-smithy on South Street (108..117, 152..161)
        reserve_open_area(113, 152, 117, 161);
        fill(113, 152, 117, 161, ':', 'p', 0, false);
        fill(113, 152, 117, 152, '#', 'B', 0, false);
        fill(113, 161, 117, 161, '#', 'B', 0, false);
        for (int y = 153; y <= 160; ++y) set(117, y, (y >= 155 && y <= 158) ? ':' : 'f', 'p', 0, false);
        set(114, 153, 'h', 'p', 0, false); set(115, 153, 'u', 'p', 0, false);
        set(114, 160, 'h', 'p', 0, false); set(115, 160, 'C', 'p', 0, false);
        set(113, 156, 'k', 'p', 0, false);
        set(114, 157, ':', 'p', 0, false); // 王铁匠 @ (114, 157)
        build_story_box(108, 152, 112, 161, 0, 'B', 'B');
        place_door(112, 158, 113, 158, 0, 'B');
        set(110, 154, 'b', 'B', 0, true); set(110, 159, 'c', 'B', 0, true);
        add_zone(108, 152, 117, 161, "王记铁匠铺");

        // 8. 醉仙楼 — Cozy 2-story wine tavern on South Street (122..131, 152..161)
        build_story_box(122, 152, 131, 161, 0, 'N', 'N');
        place_door(122, 157, 121, 157, 0, 'N');
        place_door(127, 161, 127, 162, 0, 'N');
        place_windows_v(122, 154, 159, 2, 0, 'N');
        place_windows_h(161, 124, 129, 2, 0, 'N');
        set(127, 155, 'k', 'N', 0, true); set(127, 156, 'k', 'N', 0, true);
        set(127, 157, 'k', 'N', 0, true); set(127, 158, 'k', 'N', 0, true);
        set(126, 157, 'i', 'N', 0, true); // 冼老板 @ (126, 157)
        set(125, 157, 'i', 'N', 0, true);
        build_table_set(125, 159, 0, 'N');
        set(129, 154, 'h', 'N', 0, true); set(129, 155, 'h', 'N', 0, true); set(129, 157, 'a', 'N', 0, true);
        set(129, 159, '^', 'N', 0, true);
        build_story_box(123, 153, 130, 160, 1, 'N', 'N');
        set(129, 159, 'v', 'N', 1, true);
        build_table_set(126, 156, 1, 'N');
        add_zone(122, 152, 131, 161, "醉仙楼");

        // --- EAST STREET (东关大街: 回春堂药铺, 通济钱庄, 福兴杂货铺, 春风茶馆, 水埠码头) ---

        // 9. 回春堂药铺 — North of East Street (126..134, 109..117)
        build_story_box(126, 109, 134, 117, 0, 'H', 'H');
        place_door(130, 117, 130, 118, 0, 'H');
        place_windows_h(117, 128, 132, 2, 0, 'H');
        set(128, 111, 'K', 'H', 0, true); set(129, 111, 'K', 'H', 0, true);
        set(131, 111, 'K', 'H', 0, true); set(132, 111, 'K', 'H', 0, true);
        set(129, 114, 'l', 'H', 0, true); set(131, 114, 'q', 'H', 0, true);
        set(130, 113, 'i', 'H', 0, true); // 平大夫 @ (130, 113)
        set(127, 115, 'h', 'H', 0, true);
        add_zone(126, 109, 134, 117, "回春堂药铺");

        // 10. 通济钱庄 — Classic MUD Bank wall-to-wall with 回春堂 (135..142, 109..117)
        build_story_box(135, 109, 142, 117, 0, 'B', 'B');
        place_door(138, 117, 138, 118, 0, 'B');
        place_windows_h(117, 136, 140, 2, 0, 'B');
        set(137, 113, 'k', 'B', 0, true); set(138, 113, 'k', 'B', 0, true); set(139, 113, 'k', 'B', 0, true);
        set(137, 111, 'C', 'B', 0, true); set(140, 111, 'C', 'B', 0, true);
        add_zone(135, 109, 142, 117, "通济钱庄");

        // 11. 福兴杂货铺 — Classic MUD General Store south of East Street (131..141, 122..129)
        build_story_box(131, 122, 141, 129, 0, 'H', 'H');
        place_door(136, 122, 136, 121, 0, 'H');
        place_windows_h(122, 133, 139, 2, 0, 'H');
        set(133, 125, 'K', 'H', 0, true); set(133, 127, 'K', 'H', 0, true);
        set(139, 125, 'C', 'H', 0, true); set(139, 127, 'a', 'H', 0, true);
        set(136, 126, 'k', 'H', 0, true);
        add_zone(131, 122, 141, 129, "福兴杂货铺");

        // 12. 春风茶馆 — Dongguan waterside storytelling teahouse (173..182, 122..130)
        build_story_box(173, 122, 182, 130, 0, 'H', 'H');
        place_door(177, 122, 177, 121, 0, 'H');
        place_door(173, 126, 172, 126, 0, 'H');
        place_windows_h(122, 175, 180, 2, 0, 'H');
        place_windows_v(173, 124, 128, 2, 0, 'H');
        set(177, 125, 'l', 'H', 0, true);
        set(178, 126, 'i', 'H', 0, true); // 说书先生 @ (178, 126)
        build_table_set(176, 128, 0, 'H');
        build_table_set(180, 128, 0, 'H');
        set(180, 124, 'h', 'H', 0, true);
        add_zone(173, 122, 182, 130, "春风茶馆");

        // 13. 水埠码头 — Xiaoqinhuai River east-bank cargo wharf (161..170, 162..170)
        reserve_open_area(161, 162, 170, 170);
        fill(164, 162, 170, 170, ':', 'p', 0, false);
        fill(161, 164, 164, 168, '=', '=', 0, false);
        set(166, 163, 'C', 'p', 0, false); set(168, 163, 'C', 'p', 0, false);
        set(166, 169, 'a', 'p', 0, false); set(165, 165, 'L', 'p', 0, false);
        set(167, 166, ':', 'p', 0, false); // 老船夫 @ (167, 166)
        add_zone(161, 162, 170, 170, "水埠码头");

        // --- WEST STREET (西市大街: 扬威武馆, 镇远镖局) ---

        // 14. 扬威武馆 — Martial Hall + stone courtyard south of West Street (97..107, 122..131)
        reserve_open_area(97, 122, 102, 131);
        fill(97, 122, 102, 131, '+', 'p', 0, false);
        fill(97, 122, 97, 131, '#', 'B', 0, false);
        fill(97, 131, 102, 131, '#', 'B', 0, false);
        for (int x = 98; x <= 102; ++x) set(x, 122, (x >= 99 && x <= 101) ? '+' : '#', 'B', 0, false);
        set(98, 124, 'k', 'p', 0, false); set(98, 129, 'k', 'p', 0, false);
        set(100, 126, '+', 'p', 0, false); // 陈馆主 @ (100, 126)
        build_story_box(103, 122, 107, 131, 0, 'N', 'N');
        place_door(103, 126, 102, 126, 0, 'N');
        set(105, 124, 'r', 'N', 0, true); set(105, 128, 'l', 'N', 0, true);
        add_zone(97, 122, 107, 131, "扬威武馆");

        // 15. 镇远镖局 — Classic MUD Escort Agency north of West Street (97..106, 108..117)
        build_story_box(97, 108, 106, 117, 0, 'B', 'B');
        place_door(101, 117, 101, 118, 0, 'B');
        place_windows_h(117, 99, 104, 2, 0, 'B');
        set(99, 110, 'C', 'B', 0, true); set(104, 110, 'C', 'B', 0, true);
        set(101, 112, 'l', 'B', 0, true); set(103, 114, 'k', 'B', 0, true);
        add_zone(97, 108, 106, 117, "镇远镖局");
    }

    // -----------------------------------------------------------------------
    // STREET-FIRST HOUSE PLACER (HARD INVARIANT: ZERO DOORS FACING WALLS!)
    // Finds a valid committed road_mask landing tile on one of the 4 walls;
    // refuses to build if no street-facing door exists!
    // -----------------------------------------------------------------------
    bool find_street_door(int x0, int y0, int x1, int y1, int seq,
                          int &out_dx, int &out_dy, int &out_ox, int &out_oy) const {
        const int mx = (x0 + x1) / 2;
        const int my = (y0 + y1) / 2;
        struct SideCand { int dx, dy, ox, oy; };
        std::vector<SideCand> cands;
        cands.reserve(16);
        auto push_if = [&](int dx, int dy, int ox, int oy) {
            if (is_valid_door_landing(ox, oy)) cands.push_back({dx, dy, ox, oy});
        };
        // Prefer centered doors, then ±1 along the wall (never corners!)
        for (int off : {0, -1, 1}) {
            if (mx + off > x0 && mx + off < x1) {
                push_if(mx + off, y1, mx + off, y1 + 1); // South
                push_if(mx + off, y0, mx + off, y0 - 1); // North
            }
            if (my + off > y0 && my + off < y1) {
                push_if(x0, my + off, x0 - 1, my + off); // West
                push_if(x1, my + off, x1 + 1, my + off); // East
            }
        }
        if (cands.empty()) return false;
        const SideCand &pick = cands[static_cast<std::size_t>(seq % static_cast<int>(cands.size()))];
        out_dx = pick.dx; out_dy = pick.dy;
        out_ox = pick.ox; out_oy = pick.oy;
        return true;
    }

    bool place_street_house(int x0, int y0, int w, int h, int seq, const char *zone_name) {
        const int x1 = x0 + w - 1;
        const int y1 = y0 + h - 1;
        if (!area_is_clear_for_house(x0, y0, x1, y1)) return false;

        int dx = 0, dy = 0, ox = 0, oy = 0;
        if (!find_street_door(x0, y0, x1, y1, seq, dx, dy, ox, oy)) {
            return false; // NEVER place a blind/dead-door house!
        }

        const char style = pick_contrasting_style(x0, y0, x1, y1, seq);
        build_story_box(x0, y0, x1, y1, 0, style, style);
        place_door(dx, dy, ox, oy, 0, style);

        // Wooden lattice windows facing EVERY nearby water tile AND street edge!
        add_waterside_windows(x0, y0, x1, y1, 0, style);
        if (dy == y1) place_windows_h(y1, x0 + 1, x1 - 1, 2, 0, style);
        if (dy == y0) place_windows_h(y0, x0 + 1, x1 - 1, 2, 0, style);
        if (dx == x0) place_windows_v(x0, y0 + 1, y1 - 1, 2, 0, style);
        if (dx == x1) place_windows_v(x1, y0 + 1, y1 - 1, 2, 0, style);

        // Compute interior tile right behind the door so furniture NEVER blocks entry!
        const int in_x = dx + (dx - ox);
        const int in_y = dy + (dy - oy);
        auto place_furn = [&](int fx, int fy, char ch) {
            if ((fx == in_x && fy == in_y) || get_tile(fx, fy, 0) != 'i') return;
            set(fx, fy, ch, style, 0, true);
        };

        if (w >= 5 && h >= 5) {
            place_furn(x0 + 1, y0 + 1, (seq % 2 == 0) ? 'b' : 'k');
            place_furn(x1 - 1, y0 + 1, (seq % 3 == 0) ? 'h' : 'c');
            place_furn((x0 + x1) / 2, (y0 + y1) / 2, 't');
            place_furn(x0 + 1, y1 - 1, (seq % 2 == 0) ? 'a' : 'u');
        } else {
            place_furn(x0 + 1, y0 + 1, 'b');
            place_furn(x1 - 1, y1 - 1, 'c');
        }

        // Occasional 2nd story on larger waterfront/main-street homes for stepped skyline
        if (w >= 6 && h >= 6 && (det_hash(x0, y0, 91) % 4 == 0)) {
            const int sx = (x0 + 1 == in_x && y0 + 2 == in_y) ? (x1 - 1) : (x0 + 1);
            const int sy = y0 + 2;
            if (sx > x0 && sx < x1 && sy > y0 && sy < y1) {
                set(sx, sy, '^', style, 0, true);
                build_story_box(x0 + 1, y0 + 1, x1 - 1, y1 - 1, 1, style, style);
                add_waterside_windows(x0 + 1, y0 + 1, x1 - 1, y1 - 1, 1, style);
                set(sx, sy, 'v', style, 1, true);
            }
        }
        add_zone(x0, y0, x1, y1, zone_name);
        return true;
    }

    const char *district_zone_for(int x, int y) const {
        if (x >= 146 && y < 118) return "仁丰里民居";
        if (x >= 146 && y >= 122) return "东关水巷民居";
        if (x < 116 && y < 146) return "西市坊民居";
        if (x < 116 && y >= 146) return "南水弄民居";
        if (y < 105) return "府前坊民居";
        return "中街坊民居";
    }

    // -----------------------------------------------------------------------
    // STAGE 4A: STEPPED RIVER-HUGGING HOUSES (枕河而建 + 必有合法街门!)
    // Anchors cottages flush along curved riverbanks ONLY where a committed
    // towpath or fishbone alley serves their door (so 0 doors ever face walls!).
    // -----------------------------------------------------------------------
    void build_river_hugging_houses() {
        int seq = 0;
        const int dirs[8][2] = {{0,-1},{0,1},{-1,0},{1,0},{-1,-1},{1,-1},{-1,1},{1,1}};
        const int sizes[9][2] = {{6,5},{5,6},{7,5},{5,7},{6,6},{5,5},{4,5},{5,4},{4,4}};

        for (const Vector2i rp : all_river_pts) {
            for (int d = 0; d < 8; ++d) {
                int bx = rp.x, by = rp.y;
                bool found_bank = false;
                for (int step = 1; step <= 8; ++step) {
                    const int tx = rp.x + dirs[d][0] * step;
                    const int ty = rp.y + dirs[d][1] * step;
                    if (!valid(tx, ty)) break;
                    if (!water_mask[idx(tx, ty)] && !road_mask[idx(tx, ty)]) {
                        bx = tx;
                        by = ty;
                        found_bank = true;
                        break;
                    }
                }
                if (!found_bank) continue;
                const int h = det_hash(bx, by, seq);
                for (int attempt = 0; attempt < 5; ++attempt) {
                    const int si = (attempt < 2) ? ((h + attempt) % 6) : (6 + ((h + attempt) % 3));
                    const int sw = sizes[si][0];
                    const int sh = sizes[si][1];
                    const int x0 = (dirs[d][0] < 0) ? (bx - sw + 1) : (dirs[d][0] > 0 ? bx : (bx - sw / 2));
                    const int y0 = (dirs[d][1] < 0) ? (by - sh + 1) : (dirs[d][1] > 0 ? by : (by - sh / 2));
                    if (place_street_house(x0, y0, sw, sh, seq, "枕河水巷民居")) {
                        ++seq;
                        break;
                    }
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // STAGE 4B: STRICT STREET-FRONT & FISHBONE-ALLEY ROW-HOUSE PACKING
    // Walks every committed road_mask edge (North, South, West, East) and packs
    // dense wall-to-wall varied Jiangnan houses (7x6 down to 4x4) with 100% of
    // doors opening onto streets & alleys!
    // -----------------------------------------------------------------------
    void pack_street_front_houses() {
        int seq = 300;
        const int sizes_ew[8][2] = {{7,6},{6,6},{6,5},{5,6},{7,5},{5,5},{4,5},{4,4}};
        const int sizes_ns[8][2] = {{6,7},{6,6},{5,6},{6,5},{5,7},{5,5},{5,4},{4,4}};

        // Pass 1 (Medium & Large Street-Front Homes) + Pass 2 (Compact 4x5/5x4/4x4 Infill)
        for (int pass = 0; pass < 2; ++pass) {
            for (int y = 26; y <= 212; ++y) {
                for (int x = 26; x <= 212; ++x) {
                    if (!is_valid_door_landing(x, y)) continue;
                    const int h = det_hash(x, y, pass * 131 + seq);
                    const char *zname = district_zone_for(x, y);

                    // Try anchoring flush to the SOUTH of a street tile (house north edge = y+1)
                    if (valid(x, y + 1) && !road_mask[idx(x, y + 1)] && !water_mask[idx(x, y + 1)] && !data.enclosed[0][idx(x, y + 1)]) {
                        const int s0 = (pass == 0) ? (h % 5) : (5 + (h % 3));
                        for (int k = 0; k < 3; ++k) {
                            const int si = (s0 + k) % 8;
                            const int sw = sizes_ew[si][0], sh = sizes_ew[si][1];
                            if (place_street_house(x, y + 1, sw, sh, seq, zname)) { ++seq; break; }
                            if (place_street_house(x - sw + 1, y + 1, sw, sh, seq, zname)) { ++seq; break; }
                        }
                    }
                    // Try anchoring flush to the NORTH of a street tile (house south edge = y-1)
                    if (valid(x, y - 1) && !road_mask[idx(x, y - 1)] && !water_mask[idx(x, y - 1)] && !data.enclosed[0][idx(x, y - 1)]) {
                        const int s0 = (pass == 0) ? ((h >> 3) % 5) : (5 + ((h >> 3) % 3));
                        for (int k = 0; k < 3; ++k) {
                            const int si = (s0 + k) % 8;
                            const int sw = sizes_ew[si][0], sh = sizes_ew[si][1];
                            if (place_street_house(x, y - sh, sw, sh, seq, zname)) { ++seq; break; }
                            if (place_street_house(x - sw + 1, y - sh, sw, sh, seq, zname)) { ++seq; break; }
                        }
                    }
                    // Try anchoring flush to the EAST of a street tile (house west edge = x+1)
                    if (valid(x + 1, y) && !road_mask[idx(x + 1, y)] && !water_mask[idx(x + 1, y)] && !data.enclosed[0][idx(x + 1, y)]) {
                        const int s0 = (pass == 0) ? ((h >> 6) % 5) : (5 + ((h >> 6) % 3));
                        for (int k = 0; k < 3; ++k) {
                            const int si = (s0 + k) % 8;
                            const int sw = sizes_ns[si][0], sh = sizes_ns[si][1];
                            if (place_street_house(x + 1, y, sw, sh, seq, zname)) { ++seq; break; }
                            if (place_street_house(x + 1, y - sh + 1, sw, sh, seq, zname)) { ++seq; break; }
                        }
                    }
                    // Try anchoring flush to the WEST of a street tile (house east edge = x-1)
                    if (valid(x - 1, y) && !road_mask[idx(x - 1, y)] && !water_mask[idx(x - 1, y)] && !data.enclosed[0][idx(x - 1, y)]) {
                        const int s0 = (pass == 0) ? ((h >> 9) % 5) : (5 + ((h >> 9) % 3));
                        for (int k = 0; k < 3; ++k) {
                            const int si = (s0 + k) % 8;
                            const int sw = sizes_ns[si][0], sh = sizes_ns[si][1];
                            if (place_street_house(x - sw, y, sw, sh, seq, zname)) { ++seq; break; }
                            if (place_street_house(x - sw, y - sh + 1, sw, sh, seq, zname)) { ++seq; break; }
                        }
                    }
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // STAGE 5: YANGZHOU POCKET COURTYARD GARDENS & LIVED-IN ALLEY DETAILS
    // Turns any tiny unbuilt pocket into charming willow/well/flower courtyards
    // while strictly respecting door_apron_mask & road_mask!
    // -----------------------------------------------------------------------
    void build_courtyard_pockets_and_details() {
        for (int y = 27; y <= 212; ++y) {
            for (int x = 27; x <= 212; ++x) {
                if (x < 94 && y < 78) continue;
                const std::size_t i = idx(x, y);
                if (water_mask[i] || road_mask[i] || door_apron_mask[i] || data.enclosed[0][i]) continue;
                if (get_tile(x, y, 0) != ':') continue;
                // Only place details where all 4 neighbors are clear of doors!
                bool near_door = false;
                for (const Vector2i st : steps) {
                    if (valid(x + st.x, y + st.y) && get_tile(x + st.x, y + st.y, 0) == 'D') {
                        near_door = true;
                        break;
                    }
                }
                if (near_door) continue;
                const int h = det_hash(x, y, 57);
                const bool near_water =
                    (valid(x, y - 1) && water_mask[idx(x, y - 1)]) ||
                    (valid(x, y + 1) && water_mask[idx(x, y + 1)]) ||
                    (valid(x - 1, y) && water_mask[idx(x - 1, y)]) ||
                    (valid(x + 1, y) && water_mask[idx(x + 1, y)]);
                if (near_water) {
                    // Natural grassy/willow riverbank edging along curved canals
                    if (h % 9 == 0) set(x, y, 'Y', '\0', 0, false);
                    else if (h % 9 == 3) set(x, y, 'g', '\0', 0, false);
                    else set(x, y, '.', '\0', 0, false);
                } else {
                    // Clean bluestone courtyard pockets with sparse trees, shrubs & rainwater vats (NO benches!)
                    if (h % 29 == 0) set(x, y, 'Y', 'p', 0, false);
                    else if (h % 23 == 4) set(x, y, 'g', 'p', 0, false);
                    else if (h % 31 == 9) set(x, y, 'P', 'p', 0, false);
                    else if (h % 37 == 2) set(x, y, 'a', 'p', 0, false);
                }
            }
        }
        // Subtle riverside lanterns on main towpath (NEVER on door_apron_mask!)
        for (int y = 26; y <= 213; ++y) {
            for (int x = 26; x <= 213; ++x) {
                const std::size_t i = idx(x, y);
                if (!road_mask[i] || door_apron_mask[i] || water_mask[i] || get_tile(x, y, 0) != ':') continue;
                const bool s_w = valid(x, y + 1) && water_mask[idx(x, y + 1)] && !creek_mask[idx(x, y + 1)];
                const bool e_w = valid(x + 1, y) && water_mask[idx(x + 1, y)] && !creek_mask[idx(x + 1, y)];
                if ((s_w || e_w) && ((x * 13 + y * 29) % 19 == 0)) {
                    bool near_door = false;
                    for (const Vector2i st : steps)
                        if (valid(x + st.x, y + st.y) && get_tile(x + st.x, y + st.y, 0) == 'D') near_door = true;
                    if (!near_door) set(x, y, 'L', 'p', 0, false);
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // STAGE 6: POST-BUILD DOOR TOPOLOGY VALIDATOR (ZERO DOOR-AGAINST-WALL!)
    // Ensures every single 'D' across 240x240 has passable opposite sides
    // (either N+S or E+W) and NEVER opens into a wall or water!
    // -----------------------------------------------------------------------
    void validate_and_heal_doors() {
        auto is_pass = [&](int x, int y) -> bool {
            if (!valid(x, y)) return false;
            const char t = get_tile(x, y, 0);
            return passable_tile(t) && t != 'W' && t != '~';
        };
        for (int y = 1; y < city_size - 1; ++y) {
            for (int x = 1; x < city_size - 1; ++x) {
                if (get_tile(x, y, 0) != 'D') continue;
                const bool ns_ok = is_pass(x, y - 1) && is_pass(x, y + 1);
                const bool ew_ok = is_pass(x - 1, y) && is_pass(x + 1, y);
                if (!ns_ok && !ew_ok) {
                    // Convert any stray invalid door cleanly back into wall so 0 dead doors exist
                    set(x, y, '#', data.surfaces[0][idx(x, y)], 0, data.enclosed[0][idx(x, y)] != 0);
                }
            }
        }
    }

    YangzhouWorldData finish() {
        build_moat_and_walls();
        build_waterways_streets_and_fishbones();
        build_classic_wuxia_landmarks();
        build_river_hugging_houses();
        pack_street_front_houses();
        build_courtyard_pockets_and_details();
        validate_and_heal_doors();

        set(start_tile.x, start_tile.y, '+', 'm', 0, false);
        for (const auto &npc : kYangzhouNpcs) {
            const char cur = get_tile(npc.pos.x, npc.pos.y, 0);
            if (cur == '#' || cur == 'W' || cur == '~' || cur == 'w') {
                set(npc.pos.x, npc.pos.y, 'i', 'H', 0, true);
            }
        }
        return std::move(data);
    }
};

} // namespace

const YangzhouWorldData &yangzhou_world_data() {
    static const YangzhouWorldData world = Builder().finish();
    return world;
}

const NpcDef *npc_at_tile(Vector2i p) {
    for (const auto &npc : kYangzhouNpcs) {
        if (npc.pos == p) return &npc;
    }
    return nullptr;
}

bool is_npc_tile(Vector2i p) {
    return npc_at_tile(p) != nullptr;
}

} // namespace cangling
