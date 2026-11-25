#include "world.hpp"

namespace cangling {
String CanglingWorld::generated_prop(Vector2i p) {
    if (city.layout < 2 || !in_city(p)) return {};
    const char tile = city.tile(p,floor);
    const auto roll = sector_seed(seed ^ (floor ? 0xb6a31423u : 0x3280ea56u),p);
    if (tile == 'b' && roll % 3 != 0) return "sheet";
    if (tile == 'k' && city.surface(p,floor) == 'J' && roll % 3 != 0) {
        constexpr std::array food{"apple", "flatbread", "pear"};
        return food[roll/3 % food.size()];
    }
    if (tile == 'K' && roll % 4 != 0) return roll % 3 == 0 ? "herb_bundle" : "clay_bottle";
    if (tile == 't' && roll % 5 == 0) return "pear";
    if (tile == 'F') {
        constexpr std::array clothes{"tunic", "pants", "robe", "boots"};
        const auto cloth = sector_seed(seed ^ (floor ? 0x75cc9414u : 0xdaaf6712u),p);
        if (cloth % 5 != 0) return clothes[cloth/5 % clothes.size()];
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
