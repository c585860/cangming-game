#!/usr/bin/env python3
"""
Deterministic vanilla CCB (Cataclysm-Cleanwater-Bomb) data exporter.
Reads 100% of Cataclysm-Cleanwater-Bomb/data/json/{items,mutations,monsters},
resolves copy-from / abstract / relative / proportional / extend / delete
inheritance faithfully per item_factory.cpp, applies official zh_CN translations
from lang/mo/zh_CN/LC_MESSAGES/cataclysm-dda.mo, and writes compact runtime data
files into cangling-city/packs/cataclysm/vanilla/.
"""

import copy
import gettext
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(r"d:\Project\CDDA-COOP\ccb\Cataclysm-Cleanwater-Bomb")
OUT_DIR = Path(r"d:\Project\CDDA-COOP\ccb\cangling-city\packs\cataclysm\vanilla")
MO_PATH = ROOT / "lang" / "mo" / "zh_CN" / "LC_MESSAGES" / "cataclysm-dda.mo"
TILE_CONFIG = ROOT / "gfx" / "MSX++UndeadPeopleEdition" / "tile_config.json"


def load_translator():
    if MO_PATH.exists():
        with open(MO_PATH, "rb") as f:
            return gettext.GNUTranslations(f)
    return gettext.NullTranslations()


def extract_text(val, tr):
    if isinstance(val, str):
        return tr.gettext(val) if val else ""
    if isinstance(val, dict):
        ctxt = val.get("ctxt")
        s = val.get("str") or val.get("str_sp") or val.get("str_pl") or ""
        if not s:
            return ""
        if ctxt:
            res = tr.pgettext(ctxt, s)
            if res != s:
                return res
        return tr.gettext(s)
    return ""


def extract_en(val):
    if isinstance(val, str):
        return val
    if isinstance(val, dict):
        return val.get("str") or val.get("str_sp") or val.get("str_pl") or ""
    return ""


def parse_mass_g(val):
    if isinstance(val, (int, float)):
        return int(round(val))
    if not isinstance(val, str):
        return 0
    total = 0.0
    for m in re.finditer(r"([\d.]+)\s*(kg|g|mg|lb|oz)", val.lower()):
        n = float(m.group(1))
        u = m.group(2)
        if u == "kg":
            total += n * 1000.0
        elif u == "g":
            total += n
        elif u == "mg":
            total += n * 0.001
        elif u == "lb":
            total += n * 453.592
        elif u == "oz":
            total += n * 28.3495
    return int(round(total))


def parse_vol_ml(val):
    if isinstance(val, (int, float)):
        return int(round(val * 250))
    if not isinstance(val, str):
        return 0
    total = 0.0
    for m in re.finditer(r"([\d.]+)\s*(l|ml)", val.lower()):
        n = float(m.group(1))
        u = m.group(2)
        if u == "l":
            total += n * 1000.0
        else:
            total += n
    return int(round(total))


def clean_tsv(s):
    if not s:
        return ""
    return s.replace("\t", " ").replace("\r", " ").replace("\n", " ").strip()


def merge_copy_from(raw_map):
    """Resolve copy-from inheritance with relative/proportional/extend/delete."""
    resolved = {}
    visiting = set()

    def apply_patch(base, child):
        out = copy.deepcopy(base)
        for k, v in child.items():
            if k in ("copy-from", "relative", "proportional", "extend", "delete", "abstract", "//", "//~"):
                continue
            out[k] = copy.deepcopy(v)

        rel = child.get("relative")
        if isinstance(rel, dict):
            for k, v in rel.items():
                if isinstance(v, (int, float)) and isinstance(out.get(k), (int, float)):
                    out[k] = out[k] + v
                elif k == "weight" and isinstance(v, str):
                    out[k] = f"{max(0, parse_mass_g(out.get(k, 0)) + parse_mass_g(v))} g"
                elif k == "volume" and isinstance(v, str):
                    out[k] = f"{max(0, parse_vol_ml(out.get(k, 0)) + parse_vol_ml(v))} ml"
                elif k == "melee_damage" and isinstance(v, dict):
                    md = out.get("melee_damage")
                    if not isinstance(md, dict):
                        md = {}
                    for dk, dv in v.items():
                        if isinstance(dv, (int, float)):
                            md[dk] = md.get(dk, 0) + dv
                    out["melee_damage"] = md

        prop = child.get("proportional")
        if isinstance(prop, dict):
            for k, v in prop.items():
                if isinstance(v, (int, float)) and isinstance(out.get(k), (int, float)):
                    out[k] = out[k] * v
                elif k == "weight" and isinstance(v, (int, float)):
                    out[k] = f"{int(round(parse_mass_g(out.get(k, 0)) * v))} g"
                elif k == "volume" and isinstance(v, (int, float)):
                    out[k] = f"{int(round(parse_vol_ml(out.get(k, 0)) * v))} ml"
                elif k == "melee_damage" and isinstance(v, dict):
                    md = out.get("melee_damage")
                    if isinstance(md, dict):
                        for dk, dv in v.items():
                            if isinstance(dv, (int, float)) and dk in md:
                                md[dk] = int(round(md[dk] * dv))

        ext = child.get("extend")
        if isinstance(ext, dict):
            for k, v in ext.items():
                if isinstance(v, list):
                    cur = out.get(k)
                    if not isinstance(cur, list):
                        cur = []
                    for elem in v:
                        if elem not in cur:
                            cur.append(elem)
                    out[k] = cur

        dele = child.get("delete")
        if isinstance(dele, dict):
            for k, v in dele.items():
                if isinstance(v, list) and isinstance(out.get(k), list):
                    out[k] = [e for e in out[k] if e not in v]

        return out

    def resolve_one(oid):
        if oid in resolved:
            return resolved[oid]
        if oid in visiting or oid not in raw_map:
            return {}
        visiting.add(oid)
        obj = raw_map[oid]
        parent_id = obj.get("copy-from")
        if parent_id and parent_id != oid and parent_id in raw_map:
            base = resolve_one(parent_id)
            merged = apply_patch(base, obj)
        else:
            merged = copy.deepcopy(obj)
        visiting.remove(oid)
        resolved[oid] = merged
        return merged

    for oid in raw_map:
        resolve_one(oid)
    return resolved


def load_json_dir(directory):
    entries = []
    for p in sorted(directory.rglob("*.json")):
        try:
            with open(p, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, list):
                entries.extend(data)
            elif isinstance(data, dict):
                entries.append(data)
        except Exception as e:
            print(f"[WARN] Failed parsing {p}: {e}", file=sys.stderr)
    return entries


