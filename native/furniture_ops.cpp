#include "world.hpp"
#include <godot_cpp/variant/variant.hpp>
#include <algorithm>
#include <cmath>
#include <string_view>
#include <vector>

namespace cangling {
using namespace godot;

namespace {
constexpr std::string_view kMovableFurniture = "qStlCcaubkKrP";
constexpr std::string_view kOpenableContainers = "cCFKr";
constexpr std::string_view kClimbableTiles = "fO%tlk";
constexpr std::string_view kSmashableTiles = "wODofbqStlkKcFrCauPg";
constexpr std::string_view kFloorForFurniture = "i.:+=";
constexpr std::string_view kHaulFloorTiles = "i.:+=os";

const char *furniture_label(char tile) {
    switch (tile) {
        case 'q': return "坐凳";
        case 'S': return "长椅";
        case 't': return "木桌";
        case 'l': return "书案";
        case 'C': return "货箱";
        case 'c': return "木柜";
        case 'a': return "陶缸";
        case 'u': return "水盆";
        case 'b': return "床榻";
        case 'k': return "长案";
        case 'K': return "展柜";
        case 'r': return "书架";
        case 'P': return "盆栽";
        case 'F': return "衣柜";
        case 'D': case 'o': return "木门";
        case 'w': case 'O': return "雕花木窗";
        case '%': return "残破木窗";
        case 'f': return "木篱";
        case 'h': return "青砖土灶";
        case 'g': return "花木";
        case '#': return "砖墙";
        case 'Y': return "行道树";
        case 'L': return "宫灯柱";
        case '^': return "上行楼梯";
        case 'v': return "下行楼梯";
        case 'X': return "上下楼梯";
        default: return "物件";
    }
}

const char *direction_name(int dx, int dy) {
    if (dx == 0 && dy == 0) return "脚下";
    const int sx = (dx > 0) ? 1 : (dx < 0 ? -1 : 0);
    const int sy = (dy > 0) ? 1 : (dy < 0 ? -1 : 0);
    if (sx == 0 && sy < 0) return "北";
    if (sx > 0 && sy < 0) return "东北";
    if (sx > 0 && sy == 0) return "东";
    if (sx > 0 && sy > 0) return "东南";
    if (sx == 0 && sy > 0) return "南";
    if (sx < 0 && sy > 0) return "西南";
    if (sx < 0 && sy == 0) return "西";
    return "西北";
}

int octant_index(int dx, int dy) {
    // 0=NW, 1=N, 2=NE, 3=W, 4=E, 5=SW, 6=S, 7=SE
    const double angle = std::atan2(static_cast<double>(dy), static_cast<double>(dx));
    // angle: 0=E, pi/2=S, pi/-pi=W, -pi/2=N
    const double deg = angle * 180.0 / 3.14159265358979323846;
    if (deg >= -157.5 && deg < -112.5) return 0; // NW
    if (deg >= -112.5 && deg < -67.5) return 1;  // N
    if (deg >= -67.5 && deg < -22.5) return 2;   // NE
    if (deg >= -22.5 && deg < 22.5) return 4;    // E
    if (deg >= 22.5 && deg < 67.5) return 7;     // SE
    if (deg >= 67.5 && deg < 112.5) return 6;    // S
    if (deg >= 112.5 && deg < 157.5) return 5;   // SW
    return 3;                                    // W
}

int smash_threshold(char tile) {
    switch (tile) {
        case 'w': case 'O': return 8;
        case 'a': case 'u': case 'P': case 'g': return 12;
        case 'q': case 'S': case 't': case 'l': return 14;
        case 'f': return 16;
        case 'b': case 'c': case 'C': case 'k': case 'K': case 'F': case 'r': return 20;
        case 'D': case 'o': return 22;
        default: return 999;
    }
}
} // namespace

bool CanglingWorld::is_movable_furniture(char tile) {
    return kMovableFurniture.find(tile) != std::string_view::npos;
}

bool CanglingWorld::is_openable_container(char tile) {
    return kOpenableContainers.find(tile) != std::string_view::npos;
}

bool CanglingWorld::is_climbable_tile(char tile) {
    return kClimbableTiles.find(tile) != std::string_view::npos;
}

bool CanglingWorld::is_smashable_tile(char tile) {
    return kSmashableTiles.find(tile) != std::string_view::npos;
}

char CanglingWorld::effective_tile(Vector2i p, int z) {
    if (!in_city(p)) return ' ';
    const int64_t k = key(p, z);
    char tile = '\0';
    if (const auto it = tile_overrides.find(k); it != tile_overrides.end()) {
        tile = it->second;
    } else {
        tile = city.tile(p, z);
    }
    if ((tile == 'D' || tile == 'w') && doors.count(k)) {
        tile = (tile == 'D') ? 'o' : 'O';
    }
    return tile;
}

bool CanglingWorld::is_container_open(Vector2i p) const {
    return open_containers.count(key(p, floor)) != 0;
}

String CanglingWorld::open_at(Vector2i p) {
    if (!in_city(p) || !near(p)) return {};
    const int64_t k = key(p, floor);
    const char raw = effective_tile(p, floor);
    if (raw == 'D') {
        doors.insert(k);
        char_state.last_sound = 6;
        return String::utf8("你打开了门。");
    }
    if (raw == 'w') {
        doors.insert(k);
        char_state.last_sound = 5;
        return String::utf8("你推开了雕花木窗。");
    }
    if (is_openable_container(raw)) {
        if (open_containers.count(k)) {
            return String::utf8(furniture_label(raw)) + String::utf8("已经是打开状态。");
        }
        open_containers.insert(k);
        char_state.last_sound = 4;
        const String contents = fixture_contents(p);
        if (contents.is_empty()) {
            return String::utf8("你打开了") + String::utf8(furniture_label(raw)) + String::utf8("，里面空空如也。");
        }
        return String::utf8("你打开了") + String::utf8(furniture_label(raw)) + String::utf8("，里面放着：") + contents + String::utf8("。");
    }
    return {};
}

String CanglingWorld::close_at(Vector2i p) {
    if (!in_city(p) || !near(p)) return {};
    const int64_t k = key(p, floor);
    const char cur = effective_tile(p, floor);
    if (cur == 'o' && p != pos) {
        doors.erase(k);
        char_state.last_sound = 8;
        return String::utf8("你关上了门。");
    }
    if (cur == 'O' && p != pos) {
        doors.erase(k);
        char_state.last_sound = 5;
        return String::utf8("你关上了窗户。");
    }
    if (is_openable_container(cur)) {
        if (!open_containers.erase(k)) {
            return String::utf8(furniture_label(cur)) + String::utf8("本来就是关着的。");
        }
        char_state.last_sound = 4;
        return String::utf8("你合上了") + String::utf8(furniture_label(cur)) + String::utf8("。");
    }
    return {};
}

String CanglingWorld::smash_at(Vector2i p) {
    if (!in_city(p) || !near(p) || p == pos) {
        return String::utf8("只能砸击紧邻身旁的物件。");
    }
    const int64_t k = key(p, floor);
    const char tile = effective_tile(p, floor);
    if (tile == '%') {
        return String::utf8("这扇木窗已被砸毁，可以直接翻越过去。");
    }
    if (!is_smashable_tile(tile)) {
        if (tile == '#' || tile == 'h' || tile == 'Y' || tile == 'L') {
            char_state.spend_stamina(350);
            char_state.last_sound = 18;
            return String::utf8("你猛力砸向") + String::utf8(furniture_label(tile)) + String::utf8("，但它过于坚固，纹丝不动。(声响 18)");
        }
        return String::utf8("那个方向没有可以砸碎的物件。");
    }

    const int power = char_state.bash_power();
    const int req = smash_threshold(tile);
    char_state.spend_stamina(420);
    int &dmg = bash_damage[k];
    dmg += power;

    if (dmg < req) {
        char_state.last_sound = 20;
        return String::utf8("你用力砸向") + String::utf8(furniture_label(tile)) +
               String::utf8("，木石作响却尚未彻底砸毁（再砸一次，或手持手斧/撬棍更省力）。(声响 20)");
    }

    // Destroyed! Materialize any container/surface loot first so everything spills onto the floor.
    bash_damage.erase(k);
    if (grab_offset != Vector2i(0, 0) && pos + grab_offset == p) {
        grab_offset = {0, 0};
    }
    materialize_tile_items(p);
    doors.erase(k);
    open_containers.erase(k);

    const bool is_win = (tile == 'w' || tile == 'O');
    const bool is_door = (tile == 'D' || tile == 'o');
    const bool is_ceramic = (tile == 'a' || tile == 'u' || tile == 'P');
    const bool indoor = (city.lighting_column(p, floor, 1) & 1) != 0;
    tile_overrides[k] = is_win ? '%' : (indoor ? 'i' : '.');

    const int id_plank = find_item_by_key("wood_plank");
    const int id_rag = find_item_by_key("cloth_rag");
    const int id_shard = find_item_by_key("ceramic_shard");
    auto &pile = stored_items[k];
    if (is_win) {
        if (id_plank >= 0) pile[id_plank] = std::min(999, pile[id_plank] + 1);
    } else if (is_door) {
        if (id_plank >= 0) pile[id_plank] = std::min(999, pile[id_plank] + 2);
    } else if (is_ceramic) {
        vessel_water.erase(k);
        if (id_shard >= 0) pile[id_shard] = std::min(999, pile[id_shard] + (tile == 'P' ? 1 : 2));
    } else if (tile == 'f' || tile == 'q' || tile == 'S' || tile == 't' || tile == 'l') {
        if (id_plank >= 0) pile[id_plank] = std::min(999, pile[id_plank] + 1);
    } else if (tile == 'b') {
        if (id_plank >= 0) pile[id_plank] = std::min(999, pile[id_plank] + 2);
        if (id_rag >= 0) pile[id_rag] = std::min(999, pile[id_rag] + 1);
    } else if (tile != 'g') {
        if (id_plank >= 0) pile[id_plank] = std::min(999, pile[id_plank] + 2);
    }

    const int snd = is_door ? 34 : (is_win ? 28 : (tile == 'f' ? 24 : 28));
    char_state.last_sound = snd;
    if (is_win) {
        return String::utf8("你用力砸碎了雕花木窗，木棂崩裂飞溅！(声响 ") + String::num_int64(snd) + String::utf8(")");
    }
    if (is_door) {
        return String::utf8("你一举砸烂了木门，碎木板散落一地！(声响 ") + String::num_int64(snd) + String::utf8(")");
    }
    if (tile == 'f') {
        return String::utf8("你砸断了木篱，开出一道缺口！(声响 ") + String::num_int64(snd) + String::utf8(")");
    }
    if (is_ceramic) {
        return String::utf8("你砸碎了") + String::utf8(furniture_label(tile)) + String::utf8("，碎瓷片撒了一地！(声响 ") + String::num_int64(snd) + String::utf8(")");
    }
    return String::utf8("你砸毁了") + String::utf8(furniture_label(tile)) + String::utf8("，内里物品与碎木板散落满地！(声响 ") + String::num_int64(snd) + String::utf8(")");
}

String CanglingWorld::climb_at(Vector2i p) {
    if (!in_city(p) || !near(p) || p == pos) {
        return String::utf8("只能翻越紧邻身旁的障碍。");
    }
    const char tile = effective_tile(p, floor);
    if (tile == 'w') {
        return String::utf8("雕花木窗目前关着，请先按 o 推开或按 s 砸碎再翻越。");
    }
    if (!is_climbable_tile(tile)) {
        return String::utf8("那里无法攀爬翻越。");
    }

    const Vector2i delta = p - pos;
    const Vector2i beyond = p + delta;
    Vector2i landing = pos;
    if (walkable(beyond)) {
        landing = beyond;
    } else if (tile == 'O' || tile == '%') {
        landing = p;
    } else {
        // Check adjacent walkable tiles around the climbed obstacle away from origin
        static const std::array<Vector2i, 4> dirs{{{0,-1},{-1,0},{1,0},{0,1}}};
        int best_dist = -1;
        for (const auto d : dirs) {
            const Vector2i cand = p + d;
            if (cand == pos || !walkable(cand)) continue;
            const int dist = (cand - pos).length_squared();
            if (dist > best_dist) {
                best_dist = dist;
                landing = cand;
            }
        }
    }
    if (landing == pos) {
        return String::utf8("另一侧空间受阻，没有落脚之处，无法翻越。");
    }

    grab_offset = {0, 0};
    char_state.hauling = false;
    char_state.spend_stamina(240);
    char_state.last_sound = 10;
    pos = landing;
    if (tile == 'f') return String::utf8("你手脚并用翻过了木篱。");
    if (tile == '%') return String::utf8("你避开尖锐的残木，翻越了破碎的木窗。");
    if (tile == 'O') return String::utf8("你利落地翻过了雕花木窗。");
    return String::utf8("你撑身跃过了") + String::utf8(furniture_label(tile)) + String::utf8("。");
}

void CanglingWorld::haul_items_from(Vector2i from, Vector2i to) {
    if (from == to || !in_city(from) || !in_city(to)) return;
    const char from_tile = effective_tile(from, floor);
    if (kHaulFloorTiles.find(from_tile) == std::string_view::npos) return;
    const ItemCounts pile = items_on(from);
    bool has_any = false;
    for (int n : pile) {
        if (n > 0) { has_any = true; break; }
    }
    if (!has_any) return;

    materialize_tile_items(from);
    materialize_tile_items(to);
    const int64_t kf = key(from, floor);
    const int64_t kt = key(to, floor);
    auto it = stored_items.find(kf);
    if (it == stored_items.end()) return;
    auto &dest = stored_items[kt];
    for (int i = 0; i < item_types; ++i) {
        dest[i] = std::min(999, dest[i] + it->second[i]);
    }
    stored_items.erase(it);
    char_state.spend_stamina(60);
    char_state.last_sound = std::max(char_state.last_sound, 8);
}

String CanglingWorld::grab_furniture(Vector2i target) {
    if (!in_city(target) || !near(target) || target == pos) {
        return String::utf8("只能抓取紧邻身旁的家具。");
    }
    const char tile = effective_tile(target, floor);
    if (!is_movable_furniture(tile)) {
        return String::utf8("这里没有可以拖拽移动的家具。");
    }
    char_state.hauling = false;
    grab_offset = target - pos;
    return String::utf8("你抓住了") + String::utf8(furniture_label(tile)) + String::utf8("（移动即可推拉，再按 G 松手）。");
}

String CanglingWorld::release_grab() {
    if (grab_offset == Vector2i(0, 0)) return {};
    const Vector2i target = pos + grab_offset;
    const char tile = effective_tile(target, floor);
    grab_offset = {0, 0};
    return String::utf8("你松开了") + String::utf8(furniture_label(tile)) + String::utf8("。");
}

bool CanglingWorld::move_grabbed_furniture(Vector2i next_player_pos) {
    const Vector2i furn_from = pos + grab_offset;
    const Vector2i furn_to = next_player_pos + grab_offset;
    const char furn_tile = effective_tile(furn_from, floor);
    if (!is_movable_furniture(furn_tile)) {
        grab_offset = {0, 0};
        return false;
    }

    const bool pulling_into_player = (furn_to == pos);
    if (!pulling_into_player) {
        if (!in_city(furn_to)) return false;
        if (floor == 0 && is_npc_tile(furn_to)) return false;
        const char dest_tile = effective_tile(furn_to, floor);
        if (kFloorForFurniture.find(dest_tile) == std::string_view::npos) {
            return false;
        }
    }

    const bool pushing_from_next = (next_player_pos == furn_from);
    if (!pushing_from_next && !walkable(next_player_pos)) {
        return false;
    }

    const int64_t k_from = key(furn_from, floor);
    const int64_t k_to = key(furn_to, floor);
    const ItemCounts moving_items = items_on(furn_from);
    collected_props.insert(k_from);
    stored_items.erase(k_from);

    const ItemCounts dest_items = items_on(furn_to);
    collected_props.insert(k_to);
    ItemCounts merged = dest_items;
    bool has_any = false;
    for (int i = 0; i < item_types; ++i) {
        merged[i] = std::min(999, merged[i] + moving_items[i]);
        if (merged[i] > 0) has_any = true;
    }
    if (has_any) stored_items[k_to] = merged;
    else stored_items.erase(k_to);

    if (const auto wit = vessel_water.find(k_from); wit != vessel_water.end()) {
        const int ml = wit->second;
        vessel_water.erase(wit);
        vessel_water[k_to] = ml;
    } else if (furn_tile == 'a' || furn_tile == 'u') {
        const int default_ml = (furn_tile == 'a') ? (5000 * 3 / 4) : (1600 * 3 / 4);
        vessel_water[k_to] = default_ml;
    }

    if (open_containers.erase(k_from)) {
        open_containers.insert(k_to);
    }

    const bool indoor_from = (city.lighting_column(furn_from, floor, 1) & 1) != 0;
    tile_overrides[k_from] = indoor_from ? 'i' : '.';
    tile_overrides[k_to] = furn_tile;

    pos = next_player_pos;
    char_state.spend_stamina(180);
    char_state.last_sound = 12;
    return true;
}

Array CanglingWorld::list_nearby(int radius) {
    Array result;
    const int r = std::clamp(radius, 1, 18);
    struct Entry {
        int dist_sq;
        Dictionary data;
    };
    std::vector<Entry> rows;
    rows.reserve(64);
    const auto &cat = item_catalog();

    for (int dy = -r; dy <= r; ++dy) {
        for (int dx = -r; dx <= r; ++dx) {
            const Vector2i p = pos + Vector2i(dx, dy);
            if (!in_city(p)) continue;
            const int d2 = dx * dx + dy * dy;
            const int dist = std::max(std::abs(dx), std::abs(dy));
            const char tile = effective_tile(p, floor);
            const String dir = String::utf8(direction_name(dx, dy));

            // 1. Visible items (skip closed opaque containers)
            if (!is_openable_container(tile) || is_container_open(p) || tile == 'r') {
                const ItemCounts counts = items_on(p);
                for (int i = 0; i < item_types; ++i) {
                    if (counts[i] <= 0) continue;
                    Dictionary row;
                    row["kind"] = "item";
                    row["item_id"] = i;
                    row["name"] = String::utf8(cat[i].name);
                    row["category"] = String::utf8(category_label(cat[i].category));
                    row["count"] = counts[i];
                    row["pos"] = p;
                    row["dx"] = dx;
                    row["dy"] = dy;
                    row["dist"] = dist;
                    row["dir"] = dir;
                    row["tile_label"] = String::utf8(furniture_label(tile));
                    rows.push_back({d2, row});
                }
            }

            // 2. Notable landmarks / interactive furniture / Yangzhou NPCs
            String tname;
            if (floor == 0) {
                if (const NpcDef *npc = npc_at_tile(p)) {
                    tname = String::utf8(npc->name) + String::utf8(" · ") + String::utf8(npc->title);
                }
            }
            if (tname.is_empty() && (tile == '^' || tile == 'v' || tile == 'X' || tile == 'h' || tile == 'a' ||
                     tile == 'u' || tile == 'b' || tile == 'F' || tile == 'c' || tile == 'r' ||
                     tile == 'K' || tile == 'C' || tile == '%')) {
                tname = String::utf8(furniture_label(tile));
            }
            if (!tname.is_empty()) {
                Dictionary row;
                row["kind"] = "terrain";
                row["name"] = tname;
                row["pos"] = p;
                row["dx"] = dx;
                row["dy"] = dy;
                row["dist"] = dist;
                row["dir"] = dir;
                row["tile"] = String::chr(tile);
                rows.push_back({d2 + 1, row});
            }
        }
    }

    std::sort(rows.begin(), rows.end(), [](const Entry &a, const Entry &b) {
        return a.dist_sq < b.dist_sq;
    });

    const int limit = std::min<int>(static_cast<int>(rows.size()), 90);
    for (int i = 0; i < limit; ++i) {
        result.append(rows[i].data);
    }
    return result;
}

Array CanglingWorld::compass_summary() {
    // CCB 8-direction compass: 0=NW, 1=N, 2=NE, 3=W, 4=E, 5=SW, 6=S, 7=SE
    static constexpr const char *kOctNames[8] = {"NW", "N ", "NE", "W ", "E ", "SW", "S ", "SE"};
    std::array<int, 8> best_dist;
    best_dist.fill(999);
    std::array<String, 8> best_label;
    std::array<int, 8> best_prio{};

    constexpr int r = 9;
    const Rect2i scan = Rect2i(pos - Vector2i(r, r), Vector2i(r * 2 + 1, r * 2 + 1))
        .intersection(Rect2i(0, 0, city_size, city_size));
    const SectorGridSnapshot snap = city.snapshot_sectors(scan);
    for (int dy = -r; dy <= r; ++dy) {
        for (int dx = -r; dx <= r; ++dx) {
            if (dx == 0 && dy == 0) continue;
            const Vector2i p = pos + Vector2i(dx, dy);
            if (!in_city(p)) continue;
            const int oct = octant_index(dx, dy);
            const int dist = std::max(std::abs(dx), std::abs(dy));
            const int64_t k = key(p, floor);
            char tile = ' ';
            if (!tile_overrides.empty()) {
                if (const auto ov = tile_overrides.find(k); ov != tile_overrides.end()) tile = ov->second;
            }
            if (tile == ' ') {
                const int sx = p.x / sector_size;
                const int sy = p.y / sector_size;
                if (const Block *blk = snap.at(sx, sy)) {
                    tile = level_tiles(*blk, floor)[(p.y - sy * sector_size) * sector_size + (p.x - sx * sector_size)];
                }
            }
            if ((tile == 'D' || tile == 'w') && !doors.empty() && doors.count(k)) {
                tile = (tile == 'D') ? 'o' : 'O';
            }
            int prio = 0;
            String label;
            if (floor == 0) {
                if (const NpcDef *npc = npc_at_tile(p)) {
                    prio = 5;
                    label = String::utf8(npc->name);
                }
            }
            if (prio == 0) {
                if (tile == '^' || tile == 'v' || tile == 'X') { prio = 3; label = String::utf8("楼梯"); }
                else if (tile == 'h') { prio = 3; label = String::utf8("炉灶"); }
                else if (tile == 'b') { prio = 2; label = String::utf8("床榻"); }
                else if (tile == 'F' || tile == 'c' || tile == 'r') { prio = 2; label = String::utf8(furniture_label(tile)); }
                else if (tile == 'D' || tile == 'o') { prio = 1; label = String::utf8("木门"); }
                else if (tile == 'a' || tile == 'u') { prio = 2; label = String::utf8(furniture_label(tile)); }
                else if (tile == 'W' || tile == '~') { prio = 1; label = String::utf8("河水"); }
                else if (tile == '=') { prio = 2; label = String::utf8("石桥"); }
            }

            if (prio > 0 && (prio > best_prio[oct] || (prio == best_prio[oct] && dist < best_dist[oct]))) {
                best_prio[oct] = prio;
                best_dist[oct] = dist;
                best_label[oct] = label;
            }
        }
    }

    Array out;
    for (int i = 0; i < 8; ++i) {
        Dictionary d;
        d["dir"] = String::utf8(kOctNames[i]);
        d["label"] = best_label[i];
        d["dist"] = best_prio[i] > 0 ? best_dist[i] : 0;
        out.append(d);
    }
    return out;
}

} // namespace cangling
