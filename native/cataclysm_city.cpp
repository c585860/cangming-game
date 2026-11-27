#include "city.hpp"
#include "core_packs.hpp"
#include "monsters.hpp"
#include <algorithm>
#include <cmath>
#include <mutex>

namespace cangling {
namespace {

// ---------------------------------------------------------------------------
// Cataclysm: Cleanwater Bomb (CCB) Core Pack — 240 x 240 New England Town
// Deterministic per-seed generator with:
//   * Emergency Evacuation Shelter start at (120, 200) (safe zone radius >= 18)
//   * Asphalt arterial roads ('+' surface 'm'), concrete sidewalks (':' surface 'p'),
//     streetlamps ('L'), northern river ('W'/'~') & concrete highway bridges ('=')
//   * Iconic CCB POIs: Evac Shelter, Grocery Store, Pharmacy, Hardware Store,
//     Police Station, Public Library, Clinic, Gas Station, Central Park & Suburbs
//   * Strict door_apron_mask + validate_and_heal_doors() => ZERO bad doors!
//   * Deterministic CCB monster spawns across town streets, stores & suburbs.
// ---------------------------------------------------------------------------

struct CataclysmBuilder {
    CataclysmWorldData data;
    std::vector<std::uint8_t> water_mask;
    std::vector<std::uint8_t> road_mask;
    std::vector<std::uint8_t> door_apron_mask;
    std::uint32_t seed = 0;

    explicit CataclysmBuilder(std::uint32_t s) : seed(s) {
        const std::size_t n = static_cast<std::size_t>(city_size * city_size);
        for (int z = 0; z < 3; ++z) {
            data.tiles[z].assign(n, z == 0 ? '.' : ' ');
            data.surfaces[z].assign(n, '\0');
            data.enclosed[z].assign(n, 0);
        }
        water_mask.assign(n, 0);
        road_mask.assign(n, 0);
        door_apron_mask.assign(n, 0);
        data.spawn_tile = {120, 200};
    }

    static bool valid(int x, int y) {
        return x >= 0 && y >= 0 && x < city_size && y < city_size;
    }

    static std::size_t idx(int x, int y) {
        return static_cast<std::size_t>(y * city_size + x);
    }

    int hash(int x, int y, int salt = 0) const {
        std::uint32_t n = static_cast<std::uint32_t>(x) * 374761393u +
                          static_cast<std::uint32_t>(y) * 668265263u +
                          (seed ^ static_cast<std::uint32_t>(salt)) * 1442695041u;
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

    void add_zone(int x0, int y0, int x1, int y1, const char *name) {
        data.zones.push_back({Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1), name});
    }

    void pave_asphalt(int x0, int y0, int x1, int y1) {
        for (int y = y0; y <= y1; ++y) {
            for (int x = x0; x <= x1; ++x) {
                if (!valid(x, y)) continue;
                const std::size_t i = idx(x, y);
                if (water_mask[i]) {
                    set(x, y, '=', 'm', 0, false);
                } else {
                    set(x, y, '+', 'm', 0, false);
                }
                road_mask[i] = 1;
            }
        }
    }

    void pave_sidewalk(int x0, int y0, int x1, int y1) {
        for (int y = y0; y <= y1; ++y) {
            for (int x = x0; x <= x1; ++x) {
                if (!valid(x, y)) continue;
                const std::size_t i = idx(x, y);
                if (water_mask[i]) continue;
                if (data.tiles[0][i] == '+' || data.tiles[0][i] == '=') continue;
                set(x, y, ':', 'p', 0, false);
                road_mask[i] = 1;
            }
        }
    }

    void carve_north_river() {
        for (int x = 0; x < city_size; ++x) {
            const double wave = std::sin(static_cast<double>(x) * 0.045 + static_cast<double>(seed % 17)) * 4.5;
            const int cy = 28 + static_cast<int>(std::round(wave));
            for (int dy = -4; dy <= 4; ++dy) {
                const int y = cy + dy;
                if (!valid(x, y)) continue;
                const char wt = (std::abs(dy) <= 2) ? 'W' : '~';
                set(x, y, wt, '\0', 0, false);
                water_mask[idx(x, y)] = 1;
            }
        }
        add_zone(0, 20, city_size - 1, 36, "清溪河道 (Clearwater River)");
    }

