# 第三方来源

## 项目来源

- 沧菱城（Cangling City）：c585860。
- 官方源码：https://github.com/c585860/cangling-city
- 交流 QQ 群：1001568760。

## CCB / Cataclysm

本项目的贴图来源和部分功能设计参考 Cataclysm-Cleanwater-Bomb（CCB）及其上游 Cataclysm: Dark Days Ahead。

- CCB：https://github.com/CrimsonCrossBunker/Cataclysm-Cleanwater-Bomb
- CDDA：https://github.com/CleverRaven/Cataclysm-DDA
- 原项目中适用的 CC BY-SA 3.0 许可：https://creativecommons.org/licenses/by-sa/3.0/

来自上述项目的内容仍属于原作者，保留原许可及署名，不因收入本仓库而改变。

## 美术素材

- `art/undead_people/` 来自 CCB 的 `gfx/MSX++UndeadPeopleEdition/`，保留原始 `tileset.txt`。该文件列出 MSXotto+、UltiCa 和 Dungeon Crawl: Stone Soup 等素材来源，其中标明的 DCSS 素材使用 CC0。
- `art/ultica.png` 及 `art/streets.png` 中的部分图块来自 UltiCa 贡献者，另有来自上述 Undead People 图集的室内图块。历史图集经过裁切、组合及重排，提取方式见 `art/extract_streets.py`。
- 原素材源目录及贡献记录：https://github.com/I-am-Erk/CDDA-Tilesets/tree/master/gfx
- DCSS 素材来源：https://github.com/crawl/tiles
- 完整的本项目素材说明见 [art/CREDITS.md](art/CREDITS.md)。

## 开发依赖

Godot 引擎是外部依赖。随仓库附带的 `third_party/godot-cpp/` 来自提交 `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77`，保留原始 MIT 许可 `LICENSE.md`。其作者、许可及源码见各自项目：

- https://github.com/godotengine/godot
- https://github.com/godotengine/godot-cpp
