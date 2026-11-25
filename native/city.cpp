#include "city.hpp"
#include <godot_cpp/variant/variant.hpp>

namespace cangling {
namespace {
constexpr int cache_limit = 72;

constexpr std::array civic_types{"书院", "巡检所", "医馆"};

const char *choose_plot(const CityPlan &plan, Vector2i s, int index, District zone, std::mt19937 &rng) {
    if (s == Vector2i(20, 22)) return std::array{"街市", "商铺", "药铺", "客栈"}[index];
    if (s == Vector2i(19, 22)) return std::array{"住宅", "吐纳院", "吐纳庭", "住宅"}[index];
    if (index == 0) {
        for (std::size_t i = 0; i < plan.civic_sites.size(); ++i) {
            if (s == plan.civic_sites[i]) return civic_types[i];
        }
    }
    if (zone == District::farmland || zone == District::east_bank) {
        return std::array{"果圃", "空地", "果圃", "空地", "住宅"}[random_int(rng, 0, 4)];
    }
    if (zone == District::warehouses) {
        return std::array{"仓房", "仓房", "仓房", "工坊", "工坊", "住宅", "客栈", "公园"}[random_int(rng, 0, 7)];
    }
    if (zone == District::central) {
        return std::array{"住宅", "住宅", "住宅", "书院", "巡检所", "医馆", "公园", "商铺"}[random_int(rng, 0, 7)];
    }
    if (zone == District::commerce) {
        return std::array{"商铺", "商铺", "住宅", "住宅", "客栈", "药铺", "工坊", "广场"}[random_int(rng, 0, 7)];
    }
    return std::array{"住宅", "住宅", "住宅", "住宅", "住宅", "果圃", "公园", "商铺"}[random_int(rng, 0, 7)];
}
}

void City::reset(std::uint32_t new_seed, int version) {
    seed = new_seed;
    layout = version;
    plan.generate(seed);
    cache.clear();
    recent.clear();
}

const Block &City::block_at(Vector2i s) {
    const int key = s.y * sector_count + s.x;
    auto it = cache.find(key);
    if (it != cache.end()) {
        recent.splice(recent.end(), recent, it->second.position);
        return it->second.block;
    }
    if (cache.size() == cache_limit) {
        cache.erase(recent.front());
        recent.pop_front();
    }
    recent.push_back(key);
    auto &block = cache.emplace(key, Cached{Block{}, std::prev(recent.end())}).first->second.block;
    block.upper.fill(' ');
    block.attic.fill(' ');
    fill_streets(block, s, plan);
    if (layout >= 2) shape_streets(block,s,plan);
    std::mt19937 rng(sector_seed(seed, s));
    const District zone = plan.district_at(s);
    if (zone != District::port) {
        for (int i = 0; i < 4; ++i) {
            const Vector2i origin(5 + (i % 2) * 27, 5 + (i / 2) * 27);
            const char *kind = choose_plot(plan,s,i,zone,rng);
            if (layout == 1) build_plot(block,origin,kind,rng);
            else if (layout == 2) build_street_plot(block,origin,kind,rng);
            else build_specialty_plot(block,origin,kind,rng,s == Vector2i(19,22) || s == Vector2i(20,22));
        }
    }
    if (layout >= 2 && zone != District::farmland && zone != District::east_bank) {
        for (int y = 1; y+1 < sector_size; ++y) {
            for (int x = 1; x+1 < sector_size; ++x) {
                char &tile = tile_ref(block.ground,x,y);
                if (tile != '.' || tile_ref(block.ground_surface,x,y)) continue;
                const auto hash = sector_seed(seed, s*sector_size+Vector2i(x,y));
                const bool roadside = tile_ref(block.ground_surface,x-1,y) == 'p' || tile_ref(block.ground_surface,x,y-1) == 'p';
                if (roadside && hash % 31 == 0) tile = 'L';
                else if (roadside && hash % 47 == 0) tile = 'Y';
            }
        }
    }
    // Keep the south wall continuous over the southernmost lots.
    if (s.y == 22 && s.x >= 1 && s.x < 22) {
        for (int x = 0; x < sector_size; ++x) {
            if (!(south_gate_column(s.x) && x <= 3)) {
                tile_ref(block.ground, x, 56) = '#';
                tile_ref(block.ground_surface, x, 56) = 'B';
            }
        }
    }
    repair_windows(block);
    return block;
}

char City::tile(Vector2i p, int floor) {
    if (!in_city(p)) return ' ';
    const auto s = sector_at(p);
    const auto local = p - s * sector_size;
    const Block &block = block_at(s);
    return level_tiles(block, floor)[local.y * sector_size + local.x];
}

int City::lighting_column(Vector2i p, int floor, int layers) {
    if (!in_city(p)) return 0;
    const auto s = sector_at(p);
    const auto local = p - s * sector_size;
    const Block &block = block_at(s);
    const int i = local.y * sector_size + local.x;
    int result = 0;
    // Two bits per layer: enclosed floor, then opaque slab or roof above it.
    for (int layer = 0; layer < layers && layer < 4 && floor <= std::numeric_limits<int>::max() - layer; ++layer) {
        const int z = floor + layer;
        const bool enclosed = enclosed_at(block, z, i);
        bool ceiling = enclosed;
        if (z < std::numeric_limits<int>::max() && enclosed_at(block, z + 1, i)) {
            const char upper = level_tiles(block, z + 1)[i];
            ceiling = upper != 'X' && upper != 'v';
        }
        const int flags = int(enclosed) | (int(ceiling) << 1);
        result |= flags << (layer * 2);
    }
    return result;
}

char City::surface(Vector2i p, int floor) {
    if (!in_city(p)) return '\0';
    const auto s = sector_at(p);
    const auto local = p - s * sector_size;
    const Block &block = block_at(s);
    return level_surfaces(block, floor)[local.y * sector_size + local.x];
}

String City::location(Vector2i p) {
    if (!in_city(p)) return String();
    if (p.x >= 1320 && p.x < 1340 && p.y >= 1320 && p.y <= 1335) return String::utf8("沧菱码头");
    if (p.x >= 1320 && p.x < 1340 && p.y > 1335 && p.y < 1380) return String::utf8("城东河滩");
    if (p.y >= 1376 && p.x > 1170 && p.x < 1230) return String::utf8("南门外");
    const auto s = sector_at(p);
    const auto local = p - s * sector_size;
    for (const Plot &plot : block_at(s).plots) {
        if (plot.bounds.has_point(local)) return String::utf8(plot.name);
    }
    return String::utf8(district_name(plan.district_at(s)));
}

Dictionary City::landmarks() const {
    Dictionary result;
    result[Vector2i(1201, 1376)] = String::utf8("南门");
    result[market_tile] = String::utf8("南坊街市");
    result[altar_tile] = String::utf8("吐纳院");
    result[dock_tile] = String::utf8("沧菱码头");
    result[herb_tiles[1]] = String::utf8("采药河滩");
    for (std::size_t i = 0; i < plan.civic_sites.size(); ++i) {
        result[plan.civic_sites[i] * sector_size + Vector2i(16,16)] = String::utf8(civic_types[i]);
    }
    result[plan.trade_center * sector_size + Vector2i(16,16)] = String::utf8("商坊");
    result[plan.orchard_center * sector_size + Vector2i(16,16)] = String::utf8("城郊田圃");
    return result;
}
}