    void build_road_grid() {
        // Primary North-South Avenues (Main St terminates cleanly at Shelter Rd facing Evac Shelter!)
        const int ns_roads[] = {65, 118, 171};
        for (int rx : ns_roads) {
            const int end_y = (rx == 118) ? 193 : 228;
            pave_asphalt(rx, 8, rx + 3, end_y);
            pave_sidewalk(rx - 1, 10, rx - 1, end_y + 1);
            pave_sidewalk(rx + 4, 10, rx + 4, end_y + 1);
        }

        // Primary East-West Streets
        const int ew_roads[] = {52, 100, 148, 190};
        for (int ry : ew_roads) {
            pave_asphalt(12, ry, 228, ry + 3);
            pave_sidewalk(12, ry - 1, 228, ry - 1);
            pave_sidewalk(12, ry + 4, 228, ry + 4);
        }

        // Secondary residential connector streets
        const int sub_ns[] = {36, 92, 146, 200};
        for (int rx : sub_ns) {
            pave_asphalt(rx, 52, rx + 1, 193);
            pave_sidewalk(rx - 1, 52, rx - 1, 193);
            pave_sidewalk(rx + 2, 52, rx + 2, 193);
        }

        add_zone(117, 36, 122, 224, "主干大道 (Main St)");
        add_zone(64, 36, 69, 224, "西林大道 (West Blvd)");
        add_zone(170, 36, 175, 224, "东城大道 (East Blvd)");
        add_zone(12, 100, 228, 105, "中央大街 (Central Ave)");
        add_zone(12, 148, 228, 153, "橡树街 (Oak St)");
        add_zone(12, 190, 228, 194, "避难所大道 (Shelter Rd)");

        // Streetlamps along sidewalks (respecting intersections)
        for (int rx : ns_roads) {
            for (int y = 44; y <= 216; y += 16) {
                if (valid(rx - 1, y) && get_tile(rx - 1, y) == ':' && !door_apron_mask[idx(rx - 1, y)]) {
                    set(rx - 1, y, 'L', 'p', 0, false);
                }
                if (valid(rx + 4, y + 8) && get_tile(rx + 4, y + 8) == ':' && !door_apron_mask[idx(rx + 4, y + 8)]) {
                    set(rx + 4, y + 8, 'L', 'p', 0, false);
                }
            }
        }
    }

    bool area_free(int x0, int y0, int x1, int y1) const {
        if (x0 < 14 || y0 < 40 || x1 > 224 || y1 > 224) return false;
        for (int y = y0; y <= y1; ++y) {
            for (int x = x0; x <= x1; ++x) {
                const std::size_t i = idx(x, y);
                if (water_mask[i] || road_mask[i] || data.enclosed[0][i] || door_apron_mask[i]) return false;
            }
        }
        return true;
    }

