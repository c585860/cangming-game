#include "item_catalog.hpp"
#include "city.hpp"
#include <cstring>

namespace cangling {
namespace {

constexpr std::array<ItemDef, kItemCount> kCatalog{{
    // 0..3: Bedding (SUS_bed)
    {"sheet", "sheet_cotton", "棉布床单", ItemCategory::Bedding, 480, 1200, 0, 0, 0, 1,
        WearSlot::None, 0, 0, 0, "", "柔软洗净的素色棉布床单。"},
    {"pillow", "pillow", "棉芯软枕", ItemCategory::Bedding, 520, 1800, 0, 0, 0, 1,
        WearSlot::None, 0, 0, 0, "", "填满干荞麦壳与木棉的绣花枕头。"},
    {"blanket", "blanket", "厚棉被", ItemCategory::Bedding, 1450, 3600, 0, 0, 0, 1,
        WearSlot::None, 0, 0, 0, "", "厚实保暖的江南手工弹棉被褥。"},
    {"quilt_silk", "quilt", "织锦绣被", ItemCategory::Bedding, 1320, 3400, 0, 0, 0, 1,
        WearSlot::None, 0, 0, 0, "", "织有云纹的丝锦薄被，轻暖舒爽。"},

    // 4..15: Clothing & Carry Gear (SUS_wardrobe / SUS_dresser)
    {"straw_hat", "straw_hat", "竹编斗笠", ItemCategory::Clothing, 240, 1200, 0, 0, 0, 1,
        WearSlot::Head, 6, 2, 0, "overlay_worn_straw_hat", "江南水乡常见竹笠，能遮风挡雨。"},
    {"cloth_cap", "bandana", "青布方巾", ItemCategory::Clothing, 110, 250, 0, 0, 0, 0,
        WearSlot::Head, 8, 1, 0, "overlay_worn_bandana", "轻便素净的青布头巾。"},
    {"tunic", "tunic", "棉布短衫", ItemCategory::Clothing, 420, 1000, 0, 0, 0, 1,
        WearSlot::Torso, 14, 4, 400, "overlay_worn_tunic", "寻常百姓常穿的粗棉短衫。"},
    {"silk_shirt", "longshirt", "素绫中衣", ItemCategory::Clothing, 310, 750, 0, 0, 0, 1,
        WearSlot::Torso, 12, 2, 300, "overlay_worn_tunic", "贴身轻薄的素色绫罗中衣，活动灵便。"},
    {"pants", "pants", "粗布长裤", ItemCategory::Clothing, 460, 1100, 0, 0, 0, 1,
        WearSlot::Legs, 14, 4, 600, "overlay_worn_pants", "耐磨耐脏的靛青粗布长裤，带两个深兜。"},
    {"robe", "robe", "青衫长袍", ItemCategory::Clothing, 780, 2000, 0, 0, 0, 1,
        WearSlot::Outer, 22, 6, 1600, "overlay_worn_robe", "广袖青衫长袍，袖袋宽大可纳随身杂物。"},
    {"cloak", "cloak", "蓑衣披风", ItemCategory::Clothing, 820, 2200, 0, 0, 0, 1,
        WearSlot::Outer, 26, 6, 1200, "overlay_worn_cloak", "耐雨防风的旅人披风，阴雨天甚为实用。"},
    {"winter_coat", "coat_winter", "夹棉袄袍", ItemCategory::Clothing, 1450, 3500, 0, 0, 0, 2,
        WearSlot::Outer, 44, 12, 2400, "overlay_worn_coat_winter", "厚实保暖的冬日夹棉袄袍，多处暗袋。"},
    {"boots", "boots", "千层布靴", ItemCategory::Clothing, 620, 1400, 0, 0, 0, 3,
        WearSlot::Feet, 12, 4, 0, "overlay_worn_boots", "纳底厚实的千层布靴，行远路不磨脚。"},
    {"sandals", "bastsandals", "编织草鞋", ItemCategory::Clothing, 260, 650, 0, 0, 0, 1,
        WearSlot::Feet, 4, 1, 0, "overlay_worn_bastsandals", "轻便透气的稻草编鞋。"},
    {"cloth_bag", "backpack", "青布行囊", ItemCategory::Clothing, 560, 1500, 0, 0, 0, 2,
        WearSlot::Back, 4, 6, 14000, "overlay_worn_backpack", "背负式青布行囊，可大幅扩充携带容积。"},
    {"pouch", "mbag", "腰间荷包", ItemCategory::Clothing, 190, 450, 0, 0, 0, 1,
        WearSlot::Back, 2, 2, 4200, "overlay_worn_mbag", "系于腰侧的帆布荷包，随手取物极便。"},

    // 16..22: Food (SUS_pantry / kitchen)
    {"flatbread", "flatbread", "芝麻炊饼", ItemCategory::Food, 210, 350, 340, -4, 3, 1,
        WearSlot::None, 0, 0, 0, "", "刚出炉的香酥芝麻炊饼，顶饿耐放。"},
    {"steamed_bun", "bread", "白面馒头", ItemCategory::Food, 180, 320, 290, -2, 2, 1,
        WearSlot::None, 0, 0, 0, "", "松软麦香的大白馒头。"},
    {"rice_bowl", "deluxe_rice", "热白米饭", ItemCategory::Food, 320, 480, 410, 6, 6, 1,
        WearSlot::None, 0, 0, 0, "", "粒粒分明的江南新米饭。"},
    {"dried_meat", "jerky", "风干酱肉", ItemCategory::Food, 160, 240, 450, -12, 7, 1,
        WearSlot::None, 0, 0, 0, "", "咸香耐存的腌制酱肉干，热量充沛。"},
    {"apple", "apple", "青红苹果", ItemCategory::Food, 150, 220, 120, 20, 4, 1,
        WearSlot::None, 0, 0, 0, "", "脆甜多汁的鲜果，兼能生津解渴。"},
    {"pear", "pear", "江南雪梨", ItemCategory::Food, 170, 240, 110, 26, 5, 1,
        WearSlot::None, 0, 0, 0, "", "清甜润肺的大雪梨，水分充足。"},
    {"pastry", "cake2", "桂花糖糕", ItemCategory::Food, 140, 220, 260, -4, 11, 0,
        WearSlot::None, 0, 0, 0, "", "香甜软糯的桂花米糕，颇令人心情愉悦。"},

    // 23..26: Drinks
    {"tea_cup", "tea", "江南清茶", ItemCategory::Drink, 260, 300, 10, 52, 8, 1,
        WearSlot::None, 0, 0, 0, "", "微温清香的绿茶，解渴提神。"},
    {"clean_water", "water_clean", "竹筒清水", ItemCategory::Drink, 350, 400, 0, 60, 1, 2,
        WearSlot::None, 0, 0, 0, "", "清冽甘甜的井水，装于竹筒之中。"},
    {"rice_wine", "brew_fruit_wine", "江南米酒", ItemCategory::Drink, 420, 450, 150, 30, 12, 3,
        WearSlot::None, 0, 0, 0, "", "微甜醇厚的本地糯米黄酒。"},
    {"herb_tea", "tea_raw", "清露草茶", ItemCategory::Drink, 280, 320, 55, 45, 10, 1,
        WearSlot::None, 0, 0, 0, "", "以河滩清露草冲泡的温润草茶，解乏生津。"},

    // 27..31: Herbs, Books & Rope
    {"herb_bundle", "mayapple", "干草药", ItemCategory::Medical, 90, 220, 20, 0, 0, 0,
        WearSlot::None, 0, 0, 0, "", "晒干扎束的常见草药，药铺常备。"},
    {"clay_bottle", "bottle_glass", "青瓷小瓶", ItemCategory::Misc, 180, 300, 0, 0, 0, 3,
        WearSlot::None, 0, 0, 0, "", "光滑素雅的青瓷小药瓶。"},
    {"book_scroll", "book_archery", "线装古籍", ItemCategory::Book, 340, 520, 0, 0, 10, 2,
        WearSlot::None, 0, 0, 0, "", "墨香犹存的线装旧书（按 R 可阅读，增长见闻与心境）。"},
    {"ink_paper", "paper", "宣纸墨锭", ItemCategory::Misc, 160, 320, 0, 0, 0, 1,
        WearSlot::None, 0, 0, 0, "", "一叠洁白宣纸与半方徽墨。"},
    {"rope", "rope_6", "粗麻绳", ItemCategory::Tool, 620, 900, 0, 0, 0, 2,
        WearSlot::None, 0, 0, 0, "", "结实耐磨的麻绳，捆扎搬运常用。"},

    // 32..49: CCB SUS Domestic Kitchenware, Tools, Lighting, Medical & Debris
    {"cleaver", "knife_butcher", "铁背菜刀", ItemCategory::Tool, 540, 400, 0, 0, 0, 10,
        WearSlot::None, 0, 0, 0, "", "厨房常用的厚背铁菜刀（可手持 w，砸物/劈砍得力）。"},
    {"chopsticks", "chopsticks", "青竹筷子", ItemCategory::Misc, 30, 50, 0, 0, 0, 0,
        WearSlot::None, 0, 0, 0, "", "一双打磨光滑的毛竹筷。"},
    {"bowl_clay", "bowl_clay", "青花瓷碗", ItemCategory::Misc, 240, 380, 0, 0, 0, 2,
        WearSlot::None, 0, 0, 0, "", "家常粗瓷青花饭碗。"},
    {"iron_pot", "pot", "铸铁小锅", ItemCategory::Tool, 1450, 2200, 0, 0, 0, 8,
        WearSlot::None, 0, 0, 0, "", "厚重的双耳铁锅，可用于灶台烹煮。"},
    {"teapot", "teapot", "紫砂茶壶", ItemCategory::Misc, 480, 750, 0, 0, 0, 3,
        WearSlot::None, 0, 0, 0, "", "温润古朴的宜兴紫砂壶。"},
    {"salt", "salt", "粗盐罐", ItemCategory::Food, 320, 350, 0, -25, -4, 2,
        WearSlot::None, 0, 0, 0, "", "一罐海盐，厨房腌制调味必备。"},
    {"noodles", "noodles_fast", "干挂面", ItemCategory::Food, 260, 420, 390, -8, 2, 1,
        WearSlot::None, 0, 0, 0, "", "一束晒干的细白挂面，耐储存。"},
    {"hatchet", "hatchet", "伐木手斧", ItemCategory::Tool, 1280, 1100, 0, 0, 0, 20,
        WearSlot::None, 0, 0, 0, "", "锋利趁手的铁手斧（手持 w 后按 s 可轻松砸开木门与家具）。"},
    {"crowbar", "crowbar", "铁撬棍", ItemCategory::Tool, 1650, 1250, 0, 0, 0, 16,
        WearSlot::None, 0, 0, 0, "", "厚实锻铁撬棍（手持 w 提升砸碎与撬门能力）。"},
    {"oil_lamp", "oil_lamp", "桐油手灯", ItemCategory::Tool, 460, 650, 0, 0, 0, 3,
        WearSlot::None, 0, 0, 0, "", "便携铜制桐油灯（按 a 使用可点亮/熄灭随身照明）。"},
    {"tinderbox", "lighter", "火折子", ItemCategory::Tool, 80, 120, 0, 0, 0, 0,
        WearSlot::None, 0, 0, 0, "", "吹气即燃的竹筒火折子（按 a 可点燃炉灶或火源）。"},
    {"wood_plank", "2x4", "碎木板", ItemCategory::Misc, 950, 1600, 0, 0, 0, 6,
        WearSlot::None, 0, 0, 0, "", "木门或家具砸碎后散落的结实木板。"},
    {"cloth_rag", "rag", "碎布条", ItemCategory::Medical, 60, 140, 0, 0, 0, 0,
        WearSlot::None, 0, 0, 0, "", "拆散衣物或床品所得的棉布条，可用于包扎。"},
    {"ceramic_shard", "ceramic_shard", "碎瓷片", ItemCategory::Misc, 110, 160, 0, 0, 0, 2,
        WearSlot::None, 0, 0, 0, "", "陶缸或瓷盆破碎后的锋利碎片。"},
    {"bandage", "bandages", "金创纱布", ItemCategory::Medical, 80, 150, 0, 0, 2, 0,
        WearSlot::None, 0, 0, 0, "", "浸过止血药汁的洁净纱布（按 a 可包扎疗伤）。"},
    {"candle", "candle", "红油蜡烛", ItemCategory::Tool, 120, 150, 0, 0, 0, 0,
        WearSlot::None, 0, 0, 0, "", "民间常用红蜡烛，夜间照明必备。"},
    {"towel", "towel", "棉布手巾", ItemCategory::Misc, 180, 420, 0, 0, 0, 0,
        WearSlot::None, 0, 0, 0, "", "洗漱用的厚实白棉手巾。"},
    {"soap", "soap", "皂角块", ItemCategory::Misc, 110, 140, 0, 0, 0, 1,
        WearSlot::None, 0, 0, 0, "", "天然草木灰与皂角制成的洗漱香皂。"},
}};

inline std::uint32_t mix_roll(std::uint32_t seed, godot::Vector2i p, int floor, std::uint32_t salt) {
    return sector_seed(seed ^ salt ^ (static_cast<std::uint32_t>(floor + 17) * 0x9e3779b9u), p);
}

} // namespace

const std::array<ItemDef, kItemCount> &item_catalog() {
    return kCatalog;
}

int find_item_by_key(const char *key) {
    if (!key) return -1;
    for (int i = 0; i < kItemCount; ++i) {
        if (std::strcmp(kCatalog[i].key, key) == 0) return i;
    }
    return -1;
}

const char *category_label(ItemCategory cat) {
    switch (cat) {
        case ItemCategory::Bedding: return "床品";
        case ItemCategory::Clothing: return "着装";
        case ItemCategory::Food: return "食粮";
        case ItemCategory::Drink: return "茶水";
        case ItemCategory::Tool: return "器具";
        case ItemCategory::Book: return "典籍";
        case ItemCategory::Medical: return "医药";
        default: return "杂物";
    }
}

const char *wear_slot_label(WearSlot slot) {
    switch (slot) {
        case WearSlot::Head: return "头部";
        case WearSlot::Torso: return "上身";
        case WearSlot::Legs: return "下身";
        case WearSlot::Feet: return "足部";
        case WearSlot::Outer: return "外袍";
        case WearSlot::Back: return "背负";
        default: return "无";
    }
}

ItemCounts spawn_contextual_items(char tile, char surface, std::uint32_t seed, godot::Vector2i p, int floor) {
    ItemCounts out{};
    const auto r1 = mix_roll(seed, p, floor, 0x3280ea56u);
    const auto r2 = mix_roll(seed, p, floor, 0x75cc9414u);
    const auto r3 = mix_roll(seed, p, floor, 0xdaaf6712u);
    const auto r4 = mix_roll(seed, p, floor, 0x41c64e6du);

    switch (tile) {
        case 'b': {
            // SUS_bed: pillow + blanket/silk quilt + cotton sheet
            if (r1 % 10 < 9) out[1] += 1; // pillow
            if (r2 % 10 < 8) {
                constexpr std::array<int, 2> covers{2, 3}; // blanket / quilt_silk
                out[covers[(r2 / 10) % covers.size()]] += 1;
            }
            if (r3 % 10 < 7) out[0] += 1; // sheet
            break;
        }
        case 'F': {
            // SUS_wardrobe: 2-4 realistic clothing articles + bags
            constexpr std::array<int, 12> clothes{4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15};
            out[clothes[r1 % clothes.size()]] += 1;
            out[clothes[r2 % clothes.size()]] += 1;
            if (r3 % 10 < 7) out[clothes[(r3 / 10) % clothes.size()]] += 1;
            if (r4 % 10 < 4) out[48] += 1; // folded towel
            break;
        }
        case 'c': {
            // SUS_dresser / domestic cabinet: folded clothes, candles, tinderbox, bandages, rags, towels
            constexpr std::array<int, 10> pool{0, 5, 6, 7, 8, 15, 42, 46, 47, 48};
            out[pool[r1 % pool.size()]] += 1;
            if (r2 % 10 < 8) out[pool[(r2 / 10) % pool.size()]] += 1;
            if (r3 % 10 < 5) out[pool[(r3 / 10) % pool.size()]] += 1;
            break;
        }
        case 'k': {
            // SUS_kitchen_counter / utensils / pantry vs shop counter
            if (surface == 'J') {
                constexpr std::array<int, 12> kitchen_food{16, 17, 18, 19, 20, 21, 23, 24, 32, 33, 34, 38};
                out[kitchen_food[r1 % kitchen_food.size()]] += 1;
                if (r2 % 10 < 8) out[kitchen_food[(r2 / 10) % kitchen_food.size()]] += 1;
                if (r3 % 10 < 5) out[r3 % 2 == 0 ? 35 : 37] += 1; // iron pot or salt jar
            } else {
                constexpr std::array<int, 9> shop_pool{16, 22, 23, 24, 25, 28, 36, 41, 47};
                out[shop_pool[r1 % shop_pool.size()]] += 1;
                if (r2 % 10 < 6) out[shop_pool[(r2 / 10) % shop_pool.size()]] += 1;
            }
            break;
        }
        case 'h': {
            // Hearth / stove: iron pot + tinderbox
            if (r1 % 10 < 7) out[35] += 1; // iron_pot
            if (r2 % 10 < 5) out[42] += 1; // tinderbox
            break;
        }
        case 'K': {
            // Apothecary / display cabinet: herbs, bandages, herb tea, bottles, pastries, teapot
            constexpr std::array<int, 7> apoth{27, 28, 26, 46, 22, 36, 15};
            out[apoth[r1 % apoth.size()]] += 1;
            if (r2 % 10 < 8) out[apoth[(r2 / 10) % apoth.size()]] += 1;
            if (r3 % 10 < 4) out[apoth[(r3 / 10) % apoth.size()]] += 1;
            break;
        }
        case 't': {
            // Dining / bedside table: teapot, bowls, chopsticks, tea, candles, fruit, flatbread
            constexpr std::array<int, 10> table_pool{16, 17, 18, 20, 21, 23, 25, 33, 34, 36};
            if (r1 % 10 < 7) out[table_pool[(r1 / 10) % table_pool.size()]] += 1;
            if (r2 % 10 < 4) out[r2 % 2 == 0 ? 47 : 33] += 1; // candle or chopsticks
            break;
        }
        case 'l': {
            // Scholar's desk: books, ink & xuan paper, candle/oil lamp, tea
            out[29] += 1; // book_scroll
            if (r1 % 10 < 8) out[30] += 1; // ink_paper
            if (r2 % 10 < 5) out[r2 % 2 == 0 ? 41 : 47] += 1; // oil_lamp or candle
            if (r3 % 10 < 4) out[23] += 1; // tea
            break;
        }
        case 'r': {
            // Bookshelf / pantry rack: multiple books, scrolls, jars, noodles, rope, oil lamp
            constexpr std::array<int, 8> rack_pool{29, 29, 30, 28, 27, 38, 31, 41};
            out[rack_pool[r1 % rack_pool.size()]] += 1;
            if (r2 % 10 < 8) out[rack_pool[(r2 / 10) % rack_pool.size()]] += 1;
            if (r3 % 10 < 5) out[rack_pool[(r3 / 10) % rack_pool.size()]] += 1;
            break;
        }
        case 'C': {
            // Cargo chest / workshop crate: tools (hatchet, crowbar, rope), rations, wine, bags, planks
            constexpr std::array<int, 11> crate_pool{16, 19, 24, 25, 14, 31, 38, 39, 40, 41, 43};
            out[crate_pool[r1 % crate_pool.size()]] += 1;
            if (r2 % 10 < 7) out[crate_pool[(r2 / 10) % crate_pool.size()]] += 1;
            if (r3 % 10 < 4) out[crate_pool[(r3 / 10) % crate_pool.size()]] += 1;
            break;
        }
        case 'u': {
            // Washstand: towel & soap
            if (r1 % 10 < 7) out[48] += 1;
            if (r2 % 10 < 6) out[49] += 1;
            break;
        }
        default:
            break;
    }
    return out;
}

} // namespace cangling
