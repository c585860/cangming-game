#include "ccb_overmap.hpp"
#include "ccb_vanilla.hpp"
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <algorithm>
#include <cmath>
#include <mutex>

namespace cangling {
using namespace godot;

namespace {

std::uint32_t mix_hash(std::uint32_t a, std::uint32_t b, std::uint32_t c) {
    std::uint32_t h = a * 0x9e3779b1u ^ b * 0x85ebca77u ^ c * 0xc2b2ae3du;
    h ^= h >> 15;
    h *= 0x2c1b3c6du;
    h ^= h >> 12;
    h *= 0x297a2d39u;
    h ^= h >> 15;
    return h;
}

struct TemplateLibrary {
    bool loaded = false;
    std::mutex mu;
    std::unordered_map<int, std::vector<OmtTemplate>> by_kind;
};

TemplateLibrary &tpl_lib() {
    static TemplateLibrary lib;
    return lib;
}

bool str_contains(const std::string &s, const char *sub) {
    return s.find(sub) != std::string::npos;
}

char terrain_and_furn_to_compat(const std::string &ter, const std::string &furn) {
    // Doors & Windows
    if (str_contains(ter, "t_door_o")) return 'o';
    if (str_contains(ter, "t_door")) return 'D';
    if (str_contains(ter, "t_window_open")) return 'O';
    if (str_contains(ter, "t_window_frame") || str_contains(ter, "t_window_empty")) return '%';
    if (str_contains(ter, "t_window")) return 'w';
    // Walls & Obstacles
    if (str_contains(ter, "wall") || str_contains(ter, "t_rock")) return '#';
    if (str_contains(ter, "t_tree")) return 'Y';
    if (str_contains(ter, "t_shrub") || str_contains(ter, "t_underbrush")) return 'g';
    if (str_contains(ter, "t_fence") || str_contains(ter, "t_chainfence") || str_contains(ter, "t_railing")) return 'f';
    if (str_contains(ter, "t_water")) return '~';
    if (str_contains(ter, "t_stairs_down")) return 'v';
    if (str_contains(ter, "t_stairs_up") || str_contains(ter, "t_ladder")) return '^';

    // Furniture mapping for lighting / walkability / interaction compatibility
    if (!furn.empty()) {
        if (str_contains(furn, "bed")) return 'b';
        if (str_contains(furn, "chair") || str_contains(furn, "stool")) return 'q';
        if (str_contains(furn, "bench") || str_contains(furn, "sofa") || str_contains(furn, "couch")) return 'S';
        if (str_contains(furn, "table")) return 't';
        if (str_contains(furn, "counter")) return 'k';
        if (str_contains(furn, "rack") || str_contains(furn, "shelf") || str_contains(furn, "bookcase")) return 'r';
        if (str_contains(furn, "locker") || str_contains(furn, "cupboard") || str_contains(furn, "dresser") || str_contains(furn, "fridge")) return 'F';
        if (str_contains(furn, "crate")) return 'C';
        if (str_contains(furn, "oven") || str_contains(furn, "stove")) return 'h';
        if (str_contains(furn, "sink") || str_contains(furn, "toilet") || str_contains(furn, "bathtub")) return 'u';
        if (str_contains(furn, "trash")) return 'c';
    }

    // Open floors & outdoor grounds
    if (str_contains(ter, "pavement") || str_contains(ter, "asphalt")) return '=';
    if (str_contains(ter, "sidewalk") || str_contains(ter, "concrete")) return ':';
    if (str_contains(ter, "floor") || str_contains(ter, "linoleum") || str_contains(ter, "carpet") || str_contains(ter, "thconc")) return 'i';
    return '.';
}

bool is_indoor_terrain(const std::string &ter) {
    return str_contains(ter, "t_floor") || str_contains(ter, "t_linoleum") ||
           str_contains(ter, "t_carpet") || str_contains(ter, "t_thconc_floor") ||
           str_contains(ter, "t_stairs") || str_contains(ter, "wall") ||
           str_contains(ter, "t_door") || str_contains(ter, "t_window");
}

} // namespace

int CcbOvermapManager::floor_div(int a, int b) {
    int q = a / b;
    int r = a % b;
    if (r != 0 && ((r < 0) != (b < 0))) --q;
    return q;
}

int CcbOvermapManager::floor_mod(int a, int b) {
    int r = a % b;
    if (r < 0) r += b;
    return r;
}

int64_t CcbOvermapManager::pair_key(int x, int y) {
    return (static_cast<int64_t>(x) << 32) | static_cast<std::uint32_t>(y);
}

Vector2i CcbOvermapManager::world_to_omt(Vector2i wp) {
    return {floor_div(wp.x, kOmtSize), floor_div(wp.y, kOmtSize)};
}

Vector2i CcbOvermapManager::world_to_local(Vector2i wp) {
    return {floor_mod(wp.x, kOmtSize), floor_mod(wp.y, kOmtSize)};
}

OmtKind CcbOvermapManager::parse_omt_kind(const std::string &name) {
    if (name == "shelter") return OmtKind::Shelter;
    if (name == "house") return OmtKind::House;
    if (name == "s_grocery") return OmtKind::Grocery;
    if (name == "pharmacy" || name == "hospital") return OmtKind::Pharmacy;
    if (name == "s_hardware") return OmtKind::Hardware;
    if (name == "s_gun") return OmtKind::GunStore;
    if (name == "police_station") return OmtKind::PoliceStation;
    if (name == "fire_station") return OmtKind::FireStation;
    if (name == "library") return OmtKind::Library;
    if (name == "garage_gas") return OmtKind::GasStation;
    if (name == "warehouse") return OmtKind::Warehouse;
    if (name == "toxic_dump") return OmtKind::ToxicDump;
    if (name == "forest_camp") return OmtKind::ForestCamp;
    if (name == "forest") return OmtKind::Forest;
    if (name == "road") return OmtKind::Road;
    if (name == "river") return OmtKind::River;
    return OmtKind::Shelter;
}

const char *CcbOvermapManager::omt_kind_name_cn(OmtKind k) {
    switch (k) {
        case OmtKind::Field:         return "荒野田野";
        case OmtKind::Forest:        return "新英格兰森林";
        case OmtKind::ForestCamp:    return "林地营地";
        case OmtKind::River:         return "宽阔河流";
        case OmtKind::Road:          return "柏油公路";
        case OmtKind::Bridge:        return "跨河公路桥";
        case OmtKind::Shelter:       return "应急避难所 (Evac Shelter)";
        case OmtKind::House:         return "城镇民宅";
        case OmtKind::Grocery:       return "生鲜杂货超市";
        case OmtKind::Pharmacy:      return "城镇药房";
        case OmtKind::Hardware:      return "五金建材店";
        case OmtKind::GunStore:      return "枪械军品店";
        case OmtKind::PoliceStation: return "城镇警察局";
        case OmtKind::FireStation:   return "消防救援站";
        case OmtKind::Library:       return "公共图书馆";
        case OmtKind::GasStation:    return "加油维修站";
        case OmtKind::Warehouse:     return "货运仓库";
        case OmtKind::ToxicDump:     return "核废料与生化倾倒场";
    }
    return "荒野";
}

char CcbOvermapManager::omt_kind_glyph(OmtKind k, std::uint8_t road_mask) {
    switch (k) {
        case OmtKind::Field:         return '.';
        case OmtKind::Forest:        return 'F';
        case OmtKind::ForestCamp:    return 'C';
        case OmtKind::River:         return '~';
        case OmtKind::Bridge:        return '=';
        case OmtKind::Road: {
            const bool ns = (road_mask & 1) || (road_mask & 4);
            const bool ew = (road_mask & 2) || (road_mask & 8);
            if (ns && ew) return '+';
            if (ns) return '|';
            return '-';
        }
        case OmtKind::Shelter:       return '^';
        case OmtKind::House:         return 'H';
        case OmtKind::Grocery:       return 'g';
        case OmtKind::Pharmacy:      return 'p';
        case OmtKind::Hardware:      return 'h';
        case OmtKind::GunStore:      return 'G';
        case OmtKind::PoliceStation: return 'P';
        case OmtKind::FireStation:   return 'f';
        case OmtKind::Library:       return 'L';
        case OmtKind::GasStation:    return 's';
        case OmtKind::Warehouse:     return 'W';
        case OmtKind::ToxicDump:     return 'X';
    }
    return '.';
}

const char *CcbOvermapManager::omt_kind_color_hex(OmtKind k) {
    switch (k) {
        case OmtKind::Field:         return "#4c6b3c";
        case OmtKind::Forest:        return "#27582a";
        case OmtKind::ForestCamp:    return "#6fa857";
        case OmtKind::River:         return "#2a69a8";
        case OmtKind::Bridge:        return "#9aa4b0";
        case OmtKind::Road:          return "#7a8088";
        case OmtKind::Shelter:       return "#f2e8cf";
        case OmtKind::House:         return "#74b85e";
        case OmtKind::Grocery:       return "#e5c158";
        case OmtKind::Pharmacy:      return "#e66e8a";
        case OmtKind::Hardware:      return "#c88a4b";
        case OmtKind::GunStore:      return "#d9534f";
        case OmtKind::PoliceStation: return "#4a8fe7";
        case OmtKind::FireStation:   return "#e05a3a";
        case OmtKind::Library:       return "#a982e3";
        case OmtKind::GasStation:    return "#d4a64a";
        case OmtKind::Warehouse:     return "#9098a4";
        case OmtKind::ToxicDump:     return "#8ce639";
    }
    return "#556655";
}

void CcbOvermapManager::ensure_templates_loaded() {
    auto &lib = tpl_lib();
    std::lock_guard<std::mutex> lock(lib.mu);
    if (lib.loaded) return;
    lib.loaded = true;

    const String path = String("res://packs/cataclysm/vanilla/mapgen_omt.json");
    if (!FileAccess::file_exists(path)) return;
    const String text = FileAccess::get_file_as_string(path);
    const Variant parsed = JSON::parse_string(text);
    if (parsed.get_type() != Variant::DICTIONARY) return;
    const Dictionary root = parsed;
    const Array templates = root.get("templates", Array());

    for (int i = 0; i < templates.size(); ++i) {
        if (templates[i].get_type() != Variant::DICTIONARY) continue;
        const Dictionary td = templates[i];
        OmtTemplate tpl;
        tpl.id = String(td.get("id", String())).utf8().get_data();
        const std::string kind_s = String(td.get("kind", String())).utf8().get_data();
        tpl.kind = parse_omt_kind(kind_s);

        const Array tleg = td.get("ter_legend", Array());
        for (int j = 0; j < tleg.size(); ++j) {
            tpl.ter_legend.emplace_back(String(tleg[j]).utf8().get_data());
        }
        const Array fleg = td.get("furn_legend", Array());
        for (int j = 0; j < fleg.size(); ++j) {
            tpl.furn_legend.emplace_back(String(fleg[j]).utf8().get_data());
        }
        if (tpl.ter_legend.empty()) tpl.ter_legend.emplace_back("t_grass");
        if (tpl.furn_legend.empty()) tpl.furn_legend.emplace_back("");

        const Array tarr = td.get("t", Array());
        const Array farr = td.get("f", Array());
        if (tarr.size() != kOmtSize * kOmtSize || farr.size() != kOmtSize * kOmtSize) continue;
        for (int idx = 0; idx < kOmtSize * kOmtSize; ++idx) {
            const int ti = std::clamp(static_cast<int>(tarr[idx]), 0, static_cast<int>(tpl.ter_legend.size()) - 1);
            const int fi = std::clamp(static_cast<int>(farr[idx]), 0, static_cast<int>(tpl.furn_legend.size()) - 1);
            tpl.ter_idx[static_cast<std::size_t>(idx)] = static_cast<std::uint16_t>(ti);
            tpl.furn_idx[static_cast<std::size_t>(idx)] = static_cast<std::uint16_t>(fi);
        }

        const Array st = td.get("start", Array());
        if (st.size() >= 2) {
            tpl.start_local = Vector2i(std::clamp(static_cast<int>(st[0]), 1, kOmtSize - 2),
                                       std::clamp(static_cast<int>(st[1]), 1, kOmtSize - 2));
        }

        const Array sp = td.get("spawns", Array());
        for (int s = 0; s < sp.size(); ++s) {
            if (sp[s].get_type() != Variant::DICTIONARY) continue;
            const Dictionary sd = sp[s];
            OmtItemSpawn isp;
            isp.lx = std::clamp(static_cast<int>(sd.get("x", 12)), 0, kOmtSize - 1);
            isp.ly = std::clamp(static_cast<int>(sd.get("y", 12)), 0, kOmtSize - 1);
            const Array items = sd.get("items", Array());
            for (int k = 0; k < items.size(); ++k) {
                isp.items.emplace_back(String(items[k]).utf8().get_data());
            }
            if (!isp.items.empty()) tpl.spawns.push_back(std::move(isp));
        }

        lib.by_kind[static_cast<int>(tpl.kind)].push_back(std::move(tpl));
    }
}

void CcbOvermapManager::reset(std::uint32_t seed, int city_size_opt, int city_spacing_opt, float monster_rate) {
    ensure_templates_loaded();
    std::lock_guard<std::mutex> lock(mutex_);
    seed_ = seed;
    city_size_opt_ = std::clamp(city_size_opt, 3, 16);
    city_spacing_opt_ = std::clamp(city_spacing_opt, 2, 8);
    monster_rate_ = std::clamp(monster_rate, 0.25f, 4.0f);
    om_cache_.clear();
    chunk_cache_.clear();
    chunk_lru_.clear();
}

std::shared_ptr<const OvermapRegion> CcbOvermapManager::get_overmap_locked(int om_x, int om_y) {
    const int64_t k = pair_key(om_x, om_y);
    if (const auto it = om_cache_.find(k); it != om_cache_.end()) {
        return it->second;
    }

    auto om = std::make_shared<OvermapRegion>();
    om->om_coord = {om_x, om_y};
    const std::uint32_t om_seed = mix_hash(seed_, static_cast<std::uint32_t>(om_x + 10007), static_cast<std::uint32_t>(om_y + 20011));

    auto at = [&](int x, int y) -> OmtCell & {
        return om->cells[static_cast<std::size_t>(y * kOvermapSize + x)];
    };

    // 1. Base wilderness: fields & organic forests
    for (int y = 0; y < kOvermapSize; ++y) {
        for (int x = 0; x < kOvermapSize; ++x) {
            const double nx = static_cast<double>(om_x * kOvermapSize + x) * 0.09;
            const double ny = static_cast<double>(om_y * kOvermapSize + y) * 0.09;
            const double forest_wave = std::sin(nx + std::cos(ny * 0.7)) + std::cos(ny * 0.85 - nx * 0.5);
            OmtCell &c = at(x, y);
            const std::uint32_t h = mix_hash(om_seed, static_cast<std::uint32_t>(x), static_cast<std::uint32_t>(y));
            if (forest_wave > 0.35) {
                c.kind = ((h % 85u) == 0u) ? OmtKind::ForestCamp : OmtKind::Forest;
            } else {
                c.kind = OmtKind::Field;
            }
            c.variant = static_cast<std::uint8_t>(h & 0xFFu);
            c.rot = static_cast<std::uint8_t>((h >> 8) & 3u);
        }
    }

    // 2. Meandering river flowing roughly N->S across every Overmap
    int river_x = 132 + static_cast<int>(om_seed % 26u) - 13;
    for (int y = 0; y < kOvermapSize; ++y) {
        const std::uint32_t rh = mix_hash(om_seed ^ 0x55AAu, static_cast<std::uint32_t>(y), 7u);
        if ((rh % 5u) == 0u && river_x > 110) --river_x;
        else if ((rh % 5u) == 1u && river_x < 164) ++river_x;
        for (int dx = -1; dx <= 1; ++dx) {
            const int rx = std::clamp(river_x + dx, 2, kOvermapSize - 3);
            at(rx, y).kind = OmtKind::River;
        }
    }

    // 3. Place organic New England towns (guaranteed primary town near center of every Overmap)
    struct Town { int cx, cy, rad; };
    std::vector<Town> towns;
    const int base_rad = std::clamp(city_size_opt_, 4, 14);
    // Primary town near (90, 90) so (0,0) Overmap always has a rich town right beside the starting Evac Shelter!
    towns.push_back({90, 90, base_rad});
    const int extra_towns = std::clamp(7 - city_spacing_opt_, 2, 5);
    for (int i = 0; i < extra_towns; ++i) {
        const std::uint32_t th = mix_hash(om_seed, static_cast<std::uint32_t>(i + 1), 991u);
        int cx = 22 + static_cast<int>(th % 136u);
        int cy = 22 + static_cast<int>((th >> 10) % 136u);
        // Avoid spawning right inside the river
        if (std::abs(cx - river_x) < 12) cx = (cx < river_x) ? std::max(18, river_x - 16) : std::min(160, river_x + 16);
        int rad = std::max(4, base_rad - 2 + static_cast<int>((th >> 20) % 4u));
        towns.push_back({cx, cy, rad});
    }

    // 4. Lay interstate highways connecting Overmap edges (x=90, y=90) + town centers
    auto carve_road = [&](int x0, int y0, int x1, int y1) {
        int x = x0, y = y0;
        while (x != x1) {
            OmtCell &c = at(x, y);
            c.kind = (c.kind == OmtKind::River || c.kind == OmtKind::Bridge) ? OmtKind::Bridge : OmtKind::Road;
            x += (x1 > x) ? 1 : -1;
        }
        while (y != y1) {
            OmtCell &c = at(x, y);
            c.kind = (c.kind == OmtKind::River || c.kind == OmtKind::Bridge) ? OmtKind::Bridge : OmtKind::Road;
            y += (y1 > y) ? 1 : -1;
        }
        OmtCell &endc = at(x1, y1);
        endc.kind = (endc.kind == OmtKind::River || endc.kind == OmtKind::Bridge) ? OmtKind::Bridge : OmtKind::Road;
    };

    carve_road(0, 90, kOvermapSize - 1, 90);
    carve_road(90, 0, 90, kOvermapSize - 1);
    for (const auto &t : towns) {
        carve_road(90, 90, t.cx, t.cy);
    }

    // 5. Build town street grids & assign authentic commercial/residential/outskirt OMT buildings
    static constexpr OmtKind kCommercialPool[] = {
        OmtKind::Grocery, OmtKind::Pharmacy, OmtKind::Hardware, OmtKind::PoliceStation,
        OmtKind::FireStation, OmtKind::Library, OmtKind::GunStore, OmtKind::GasStation, OmtKind::Warehouse
    };

    for (std::size_t ti = 0; ti < towns.size(); ++ti) {
        const auto &t = towns[ti];
        const int r = t.rad;
        for (int dy = -r; dy <= r; ++dy) {
            for (int dx = -r; dx <= r; ++dx) {
                const int gx = t.cx + dx;
                const int gy = t.cy + dy;
                if (gx < 2 || gy < 2 || gx >= kOvermapSize - 2 || gy >= kOvermapSize - 2) continue;
                const int dist = std::abs(dx) + std::abs(dy);
                if (dist > r + 2) continue;
                OmtCell &c = at(gx, gy);
                if (c.kind == OmtKind::River || c.kind == OmtKind::Bridge) continue;

                // Vanilla-style 3-OMT spaced city blocks with asphalt streets
                if ((dx % 3) == 0 || (dy % 3) == 0) {
                    c.kind = OmtKind::Road;
                    continue;
                }

                const std::uint32_t bh = mix_hash(om_seed, static_cast<std::uint32_t>(gx * 73), static_cast<std::uint32_t>(gy * 137));
                c.variant = static_cast<std::uint8_t>(bh & 0xFFu);
                // Face nearest road
                if ((dy % 3) == 1) c.rot = 0;
                else if ((dy % 3) == -1) c.rot = 2;
                else if ((dx % 3) == 1) c.rot = 3;
                else c.rot = 1;

                if (dist <= r / 2 + 1) {
                    c.kind = kCommercialPool[(bh >> 4) % 9u];
                } else {
                    c.kind = ((bh % 7u) == 0u) ? kCommercialPool[(bh >> 8) % 9u] : OmtKind::House;
                }
            }
        }

        // Guaranteed Evacuation Shelter on the town's northern/eastern outskirts along highway!
        const int sh_x = std::clamp(t.cx + 1, 3, kOvermapSize - 4);
        const int sh_y = std::clamp(t.cy - r - 2, 3, kOvermapSize - 4);
        if (at(sh_x, sh_y).kind != OmtKind::River) {
            at(sh_x, sh_y).kind = OmtKind::Shelter;
            at(sh_x, sh_y).rot = 0;
            at(sh_x, sh_y).variant = static_cast<std::uint8_t>(ti % 3u);
        }
        // Guaranteed Toxic Waste Dump / Biohazard Site on the far southern outskirts!
        const int tx_x = std::clamp(t.cx - r - 3, 3, kOvermapSize - 4);
        const int tx_y = std::clamp(t.cy + r + 3, 3, kOvermapSize - 4);
        if (at(tx_x, tx_y).kind != OmtKind::River) {
            at(tx_x, tx_y).kind = OmtKind::ToxicDump;
            at(tx_x, tx_y).rot = 0;
        }
    }

    // 6. Compute road connectivity bitmasks for every OMT
    for (int y = 0; y < kOvermapSize; ++y) {
        for (int x = 0; x < kOvermapSize; ++x) {
            OmtCell &c = at(x, y);
            if (c.kind != OmtKind::Road && c.kind != OmtKind::Bridge) continue;
            auto is_road = [&](int nx, int ny) {
                if (nx < 0 || ny < 0 || nx >= kOvermapSize || ny >= kOvermapSize) return true;
                const OmtKind nk = at(nx, ny).kind;
                return nk == OmtKind::Road || nk == OmtKind::Bridge;
            };
            std::uint8_t mask = 0;
            if (is_road(x, y - 1)) mask |= 1;
            if (is_road(x + 1, y)) mask |= 2;
            if (is_road(x, y + 1)) mask |= 4;
            if (is_road(x - 1, y)) mask |= 8;
            c.road_mask = mask;
        }
    }

    // Keep at most 16 cached overmaps (~1.5 MB each is tiny, actually 180*180*4 = 129 KB!)
    if (om_cache_.size() >= 24) {
        om_cache_.erase(om_cache_.begin());
    }
    om_cache_[k] = om;
    return om;
}

OmtCell CcbOvermapManager::cell_at_omt(Vector2i omt_coord) {
    const int om_x = floor_div(omt_coord.x, kOvermapSize);
    const int om_y = floor_div(omt_coord.y, kOvermapSize);
    const int lx = floor_mod(omt_coord.x, kOvermapSize);
    const int ly = floor_mod(omt_coord.y, kOvermapSize);
    std::lock_guard<std::mutex> lock(mutex_);
    const auto om = get_overmap_locked(om_x, om_y);
    return om->cells[static_cast<std::size_t>(ly * kOvermapSize + lx)];
}

std::shared_ptr<OmtChunk> CcbOvermapManager::build_chunk(Vector2i omt_coord, const OmtCell &cell) const {
    auto ch = std::make_shared<OmtChunk>();
    ch->omt_coord = omt_coord;
    ch->kind = cell.kind;
    ch->terrain.fill("t_grass");
    ch->furniture.fill("");
    ch->compat_tile.fill('.');
    ch->enclosed.fill(0);
    ch->start_local = {12, 12};
    ch->base_rad = (cell.kind == OmtKind::ToxicDump) ? 18.0f : 0.0f;

    const std::uint32_t h_omt = mix_hash(seed_, static_cast<std::uint32_t>(omt_coord.x + 50000), static_cast<std::uint32_t>(omt_coord.y + 50000));
    const Vector2i world_origin(omt_coord.x * kOmtSize, omt_coord.y * kOmtSize);

    auto set_cell = [&](int x, int y, const std::string &ter, const std::string &furn = "") {
        const std::size_t idx = static_cast<std::size_t>(y * kOmtSize + x);
        ch->terrain[idx] = ter;
        ch->furniture[idx] = furn;
        ch->compat_tile[idx] = terrain_and_furn_to_compat(ter, furn);
        ch->enclosed[idx] = is_indoor_terrain(ter) ? 1 : 0;
    };

    // Check if we have an exported vanilla CCB 24x24 JSON template for this OmtKind!
    auto &lib = tpl_lib();
    const OmtTemplate *tpl = nullptr;
    {
        std::lock_guard<std::mutex> lk(lib.mu);
        const auto it = lib.by_kind.find(static_cast<int>(cell.kind));
        if (it != lib.by_kind.end() && !it->second.empty()) {
            tpl = &it->second[cell.variant % it->second.size()];
        }
    }

    if (tpl != nullptr) {
        const int rot = (cell.kind == OmtKind::Shelter) ? 0 : static_cast<int>(cell.rot & 3u);
        auto rot_xy = [rot](int x, int y) -> Vector2i {
            if (rot == 1) return {kOmtSize - 1 - y, x};
            if (rot == 2) return {kOmtSize - 1 - x, kOmtSize - 1 - y};
            if (rot == 3) return {y, kOmtSize - 1 - x};
            return {x, y};
        };

        for (int y = 0; y < kOmtSize; ++y) {
            for (int x = 0; x < kOmtSize; ++x) {
                const std::size_t src = static_cast<std::size_t>(y * kOmtSize + x);
                const Vector2i dst = rot_xy(x, y);
                const std::string &ter = tpl->ter_legend[tpl->ter_idx[src]];
                const std::string &furn = tpl->furn_legend[tpl->furn_idx[src]];
                set_cell(dst.x, dst.y, ter, furn);
            }
        }
        ch->start_local = rot_xy(tpl->start_local.x, tpl->start_local.y);
        for (const auto &sp : tpl->spawns) {
            OmtItemSpawn rsp;
            const Vector2i dp = rot_xy(sp.lx, sp.ly);
            rsp.lx = dp.x;
            rsp.ly = dp.y;
            rsp.items = sp.items;
            ch->item_spawns.push_back(std::move(rsp));
        }
    } else if (cell.kind == OmtKind::Road || cell.kind == OmtKind::Bridge) {
        const bool is_bridge = (cell.kind == OmtKind::Bridge);
        const bool n = (cell.road_mask & 1) != 0;
        const bool e = (cell.road_mask & 2) != 0;
        const bool s = (cell.road_mask & 4) != 0;
        const bool w = (cell.road_mask & 8) != 0;
        for (int y = 0; y < kOmtSize; ++y) {
            for (int x = 0; x < kOmtSize; ++x) {
                std::string ter = is_bridge ? "t_water_dp" : "t_grass";
                const bool in_ns = (x >= 6 && x <= 17) && ((n && y <= 17) || (s && y >= 6));
                const bool in_ew = (y >= 6 && y <= 17) && ((w && x <= 17) || (e && x >= 6));
                const bool in_side_ns = (x == 5 || x == 18) && ((n && y <= 18) || (s && y >= 5));
                const bool in_side_ew = (y == 5 || y == 18) && ((w && x <= 18) || (e && x >= 5));
                if (in_ns || in_ew) {
                    const bool yellow_ns = (x == 11 || x == 12) && (y % 4 != 0) && in_ns && !in_ew;
                    const bool yellow_ew = (y == 11 || y == 12) && (x % 4 != 0) && in_ew && !in_ns;
                    ter = (yellow_ns || yellow_ew) ? "t_pavement_y" : "t_pavement";
                } else if (in_side_ns || in_side_ew) {
                    ter = is_bridge ? "t_concrete_wall" : "t_sidewalk";
                }
                set_cell(x, y, ter);
            }
        }
    } else if (cell.kind == OmtKind::River) {
        for (int y = 0; y < kOmtSize; ++y) {
            for (int x = 0; x < kOmtSize; ++x) {
                const bool bank = (x <= 1 || x >= kOmtSize - 2);
                set_cell(x, y, bank ? "t_water_sh" : "t_water_dp");
            }
        }
    } else if (cell.kind == OmtKind::Forest) {
        for (int y = 0; y < kOmtSize; ++y) {
            for (int x = 0; x < kOmtSize; ++x) {
                const std::uint32_t th = mix_hash(h_omt, static_cast<std::uint32_t>(x), static_cast<std::uint32_t>(y));
                const int roll = static_cast<int>(th % 100u);
                if (roll < 26) set_cell(x, y, "t_tree");
                else if (roll < 38) set_cell(x, y, "t_shrub");
                else if (roll < 48) set_cell(x, y, "t_dirt");
                else set_cell(x, y, "t_grass");
            }
        }
    } else {
        // Vanilla Field
        for (int y = 0; y < kOmtSize; ++y) {
            for (int x = 0; x < kOmtSize; ++x) {
                const std::uint32_t th = mix_hash(h_omt, static_cast<std::uint32_t>(x), static_cast<std::uint32_t>(y));
                const int roll = static_cast<int>(th % 100u);
                if (roll < 4) set_cell(x, y, "t_shrub");
                else if (roll < 7) set_cell(x, y, "t_tree");
                else if (roll < 15) set_cell(x, y, "t_dirt");
                else set_cell(x, y, "t_grass");
            }
        }
    }

    // Deterministic vanilla monster spawns per OMT (never spawn inside starting Evac Shelter!)
    int mon_count = 0;
    static constexpr const char *kTownZeds[] = {
        "mon_zombie", "mon_zombie", "mon_zombie_runner", "mon_zombie_fat", "mon_zombie_tough", "mon_zombie_crawler"
    };
    static constexpr const char *kCopZeds[] = {"mon_zombie_cop", "mon_zombie_tough", "mon_zombie_runner", "mon_zombie"};
    static constexpr const char *kWildMons[] = {"mon_dog", "mon_zombie", "mon_zombie_crawler"};

    if (cell.kind == OmtKind::Road) mon_count = 2;
    else if (cell.kind == OmtKind::House || cell.kind == OmtKind::Grocery || cell.kind == OmtKind::Pharmacy ||
             cell.kind == OmtKind::Hardware || cell.kind == OmtKind::Library || cell.kind == OmtKind::GasStation ||
             cell.kind == OmtKind::Warehouse) mon_count = 3;
    else if (cell.kind == OmtKind::PoliceStation || cell.kind == OmtKind::FireStation ||
             cell.kind == OmtKind::GunStore || cell.kind == OmtKind::ToxicDump) mon_count = 4;
    else if (cell.kind == OmtKind::Forest || cell.kind == OmtKind::Field) mon_count = ((h_omt % 3u) == 0u) ? 1 : 0;

    mon_count = static_cast<int>(std::round(static_cast<float>(mon_count) * monster_rate_));
    for (int m = 0; m < mon_count; ++m) {
        const std::uint32_t mh = mix_hash(h_omt ^ 0xBEEFu, static_cast<std::uint32_t>(m + 1), 313u);
        for (int tries = 0; tries < 10; ++tries) {
            const int lx = 2 + static_cast<int>((mh + static_cast<std::uint32_t>(tries * 7)) % 20u);
            const int ly = 2 + static_cast<int>(((mh >> 8) + static_cast<std::uint32_t>(tries * 11)) % 20u);
            const std::size_t idx = static_cast<std::size_t>(ly * kOmtSize + lx);
            if (!is_terrain_walkable(ch->terrain[idx], ch->furniture[idx])) continue;
            MonsterSpawn ms;
            if (cell.kind == OmtKind::PoliceStation || cell.kind == OmtKind::ToxicDump) {
                ms.species_id = kCopZeds[(mh >> 16) % 4u];
            } else if (cell.kind == OmtKind::Forest || cell.kind == OmtKind::Field) {
                ms.species_id = kWildMons[(mh >> 16) % 3u];
            } else {
                ms.species_id = kTownZeds[(mh >> 16) % 6u];
            }
            ms.pos = world_origin + Vector2i(lx, ly);
            ms.floor = 0;
            ch->monster_spawns.push_back(std::move(ms));
            break;
        }
    }

    return ch;
}

std::shared_ptr<const OmtChunk> CcbOvermapManager::chunk_at_omt(Vector2i omt_coord) {
    const int64_t ck = pair_key(omt_coord.x, omt_coord.y);
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (const auto it = chunk_cache_.find(ck); it != chunk_cache_.end()) {
            chunk_lru_.splice(chunk_lru_.begin(), chunk_lru_, it->second.it);
            return it->second.chunk;
        }
    }