def extract_armor_stats(obj):
    covers = set()
    enc = 0
    warmth = int(obj.get("warmth", 0) or 0)
    env_res = int(obj.get("environmental_protection", 0) or 0)
    storage_ml = 0
    a_bash = 0
    a_cut = 0
    a_stab = 0
    coverage = 0

    for ad in (obj.get("armor") or []):
        if not isinstance(ad, dict):
            continue
        enc = max(enc, int(ad.get("encumbrance", 0) or 0) if isinstance(ad.get("encumbrance"), (int, float)) else 0)
        if isinstance(ad.get("encumbrance"), list) and ad["encumbrance"]:
            enc = max(enc, int(ad["encumbrance"][0] or 0))
        coverage = max(coverage, int(ad.get("coverage", 0) or 0))
        for c in (ad.get("covers") or []):
            if isinstance(c, str):
                covers.add(c)
        # Approximate material thickness protection matching CCB material defaults
        thick = float(ad.get("material_thickness", 0) or 0)
        mats = ad.get("material") or obj.get("material") or []
        best_b, best_c, best_s = 0.0, 0.0, 0.0
        for m in mats:
            mid = m.get("type", "") if isinstance(m, dict) else (m if isinstance(m, str) else "")
            mt = float(m.get("thickness", thick) if isinstance(m, dict) else thick)
            if mt <= 0:
                mt = 1.0
            ml = mid.lower()
            if "steel" in ml or "iron" in ml or "alloy" in ml or "ceramic" in ml:
                best_b, best_c, best_s = max(best_b, mt * 3.5), max(best_c, mt * 6.0), max(best_s, mt * 5.0)
            elif "kevlar" in ml or "nomex" in ml or "chitin" in ml:
                best_b, best_c, best_s = max(best_b, mt * 2.5), max(best_c, mt * 4.5), max(best_s, mt * 3.5)
            elif "leather" in ml or "rubber" in ml or "neoprene" in ml or "plastic" in ml:
                best_b, best_c, best_s = max(best_b, mt * 1.8), max(best_c, mt * 2.6), max(best_s, mt * 2.0)
            else:
                best_b, best_c, best_s = max(best_b, mt * 0.9), max(best_c, mt * 1.1), max(best_s, mt * 0.8)
        a_bash = max(a_bash, int(round(best_b)))
        a_cut = max(a_cut, int(round(best_c)))
        a_stab = max(a_stab, int(round(best_s)))

    for pk in (obj.get("pocket_data") or []):
        if isinstance(pk, dict) and pk.get("pocket_type", "CONTAINER") == "CONTAINER":
            storage_ml += parse_vol_ml(pk.get("max_contains_volume", 0))

    # Map covers to compact 6-bit mask: H=1, T=2, LA=4, RA=8, LL=16, RL=32
    mask = 0
    for c in covers:
        cl = c.lower()
        if "head" in cl or "eyes" in cl or "mouth" in cl:
            mask |= 1
        elif "torso" in cl:
            mask |= 2
        elif "arm_l" in cl or "hand_l" in cl:
            mask |= 4
        elif "arm_r" in cl or "hand_r" in cl:
            mask |= 8
        elif "arm" in cl or "hand" in cl:
            mask |= 12
        elif "leg_l" in cl or "foot_l" in cl:
            mask |= 16
        elif "leg_r" in cl or "foot_r" in cl:
            mask |= 32
        elif "leg" in cl or "foot" in cl or "feet" in cl:
            mask |= 48

    return mask, enc, warmth, env_res, storage_ml, a_bash, a_cut, a_stab, coverage


