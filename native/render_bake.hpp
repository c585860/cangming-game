#pragma once

#include "ccb_overmap.hpp"
#include "city.hpp"
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/string.hpp>
#include <unordered_map>
#include <unordered_set>
#include <cstdint>

namespace cangling {

// Multi-core C++ render-data baker: builds GPU-ready geometry, bounce albedo, river field,
// sky transport, ambient lightmap, and point-light slot/source textures in parallel via ThreadPool.
class RenderBaker {
public:
    static godot::Dictionary bake_region(City &city, const std::unordered_set<int64_t> &doors,
        const std::unordered_map<int64_t, char> &overrides,
        Rect2i area, int z, int layers, const String &season, double &out_bake_ms,
        CcbOvermapManager *overmap = nullptr);

    static godot::PackedByteArray bake_ambient(City &city, const std::unordered_set<int64_t> &doors,
        const std::unordered_map<int64_t, char> &overrides,
        Rect2i area, Rect2i region, int z, float outdoor_light, float sun_warmth,
        CcbOvermapManager *overmap = nullptr);

    static godot::Dictionary bake_point_lights(City &city, const std::unordered_set<int64_t> &doors,
        const std::unordered_map<int64_t, char> &overrides,
        Rect2i area, Rect2i region, int z, const godot::Dictionary &sites, int seed,
        CcbOvermapManager *overmap = nullptr);
};

} // namespace cangling
