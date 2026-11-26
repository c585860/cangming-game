#include "bounties.hpp"
#include <godot_cpp/variant/variant.hpp>
#include <algorithm>
#include <cmath>
#include <cstring>

namespace cangling {
using namespace godot;

const std::array<BountyDef, kBountyCount> &bounty_catalog() {
    static const std::array<BountyDef, kBountyCount> kBounties{{
        {"escort_dock", "镇远镖局 · 漕运短镖", "镇远镖局",
         "先赴西市镇远镖局(101,115)领镖单，再沿东关大街护送至水埠码头交给「老船夫」。",
         {101, 115}, {167, 166}, "boatman", 22, 32, 20, 5},
        {"herb_supply", "回春堂 · 急症药材单", "回春堂药铺",
         "筹集 2 束「干草药」或 1 份「金创纱布」（可采集、制作或购得），送交回春堂「平大夫」。",
         {0, 0}, {130, 113}, "herbalist", 18, 28, 16, 4},
        {"tavern_feast", "醉仙楼 · 雅间急膳单", "醉仙楼",
         "备好 1 份「扬州阳春面」、「红烧狮子头」或「热白米饭」（可烹饪或购得），送至春风茶馆交予「说书先生」。",
         {0, 0}, {178, 126}, "storyteller", 20, 30, 18, 4},
        {"academy_rubbing", "文昌书院 · 五亭碑文抄录", "文昌书院",
         "前往西北翠微湖「五亭桥」(61,52)实地勘察抄录碑文，归来交予文昌书院「顾夫子」。",
         {61, 52}, {130, 88}, "scholar", 24, 36, 22, 6},
        {"martial_trial", "扬威武馆 · 演武试招", "扬威武馆",
         "在扬威武馆与陪练弟子、陈馆主或周教头完成 1 场演武切磋，随后向「陈馆主」复命。",
         {0, 0}, {100, 126}, "martial_master", 25, 38, 25, 6},
    }};
    return kBounties;
}

int find_bounty_index(const char *id) {
    if (!id) return -1;
    const auto &cat = bounty_catalog();
    for (std::size_t i = 0; i < cat.size(); ++i) {
        if (std::strcmp(cat[i].id, id) == 0) return static_cast<int>(i);
    }
    return -1;
}

void BountyTracker::reset() {
    active_index = -1;
    waypoint_done = false;
    start_spar_total = 0;
    completed_count = 0;
}

void BountyTracker::update_proximity(Vector2i player_pos, int current_spar_total) {
    if (active_index < 0 || active_index >= static_cast<int>(kBountyCount)) return;
    const auto &def = bounty_catalog()[static_cast<std::size_t>(active_index)];
    if (def.waypoint_pos != Vector2i(0, 0) && !waypoint_done) {
        const Vector2i d = (player_pos - def.waypoint_pos).abs();
        if (std::max(d.x, d.y) <= 4) {
            waypoint_done = true;
        }
    }
    if (std::strcmp(def.id, "martial_trial") == 0 && current_spar_total > start_spar_total) {
        waypoint_done = true;
    }
}

bool BountyTracker::is_ready_to_turn_in(const ItemCounts &carried, int current_spar_total) const {
    if (active_index < 0 || active_index >= static_cast<int>(kBountyCount)) return false;
    const auto &def = bounty_catalog()[static_cast<std::size_t>(active_index)];
    if (std::strcmp(def.id, "escort_dock") == 0 || std::strcmp(def.id, "academy_rubbing") == 0) {
        return waypoint_done;
    }
    if (std::strcmp(def.id, "martial_trial") == 0) {
        return waypoint_done || current_spar_total > start_spar_total;
    }
    if (std::strcmp(def.id, "herb_supply") == 0) {
        const int herb = find_item_by_key("herb_bundle");
        const int band = find_item_by_key("bandage");
        return (herb >= 0 && carried[herb] >= 2) || (band >= 0 && carried[band] >= 1);
    }
    if (std::strcmp(def.id, "tavern_feast") == 0) {
        const int nood = find_item_by_key("yangchun_noodles");
        const int lion = find_item_by_key("lion_head");
        const int rice = find_item_by_key("rice_bowl");
        return (nood >= 0 && carried[nood] >= 1) || (lion >= 0 && carried[lion] >= 1) || (rice >= 0 && carried[rice] >= 1);
    }
    return false;
}

String BountyTracker::accept(int idx, int current_spar_total) {
    if (idx < 0 || idx >= static_cast<int>(kBountyCount)) return String::utf8("未找到该项江湖委托。");
    active_index = idx;
    waypoint_done = false;
    start_spar_total = current_spar_total;
    const auto &def = bounty_catalog()[static_cast<std::size_t>(idx)];
    return String::utf8("你揭下告示，接取了江湖委托【") + String::utf8(def.title) + String::utf8("】：") + String::utf8(def.desc);
}

String BountyTracker::abandon() {
    if (active_index < 0) return String::utf8("你当前没有进行中的江湖委托。");
    const auto &def = bounty_catalog()[static_cast<std::size_t>(active_index)];
    const String name = String::utf8(def.title);
    active_index = -1;
    waypoint_done = false;
    return String::utf8("你放弃了当前委托【") + name + String::utf8("】。");
}

String BountyTracker::try_turn_in(const char *npc_id, ItemCounts &carried, int &coins,
                                  CharacterState &ch, SkillSet &skills) {
    if (active_index < 0 || active_index >= static_cast<int>(kBountyCount) || !npc_id) return {};
    const auto &def = bounty_catalog()[static_cast<std::size_t>(active_index)];
    if (std::strcmp(def.turnin_npc_id, npc_id) != 0) return {};
    if (!is_ready_to_turn_in(carried, ch.spar_total)) {
        return String::utf8("委托【") + String::utf8(def.title) + String::utf8("】尚未完成要求：") + String::utf8(def.desc);
    }
    // Consume delivery items for supply bounties
    if (std::strcmp(def.id, "herb_supply") == 0) {
        const int herb = find_item_by_key("herb_bundle");
        const int band = find_item_by_key("bandage");
        if (herb >= 0 && carried[herb] >= 2) carried[herb] -= 2;
        else if (band >= 0 && carried[band] >= 1) carried[band] -= 1;
    } else if (std::strcmp(def.id, "tavern_feast") == 0) {
        const int nood = find_item_by_key("yangchun_noodles");
        const int lion = find_item_by_key("lion_head");
        const int rice = find_item_by_key("rice_bowl");
        if (nood >= 0 && carried[nood] >= 1) carried[nood] -= 1;
        else if (lion >= 0 && carried[lion] >= 1) carried[lion] -= 1;
        else if (rice >= 0 && carried[rice] >= 1) carried[rice] -= 1;
    }

    coins += def.coin_reward;
    const int pot = skills.add_potential(def.pot_reward);
    skills.add_combat_exp(def.exp_reward);
    ch.reputation += def.rep_reward;
    ch.morale = std::min(50, ch.morale + 8);
    ++completed_count;
    const String title = String::utf8(def.title);
    active_index = -1;
    waypoint_done = false;
    return String::utf8("你圆满完成了江湖委托【") + title + String::utf8("】！获赏 ") +
           String::num_int64(def.coin_reward) + String::utf8(" 文铜钱、潜能 +") +
           String::num_int64(pot) + String::utf8("、阅历 +") + String::num_int64(def.exp_reward) +
           String::utf8("、江湖声望 +") + String::num_int64(def.rep_reward) + String::utf8("！");
}

Array BountyTracker::list_to_array(const ItemCounts &carried, int current_spar_total) const {
    Array out;
    const auto &cat = bounty_catalog();
    for (std::size_t i = 0; i < kBountyCount; ++i) {
        const auto &def = cat[i];
        const bool is_act = (active_index == static_cast<int>(i));
        Dictionary row;
        row["index"] = static_cast<int>(i);
        row["id"] = String::utf8(def.id);
        row["title"] = String::utf8(def.title);
        row["giver"] = String::utf8(def.giver);
        row["desc"] = String::utf8(def.desc);
        row["waypoint_pos"] = def.waypoint_pos;
        row["turnin_pos"] = def.turnin_pos;
        row["coin_reward"] = def.coin_reward;
        row["pot_reward"] = def.pot_reward;
        row["exp_reward"] = def.exp_reward;
        row["rep_reward"] = def.rep_reward;
        row["active"] = is_act;
        row["ready"] = is_act && is_ready_to_turn_in(carried, current_spar_total);
        row["waypoint_done"] = is_act && waypoint_done;
        out.append(row);
    }
    return out;
}

Dictionary BountyTracker::active_dict(const ItemCounts &carried, int current_spar_total) const {
    Dictionary d;
    d["active"] = (active_index >= 0 && active_index < static_cast<int>(kBountyCount));
    d["completed_count"] = completed_count;
    if (active_index >= 0 && active_index < static_cast<int>(kBountyCount)) {
        const auto &def = bounty_catalog()[static_cast<std::size_t>(active_index)];
        d["index"] = active_index;
        d["id"] = String::utf8(def.id);
        d["title"] = String::utf8(def.title);
        d["desc"] = String::utf8(def.desc);
        d["waypoint_pos"] = def.waypoint_pos;
        d["turnin_pos"] = def.turnin_pos;
        d["waypoint_done"] = waypoint_done;
        d["ready"] = is_ready_to_turn_in(carried, current_spar_total);
    }
    return d;
}

Dictionary BountyTracker::save_dict() const {
    Dictionary d;
    d["active_index"] = active_index;
    d["waypoint_done"] = waypoint_done;
    d["start_spar_total"] = start_spar_total;
    d["completed_count"] = completed_count;
    return d;
}

void BountyTracker::load_dict(const Dictionary &d) {
    reset();
    if (d.has("active_index")) {
        const int idx = static_cast<int>(d["active_index"]);
        active_index = (idx >= 0 && idx < static_cast<int>(kBountyCount)) ? idx : -1;
    }
    if (d.has("waypoint_done")) waypoint_done = static_cast<bool>(d["waypoint_done"]);
    if (d.has("start_spar_total")) start_spar_total = std::max(0, static_cast<int>(d["start_spar_total"]));
    if (d.has("completed_count")) completed_count = std::max(0, static_cast<int>(d["completed_count"]));
}

} // namespace cangling
