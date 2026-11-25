#include "city.hpp"
#include <algorithm>

namespace cangling {
namespace {
enum class Design { residence, market, cargo, school, inn, civic };

bool wall(char c) { return c == '#' || c == 'w' || c == 'D'; }
bool indoor(char s) { return std::string_view("idRjJ").find(s) != std::string_view::npos; }
}

void repair_windows(Block &block) {
    for (int z = 0; z < 3; ++z) {
        auto *cells = &level_tiles(block,z);
        auto *surfaces = &level_surfaces(block,z);
        const auto original = *cells;
        for (int y = 1; y < sector_size-1; ++y) {
            for (int x = 1; x < sector_size-1; ++x) {
                const int i = y*sector_size+x;
                if (original[i] != 'w') continue;
                const auto facade = [&](int along, int across) {
                    if (!wall(original[i-along]) || !wall(original[i+along])) return false;
                    for (const int side : {-across,across}) {
                        const auto exterior = [&](int at) {
                            return !wall(original[at]) && !indoor((*surfaces)[at]) && original[at] != 'i';
                        };
                        const int in = i-side;
                        if (exterior(i+side) && exterior(i+side-along) && exterior(i+side+along) &&
                            !wall(original[in]) && (indoor((*surfaces)[in]) || original[in] == 'i' ||
                            ((*surfaces)[i] == 0 && std::string_view("btckqruarSFPhlCK").find(original[in]) != std::string_view::npos))) return true;
                    }
                    return false;
                };
                if (!facade(1,sector_size) && !facade(sector_size,1)) (*cells)[i] = '#';
            }
        }
    }
}

void build_specialty_plot(Block &block, Vector2i origin, const char *kind, std::mt19937 &rng, bool keep_footprint) {
    const std::string_view name(kind);
    Design design = Design::residence;
    if (name == "商铺" || name == "药铺" || name == "医馆") design = Design::market;
    else if (name == "仓房" || name == "工坊") design = Design::cargo;
    else if (name == "书院") design = Design::school;
    else if (name == "客栈") design = Design::inn;
    else if (name == "巡检所") design = Design::civic;
    if (keep_footprint || design == Design::residence) {
        build_street_plot(block,origin,kind,rng);
        return;
    }
    const auto turn = [](int x, int y, int r) -> Vector2i {
        switch (r) {
            case 0: return {x,y};
            case 1: return {22-y,x};
            case 2: return {22-x,22-y};
            default: return {y,22-x};
        }
    };
    const int variant = random_int(rng,0,3);
    const int width = (design == Design::cargo ? 17 : 15)+(variant&1);
    const int depth = (design == Design::market ? 12 : 14)+(variant>>1);
    const int mid = width/2;
    int facing = -1, left = 0, front = 0, best = -10000;
    for (int i = 0; i < 4; ++i) {
        const int r = (variant+i)%4;
        for (int f = 2; f <= 23-depth; ++f) {
            for (int l = 0; l <= 23-width; ++l) {
                bool free = true;
                for (int y = f; y < f+depth && free; ++y) for (int x = l; x < l+width; ++x) {
                    const auto p = origin+turn(x,y,r);
                    const char surface = tile_ref(block.ground_surface,p.x,p.y);
                    if (surface || tile_ref(block.ground,p.x,p.y) != '.') { free = false; break; }
                }
                if (!free) continue;
                int score = -std::abs(l-(23-width)/2)*2-f;
                for (int y = f-1; y >= -4; --y) {
                    const auto p = origin+turn(l+mid,y,r);
                    if (p.x<0 || p.y<0 || p.x>=sector_size || p.y>=sector_size) break;
                    const char s = tile_ref(block.ground_surface,p.x,p.y);
                    if (s == 'm' || s == 'p') { score += 25-(f-y)*2; break; }
                }
                if (score > best) { best = score; facing = r; left = l; front = f; }
            }
        }
    }
    if (facing < 0) {
        build_street_plot(block,origin,kind,rng);
        return;
    }
    auto put = [&](int z, int x, int y, char tile, char surface) {
        const auto p = origin+turn(left+x,front+y,facing);
        tile_ref(z ? block.upper : block.ground,p.x,p.y) = tile;
        tile_ref(z ? block.upper_surface : block.ground_surface,p.x,p.y) = surface;
    };
    const char facade = design == Design::cargo || design == Design::civic ? 'B' :
                        design == Design::school || design == Design::inn ? 'N' : 'H';
    const char finish = design == Design::cargo ? 'd' : design == Design::market ? 'j' : 'i';
    const int stair = depth-3, rear = depth-5;
    for (int y = 0; y < depth; ++y) for (int x = 0; x < width; ++x) {
        const bool edge = y == 0 || y == depth-1 || x == 0 || x == width-1;
        const bool light = ((x == 0 || x == width-1) && y >= 2 && y < depth-2 && y % 4 == 2) ||
                           ((y == 0 || y == depth-1) && x >= 2 && x < width-2 && x % 4 == 2);
        const auto p = origin+turn(left+x,front+y,facing);
        put(0,x,y,edge ? (light && design != Design::cargo ? 'w' : '#') : 'i',edge ? facade : finish);
        mark_enclosed_story(block, 0, p);
        if (design != Design::cargo || y >= rear) {
            const bool upper_edge = edge || (design == Design::cargo && y == rear);
            put(1,x,y,upper_edge ? (edge && light ? 'w' : '#') : 'i',upper_edge ? facade : 'i');
            mark_enclosed_story(block, 1, p);
        }
    }
    put(0,mid,0,'D',finish);
    if (design == Design::cargo || design == Design::market || design == Design::school) put(0,mid+1,0,'D',finish);
    for (int y = -1; y >= -front; --y) {
        for (int x = design == Design::cargo ? mid-3 : mid-1; x <= (design == Design::cargo ? mid+3 : mid+1); ++x) {
            const auto p = origin+turn(left+x,front+y,facing);
            if (!tile_ref(block.ground_surface,p.x,p.y)) put(0,x,y,':','p');
        }
    }
    switch (design) {
        case Design::market:
            for (int y = 4; y < rear-1; ++y) for (int x : {2,4,width-5,width-3}) put(0,x,y,'K',finish);
            for (int x = 2; x < mid-2; ++x) put(0,x,2,'k',finish);
            for (int x = 1; x < width-1; ++x) put(0,x,rear,x == mid ? 'D' : '#',x == mid ? finish : facade);
            for (int x = 2; x < width-2; x += 2) if (x != mid) put(0,x,depth-2,'C',finish);
            break;
        case Design::cargo:
            for (int y = 3; y < depth-2; ++y) for (int x : {2,3,width-4,width-3}) {
                if ((y+variant)%4 != 0) put(0,x,y,name == "工坊" ? 'k' : 'C',finish);
            }
            if (name == "工坊") { put(0,1,depth-2,'h',finish); put(0,width-2,depth-2,'a',finish); }
            break;
        case Design::school:
            for (int y = 2; y < depth-2; ++y) { put(0,1,y,'r',finish); put(0,width-2,y,'r',finish); }
            for (int y = 4; y < rear+1; y += 3) for (int x : {3,mid-2,mid+2,width-4}) {
                put(0,x,y,'l',finish); put(0,x,y+1,'q',finish);
            }
            for (int y = 1; y < depth-1; ++y) put(0,mid,y,'i','R');
            break;
        case Design::inn:
            for (int y = 3; y < rear; y += 3) for (int x : {3,mid-2,mid+3}) {
                put(0,x,y,'t',finish); put(0,x,y+1,'q',finish);
            }
            for (int x = mid+2; x < width-1; ++x) put(0,x,depth-2,'k','J');
            put(0,width-2,depth-3,'h','J'); put(0,width-2,depth-4,'u','J');
            break;
        case Design::civic:
            for (int x = 2; x < width-2; ++x) if (x != mid) put(0,x,4,'k',finish);
            for (int y = 6; y < depth-2; ++y) {
                put(0,mid-2,y,y == rear ? 'D' : '#',facade);
                put(0,mid+2,y,y == rear ? 'D' : '#',facade);
            }
            put(0,2,depth-2,'l',finish); put(0,width-3,depth-2,'C',finish);
            break;
        default: break;
    }
    const int upper_front = design == Design::cargo ? rear : 0;
    for (int y = upper_front+1; y < depth-1; ++y) {
        if (design == Design::inn && y % 5 == 0) {
            for (int x = 1; x < width-1; ++x) if (x != mid) put(1,x,y,'#',facade);
        } else if (design == Design::inn) {
            for (int x : {mid-1,mid+1}) put(1,x,y,y % 5 == 2 ? 'D' : '#',facade);
            if (y%5 == 1) for (int x : {2,width-3}) put(1,x,y,'b','i');
            if (y%5 == 3) for (int x : {2,width-3}) put(1,x,y,'F','i');
        } else if (y%3 == 1) {
            const char fixture = design == Design::school ? 'r' : design == Design::cargo ? 'C' : 'l';
            put(1,2,y,fixture,'i'); put(1,width-3,y,fixture,'i');
        }
    }
    put(0,mid,stair,'^',finish);
    put(1,mid,stair,'v','i');
    block.plots.push_back({Rect2i(origin,{23,23}),kind});
}
}
