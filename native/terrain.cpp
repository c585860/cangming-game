#include "city.hpp"

namespace cangling {
bool south_gate_column(int x) { return x == 0 || x == 4 || x == 12 || x == 20 || x >= 22; }

const char *district_name(District district) {
    switch (district) {
        case District::farmland: return "城郊田圃";
        case District::residential: return "民居街坊";
        case District::commerce: return "沿街商坊";
        case District::central: return "内城";
        case District::warehouses: return "漕运仓场";
        case District::port: return "沧菱河埠";
        case District::east_bank: return "东堤";
        case District::river: return "沧菱河";
    }
    return "";
}

void fill_streets(Block &block, Vector2i sector, const CityPlan &plan) {
    const auto base = sector * sector_size;
    const District zone = plan.district_at(sector);
    const bool north = plan.connected(sector, 0), west = plan.connected(sector, 1);
    const bool east = plan.connected(sector, 2), south = plan.connected(sector, 3);
    for (int y = 0; y < sector_size; ++y) {
        const int gy = base.y + y;
        const int shore = plan.shores[gy];
        for (int x = 0; x < sector_size; ++x) {
            const int gx = base.x + x;
            char tile = '.';
            const bool horizontal = y <= 3 && ((x <= 3 && west) || (x >= 1 && east));
            const bool vertical = x <= 3 && ((y <= 3 && north) || (y >= 1 && south));
            if (gx >= shore && gx < east_shore) {
                tile = east && y <= 3 ? '=' : (gx - shore < 3 || east_shore - gx <= 3 ? '~' : 'W');
            } else if (horizontal || vertical || (x <= 3 && y <= 3)) {
                tile = plan.bridges[sector.y] || sector.x == plan.civic_center.x || sector.x == 20 ? '+' : ':';
            } else if (zone != District::farmland && zone != District::port && zone != District::east_bank &&
                       ((x >= 28 && x <= 31) || (y >= 28 && y <= 31))) {
                tile = ':';
            } else if (zone == District::port && gx < shore && (gx >= shore - 8 || (gx * 7 + gy * 13) % 17 < 4)) {
                tile = 's';
            }
            tile_ref(block.ground, x, y) = tile;
        }
    }
}

std::uint32_t sector_seed(std::uint32_t seed, Vector2i s) {
    std::uint32_t n = seed ^ (static_cast<std::uint32_t>(s.x) * 0x9e3779b9u) ^ (static_cast<std::uint32_t>(s.y) * 0x85ebca6bu);
    n ^= n >> 16;
    n *= 0x7feb352du;
    n ^= n >> 15;
    n *= 0x846ca68bu;
    return n ^ (n >> 16);
}

int random_int(std::mt19937 &rng, int low, int high) {
    return low + static_cast<int>(rng() % static_cast<std::uint32_t>(high - low + 1));
}
}