    // Build a clean modern building with guaranteed street-facing entrance & door apron!
    void build_modern_building(
        int x0, int y0, int x1, int y1,
        const char *name,
        char door_side, // 'N', 'S', 'W', 'E'
        int door_coord,
        char floor_surface,
        bool two_story = false) {
        if (x1 - x0 < 5 || y1 - y0 < 5) return;

        // Clear perimeter & construct walls + interior concrete/wood floor
        fill(x0, y0, x1, y1, 'i', floor_surface, 0, true);
        for (int x = x0; x <= x1; ++x) {
            set(x, y0, '#', floor_surface, 0, true);
            set(x, y1, '#', floor_surface, 0, true);
        }
        for (int y = y0; y <= y1; ++y) {
            set(x0, y, '#', floor_surface, 0, true);
            set(x1, y, '#', floor_surface, 0, true);
        }

        // Windows along outer walls
        for (int x = x0 + 2; x <= x1 - 2; x += 3) {
            set(x, y0, 'w', floor_surface, 0, true);
            set(x, y1, 'w', floor_surface, 0, true);
        }
        for (int y = y0 + 2; y <= y1 - 2; y += 3) {
            set(x0, y, 'w', floor_surface, 0, true);
            set(x1, y, 'w', floor_surface, 0, true);
        }

        // Front door + clean sidewalk walkway apron connecting to nearest street!
        int dx = (x0 + x1) / 2, dy = y0;
        int out_x = dx, out_y = dy - 1;
        int in_x = dx, in_y = dy + 1;
        if (door_side == 'N') {
            dx = std::clamp(door_coord, x0 + 2, x1 - 2);
            dy = y0; out_x = dx; out_y = y0 - 1; in_x = dx; in_y = y0 + 1;
        } else if (door_side == 'S') {
            dx = std::clamp(door_coord, x0 + 2, x1 - 2);
            dy = y1; out_x = dx; out_y = y1 + 1; in_x = dx; in_y = y1 - 1;
        } else if (door_side == 'W') {
            dx = x0; dy = std::clamp(door_coord, y0 + 2, y1 - 2);
            out_x = x0 - 1; out_y = dy; in_x = x0 + 1; in_y = dy;
        } else {
            dx = x1; dy = std::clamp(door_coord, y0 + 2, y1 - 2);
            out_x = x1 + 1; out_y = dy; in_x = x1 - 1; in_y = dy;
        }

        set(dx, dy, 'D', floor_surface, 0, true);
        set(in_x, in_y, 'i', floor_surface, 0, true);
        door_apron_mask[idx(in_x, in_y)] = 1;

        // Pave exterior concrete walkway from door straight out until it hits road_mask (max 6 tiles)
        int wx = out_x, wy = out_y;
        const int step_x = out_x - dx;
        const int step_y = out_y - dy;
        for (int k = 0; k < 6 && valid(wx, wy); ++k) {
            const std::size_t wi = idx(wx, wy);
            if (water_mask[wi] || data.enclosed[0][wi]) break;
            if (!road_mask[wi] || get_tile(wx, wy) == 'L') {
                set(wx, wy, ':', 'p', 0, false);
                road_mask[wi] = 1;
            }
            door_apron_mask[wi] = 1;
            wx += step_x;
            wy += step_y;
            if (valid(wx, wy) && road_mask[idx(wx, wy)] && get_tile(wx, wy) == '+') break;
        }

        if (two_story) {
            fill(x0, y0, x1, y1, 'i', 'i', 1, true);
            for (int x = x0; x <= x1; ++x) {
                set(x, y0, '#', 'i', 1, true);
                set(x, y1, '#', 'i', 1, true);
            }
            for (int y = y0; y <= y1; ++y) {
                set(x0, y, '#', 'i', 1, true);
                set(x1, y, '#', 'i', 1, true);
            }
            for (int x = x0 + 2; x <= x1 - 2; x += 3) {
                set(x, y0, 'w', 'i', 1, true);
                set(x, y1, 'w', 'i', 1, true);
            }
            // Safe interior stairs away from door
            const int sx = (door_side == 'W') ? (x1 - 2) : (x0 + 2);
            const int sy = (door_side == 'N') ? (y1 - 2) : (y0 + 2);
            set(sx, sy, '^', floor_surface, 0, true);
            set(sx, sy, 'v', 'i', 1, true);
            set(x0 + 2, y0 + 2, 'b', 'i', 1, true);
            set(x1 - 2, y0 + 2, 'F', 'i', 1, true);
            set((x0 + x1) / 2, (y0 + y1) / 2, 't', 'i', 1, true);
        }

        add_zone(x0, y0, x1, y1, name);
    }

