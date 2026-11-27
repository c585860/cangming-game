#include "world.hpp"
#include <godot_cpp/classes/a_star_grid2d.hpp>
#include <algorithm>

namespace cangling {
using namespace godot;
namespace {
const Rect2i full_bounds(Vector2i(0, 0), Vector2i(city_size, city_size));

Rect2i nearby_box(Vector2i a, Vector2i b) {
    const Vector2i pad(24, 24);
    const Vector2i lo(std::min(a.x, b.x), std::min(a.y, b.y));
    const Vector2i hi(std::max(a.x, b.x), std::max(a.y, b.y));
    return Rect2i(lo - pad, hi - lo + pad * 2 + Vector2i(1, 1)).intersection(full_bounds);
}
}

std::vector<Vector2i> CanglingWorld::local_path(Vector2i from, Vector2i to, Rect2i region, int z) {
    if (from == to) return {from};
    Ref<AStarGrid2D> grid;
    grid.instantiate();
    grid->set_region(region);
    grid->set_diagonal_mode(AStarGrid2D::DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE);
    grid->set_default_estimate_heuristic(AStarGrid2D::HEURISTIC_OCTILE);
    grid->set_default_compute_heuristic(AStarGrid2D::HEURISTIC_OCTILE);
    grid->update();
    if (active_pack == CorePackId::Cataclysm) {
        const int x0 = region.position.x, y0 = region.position.y;
        const int x1 = x0 + region.size.x, y1 = y0 + region.size.y;
        for (int y = y0; y < y1; ++y) {
            for (int x = x0; x < x1; ++x) {
                const Vector2i cell(x, y);
                if (cell != from && cell != to && !walkable_on(cell, z)) {
                    grid->set_point_solid(cell, true);
                }
            }
        }
        const auto path = grid->get_id_path(from, to);
        std::vector<Vector2i> answer;
        answer.reserve(path.size());
        for (int i = 0; i < path.size(); ++i) answer.emplace_back(path[i]);
        return answer;
    }
    const SectorGridSnapshot snap = city.snapshot_sectors(region);
    const int x0 = region.position.x, y0 = region.position.y;
    const int x1 = x0 + region.size.x, y1 = y0 + region.size.y;
    for (int y = y0; y < y1; ++y) {
        const int sy = y / sector_size;
        const int ly = y - sy * sector_size;
        for (int x = x0; x < x1; ++x) {
            const Vector2i cell(x, y);
            if (z == 0 && is_npc_tile(cell)) {
                grid->set_point_solid(cell, true);
                continue;
            }
            const int64_t k = key(cell, z);
            char tile = ' ';
            if (!tile_overrides.empty()) {
                if (const auto ov = tile_overrides.find(k); ov != tile_overrides.end()) tile = ov->second;
            }
            if (tile == ' ') {
                const int sx = x / sector_size;
                if (const Block *blk = snap.at(sx, sy)) {
                    tile = level_tiles(*blk, z)[ly * sector_size + (x - sx * sector_size)];
                }
            }
            if ((tile == 'D' || tile == 'w') && !doors.empty() && doors.count(k)) {
                tile = (tile == 'D') ? 'o' : 'O';
            }
            if (!passable_tile(tile)) grid->set_point_solid(cell, true);
        }
    }
    const auto path = grid->get_id_path(from, to);
    std::vector<Vector2i> answer;
    answer.reserve(path.size());
    for (int i = 0; i < path.size(); ++i) answer.emplace_back(path[i]);
    return answer;
}

std::vector<Vector2i> CanglingWorld::sector_path(Vector2i from, Vector2i to) const {
    return {from, to};
}

std::vector<Vector2i> CanglingWorld::find_path(Vector2i to) {
    if (!walkable(to)) return {};
    if (active_pack == CorePackId::Cataclysm) {
        const Vector2i pad(18, 18);
        const Vector2i lo(std::min(pos.x, to.x), std::min(pos.y, to.y));
        const Vector2i hi(std::max(pos.x, to.x), std::max(pos.y, to.y));
        const Rect2i box(lo - pad, hi - lo + pad * 2 + Vector2i(1, 1));
        if (box.size.x > 120 || box.size.y > 120) return {};
        return local_path(pos, to, box, floor);
    }
    if (floor != 0) {
        return local_path(pos, to, nearby_box(pos, to), floor);
    }
    // On compact 240x240 Yangzhou, local A* handles nearby paths in <0.5ms and full-city A* in <2.5ms!
    auto local = local_path(pos, to, nearby_box(pos, to), 0);
    if (!local.empty()) return local;
    return local_path(pos, to, full_bounds, 0);
}

Array CanglingWorld::route_to(Vector2i dest, bool interact_with_target) {
    if (!in_bounds(dest)) return {};
    std::vector<Vector2i> result;
    if (interact_with_target) {
        if (near(dest)) result = {pos};
        else {
            static const std::array<Vector2i, 8> adj{{{0,-1},{-1,0},{1,0},{0,1},{-1,-1},{1,-1},{-1,1},{1,1}}};
            for (const auto step : adj) {
                auto candidate = find_path(dest + step);
                if (!candidate.empty() && (result.empty() || candidate.size() < result.size())) result.swap(candidate);
            }
            if (result.empty() && walkable(dest)) result = find_path(dest);
        }
    } else {
        result = find_path(dest);
    }
    Array converted;
    converted.resize(result.size());
    for (std::size_t i = 0; i < result.size(); ++i) converted[i] = result[i];
    return converted;
}
}
