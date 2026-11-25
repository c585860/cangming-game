#include "city.hpp"
#include <algorithm>

namespace cangling {
std::vector<Vector2i> CityPlan::road_path(Vector2i from, int direction) const {
    if (!connected(from,direction)) return {};
    if (direction < 2) {
        auto path = road_path(from + steps[direction],3-direction);
        std::reverse(path.begin(),path.end());
        return path;
    }
    const bool east = direction == 2;
    const bool bridge = east && from.x == 22;
    const bool riverbank = !east && from.x == 22;
    const auto origin = hub(from);
    const auto normal = east ? Vector2i(0,1) : Vector2i(1,0);
    const auto tangent = steps[direction];
    const auto shape = sector_seed(seed ^ (0x30fd98b9u + direction),from);
    const int rise = bridge ? 0 : riverbank ? 4 : 6 + shape % 8;
    const int peak = 19 + (shape >> 7) % 23;
    const int end = !east && from.y == 22 ? 50 : sector_size;
    std::vector<Vector2i> path{origin};
    for (int t = 1; t <= sector_size; ++t) {
        const int side = t < peak ? t : std::max(0,end-t);
        const int span = t < peak ? peak : end-peak;
        const int bend = rise * side * side * (3*span-2*side) / (span*span*span);
        const auto at = origin + tangent*t + normal*bend;
        auto p = path.back() + tangent;
        path.push_back(p);
        while (p != at) {
            p += normal * ((east ? at.y-p.y : at.x-p.x) > 0 ? 1 : -1);
            path.push_back(p);
        }
    }
    return path;
}

void shape_streets(Block &block, Vector2i sector, const CityPlan &plan) {
    const auto base = sector * sector_size;
    auto put = [&](Vector2i p, char style, bool center) {
        const auto local = p-base;
        if (local.x < 0 || local.y < 0 || local.x >= sector_size || local.y >= sector_size) return;
        char &cell = tile_ref(block.ground,local.x,local.y);
        char &surface = tile_ref(block.ground_surface,local.x,local.y);
        if ((cell == '~' || cell == 'W') && !center) return;
        if (cell == '~' || cell == 'W' || cell == '=') {
            cell = '=';
            surface = '=';
        } else if (center || surface == '\0') {
            cell = style == 'm' ? '+' : ':';
            if (surface != 'm' && surface != '=') surface = style;
        }
    };
    // Replace the straight layout while preserving water and the bridge deck.
    for (int y = 0; y < sector_size; ++y) {
        for (int x = 0; x < sector_size; ++x) {
            auto &tile = tile_ref(block.ground,x,y);
            if (tile == ':' || tile == '+') tile = '.';
        }
    }
    for (int direction = 0; direction < 4; ++direction) {
        const auto east_west = direction == 1 || direction == 2;
        const auto road_sector = direction < 2 ? sector+steps[direction] : sector;
        const bool main = east_west ? plan.bridges[road_sector.y] || road_sector.y == plan.civic_center.y :
            road_sector.x == 20 || road_sector.x == plan.civic_center.x || road_sector.x == plan.trade_center.x;
        const auto normal = east_west ? Vector2i(0,1) : Vector2i(1,0);
        const auto path = plan.road_path(sector,direction);
        for (const auto p : path) {
            for (int offset = -1; offset < (main ? 5 : 3); ++offset) {
                put(p+normal*offset,offset >= (main ? 3 : 2) ? 'p' : main ? 'm' : 'p',false);
            }
            put(p,main ? 'm' : 'p',true);
            if (main) {
                put(p+normal, 'm', true);
                put(p+normal*2, 'm', true);
            }
        }
    }
}
}