    void build_evac_shelter() {
        // Emergency Evacuation Shelter just south of Shelter Rd (y=190..194)
        const int x0 = 113, y0 = 196, x1 = 127, y1 = 206;
        build_modern_building(x0, y0, x1, y1, "应急避难所 (Evac Shelter)", 'N', 120, 'i', true);

        // Shelter interior layout: benches, supply lockers, computer console, crates, water sink
        for (int x = x0 + 2; x <= x0 + 5; ++x) set(x, y0 + 2, 'F', 'i', 0, true);
        for (int x = x1 - 5; x <= x1 - 2; ++x) set(x, y0 + 2, 'C', 'i', 0, true);
        set(x0 + 2, y0 + 5, 'S', 'i', 0, true);
        set(x0 + 3, y0 + 5, 'S', 'i', 0, true);
        set(x1 - 2, y0 + 5, 'S', 'i', 0, true);
        set(x1 - 3, y0 + 5, 'S', 'i', 0, true);
        set(120, y0 + 7, 'l', 'i', 0, true); // Evac shelter terminal desk
        set(x1 - 2, y1 - 2, 'u', 'i', 0, true);
        set(x1 - 3, y1 - 2, 'h', 'i', 0, true);

        // Clean guaranteed walkable spawn tile inside shelter hall
        set(120, 200, 'i', 'i', 0, true);
        set(120, 199, 'i', 'i', 0, true);
        set(120, 198, 'i', 'i', 0, true);
        set(120, 197, 'i', 'i', 0, true);
        data.spawn_tile = {120, 200};
    }

    void build_iconic_pois() {
        // 1. Grocery Store (城镇超市) — SE of Oak St & Main St
        build_modern_building(124, 156, 142, 172, "城镇超市 (Grocery Store)", 'N', 133, 'i', false);
        for (int x = 127; x <= 139; x += 3) {
            for (int y = 160; y <= 169; y += 2) set(x, y, 'r', 'i', 0, true);
        }
        set(126, 158, 'k', 'i', 0, true);
        set(127, 158, 'k', 'i', 0, true);
        set(139, 158, 'C', 'i', 0, true);
        set(140, 170, 'F', 'i', 0, true);

        // 2. Pharmacy (社区药房) — SW of Oak St & Main St
        build_modern_building(97, 156, 114, 169, "社区药房 (Pharmacy)", 'N', 105, 'i', false);
        for (int x = 100; x <= 111; x += 3) {
            set(x, 161, 'K', 'i', 0, true);
            set(x, 164, 'K', 'i', 0, true);
        }
        set(99, 167, 'k', 'i', 0, true);
        set(100, 167, 'k', 'i', 0, true);
        set(112, 167, 'u', 'i', 0, true);
        set(112, 159, 'F', 'i', 0, true);

        // 3. Hardware Store (五金工具店) — SE of Central Ave & Main St
        build_modern_building(124, 108, 142, 124, "五金工具店 (Hardware Store)", 'N', 133, 'i', false);
        for (int x = 127; x <= 139; x += 3) {
            set(x, 113, 'r', 'i', 0, true);
            set(x, 117, 'C', 'i', 0, true);
            set(x, 121, 't', 'i', 0, true);
        }
        set(126, 110, 'k', 'i', 0, true);
        set(140, 110, 'F', 'i', 0, true);

        // 4. Police Station (城镇警局) — SW of Central Ave & Main St
        build_modern_building(97, 108, 114, 124, "城镇警局 (Police Station)", 'N', 105, 'i', true);
        set(100, 111, 'k', 'i', 0, true);
        set(101, 111, 'k', 'i', 0, true);
        set(109, 111, 'l', 'i', 0, true);
        set(111, 111, 'F', 'i', 0, true);
        set(112, 111, 'F', 'i', 0, true);
        for (int x = 99; x <= 112; ++x) {
            if (x != 105) set(x, 117, 'f', 'i', 0, true); // Security bars / cells
        }
        set(100, 121, 'b', 'i', 0, true);
        set(111, 121, 'b', 'i', 0, true);

        // 5. Public Library (市立图书馆) — SE of North Ave & Main St
        build_modern_building(124, 58, 142, 74, "市立图书馆 (Public Library)", 'N', 133, 'i', true);
        for (int x = 127; x <= 139; x += 3) {
            for (int y = 62; y <= 70; y += 2) set(x, y, 'r', 'i', 0, true);
        }
        set(127, 72, 't', 'i', 0, true);
        set(128, 72, 'q', 'i', 0, true);
        set(137, 72, 't', 'i', 0, true);
        set(138, 72, 'q', 'i', 0, true);

        // 6. Clinic (街区诊所) — SW of North Ave & Main St
        build_modern_building(97, 58, 114, 74, "街区诊所 (Clinic)", 'N', 105, 'i', false);
        set(100, 62, 'b', 'i', 0, true);
        set(100, 66, 'b', 'i', 0, true);
        set(100, 70, 'b', 'i', 0, true);
        set(111, 62, 'K', 'i', 0, true);
        set(111, 66, 'u', 'i', 0, true);
        set(111, 70, 'F', 'i', 0, true);

        // 7. Gas Station (加油站便利店) — Oak St & West Blvd
        build_modern_building(72, 156, 88, 168, "加油站便利店 (Gas Station)", 'N', 80, 'i', false);
        set(75, 160, 'k', 'i', 0, true);
        set(76, 160, 'k', 'i', 0, true);
        set(84, 160, 'r', 'i', 0, true);
        set(84, 164, 'C', 'i', 0, true);
        set(75, 165, 'F', 'i', 0, true);

        // 8. Central Park (中央公园) — between West Blvd & Sub NS 92, Central Ave to Oak St
        add_zone(72, 108, 89, 144, "中央公园 (City Park)");
        for (int y = 110; y <= 142; ++y) set(80, y, ':', 'p', 0, false);
        for (int x = 72; x <= 89; ++x) set(x, 126, ':', 'p', 0, false);
        for (int y = 112; y <= 140; y += 6) {
            for (int x = 74; x <= 87; x += 6) {
                if (x == 80 || y == 126) continue;
                set(x, y, ((x + y) % 12 == 0) ? 'Y' : 'g', '\0', 0, false);
            }
        }
        set(79, 118, 'S', 'p', 0, false);
        set(81, 134, 'S', 'p', 0, false);
    }