    const OmtCell cell = cell_at_omt(omt_coord);
    std::shared_ptr<const OmtChunk> built = build_chunk(omt_coord, cell);

    std::lock_guard<std::mutex> lock(mutex_);
    if (const auto it = chunk_cache_.find(ck); it != chunk_cache_.end()) {
        return it->second.chunk;
    }
    chunk_lru_.push_front(ck);
    chunk_cache_.emplace(ck, CachedChunk{built, chunk_lru_.begin()});
    while (chunk_cache_.size() > 160u) {
        const int64_t ev = chunk_lru_.back();
        chunk_lru_.pop_back();
        chunk_cache_.erase(ev);
    }
    return built;
}

std::shared_ptr<const OmtChunk> CcbOvermapManager::chunk_at_world(Vector2i wp) {
    return chunk_at_omt(world_to_omt(wp));
}

std::string CcbOvermapManager::terrain_at(Vector2i wp) {
    const auto ch = chunk_at_world(wp);
    const Vector2i l = world_to_local(wp);
    return ch->terrain[static_cast<std::size_t>(l.y * kOmtSize + l.x)];
}

std::string CcbOvermapManager::furniture_at(Vector2i wp) {
    const auto ch = chunk_at_world(wp);
    const Vector2i l = world_to_local(wp);
    return ch->furniture[static_cast<std::size_t>(l.y * kOmtSize + l.x)];
}

