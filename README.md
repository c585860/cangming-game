# 沧溟修真界

独立的修真题材回合制城市探索游戏，使用 Godot 4.5 与 C++ GDExtension 开发。
基于

**项目作者／来源：c585860**  
**交流 QQ 群：1001568760**  
**官方源码：https://github.com/c585860/cangling-city**

转载、分享或展示本项目时，请保留项目来源。

## 当前内容

灵感来源于cataclysm:cleanwater Bomb

## 构建与运行

需要 Godot 4.5.x、对应的 godot-cpp 4.5、CMake 3.22+、Ninja，以及支持 C++17 的编译器。godot-cpp 需要另外获取，不包含在此仓库中。

在 PowerShell 中执行，替换 godot-cpp 的路径：

```powershell
git clone --branch godot-4.5-stable --depth 1 https://github.com/godotengine/godot-cpp.git ../godot-cpp
cmake -S . -B build/native -G Ninja -DGODOT_CPP_DIR="../godot-cpp"
cmake --build build/native --parallel 8
```

Windows 扩展输出至 `bin/cangling.dll`。完成构建后，用 Godot 打开 `project.godot` 并运行主场景，或指定引擎路径后使用启动脚本：

```powershell
$env:GODOT_EXE = "C:\Tools\Godot\Godot_v4.5.1-stable_win64.exe"
.\play.cmd
```


## 目录

- `native/`：C++ 世界状态、城市生成、寻路、物品和交互。
- `scripts/`：界面、地图绘制、时间与光影。
- `data/`：城市和建筑配置。
- `art/`：贴图和图集。

## 署名与许可

沧菱城项目作者／来源为 **c585860**，QQ 群 **1001568760**。第三方署名与许可见 [THIRD_PARTY.md](THIRD_PARTY.md)。
未经允许禁止转载。