    void furnish_suburban_house(int x0, int y0, int x1, int y1, int h) {
        // Living room sofa/table, bedroom bed/locker, kitchen stove/sink/counter
        const int mx = (x0 + x1) / 2;
        const int my = (y0 + y1) / 2;
        if (get_tile(x0 + 2, y0 + 2) == 'i' && !door_apron_mask[idx(x0 + 2, y0 + 2)]) set(x0 + 2, y0 + 2, 'b', 'i', 0, true);
        if (get_tile(x0 + 3, y0 + 2) == 'i' && !door_apron_mask[idx(x0 + 3, y0 + 2)]) set(x0 + 3, y0 + 2, 'F', 'i', 0, true);
        if (get_tile(x1 - 2, y0 + 2) == 'i' && !door_apron_mask[idx(x1 - 2, y0 + 2)]) set(x1 - 2, y0 + 2, 'h', 'i', 0, true);
        if (get_tile(x1 - 3, y0 + 2) == 'i' && !door_apron_mask[idx(x1 - 3, y0 + 2)]) set(x1 - 3, y0 + 2, 'u', 'i', 0, true);
        if (get_tile(mx, my) == 'i' && !door_apron_mask[idx(mx, my)]) set(mx, my, 't', 'i', 0, true);
        if (get_tile(mx + 1, my) == 'i' && !door_apron_mask[idx(mx + 1, my)]) set(mx + 1, my, 'q', 'i', 0, true);
        if (get_tile(x0 + 2, y1 - 2) == 'i' && !door_apron_mask[idx(x0 + 2, y1 - 2)]) set(x0 + 2, y1 - 2, 'S', 'i', 0, true);
        if (get_tile(x1 - 2, y1 - 2) == 'i' && !door_apron_mask[idx(x1 - 2, y1 - 2)]) {
            set(x1 - 2, y1 - 2, (h % 2 == 0) ? 'r' : 'k', 'i', 0, true);
        }
    }

