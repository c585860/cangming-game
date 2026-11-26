#include "city.hpp"
#include "thread_pool.hpp"

namespace cangling {
namespace {
constexpr int span = survey_tile_size;
constexpr int per_block = sector_size / span;
constexpr int width = city_size / span;

int building_icon(std::string_view name) {
    if (name == "醉仙楼" || name == "悦来客栈") return 11;
    if (name == "回春堂药铺") return 9;
    if (name == "王记铁匠铺" || name == "水埠码头") return 10;
    if (name == "利源当铺" || name == "春风茶馆") return 8;
    if (name == "扬威武馆" || name == "文昌阁" || name == "沧灵府衙" || name == "沧灵南门" ||
        name == "沧灵北门" || name == "沧灵东门" || name == "沧灵西门") return 12;
    if (name == "沧灵广场" || name == "翠微湖 · 五亭桥") return 13;
    if (name.find("坊") != std::string_view::npos || name.find("民居") != std::string_view::npos ||
        name.find("巷") != std::string_view::npos || name.find("宅院") != std::string_view::npos ||
        name.find("铺面") != std::string_view::npos) return 7;
    return 0;
}
}

godot::PackedByteArray City::survey() {
    godot::PackedByteArray data;
    data.resize(width * width * 2);
    auto *out = data.ptrw();

    const int total_sectors = sector_count * sector_count;
    ThreadPool::instance().parallel_for(0, total_sectors, 1, [this, out](int begin, int end) {
        for (int idx = begin; idx < end; ++idx) {
            const int sy = idx / sector_count;
            const int sx = idx % sector_count;
            std::shared_ptr<const Block> blk = try_cached({sx, sy});
            if (!blk) blk = generate_block({sx, sy});
            const Block &block = *blk;
            for (int cy = 0; cy < per_block; ++cy) {
                for (int cx = 0; cx < per_block; ++cx) {
                    const int left = cx * span, top = cy * span;
                    int water = 0, bridge = 0, road = 0, main = 0, wooded = 0, roof = 0, mask = 0;
                    for (int y = 0; y < span; ++y) {
                        for (int x = 0; x < span; ++x) {
                            const int n = (top + y) * sector_size + left + x;
                            const char tile = block.ground[n], surface = block.ground_surface[n];
                            water += (tile == '~' || tile == 'W');
                            bridge += (tile == '=');
                            wooded += (tile == 'Y' || tile == 'g');
                            roof += block.enclosed_stories[0].test(n);
                            const bool street = (tile == '=') || ((tile == '+' || tile == ':') &&
                                (surface == 'm' || surface == 'p' || !surface));
                            if (!street) continue;
                            ++road;
                            main += (surface == 'm' || tile == '+');
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
                    else {
                        for (auto it = block.plots.rbegin(); it != block.plots.rend(); ++it) {
                            if (!it->bounds.has_point(center)) continue;
                            const int icon = building_icon(it->name);
                            if (icon > 0 && (roof >= 3 || icon >= 13 || icon == 10)) {
                                kind = icon;
                                break;
                            }
                        }
                        if (!kind && road >= span && mask) kind = main ? 1 : 2;
                        if (!kind && wooded >= 2) kind = 5;
                        if (!kind && water >= 3) kind = 6;
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
