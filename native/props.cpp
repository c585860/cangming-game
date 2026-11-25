#include "world.hpp"

namespace cangling {
String CanglingWorld::generated_prop(Vector2i p) {
    if (city.layout < 2 || !in_city(p)) return {};
    const ItemCounts spawned = spawn_contextual_items(effective_tile(p, floor), city.surface(p, floor), seed, p, floor);
    const auto &cat = item_catalog();
    for (int i = 0; i < item_types; ++i) {
        if (spawned[i] > 0) return String(cat[i].key);
    }
    return {};
}

String CanglingWorld::fixture_contents(Vector2i p) {
    const auto items = items_on(p);
    String result;
    for (int i = 0; i < item_types; ++i) {
        if (!items[i]) continue;
        if (!result.is_empty()) result += String::utf8("、");
        result += item_name(i) + String::utf8(" × ") + String::num_int64(items[i]);
    }
    return result;
}
}
