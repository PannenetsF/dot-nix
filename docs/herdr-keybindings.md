# herdr 快捷键速查表

配置源：`config/herdr/config.toml`（由仓库根目录的共享激活脚本
`install-herdr-plugins.sh` 装为可写文件 `~/.config/herdr/config.toml`；
macOS 经 `nix-darwin/herdr.nix` postActivation、Linux host 经
`modules/herdr.nix` 的 home.activation 两个薄封装调用，可
`herdr server reload-config` 热加载）。

记号：**`P` = prefix = `ctrl+b`**，先按 prefix、松开、再按第二键；
**`C-A-x` = `ctrl+alt+x` 同时按下**（直连和弦，无需 prefix；注意 `C-A` 是
ctrl+alt，不是 tmux 的 ctrl+a）。

设计原则：高频操作给 ctrl+alt 直连和弦，低频操作只走 prefix。裸 alt 全局被
AeroSpace 占用（`alt+hjkl`、`alt+数字`），裸 ctrl 被 shell/nvim 占用，ctrl+alt
是各终端均不占用的安全层，且 kitty 未开 `macos_option_as_alt` 也能传输。

> 进入 prefix 模式时 herdr 会自动切到 ASCII 输入法、退出时恢复
> （`[experimental] switch_ascii_input_source_in_prefix = true`，仅 macOS；
> 该 herdr 默认关闭，必须写在模板里，只在设置界面里开会被下次激活覆盖）。

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

注意 `P b` 已被 previous_tab 占用：它同时是 herdr 默认的 sidebar 折叠键
（model.rs 文档字符串 Default: "prefix+b"），用户绑定静默胜出，默认的
折叠功能因此失效，需要折叠请把该动作改到别的键。

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
| 跳第 N 个 workspace | `P S-1..9`（对应 AeroSpace `alt-S-数字`；AeroSpace 另定义了 workspace 10（`alt-0`），但 herdr 刻意只绑 1..9，workspace 10 没有 herdr 快捷键） |
| 跳第 N 个 agent | `P C-1..9` |

## 按需才用

| 操作 | 按键 | 对应习惯 |
| --- | --- | --- |
| LazyGit 弹窗 | `P C-g` | nvim `<leader>g` |
| which-key 分组菜单（可选插件，见下） | `P Space` | which-key.nvim |
| zoetrope 会话流程图（可选插件，见下） | `P S-z` | — |
| herdr-radar 切换 agent 排序（可选插件，见下） | `P C-r` | — |
| herdr-radar 设置弹窗（可选插件，见下） | `P ,` | — |
| herdr-projects 工作看板（可选插件，见下） | `P a` | board 总控弹窗 |
| herdr-projects 注册本地仓库并打开 coordinator | `P S-c` | fzf 多选 git 仓库；C = create |
| herdr-projects 选仓库打开 coordinator | `P C-p` | 在跑就聚焦、挂了重启、第一次新建 |
| herdr-projects 另开一个新 coordinator | `P C-n` | n = new；同一仓库的全新对话 |
| herdr-projects 聚焦 coordinator | `P C-f` | f = focus；只跳转，绝不自启 |
| herdr-projects 追加注册本地仓库 | `P S-a` | fzf 多选，已注册的自动隐藏 |
| roadboard 路线图看板（可选插件，见下） | `P S-r` | 7 态任务树；再按一次关闭 |
| herdr-portal 全局 agent 看板 TUI（可选插件，见下） | `P S-o` | ↑↓ 选 agent、Enter 跳 pane；只读导航 |
| herdr-portal 全局 agent 看板 web 大屏 | `P C-o` | 浏览器 127.0.0.1:8787；可回消息 |
| Copy/滚动模式（vim 键位、`/` 搜索、`v` 选择、`y` 复制） | `P [` | — |
| 编辑滚动历史到 `$EDITOR` | `P S-e` | 原默认 `e`，给 sidebar 让位 |
| 设置界面 | `P S-s` | 原默认 `s`，给横分让位 |
| detach（全部后台继续跑） | `P q` | tmux 同键 |
| 跳到最新通知指向的 pane | `P o` | — |
| 重载配置 | `herdr server reload-config` | 默认 `P S-r` 已让给 roadboard，用命令行 |
| 完整按键面板（可 `/` 过滤） | `P ?` | — |

goto 面板（`P f`）里的过滤单键：`b/w/i/d` 分别过滤
blocked/working/idle/done 的 agent，`a` 恢复全部。

