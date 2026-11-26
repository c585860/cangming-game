#include "city.hpp"

namespace cangling {
void CityPlan::generate(std::uint32_t value) {
    seed = value;
    roads.fill(0x0F);
    bridges.fill(true);
    shores.fill(221);
    civic_center = {2, 1};
    trade_center = {2, 2};
    orchard_center = {0, 0};
    civic_sites = {{{1, 1}, {2, 1}, {1, 2}}};
}

bool CityPlan::connected(Vector2i s, int direction) const {
    return (road_mask(s) & (1 << direction)) != 0;
}

int CityPlan::road_mask(Vector2i s) const {
    if (s.x < 0 || s.y < 0 || s.x >= sector_count || s.y >= sector_count) return 0;
    return roads[s.y * sector_count + s.x];
}

District CityPlan::district_at(Vector2i s) const {
    if (s.x == 0 && s.y == 0) return District::farmland;
    if (s.x == 3) return District::east_bank;
    if (s.x == 2 && s.y == 2) return District::commerce;
    if (s.x == 2 && s.y == 1) return District::central;
    return District::residential;
}

char CityPlan::overview(Vector2i s) const {
    if (s.x < 0 || s.y < 0 || s.x >= sector_count || s.y >= sector_count) return ' ';
    switch (district_at(s)) {
        case District::farmland: return '.';
        case District::residential: return 'i';
        case District::commerce: return '+';
        case District::central: return 'H';
        case District::east_bank: return 'g';
        default: return '~';
    }
}
}
