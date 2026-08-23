# 测试框架安装 (GUT for Godot 4)

单元测试使用 [GUT 9.x](https://github.com/bitwes/Gut)。冒烟测试 `tests/test_smoke.gd` 不依赖 GUT，见 README。

## 安装步骤

1. 打开 PowerShell，进入**仓库根目录**（含 `config/` 与 `godot/` 的那一层）：
   ```powershell
   cd <仓库根目录>
   ```

2. 把 GUT 仓库克隆为 addons 子目录：
   ```powershell
   git clone --depth 1 --branch v9.4.0 https://github.com/bitwes/Gut.git godot/addons/gut
   ```
   > GUT 不进本仓库 git；`.gitignore` 已排除 `godot/.godot/` 等缓存，clone 后本地保留即可。

3. 用 Godot 4.7.x 打开 `<仓库根目录>/godot/project.godot`。

4. 在菜单 **Project → Project Settings → Plugins** 里勾选 **Gut** 启用。

5. 跑测试（在 `godot/` 目录下执行，或将 `--path` 指向 `godot/`）：
   ```powershell
   & "C:\path\to\Godot_v4.7.2-stable_win64_console.exe" `
     --path "<仓库根目录>\godot" `
     --headless -s addons/gut/gut_cmdln.gd -gdir=res://../tests -gexit
   ```

## 测试文件位置

- `tests/test_<name>.gd` — 单测
- 每个 GUT 测试必须 `extends GutTest`
- 文件以 `test_` 开头才能被 GUT 自动识别

## 冒烟测试（无需 GUT）

```powershell
& "C:\path\to\Godot_v4.7.2-stable_win64_console.exe" `
  --path "<仓库根目录>\godot" `
  --headless -s res://../tests/test_smoke.gd
```
