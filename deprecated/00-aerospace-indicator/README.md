# 00 — AeroSpace + workspace indicator + JankyBorders（已停用归档）

2026-10-18 起，macOS 窗口管理切换到 OmniWM（见 `nix-darwin/window-manager.nix`
与 `docs/omniwm-trial.md`）。原 AeroSpace 组合不再被 nix-darwin 安装、启动或
渲染，整套文件原样归档在本目录，**不参与任何求值/激活/测试**。保留它们是为了
回滚和查阅自愈式 workspace→monitor 分配的实现思路。

## 目录内容

| 路径 | 原位置 | 说明 |
| --- | --- | --- |
| `aerospace/aerospace.toml` | `config/aerospace/` | AeroSpace 配置模板（唯一真相源） |
| `aerospace/render-config.py` | `config/aerospace/` | 按当前连接显示器渲染 workspace→monitor 分配，写 live toml + assignments.json 侧车 |
| `aerospace/rehome-workspaces.py` | `config/aerospace/` | 显示器重连后把 workspace 显式重新归位（绕过上游 issue #520） |
| `aerospace/start_workspace_indicator.sh` | `config/aerospace/` | 编译/启动 workspace 指示器（NSPanel accessory app） |
| `aerospace/workspace_indicator.swift` | `config/aerospace/` | 指示器 Swift 源码：per-display 面板、HUD、显示器变化去抖 |
| `aerospace/README.md` | `config/aerospace/` | 模板/渲染产物约定与最后一次 live 映射快照（2026-09-30） |
| `aerospace-patched.rb` | `config/homebrew/Casks/` | 本地 tap cask：`PannenetsF/AeroSpace` pinned `v0.21.3-Beta-pf.1`（App/CLI 同版本 universal） |
| `legacy-gui-apps.nix` | `nix-darwin/gui-apps.nix` 的归档快照 | 停用前的 nix 胶水：render/reconfigure/start 脚本、三个 launchd agent、激活体 |

## 独立使用（不恢复 nix 管理）

这些文件归档时保持可独立运行，不依赖 nix store：

```sh
# 渲染配置（参数：模板路径、输出路径）
python3 aerospace/render-config.py aerospace/aerospace.toml ~/.config/aerospace/aerospace.toml
# 显示器变化后重配 + workspace 归位
python3 aerospace/rehome-workspaces.py \
  ~/.config/aerospace/aerospace.toml.assignments.json /opt/homebrew/bin/aerospace
# 编译指示器
swiftc aerospace/workspace_indicator.swift -o /tmp/aerospace-workspace-indicator
```

`legacy-gui-apps.nix` 是**冻结快照**，内部 `${../config/aerospace/...}` 路径
指向旧布局，不能从本目录直接 import；恢复管理时把它作为参照写回
`nix-darwin/gui-apps.nix`。

## 如何恢复整套组合

以下路径相对仓库根目录：

1. `mkdir -p config/aerospace && git mv deprecated/00-aerospace-indicator/aerospace/* config/aerospace/`
   （README、模板、三个脚本/源码一并移回）。
2. `git mv deprecated/00-aerospace-indicator/aerospace-patched.rb config/homebrew/Casks/aerospace-patched.rb`。
3. 参照 `legacy-gui-apps.nix` 还原 `nix-darwin/gui-apps.nix` 的 AeroSpace /
   indicator / borders 段；在 `nix-darwin/homebrew.nix` 还原
   `dot-nix/local/aerospace-patched` cask、本地 tap staging、
   `felixkratz/formulae` tap 与 `borders` formula 及迁移逻辑。
4. 停用/退出 OmniWM（菜单 Quit，勿与 AeroSpace 同时运行），自行
   `bash ./init.sh` 激活。

## 停用后本机的清理策略（2026-10 起严格声明式）

- Homebrew cask `aerospace-patched`（连同任何不在 nix Brewfile 里的
  formula/cask）由 `init.sh` 在每次 darwin switch 后跑
  `brew bundle cleanup --force` 卸载并清缓存；旧 cask 文件也在 preActivation
  从本地 tap staging 显式删除。回滚需按上文重新声明 cask 或从本目录的
  `aerospace-patched.rb` 重新放进 `config/homebrew/Casks/`。
- `config/omniwm/stop-aerospace.sh` 负责 bootout launchd agent、**删除
  RunAtLoad plist**（否则登录复活）并对残留进程发 SIGTERM。
- `~/.config/aerospace/` 等用户配置不由 brew/nix 管理；需要时自行保留或删除。
