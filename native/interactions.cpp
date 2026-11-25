#include "world.hpp"
#include <algorithm>
#include <limits>

namespace cangling {
using namespace godot;
namespace {
String text(const char *s) { return String::utf8(s); }
const char *fixture(char tile) {
    switch (tile) {
        case 'b': return "床榻"; case 't': return "木桌"; case 'c': return "木柜";
        case 'C': return "货箱"; case 'k': return "长案"; case 'u': return "水盆";
        case 'q': return "坐凳"; case 'r': return "置物架"; case 'l': return "书案";
        case 'h': return "炉灶"; case 'a': return "陶缸"; case 'f': return "木篱";
        case 'g': return "花木"; case 'w': return "窗户";
        case 'K': return "展柜"; case 'S': return "长椅"; case 'P': return "盆栽";
        case 'F': return "衣柜"; case 'Y': return "行道树"; case 'L': return "街灯";
        default: return nullptr;
    }
}
}

StringName CanglingWorld::site(Vector2i p) {
    if (!in_city(p)) return {};
    if (floor == 0) {
        if (p == market_tile) return "merchant";
        if (p == altar_tile) return "altar";
        if (p == dock_tile) return "ferryman";
        for (std::size_t i = 0; i < herb_tiles.size(); ++i) {
            if (p == herb_tiles[i] && !collected[i]) return "herb";
        }
    }
    switch (city.tile(p,floor)) {
        case 'D': return "door";
        case '^': return "up";
        case 'v': return "down";
        case 'X': return "stairs";
        default: return {};
    }
}

Dictionary CanglingWorld::actions_at(Vector2i p) {
    Dictionary out;
    if (!in_city(p)) return out;
    const char tile = city.tile(p,floor);
    if (tile == ' ') return out;
    const auto kind = site(p);
    if (kind == StringName("door")) {
        if (p != pos) out["door"] = text(doors.count(key(p,floor)) ? "关门" : "开门");
    } else if (kind == StringName("up")) out["stairs_up"] = text("上楼");
    else if (kind == StringName("down")) out["stairs_down"] = text("下楼");
    else if (kind == StringName("stairs")) {
        out["stairs_up"] = text("上楼");
        out["stairs_down"] = text("下楼");
    }
    else if (kind == StringName("merchant")) out["talk"] = text("与沈青交谈");
    else if (kind == StringName("ferryman")) out["talk"] = text("与渡夫交谈");
    else if (kind == StringName("altar")) out["cultivate"] = text(quest == 3 ? "在石台吐纳" : "查看吐纳石台");
    else if (kind == StringName("herb")) out["gather"] = text("采集清露草");
    if (fixture(tile)) {
        out["inspect"] = text(tile == 'F' ? "查看衣物" : "查看") + (tile == 'F' ? String() : text(fixture(tile)));
        if (tile == 'b' || tile == 'q' || tile == 'S') out["rest"] = text(tile == 'b' ? "歇息片刻" : "坐下休息");
    }
    if (tile == 'w') out["window"] = text(doors.count(key(p,floor)) ? "关窗" : "开窗");
    const auto available = items_on(p);
    for (int i = 0; i < item_types; ++i) {
        if (available[i]) out[String("take_") + String::num_int64(i)] = text("拿取") + item_name(i);
    }
    if (std::string_view("btckKlruCaF").find(tile) != std::string_view::npos &&
        std::any_of(carried.begin(),carried.end(),[](int n){return n != 0;})) out["store"] = text("放入物品");
    const int limit = water_capacity_at(p);
    if (limit) {
        const int amount = water_at(p);
        if (amount > 0 && carried_water < bottle_capacity()) out["water_take"] = text("装入水壶…");
        if (amount < limit && carried_water > 0) out["water_pour"] = text("从水壶倒入…");
    }
    if (walkable(p) && p != pos) out["walk"] = text("走到此处");
    return out;
}

String CanglingWorld::interact(Vector2i p, const String &action) {
    if (!near(p) || !actions_at(p).has(action)) return {};
    if (action == "door") {
        ++minutes;
        if (doors.erase(key(p,floor))) return text("你关上了门。");
        doors.insert(key(p,floor));
        return text("你打开了门。");
    }
    if (action == "window") {
        ++minutes;
        if (doors.erase(key(p,floor))) return text("你关上了窗。");
        doors.insert(key(p,floor));
        return text("你打开了窗。");
    }
    if (action.begins_with("take_")) return take_item(p,action.substr(5).to_int());
    if (action == "stairs_up" || action == "stairs_down") {
        const bool up = action == "stairs_up";
        if ((up && floor == std::numeric_limits<int>::max()) || (!up && floor == std::numeric_limits<int>::min())) return {};
        const int next = floor + (up ? 1 : -1);
        const char destination = city.tile(p,next);
        if (destination != '^' && destination != 'v' && destination != 'X') return {};
        pos = p;
        floor = next;
        minutes += 2;
        return String("你到达 Z=") + String::num_int64(floor) + text("。");
    }
    if (action == "rest") {
        minutes += 10;
        return text("你歇了一刻钟，起身继续赶路。" );
    }
    if (action == "inspect") {
        const char tile = city.tile(p,floor);
        const auto contents = fixture_contents(p);
        if (tile == 'F') return contents.is_empty() ? text("衣柜里空着。") : text("衣柜里收着：") + contents + text("。");
        if (const int limit = water_capacity_at(p); limit > 0) {
            return text(fixture(tile)) + text("里有 ") + String::num_int64(water_at(p)) + text(" / ") +
                   String::num_int64(limit) + text(" 毫升水。") + (contents.is_empty() ? String() : text(" 另有：") + contents);
        }
        if (!contents.is_empty()) return text(fixture(tile)) + text("：") + contents + text("。");
        return text("这里有") + text(fixture(tile)) + text("。");
    }
    if (action == "walk") return {};
    return run_quest_action(p,site(p));
}

String CanglingWorld::change_floor(int direction) {
    if (direction != 1 && direction != -1) return {};
    const auto action = direction > 0 ? String("stairs_up") : String("stairs_down");
    if (actions_at(pos).has(action)) return interact(pos,action);
    for (const auto offset : steps) {
        if (actions_at(pos+offset).has(action)) return interact(pos+offset,action);
    }
    return text("附近没有通往该高度的楼梯。");
}

String CanglingWorld::get_quest_text() const {
    static constexpr const char *quests[] = {"去南坊街市找药商沈青。", "去城东河滩采三株清露草。",
        "回南坊街市找沈青交付清露草。", "到南门内的吐纳院完成第一次吐纳。", "已踏入引气一层。"};
    return text(quests[quest]);
}

String CanglingWorld::run_quest_action(Vector2i p, const StringName &kind) {
    if (kind == StringName("merchant")) {
        switch (quest) {
            case 0:
                quest = 1; minutes += 2;
                return text("沈青：去城东河滩采三株清露草。你若带来，我便教你引气。");
            case 1:
                return text("沈青：沿大街向东走，过码头往南便是河滩。");
            case 2:
                quest = 3; herbs -= 3; coins += 12; minutes += 2;
                return text("你交付三株清露草，得了十二文。沈青传给你口诀，叫你去南门内的吐纳院。");
            case 3: return text("沈青：到吐纳院的石台静坐，莫急着引气。");
            default: return text("沈青：恭喜道友引气入体。");
        }
    }
    if (kind == StringName("herb")) {
        if (quest == 0) return text("草叶尖凝着露水，你尚辨不出它的药性。");
        if (quest >= 2) return text("今晨已采够药草，留些给来日吧。");
        const auto it = std::find(herb_tiles.begin(),herb_tiles.end(),p);
        if (it == herb_tiles.end()) return {};
        collected[it-herb_tiles.begin()] = true;
        ++herbs;
        minutes += 3;
        if (herbs == 3) {
            quest = 2;
            return text("三株清露草已集齐，回街市找沈青交付。");
        }
        return text("你采下一株清露草。");
    }
    if (kind == StringName("altar")) {
        if (quest == 3) {
            quest = 4; minutes += 30;
            return text("你依照口诀静坐，引第一缕灵气入体，踏入引气一层。");
        }
        return text(quest == 4 ? "灵气在丹田中缓缓流转。" : "石台上还沾着晨露。你尚未习得吐纳口诀。");
    }
    if (kind == StringName("ferryman")) return text("渡夫：晨雾没散，今天迟些开船。");
    return {};
}
}
