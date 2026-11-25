#include "world.hpp"
#include <algorithm>
#include <limits>

namespace cangling {
using namespace godot;
namespace {
String text(const char *s) { return String::utf8(s); }
const char *fixture(char tile) {
    switch (tile) {
        case 'b': return "床榻"; case 't': return "八仙桌"; case 'c': return "雕花木柜";
        case 'C': return "樟木货箱"; case 'k': return "长案柜台"; case 'u': return "青花水盆";
        case 'q': return "坐凳圈椅"; case 'r': return "中式书架"; case 'l': return "雕花书案";
        case 'h': return "青砖土灶"; case 'a': return "大陶缸"; case 'f': return "木篱";
        case 'g': return "花木"; case 'w': case 'O': return "雕花木窗"; case '%': return "残破木窗";
        case 'K': return "百子展柜"; case 'S': return "红木春凳"; case 'P': return "青花盆景";
        case 'F': return "顶箱衣柜"; case 'Y': return "行道树"; case 'L': return "宫灯柱";
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
    switch (effective_tile(p, floor)) {
        case 'D': case 'o': return "door";
        case '^': return "up";
        case 'v': return "down";
        case 'X': return "stairs";
        default: return {};
    }
}

Dictionary CanglingWorld::actions_at(Vector2i p) {
    Dictionary out;
    if (!in_city(p)) return out;
    const char tile = effective_tile(p, floor);
    if (tile == ' ') return out;
    const auto kind = site(p);
    if (kind == StringName("door")) {
        if (p != pos) out["door"] = text(tile == 'o' ? "关门 (c)" : "开门 (o)");
    } else if (kind == StringName("up")) out["stairs_up"] = text("上楼 (<)");
    else if (kind == StringName("down")) out["stairs_down"] = text("下楼 (>)");
    else if (kind == StringName("stairs")) {
        out["stairs_up"] = text("上楼 (<)");
        out["stairs_down"] = text("下楼 (>)");
    }
    else if (kind == StringName("merchant")) out["talk"] = text("与沈青交谈");
    else if (kind == StringName("ferryman")) out["talk"] = text("与渡夫交谈");
    else if (kind == StringName("altar")) out["cultivate"] = text(quest == 3 ? "在石台吐纳" : "查看吐纳石台");
    else if (kind == StringName("herb")) out["gather"] = text("采集清露草");

    if (tile == 'w' || tile == 'O') {
        out["window"] = text(tile == 'O' ? "关窗 (c)" : "开窗 (o)");
    }
    if (is_climbable_tile(tile) && p != pos) {
        out["climb"] = text("翻越 (e)");
    }
    if (is_smashable_tile(tile) && p != pos) {
        out["smash"] = text("砸碎 (s)");
    }
    if (tile == 'h') {
        out["warm_hearth"] = text("在灶台烤火取暖");
    }
    if (tile == 'u') {
        out["wash"] = text("洗漱净面解乏");
    }
    if (is_openable_container(tile)) {
        out["container"] = text(is_container_open(p) ? "查看柜内物品 (e)" : "打开并查看 (o/e)");
        if (is_container_open(p)) out["close_container"] = text("合上柜门 (c)");
    }
    if (fixture(tile)) {
        if (tile == 'b') out["rest"] = text("躺下歇息");
        else if (tile == 'q' || tile == 'S') out["rest"] = text("坐下休息");
        out["inspect"] = text("查看") + text(fixture(tile));
    }
    if (is_movable_furniture(tile) && p != pos) {
        if (grab_offset != Vector2i(0, 0) && pos + grab_offset == p) {
            out["release_grab"] = text("松开家具 (G)");
        } else {
            out["grab"] = text("抓取拖拽家具 (G)");
        }
    }

    const auto available = items_on(p);
    int item_sum = 0;
    for (int i = 0; i < item_types; ++i) item_sum += available[i];
    if (item_sum > 0 && (!is_openable_container(tile) || is_container_open(p) || tile == 'r')) {
        out["loot"] = text("拾取 / 食用此处物品 (g)");
    }
    if (std::string_view("btckKlruCaFqS").find(tile) != std::string_view::npos &&
        std::any_of(carried.begin(), carried.end(), [](int n) { return n != 0; })) {
        out["store"] = text("放入物品");
    }
    const int limit = water_capacity_at(p);
    if (limit) {
        const int amount = water_at(p);
        if (amount > 0) out["drink_vessel"] = text("直接饮水");
        if (amount > 0 && carried_water < bottle_capacity()) out["water_take"] = text("装入水壶…");
        if (amount < limit && carried_water > 0) out["water_pour"] = text("从水壶倒入…");
    }
    if (walkable(p) && p != pos && !out.has("walk")) out["walk"] = text("走到此处");
    return out;
}

String CanglingWorld::interact(Vector2i p, const String &action) {
    if (!near(p) || !actions_at(p).has(action)) return {};
    const char tile = effective_tile(p, floor);
    if (action == "door") {
        return tile == 'o' ? close_at(p) : open_at(p);
    }
    if (action == "window") {
        return tile == 'O' ? close_at(p) : open_at(p);
    }
    if (action == "smash") {
        return smash_at(p);
    }
    if (action == "climb") {
        return climb_at(p);
    }
    if (action == "warm_hearth") {
        rest_minutes(10, false);
        return text("你在青砖土灶旁烤火暖手，寒意与倦乏顿时消散不少。");
    }
    if (action == "wash") {
        char_state.fatigue = std::max(0.0, char_state.fatigue - 6.0);
        char_state.morale = std::min(50, char_state.morale + 3);
        advance_time(3);
        return text("你掬起青花盆里的凉水洗漱净面，顿时神清气爽。");
    }
    if (action == "close_container") {
        return close_at(p);
    }
    if (action == "grab") {
        return grab_furniture(p);
    }
    if (action == "release_grab") {
        return release_grab();
    }
    if (action == "drink_vessel") {
        const int available = water_at(p);
        if (available <= 0) return text("容器里已经没有水了。");
        const int take = std::min(available, 250);
        vessel_water[key(p, floor)] = available - take;
        int mins = 0;
        const String msg = char_state.drink_water(take, mins);
        minutes += mins;
        return msg;
    }
    if (action.begins_with("take_")) return take_item(p, action.substr(5).to_int());
    if (action == "stairs_up" || action == "stairs_down") {
        const bool up = action == "stairs_up";
        if ((up && floor == std::numeric_limits<int>::max()) || (!up && floor == std::numeric_limits<int>::min())) return {};
        const int next = floor + (up ? 1 : -1);
        const char destination = effective_tile(p, next);
        if (destination != '^' && destination != 'v' && destination != 'X') return {};
        grab_offset = {0, 0};
        pos = p;
        floor = next;
        advance_time(2);
        return String("你到达 ") + (floor == 0 ? text("地面层") : floor == 1 ? text("二层") : text("三层阁楼")) + text("。");
    }
    if (action == "rest") {
        const bool sleeping = (tile == 'b');
        rest_minutes(sleeping ? 20 : 10, sleeping);
        return sleeping ? text("你躺上床榻盖好锦被，小憩片刻，倦意消散不少。")
                        : text("你坐下歇了一刻钟，气息舒缓不少。");
    }
    if (action == "inspect") {
        const auto contents = fixture_contents(p);
        if (is_openable_container(tile) && !is_container_open(p) && tile != 'r') {
            return text(fixture(tile)) + text("目前关着（按 o 或 e 可打开查看）。");
        }
        if (const int limit = water_capacity_at(p); limit > 0) {
            return text(fixture(tile)) + text("里有 ") + String::num_int64(water_at(p)) + text(" / ") +
                   String::num_int64(limit) + text(" 毫升水。") + (contents.is_empty() ? String() : text(" 另有：") + contents);
        }
        if (!contents.is_empty()) return text(fixture(tile)) + text("：") + contents + text("。");
        return text("这里有") + text(fixture(tile)) + text("。");
    }
    if (action == "walk") return {};
    return run_quest_action(p, site(p));
}

String CanglingWorld::change_floor(int direction) {
    if (direction != 1 && direction != -1) return {};
    const auto action = direction > 0 ? String("stairs_up") : String("stairs_down");
    if (actions_at(pos).has(action)) return interact(pos, action);
    static const std::array<Vector2i, 8> adj{{{0,-1},{-1,0},{1,0},{0,1},{-1,-1},{1,-1},{-1,1},{1,1}}};
    for (const auto offset : adj) {
        if (actions_at(pos + offset).has(action)) return interact(pos + offset, action);
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
                quest = 1; advance_time(2);
                return text("沈青：去城东河滩采三株清露草。你若带来，我便教你引气。");
            case 1:
                return text("沈青：沿大街向东走，过码头往南便是河滩。");
            case 2:
                quest = 3; herbs -= 3; coins += 12; advance_time(2);
                return text("你交付三株清露草，得了十二文。沈青传给你口诀，叫你去南门内的吐纳院。");
            case 3: return text("沈青：到吐纳院的石台静坐，莫急着引气。");
            default: return text("沈青：恭喜道友引气入体。");
        }
    }
    if (kind == StringName("herb")) {
        if (quest == 0) return text("草叶尖凝着露水，你尚辨不出它的药性。");
        if (quest >= 2) return text("今晨已采够药草，留些给来日吧。");
        const auto it = std::find(herb_tiles.begin(), herb_tiles.end(), p);
        if (it == herb_tiles.end()) return {};
        collected[it - herb_tiles.begin()] = true;
        ++herbs;
        advance_time(3);
        if (herbs == 3) {
            quest = 2;
            return text("三株清露草已集齐，回街市找沈青交付。");
        }
        return text("你采下一株清露草。");
    }
    if (kind == StringName("altar")) {
        if (quest == 3) {
            quest = 4; rest_minutes(30, false);
            return text("你依照口诀静坐，引第一缕灵气入体，踏入引气一层。");
        }
        return text(quest == 4 ? "灵气在丹田中缓缓流转。" : "石台上还沾着晨露。你尚未习得吐纳口诀。");
    }
    if (kind == StringName("ferryman")) return text("渡夫：晨雾没散，今天迟些开船。");
    return {};
}
}
