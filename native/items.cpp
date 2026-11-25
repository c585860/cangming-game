#include "world.hpp"
#include <algorithm>
#include <limits>

namespace cangling {
using namespace godot;
namespace {
struct Item { const char *key; const char *tile; const char *name; };
constexpr std::array items{
    Item{"sheet","sheet_cotton","棉布床单"}, Item{"apple","apple","苹果"},
    Item{"flatbread","flatbread","烙饼"}, Item{"pear","pear","梨"},
    Item{"herb_bundle","mayapple","干草药"}, Item{"clay_bottle","bottle_glass","小瓶"},
    Item{"tunic","tunic","棉布短衫"}, Item{"pants","pants","布裤"},
    Item{"robe","robe","长袍"}, Item{"boots","boots","布靴"}
};
constexpr int max_stack = 999;
constexpr int area = city_size*city_size;

int number(const Variant &value, int low, int high) {
    if (value.get_type() != Variant::INT && value.get_type() != Variant::FLOAT) return -1;
    const double n = static_cast<double>(value);
    return n >= low && n <= high && n == static_cast<int>(n) ? static_cast<int>(n) : -1;
}

int capacity(char tile) { return tile == 'a' ? 5000 : tile == 'u' ? 1600 : 0; }

int64_t number64(const Variant &value) {
    if (value.get_type() != Variant::INT) return std::numeric_limits<int64_t>::min();
    return static_cast<int64_t>(value);
}

Vector2i decode_key(int64_t key, int &z) {
    const int x = static_cast<int>((key % city_size + city_size) % city_size);
    const int64_t row = (key - x) / city_size;
    const int y = static_cast<int>((row % city_size + city_size) % city_size);
    const int64_t level = (row - y) / city_size;
    if (level < std::numeric_limits<int>::min() || level > std::numeric_limits<int>::max()) {
        z = std::numeric_limits<int>::min();
    } else {
        z = static_cast<int>(level);
    }
    return {x,y};
}
}

String CanglingWorld::item_name(int i) { return String::utf8(items[i].name); }

int CanglingWorld::generated_item(Vector2i p) {
    const auto prop = generated_prop(p);
    for (int i = 0; i < item_types; ++i) if (prop == items[i].key) return i;
    return -1;
}

CanglingWorld::ItemCounts CanglingWorld::items_on(Vector2i p) {
    if (!in_city(p)) return {};
    const int64_t k = key(p,floor);
    ItemCounts count{};
    if (const auto it = stored_items.find(k); it != stored_items.end()) count = it->second;
    if (!collected_props.count(k)) {
        const int i = generated_item(p);
        if (i >= 0) ++count[i];
    }
    return count;
}

String CanglingWorld::prop_at(Vector2i p) {
    const auto count = items_on(p);
    for (int i = 0; i < item_types; ++i) if (count[i]) return items[i].tile;
    return {};
}

Array CanglingWorld::inventory() const {
    Array result;
    for (int i = 0; i < item_types; ++i) {
        if (!carried[i]) continue;
        Dictionary row;
        row["id"] = i;
        row["name"] = item_name(i);
        row["count"] = carried[i];
        row["tile"] = items[i].tile;
        result.append(row);
    }
    return result;
}

String CanglingWorld::take_item(Vector2i p, int i) {
    if (!in_city(p) || !near(p) || i < 0 || i >= item_types || items_on(p)[i] == 0) return {};
    if (carried[i] >= max_stack) return String::utf8("行囊里同类物品已满。");
    const int k = key(p,floor);
    if (auto it = stored_items.find(k); it != stored_items.end() && it->second[i] > 0) {
        if (--it->second[i] == 0 && std::none_of(it->second.begin(),it->second.end(),[](int n){return n != 0;}))
            stored_items.erase(it);
    } else collected_props.insert(k);
    ++carried[i];
    ++minutes;
    return String::utf8("你拿起了") + item_name(i) + String::utf8("。");
}

String CanglingWorld::place_item(Vector2i p, int i) {
    if (!in_city(p) || !near(p) || i < 0 || i >= item_types || !carried[i]) return {};
    if (p != pos && std::string_view("btckKlruCaF").find(city.tile(p,floor)) == std::string_view::npos) return {};
    auto &count = stored_items[key(p,floor)][i];
    if (count >= max_stack) return String::utf8("这里已经堆不下了。");
    ++count;
    --carried[i];
    ++minutes;
    return String::utf8("你放下了") + item_name(i) + String::utf8("。");
}

int CanglingWorld::water_capacity_at(Vector2i p) { return capacity(city.tile(p,floor)); }

int CanglingWorld::water_at(Vector2i p) {
    const int limit = water_capacity_at(p);
    if (limit == 0) return 0;
    const auto it = vessel_water.find(key(p,floor));
    return it != vessel_water.end() ? it->second : limit*3/4;
}

String CanglingWorld::transfer_water(Vector2i p, int amount, bool fill_bottle) {
    const int limit = water_capacity_at(p);
    if (limit == 0 || !near(p) || amount <= 0) return {};
    const int original = water_at(p);
    const int available = fill_bottle ? std::min(original,bottle_capacity()-carried_water) :
                          std::min(carried_water,limit-original);
    const int moved = std::min(amount,available);
    if (!moved) return String::utf8("无水可倒，或容器已满。");
    const int delta = fill_bottle ? moved : -moved;
    carried_water += delta;
    vessel_water[key(p,floor)] = original-delta;
    ++minutes;
    return (fill_bottle ? String::utf8("你装入水壶 ") : String::utf8("你倒回容器 ")) +
           String::num_int64(moved) + String::utf8(" 毫升水。");
}

void CanglingWorld::clear_items() {
    carried.fill(0);
    stored_items.clear();
    collected_props.clear();
    vessel_water.clear();
    carried_water = 0;
}

Dictionary CanglingWorld::item_state() const {
    Dictionary data;
    Array bag, taken, placed, water;
    for (int count : carried) bag.append(count);
    for (int64_t k : collected_props) taken.append(k);
    for (const auto &[k,counts] : stored_items) {
        for (int i = 0; i < item_types; ++i) if (counts[i]) placed.append(Array::make(static_cast<int64_t>(k),i,counts[i]));
    }
    for (const auto &[k,count] : vessel_water) water.append(Array::make(static_cast<int64_t>(k),count));
    data["bag"] = bag;
    data["taken"] = taken;
    data["placed"] = placed;
    data["water"] = water;
    data["bottle_ml"] = carried_water;
    return data;
}

bool CanglingWorld::restore_item_state(const Dictionary &data, City &loaded) {
    for (const char *name : {"bag","taken","placed","water"})
        if (data.get(name,Variant()).get_type() != Variant::ARRAY) return false;
    const Array bag = data["bag"], taken = data["taken"], placed = data["placed"], water = data["water"];
    ItemCounts next_bag{};
    decltype(collected_props) next_taken;
    decltype(stored_items) next_placed;
    decltype(vessel_water) next_water;
    const int bottle = number(data.get("bottle_ml",Variant()),0,bottle_capacity());
    if (bottle < 0 || bag.size() != item_types) return false;
    for (int i = 0; i < item_types; ++i) {
        next_bag[i] = number(bag[i],0,max_stack);
        if (next_bag[i] < 0) return false;
    }
    for (int i = 0; i < taken.size(); ++i) {
        const int64_t k = number64(taken[i]);
        if (k == std::numeric_limits<int64_t>::min()) return false;
        int z = 0;
        const Vector2i p = decode_key(k,z);
        if (!in_city(p) || z == std::numeric_limits<int>::min()) return false;
        next_taken.insert(k);
    }
    for (int i = 0; i < placed.size(); ++i) {
        if (placed[i].get_type() != Variant::ARRAY) return false;
        const Array row = placed[i];
        if (row.size() != 3) return false;
        const int64_t k = number64(row[0]);
        const int item = number(row[1],0,item_types-1), n = number(row[2],1,max_stack);
        int z = 0;
        const Vector2i p = decode_key(k,z);
        if (k == std::numeric_limits<int64_t>::min() || !in_city(p) || z == std::numeric_limits<int>::min() || item < 0 || n < 0) return false;
        next_placed[k][item] = n;
    }
    for (int i = 0; i < water.size(); ++i) {
        if (water[i].get_type() != Variant::ARRAY) return false;
        const Array row = water[i];
        if (row.size() != 2) return false;
        const int64_t k = number64(row[0]);
        if (k == std::numeric_limits<int64_t>::min()) return false;
        int z = 0;
        const Vector2i p = decode_key(k,z);
        if (!in_city(p) || z == std::numeric_limits<int>::min()) return false;
        const int limit = capacity(loaded.tile(p,z));
        const int n = number(row[1],0,limit);
        if (n < 0 || limit == 0) return false;
        next_water[k] = n;
    }
    carried = next_bag;
    stored_items = std::move(next_placed);
    vessel_water = std::move(next_water);
    collected_props = std::move(next_taken);
    carried_water = bottle;
    return true;
}
}
