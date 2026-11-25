# UNDEAD_PEOPLE(CCB)

`undead_people/` contains the unmodified tileset from CCB's `gfx/MSX++UndeadPeopleEdition` directory. See its original `tileset.txt` for source and attribution information. The neighboring `.png.import` entries are Godot metadata, not part of the original pack.

The city renderer resolves original IDs from `tile_config.json`. To add a new visual, pass the original ID to `UndeadTiles.draw` (preload `scripts/undead_tiles.gd`); no image crop is required. Godot export presets must include the raw tileset JSON, for example via the non-resource include filter `art/undead_people/*.json`.

## Legacy UltiCa artwork (not used by the city renderer)

ultica.png and the outdoor tiles in streets.png use artwork by the UltimateCataclysm (UltiCa) contributors, taken from the local Cataclysm-Cleanwater-Bomb checkout under gfx/UltimateCataclysm. Individual contributor credits are in the [source tile folders](https://github.com/I-am-Erk/CDDA-Tilesets/tree/master/gfx/UltimateCataclysm). The sprites were cropped and arranged into a small atlas; character sprites combine existing clothing layers.

The UltiCa artwork retains its [CC BY-SA 3.0 license](https://creativecommons.org/licenses/by-sa/3.0/), as noted in CCB's gfx/LICENSE.txt. The indoor floor, walls and furniture in streets.png also include artwork extracted from the local gfx/MSX++UndeadPeopleEdition tileset. The extraction script records the source tile IDs; this project does not relicense the original artwork.