> herdr-projects 仓库选择器（1.2.x board 模型）：仓库注册信息保存在插件的
> `data/repos.json`。`P S-c`（`config/herdr/new-project.sh`）用 fzf 多选本地
> git 仓库（Tab 勾选，扫描根 `HP_PROJECT_ROOTS`，默认冒号分隔的
> `~/Documents:~/.config`，深度 4 层，含 worktree），注册选中的第一个仓库并
> 打开它的 project coordinator；`P S-a`
> （`config/herdr/add-repo.sh`）只把多选到的本地仓库注册进注册表（已注册的
> 自动隐藏），不开任何东西；`P C-p`
> （`config/herdr/pick-project.sh`）在已注册仓库里 fzf 选一个，pane 还活着
> 就直接聚焦、pane 没了但对话还在就重启、第一次用则新建。注册走公开 CLI
> （建一个不 delegate 的占位 task 立刻 clear，不启动 agent、不需要 herdr
> 在跑），不手写插件内部 JSON。弹窗出错都会停住显示错误。
> 弹窗继承 herdr server 的环境变量：`HP_PROJECT_ROOTS` 用冒号分隔多个
> 根，且不展开 `~`，需写绝对路径（在 shell 里用 `$HOME` 赋值会由 shell
> 先展开，直接写 `~` 则不会）。

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

`furkankly.zoetrope` 插件把聚焦的 agent pane 会话画成实时流程图。插件由共享
激活脚本 `install-herdr-plugins.sh` 以 pinned ref 安装（macOS 经
`nix-darwin/herdr.nix` postActivation、Linux host 经 `modules/herdr.nix`
两个薄封装调用），`zoe` CLI 在 macOS 由 `nix-darwin/homebrew.nix` 管理。前提：`herdr integration install claude`
（或 codex）已装，且 agent 是在集成安装之后启动的，否则 pane 没有 session id。

- `P S-z`：在当前 pane 上叠加流程图，跟 live 会话；再按一次或图内 `q` 关闭
- 其他放置方式：`furkankly.zoetrope.open-split` / `open-tab`（改 config.toml
  里对应 command 后 `herdr server reload-config`）

## 可选：herdr-radar agent 状态侧边栏

`hhdebb.herdr-radar` 把 herdr 自带的 Agents 列表改造成可读的状态视图：工作中
braille spinner、完成绿勾保留到你看过为止、提问红色脉动、空闲按时间分三级
变淡；按项目/仓库分组（worktree 挂在仓库下）、按活跃度排序。插件由共享激活
脚本 `install-herdr-plugins.sh` 安装（pinned fork `v1.4.9-pf.1`，
PannenetsF/herdr-radar，基于上游 v1.4.9，fork 仅剩静态 ws_key 一个竞态修复；macOS 经 `nix-darwin/herdr.nix` postActivation、
Linux host 经 `modules/herdr.nix` 两个薄封装调用；要求 herdr ≥ 0.9.0，是
Node 插件，node 由 `modules/host.nix` 的 `nodejs_22` 提供）。

- `P C-r`：在 grouped-by-activity 与 flat recent-first 两种排序间翻转
- `P ,`：设置弹窗（空闲分级时长、glyph 样式等都在里面）
- 上游建议的 `P a` 被 Projects 占用、裸 `P r` 是 herdr resize 模式，所以
  这两个键改到了插件动作所在的 ctrl 层
- 插件自管三样东西，均不在仓库模板里：config.toml 尾部三块 marker-fenced
  配置（tab-bar 命令、`[ui.sidebar.*]` 着色行、`[theme.custom]`）、
  `~/Library/Fonts` 下的图标字体、kitty 的 codepoint map
- 模板每次激活都会用仓库版覆盖 config.toml，所以 postActivation 在装模板
  之后会调一次 `plugin action invoke configure` 修复三块配置；kitty 的
  codepoint map 直接预置在 `config/kitty/kitty.conf`（否则插件首次安装的
  build hook 会因写只读 Nix-store 软链硬失败）
- 插件默认跟随 macOS 深浅色模式并改写 `[theme] name`；模板把
  `light_name`/`dark_name` 都钉成 `"terminal"`，于是它只切换自己侧边栏
  的调色板，不会动 terminal 跟随 kitty 的主题
- 与 herdr-projects 共存：projects 1.2.x 自己提议的 `[ui.sidebar.agents]`
  三行任务状态行与 radar 的 glyph 表互斥，仓库模板**只发 radar 版**；
  projects 检测到侧边栏表已存在会把它当成用户手写表保留并跳过自己的块
  （任务三行在 board 弹窗里完整可见），因此激活不再需要排序约定

