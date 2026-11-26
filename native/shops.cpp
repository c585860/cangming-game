#include "shops.hpp"
#include <godot_cpp/variant/variant.hpp>
#include <algorithm>
#include <cmath>
#include <cstring>

namespace cangling {
using namespace godot;

namespace {
std::vector<const char *> stock_keys_for(const char *npc_id) {
    if (!npc_id) return {};
    if (std::strcmp(npc_id, "innkeeper") == 0) {
        return {"lion_head", "yangchun_noodles", "rice_bowl", "flatbread", "dried_meat", "pastry", "tea_cup", "daughter_wine", "rice_wine"};
    }
    if (std::strcmp(npc_id, "herbalist") == 0) {
        return {"bandage", "trauma_salve", "qi_powder", "herb_bundle", "herb_tea", "clay_bottle", "book_medicine"};
    }
    if (std::strcmp(npc_id, "blacksmith") == 0) {
        return {"iron_sword", "willow_blade", "waxwood_club", "bamboo_staff", "steel_spear", "leather_whip", "iron_darts", "hatchet", "crowbar", "iron_pot", "tinderbox"};
    }
    if (std::strcmp(npc_id, "scholar") == 0) {
        return {"book_literate", "book_medicine", "book_cooking", "book_smithing", "book_force", "book_sword", "book_unarmed", "book_scroll", "ink_paper"};
    }
    if (std::strcmp(npc_id, "grocer") == 0) {
        return {"straw_hat", "cloak", "winter_coat", "cloth_bag", "pouch", "boots", "oil_lamp", "candle", "tinderbox", "rope", "salt", "noodles", "towel", "soap"};
    }
    if (std::strcmp(npc_id, "waiter") == 0) {
        return {"steamed_bun", "flatbread", "tea_cup", "clean_water", "rice_wine"};
    }
    if (std::strcmp(npc_id, "storyteller") == 0) {
        return {"tea_cup", "pastry", "book_scroll"};
    }
    return {};
}

int sell_value_for(int item_id, const SkillSet &skills) {
    const auto &def = item_catalog()[item_id];
    const double lit_bonus = 1.0 + std::min(0.25, static_cast<double>(skills.level_of("literate")) * 0.01);
    return std::max(1, static_cast<int>(std::round(static_cast<double>(def.base_price) * 0.55 * lit_bonus)));
}
} // namespace

ShopService shop_service_for_npc(const char *npc_id) {
    if (!npc_id) return ShopService::None;
    if (std::strcmp(npc_id, "pawnbroker") == 0) return ShopService::Pawn;
    if (std::strcmp(npc_id, "banker") == 0) return ShopService::Bank;
    if (std::strcmp(npc_id, "waiter") == 0) return ShopService::Inn;
    if (!stock_keys_for(npc_id).empty()) return ShopService::Merchant;
    return ShopService::None;
}

Array shop_catalog_for_npc(const char *npc_id, const SkillSet &skills) {
    Array out;
    const auto keys = stock_keys_for(npc_id);
    const auto &cat = item_catalog();
    const double discount = 1.0 - std::min(0.15, static_cast<double>(skills.level_of("literate")) * 0.005);
    for (const char *k : keys) {
        const int id = find_item_by_key(k);
        if (id < 0) continue;
        const auto &def = cat[id];
        const int price = std::max(1, static_cast<int>(std::round(static_cast<double>(def.base_price) * discount)));
        Dictionary row;
        row["id"] = id;
        row["key"] = String::utf8(def.key);
        row["name"] = String::utf8(def.name);
        row["category"] = String::utf8(category_label(def.category));
        row["price"] = price;
        row["desc"] = String::utf8(def.desc);
        row["volume_ml"] = def.volume_ml;
        row["weight_g"] = def.weight_g;
        out.append(row);
    }
    return out;
}

String buy_from_npc(const char *npc_id, int item_id, int &coins, ItemCounts &carried, const CharacterState &ch) {
    if (item_id < 0 || item_id >= kItemCount) return String::utf8("未找到该项货品。");
    const auto keys = stock_keys_for(npc_id);
    bool in_stock = false;
    const auto &def = item_catalog()[item_id];
    for (const char *k : keys) {
        if (std::strcmp(k, def.key) == 0) {
            in_stock = true;
            break;
        }
    }
    if (!in_stock) return String::utf8("此铺面暂不售卖该货品。");
    const int price = std::max(1, def.base_price);
    if (coins < price) {
        return String::utf8("随身铜钱不足（需 ") + String::num_int64(price) + String::utf8(" 文，当前仅 ") +
               String::num_int64(coins) + String::utf8(" 文）。");
    }
    if (ch.carry_volume_ml(carried) + def.volume_ml > ch.max_carry_volume_ml()) {
        return String::utf8("行囊容积已满，放不下「") + String::utf8(def.name) + String::utf8("」，请先整理或换大行囊。");
    }
    coins -= price;
    ++carried[item_id];
    return String::utf8("你花费 ") + String::num_int64(price) + String::utf8(" 文铜钱，购得「") +
           String::utf8(def.name) + String::utf8("」收入行囊。");
}

String sell_to_npc(const char *npc_id, int item_id, int &coins, ItemCounts &carried, const SkillSet &skills) {
    if (!npc_id) return String::utf8("附近无人收货。");
    const ShopService svc = shop_service_for_npc(npc_id);
    if (svc != ShopService::Pawn && svc != ShopService::Merchant) {
        return String::utf8("此人不收购杂物，请前往南大街「利源当铺」典当。");
    }
    if (item_id < 0 || item_id >= kItemCount || carried[item_id] <= 0) {
        return String::utf8("行囊中没有这件物品。");
    }
    const auto &def = item_catalog()[item_id];
    int val = sell_value_for(item_id, skills);
    if (svc != ShopService::Pawn) val = std::max(1, val * 4 / 5);
    --carried[item_id];
    coins += val;
    return String::utf8("你将「") + String::utf8(def.name) + String::utf8("」典当售出，得铜钱 ") +
           String::num_int64(val) + String::utf8(" 文。");
}

String bank_transfer(int amount, bool deposit, int &coins, CharacterState &ch) {
    if (amount <= 0) return String::utf8("存取数额须大于 0。");
    if (deposit) {
        const int move = std::min(amount, coins);
        if (move <= 0) return String::utf8("你身上没有可存入的铜钱。");
        coins -= move;
        ch.bank_coins += move;
        return String::utf8("你在通济钱庄存入 ") + String::num_int64(move) + String::utf8(" 文铜钱（钱庄结余 ") +
               String::num_int64(ch.bank_coins) + String::utf8(" 文）。");
    }
    const int move = std::min(amount, ch.bank_coins);
    if (move <= 0) return String::utf8("你在通济钱庄尚无存款。");
    ch.bank_coins -= move;
    coins += move;
    return String::utf8("你从通济钱庄取出 ") + String::num_int64(move) + String::utf8(" 文铜钱（钱庄结余 ") +
           String::num_int64(ch.bank_coins) + String::utf8(" 文）。");
}

String rent_inn_room(int &coins, int current_minutes, CharacterState &ch) {
    constexpr int kRoomCost = 5;
    if (ch.inn_room_until_min > current_minutes + 60) {
        return String::utf8("店小二笑道：「客官的上房尚未退期，请直接上二楼厢房歇息便是！」");
    }
    if (coins < kRoomCost) {
        return String::utf8("店小二陪笑道：「客官，悦来客栈二楼雅间住一宿需 ") + String::num_int64(kRoomCost) +
               String::utf8(" 文铜钱，您盘缠不够呢。」");
    }
    coins -= kRoomCost;
    ch.inn_room_until_min = current_minutes + 1440; // Valid for 1 full game day (24h)
    ch.morale = std::min(50, ch.morale + 5);
    return String::utf8("你付给店小二 ") + String::num_int64(kRoomCost) +
           String::utf8(" 文铜钱租下悦来客栈二楼上房（24时辰内有效，卧榻歇息恢复翻倍且驱寒解乏）！");
}

} // namespace cangling
