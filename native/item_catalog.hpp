#pragma once

#include <array>
#include <cstdint>
#include <godot_cpp/variant/vector2i.hpp>

namespace cangling {

inline constexpr int kItemCount = 32;
using ItemCounts = std::array<int, kItemCount>;

enum class ItemCategory : std::uint8_t {
    Bedding = 0,
    Clothing = 1,
    Food = 2,
    Drink = 3,
    Misc = 4,
};

enum class WearSlot : std::uint8_t {
    None = 0,
    Head = 1,
    Torso = 2,
    Legs = 3,
    Feet = 4,
    Outer = 5,
    Back = 6,
};

struct ItemDef {
    const char *key;
    const char *tile;
    const char *name;
    ItemCategory category;
    int weight_g;
    int volume_ml;
    int kcal;
    int quench;
    int joy;
    WearSlot slot;
    int warmth;
    int encumbrance;
    int storage_ml;
    const char *overlay; // paper-doll overlay ID when worn (empty if none)
    const char *desc;
};

const std::array<ItemDef, kItemCount> &item_catalog();
int find_item_by_key(const char *key);
const char *category_label(ItemCategory cat);
const char *wear_slot_label(WearSlot slot);

// CCB-style contextual loot group generator (beds -> pillow/quilt/sheet, wardrobes -> clothing,
// kitchens -> food/tea/water, desks/shelves -> scrolls/ink, apothecary -> herbs/medicine, crates -> supplies).
ItemCounts spawn_contextual_items(char tile, char surface, std::uint32_t seed, godot::Vector2i p, int floor);

} // namespace cangling
