#pragma once

#include "character_state.hpp"
#include "item_catalog.hpp"
#include "skills.hpp"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <vector>

namespace cangling {

enum class ShopService : int {
    None = 0,
    Merchant = 1, // Buy goods
    Pawn = 2,     // Buy + Pawn/Sell player items for coins
    Bank = 3,     // Deposit / Withdraw copper coins
    Inn = 4,      // Rent 2F guestroom + buy tea/buns
};

ShopService shop_service_for_npc(const char *npc_id);
godot::Array shop_catalog_for_npc(const char *npc_id, const SkillSet &skills);
godot::String buy_from_npc(const char *npc_id, int item_id, int &coins, ItemCounts &carried, const CharacterState &ch);
godot::String sell_to_npc(const char *npc_id, int item_id, int &coins, ItemCounts &carried, const SkillSet &skills);
godot::String bank_transfer(int amount, bool deposit, int &coins, CharacterState &ch);
godot::String rent_inn_room(int &coins, int current_minutes, CharacterState &ch);

} // namespace cangling