    void build_suburbs() {
        // Place clean rows of suburban houses along street corridors with guaranteed street access
        struct LotRow { int x_start; int x_end; int y0; int y1; char door_side; };
        const LotRow rows[] = {
            // South of North Ave (y=52..57)
            {40, 60, 59, 68, 'N'},
            {72, 88, 59, 68, 'N'},
            {150, 167, 59, 68, 'N'},
            {178, 196, 59, 68, 'N'},
            {205, 222, 59, 68, 'N'},
            // North of Central Ave (y=100..105)
            {40, 60, 88, 97, 'S'},
            {72, 88, 88, 97, 'S'},
            {97, 114, 88, 97, 'S'},
            {124, 142, 88, 97, 'S'},
            {150, 167, 88, 97, 'S'},
            {178, 196, 88, 97, 'S'},
            // South of Central Ave (y=100..105)
            {40, 60, 108, 118, 'N'},
            {150, 167, 108, 118, 'N'},
            {178, 196, 108, 118, 'N'},
            {205, 222, 108, 118, 'N'},
            // North of Oak St (y=148..153)
            {40, 60, 136, 145, 'S'},
            {97, 114, 136, 145, 'S'},
            {124, 142, 136, 145, 'S'},
            {150, 167, 136, 145, 'S'},
            {178, 196, 136, 145, 'S'},
            // South of Oak St (y=148..153)
            {40, 60, 156, 166, 'N'},
            {150, 167, 156, 166, 'N'},
            {178, 196, 156, 166, 'N'},
            // North of Shelter Rd (y=190..194)
            {40, 60, 178, 187, 'S'},
            {72, 88, 178, 187, 'S'},
            {97, 114, 178, 187, 'S'},
            {124, 142, 178, 187, 'S'},
            {150, 167, 178, 187, 'S'},
            {178, 196, 178, 187, 'S'},
            // South of Shelter Rd (flanking Evac Shelter)
            {72, 104, 197, 206, 'N'},
            {134, 166, 197, 206, 'N'},
        };

        for (const auto &row : rows) {
            int x = row.x_start;
            while (x + 8 <= row.x_end) {
                const int h = hash(x, row.y0, 77);
                const int w = 8 + (h % 3); // 8..10
                const int x1 = std::min(x + w - 1, row.x_end);
                if (x1 - x >= 6 && area_free(x, row.y0, x1, row.y1)) {
                    const bool two_story = (h % 4 == 0);
                    build_modern_building(x, row.y0, x1, row.y1, "郊区民居 (Suburban House)",
                                          row.door_side, (x + x1) / 2, 'i', two_story);
                    furnish_suburban_house(x, row.y0, x1, row.y1, h);
                }
                x = x1 + 3;
            }
        }
    }

    void scatter_outer_trees() {
        for (int y = 40; y < 224; y += 3) {
            for (int x = 14; x < 224; x += 3) {
                const std::size_t i = idx(x, y);
                if (water_mask[i] || road_mask[i] || data.enclosed[0][i] || door_apron_mask[i]) continue;
                if (get_tile(x, y) != '.') continue;
                const int h = hash(x, y, 313);
                if ((h % 100) < 12) {
                    set(x, y, (h % 3 == 0) ? 'Y' : 'g', '\0', 0, false);
                }
            }
        }
    }

    void validate_and_heal_doors() {
        // Hard invariant: every 'D' tile must have >=1 passable exterior non-enclosed neighbor and >=1 passable interior neighbor
        static constexpr int kDx[4] = {0, 1, 0, -1};
        static constexpr int kDy[4] = {-1, 0, 1, 0};
        for (int y = 1; y < city_size - 1; ++y) {
            for (int x = 1; x < city_size - 1; ++x) {
                if (get_tile(x, y) != 'D') continue;
                bool has_ext = false, has_int = false;
                for (int d = 0; d < 4; ++d) {
                    const int nx = x + kDx[d], ny = y + kDy[d];
                    const char nt = get_tile(nx, ny);
                    if (!passable_tile(nt)) continue;
                    if (data.enclosed[0][idx(nx, ny)]) has_int = true;
                    else has_ext = true;
                }
                if (!has_ext || !has_int) {
                    set(x, y, '#', 'i', 0, true);
                }
            }
        }
    }

