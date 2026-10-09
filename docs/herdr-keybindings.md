# herdr 快捷键速查表

配置源：`config/herdr/config.toml`（经 nix-darwin postActivation 装为可写文件
`~/.config/herdr/config.toml`，可 `herdr server reload-config` 热加载）。

记号：**`P` = prefix = `ctrl+b`**，先按 prefix、松开、再按第二键；
**`C-A-x` = `ctrl+alt+x` 同时按下**（直连和弦，无需 prefix；注意 `C-A` 是
ctrl+alt，不是 tmux 的 ctrl+a）。

设计原则：高频操作给 ctrl+alt 直连和弦，低频操作只走 prefix。裸 alt 全局被
AeroSpace 占用（`alt+hjkl`、`alt+数字`），裸 ctrl 被 shell/nvim 占用，ctrl+alt
是各终端均不占用的安全层，且 kitty 未开 `macos_option_as_alt` 也能传输。

## 肌肉记忆层（最常用）

| 操作 | 直连 | prefix 版 | nvim 对应 |
| --- | --- | --- | --- |
| 切换 pane | `C-A-h/j/k/l` | `P h/j/k/l` | `<C-h/j/k/l>` |
| 下一个 / 上一个 tab | `C-A-]` / `C-A-[` | `P n` / `P b`（`P p` 同） | `<leader>bn` / `<leader>bb`、`]q`/`[q` |
| 模糊跳转任意 agent/tab/workspace | `C-A-f` | `P f` / `P g` | `<leader>ff`、`<leader>bj` |
| 竖分 / 横分 pane | `C-A-v` / `C-A-s` | `P v` / `P s` | `:vsplit` / `:split` |
| 新建 tab | `C-A-c` | `P c` | — |
| 关闭 pane / tab | `C-A-x` / `C-A-S-x` | `P x` / `P S-x` | `<leader>c`（语义近） |
| 当前 pane 放大/还原 | `C-A-z` | `P z` | — |
| 开关 sidebar | `C-A-e` | `P e` | `<leader>e` Neotree |

单 pane tab 里 zoom 没有视觉效果，先分屏再试。关 pane 会杀掉其中进程
（`ui.confirm_close` 有确认）。

## 布局调整

| 操作 | 直连 | prefix 版 |
| --- | --- | --- |
| 交换 pane 位置 | `C-A-S-h/j/k/l` | `P S-h/j/k/l` |
| 调整 pane 大小 | `C-A-←/↓/↑/→` | 或 `P r` 进 resize 模式后用 hjkl |
| pane 正反向轮换 | — | `P Tab` / `P S-Tab` |
| 重命名 tab / pane | — | `P S-t` / `P S-p` |

## 多项目 / workspace

| 操作 | 按键 |
| --- | --- |
| workspace 选择器 | `P w` |
| 新建 / 关闭 / 重命名 workspace | `P S-n` / `P S-d` / `P S-w` |
| 跳第 N 个 tab | `P 1..9` |
| 跳第 N 个 workspace | `P S-1..9`（对应 AeroSpace `alt-S-数字`） |
| 跳第 N 个 agent | `P C-1..9` |

## 按需才用

| 操作 | 按键 | 对应习惯 |
| --- | --- | --- |
| LazyGit 弹窗 | `P C-g` | nvim `<leader>g` |
| which-key 分组菜单（可选插件，见下） | `P Space` | which-key.nvim |
| zoetrope 会话流程图（可选插件，见下） | `P S-z` | — |
| Copy/滚动模式（vim 键位、`/` 搜索、`v` 选择、`y` 复制） | `P [` | — |
| 编辑滚动历史到 `$EDITOR` | `P S-e` | 原默认 `e`，给 sidebar 让位 |
| 设置界面 | `P S-s` | 原默认 `s`，给横分让位 |
| detach（全部后台继续跑） | `P q` | tmux 同键 |
| 跳到最新通知指向的 pane | `P o` | — |
| 重载配置 | `P S-r` | — |
| 完整按键面板（可 `/` 过滤） | `P ?` | — |

goto 面板（`P f`）里的过滤单键：`b/w/i/d` 分别过滤
blocked/working/idle/done 的 agent，`a` 恢复全部。

## 可选：which-key 风格分组菜单

herdr 自身的 prefix 底栏（`PREFIX  esc cancel …`）不可配置，插件也无法扩展。
社区插件 `cowboyvang.which-key` 提供 `P Space` 呼出的分组浮层，读取实际
config.toml 生成，可直接按第二键执行。插件不经过 nix 管理，手动安装：

```sh
herdr plugin install CowboyVang/herdr-which-key --yes
# 若 launch.sh 指向已被清理的 .tmp-install-* 目录，重建启动器：
herdr plugin action invoke which-key-install-launcher --plugin cowboyvang.which-key
herdr server reload-config
```

未安装时配置里的 `P Space` 是空弹窗兜底，不影响其他绑定。

## 可选：zoetrope 会话流程图

`furkankly.zoetrope` 插件把聚焦的 agent pane 会话画成实时流程图。插件由
`nix-darwin/herdr.nix` postActivation 安装（pinned ref），`zoe` CLI 由
`nix-darwin/homebrew.nix` 管理。前提：`herdr integration install claude`
（或 codex）已装，且 agent 是在集成安装之后启动的，否则 pane 没有 session id。

- `P S-z`：在当前 pane 上叠加流程图，跟 live 会话；再按一次或图内 `q` 关闭
- 其他放置方式：`furkankly.zoetrope.open-split` / `open-tab`（改 config.toml
  里对应 command 后 `herdr server reload-config`）
