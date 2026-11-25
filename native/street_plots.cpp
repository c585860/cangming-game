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

void furnish(Lot &lot, int z, Rect2i room, Use use, bool enters_from_left, int doorway, std::mt19937 &rng) {
    const int width = room.size.x, depth = room.size.y;
    const int aisle = width / 2;
    const char floor = floor_for(use);
    auto put = [&](int x, int y, char thing, char finish = 0) {
        if (x < 0 || x >= width || y < 0 || y >= depth) return;
        if (thing != 'i' && (x == aisle || y+room.position.y == doorway)) return;
        if (!enters_from_left) x = width-1-x;
        const char current = lot.cell(z,room.position.x+x,room.position.y+y);
        if (current == '#' || current == 'w' || current == 'D' || current == ' ' || current == '.') return;
        lot.put(z, room.position.x+x, room.position.y+y, thing, finish ? finish : floor);
    };
    for (int y = 0; y < depth; ++y) {
        for (int x = 0; x < width; ++x) put(x,y,'i');
    }
    switch (use) {
        case Use::shop:
            for (int x = 0; x < width; ++x) {
                put(x,0,'K');
                if (depth >= 7) put(x,depth-2,'K');
                if (width >= 7 && depth >= 9) put(x,depth/2,'k');
            }
            put(width-1,depth-1,'c');
            for (int y = 0; y < depth; ++y) put(aisle,y,'i','R');
            break;
        case Use::kitchen:
            put(0,0,'h'); put(width-1,0,'u');
            for (int x = 1; x < width-1; ++x) put(x,0,'k');
            put(width-1,1,'k'); put(width-1,2,'c');
            if (depth >= 5) { put(1,depth-2,'t'); put(0,depth-2,'q'); }
            break;
        case Use::bedroom: {
            const int back = doorway-room.position.y >= depth-2 ? 0 : depth-1;
            const int inward = back == 0 ? 1 : -1;
            put(width-1,back,'b'); put(width-1,back+inward,'b');
            put(0,back,'F'); put(0,back+inward,'c');
            put(width-2,back,'S'); put(0,depth/2,'l');
            break;
        }
        case Use::hall:
            for (int x = 0; x < width; ++x) put(x,0,'S');
            if (depth >= 4) {
                const int row = depth >= 6 ? 2 : 1;
                put(width-2,row,'t'); put(width-1,row,'t'); put(width-1,row+1,'q');
            }
            for (int y = 1; y < depth-1; ++y) put(aisle,y,'i','R');
            put(width-1,depth-1,'P');
            break;
        case Use::study:
            for (int x = 0; x < width; ++x) put(x,0,'r');
            for (int y = 1; y < std::min(4,depth-1); ++y) put(width-1,y,'r');
            put(0,depth-1,'l'); put(1,depth-1,'q');
            break;
        case Use::bath:
            put(0,0,'u'); put(width-1,0,'a'); put(width-1,1,'a');
            break;
        case Use::store:
        case Use::workshop:
            for (int x = 0; x < width; ++x) put(x,0,random_int(rng,0,3) == 0 ? 'c' : use == Use::store ? 'C' : 'k');
            for (int y = 2; y < depth-1; y += 2) {
                put(width-1,y,use == Use::store ? 'C' : 'k');
                put(0,y,'r');
            }
            put(width-1,depth-1,use == Use::workshop ? 'h' : 'a');
            break;
    }
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
        // Keep furniture inside the stepped footprint and clear of all door rows.
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
