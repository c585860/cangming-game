#include "item_catalog.hpp"
#include "city.hpp"
#include <cstring>

namespace cangling {
namespace {

constexpr std::array<ItemDef, kItemCount> kCatalog{{
    // 0..3: Bedding (床品)
    {"sheet", "sheet_cotton", "棉布床单", ItemCategory::Bedding, 480, 1200, 0, 0, 0,
        WearSlot::None, 0, 0, 0, "", "柔软洗净的素色棉布床单。"},
    {"pillow", "pillow", "棉芯软枕", ItemCategory::Bedding, 520, 1800, 0, 0, 0,
        WearSlot::None, 0, 0, 0, "", "填满干荞麦壳与木棉的绣花枕头。"},
    {"blanket", "blanket", "厚棉被", ItemCategory::Bedding, 1450, 3600, 0, 0, 0,
        WearSlot::None, 0, 0, 0, "", "厚实保暖的江南手工弹棉被褥。"},
    {"quilt_silk", "quilt", "织锦绣被", ItemCategory::Bedding, 1320, 3400, 0, 0, 0,
        WearSlot::None, 0, 0, 0, "", "织有云纹的丝锦薄被，轻暖舒爽。"},

    // 4..15: Clothing & Carry Gear (着装与行囊，参考 CCB armor/clothing)
    {"straw_hat", "straw_hat", "竹编斗笠", ItemCategory::Clothing, 240, 1200, 0, 0, 0,
        WearSlot::Head, 6, 2, 0, "overlay_worn_straw_hat", "江南水乡常见竹笠，能遮风挡雨。"},
    {"cloth_cap", "bandana", "青布方巾", ItemCategory::Clothing, 110, 250, 0, 0, 0,
        WearSlot::Head, 8, 1, 0, "overlay_worn_bandana", "轻便素净的青布头巾。"},
    {"tunic", "tunic", "棉布短衫", ItemCategory::Clothing, 420, 1000, 0, 0, 0,
        WearSlot::Torso, 14, 4, 400, "overlay_worn_tunic", "寻常百姓常穿的粗棉短衫。"},
    {"silk_shirt", "longshirt", "素绫中衣", ItemCategory::Clothing, 310, 750, 0, 0, 0,
        WearSlot::Torso, 12, 2, 300, "overlay_worn_tunic", "贴身轻薄的素色绫罗中衣，活动灵便。"},
    {"pants", "pants", "粗布长裤", ItemCategory::Clothing, 460, 1100, 0, 0, 0,
        WearSlot::Legs, 14, 4, 600, "overlay_worn_pants", "耐磨耐脏的靛青粗布长裤，带两个深兜。"},
    {"robe", "robe", "青衫长袍", ItemCategory::Clothing, 780, 2000, 0, 0, 0,
        WearSlot::Outer, 22, 6, 1600, "overlay_worn_robe", "广袖青衫长袍，袖袋宽大可纳随身杂物。"},
    {"cloak", "cloak", "蓑衣披风", ItemCategory::Clothing, 820, 2200, 0, 0, 0,
        WearSlot::Outer, 26, 6, 1200, "overlay_worn_cloak", "耐雨防风的旅人披风，阴雨天甚为实用。"},
    {"winter_coat", "coat_winter", "夹棉袄袍", ItemCategory::Clothing, 1450, 3500, 0, 0, 0,
        WearSlot::Outer, 44, 12, 2400, "overlay_worn_coat_winter", "厚实保暖的冬日夹棉袄袍，多处暗袋。"},
    {"boots", "boots", "千层布靴", ItemCategory::Clothing, 620, 1400, 0, 0, 0,
        WearSlot::Feet, 12, 4, 0, "overlay_worn_boots", "纳底厚实的千层布靴，行远路不磨脚。"},
    {"sandals", "bastsandals", "编织草鞋", ItemCategory::Clothing, 260, 650, 0, 0, 0,
        WearSlot::Feet, 4, 1, 0, "overlay_worn_bastsandals", "轻便透气的稻草编鞋。"},
    {"cloth_bag", "backpack", "青布行囊", ItemCategory::Clothing, 560, 1500, 0, 0, 0,
        WearSlot::Back, 4, 6, 14000, "overlay_worn_backpack", "背负式青布行囊，可大幅扩充携带容积。"},
    {"pouch", "mbag", "腰间荷包", ItemCategory::Clothing, 190, 450, 0, 0, 0,
        WearSlot::Back, 2, 2, 4200, "overlay_worn_mbag", "系于腰侧的帆布荷包，随手取物极便。"},

    // 16..22: Food (饮食·食粮)
    {"flatbread", "flatbread", "芝麻炊饼", ItemCategory::Food, 210, 350, 340, -4, 3,
        WearSlot::None, 0, 0, 0, "", "刚出炉的香酥芝麻炊饼，顶饿耐放。"},
    {"steamed_bun", "bread", "白面馒头", ItemCategory::Food, 180, 320, 290, -2, 2,
        WearSlot::None, 0, 0, 0, "", "松软麦香的大白馒头。"},
    {"rice_bowl", "deluxe_rice", "热白米饭", ItemCategory::Food, 320, 480, 410, 6, 6,
        WearSlot::None, 0, 0, 0, "", "粒粒分明的江南新米饭。"},
    {"dried_meat", "jerky", "风干酱肉", ItemCategory::Food, 160, 240, 450, -12, 7,
        WearSlot::None, 0, 0, 0, "", "咸香耐存的腌制酱肉干，热量充沛。"},
    {"apple", "apple", "青红苹果", ItemCategory::Food, 150, 220, 120, 20, 4,
        WearSlot::None, 0, 0, 0, "", "脆甜多汁的鲜果，兼能生津解渴。"},
    {"pear", "pear", "江南雪梨", ItemCategory::Food, 170, 240, 110, 26, 5,
        WearSlot::None, 0, 0, 0, "", "清甜润肺的大雪梨，水分充足。"},
    {"pastry", "cake2", "桂花糖糕", ItemCategory::Food, 140, 220, 260, -4, 11,
        WearSlot::None, 0, 0, 0, "", "香甜软糯的桂花米糕，颇令人心情愉悦。"},

    // 23..26: Drinks (饮食·茶水)
    {"tea_cup", "tea", "江南清茶", ItemCategory::Drink, 260, 300, 10, 52, 8,
        WearSlot::None, 0, 0, 0, "", "微温清香的绿茶，解渴提神。"},
    {"clean_water", "water_clean", "竹筒清水", ItemCategory::Drink, 350, 400, 0, 60, 1,
        WearSlot::None, 0, 0, 0, "", "清冽甘甜的井水，装于竹筒之中。"},
    {"rice_wine", "brew_fruit_wine", "江南米酒", ItemCategory::Drink, 420, 450, 150, 30, 12,
        WearSlot::None, 0, 0, 0, "", "微甜醇厚的本地糯米黄酒。"},
    {"herb_tea", "tea_raw", "清露草茶", ItemCategory::Drink, 280, 320, 55, 45, 10,
        WearSlot::None, 0, 0, 0, "", "以河滩清露草冲泡的温润草茶，解乏生津。"},

    // 27..31: Books, Herbs & Tools (典籍、药材与杂物)
    {"herb_bundle", "mayapple", "干草药", ItemCategory::Misc, 90, 220, 20, 0, 0,
        WearSlot::None, 0, 0, 0, "", "晒干扎束的常见草药，药铺常备。"},
    {"clay_bottle", "bottle_glass", "青瓷小瓶", ItemCategory::Misc, 180, 300, 0, 0, 0,
        WearSlot::None, 0, 0, 0, "", "光滑素雅的青瓷小药瓶。"},
    {"book_scroll", "book_archery", "线装古籍", ItemCategory::Misc, 340, 520, 0, 0, 0,
        WearSlot::None, 0, 0, 0, "", "墨香犹存的线装旧书，记述乡野见闻。"},
    {"ink_paper", "paper", "宣纸墨锭", ItemCategory::Misc, 160, 320, 0, 0, 0,
        WearSlot::None, 0, 0, 0, "", "一叠洁白宣纸与半方徽墨。"},
    {"rope", "rope_6", "粗麻绳", ItemCategory::Misc, 620, 900, 0, 0, 0,
        WearSlot::None, 0, 0, 0, "", "结实耐磨的麻绳，捆扎搬运常用。"},
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

    switch (tile) {
        case 'b': {
            // Beds realistically spawn pillow + blanket/sheet/silk quilt (CCB bedroom itemgroup)
            if (r1 % 10 < 8) out[1] += 1; // pillow
            if (r2 % 10 < 7) {
                constexpr std::array<int, 3> covers{0, 2, 3}; // sheet, blanket, quilt_silk
                out[covers[(r2 / 10) % covers.size()]] += 1;
            }
            if (r3 % 10 == 0) out[0] += 1; // extra sheet
            break;
        }
        case 'F': {
            // Wardrobes spawn 1-3 assorted clothing pieces & bags (CCB wardrobe itemgroup)
            constexpr std::array<int, 12> clothes{4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15};
            if (r1 % 10 < 9) {
                out[clothes[(r1 / 10) % clothes.size()]] += 1;
                if (r2 % 10 < 7) out[clothes[(r2 / 10) % clothes.size()]] += 1;
                if (r3 % 10 < 4) out[clothes[(r3 / 10) % clothes.size()]] += 1;
            }
            break;
        }
        case 'c': {
            // Wooden dressers / cabinets spawn folded shirts, pants, pouches, sheets, paper
            constexpr std::array<int, 8> pool{0, 5, 6, 7, 8, 15, 28, 30};
            if (r1 % 10 < 7) {
                out[pool[(r1 / 10) % pool.size()]] += 1;
                if (r2 % 10 < 4) out[pool[(r2 / 10) % pool.size()]] += 1;
            }
            break;
        }
        case 'k': {
            // Kitchen counters (J) spawn staple food & drinks; shop/inn counters spawn tea, wine, snacks
            if (surface == 'J') {
                constexpr std::array<int, 8> kitchen_food{16, 17, 18, 19, 20, 21, 23, 24};
                if (r1 % 10 < 7) out[kitchen_food[(r1 / 10) % kitchen_food.size()]] += 1;
                if (r2 % 10 < 4) out[kitchen_food[(r2 / 10) % kitchen_food.size()]] += 1;
            } else {
                constexpr std::array<int, 6> shop_pool{16, 22, 23, 24, 25, 28};
                if (r1 % 10 < 5) out[shop_pool[(r1 / 10) % shop_pool.size()]] += 1;
            }
            break;
        }
        case 'K': {
            // Apothecary / display cabinets spawn herbs, bottles, herb tea, pastries, pouches
            constexpr std::array<int, 6> apoth{27, 28, 26, 22, 15, 23};
            if (r1 % 10 < 8) {
                out[apoth[(r1 / 10) % apoth.size()]] += 1;
                if (r2 % 10 < 4) out[apoth[(r2 / 10) % apoth.size()]] += 1;
            }
            break;
        }
        case 't': {
            // Dining tables occasionally hold tea, rice, flatbread, fruit, or wine
            constexpr std::array<int, 7> table_pool{16, 17, 18, 20, 21, 23, 25};
            if (r1 % 10 < 4) out[table_pool[(r1 / 10) % table_pool.size()]] += 1;
            break;
        }
        case 'l': {
            // Scholar desks spawn scrolls, ink/paper, or tea
            constexpr std::array<int, 3> desk_pool{29, 30, 23};
            if (r1 % 10 < 7) out[desk_pool[(r1 / 10) % desk_pool.size()]] += 1;
            break;
        }
        case 'r': {
            // Bookshelves & wooden racks spawn books, scrolls, bottles, herbs, rope
            constexpr std::array<int, 5> rack_pool{29, 30, 28, 27, 31};
            if (r1 % 10 < 7) {
                out[rack_pool[(r1 / 10) % rack_pool.size()]] += 1;
                if (r2 % 10 < 3) out[rack_pool[(r2 / 10) % rack_pool.size()]] += 1;
            }
            break;
        }
        case 'C': {
            // Cargo trunks spawn preserved rations, wine, bags, boots, rope, blankets
            constexpr std::array<int, 8> crate_pool{16, 19, 24, 25, 14, 12, 31, 2};
            if (r1 % 10 < 7) {
                out[crate_pool[(r1 / 10) % crate_pool.size()]] += 1;
                if (r2 % 10 < 4) out[crate_pool[(r2 / 10) % crate_pool.size()]] += 1;
            }
            break;
        }
        default:
            break;
    }
    return out;
}

} // namespace cangling