    void populate_monsters() {
        // Weighted authentic vanilla CCB monster IDs from monsters.json
        auto pick_species = [&](int x, int y, int h) -> std::string {
            if (x >= 94 && x <= 118 && y >= 104 && y <= 130 && (h % 3 == 0)) {
                return "mon_zombie_cop";
            }
            if (x >= 166 && x <= 198 && y >= 104 && y <= 146 && (h % 3 == 0)) {
                return "mon_zombie_hazmat";
            }
            const int r = h % 100;
            if (r < 38) return "mon_zombie";
            if (r < 54) return "mon_zombie_fat";
            if (r < 68) return "mon_zombie_runner";
            if (r < 80) return "mon_zombie_tough";
            if (r < 88) return "mon_zombie_cop";
            if (r < 94) return "mon_zombie_soldier";
            return "mon_dog_zombie_rot";
        };

        // 1. Guaranteed encounter squad north of Evac Shelter along Oak St / Main St (distance 22..48)
        const Vector2i guaranteed_pts[] = {
            {119, 174}, {121, 168}, {132, 152}, {106, 151}, {118, 146},
            {121, 134}, {105, 104}, {133, 104}, {82, 151}, {152, 151},
        };
        for (int k = 0; k < 10; ++k) {
            const Vector2i p = guaranteed_pts[k];
            if (valid(p.x, p.y) && passable_tile(get_tile(p.x, p.y))) {
                data.monster_spawns.push_back({pick_species(p.x, p.y, hash(p.x, p.y, 900 + k)), p, 0});
            }
        }

        // 2. Town-wide deterministic zombie distribution (strictly outside 18-tile safe radius of Evac Shelter!)
        for (int y = 44; y <= 216; y += 5) {
            for (int x = 36; x <= 216; x += 5) {
                const int cheb = std::max(std::abs(x - data.spawn_tile.x), std::abs(y - data.spawn_tile.y));
                if (cheb < 19) continue;
                const char t = get_tile(x, y);
                if (t != '+' && t != ':' && t != '.' && t != 'i') continue;
                const int h = hash(x, y, 521);
                const int chance = (t == '+' || t == ':') ? 9 : (t == 'i' ? 6 : 3);
                if ((h % 100) < chance) {
                    data.monster_spawns.push_back({pick_species(x, y, h), {x, y}, 0});
                    if (data.monster_spawns.size() >= 115) return;
                }
            }
        }
    }

    void add_radiation_zones() {
        // Authentic CCB radiation hazard zones (Toxic Waste Dump & Damaged Lab Vent)
        data.rad_zones.push_back({{182, 128}, 14, 24.0f, "核废料泄漏区 (Toxic Waste Dump)"});
        data.rad_zones.push_back({{120, 44}, 10, 16.0f, "地下实验室排气口 (Lab Vent)"});
        add_zone(170, 116, 194, 140, "核废料泄漏区 (辐射危险)");
    }

    CataclysmWorldData build() {
        carve_north_river();
        build_road_grid();
        build_evac_shelter();
        build_iconic_pois();
        build_suburbs();
        scatter_outer_trees();
        validate_and_heal_doors();
        add_radiation_zones();
        populate_monsters();
        return std::move(data);
    }
};

} // namespace

std::shared_ptr<const CataclysmWorldData> cataclysm_world_data(std::uint32_t seed) {
    static std::mutex mu;
    static std::uint32_t cached_seed = 0;
    static std::shared_ptr<const CataclysmWorldData> cached_ptr;
    std::lock_guard<std::mutex> lock(mu);
    if (cached_ptr && cached_seed == seed) {
        return cached_ptr;
    }
    CataclysmBuilder builder(seed);
    cached_ptr = std::make_shared<const CataclysmWorldData>(builder.build());
    cached_seed = seed;
    return cached_ptr;
}

} // namespace cangling