def extract_vitamins_and_use(obj):
    vits = {}
    for v in (obj.get("vitamins") or []):
        if isinstance(v, list) and len(v) >= 2 and isinstance(v[0], str):
            val = v[1]
            if isinstance(val, (int, float)):
                vits[v[0]] = int(val)
    ua = obj.get("use_action")
    use_tags = []

    def inspect_ua(u):
        if isinstance(u, str):
            use_tags.append(u.lower())
        elif isinstance(u, dict):
            ut = str(u.get("type", "")).lower()
            if ut:
                use_tags.append(ut)
            for v in (u.get("vitamins") or []):
                if isinstance(v, list) and len(v) >= 2 and isinstance(v[0], str):
                    if len(v) >= 3 and isinstance(v[1], (int, float)) and isinstance(v[2], (int, float)):
                        vits[v[0]] = int((v[1] + v[2]) // 2)
                    elif isinstance(v[1], (int, float)):
                        vits[v[0]] = int(v[1])
            for eff in (u.get("effects") or []):
                if isinstance(eff, dict) and eff.get("id"):
                    use_tags.append("eff:" + str(eff["id"]))
            if u.get("heal"):
                use_tags.append("heal")
        elif isinstance(u, list):
            for sub in u:
                inspect_ua(sub)

    inspect_ua(ua)
    return vits, sorted(set(use_tags))


def export_items(tr):
    entries = load_json_dir(ROOT / "data" / "json" / "items")
    # Also scan core item files under data/json if any
    ITEM_TYPES = {
        "ITEM", "GENERIC", "TOOL", "ARMOR", "COMESTIBLE", "GUN", "AMMO",
        "BOOK", "MAGAZINE", "TOOLMOD", "GUNMOD", "BIONIC_ITEM", "PET_ARMOR",
        "BATTERY", "ENGINE", "WHEEL", "TOOL_ARMOR"
    }
    raw_map = {}
    concrete_ids = []
    for e in entries:
        if not isinstance(e, dict):
            continue
        t = e.get("type", "")
        if t not in ITEM_TYPES:
            continue
        oid = e.get("id") or e.get("abstract")
        if not oid or not isinstance(oid, str):
            continue
        raw_map[oid] = e
        if "id" in e and "abstract" not in e:
            concrete_ids.append(oid)

    resolved = merge_copy_from(raw_map)
    seen = set()
    unique_ids = []
    for cid in concrete_ids:
        if cid not in seen:
            seen.add(cid)
            unique_ids.append(cid)
    unique_ids.sort()

    # Load known sprite IDs from undead_people tile_config.json so every item maps to a real sprite!
    known_tiles = set()
    if TILE_CONFIG.exists():
        try:
            with open(TILE_CONFIG, "r", encoding="utf-8") as f:
                tc = json.load(f)
            for sheet in tc.get("tiles-new", []):
                for t in sheet.get("tiles", []):
                    tid = t.get("id")
                    if isinstance(tid, str):
                        known_tiles.add(tid)
                    elif isinstance(tid, list):
                        for x in tid:
                            if isinstance(x, str):
                                known_tiles.add(x)
        except Exception:
            pass

    out_path = OUT_DIR / "items.tsv"
    count = 0
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        # Header:
        # id, name_zh, name_en, subtype, category, weight_g, vol_ml, bash, cut, stab, to_hit,
        # kcal, quench, fun, healthy, comestible_type, covers_mask, encumb, warmth, env_res,
        # storage_ml, a_bash, a_cut, a_stab, coverage, flags_csv, vitamins_csv, use_csv, tile, desc
        f.write("id\tname_zh\tname_en\tsubtype\tcategory\tweight_g\tvol_ml\tbash\tcut\tstab\tto_hit\tkcal\tquench\tfun\thealthy\tcomestible_type\tcovers_mask\tencumb\twarmth\tenv_res\tstorage_ml\ta_bash\ta_cut\ta_stab\tcoverage\tflags\tvitamins\tuse_tags\ttile\tdesc\n")
        for cid in unique_ids:
            obj = resolved[cid]
            name_en = clean_tsv(extract_en(obj.get("name", cid))) or cid
            name_zh = clean_tsv(extract_text(obj.get("name", cid), tr)) or name_en
            desc = clean_tsv(extract_text(obj.get("description", ""), tr))
            if len(desc) > 220:
                desc = desc[:217] + "..."

            subtypes = obj.get("subtypes") or []
            if isinstance(subtypes, list) and subtypes:
                subtype = str(subtypes[0])
            else:
                subtype = str(obj.get("type", "GENERIC"))
            if "ARMOR" in subtypes:
                subtype = "ARMOR"
            elif "COMESTIBLE" in subtypes:
                subtype = "COMESTIBLE"
            elif "GUN" in subtypes:
                subtype = "GUN"
            elif "BOOK" in subtypes:
                subtype = "BOOK"
            elif "TOOL" in subtypes:
                subtype = "TOOL"

            category = clean_tsv(str(obj.get("category", "")))
            weight_g = parse_mass_g(obj.get("weight", 0))
            vol_ml = parse_vol_ml(obj.get("volume", 0))

            md = obj.get("melee_damage") or {}
            if not isinstance(md, dict):
                md = {}
            bash = int(md.get("bash", obj.get("bashing", 0)) or 0)
            cut = int(md.get("cut", obj.get("cutting", 0)) or 0)
            stab = int(md.get("stab", 0) or 0)
            th = obj.get("to_hit", 0)
            if isinstance(th, dict):
                to_hit = 0
                for tv in th.values():
                    if isinstance(tv, (int, float)):
                        to_hit += int(tv)
            elif isinstance(th, (int, float)):
                to_hit = int(th)
            else:
                to_hit = 0

            kcal = int(obj.get("calories", 0) or 0)
            quench = int(obj.get("quench", 0) or 0)
            fun = int(obj.get("fun", 0) or 0)
            healthy = int(obj.get("healthy", 0) or 0)
            ctype = clean_tsv(str(obj.get("comestible_type", "")))

            mask, enc, warmth, env_res, storage_ml, a_bash, a_cut, a_stab, cov = extract_armor_stats(obj)

            flags = [str(fl) for fl in (obj.get("flags") or []) if isinstance(fl, str)]
            vits, use_tags = extract_vitamins_and_use(obj)
            vits_str = ",".join(f"{k}:{v}" for k, v in sorted(vits.items()))
            flags_str = ",".join(flags)
            use_str = ",".join(use_tags)

            # Resolve sprite tile
            tile = ""
            if cid in known_tiles:
                tile = cid
            elif isinstance(obj.get("looks_like"), str) and obj["looks_like"] in known_tiles:
                tile = obj["looks_like"]
            elif isinstance(obj.get("copy-from"), str) and obj["copy-from"] in known_tiles:
                tile = obj["copy-from"]

            f.write(
                f"{cid}\t{name_zh}\t{name_en}\t{subtype}\t{category}\t{weight_g}\t{vol_ml}\t"
                f"{bash}\t{cut}\t{stab}\t{to_hit}\t{kcal}\t{quench}\t{fun}\t{healthy}\t{ctype}\t"
                f"{mask}\t{enc}\t{warmth}\t{env_res}\t{storage_ml}\t{a_bash}\t{a_cut}\t{a_stab}\t{cov}\t"
                f"{flags_str}\t{vits_str}\t{use_str}\t{tile}\t{desc}\n"
            )
            count += 1

    return count


def export_mutations(tr):
    entries = load_json_dir(ROOT / "data" / "json" / "mutations")
    categories = []
    mut_raw = {}
    concrete_muts = []
    for e in entries:
        if not isinstance(e, dict):
            continue
        t = e.get("type", "")
        if t == "mutation_category":
            categories.append({
                "id": e.get("id", ""),
                "name": extract_text(e.get("name", e.get("id", "")), tr),
                "threshold_mut": e.get("threshold_mut", ""),
                "vitamin": e.get("vitamin", ""),
                "mutagen_message": extract_text(e.get("mutagen_message", "你感到体内发生了某种异变。"), tr),
                "threshold_min": int(e.get("threshold_min", 2200) or 2200),
            })
        elif t == "mutation":
            mid = e.get("id") or e.get("abstract")
            if not mid:
                continue
            mut_raw[mid] = e
            if "id" in e and "abstract" not in e:
                concrete_muts.append(mid)

    resolved = merge_copy_from(mut_raw)
    seen = set()
    muts_out = []
    for mid in sorted(concrete_muts):
        if mid in seen:
            continue
        seen.add(mid)
        obj = resolved[mid]
        if obj.get("valid") is False and not obj.get("threshold") and not obj.get("category"):
            continue
        muts_out.append({
            "id": mid,
            "name": extract_text(obj.get("name", mid), tr) or mid,
            "desc": extract_text(obj.get("description", ""), tr)[:200],
            "points": int(obj.get("points", 0) or 0),
            "starting_trait": bool(obj.get("starting_trait", False)),
            "profession": bool(obj.get("profession", False)),
            "valid": bool(obj.get("valid", True)),
            "purifiable": bool(obj.get("purifiable", True)),
            "threshold": bool(obj.get("threshold", False)),
            "threshreq": obj.get("threshreq") or [],
            "category": obj.get("category") or [],
            "prereqs": obj.get("prereqs") or [],
            "prereqs2": obj.get("prereqs2") or [],
            "cancels": obj.get("cancels") or [],
            "changes_to": obj.get("changes_to") or [],
            "flags": obj.get("flags") or [],
            "vitamin_cost": int(obj.get("vitamin_cost", 100) or 100),
        })

    out_path = OUT_DIR / "mutations.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"categories": categories, "mutations": muts_out}, f, ensure_ascii=False)
    return len(categories), len(muts_out)


def export_monsters_and_drops(tr, valid_items):
    # 1. Load all item_groups across data/json/monsterdrops and data/json/itemgroups
    raw_groups = {}
    for gdir in [
        ROOT / "data" / "json" / "monsterdrops",
        ROOT / "data" / "json" / "itemgroups",
    ]:
        if not gdir.exists():
            continue
        for p in sorted(gdir.rglob("*.json")):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    data = json.load(f)
            except Exception:
                continue
            arr = data if isinstance(data, list) else ([data] if isinstance(data, dict) else [])
            for e in arr:
                if not isinstance(e, dict) or e.get("type") != "item_group":
                    continue
                gid = e.get("id")
                if not isinstance(gid, str) or not gid:
                    continue
                if gid not in raw_groups:
                    raw_groups[gid] = copy.deepcopy(e)
                else:
                    # Merge duplicate item_group definitions (vanilla CDDA appends entries/items/groups)
                    for k in ("entries", "items", "groups"):
                        if isinstance(e.get(k), list):
                            raw_groups[gid].setdefault(k, []).extend(copy.deepcopy(e[k]))

    # Resolve copy-from on item_groups if any
    raw_groups = merge_copy_from(raw_groups)

    def parse_range(val, default_pair=None):
        if isinstance(val, (int, float)):
            v = int(val)
            return [v, v]
        if isinstance(val, list) and len(val) >= 2 and isinstance(val[0], (int, float)) and isinstance(val[1], (int, float)):
            return [int(val[0]), int(val[1])]
        return default_pair

    referenced_groups = set()

    def compile_entry(ent):
        """Compile a single vanilla item_group entry into a compact dict."""
        if isinstance(ent, str):
            return {"i": ent} if ent in valid_items else None
        if isinstance(ent, list) and ent:
            iid = ent[0]
            prob = int(ent[1]) if len(ent) >= 2 and isinstance(ent[1], (int, float)) else 100
            if isinstance(iid, str) and iid in valid_items:
                out = {"i": iid}
                if prob != 100:
                    out["p"] = max(1, prob)
                return out
            return None
        if not isinstance(ent, dict):
            return None

        out = {}
        prob = ent.get("prob")
        if isinstance(prob, (int, float)) and int(prob) != 100:
            out["p"] = max(0, int(prob))

        cnt = parse_range(ent.get("count"))
        if cnt and (cnt[0] != 1 or cnt[1] != 1):
            out["n"] = [max(1, cnt[0]), max(1, min(cnt[1], 12))]

        dmg = parse_range(ent.get("damage"))
        if dmg and (dmg[0] > 0 or dmg[1] > 0):
            out["dm"] = [max(0, min(4, dmg[0])), max(0, min(4, dmg[1]))]

        if isinstance(ent.get("item"), str):
            if ent["item"] not in valid_items:
                return None
            out["i"] = ent["item"]
            return out

        if isinstance(ent.get("group"), str):
            gid = ent["group"]
            if gid not in raw_groups:
                return None
            referenced_groups.add(gid)
            out["g"] = gid
            return out

        if isinstance(ent.get("collection"), list):
            subs = [c for c in (compile_entry(x) for x in ent["collection"]) if c]
            if not subs:
                return None
            out["c"] = subs
            return out

        if isinstance(ent.get("distribution"), list):
            subs = [c for c in (compile_entry(x) for x in ent["distribution"]) if c]
            if not subs:
                return None
            out["d"] = subs
            return out

        return None

    def compile_group_obj(obj):
        if isinstance(obj, list):
            # Inline list of entries defaults to distribution unless dict
            subs = [c for c in (compile_entry(x) for x in obj) if c]
            return {"s": "d", "e": subs} if subs else None
        if not isinstance(obj, dict):
            return None
        subtype = str(obj.get("subtype", "old")).lower()
        mode = "c" if subtype == "collection" else "d"
        compiled = []
        for ent in (obj.get("entries") or []):
            c = compile_entry(ent)
            if c:
                compiled.append(c)
        for it in (obj.get("items") or []):
            c = compile_entry(it)
            if c:
                compiled.append(c)
        for grp in (obj.get("groups") or []):
            if isinstance(grp, str) and grp in raw_groups:
                referenced_groups.add(grp)
                compiled.append({"g": grp})
            elif isinstance(grp, list) and grp and isinstance(grp[0], str) and grp[0] in raw_groups:
                referenced_groups.add(grp[0])
                ent = {"g": grp[0]}
                if len(grp) >= 2 and isinstance(grp[1], (int, float)) and int(grp[1]) != 100:
                    ent["p"] = max(1, int(grp[1]))
                compiled.append(ent)
            elif isinstance(grp, dict):
                c = compile_entry(grp)
                if c:
                    compiled.append(c)
        if not compiled:
            return None
        return {"s": mode, "e": compiled}

    # 2. Load & resolve all MONSTER definitions
    entries = load_json_dir(ROOT / "data" / "json" / "monsters")
    raw_map = {}
    concrete = []
    for e in entries:
        if not isinstance(e, dict) or e.get("type") != "MONSTER":
            continue
        mid = e.get("id") or e.get("abstract")
        if not mid or not isinstance(mid, str):
            continue
        raw_map[mid] = e
        if "id" in e and "abstract" not in e:
            concrete.append(mid)

    resolved = merge_copy_from(raw_map)
    compiled_groups = {}
    seen = set()
    out = []
    for mid in sorted(concrete):
        if mid in seen:
            continue
        seen.add(mid)
        obj = resolved[mid]
        armor = obj.get("armor") or {}
        if not isinstance(armor, dict):
            armor = {}
        a_bash = int(armor.get("bash", obj.get("armor_bash", 0)) or 0)
        a_cut = int(armor.get("cut", obj.get("armor_cut", 0)) or 0)
        a_stab = int(armor.get("stab", obj.get("armor_stab", 0)) or 0)
        specials = []
        for sa in (obj.get("special_attacks") or []):
            if isinstance(sa, list) and sa:
                specials.append(str(sa[0]))
            elif isinstance(sa, dict):
                sid = sa.get("id") or sa.get("type") or ""
                if sid:
                    specials.append(str(sid))
            elif isinstance(sa, str):
                specials.append(sa)

        # Resolve death_drops: either string group ID or inline dict/list
        dd_raw = obj.get("death_drops")
        dd_id = ""
        if isinstance(dd_raw, str) and dd_raw in raw_groups:
            dd_id = dd_raw
            referenced_groups.add(dd_id)
        elif isinstance(dd_raw, (dict, list)):
            cg = compile_group_obj(dd_raw)
            if cg:
                dd_id = f"__mon_dd_{mid}"
                compiled_groups[dd_id] = cg

        species = obj.get("species") or []
        flags = obj.get("flags") or []
        filthy_drops = ("ZOMBIE" in species) or ("FILTHY" in flags)
        weight_g = parse_mass_g(obj.get("weight", "81500 g")) or 81500

        out.append({
            "id": mid,
            "name": extract_text(obj.get("name", mid), tr) or mid,
            "desc": extract_text(obj.get("description", ""), tr)[:180],
            "looks_like": obj.get("looks_like", ""),
            "hp": int(obj.get("hp", 60) or 60),
            "speed": int(obj.get("speed", 75) or 75),
            "melee_skill": int(obj.get("melee_skill", 3) or 3),
            "melee_dice": int(obj.get("melee_dice", 2) or 2),
            "melee_dice_sides": int(obj.get("melee_dice_sides", 4) or 4),
            "dodge": int(obj.get("dodge", 0) or 0),
            "armor_bash": a_bash,
            "armor_cut": a_cut,
            "armor_stab": a_stab,
            "vision_day": int(obj.get("vision_day", 30) or 30),
            "vision_night": int(obj.get("vision_night", 5) or 5),
            "aggression": int(obj.get("aggression", 100) or 100),
            "weight_g": weight_g,
            "filthy_drops": filthy_drops,
            "species": species,
            "flags": flags,
            "special_attacks": sorted(set(specials)),
            "harvest": str(obj.get("harvest", "")),
            "death_drops": dd_id,
        })

    # Recursively compile every item_group reachable from monster death_drops!
    pending = set(referenced_groups)
    while pending:
        gid = pending.pop()
        if gid in compiled_groups or gid not in raw_groups:
            continue
        before = set(referenced_groups)
        cg = compile_group_obj(raw_groups[gid])
        if cg:
            compiled_groups[gid] = cg
        newly = referenced_groups - before
        for ng in newly:
            if ng not in compiled_groups:
                pending.add(ng)

    with open(OUT_DIR / "monsters.json", "w", encoding="utf-8") as f:
        json.dump({"monsters": out}, f, ensure_ascii=False)
    with open(OUT_DIR / "monsterdrops.json", "w", encoding="utf-8") as f:
        json.dump({"groups": compiled_groups}, f, ensure_ascii=False)

    # 3. Export vanilla harvest.json tables!
    harv_raw = {}
    harv_concrete = []
    for hp in [ROOT / "data" / "json" / "harvest.json"]:
        if hp.exists():
            with open(hp, "r", encoding="utf-8") as f:
                hdata = json.load(f)
            for e in (hdata if isinstance(hdata, list) else []):
                if not isinstance(e, dict) or e.get("type") != "harvest":
                    continue
                hid = e.get("id") or e.get("abstract")
                if hid:
                    harv_raw[hid] = e
                    if "id" in e and "abstract" not in e:
                        harv_concrete.append(hid)
    harv_res = merge_copy_from(harv_raw)
    harv_out = {}
    for hid in sorted(set(harv_concrete)):
        obj = harv_res[hid]
        ents = []
        for he in (obj.get("entries") or []):
            if not isinstance(he, dict):
                continue
            drop_id = str(he.get("drop", ""))
            if not drop_id or drop_id not in valid_items:
                continue
            row = {"drop": drop_id, "type": str(he.get("type", "flesh"))}
            if isinstance(he.get("mass_ratio"), (int, float)):
                row["mr"] = round(float(he["mass_ratio"]), 5)
            bn = parse_range(he.get("base_num"))
            if bn:
                row["bn"] = bn
            ents.append(row)
        if ents:
            harv_out[hid] = ents
    with open(OUT_DIR / "harvest.json", "w", encoding="utf-8") as f:
        json.dump({"harvest": harv_out}, f, ensure_ascii=False)

    return len(out), len(compiled_groups), len(harv_out)


def parse_time_min(val):
    if isinstance(val, (int, float)):
        return max(1, int(round(val / 6000.0)))
    if not isinstance(val, str):
        return 5
    total = 0.0
    for m in re.finditer(r"([\d.]+)\s*(d|h|m|s)", val.lower()):
        n = float(m.group(1))
        u = m.group(2)
        if u == "d":
            total += n * 1440.0
        elif u == "h":
            total += n * 60.0
        elif u == "m":
            total += n
        elif u == "s":
            total += n / 60.0
    return max(1, int(round(total)))


def load_all_item_groups(valid_items):
    """Build group_id -> list of concrete vanilla item IDs (up to 48 per group)."""
    raw_groups = {}
    for directory in [ROOT / "data" / "json" / "itemgroups", ROOT / "data" / "json"]:
        if directory == ROOT / "data" / "json":
            files = [directory / "professions.json", directory / "hobbies.json"]
        else:
            files = sorted(directory.rglob("*.json"))
        for p in files:
            if not p.exists():
                continue
            try:
                with open(p, "r", encoding="utf-8") as f:
                    data = json.load(f)
            except Exception:
                continue
            arr = data if isinstance(data, list) else ([data] if isinstance(data, dict) else [])
            for e in arr:
                if isinstance(e, dict) and e.get("type") == "item_group" and isinstance(e.get("id"), str):
                    gid = e["id"]
                    if gid not in raw_groups:
                        raw_groups[gid] = e
                    else:
                        # merge entries/items
                        for k in ("entries", "items", "groups"):
                            if isinstance(e.get(k), list):
                                raw_groups[gid].setdefault(k, []).extend(e[k])

    memo = {}

    def resolve_group(gid, depth=0):
        if gid in memo:
            return memo[gid]
        if depth > 4 or gid not in raw_groups:
            return []
        obj = raw_groups[gid]
        res = []
        seen = set()

        def add_item(iid):
            if isinstance(iid, str) and iid in valid_items and iid not in seen:
                seen.add(iid)
                res.append(iid)

        for it in (obj.get("items") or []):
            if isinstance(it, str):
                add_item(it)
            elif isinstance(it, list) and it and isinstance(it[0], str):
                add_item(it[0])
            elif isinstance(it, dict) and isinstance(it.get("item"), str):
                add_item(it["item"])
        for ent in (obj.get("entries") or []):
            if isinstance(ent, dict):
                if isinstance(ent.get("item"), str):
                    add_item(ent["item"])
                if isinstance(ent.get("container-item"), str):
                    add_item(ent["container-item"])
                if isinstance(ent.get("group"), str):
                    for sub in resolve_group(ent["group"], depth + 1):
                        add_item(sub)
                        if len(res) >= 48:
                            break
                for sub_g in (ent.get("collection") or ent.get("distribution") or []):
                    if isinstance(sub_g, dict) and isinstance(sub_g.get("item"), str):
                        add_item(sub_g["item"])
                    elif isinstance(sub_g, dict) and isinstance(sub_g.get("group"), str):
                        for sub in resolve_group(sub_g["group"], depth + 1):
                            add_item(sub)
            if len(res) >= 48:
                break
        for grp in (obj.get("groups") or []):
            gname = grp if isinstance(grp, str) else (grp[0] if isinstance(grp, list) and grp else "")
            if isinstance(gname, str):
                for sub in resolve_group(gname, depth + 1):
                    add_item(sub)
                    if len(res) >= 48:
                        break
        memo[gid] = res[:48]
        return memo[gid]

    resolved = {}
    for gid in raw_groups:
        items = resolve_group(gid)
        if items:
            resolved[gid] = items
    return resolved


def export_skills(tr):
    p = ROOT / "data" / "json" / "skills.json"
    with open(p, "r", encoding="utf-8") as f:
        entries = json.load(f)
    out = []
    for e in entries:
        if not isinstance(e, dict) or e.get("type") != "skill":
            continue
        sid = e.get("id")
        if not sid:
            continue
        out.append({
            "id": sid,
            "name": extract_text(e.get("name", sid), tr) or sid,
            "desc": extract_text(e.get("description", ""), tr)[:220],
            "category": str(e.get("display_category", "display_none")),
            "sort_rank": int(e.get("sort_rank", 10000) or 10000),
        })
    out.sort(key=lambda x: (x["sort_rank"], x["id"]))
    with open(OUT_DIR / "skills.json", "w", encoding="utf-8") as f:
        json.dump({"skills": out}, f, ensure_ascii=False)
    return len(out)


def export_scenarios(tr):
    # Load start_locations to resolve sloc_* -> omt kind
    sloc_map = {}
    sloc_path = ROOT / "data" / "json" / "start_locations.json"
    if sloc_path.exists():
        with open(sloc_path, "r", encoding="utf-8") as f:
            sdata = json.load(f)
        raw_sloc = {}
        for e in sdata:
            if isinstance(e, dict) and e.get("type") == "start_location" and e.get("id"):
                raw_sloc[e["id"]] = e
        res_sloc = merge_copy_from(raw_sloc)
        for sid, obj in res_sloc.items():
            ters = []
            for t in (obj.get("terrain") or []):
                if isinstance(t, str):
                    ters.append(t)
                elif isinstance(t, dict) and isinstance(t.get("om_terrain"), str):
                    ters.append(t["om_terrain"])
            sloc_map[sid] = {
                "name": extract_text(obj.get("name", sid), tr) or sid,
                "terrains": ters,
            }

    def map_slocs_to_omt_kind(slocs):
        for sl in slocs:
            s = sl.lower()
            if "shelter" in s:
                return "shelter"
            if "hospital" in s or "clinic" in s:
                return "hospital"
            if "police" in s or "prison" in s:
                return "police_station"
            if "fire_station" in s:
                return "fire_station"
            if "pharm" in s:
                return "pharmacy"
            if "grocery" in s or "mall" in s:
                return "s_grocery"
            if "hardware" in s or "garage" in s:
                return "s_hardware"
            if "library" in s or "school" in s:
                return "library"
            if "lab" in s or "toxic" in s or "mine" in s:
                return "toxic_dump"
            if "house" in s or "cabin" in s or "apartment" in s or "mansion" in s:
                return "house"
            if "forest" in s or "camp" in s or "field" in s or "wilderness" in s:
                return "forest_camp"
        return "shelter"

    with open(ROOT / "data" / "json" / "scenarios.json", "r", encoding="utf-8") as f:
        entries = json.load(f)
    raw = {}
    order = []
    for e in entries:
        if isinstance(e, dict) and e.get("type") == "scenario":
            oid = e.get("id") or e.get("abstract")
            if oid:
                raw[oid] = e
                if "id" in e and "abstract" not in e:
                    order.append(oid)
    resolved = merge_copy_from(raw)
    seen = set()
    out = []
    for oid in order:
        if oid in seen:
            continue
        seen.add(oid)
        obj = resolved[oid]
        slocs = [str(s) for s in (obj.get("allowed_locs") or []) if isinstance(s, str)]
        profs = [str(p) for p in (obj.get("professions") or []) if isinstance(p, str)]
        ftraits = [str(t) for t in (obj.get("forced_traits") or []) if isinstance(t, str)]
        attraits = [str(t) for t in (obj.get("traits") or []) if isinstance(t, str)]
        flags = [str(fl) for fl in (obj.get("flags") or []) if isinstance(fl, str)]
        out.append({
            "id": oid,
            "name": extract_text(obj.get("name", oid), tr) or oid,
            "desc": extract_text(obj.get("description", ""), tr)[:280],
            "points": int(obj.get("points", 0) or 0),
            "start_name": extract_text(obj.get("start_name", "Evac Shelter"), tr) or "Evac Shelter",
            "allowed_locs": slocs[:8],
            "start_omt": map_slocs_to_omt_kind(slocs),
            "professions": profs[:24],
            "forced_traits": ftraits,
            "traits": attraits,
            "flags": flags,
        })
    with open(OUT_DIR / "scenarios.json", "w", encoding="utf-8") as f:
        json.dump({"scenarios": out}, f, ensure_ascii=False)
    return len(out)


def export_professions(tr, valid_items, item_subtypes, item_groups):
    entries = []
    for fname in ("professions.json", "hobbies.json"):
        p = ROOT / "data" / "json" / fname
        if p.exists():
            with open(p, "r", encoding="utf-8") as f:
                entries.extend(json.load(f))

    raw = {}
    order = []
    for e in entries:
        if isinstance(e, dict) and e.get("type") == "profession":
            oid = e.get("id") or e.get("abstract")
            if oid:
                raw[oid] = e
                if "id" in e and "abstract" not in e:
                    order.append(oid)
    resolved = merge_copy_from(raw)

    def collect_entries(node, acc):
        if isinstance(node, list):
            for x in node:
                collect_entries(x, acc)
        elif isinstance(node, str):
            if node in valid_items:
                acc.append(node)
        elif isinstance(node, dict):
            if isinstance(node.get("item"), str) and node["item"] in valid_items:
                raw_cnt = node.get("count", 1)
                if isinstance(raw_cnt, list) and raw_cnt:
                    cnt = int(raw_cnt[0] or 1)
                elif isinstance(raw_cnt, (int, float)):
                    cnt = int(raw_cnt or 1)
                else:
                    cnt = 1
                for _ in range(max(1, min(cnt, 4))):
                    acc.append(node["item"])
            if isinstance(node.get("container-item"), str) and node["container-item"] in valid_items:
                acc.append(node["container-item"])
            if isinstance(node.get("group"), str):
                gitems = item_groups.get(node["group"], [])
                for gi in gitems[:4]:
                    acc.append(gi)
            for k in ("entries", "both", "male"):
                if k in node:
                    collect_entries(node[k], acc)

    seen = set()
    out = []
    for oid in order:
        if oid in seen:
            continue
        seen.add(oid)
        obj = resolved[oid]
        is_hobby = (obj.get("subtype") == "hobby")
        raw_items = []
        collect_entries(obj.get("items") or {}, raw_items)
        # Split into worn, wielded, bag based on real item subtype
        worn = []
        bag = []
        wielded = ""
        for iid in raw_items:
            st = item_subtypes.get(iid, "GENERIC")
            if st == "ARMOR" and len(worn) < 12 and iid not in worn:
                worn.append(iid)
            elif not wielded and st in ("GUN", "TOOL", "GENERIC") and iid not in worn:
                wielded = iid
            else:
                if len(bag) < 16:
                    bag.append(iid)
        skills = []
        for sk in (obj.get("skills") or []):
            if isinstance(sk, dict) and sk.get("name"):
                skills.append({"name": str(sk["name"]), "level": int(sk.get("level", 1) or 1)})
        traits = [str(t) for t in (obj.get("traits") or []) if isinstance(t, str)]
        flags = [str(fl) for fl in (obj.get("flags") or []) if isinstance(fl, str)]
        nm = obj.get("name", oid)
        if isinstance(nm, dict) and "male" in nm:
            nm_zh = extract_text(nm["male"], tr) or extract_en(nm["male"])
        else:
            nm_zh = extract_text(nm, tr) or oid
        out.append({
            "id": oid,
            "name": nm_zh,
            "desc": extract_text(obj.get("description", ""), tr)[:260],
            "points": int(obj.get("points", 0) or 0),
            "is_hobby": is_hobby,
            "worn": worn,
            "wielded": wielded,
            "bag": bag,
            "skills": skills,
            "traits": traits,
            "flags": flags,
        })
    with open(OUT_DIR / "professions.json", "w", encoding="utf-8") as f:
        json.dump({"professions": out}, f, ensure_ascii=False)
    return len(out)


def export_recipes(tr, valid_items):
    entries = load_json_dir(ROOT / "data" / "json" / "recipes")
    raw = {}
    concrete = []
    for e in entries:
        if not isinstance(e, dict) or e.get("type") != "recipe":
            continue
        oid = e.get("result") or e.get("abstract")
        if not oid or not isinstance(oid, str):
            continue
        suffix = e.get("id_suffix", "")
        key = f"{oid}_{suffix}" if suffix else oid
        raw[key] = e
        if "result" in e and "abstract" not in e:
            concrete.append(key)

    resolved = merge_copy_from(raw)
    seen_res = set()
    out = []
    for key in sorted(concrete):
        obj = resolved[key]
        res = obj.get("result", "")
        if not res or res not in valid_items or res in seen_res:
            continue
        if obj.get("obsolete"):
            continue
        # Simplify components: list of [ [item_id, count], ... ] (keep only valid items)
        comps_out = []
        raw_comps = obj.get("components") or []
        valid_recipe = True
        for alt_group in raw_comps:
            if not isinstance(alt_group, list):
                continue
            alts = []
            for pair in alt_group:
                if isinstance(pair, list) and len(pair) >= 2 and isinstance(pair[0], str) and isinstance(pair[1], (int, float)):
                    if pair[0] in valid_items:
                        alts.append([pair[0], max(1, int(pair[1]))])
            if alts:
                comps_out.append(alts[:4])
            else:
                valid_recipe = False
                break
        if not valid_recipe or not comps_out:
            continue
        seen_res.add(res)
        out.append({
            "id": key,
            "result": res,
            "charges": max(1, int(obj.get("charges", 1) or 1)),
            "category": str(obj.get("category", "CC_OTHER")),
            "subcategory": str(obj.get("subcategory", "")),
            "skill_used": str(obj.get("skill_used", "survival") or "survival"),
            "difficulty": int(obj.get("difficulty", 0) or 0),
            "time_min": parse_time_min(obj.get("time", "5 m")),
            "autolearn": bool(obj.get("autolearn", False)),
            "components": comps_out[:6],
        })
    with open(OUT_DIR / "recipes.json", "w", encoding="utf-8") as f:
        json.dump({"recipes": out}, f, ensure_ascii=False)
    return len(out)


def pick_val(v):
    """Resolve CCB mapgen terrain/furniture value (string, weighted list, param dict)."""
    if isinstance(v, str):
        return v
    if isinstance(v, dict):
        if isinstance(v.get("fallback"), str):
            return v["fallback"]
        if isinstance(v.get("param"), str):
            p = v["param"].lower()
            if "wall" in p:
                return "t_wall_w"
            if "linoleum" in p:
                return "t_linoleum_white"
            if "floor" in p:
                return "t_floor"
            if "door" in p:
                return "t_door_c"
            if "window" in p:
                return "t_window_domestic"
            if "roof" in p:
                return "t_flat_roof"
        if isinstance(v.get("default"), str):
            return v["default"]
        return ""
    if isinstance(v, list) and v:
        first = v[0]
        if isinstance(first, str):
            return first
        if isinstance(first, list) and first:
            return pick_val(first[0])
        if isinstance(first, dict):
            return pick_val(first)
    return ""


def normalize_vanilla_terrain(tid, known_tiles):
    if not tid:
        return "t_grass"
    if tid in known_tiles:
        return tid
    tl = tid.lower()
    if "groundcover" in tl or "region_grass" in tl:
        return "t_grass"
    if "region_soil" in tl or "soil" in tl:
        return "t_dirt"
    if "region_tree" in tl or "tree_fruit" in tl or "tree" in tl:
        return "t_tree"
    if "region_shrub" in tl or "shrub" in tl or "bush" in tl:
        return "t_shrub"
    if "wall_wood" in tl or "wall_w" in tl:
        return "t_wall_w"
    if "brick" in tl and "wall" in tl:
        return "t_brick_wall"
    if "concrete" in tl and "wall" in tl:
        return "t_concrete_wall"
    if "wall" in tl:
        return "t_wall"
    if "window" in tl:
        return "t_window_domestic" if "t_window_domestic" in known_tiles else "t_window"
    if "door_locked" in tl:
        return "t_door_locked_interior" if "t_door_locked_interior" in known_tiles else "t_door_c"
    if "door" in tl:
        return "t_door_c"
    if "linoleum" in tl:
        return "t_linoleum_white" if "t_linoleum_white" in known_tiles else "t_floor"
    if "carpet" in tl:
        return "t_carpet_red" if "t_carpet_red" in known_tiles else "t_floor"
    if "pavement_y" in tl:
        return "t_pavement_y"
    if "pavement" in tl or "asphalt" in tl:
        return "t_pavement"
    if "sidewalk" in tl:
        return "t_sidewalk"
    if "floor" in tl or "thconc" in tl:
        return "t_floor"
    if "water_dp" in tl or "river" in tl:
        return "t_water_dp"
    if "water" in tl:
        return "t_water_sh"
    if "stairs_down" in tl:
        return "t_stairs_down"
    if "stairs_up" in tl:
        return "t_stairs_up"
    if "fence" in tl:
        return "t_chainfence" if "t_chainfence" in known_tiles else "t_fence"
    return "t_grass"


def export_mapgen_omt(known_tiles, item_groups, valid_items):
    """Parse real vanilla CCB mapgen_palettes + mapgen JSON files into resolved 24x24 OMT templates."""
    palettes = {}
    all_mapgens = []

    for d in [ROOT / "data" / "json" / "mapgen_palettes", ROOT / "data" / "json" / "mapgen"]:
        for p in sorted(d.rglob("*.json")):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    data = json.load(f)
            except Exception:
                continue
            arr = data if isinstance(data, list) else ([data] if isinstance(data, dict) else [])
            for e in arr:
                if not isinstance(e, dict):
                    continue
                et = e.get("type")
                if et == "palette" and isinstance(e.get("id"), str):
                    palettes[e["id"]] = e
                elif et == "mapgen":
                    e["_src_file"] = str(p.relative_to(ROOT / "data" / "json" / "mapgen")) if d.name == "mapgen" else ""
                    all_mapgens.append(e)

    pal_memo = {}

    def resolve_palette(pid, depth=0):
        if pid in pal_memo:
            return pal_memo[pid]
        if depth > 6 or pid not in palettes:
            return {"terrain": {}, "furniture": {}, "items": {}, "toilets": set()}
        obj = palettes[pid]
        ter = {}
        furn = {}
        items = {}
        toilets = set()
        for subp in (obj.get("palettes") or []):
            spid = pick_val(subp)
            if spid:
                sub = resolve_palette(spid, depth + 1)
                ter.update(sub["terrain"])
                furn.update(sub["furniture"])
                items.update(sub["items"])
                toilets.update(sub["toilets"])
        for k, v in (obj.get("terrain") or {}).items():
            val = pick_val(v)
            if val:
                ter[k] = val
        for k, v in (obj.get("furniture") or {}).items():
            val = pick_val(v)
            if val:
                furn[k] = val
        for k, v in (obj.get("items") or {}).items():
            grp = ""
            if isinstance(v, dict):
                grp = str(v.get("item", ""))
            elif isinstance(v, list) and v and isinstance(v[0], dict):
                grp = str(v[0].get("item", ""))
            if grp:
                items[k] = grp
        for k in (obj.get("toilets") or {}).keys():
            toilets.add(k)
        res = {"terrain": ter, "furniture": furn, "items": items, "toilets": toilets}
        pal_memo[pid] = res
        return res

    # Mapgen files / om_terrain names -> canonical OMT category kinds we want in our infinite Overmap!
    WANTED_TARGETS = {
        "shelter": ["24x24_shelter", "24x24_shelter_1", "24x24_shelter_2"],
        "s_grocery": ["s_grocery_unlooted", "s_grocery_looted", "s_grocery"],
        "pharmacy": ["s_pharm", "pharmacy", "s_pharm_1"],
        "s_hardware": ["s_hardware", "s_hardware_1", "s_hardware_2"],
        "s_gun": ["s_gun", "s_gun_1", "s_gun_2"],
        "police_station": ["police", "police_station"],
        "fire_station": ["fire_station", "fire_station_1"],
        "library": ["s_library", "library", "urban_library"],
        "garage_gas": ["s_gas", "s_gas_1", "garage_gas"],
        "toxic_dump": ["toxic_dump", "drug_lab"],
        "warehouse": ["warehouse", "abandoned_warehouse"],
        "forest_camp": ["survivor_forest_camp", "campsite", "cabin"],
        "hospital": ["hospital"],
    }

    # Build a flat lookup of valid 24x24 mapgen candidates
    collected = {k: [] for k in list(WANTED_TARGETS.keys()) + ["house"]}

    def classify_mapgen(e):
        om = e.get("om_terrain")
        nid = e.get("nested_mapgen_id", "")
        src = e.get("_src_file", "").replace("\\", "/").lower()
        names = []
        if isinstance(om, str):
            names.append(om)
        elif isinstance(om, list):
            for x in om:
                if isinstance(x, str):
                    names.append(x)
        if isinstance(nid, str) and nid:
            names.append(nid)

        for nm in names:
            nml = nm.lower()
            if "roof" in nml or "under" in nml or "basement" in nml or "_2nd" in nml or "upper" in nml or "_z1" in nml:
                continue
            for kind, keys in WANTED_TARGETS.items():
                for k in keys:
                    if nml == k or nml.startswith(k + "_"):
                        return kind, nm
        if src.startswith("house/") or any(n.lower().startswith("house_") for n in names):
            for nm in names:
                nml = nm.lower()
                if "roof" in nml or "basement" in nml or "2nd" in nml or "upper" in nml or "second" in nml:
                    return None, None
            return "house", (names[0] if names else Path(src).stem)
        if "cabin" in src and "roof" not in src and "basement" not in src:
            return "forest_camp", (names[0] if names else Path(src).stem)
        return None, None

    LIMITS = {
        "shelter": 3, "house": 18, "s_grocery": 3, "pharmacy": 3, "s_hardware": 3,
        "s_gun": 2, "police_station": 2, "fire_station": 2, "library": 2,
        "garage_gas": 2, "toxic_dump": 2, "warehouse": 2, "forest_camp": 3, "hospital": 2,
    }

    for e in all_mapgens:
        obj = e.get("object")
        if not isinstance(obj, dict):
            continue
        rows = obj.get("rows")
        if not isinstance(rows, list) or len(rows) != 24:
            continue
        if any(not isinstance(r, str) or len(r) != 24 for r in rows):
            continue
        kind, tid_name = classify_mapgen(e)
        if not kind or len(collected[kind]) >= LIMITS.get(kind, 2):
            continue

        # Merge palettes + local terrain/furniture/items
        ter_map = {}
        furn_map = {}
        item_map = {}
        toilets = set()
        for pid in (obj.get("palettes") or []):
            spid = pick_val(pid)
            if spid:
                sub = resolve_palette(spid)
                ter_map.update(sub["terrain"])
                furn_map.update(sub["furniture"])
                item_map.update(sub["items"])
                toilets.update(sub["toilets"])
        for k, v in (obj.get("terrain") or {}).items():
            val = pick_val(v)
            if val:
                ter_map[k] = val
        for k, v in (obj.get("furniture") or {}).items():
            val = pick_val(v)
            if val:
                furn_map[k] = val
        for k, v in (obj.get("items") or {}).items():
            grp = ""
            if isinstance(v, dict):
                grp = str(v.get("item", ""))
            elif isinstance(v, list) and v and isinstance(v[0], dict):
                grp = str(v[0].get("item", ""))
            if grp:
                item_map[k] = grp
        for k in (obj.get("toilets") or {}).keys():
            toilets.add(k)

        fill_ter = normalize_vanilla_terrain(pick_val(obj.get("fill_ter", "t_grass")) or "t_grass", known_tiles)
        # Convert 24x24 rows into resolved terrain & furniture grids + compact legends
        ter_legend = []
        ter_idx = {}
        furn_legend = [""]
        furn_idx = {"": 0}
        t_grid = []
        f_grid = []
        spawns = []

        def get_t_id(tstr):
            if tstr not in ter_idx:
                ter_idx[tstr] = len(ter_legend)
                ter_legend.append(tstr)
            return ter_idx[tstr]

        def get_f_id(fstr):
            if fstr not in furn_idx:
                furn_idx[fstr] = len(furn_legend)
                furn_legend.append(fstr)
            return furn_idx[fstr]

        start_xy = [12, 12]
        found_start = False

        for y in range(24):
            row = rows[y]
            for x in range(24):
                ch = row[x]
                raw_t = ter_map.get(ch, "")
                if not raw_t:
                    if ch == " ":
                        raw_t = fill_ter
                    elif ch == ".":
                        raw_t = "t_floor"
                    elif ch == "#":
                        raw_t = "t_wall_w"
                    elif ch == "+":
                        raw_t = "t_door_c"
                    elif ch == "-":
                        raw_t = "t_wall_w"
                    else:
                        raw_t = fill_ter
                nt = normalize_vanilla_terrain(raw_t, known_tiles)
                t_grid.append(get_t_id(nt))

                raw_f = furn_map.get(ch, "")
                if not raw_f and ch in toilets:
                    raw_f = "f_toilet"
                if raw_f and raw_f not in known_tiles:
                    if "table" in raw_f:
                        raw_f = "f_table"
                    elif "chair" in raw_f:
                        raw_f = "f_chair"
                    elif "bed" in raw_f:
                        raw_f = "f_bed"
                    elif "counter" in raw_f:
                        raw_f = "f_counter"
                    elif "rack" in raw_f or "shelf" in raw_f or "bookcase" in raw_f:
                        raw_f = "f_rack"
                    elif "locker" in raw_f or "cupboard" in raw_f or "dresser" in raw_f:
                        raw_f = "f_locker"
                    elif "fridge" in raw_f:
                        raw_f = "f_fridge"
                    elif "oven" in raw_f:
                        raw_f = "f_oven"
                    elif "sink" in raw_f:
                        raw_f = "f_sink"
                    elif "bench" in raw_f:
                        raw_f = "f_bench"
                    elif "sofa" in raw_f or "couch" in raw_f:
                        raw_f = "f_sofa"
                    elif "crate" in raw_f:
                        raw_f = "f_crate_c"
                    elif "trash" in raw_f:
                        raw_f = "f_trashcan"
                    else:
                        raw_f = ""
                f_grid.append(get_f_id(raw_f))

                if not found_start and 5 <= x <= 18 and 5 <= y <= 18 and nt in ("t_floor", "t_linoleum_white", "t_linoleum_gray", "t_carpet_red") and not raw_f:
                    start_xy = [x, y]
                    found_start = True

                # Item group on tile
                if ch in item_map and len(spawns) < 28:
                    grp = item_map[ch]
                    gitems = item_groups.get(grp, [])
                    if not gitems and grp in valid_items:
                        gitems = [grp]
                    if gitems:
                        spawns.append({"x": x, "y": y, "items": gitems[:8]})

        # Also harvest place_items
        for pi in (obj.get("place_items") or []):
            if not isinstance(pi, dict) or len(spawns) >= 36:
                continue
            grp = str(pi.get("item", ""))
            gitems = item_groups.get(grp, [])
            if not gitems and grp in valid_items:
                gitems = [grp]
            if not gitems:
                continue
            px = pi.get("x", 12)
            py = pi.get("y", 12)
            x = int(px[0] if isinstance(px, list) else px)
            y = int(py[0] if isinstance(py, list) else py)
            if 0 <= x < 24 and 0 <= y < 24:
                spawns.append({"x": x, "y": y, "items": gitems[:8]})

        collected[kind].append({
            "id": tid_name,
            "kind": kind,
            "ter_legend": ter_legend,
            "furn_legend": furn_legend,
            "t": t_grid,
            "f": f_grid,
            "start": start_xy,
            "spawns": spawns,
        })

    templates = []
    for k, arr in collected.items():
        templates.extend(arr)
    with open(OUT_DIR / "mapgen_omt.json", "w", encoding="utf-8") as f:
        json.dump({"templates": templates}, f, ensure_ascii=False)
    return {k: len(v) for k, v in collected.items()}


def load_known_tiles():
    known_tiles = set()
    if TILE_CONFIG.exists():
        try:
            with open(TILE_CONFIG, "r", encoding="utf-8") as f:
                tc = json.load(f)
            for sheet in tc.get("tiles-new", []):
                for t in sheet.get("tiles", []):
                    tid = t.get("id")
                    if isinstance(tid, str):
                        known_tiles.add(tid)
                    elif isinstance(tid, list):
                        for x in tid:
                            if isinstance(x, str):
                                known_tiles.add(x)
        except Exception:
            pass
    return known_tiles


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tr = load_translator()
    n_items = export_items(tr)
    # Read back exported item IDs & subtypes for cross-referencing
    valid_items = set()
    item_subtypes = {}
    with open(OUT_DIR / "items.tsv", "r", encoding="utf-8") as f:
        next(f)
        for line in f:
            parts = line.split("\t")
            if len(parts) >= 4:
                valid_items.add(parts[0])
                item_subtypes[parts[0]] = parts[3]

    known_tiles = load_known_tiles()
    item_groups = load_all_item_groups(valid_items)

    n_cats, n_muts = export_mutations(tr)
    n_mons, n_mdrops, n_harv = export_monsters_and_drops(tr, valid_items)
    n_skills = export_skills(tr)
    n_scens = export_scenarios(tr)
    n_profs = export_professions(tr, valid_items, item_subtypes, item_groups)
    n_recipes = export_recipes(tr, valid_items)
    omt_counts = export_mapgen_omt(known_tiles, item_groups, valid_items)
    print(
        f"EXPORT_CCB_VANILLA_OK items={n_items} mutation_categories={n_cats} "
        f"mutations={n_muts} monsters={n_mons} monsterdrop_groups={n_mdrops} harvest={n_harv} "
        f"skills={n_skills} scenarios={n_scens} professions={n_profs} recipes={n_recipes} "
        f"item_groups={len(item_groups)} omt_templates={sum(omt_counts.values())}"
    )
    print("  OMT breakdown:", omt_counts)
    for p in sorted(OUT_DIR.iterdir()):
        print(f"  {p.name}: {p.stat().st_size / 1024:.1f} KB")


if __name__ == "__main__":
    main()
