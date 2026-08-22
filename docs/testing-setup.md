# 测试框架安装 (GUT for Godot 4)

P1 阶段视觉验收已足够，单元测试从 **P2 寻路/A\*** 开始就必须。统一用 [GUT 9.x](https://github.com/bitwes/Gut)。

## 安装步骤

1. 打开 PowerShell，进入项目根：
   ```powershell
   cd D:\Projects\pixel_world
   ```

2. 把 GUT 仓库克隆为 addons 子目录（GUT 主线已支持 Godot 4）：
   ```powershell
   git clone --depth 1 --branch v9.4.0 https://github.com/bitwes/Gut.git godot/addons/gut
   ```
   > **不要**把这个目录 commit 到本仓库（`addons/` 已在仓库，但实际 clone 后请确保 `.gitignore` 仍然有效）。
   > 实际策略:由开发者本地 clone 一次，之后不再变动。

3. 启动 Godot，打开 `D:\Projects\pixel_world\godot\project.godot`。

4. 在菜单 **Project → Project Settings → Plugins** 里勾选 **Gut** 启用。

5. 跑测试（F6 或菜单 Gut → Run All）：
   ```powershell
   & godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
   ```

## 测试文件位置

- `tests/test_<name>.gd` — 单测
- 每个测试必须 `extends GutTest`
- 文件以 `test_` 开头才能被 GUT 自动识别

## 状态

- ⏳ P1 不强制
- ⏳ P2 (寻路/A*) 起必装
