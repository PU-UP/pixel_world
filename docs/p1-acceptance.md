# P1 验收清单

> P1 = "渲染 + 单 agent 移动 + 相机跟随"
> 估时 2 天。本节列出 P1 完成的客观标准。

## 必备验收项

### 视觉
- [ ] 打开 `godot/project.godot` → F5 启动,主场景 `Main.tscn` 加载成功
- [ ] 视口大小 480x320,拉伸后窗口 960x640,比例不糊
- [ ] 世界能看到 64x64 瓦片(1024x1024 像素)的程序化生成荒岛
  - 中央: 绿色草地
  - 边缘: 蓝色海水
  - 海岸: 黄色沙滩
  - 中心: 灰色山
  - 散布: 深绿树
- [ ] 玩家是 16x16 红色 sprite,带肤色"脸"和黑色描边

### 交互
- [ ] WASD 或 方向键 移动玩家,速度约 5 瓦片/秒
- [ ] 玩家**不能**走到水/山/树(阻挡)
- [ ] 玩家**不能**走出世界边界(64x64 瓦片范围)
- [ ] 相机平滑跟随玩家(不能瞬移,要"smoothing")
- [ ] 调试 HUD 左上角显示 FPS / tick / 玩家坐标 / 瓦片坐标
- [ ] ` ` (反引号) 切换调试 HUD 显隐
- [ ] ESC 退出

### 工程
- [ ] `godot/` 目录结构与 AGENTS.md §3 完全一致
- [ ] GDScript 编译无错(控制台无 Parse Error)
- [ ] 第一帧绘制正常,无"missing texture"红色方块
- [ ] `data/` 目录已就绪(运行时数据落到这里)
- [ ] `.gitignore` 屏蔽了 `.godot/`、`.import/`、`*.db`、`data/`

## 验证方法

```powershell
cd D:\Projects\pixel_world
godot --path godot --headless --check-only   # 静态脚本检查
godot --path godot                           # GUI 启动
```

## 完成后

- [ ] 把"P1"在 AGENTS.md §6 阶段表里打勾
- [ ] 截 1-2 张 F5 截图,放到 `docs/screenshots/p1.png`(可手动建目录)
- [ ] commit:`feat(p1): procedural island, player movement, camera follow`
- [ ] 进入 P2: 寻路 + 行动原语骨架