char CcbOvermapManager::compat_tile_at(Vector2i wp) {
    const auto ch = chunk_at_world(wp);
    const Vector2i l = world_to_local(wp);
    return ch->compat_tile[static_cast<std::size_t>(l.y * kOmtSize + l.x)];
}

bool CcbOvermapManager::enclosed_at(Vector2i wp) {
    const auto ch = chunk_at_world(wp);
    const Vector2i l = world_to_local(wp);
    return ch->enclosed[static_cast<std::size_t>(l.y * kOmtSize + l.x)] != 0;
}

float CcbOvermapManager::radiation_at(Vector2i wp) {
    const auto ch = chunk_at_world(wp);
    return ch->base_rad;
}

String CcbOvermapManager::location_name(Vector2i wp) {
    const Vector2i omt = world_to_omt(wp);
    const OmtCell c = cell_at_omt(omt);
    return String::utf8(omt_kind_name_cn(c.kind)) +
           String(" [") + String::num_int64(omt.x) + String(",") + String::num_int64(omt.y) + String("]");
}

bool CcbOvermapManager::is_terrain_walkable(const std::string &ter, const std::string &furn) const {
    if (str_contains(ter, "wall") || str_contains(ter, "t_rock") || str_contains(ter, "t_tree") ||
        str_contains(ter, "t_water_dp") || str_contains(ter, "t_fence") || str_contains(ter, "t_chainfence") ||
        str_contains(ter, "t_window_domestic") || str_contains(ter, "t_window_no_curtains") || ter == "t_window") {
        return false;
    }
    if (!furn.empty()) {
        if (str_contains(furn, "locker") || str_contains(furn, "rack") || str_contains(furn, "shelf") ||
            str_contains(furn, "bookcase") || str_contains(furn, "fridge") || str_contains(furn, "oven") ||
            str_contains(furn, "counter") || str_contains(furn, "crate") || str_contains(furn, "cupboard") ||
            str_contains(furn, "dresser") || str_contains(furn, "sink")) {
            return false;
        }
    }
    return true;
}

