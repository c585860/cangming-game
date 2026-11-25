"""Extract the project's additional UltiCa tiles from a local CCB checkout (Pillow)."""
import json
import sys
from pathlib import Path
from PIL import Image

def load_tileset(source):
    config = json.loads((source / "tile_config.json").read_text(encoding="utf-8-sig"))
    entries, sheets = {}, []
    offset = 0
    for group in config["tiles-new"]:
        image = Image.open(source / group["file"])
        w, h = group.get("sprite_width", 32), group.get("sprite_height", 32)
        end = offset + image.width // w * (image.height // h)
        sheets.append((offset, end, w, h, image))
        offset = end
        for tile in group["tiles"]:
            for key in tile["id"] if isinstance(tile["id"], list) else [tile["id"]]:
                entries[key] = tile
    return entries, sheets


root = Path(sys.argv[1]) / "gfx"
entries, sheets = load_tileset(root / "UltimateCataclysm")

sprites, manifest = [], {}


def crop(index):
    start, _, w, h, sheet = next(s for s in sheets if s[0] <= index < s[1])
    row, col = divmod(index - start, sheet.width // w)
    return sheet.crop((col * w, row * h, (col + 1) * w, (row + 1) * h)).convert("RGBA")


def add(key, index, bg=None, weight=1):
    image = crop(index)
    if image.width > 32:
        image = image.resize((32, int(image.height * 32 / image.width)), Image.Resampling.NEAREST)
    if bg is not None:
        background = crop(bg)
        background.alpha_composite(image)
        image = background
    if image.width < 32:
        padded = Image.new("RGBA", (32, 32))
        padded.paste(image, ((32 - image.width) // 2, (32 - image.height) // 2))
        image = padded
    manifest.setdefault(key, []).append([len(sprites), image.height, weight])
    sprites.append(image)


def variants(key, tile_id, branch=None):
    tile = entries[tile_id]
    if branch:
        tile = next(t for t in tile["additional_tiles"] if t["id"] == branch)
    for item in tile["fg"]:
        add(key, item["sprite"] if isinstance(item, dict) else item,
            weight=item.get("weight", 1) if isinstance(item, dict) else 1)


def joins(key, tile_id):
    # Mask bits are S, E, W, N, as in CCB's map::get_tile_values.
    sequence = [("unconnected", 0), ("end_piece", 0), ("end_piece", 3), ("corner", 0),
                ("end_piece", 1), ("corner", 1), ("edge", 1), ("t_connection", 0),
                ("end_piece", 2), ("edge", 0), ("corner", 3), ("t_connection", 3),
                ("corner", 2), ("t_connection", 1), ("t_connection", 2), ("center", 0)]
    by_name = {t["id"]: t["fg"] for t in entries[tile_id]["additional_tiles"]}
    for name, orientation in sequence:
        indices = by_name[name]
        add(key, indices[orientation % len(indices)])


variants("grass", "t_grass")
variants("grass_rich", "t_grass_season_summer")
variants("road", "t_thconc_floor")
for key, tile_id in [("stone_wall", "t_rock_wall"), ("pavers", "t_sidewalk"),
                     ("runner", "t_carpet_red"), ("fence", "t_fence_season_spring"), ("bench", "f_bench")]:
    joins(key, tile_id)

for key, index in {"kitchen": 6890, "gate": 6290, "gate_open": 6291, "rack": 2988, "plant": 2868,
                   "tree": 13293, "shrub": 8239, "lamp": 9139, "sheet": 883, "apple": 1209,
                   "flatbread": 1243, "pear": 1274, "clay_bottle": 851, "herb_bundle": 1265}.items():
    add(key, index)

entries, sheets = load_tileset(root / "MSX++UndeadPeopleEdition")
variants("wood", "t_floor", "center")
variants("chair", "f_chair")
variants("armchair", "f_armchair")
for key, tile_id in [("wood_wall", "t_wall_log"), ("log_wall", "t_wall_wood"), ("bed", "f_bed"),
                     ("counter", "f_counter"), ("table", "f_table"), ("sofa", "f_sofa"), ("cupboard", "f_cupboard")]:
    joins(key, tile_id)
for key, tile_id in [("door", "t_door_c"), ("door_open", "t_door_o"), ("window", "t_window_domestic"),
                     ("display", "f_displaycase"), ("wardrobe", "f_wardrobe")]:
    variants(key, tile_id)

atlas = Image.new("RGBA", (512, ((len(sprites) + 15) // 16) * 64))
for i, tile in enumerate(sprites):
    atlas.paste(tile, (i % 16 * 32, i // 16 * 64))
atlas.save(Path(__file__).with_name("streets.png"), optimize=True)
Path(__file__).with_name("streets.json").write_text(json.dumps(manifest, separators=(",", ":")), encoding="utf-8")
