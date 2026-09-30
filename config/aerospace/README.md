# AeroSpace 配置

## 模板与渲染产物

- `aerospace.toml`（本目录）是**模板/唯一真相源**，由 Home Manager 管理。
- `~/.config/aerospace/aerospace.toml` 是 `render-config.py` 生成的渲染产物，
  只替换 `BEGIN/END AUTO-GENERATED WORKSPACE ASSIGNMENTS` 之间的
  `[workspace-to-monitor-force-assignment]` 块，其余内容逐字来自模板。
  不要手改 live 文件，会在下次 `reconfigure-aerospace`（显示器变化去抖触发，
  定义在 `nix-darwin/gui-apps.nix`）时被覆盖。
- 渲染时会同时写 `aerospace.toml.assignments.json` 侧车文件，记录上次
  AeroSpace/env 权威查询到的映射；只有 CoreGraphics 可用时会沿用它，
  避免显示器重连期间把 workspace 写到错误的数字编号上。

## 当前 live 映射快照（2026-09-30）

显示器拓扑（`aerospace list-monitors`）：

| monitor-id | 名称 | 备注 |
| --- | --- | --- |
| 1 | DELL U2720Q (2) | 外接竖屏 |
| 2 | HP Z27k G3 | main，中央主屏 |
| 3 | Built-in Retina Display | 内置屏 |
| 4 | DELL U2720Q (1) | 外接竖屏 |

workspace 分配（每个值都是 `[首选, 'main']` 自愈数组，显示器消失时退回 main）：

| Workspace | 目标 |
| --- | --- |
| 1–3 | 2（HP Z27k G3） |
| 4–6 | 1（DELL U2720Q (2)） |
| 7–8 | 4（DELL U2720Q (1)） |
| 9–10 | built-in |

该快照只作记录：实际映射由 `render-config.py` 在每次激活/重配时按当时连接的
显示器重新计算（HP Z27k G3 优先主屏，其余外接屏按从左到右顺序，内置屏最后），
不依赖这里记录的数字编号。
