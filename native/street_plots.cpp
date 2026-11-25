#include "city.hpp"
#include <algorithm>

namespace cangling {
namespace {
using Name = std::string_view;
enum class Use { hall, kitchen, bedroom, shop, store, study, bath, workshop };

struct Lot {
    Block &block;
    Vector2i origin;
    int facing;
    Vector2i at(int x, int y) const {
        switch (facing) {
            case 0: return origin + Vector2i(x,y);
            case 1: return origin + Vector2i(22-y,x);
            case 2: return origin + Vector2i(22-x,22-y);
            default: return origin + Vector2i(y,22-x);
        }
    }
    void put(int z, int x, int y, char tile, char surface) {
        const auto p = at(x,y);
        tile_ref(level_tiles(block,z),p.x,p.y) = tile;
        tile_ref(level_surfaces(block,z),p.x,p.y) = surface;
    }
    char grade(int x, int y) const {
        const auto p = at(x,y);
        return tile_ref(block.ground_surface,p.x,p.y);
    }
    char cell(int z, int x, int y) const {
        const auto p = at(x,y);
        return level_tiles(block,z)[p.y*sector_size+p.x];
    }
};

char floor_for(Use use) {
    if (use == Use::kitchen) return 'J';
    if (use == Use::bath || use == Use::workshop) return 'j';
    return use == Use::store ? 'd' : 'i';
}

// CCB-style rich lived-in room furnishing (40-55% density with guaranteed clear doorways & central walkway).
void furnish(Lot &lot, int z, Rect2i room, Use use, bool enters_from_left, int doorway, std::mt19937 &rng) {
    const int width = room.size.x, depth = room.size.y;
    const int aisle = width / 2;
    const int door_local = doorway - room.position.y;
    const char floor = floor_for(use);

    auto blocked_door = [&](int x, int y) -> bool {
        if (y == door_local && (x == 0 || x == 1)) return true;
        if (x == aisle && y == door_local) return true;
        return false;
    };
    auto put_raw = [&](int x, int y, char thing, char finish = 0, bool allow_aisle = false) {
        if (x < 0 || x >= width || y < 0 || y >= depth) return;
        if (thing != 'i') {
            if (blocked_door(x, y)) return;
            if (!allow_aisle && x == aisle) return;
        }
        const int gx = enters_from_left ? x : (width - 1 - x);
        const char current = lot.cell(z, room.position.x + gx, room.position.y + y);
        if (current == '#' || current == 'w' || current == 'D' || current == ' ' || current == '.') return;
        lot.put(z, room.position.x + gx, room.position.y + y, thing, finish ? finish : floor);
    };
    auto put = [&](int x, int y, char thing, char finish = 0) {
        put_raw(x, y, thing, finish, false);
    };
    auto put_rug = [&](int x0, int y0, int x1, int y1) {
        for (int y = std::max(0, y0); y <= std::min(depth - 1, y1); ++y) {
            for (int x = std::max(0, x0); x <= std::min(width - 1, x1); ++x) {
                const int gx = enters_from_left ? x : (width - 1 - x);
                const char cur = lot.cell(z, room.position.x + gx, room.position.y + y);
                if (cur == 'i') lot.put(z, room.position.x + gx, room.position.y + y, 'i', 'R');
            }
        }
    };

    for (int y = 0; y < depth; ++y) {
        for (int x = 0; x < width; ++x) put_raw(x, y, 'i', floor, true);
    }

    switch (use) {
        case Use::shop: {
            // Rich apothecary/merchant shop: rows of display cabinets, counters, ledger desk, crates & carpet
            for (int x = 0; x < width; ++x) {
                put(x, 0, x == width - 1 ? 'r' : 'K');
                if (depth >= 6) put(x, depth - 1, x == 0 ? 'c' : (x == width - 1 ? 'C' : 'K'));
            }
            for (int y = 2; y < depth - 1; y += 2) {
                put(width - 1, y, y % 4 == 0 ? 'C' : 'K');
            }
            if (width >= 5 && depth >= 5) {
                const int mid_y = depth / 2;
                put(width - 2, mid_y, 'k');
                put(width - 1, mid_y, 'k');
                put(width - 2, mid_y + 1, 'q');
                put(0, depth - 2, 'l');
                put(1, depth - 2, 'q');
            }
            put(0, 1, 'P');
            put_rug(aisle, 0, aisle, depth - 1);
            break;
        }
        case Use::kitchen: {
            // Rich CCB domestic kitchen: hearth + full L-shaped counter run + washstand + water vat + pantry + dining set
            put(0, 0, 'h');
            for (int x = 1; x < width - 1; ++x) put(x, 0, 'k');
            put(width - 1, 0, 'u');
            for (int y = 1; y < std::min(depth - 1, 4); ++y) {
                put(width - 1, y, y == 1 ? 'k' : (y == 2 ? 'a' : 'c'));
            }
            put(0, depth - 1, 'r');
            if (width >= 4) put(1, depth - 1, 'c');
            put(width - 1, depth - 1, 'C');
            // Dining table surrounded by stools/chairs
            if (depth >= 4 && width >= 4) {
                const int ty = std::max(2, depth - 2);
                const int tx = std::min(width - 2, std::max(1, width / 2));
                put_raw(tx, ty, 't', floor, true);
                if (tx + 1 < width - 1) put(tx + 1, ty, 't');
                put(tx - 1, ty, 'q');
                if (ty - 1 >= 1) put_raw(tx, ty - 1, 'q', floor, true);
                if (ty + 1 < depth) put_raw(tx, ty + 1, 'q', floor, true);
            }
            break;
        }
        case Use::bedroom: {
            // Rich CCB bedroom: 2-tile canopy bed, bedside table/lamp, wardrobe, dresser, study desk + chair, bench, bonsai & rug!
            const int back = door_local >= depth - 2 ? 0 : depth - 1;
            const int inward = back == 0 ? 1 : -1;
            const int front = depth - 1 - back;
            // 2-tile canopy bed against the far wall
            put(width - 1, back, 'b');
            put(width - 1, back + inward, 'b');
            // Bedside table + bench at foot of bed
            put(width - 2, back, 't');
            if (depth >= 4) put(width - 1, back + inward * 2, 'S');
            // Wardrobe & dresser along opposite wall
            put(0, back, 'F');
            put(0, back + inward, 'c');
            if (width >= 5) put(1, back, 'c');
            // Reading desk + armchair + bookshelf
            const int desk_y = std::clamp(depth / 2, 1, std::max(1, depth - 2));
            if (desk_y != door_local) {
                put(0, desk_y, 'l');
                put(1, desk_y, 'q');
            }
            put(width - 1, front, 'r');
            if (width >= 4) put(width - 2, front, 'P');
            if (width >= 4 && depth >= 4) {
                put_rug(1, std::min(back, back + inward), width - 2, std::max(back, back + inward));
            }
            break;
        }
        case Use::hall: {
            // Rich Jiangnan reception hall: benches, Eight-Immortals table + 4 chairs, curio cabinet, bookshelf, bonsai & silk carpet
            for (int x = 0; x < width; ++x) {
                put(x, 0, (x == 0 || x == width - 1) ? 'P' : 'S');
            }
            put(width - 1, 1, 'K');
            if (depth >= 4) put(width - 1, depth - 2, 'r');
            put(width - 1, depth - 1, 'c');
            if (width >= 4) put(0, depth - 1, 'S');
            if (width >= 5) put(1, depth - 1, 'S');
            if (depth >= 4 && width >= 4) {
                const int ty = depth / 2;
                const int tx = std::max(1, width - 2);
                put(tx, ty, 't');
                if (tx - 1 >= 1 && tx - 1 != aisle) put(tx - 1, ty, 't');
                put(tx, ty - 1, 'q');
                put(tx, ty + 1, 'q');
                if (tx - 1 >= 0 && tx - 1 != aisle) put(tx - 1, ty + 1, 'q');
            }
            put_rug(std::max(1, aisle - 1), 1, std::min(width - 2, aisle + 1), depth - 2);
            break;
        }
        case Use::study: {
            // Rich scholar's study: wall-to-wall bookshelves, twin scholar desk + armchair, curio cabinet, tea table, bonsai & rug
            for (int x = 0; x < width; ++x) put(x, 0, x == width - 1 ? 'K' : 'r');
            for (int y = 1; y < depth - 1; ++y) put(width - 1, y, (y % 3 == 0) ? 'c' : 'r');
            put(0, depth - 1, 'l');
            if (width >= 4) put(1, depth - 1, 'l');
            if (depth >= 3) put(1, depth - 2, 'q');
            put(width - 1, depth - 1, 'P');
            if (depth >= 5 && width >= 4) {
                put(width - 2, 2, 't');
                put(width - 2, 3, 'q');
                put(0, 1, 'S');
            }
            put_rug(1, 1, std::max(1, width - 2), std::max(1, depth - 2));
            break;
        }
        case Use::bath: {
            // Rich washroom: porcelain washstand, twin water vats, linen wardrobe, towel cabinet, stool & bonsai
            put(0, 0, 'u');
            put(width - 1, 0, 'a');
            if (depth >= 3) put(width - 1, 1, 'a');
            put(0, depth - 1, 'c');
            put(width - 1, depth - 1, 'F');
            if (width >= 4) put(1, 0, 'q');
            if (width >= 4 && depth >= 3) put(width - 2, depth - 1, 'P');
            break;
        }
        case Use::store:
        case Use::workshop: {
            // Rich storeroom / artisan workshop: workbenches, cargo chests, racks, forge hearth, quenching vat & tool cabinets
            for (int x = 0; x < width; ++x) {
                put(x, 0, (x % 3 == 0) ? 'c' : (use == Use::store ? 'C' : 'k'));
            }
            for (int y = 2; y < depth - 1; ++y) {
                if (y % 2 == 0) {
                    put(width - 1, y, use == Use::store ? 'C' : 'k');
                    put(0, y, 'r');
                } else if (width >= 5) {
                    put(width - 1, y, 'C');
                }
            }
            put(width - 1, depth - 1, use == Use::workshop ? 'h' : 'a');
            if (width >= 4) put(width - 2, depth - 1, use == Use::workshop ? 'a' : 'C');
            put(0, depth - 1, 'c');
            if (depth >= 4 && width >= 4) put(1, depth - 2, 'q');
            break;
        }
    }
    (void)rng;
}

std::array<Use,4> uses(Name name, int floor, bool alt) {
    using U = Use;
    if (floor != 0) {
        if (name == "客栈") return {U::bedroom,U::bedroom,U::bedroom,U::bath};
        if (name == "仓房" || name == "工坊") return {U::store,U::store,U::study,U::bath};
        if (name == "书院") return {U::study,U::bedroom,U::study,U::bedroom};
        return alt ? std::array{U::bedroom,U::bath,U::bedroom,U::study} : std::array{U::bedroom,U::study,U::bath,U::bedroom};
    }
    if (name == "商铺" || name == "药铺" || name == "医馆") return {U::shop,U::store,U::shop,U::study};
    if (name == "客栈") return {U::hall,U::store,U::kitchen,U::bath};
    if (name == "仓房") return {U::store,U::study,U::store,U::store};
    if (name == "工坊") return {U::workshop,U::store,U::shop,U::study};
    if (name == "书院" || name == "吐纳院" || name == "巡检所") return {U::hall,U::study,U::study,U::store};
    return alt ? std::array{U::kitchen,U::store,U::hall,U::bedroom} : std::array{U::hall,U::bedroom,U::kitchen,U::study};
}
}

void build_street_plot(Block &block, Vector2i origin, const char *kind, std::mt19937 &rng) {
    const Name name(kind);
    if (name == "空地" || name == "街市" || name == "广场" || name == "果圃" || name == "公园" || name == "吐纳庭") {
        build_plot(block,origin,kind,rng);
        return;
    }
    const bool domestic = name == "住宅" || name == "吐纳院";
    const bool shop = name == "商铺" || name == "药铺" || name == "医馆";
    const bool big = shop || name == "仓房" || name == "客栈" || name == "书院";
    const int style = random_int(rng,0,3);
    const int facing = random_int(rng,0,3);
    Lot lot{block,origin,facing};
    int width = random_int(rng,big ? 15 : 12,big ? 18 : 16);
    const int depth = random_int(rng,11,big ? 15 : 14);
    const int notch = style == 1 || style == 3 ? 3 : 0;
    const int cut = style == 3 ? 3 : 0;
    const int corridor = big && style != 1 ? 2 : 1;
    int left = (23-width)/2;
    int front = domestic ? random_int(rng,5,8) : random_int(rng,3,6);
    auto free = [&](int l, int f, int w) {
        for (int y = f; y < f+depth; ++y) {
            for (int x = l; x < l+w; ++x) {
                if (lot.grade(x,y)) return false;
            }
        }
        return true;
    };
    bool fits = false;
    for (; width >= 12 && !fits; --width) {
        for (int dy = 0; dy <= 11 && !fits; ++dy) {
            for (int dx = 0; dx <= 23-width; ++dx) {
                const int lx = (left+dx) % (24-width);
                const int fy = (front+dy) % (24-depth);
                if (fy < 2 || !free(lx,fy,width)) continue;
                left = lx; front = fy; fits = true; break;
            }
        }
        if (fits) break;
    }
    if (!fits) return;
    const int right = left+width-1, back = front+depth-1;
    const int hall = left+std::clamp(width/2+(style == 2 ? -1 : 0),5,width-corridor-5);
    const int east_wall = hall+corridor;
    const int splits[2]{front+random_int(rng,4,depth-5),front+random_int(rng,5,depth-4)};
    const bool split_right = !shop && name != "仓房" && style != 2;
    const int notch_start = std::max(splits[1]+1,back-3);
    const int stair_y = front+random_int(rng,2,depth-3);
    auto inside = [&](int x, int y) {
        if (x < left || x > right || y < front || y > back) return false;
        if (x < left+cut && y < front+2) return false;
        return !(notch && x > std::max(east_wall+3,right-notch) && y > notch_start);
    };
    for (int z = 0; z < 3; ++z) {
        for (int y = front; y <= back; ++y) {
            for (int x = left; x <= right; ++x) {
                if (!inside(x,y)) continue;
                const bool outer = !inside(x-1,y) || !inside(x+1,y) || !inside(x,y-1) || !inside(x,y+1);
                const bool partition = x == hall-1 || x == east_wall || (x < hall-1 && y == splits[0]) ||
                                       (split_right && x > east_wall && y == splits[1]);
                char tile = outer || partition ? '#' : 'i';
                if (outer && !partition && (((x-left)%4 == 2 && (y == front || y == back)) ||
                    ((y-front)%4 == 2 && (x == left || x == right)))) tile = 'w';
                const char surface = tile == '#' || tile == 'w' ? (name == "仓房" || name == "工坊" ? 'B' : style == 3 ? 'N' : 'H') :
                                     (x >= hall && x < east_wall ? (domestic || shop ? 'R' : 'd') : 'i');
                lot.put(z,x,y,tile,surface);
                mark_enclosed_story(block, z, lot.at(x,y));
            }
        }
        const auto types = uses(name,z,style % 2 == 1);
        auto room = [&](int x, int top, int w, int h, int wall, bool enter_left, Use use) {
            if (w < 2 || h < 2) return;
            const int door = top + h/2;
            lot.put(z,wall,door,'D','i');
            furnish(lot,z,Rect2i(x,top,w,h),use,enter_left,door,rng);
        };
        room(left+1+cut,front+1,hall-left-2-cut,splits[0]-front-1,hall-1,false,types[0]);
        room(left+1,splits[0]+1,hall-left-2,back-splits[0]-1,hall-1,false,types[1]);
        if (split_right) {
            room(east_wall+1,front+1,right-east_wall-1,splits[1]-front-1,east_wall,true,types[2]);
            room(east_wall+1,splits[1]+1,std::max(3,right-east_wall-1-notch),back-splits[1]-1,east_wall,true,types[3]);
        } else {
            room(east_wall+1,front+1,std::max(3,right-east_wall-1-notch),depth-2,east_wall,true,types[2]);
        }
        lot.put(z,hall,stair_y,z == 0 ? '^' : z == 2 ? 'v' : 'X','d');
    }
    lot.put(0,hall,front,'D','i');
    if (style == 2 && !domestic && corridor > 1) lot.put(0,hall+1,front,'D','i');
    const int gate = domestic ? std::max(0,front-5) : 0;
    for (int y = 0; y < front; ++y) {
        for (int x = left; x <= right; ++x) {
            if (lot.grade(x,y)) continue;
            if (domestic && y == gate) lot.put(0,x,y,x == hall ? 'D' : 'f',x == hall ? 'G' : '.');
            else if (domestic && y > gate && (x == left || x == right)) lot.put(0,x,y,'f','.');
            else if (x == hall || (!domestic && y == front-1)) lot.put(0,x,y,':','p');
            else if (y > gate && y < front-1 && (x == left+1 || x == right-1) && random_int(rng,0,4) < 3) {
                lot.put(0,x,y,random_int(rng,0,2) == 0 ? 'Y' : 'g','.');
            }
        }
    }
    block.plots.push_back({Rect2i(origin,{23,23}),kind});
}
}
