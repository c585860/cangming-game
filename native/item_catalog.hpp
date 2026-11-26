#pragma once

#include <array>
#include <cstdint>
#include <godot_cpp/variant/vector2i.hpp>

namespace cangling {

inline constexpr int kItemCount = 70;
using ItemCounts = std::array<int, kItemCount>;

enum class ItemCategory : std::uint8_t {
    Bedding = 0,
    Clothing = 1,
    Food = 2,
    Drink = 3,
    Tool = 4,
    Book = 5,
    Medical = 6,
    Misc = 7,
    Weapon = 8,
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
    int bash_dmg;
    WearSlot slot;
    int warmth;
    int encumbrance;
    int storage_ml;
    const char *overlay;
    const char *desc;
    int base_price;           // Standard shop price in copper coins
    int rain_resist;          // 0..100 rain resistance when worn
    const char *weapon_skill; // "" or base weapon skill id ("sword", "blade", etc.)
    const char *book_skill;   // "" or skill id taught by studying this book
    int book_min_lit;         // Min literate level required to study
    int book_max_lv;          // Max skill level studyable from this book
};

const std::array<ItemDef, kItemCount> &item_catalog();
int find_item_by_key(const char *key);
const char *category_label(ItemCategory cat);
const char *wear_slot_label(WearSlot slot);

// CCB SUS-style dense multi-item contextual loot group generator.
ItemCounts spawn_contextual_items(char tile, char surface, std::uint32_t seed, godot::Vector2i p, int floor);

} // namespace cangling
