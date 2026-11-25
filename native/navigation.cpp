#include "world.hpp"
#include <godot_cpp/classes/a_star_grid2d.hpp>
#include <algorithm>
#include <queue>

namespace cangling {
using namespace godot;
namespace {
const Rect2i bounds(Vector2i(), Vector2i(city_size, city_size));

Vector2i travel_sector(Vector2i p) {
    auto s = sector_at(p);
    if (s.x == 22 && p.x >= east_shore) s.x = 23;
    return s;
}

Rect2i nearby_box(Vector2i a, Vector2i b) {
    const Vector2i pad(sector_size / 2, sector_size / 2);
    const Vector2i lo(std::min(a.x,b.x), std::min(a.y,b.y));
    const Vector2i hi(std::max(a.x,b.x), std::max(a.y,b.y));
    return Rect2i(lo-pad,hi-lo+pad*2+Vector2i(1,1)).intersection(bounds);
}
}

std::vector<Vector2i> CanglingWorld::local_path(Vector2i from, Vector2i to, Rect2i region, int z) {
    if (from == to) return {from};
    Ref<AStarGrid2D> grid;
    grid.instantiate();
    grid->set_region(region);
    grid->set_diagonal_mode(AStarGrid2D::DIAGONAL_MODE_NEVER);
    grid->set_default_estimate_heuristic(AStarGrid2D::HEURISTIC_MANHATTAN);
    grid->set_default_compute_heuristic(AStarGrid2D::HEURISTIC_MANHATTAN);
    grid->update();
    for (int y = region.position.y; y < region.get_end().y; ++y) {
        for (int x = region.position.x; x < region.get_end().x; ++x) {
            const Vector2i cell(x,y);
            if (!walkable_on(cell,z)) grid->set_point_solid(cell, true);
        }
    }
    const auto path = grid->get_id_path(from,to);
    std::vector<Vector2i> answer;
    answer.reserve(path.size());
    for (int i = 0; i < path.size(); ++i) answer.emplace_back(path[i]);
    return answer;
}

std::vector<Vector2i> CanglingWorld::sector_path(Vector2i from, Vector2i to) const {
    constexpr int count = sector_count * sector_count;
    auto index_of = [](Vector2i p) { return p.y * sector_count + p.x; };
    auto sector_of = [](int i) { return Vector2i(i % sector_count, i / sector_count); };
    std::array<int,count> previous;
    previous.fill(-1);
    const int start = index_of(from), target = index_of(to);
    std::queue<int> frontier;
    frontier.push(start);
    previous[start] = start;
    while (!frontier.empty() && previous[target] < 0) {
        const int head = frontier.front();
        frontier.pop();
        const auto p = sector_of(head);
        for (int direction = 0; direction < 4; ++direction) {
            if (!city.plan.connected(p,direction)) continue;
            const auto step = steps[direction];
            const auto next = p + step;
            if (next.x < 0 || next.y < 0 || next.x >= sector_count || next.y >= sector_count) continue;
            const int n = index_of(next);
            if (previous[n] >= 0) continue;
            previous[n] = head;
            frontier.push(n);
        }
    }
    if (previous[target] < 0) return {};
    std::vector<Vector2i> result;
    for (int i = target; i != start; i = previous[i]) result.push_back(sector_of(i));
    result.push_back(from);
    std::reverse(result.begin(), result.end());
    return result;
}

std::vector<Vector2i> CanglingWorld::find_path(Vector2i to) {
    if (!walkable(to)) return {};
    const auto delta = (to-pos).abs();
    if (floor != 0) {
        if (sector_at(pos) != sector_at(to)) return {};
        return local_path(pos,to,nearby_box(pos,to),floor);
    }
    if (delta.x <= 40 && delta.y <= 40) {
        auto local = local_path(pos,to,nearby_box(pos,to),0);
        if (!local.empty()) return local;
    }
    const auto from_block = travel_sector(pos), to_block = travel_sector(to);
    if (from_block == to_block) return local_path(pos,to,nearby_box(pos,to),0);
    const auto graph = sector_path(from_block,to_block);
    if (graph.empty()) return {};
    auto path = local_path(pos,hub(from_block),nearby_box(pos,hub(from_block)),0);
    if (path.empty()) return {};
    const auto final_hub = hub(to_block);
    auto tail = local_path(final_hub,to,nearby_box(final_hub,to),0);
    if (tail.empty()) return {};
    for (std::size_t i = 1; i < graph.size(); ++i) {
        auto p = path.back();
        const auto end = hub(graph[i]);
        const auto step = (end-p).sign();
        if (city.layout >= 2) {
            const int direction = step.x ? (step.x > 0 ? 2 : 1) : (step.y > 0 ? 3 : 0);
            const auto street = city.plan.road_path(graph[i-1],direction);
            if (street.empty()) return {};
            for (auto cell = street.begin()+1; cell != street.end(); ++cell) {
                if (!walkable_on(*cell,0)) return {};
                path.push_back(*cell);
            }
            continue;
        }
        while (p != end) {
            p += step;
            if (!walkable_on(p,0)) return {};
            path.push_back(p);
        }
    }
    path.insert(path.end(),tail.begin()+1,tail.end());
    return path;
}

Array CanglingWorld::route_to(Vector2i dest, bool interact_with_target) {
    if (!in_city(dest)) return {};
    std::vector<Vector2i> result;
    if (interact_with_target) {
        if (near(dest)) result = {pos};
        else {
            for (const auto step : steps) {
                auto candidate = find_path(dest+step);
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