## 可选：roadboard 路线图看板

`roadboard` 是本地插件（Rust），把 Obsidian 里的 `roadmap.md` 渲染成可执行的
7 态嵌套任务树，并能把节点派给 herdr agent。插件源码在
`~/Documents/workspace/roadboard`，由共享激活脚本 `install-herdr-plugins.sh`
在仓库存在时 `herdr plugin link`（macOS/Linux 两个薄封装都会调它；本机本地
checkout，不是远端 pin；缺失也不让 activation 失败）。

- `P S-r`：切换 roadboard popup 看板（`type = "plugin_action"` →
  `roadboard.open`，打开注册的 `board` popup pane；看板聚焦时再按一次关闭）
- 看板内：`j/k` 移动、状态键翻转、Enter 派活（先复核 prompt 再确认）、`q` 关
- `C`：把选中节点**交给已有 herdr-projects coordinator**（不开新 agent）：
  `j/k` 选项目 → 复核消息 → `y` 发送；目标项目可在 detail note frontmatter
  写 `project: <slug>`（沿祖先继承，gate 里选中即写入绑定）。投递成功后节点
  标 `[/]`，后续 `?`/`x` 仍由人翻；coordinator 不调 `roadboard done`（无 run）。
  CLI：`roadboard projects` / `bind-project` / `handoff` / `preview --coordinator`
  > **已知缺口（2026-10）**：这条桥接写的是 herdr-projects 0.2 的 API
  > （`--root … list`、`coordinator prompt <slug>`）；nix-hm 已升到 1.2.13
  > （仓库注册表 + `coordinator --project <repo> tell`），roadboard 侧尚未
  > 适配，`C` 派活在改 roadboard 之前会失败；看板本身（状态翻转/树）不受影响。
- 派活默认在目标 workspace 新开一个**后台独立 tab**（标签 `road-rN`，
  `--no-focus` 不抢焦点）；同一节点重派复用其 tab/pane
- 占掉了 herdr 默认的 `P S-r`（重载配置）：需要时跑
  `herdr server reload-config`

## 可选：herdr-projects 任务看板与 project coordinator

`herdr-projects` 1.2.x 是一个工作看板：任务是 `repo/123` 形式的编号，每个被
delegate 的任务作为普通 herdr agent 跑在自己的 worktree space 里；每个注册
仓库还可以有一个 project coordinator（agent 名 `sw-coordinator-<repo>`），
由插件的 pump 守护在该仓库的 tab 里拉起。sidebar/tab 栏的任务状态聚合由
`P a` 打开的看板本身呈现。

- 插件由共享激活脚本 `install-herdr-plugins.sh` 直接 pin **上游**
  `eliasstravik/herdr-projects@v1.2.13`（不再用 fork；macOS 经
  `nix-darwin/herdr.nix` postActivation、Linux host 经
  `modules/herdr.nix` 两个薄封装调用；要求 herdr server ≥ 0.9.3；server 过
  旧时激活会跳过并提示重启 herdr。release 二进制由插件 bin/run.sh 安装期
  下载，本机不需要 Rust 工具链）
- 首次运行会把 0.2.x 时代的旧 `~/.herdr-projects`（slug 项目目录）归档到
  `~/.herdr-projects-legacy`；新数据全部在 `~/.herdr-projects/data`
  （`repos.json` 注册表、`tasks/<repo>/`、`coordinator/<session>/`）
- 激活不再有 `configure` 步骤：看板键 `P a`（`herdr-projects.open`）直接
  发在仓库 config.toml 模板里，插件因此不会再提议写键；它提议的
  `[ui.sidebar.agents]` 任务三行与 radar glyph 表互斥，模板有意不发
  （radar 保留侧边栏，插件会把已有表当用户手写表保留）；hooks/skill 由插件
  自己的 startup hook 维护
- 仓库注册：本地 git 仓库在首次被使用时注册进 `data/repos.json`。两个
  选择器脚本只是这个动作的 fzf 前端——`P S-c` 多选本地仓库注册并打开第一个
  仓库的 coordinator，`P S-a` 只注册不打开；注册不启动 agent（建一个不
  delegate 的占位任务立即 clear，只剩注册表项）
- `P C-p` 打开仓库：coordinator pane 还活着就聚焦；pane 没了但 state.json
  里有对话（如 herdr 重启后）就 `coordinator restart` 续同一个对话；从没
  起过才 `coordinator new`
- `P C-n` 无条件 `coordinator new`：在同一仓库重开一个全新对话（不复用旧
  上下文）。仓库按 cwd → 弹窗底层 pane 的 cwd → fzf 注册表解析
