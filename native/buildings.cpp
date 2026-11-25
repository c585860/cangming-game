#include "city.hpp"
#include <algorithm>
#include <string_view>

namespace cangling {
namespace {
using Kit = std::string_view;
using Rooms = std::array<Kit, 8>;
constexpr Kit kitchen = "huckc", dining = "tqqqcu", living = "tqklaq", storage = "ccCCrcC",
              bedroom = "bblrq", study = "lktqC", wash = "aukq", reception = "tqqrcl",
              shop = "Cctqrrc", clinic = "bbuCkq", workshop = "ktCkrc", forge = "hhkruC",
              classroom = "tqtqtql", library = "rrrktq", shrine = "laqqkt";

Rooms room_plan(Kit kind) {
    if (kind == "客栈") return {reception,kitchen,dining,storage,bedroom,bedroom,bedroom,wash};
    if (kind == "药铺" || kind == "医馆") return {shop,clinic,storage,workshop,bedroom,study,bedroom,wash};
    if (kind == "工坊") return {workshop,forge,storage,shop,storage,study,bedroom,wash};
    if (kind == "仓房") return {storage,storage,storage,reception,storage,storage,study,wash};
    if (kind == "书院") return {classroom,library,reception,study,library,bedroom,study,wash};
    if (kind == "巡检所") return {reception,storage,study,dining,bedroom,bedroom,study,wash};
    if (kind == "商铺") return {shop,shop,storage,workshop,bedroom,study,bedroom,wash};
    if (kind == "吐纳院") return {shrine,shrine,study,reception,shrine,bedroom,study,wash};
    return {kitchen,dining,living,storage,bedroom,bedroom,study,wash};
}

void put(Tiles &tiles, Vector2i p, char tile) { tile_ref(tiles, p.x, p.y) = tile; }

void furnish(Tiles &tiles, Vector2i base, const Rect2i &room, Kit pieces, std::mt19937 &rng) {
    std::vector<Vector2i> spots;
    const auto end = room.get_end();
    for (int x = room.position.x + 1; x < end.x - 1; ++x) {
        spots.emplace_back(x, room.position.y);
        spots.emplace_back(x, end.y - 1);
    }
    for (int y = room.position.y; y < end.y; ++y) {
        spots.emplace_back(room.position.x == 1 ? room.position.x : end.x - 1, y);
    }
    for (char piece : pieces) {
        if (spots.empty()) break;
        const auto i = random_int(rng, 0, static_cast<int>(spots.size()) - 1);
        put(tiles, base + spots[i], piece);
        spots[i] = spots.back();
        spots.pop_back();
    }
}

void open_plot(Block &block, Vector2i origin, Kit kind, std::mt19937 &rng) {
    if (kind == "空地") return;
    for (int y = 2; y < 22; ++y) {
        for (int x = 2; x < 22; ++x) {
            if (tile_ref(block.ground_surface,origin.x+x,origin.y+y)) continue;
            char tile = '.';
            if (kind == "街市" || kind == "广场" || kind == "吐纳庭") {
                tile = '+';
                if (kind == "街市" && x % 5 == 0 && y % 6 == 0 && (x < 10 || x > 14)) {
                    tile = random_int(rng, 0, 1) ? 't' : 'C';
                }
            } else if (x == 11 || x == 12 || y == 11 || y == 12) {
                tile = ':';
            } else if (x % 4 == 0 && y % 4 == 0 && random_int(rng, 0, 4) != 0) {
                tile = 'g';
            }
            put(block.ground, origin + Vector2i(x, y), tile);
        }
    }
}
}

void build_plot(Block &block, Vector2i origin, const char *name, std::mt19937 &rng) {
    const Kit kind{name};
    if (kind == "空地" || kind == "广场" || kind == "街市" || kind == "公园" || kind == "果圃" || kind == "吐纳庭") {
        open_plot(block, origin, kind, rng);
        block.plots.push_back({Rect2i(origin, {24,24}), name});
        return;
    }
    const int width = random_int(rng, 16, 21);
    const int depth = random_int(rng, 14, 18);
    const int hall = random_int(rng, width / 2 - 1, width / 2 + 1);
    const int split = random_int(rng, 5, depth - 6);
    const bool north = random_int(rng, 0, 1) == 0;
    const Vector2i base = origin + Vector2i((24 - width) / 2, north ? 22 - depth : 2);
    const Vector2i stair = base + Vector2i(hall, random_int(rng, 3, depth - 4));
    const auto roles = room_plan(kind);
    const std::array<Rect2i, 4> rooms{{{1,1,hall-2,split-1}, {hall+2,1,width-hall-3,split-1},
        {1,split+1,hall-2,depth-split-2},{hall+2,split+1,width-hall-3,depth-split-2}}};
    for (int z = 0; z < 3; ++z) {
        Tiles &tiles = level_tiles(block, z);
        for (int y = 0; y < depth; ++y) {
            for (int x = 0; x < width; ++x) {
                char cell = 'i';
                if (y == 0 || y == depth - 1 || x == 0 || x == width - 1) {
                    const bool corner = (y == 0 || y == depth - 1) && (x == 0 || x == width - 1);
                    cell = !corner && (x * 7 + y * 3 + z * 2) % 9 == 2 ? 'w' : '#';
                } else if (x == hall - 1 || x == hall + 1 || (y == split && std::abs(x-hall) > 1)) {
                    cell = '#';
                }
                const auto p = base + Vector2i(x,y);
                put(tiles, p, cell);
                mark_enclosed_story(block, z, p);
            }
        }
        for (int side : {-1, 1}) {
            put(tiles, base + Vector2i(hall + side, random_int(rng, 2, split-2)), 'D');
            put(tiles, base + Vector2i(hall + side, random_int(rng, split+2, depth-3)), 'D');
        }
        put(tiles, stair, z == 0 ? '^' : z == 2 ? 'v' : 'X');
        for (int room = 0; room < 4; ++room) {
            const int role_index = (z * 4 + room + (north ? 2 : 0)) % static_cast<int>(roles.size());
            furnish(tiles, base, rooms[room], roles[role_index], rng);
        }
    }
    const Vector2i entry = base + Vector2i(hall, north ? 0 : depth - 1);
    put(block.ground, entry, 'D');
    const int gate_y = origin.y + (north ? 0 : 22);
    for (int y = std::min(entry.y, gate_y); y <= std::max(entry.y, gate_y); ++y) {
        if (y != entry.y) put(block.ground, {entry.x,y}, ':');
    }
    if (kind == "住宅" || kind == "吐纳院") {
        if (kind == "吐纳院" || random_int(rng, 0, 4) != 0) {
            for (int x = base.x; x < base.x + width; ++x) {
                put(block.ground, {x,gate_y}, x == entry.x ? 'D' : 'f');
            }
            for (int y = std::min(entry.y, gate_y) + 1; y < std::max(entry.y, gate_y); ++y) {
                put(block.ground, {base.x,y}, 'f');
                put(block.ground, {base.x+width-1,y}, 'f');
                if (std::abs(y-gate_y) % 2 == 1) {
                    put(block.ground, {base.x+2,y}, random_int(rng,0,1) ? 'g' : 'a');
                    put(block.ground, {base.x+width-3,y}, 'g');
                }
            }
        }
    }
    block.plots.push_back({Rect2i(origin,{24,23}), name});
}
}
