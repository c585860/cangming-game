#include "city.hpp"
#include "thread_pool.hpp"
#include <godot_cpp/variant/variant.hpp>
#include <algorithm>

namespace cangling {
namespace {
constexpr std::size_t cache_limit = 32;

std::size_t block_memory_bytes(const Block &block) {
    std::size_t total = sizeof(Block);
    total += block.extra_levels.size() * (sizeof(int) + sizeof(Block::ExtraLevel) + 32u);
    total += block.plots.capacity() * sizeof(Plot);
    return total;
}
}

void City::reset(std::uint32_t new_seed, int version) {
    std::lock_guard<std::mutex> lock(cache_mutex);
    seed = new_seed;
    layout = version;
    plan.generate(seed);
    cache.clear();
    recent.clear();
}

std::shared_ptr<Block> City::generate_block(Vector2i s) const {
    auto block = std::make_shared<Block>();
    const YangzhouWorldData &yz = yangzhou_world_data();
    const Vector2i base = s * sector_size;

    for (int z = 0; z < 3; ++z) {
        Tiles &dst_t = level_tiles(*block, z);
        Tiles &dst_s = level_surfaces(*block, z);
        for (int ly = 0; ly < sector_size; ++ly) {
            const int wy = base.y + ly;
            for (int lx = 0; lx < sector_size; ++lx) {
                const int wx = base.x + lx;
                const int li = ly * sector_size + lx;
                if (wx < 0 || wy < 0 || wx >= city_size || wy >= city_size) {
                    dst_t[li] = ' ';
                    dst_s[li] = '\0';
                    continue;
                }
                const int gi = wy * city_size + wx;
                dst_t[li] = yz.tiles[z][gi];
                dst_s[li] = yz.surfaces[z][gi];
                if (yz.enclosed[z][gi]) {
                    block->enclosed_stories[z].set(li);
                }
            }
        }
    }

    const Rect2i sec_rect(base, {sector_size, sector_size});
    for (const auto &zinfo : yz.zones) {
        const Rect2i clipped = zinfo.bounds.intersection(sec_rect);
        if (clipped.size.x > 0 && clipped.size.y > 0) {
            block->plots.push_back({Rect2i(clipped.position - base, clipped.size), zinfo.name});
        }
    }
    block->plots.shrink_to_fit();
    return block;
}

std::shared_ptr<const Block> City::try_cached(Vector2i s) const {
    const int key = s.y * sector_count + s.x;
    std::lock_guard<std::mutex> lock(cache_mutex);
    const auto it = cache.find(key);
    return it != cache.end() ? it->second.block : nullptr;
}

std::shared_ptr<const Block> City::block_at(Vector2i s) {
    const int key = s.y * sector_count + s.x;
    {
        std::lock_guard<std::mutex> lock(cache_mutex);
        auto it = cache.find(key);
        if (it != cache.end()) {
            recent.splice(recent.end(), recent, it->second.position);
            return it->second.block;
        }
    }
    std::shared_ptr<const Block> created = generate_block(s);
    std::lock_guard<std::mutex> lock(cache_mutex);
    auto it = cache.find(key);
    if (it != cache.end()) {
        recent.splice(recent.end(), recent, it->second.position);
        return it->second.block;
    }
    while (cache.size() >= cache_limit && !recent.empty()) {
        cache.erase(recent.front());
        recent.pop_front();
    }
    recent.push_back(key);
    cache.emplace(key, Cached{created, std::prev(recent.end())});
    return created;
}

void City::prewarm_sectors(Rect2i area) {
    if (area.size.x <= 0 || area.size.y <= 0) return;
    const int min_x = std::clamp(area.position.x, 0, city_size - 1);
    const int min_y = std::clamp(area.position.y, 0, city_size - 1);
    const int max_x = std::clamp(area.position.x + area.size.x - 1, 0, city_size - 1);
    const int max_y = std::clamp(area.position.y + area.size.y - 1, 0, city_size - 1);
    const int min_sx = min_x / sector_size;
    const int min_sy = min_y / sector_size;
    const int max_sx = max_x / sector_size;
    const int max_sy = max_y / sector_size;

    std::vector<Vector2i> missing;
    {
        std::lock_guard<std::mutex> lock(cache_mutex);
        for (int sy = min_sy; sy <= max_sy; ++sy) {
            for (int sx = min_sx; sx <= max_sx; ++sx) {
                const int key = sy * sector_count + sx;
                auto it = cache.find(key);
                if (it != cache.end()) {
                    recent.splice(recent.end(), recent, it->second.position);
                } else {
                    missing.push_back({sx, sy});
                }
            }
        }
    }
    if (missing.empty()) return;

    std::vector<std::shared_ptr<const Block>> built(missing.size());
    ThreadPool::instance().parallel_for(0, static_cast<int>(missing.size()), 1,
        [this, &missing, &built](int begin, int end) {
            for (int i = begin; i < end; ++i) {
                built[static_cast<std::size_t>(i)] = generate_block(missing[static_cast<std::size_t>(i)]);
            }
        });

    std::lock_guard<std::mutex> lock(cache_mutex);
    for (std::size_t i = 0; i < missing.size(); ++i) {
        const Vector2i s = missing[i];
        const int key = s.y * sector_count + s.x;
        if (cache.find(key) != cache.end()) continue;
        while (cache.size() >= cache_limit && !recent.empty()) {
            cache.erase(recent.front());
            recent.pop_front();
        }
        recent.push_back(key);
        cache.emplace(key, Cached{std::move(built[i]), std::prev(recent.end())});
    }
}

SectorGridSnapshot City::snapshot_sectors(Rect2i area) {
    SectorGridSnapshot snap;
    if (area.size.x <= 0 || area.size.y <= 0) return snap;
    prewarm_sectors(area);
    const int min_x = std::clamp(area.position.x, 0, city_size - 1);
    const int min_y = std::clamp(area.position.y, 0, city_size - 1);
    const int max_x = std::clamp(area.position.x + area.size.x - 1, 0, city_size - 1);
    const int max_y = std::clamp(area.position.y + area.size.y - 1, 0, city_size - 1);
    snap.min_sx = min_x / sector_size;
    snap.min_sy = min_y / sector_size;
    const int max_sx = max_x / sector_size;
    const int max_sy = max_y / sector_size;
    snap.cols = max_sx - snap.min_sx + 1;
    snap.rows = max_sy - snap.min_sy + 1;
    snap.blocks.resize(static_cast<std::size_t>(snap.cols * snap.rows));
    for (int sy = snap.min_sy; sy <= max_sy; ++sy) {
        for (int sx = snap.min_sx; sx <= max_sx; ++sx) {
            snap.blocks[static_cast<std::size_t>((sy - snap.min_sy) * snap.cols + (sx - snap.min_sx))] = block_at({sx, sy});
        }
    }
    return snap;
}

std::size_t City::cached_sector_count() const {
    std::lock_guard<std::mutex> lock(cache_mutex);
    return cache.size();
}

std::size_t City::memory_bytes() const {
    std::lock_guard<std::mutex> lock(cache_mutex);
    std::size_t total = cache.size() * (sizeof(int) + sizeof(Cached) + 32u);
    for (const auto &entry : cache) {
        if (entry.second.block) {
            total += block_memory_bytes(*entry.second.block);
        }
    }
    return total;
}

std::size_t City::trim_cache(std::size_t keep_recent) {
    std::lock_guard<std::mutex> lock(cache_mutex);
    std::size_t freed = 0;
    while (cache.size() > keep_recent && !recent.empty()) {
        const int key = recent.front();
        recent.pop_front();
        const auto it = cache.find(key);
        if (it != cache.end()) {
            if (it->second.block) {
                freed += block_memory_bytes(*it->second.block);
            }
            freed += sizeof(int) + sizeof(Cached) + 32u;
            cache.erase(it);
        }
    }
    return freed;
}

char City::tile(Vector2i p, int floor) {
    if (!in_city(p)) return ' ';
    const auto s = sector_at(p);
    const auto local = p - s * sector_size;
    const auto block = block_at(s);
    return level_tiles(*block, floor)[local.y * sector_size + local.x];
}

int City::lighting_column(Vector2i p, int floor, int layers) {
    if (!in_city(p)) return 0;
    const auto s = sector_at(p);
    const auto local = p - s * sector_size;
    const auto block = block_at(s);
    const int i = local.y * sector_size + local.x;
    int result = 0;
    for (int layer = 0; layer < layers && layer < 4 && floor <= std::numeric_limits<int>::max() - layer; ++layer) {
        const int z = floor + layer;
        const bool enclosed = enclosed_at(*block, z, i);
        bool ceiling = enclosed;
        if (z < std::numeric_limits<int>::max() && enclosed_at(*block, z + 1, i)) {
            const char upper = level_tiles(*block, z + 1)[i];
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
    const auto block = block_at(s);
    return level_surfaces(*block, floor)[local.y * sector_size + local.x];
}

String City::location(Vector2i p) {
    if (!in_city(p)) return String();
    const YangzhouWorldData &yz = yangzhou_world_data();
    // Reverse order so specific buildings/bridges take priority over broad canal/district rects
    for (auto it = yz.zones.rbegin(); it != yz.zones.rend(); ++it) {
        if (it->bounds.has_point(p)) {
            return String::utf8(it->name);
        }
    }
    if (p.x >= 117 && p.x <= 122 && p.y > 125 && p.y < 208) return String::utf8("南大街");
    if (p.x >= 117 && p.x <= 122 && p.y > 28 && p.y < 114) return String::utf8("北大街");
    if (p.y >= 117 && p.y <= 122 && p.x > 125 && p.x < 212) return String::utf8("东关大街");
    if (p.y >= 117 && p.y <= 122 && p.x > 28 && p.x < 114) return String::utf8("西市大街");
    if (p.x >= 25 && p.x <= 214 && p.y >= 25 && p.y <= 214) {
        if (p.x < 95 && p.y < 78) return String::utf8("翠微湖坊");
        if (p.x >= 146 && p.y < 118) return String::utf8("仁丰里");
        if (p.x >= 146 && p.y >= 122) return String::utf8("东关水市坊");
        if (p.x < 116 && p.y < 146) return String::utf8("西市武坊");
        if (p.x < 116 && p.y >= 146) return String::utf8("南水烟火坊");
        if (p.y < 105) return String::utf8("府前文昌坊");
        return String::utf8("中街市井坊");
    }
    return String::utf8("沧灵城郊");
}

Dictionary City::landmarks() const {
    Dictionary result;
    result[Vector2i(120, 212)] = String::utf8("沧灵南门");
    result[Vector2i(120, 193)] = String::utf8("南门石拱桥");
    result[Vector2i(120, 120)] = String::utf8("沧灵中央广场");
    result[Vector2i(127, 157)] = String::utf8("醉仙楼");
    result[Vector2i(112, 157)] = String::utf8("王记铁匠铺");
    result[Vector2i(113, 130)] = String::utf8("利源当铺");
    result[Vector2i(130, 113)] = String::utf8("回春堂药铺");
    result[Vector2i(138, 113)] = String::utf8("通济钱庄");
    result[Vector2i(136, 125)] = String::utf8("福兴杂货铺");
    result[Vector2i(102, 126)] = String::utf8("扬威武馆");
    result[Vector2i(101, 112)] = String::utf8("镇远镖局");
    result[Vector2i(112, 108)] = String::utf8("悦来客栈");
    result[Vector2i(120, 88)]  = String::utf8("文昌阁");
    result[Vector2i(130, 89)]  = String::utf8("文昌书院");
    result[Vector2i(120, 40)]  = String::utf8("沧灵府衙");
    result[Vector2i(178, 126)] = String::utf8("春风茶馆");
    result[Vector2i(167, 166)] = String::utf8("水埠码头");
    result[Vector2i(61,  52)]  = String::utf8("翠微湖·五亭桥");
    result[Vector2i(155, 157)] = String::utf8("虹桥");
    return result;
}
}