bool CcbOvermapManager::is_terrain_opaque(const std::string &ter, const std::string &furn) const {
    if (str_contains(ter, "wall") || str_contains(ter, "t_rock") ||
        (str_contains(ter, "t_door") && !str_contains(ter, "t_door_o")) ||
        str_contains(ter, "t_tree")) {
        return true;
    }
    if (!furn.empty() && (str_contains(furn, "locker") || str_contains(furn, "bookcase") || str_contains(furn, "fridge"))) {
        return true;
    }
    return false;
}

Vector2i CcbOvermapManager::find_scenario_start(const std::string &start_omt_name) {
    const OmtKind target = parse_omt_kind(start_omt_name);
    // Spiral search outward from primary town center (90, 90) on Overmap (0, 0)
    const Vector2i center(90, 90);
    for (int r = 0; r <= 40; ++r) {
        for (int dy = -r; dy <= r; ++dy) {
            for (int dx = -r; dx <= r; ++dx) {
                if (std::abs(dx) != r && std::abs(dy) != r) continue;
                const Vector2i omt = center + Vector2i(dx, dy);
                if (cell_at_omt(omt).kind == target) {
                    const auto ch = chunk_at_omt(omt);
                    Vector2i lp = ch->start_local;
                    if (!is_terrain_walkable(
                            ch->terrain[static_cast<std::size_t>(lp.y * kOmtSize + lp.x)],
                            ch->furniture[static_cast<std::size_t>(lp.y * kOmtSize + lp.x)])) {
                        for (int y = 2; y < kOmtSize - 2; ++y) {
                            for (int x = 2; x < kOmtSize - 2; ++x) {
                                const std::size_t i = static_cast<std::size_t>(y * kOmtSize + x);
                                if (is_terrain_walkable(ch->terrain[i], ch->furniture[i])) {
                                    lp = {x, y};
                                    break;
                                }
                            }
                        }
                    }
                    return omt * kOmtSize + lp;
                }
            }
        }
    }
    return Vector2i(90 * kOmtSize + 12, 90 * kOmtSize + 12);
}

