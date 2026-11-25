#include "city.hpp"
#include <algorithm>
#include <numeric>

namespace cangling {
namespace {
constexpr int count = sector_count * sector_count;
int index(Vector2i p) { return p.y * sector_count + p.x; }
bool in_bounds(Vector2i p) { return p.x >= 0 && p.y >= 0 && p.x < sector_count && p.y < sector_count; }
}

void CityPlan::generate(std::uint32_t value) {
    seed = value;
    std::mt19937 rng(seed);
    roads.fill(0);
    bridges.fill(false);
    bridges[22] = true;
    bridges[random_int(rng,3,6)] = true;
    bridges[random_int(rng,8,12)] = true;
    bridges[random_int(rng,15,19)] = true;
    civic_center = {random_int(rng,8,13),random_int(rng,7,13)};
    trade_center = {random_int(rng,14,20),random_int(rng,11,18)};
    orchard_center = {random_int(rng,2,7),random_int(rng,2,6)};
    civic_sites = {civic_center + Vector2i(-random_int(rng,1,2),0), civic_center + Vector2i(0,random_int(rng,1,2)),
                   civic_center + Vector2i(random_int(rng,1,2),-1)};
    constexpr int bank_span = 75;
    const int bank = random_int(rng,1340,1346);
    std::array<int,city_size / bank_span + 1> bends;
    for (int &bend : bends) bend = bank + random_int(rng,-8,8);
    for (int y = 0; y < city_size; ++y) {
        const int segment = y / bank_span;
        const int t = y % bank_span;
        const int weight = t * t * (3 * bank_span - 2 * t);
        shores[y] = bends[segment] + (bends[segment+1] - bends[segment]) * weight / (bank_span * bank_span * bank_span);
    }
    struct Edge { Vector2i from; Vector2i to; int direction; bool main; };
    std::vector<Edge> edges;
    for (int y = 0; y < sector_count; ++y) {
        for (int x = 0; x < sector_count; ++x) {
            const Vector2i start(x,y);
            if (x + 1 < sector_count && (x != 22 || bridges[y])) {
                edges.push_back({start,start+steps[2],2,bridges[y] || y == civic_center.y});
            }
            if (y + 1 < sector_count && (y != 22 || south_gate_column(x))) {
                edges.push_back({start,start+steps[3],3,x == 20 || x == civic_center.x || x == trade_center.x});
            }
        }
    }
    for (int i = static_cast<int>(edges.size()) - 1; i > 0; --i) std::swap(edges[i],edges[random_int(rng,0,i)]);
    std::array<int,count> parent;
    std::iota(parent.begin(),parent.end(),0);
    auto root = [&](int id) {
        while (parent[id] != id) {
            parent[id] = parent[parent[id]];
            id = parent[id];
        }
        return id;
    };
    for (const Edge &edge : edges) {
        const int a = index(edge.from), b = index(edge.to);
        const int a_root = root(a), b_root = root(b);
        if (a_root == b_root && !edge.main && random_int(rng,0,99) >= 45) continue;
        parent[b_root] = a_root;
        roads[a] |= 1 << edge.direction;
        roads[b] |= 1 << (3-edge.direction);
    }
}

bool CityPlan::connected(Vector2i s, int direction) const {
    return (road_mask(s) & (1 << direction)) != 0;
}

int CityPlan::road_mask(Vector2i s) const { return in_bounds(s) ? roads[index(s)] : 0; }

District CityPlan::district_at(Vector2i s) const {
    if (s.x >= 23) return District::east_bank;
    if (s.x == 22) return District::port;
    if (s.y == 22 && s.x >= 19) return s.x == 21 ? District::warehouses : District::commerce;
    const auto to_civic = (s-civic_center).abs();
    const auto to_trade = (s-trade_center).abs();
    const auto to_orchard = (s-orchard_center).abs();
    const bool uneven = (sector_seed(seed,s) % 7) < 3;
    if (s.x < 2 || s.y <= 1 || s.y >= 23 || to_orchard.x + to_orchard.y <= 3+uneven) return District::farmland;
    if (s.x >= 18 + uneven && (s.x == 21 || bridges[s.y] || to_trade.y <= 2)) return District::warehouses;
    if (to_civic.x * 2 + to_civic.y <= 6 + uneven) return District::central;
    if (bridges[s.y] || to_trade.x + to_trade.y <= 4 + uneven || (s.x == civic_center.x && uneven)) return District::commerce;
    return District::residential;
}

char CityPlan::overview(Vector2i s) const {
    if (!in_bounds(s)) return ' ';
    if (s.x == 22) return bridges[s.y] ? '=' : '~';
    switch (district_at(s)) {
        case District::farmland: return '.';
        case District::residential: return 'i';
        case District::commerce: return '+';
        case District::central: return 'H';
        case District::warehouses: return 'c';
        case District::east_bank: return 'g';
        default: return '~';
    }
}
}
