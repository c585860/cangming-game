#include "city.hpp"
#include "thread_pool.hpp"

namespace cangling {
namespace {
constexpr int span = survey_tile_size;
constexpr int per_block = sector_size / span;
constexpr int width = city_size / span;

int building_icon(std::string_view name) {
    if (name == "住宅") return 7;
    if (name == "商铺" || name == "街市") return 8;
    if (name == "药铺" || name == "医馆") return 9;
    if (name == "仓房" || name == "工坊") return 10;
    if (name == "客栈") return 11;
    if (name == "书院" || name == "巡检所" || name == "吐纳院") return 12;
    if (name == "广场" || name == "公园" || name == "吐纳庭") return 13;
    if (name == "果圃") return 14;
    return 0;
}
}

godot::PackedByteArray City::survey() {
    godot::PackedByteArray data;
    // One pair per atlas cell: terrain/use ID and south/east/west/north links.
    data.resize(width * width * 2);
    auto *out = data.ptrw();

    const int total_sectors = sector_count * sector_count;
    ThreadPool::instance().parallel_for(0, total_sectors, 4, [this, out](int begin, int end) {
        for (int idx = begin; idx < end; ++idx) {
            const int sy = idx / sector_count;
            const int sx = idx % sector_count;
            // Reuse already-cached sectors or generate transiently so full-city survey
            // runs across all CPU cores without bloating or thrashing the LRU cache.
            std::shared_ptr<const Block> blk = try_cached({sx, sy});
            if (!blk) {
                blk = generate_block({sx, sy});
            }
            const Block &block = *blk;
            for (int cy = 0; cy < per_block; ++cy) {
                for (int cx = 0; cx < per_block; ++cx) {
                    const int left = cx * span, top = cy * span;
                    int water = 0, bridge = 0, road = 0, main = 0, wooded = 0, roof = 0, mask = 0;
                    for (int y = 0; y < span; ++y) {
                        for (int x = 0; x < span; ++x) {
                            const int n = (top + y) * sector_size + left + x;
                            const char tile = block.ground[n], surface = block.ground_surface[n];
                            water += tile == '~' || tile == 'W';
                            bridge += tile == '=';
                            wooded += tile == 'Y' || tile == 'g';
                            roof += block.upper[n] != ' ' || block.attic[n] != ' ';
                            const bool street = tile == '=' || ((tile == '+' || tile == ':') &&
                                (surface == 'm' || surface == 'p' || !surface));
                            if (!street) continue;
                            ++road;
                            main += surface == 'm' || tile == '+';
                            if (y == span - 1) mask |= 1;
                            if (x == span - 1) mask |= 2;
                            if (x == 0) mask |= 4;
                            if (y == 0) mask |= 8;
                        }
                    }
                    const Vector2i center(left + span / 2, top + span / 2);
                    int kind = 0;
                    if (bridge >= 2) kind = 4;
                    else if (water >= span * span / 2) kind = 3;
                    else if (road >= span && mask && roof < span * span / 3) kind = main ? 1 : 2;
                    else {
                        for (const auto &plot : block.plots) {
                            if (!plot.bounds.has_point(center)) continue;
                            const int icon = building_icon(plot.name);
                            if (roof >= span || (icon >= 13 && roof == 0)) kind = icon;
                            break;
                        }
                        if (!kind && wooded >= 5) kind = 5;
                        if (!kind && water >= 15) kind = 6;
                    }
                    const int i = ((sy * per_block + cy) * width + sx * per_block + cx) * 2;
                    out[i] = static_cast<std::uint8_t>(kind);
                    out[i + 1] = static_cast<std::uint8_t>(mask);
                }
            }
        }
    });
    return data;
}
}