Dictionary CcbOvermapManager::overmap_slice(Vector2i center_omt, int radius) {
    const int r = std::clamp(radius, 3, 28);
    const int side = r * 2 + 1;
    Dictionary out;
    out["center"] = center_omt;
    out["radius"] = r;
    out["side"] = side;
    Array rows;
    Array colors;
    Array names;
    for (int dy = -r; dy <= r; ++dy) {
        String row_str;
        Array crow;
        for (int dx = -r; dx <= r; ++dx) {
            const Vector2i omt = center_omt + Vector2i(dx, dy);
            const OmtCell c = cell_at_omt(omt);
            row_str += String::chr(omt_kind_glyph(c.kind, c.road_mask));
            crow.append(String(omt_kind_color_hex(c.kind)));
        }
        rows.append(row_str);
        colors.append(crow);
    }
    const OmtCell cur = cell_at_omt(center_omt);
    out["rows"] = rows;
    out["colors"] = colors;
    out["current_name"] = String::utf8(omt_kind_name_cn(cur.kind));
    return out;
}

std::size_t CcbOvermapManager::cached_chunk_count() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return chunk_cache_.size();
}

std::size_t CcbOvermapManager::memory_bytes() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return om_cache_.size() * sizeof(OvermapRegion) + chunk_cache_.size() * (sizeof(OmtChunk) + 576 * 32);
}

std::size_t CcbOvermapManager::trim_cache(std::size_t keep_recent) {
    std::lock_guard<std::mutex> lock(mutex_);
    std::size_t freed = 0;
    while (chunk_cache_.size() > keep_recent && !chunk_lru_.empty()) {
        const int64_t ev = chunk_lru_.back();
        chunk_lru_.pop_back();
        if (chunk_cache_.erase(ev) > 0) {
            freed += sizeof(OmtChunk) + 576 * 32;
        }
    }
    return freed;
}

} // namespace cangling
