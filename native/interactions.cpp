#include "world.hpp"
#include <algorithm>
#include <limits>
#include <string_view>

namespace cangling {
using namespace godot;
namespace {
String text(const char *s) { return String::utf8(s); }

const char *fixture(char tile) {
    switch (tile) {
        case 'b': return "床榻"; case 't': return "八仙桌"; case 'c': return "雕花木柜";
        case 'C': return "樟木货箱"; case 'k': return "长案柜台"; case 'u': return "青花水盆";
        case 'q': return "坐凳圈椅"; case 'r': return "中式书架"; case 'l': return "雕花书案";
        case 'h': return "青砖炉灶"; case 'a': return "大陶缸"; case 'f': return "木篱";
        case 'g': return "花木"; case 'w': case 'O': return "雕花木窗"; case '%': return "残破木窗";
        case 'K': return "百子展柜"; case 'S': return "红木春凳"; case 'P': return "青花盆景";
        case 'F': return "顶箱衣柜"; case 'Y': return "垂柳古树"; case 'L': return "宫灯柱";
        default: return nullptr;
    }
}

int npc_index_at(Vector2i p) {
    for (std::size_t i = 0; i < kYangzhouNpcs.size(); ++i) {
        if (kYangzhouNpcs[i].pos == p) return static_cast<int>(i);
    }
    return -1;
}

String npc_dialogue(int idx, int turn) {
    switch (idx) {
        case 0: { // 冼老板 (醉仙楼)
            static constexpr const char *lines[] = {
                "冼老板笑道：「客官请进！醉仙楼后厨有主灶、炖炉、切菜案与温酒蒸笼四处工位，想来帮厨赚铜钱与潜能，先跟我请教入门『基本厨艺』！」",
                "冼老板拨着算盘：「学武先要吃饱喝足！空腹练功伤身又耗气血，来醉仙楼吃顿热饭再上工最稳妥。」",
                "冼老板压低声音：「近来南来北往的镖师侠客齐聚沧灵城，楼上都在议论江南武林旧事，听得人热血沸腾。」",
            };
            return text(lines[turn % 3]);
        }
        case 1: { // 王铁匠 (王记铁匠铺)
            static constexpr const char *lines[] = {
                "王铁匠挥锤落火星，朗声道：「叮当响了一早上！我这锻造坊有南北风炉、淬火水槽与锻铁砧四处工位，先找老王请教『基本锻造』就能上工！」",
                "王铁匠擦把汗：「打铁既赚工钱又长潜能，顺便还能跟我学几手基本刀法与基本棍法。」",
                "王铁匠指着案上斧撬：「好刀好剑全凭百炼千锤，行走江湖防身破障都少不了。」",
            };
            return text(lines[turn % 3]);
        }
        case 2: { // 平大夫 (回春堂药铺)
            static constexpr const char *lines[] = {
                "平大夫拈须道：「行走江湖，跌打损伤在所难免。回春堂有百子柜、捣药台、切药案与煎药炉四处药坊工位，先请教入门『基本药学』便可帮忙炮制药材。」",
                "平大夫整理药屉：「精通基本药学后，不仅能在药坊谋生赚潜能，用金创纱布包扎时的疗伤回血也会大幅提升。」",
                "平大夫淡笑：「习武先养气血，基本内功修得越深，全身气血根基越厚；切莫饿着肚子强行练功。」",
            };
            return text(lines[turn % 3]);
        }
        case 3: { // 陈馆主 (扬威武馆)
            static constexpr const char *lines[] = {
                "陈馆主抱拳沉声道：「扬威武馆立于沧灵城三十载！我主授基本内功、轻功、招架与空手六艺；进里间兵器堂可向周教头请教兵刃与暗器！」",
                "陈馆主目露精光：「百八十级之前，或耗潜能请教名师，或吃饱了在木人桩旁缓慢自练；唯有臻至一百八十级宗师境后，方能耗费潜能自行研究突破！」",
                "陈馆主望向演武场：「习得任意一门基础武学后，便可在演武场的木人桩与兵器架旁助教演武，赚取铜钱、潜能与江湖阅历！」",
            };
            return text(lines[turn % 3]);
        }
        case 4: { // 周教头 (扬威武馆兵器堂)
            static constexpr const char *lines[] = {
                "周教头横枪抱拳：「少侠来得正好！剑、刀、杖、棍、枪、鞭六般兵刃与基本暗器，皆可耗费潜能向我请教入门！」",
                "周教头轻抚兵器架：「一寸长一寸强，一寸短一寸险。先选一门趁手兵刃入门，再去兵器架与武谱石案旁演练助教，事半功倍！」",
                "周教头沉声道：「练武极耗气力与口粮，饿着肚子挥刀舞剑不但难进寸功，还易伤及筋骨。」",
            };
            return text(lines[turn % 3]);
        }
        case 5: { // 顾夫子 (文昌书院)
            static constexpr const char *lines[] = {
                "顾夫子执卷微笑：「文昌书院清雅宁静，少侠可先向老夫请教『读书写字』。识文断字越精，日后耗潜能请教武学时领悟越快！」",
                "顾夫子指着满室书案：「习得读书写字后，书院的抄书案几与藏书架、乃至城中当铺钱庄的账台，皆可安心落座劳作，赚取润笔费与潜能。」",
                "顾夫子叹道：「莫道书生无用，天下高深武学秘籍，哪一部不需要扎实的文墨功底？」",
            };
            return text(lines[turn % 3]);
        }
        case 6: { // 唐掌柜 (利源当铺)
            static constexpr const char *lines[] = {
                "唐掌柜推推眼镜：「利源当铺与东街通济钱庄都缺识字的帮手！只要习得『读书写字』，算盘账台与库房验货箱随时欢迎你来干活。」",
                "唐掌柜招招手：「若还没来得及去文昌书院拜访顾夫子，老唐也能先教你几级账房识字入门！」",
                "唐掌柜提醒道：「出门在外，银钱盘缠与干粮水壶缺一不可，先攒些铜钱和潜能傍身最稳妥。」",
            };
            return text(lines[turn % 3]);
        }
        case 7: { // 老船夫 (水埠码头)
            static constexpr const char *lines[] = {
                "老船夫摇着蒲扇笑：「沧灵小秦淮河曲折盘旋穿城而过，一桨摇过南门桥、虹桥、青莲桥、五亭桥，整座水城尽在画里！」",
                "老船夫指着岸边四处货垛：「码头扛货讲究下盘稳、气息长！只要习得『基本拳脚』或『基本内功』，货箱、货缸与栈桥四处工位任你干活！」",
                "老船夫笑道：「若还没去过扬威武馆，老汉也能教你几手船上站桩的拳脚与轻功启蒙。」",
            };
            return text(lines[turn % 3]);
        }
        default: { // 说书先生 (春风茶馆)
            static constexpr const char *lines[] = {
                "说书先生啪地一拍醒木：「诸位听真！烟雨三月沧灵城，翠微湖五亭桥畔曾有两位剑客踏波论剑，那一夜水花飞溅三丈！」",
                "说书先生摇扇吟道：「昔日沧灵城中，多少名震江湖的大侠，都是从学会一门基本功、在城中工坊攒潜能一步步走出去的！」",
                "说书先生抿口清茶：「累了便坐下听段评书，既解乏养心，还能悟出几点江湖潜能；老夫亦可指点些许读书写字入门。」",
            };
            return text(lines[turn % 3]);
        }
    }
}
} // namespace

StringName CanglingWorld::site(Vector2i p) {
    if (!in_city(p)) return {};
    if (floor == 0) {
        if (const NpcDef *npc = npc_at_tile(p)) {
            return StringName(npc->id);
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

    if (floor == 0) {
        if (const NpcDef *npc = npc_at_tile(p)) {
            out["talk"] = text("与") + text(npc->name) + text("交谈 (C)");
            out["learn_menu"] = text("向") + text(npc->name) + text("请教技艺 (消耗潜能)");
            if (std::string_view(npc->id) == "storyteller") {
                out["listen"] = text("坐听江湖评书 (+心境 / +专注 / +潜能)");
            }
            return out;
        }
        if (const WorkstationDef *ws = workstation_at_tile(p)) {
            const bool unlocked = skill_meets_station_req(skill_set, *ws);
            String label = text("工位劳作：") + text(ws->action_verb) + text(" (+") +
                           String::num_int64(ws->coin_pay) + text("文 / +") +
                           String::num_int64(ws->pot_gain) + text("潜能)");
            if (!unlocked) {
                label += text(" [未学前置]");
            }
            out["workstation"] = label;
        }
    }

    const auto kind = site(p);
    if (kind == StringName("door")) {
        if (p != pos) out["door"] = text(tile == 'o' ? "关门 (c)" : "开门 (o)");
    } else if (kind == StringName("up")) out["stairs_up"] = text("上楼 (<)");
    else if (kind == StringName("down")) out["stairs_down"] = text("下楼 (>)");
    else if (kind == StringName("stairs")) {
        out["stairs_up"] = text("上楼 (<)");
        out["stairs_down"] = text("下楼 (>)");
    }

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
        out["warm_hearth"] = text("在炉灶旁烤火取暖");
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
    if (floor == 0) {
        const int nidx = npc_index_at(p);
        if (nidx >= 0) {
            const NpcDef &npc = kYangzhouNpcs[static_cast<std::size_t>(nidx)];
            if (action == "talk") {
                const int turn = npc_talk_count[static_cast<std::size_t>(nidx)]++;
                return npc_dialogue(nidx, turn);
            }
            if (action == "listen" && std::string_view(npc.id) == "storyteller") {
                rest_minutes(npc.job_minutes, false);
                char_state.morale = std::min(50, char_state.morale + 10);
                char_state.focus = std::min(120, char_state.focus + 8);
                const int gained_pot = skill_set.add_potential(8);
                skill_set.add_combat_exp(5);
                return text("你在春风茶馆坐听了一段沧灵城武林评书，听得心潮澎湃，心境与专注大为提升，另悟得潜能 +") +
                       String::num_int64(gained_pot) + text("！");
            }
            if (action == "learn_menu") {
                return text("请打开向") + text(npc.name) + text("请教技艺面板。");
            }
        }
        if (action == "workstation" && workstation_at_tile(p) != nullptr) {
            return complete_workstation(p);
        }
    }

    const char tile = effective_tile(p, floor);
    if (action == "door") return tile == 'o' ? close_at(p) : open_at(p);
    if (action == "window") return tile == 'O' ? close_at(p) : open_at(p);
    if (action == "smash") return smash_at(p);
    if (action == "climb") return climb_at(p);
    if (action == "warm_hearth") {
        rest_minutes(10, false);
        return text("你在青砖炉灶旁烤火暖手，寒意与倦乏顿时消散不少。");
    }
    if (action == "wash") {
        char_state.fatigue = std::max(0.0, char_state.fatigue - 6.0);
        char_state.morale = std::min(50, char_state.morale + 3);
        return text("你掬起青花盆里的凉水洗漱净面，顿时神清气爽。");
    }
    if (action == "close_container") return close_at(p);
    if (action == "grab") return grab_furniture(p);
    if (action == "release_grab") return release_grab();
    if (action == "drink_vessel") {
        const int available = water_at(p);
        if (available <= 0) return text("容器里已经没有水了。");
        const int take = std::min(available, 250);
        vessel_water[key(p, floor)] = available - take;
        int mins = 0;
        return char_state.drink_water(take, mins);
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
        return text("你来到 ") + (floor == 0 ? text("一层") : floor == 1 ? text("二层") : text("三层阁楼")) + text("。");
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
    return {};
}

String CanglingWorld::change_floor(int direction) {
    if (direction != 1 && direction != -1) return {};
    const auto action = direction > 0 ? String("stairs_up") : String("stairs_down");
    if (actions_at(pos).has(action)) return interact(pos, action);
    static const std::array<Vector2i, 8> adj{{{0,-1},{-1,0},{1,0},{0,1},{-1,-1},{1,-1},{-1,1},{1,1}}};
    for (const auto offset : adj) {
        if (actions_at(pos + offset).has(action)) return interact(pos + offset, action);
    }
    return text("附近没有通往该楼层的楼梯。");
}

String CanglingWorld::get_quest_text() const {
    if (skill_set.learned_count() == 0) {
        return text("初入沧灵南门：你尚未习得任何技艺。先用随身 30 点潜能向城中师傅请教入门（醉仙楼冼老板、回春堂平大夫、文昌书院顾夫子、扬威武馆陈馆主/周教头、王记铁匠铺王铁匠），再到对应工坊实体工位劳作赚铜钱与潜能！");
    }
    return text("沧灵城修行谋生：已习得 ") + String::num_int64(skill_set.learned_count()) + text(" 门技艺、累计工位劳作 ") +
           String::num_int64(jobs_done) + text(" 次，随身 ") + String::num_int64(coins) + text(" 文铜钱、") +
           String::num_int64(skill_set.potential) + text(" 点潜能。");
}

String CanglingWorld::run_quest_action(Vector2i, const StringName &) {
    return {};
}
}