- `P C-f` 是**仓库里保留的本地 shell 功能**：上游只有顶层 Coordinator 的
  `open-coordinator` action，没有按仓库进入的入口。脚本读
  `data/coordinator/<session>/projects/<repo>/state.json` 里记录的 pane，并
  把 state 里的 socket 显式 pin 到 `HERDR_SOCKET_PATH` 再聚焦（跨 herdr
  session 也能跳）；记录的 pane 没了就退而求其次，在该 socket 的 agent
  列表里找名字为 `sw-coordinator-<repo>`（或 pump 去重产生的
  `sw-coordinator-<repo>-2/-3`，名字截断规则镜像 Rust `co.rs`：全名截 29
  字符留 3 个后缀位）、cwd 在仓库根的最新 agent。只聚焦、从不自启；没有在
  跑的 coordinator 时提示用 `P C-n`/`P C-p`
- 五个 popup launcher（new-project/pick-project/add-repo/new-coordinator/
  focus-coordinator）全部由单一来源 `modules/herdr-launchers.nix` 链到
  `~/.local/bin`，共享 `herdr-popup-lib.sh`；新增第六个只改这个模块
- launcher 解析 CLI 的顺序：`$HERDR_PROJECTS_BIN` →
  `~/.herdr-projects/data/bin/herdr-projects`（插件在看板首次打开时写入的
  launcher shim，自带数据目录环境变量）→ `~/.local/bin` → 插件 checkout 里
  `bin/run.sh` 下载的 release 资产
  （`~/.config/herdr/plugins/github/herdr-projects-*/bin/herdr-projects-<os>-<arch>`）
  → PATH；因此插件刚装完、看板还没打开过时 `P S-c` 注册也能找到二进制

## 可选：herdr-portal 全局 agent 看板

`herdr-portal`（pinned fork `v1.3.0-pf.1`，PannenetsF/herdr-portal，基于
上游 loofare/herdr-portal 未打 tag 的 1.3.0；纯
Python stdlib，无 node/uv 依赖）把全部 workspace/tab/pane 的 agent 聚合成
一个按 blocked/working/idle/done/unknown 分列的看板；状态尚未上报的
`unknown`（未知）agent 在上游 1.3.0 主看板上仍会消失（columns 没有 unknown
桶），pf.1 把它们并入「执行中」列，同一 tab 里多个刚启动的 agent 都可见，
且不会被空闲回收误杀；数据走 herdr 自己的 CLI/JSON，和 radar/projects 共存。

- `P S-o`：TUI 看板 overlay（`herdr-portal.open-board`）。↑↓ 选择、←→ 切列、
  `Enter` 跳到该 agent 的 pane 且看板自动关闭；`Tab`/`v` 切普通窗口视图；
  `N` 新 tab、`s/S` 右/下 split、`E` 重命名、`X` 释放闲置 pane、`Q` 退出。
  看板本身只读（只移动焦点，不发输入）。
- `P C-o`：web 大屏（`herdr-portal.open-web`，stdlib HTTP daemon
  `127.0.0.1:8787`，日志 `~/.local/state/herdr-portal/server.log`）。
  1.3.0 起 `/api/*` 需本机 token（自动生成于
  `~/.local/state/herdr-portal/token`，打开时经 URL 一次性带入并校验
  Host/Origin）。点击卡片同样跳 pane；web 端额外能直接给 agent **回消息**，
  不是纯只读。
- 插件按需打开、无 startup hook；激活只负责 pin 安装，不自动起看板。
- 占的是空着的 o 命名空间：上游 README 建议 `P a`，但该键在本配置属于
  herdr-projects。

## 卸载 / 重置

手动清理配方（以 herdr-projects 为例）：

```sh
# 1. 移除插件写进 live config 的块和 how-to 文件（看板键 P a 来自仓库模板，
#    下次 hm-update 会随模板一起消失）
herdr-projects remove-extras
# 2. 卸载插件
herdr plugin uninstall herdr-projects
# 3. 移除 nix-darwin/configuration.nix imports 里的 ./herdr.nix 后重新激活
# 4. 删除全部看板数据（不可恢复；0.2.x 旧数据在 ~/.herdr-projects-legacy）
rm -rf ~/.herdr-projects
```

herdr-radar 没有 unconfigure：需手删 config.toml 尾部三块 marker-fenced
配置（tab-bar 命令、`[ui.sidebar.*]`、`[theme.custom]`，见上文 radar
小节）以及 `~/Library/Fonts` 下的图标字体。
