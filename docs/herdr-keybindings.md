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
| herdr-projects 项目总控（可选插件，见下） | `P a` | configure 合并的 overview 弹窗 |
| herdr-projects 新建 / 打开项目 | `P S-c` / `P C-p` | nvim `<leader>ap`；C = create |
| herdr-projects 再开 / 登记 coordinator | `P C-n` | n = new；未注册的根 pane 上改为当场 adopt |
| herdr-projects 聚焦 coordinator | `P C-f` | f = focus；跳到注册的 coordinator，无则提示登记 |
| herdr-projects 给项目追加仓库 | `P S-a` | fzf 多选，免手打路径 |
| roadboard 路线图看板（可选插件，见下） | `P S-r` | 7 态任务树；再按一次关闭 |
| herdr-portal 全局 agent 看板 TUI（可选插件，见下） | `P S-o` | 最左「待处理」列定位响铃 session；Enter 跳 pane/restart |
| herdr-portal 全局 agent 看板 web 大屏 | `P C-o` | 浏览器 127.0.0.1:8787；可回消息 |
| 跳下一个待处理 agent（可选插件，见下） | `P u` | toast 飘走后用；blocked→done 循环 |
| Copy/滚动模式（vim 键位、`/` 搜索、`v` 选择、`y` 复制） | `P [` | — |
| 编辑滚动历史到 `$EDITOR` | `P S-e` | 原默认 `e`，给 sidebar 让位 |
| 设置界面 | `P S-s` | 原默认 `s`，给横分让位 |
| detach（全部后台继续跑） | `P q` | tmux 同键 |
| 跳到最新通知指向的 pane | `P o` | — |
| 重载配置 | `herdr server reload-config` | 默认 `P S-r` 已让给 roadboard，用命令行 |
| 完整按键面板（可 `/` 过滤） | `P ?` | — |

goto 面板（`P f`）里的过滤单键：`b/w/i/d` 分别过滤
blocked/working/idle/done 的 agent，`a` 恢复全部。

> herdr-projects 三个选择器：`P S-c` 用 fzf 选一个或多个已有 git 仓库建
> 多仓项目（Tab 勾选多个，Enter 确认；`config/herdr/new-project.sh`，
> 扫描根 `HP_PROJECT_ROOTS`，默认冒号分隔的 `~/Documents:~/.config`，深度 4 层，
> 选中后输入任意项目名（大小写和空格原样保留为显示名，如 `Erdos`、
> `my project`；slug 由 `herdr-projects new` 自动派生）并打开，重名则
> 转为给已有项目追加仓库）；
> `P S-a` 给已有项目追加仓库（先选项目，再多选仓库，已挂的自动隐藏，
> `config/herdr/add-repo.sh`）；
> `P C-p` 用 fzf 选已有项目打开（`config/herdr/pick-project.sh`）。
> 插件自带的 open 动作在项目 workspace 里会直接回当前项目而不询问，
> 所以打开键走这个始终询问的脚本。三个弹窗出错都会停住显示错误。
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
- 与 herdr-projects 共存：v0.2.34 的 projects 会把自己的 tab-bar 命令和
  `$hp_sub` 侧边栏分组行合并进 radar 的 marker 块，所以激活顺序固定为
  radar configure 在前、projects configure 在后（共享激活脚本已保证）。
  已知小缺口：macOS 深浅色切换时 radar 重写侧边栏块会临时丢掉
  `$hp_sub`（tab-bar 条目会保留），下次 `hm-update` 跑 projects
  configure 即恢复——属于上游未处理的 cosmetic 问题

## 可选：roadboard 路线图看板

`roadboard` 是本地插件（Rust），把 Obsidian 里的 `roadmap.md` 渲染成可执行的
7 态嵌套任务树，并能把节点派给 herdr agent。插件源码在
`~/Documents/workspace/roadboard`，由共享激活脚本 `install-herdr-plugins.sh`
在仓库存在时 `herdr plugin link`（macOS/Linux 两个薄封装都会调它；本机本地
checkout，不是远端 pin；缺失也不让 activation 失败）。

- `P S-r`：切换 roadboard popup 看板（`type = "plugin_action"` →
  `roadboard.open`，打开注册的 `board` popup pane；看板聚焦时再按一次关闭）
- 看板内：`j/k` 移动、`h/l` 折叠、状态键翻转、Enter 派活（先复核 prompt 再确认）、`q` 关
- `T`：在 roadmap 末尾新增一个 `## 主题` chain 并带上第一个任务（两步行内
  输入：先标题、再任务；Esc 取消）。CLI：
  `roadboard add-chain "主题" --task "第一件事"`
- 长行（含中文双宽字符）在 popup 内按视觉列自动换行，光标移动时滚动跟随
- `C`（**回归中，当前不可用**）：原设计把选中节点交给 herdr-projects 的
  project coordinator（不开 road-rN agent）。该桥接一度按上游 1.2 的
  `herdr-projects coordinator tell --project <repo>` 实现；2026-10 整体
  回退到 0.2 fork（见下节）后，1.2 CLI 已不存在，`C` 派发必然失败，需在
  roadboard 独立仓库（`~/Documents/workspace/roadboard`）改回 0.2 的
  `coordinator prompt <slug>` 语义后才恢复。在修好之前不要依赖它；
  detail note frontmatter 的 `project: <repo>` 绑定语义保留。
  CLI：`roadboard projects` / `bind-project` / `handoff` / `preview --coordinator`
- 派活默认在目标 workspace 新开一个**后台独立 tab**（标签 `road-rN`，
  `--no-focus` 不抢焦点）；同一节点重派复用其 tab/pane
- 占掉了 herdr 默认的 `P S-r`（重载配置）：需要时跑
  `herdr server reload-config`

## 可选：herdr-projects 多 agent 协作（0.2 fork，永久 pin）

`herdr-projects` 提供一个 coordinator agent：描述大任务后它拆成多个 thread，
每个 thread 是独立 worktree/分支上的 agent，共享目标与项目记忆；thread 状态
六分组（waiting-on-you / ready-for-review / working / landing / idle /
resolved），sidebar 按「待你处理 / 待评审 / …」分组，tab 栏显示需要注意的
数量。**常驻 ticker 是唯一响铃源**：thread 进入 waiting-on-you /
ready-for-review 时它调 `herdr notification show --sound request/done`。

> **永久 pin fork `v0.2.34-pf.2`，不要升级上游 1.2.x。** 上游
> `eliasstravik/herdr-projects` 1.2 是不兼容的任务看板模型（任务
> `repo/123`、`data/repos.json`、keeper/voice 守护），删掉了 thread 状态机
> 和 ticker——2026-10 曾切到 1.2.13，响铃全部消失、需要交互的 session 无从
> 查找，当月回退。激活脚本检测到 1.2 插件会自动 uninstall 并收掉它的四个
> 孤儿守护。数据根是 `~/.herdr-projects/<slug>/`（0.2 布局）。

- 插件由共享激活脚本 `install-herdr-plugins.sh` 安装（fork pinned
  `v0.2.34-pf.2`，PannenetsF/herdr-projects；macOS 经
  `nix-darwin/herdr.nix` postActivation、Linux host 经 `modules/herdr.nix`
  两个薄封装调用；要求 herdr server ≥ 0.9.1；server 过旧时激活会跳过并提示
  重启 herdr）。fork 无 release 资产，安装走本机 cargo 构建（两个薄封装的
  PATH 都前置 `~/.cargo/bin`）
- 版本被激活 pin 在 fork `v0.2.34-pf.2`：不要用插件自更新（`herdr-projects
  update` 等），下次激活会被装回 pin 版本
- **coordinator 身份是注册的 agent 名**（pf.2 起）：只有带 `hpc-<slug>` /
  `hpc-<slug>-N` 名字、且 cwd 在项目家目录的 agent 才算 coordinator。
  在项目根目录手动开的会话（split pane、`claude --resume`）默认是「野
  会话」：ticker 不给它投递 inbox、`context` 会拒绝它（避免全局标 seen
  把 inbox 从真 coordinator 眼前藏掉）、sidebar 落到 `~` 尾段。用
  `coordinator adopt <slug> --pane <id>`（或在该 pane 内按 `P C-n`）登记，
  首次登记成为 primary；记录里的 pane 在同会话里连 shell pane 都不存在
  时视为过期，adopt 直接顶替；nudge 一旦选定某个 coordinator 会话就粘住，
  它消失后才重选
- sidebar 分组行、`P a` 弹窗、tab 栏条目不由仓库模板维护：激活时在模板
  写入 live config 之后跑 `herdr-projects configure`，由插件自己把这些块
  加进可写的 `~/.config/herdr/config.toml`（幂等；hm-update 会先用模板
  覆盖，再由 configure 重新加回）。configure 必须在 radar configure 之后
  （合并同一组 marker 块）；`~/.local/bin/herdr-projects` 链接首装悬空时，
  激活脚本回退 `herdr plugin action invoke configure --plugin herdr-projects`
- 同一个 configure 同时维护 agent 进度上报 hooks 和 `autoproject` skill
  链接（也能修复被其他工具重写 settings.json 挤掉的 hooks）
- 后台 ticker 在还没有任何项目时不会启动（`doctor` 会显示 not running，属
  正常）；`herdr-projects open/new` 创建第一个项目时自动拉起
- 新建项目：`herdr-projects new "名字" --repo <path>` 后
  `herdr-projects open <名字>`，然后只跟 coordinator 对话
- 快捷键：`P S-c` fzf 选已有仓库新建项目（脚本装为
  `~/.local/bin/herdr-new-project`，仓库根用 `HP_PROJECT_ROOTS` 覆盖）、
  `P C-p` fzf 选已有项目打开（`~/.local/bin/herdr-pick-project`；不用插件
  自带 open 动作，因为它在项目 workspace 内不询问直接回当前项目）、
  `P C-n`（`~/.local/bin/herdr-new-coordinator`；项目按 cwd → 底层 pane 的
  `hp_project` → fzf 顺序解析）在**已注册** coordinator/thread、guest 或
  外部 pane 上仍是 `open <slug> --new --tab` 再开一个 coordinator；在
  **未注册但 cwd 正好是项目家目录**的 pane 上则 detach 跑
  `coordinator adopt --pane` 把当前会话登记成 `hpc-<slug>`（日志
  `$TMPDIR/herdr-adopt-coordinator-<slug>.log`），避免重复开新
  coordinator 把会话越堆越多、
  `P C-f`（`~/.local/bin/herdr-focus-coordinator`，f = focus）跳到项目的
  注册 coordinator：先查 `<root>/<slug>/.state/coordinator.json` 的
  pane_id，记录的 pane 没了就退到任意在线的 `hpc-<slug>` 名字族成员（
  按 state_change_seq 取最新）；底层 pane 是未注册的根会话时同样改为
  adopt；一个注册 coordinator 都没有时提示「在该 pane 按 P C-n 登记」。
  `open`/adopt 都 detach 到后台（nohup），popup 立即关闭、
  `P a` 总控弹窗（configure 管理）；不带 `--repo` 的裸 `herdr-projects new`
  只建元数据目录，所以模板里的新建键走选择器
- 五个 popup launcher（new-project/pick-project/add-repo/new-coordinator/
  focus-coordinator）全部由单一来源 `modules/herdr-launchers.nix` 链到
  `~/.local/bin`，共享 `herdr-popup-lib.sh` 里的截断/名字族判定（镜像
  Rust `names.rs` 的 24/22 截断规则）；新增第六个只改这个模块

## 可选：herdr-portal 全局 agent 看板

`herdr-portal`（PannenetsF/herdr-portal fork，pinned `v1.3.0-pf.2`，fork 自
上游 loofare/herdr-portal 未打 tag 的 1.3.0 release commit `ba47b65`，纯
Python stdlib，无 node/uv 依赖）把全部 workspace/tab/pane 的 agent 聚合成
一个看板。fork 两个补丁：

1. **unknown 卡可见（pf.1）**：上游 1.3.0 的 columns 只有
   blocked/working/settled/window 四个桶，状态尚未上报的 `unknown`（未知）
   agent 在主看板上消失、也会被空闲回收当候选；fork 把它们并入「执行中」
   列（保留「未知」标签与计数）并在回收判定里保护。
2. **「待处理」attention 列（pf.2）**：看板最左一列直接读 herdr-projects
   0.2 fork 的 thread 状态（`thread list <slug> --json`，root 自动发现
   `~/.herdr-projects`、回退 `~/.herdr-projects-legacy`；只认 0.2.x 二进制，
   1.2 显式忽略）。waiting-on-you / ready-for-review 的 thread：对应 pane
   还活着就标注并挪进该列（waiting-on-you 排最前），pane 已死则显示虚拟
   卡。这样 ticker 响铃后要处理的 session 在看板第一眼就能找到，不用再手动
   翻 pane——这是回退 1.2 后新增的列，勿删。

- `P S-o`：TUI 看板 overlay（`herdr-portal.open-board`）。↑↓ 选择、←→ 切列、
  数字键 `1..5` 跳列；`Enter` 在普通卡上跳到该 agent 的 pane 并关闭看板，
  在「待处理」虚拟卡（pane 已死的 thread）上则先 `thread restart` 再跳到新
  pane；`Tab`/`v` 切普通窗口视图；`N` 新 tab、`s/S` 右/下 split、
  `E` 重命名、`X` 释放闲置 pane、`Q` 退出。看板本身只读（只移动焦点/重启
  thread，不发输入）。
- `P C-o`：web 大屏（`herdr-portal.open-web`，stdlib HTTP daemon
  `127.0.0.1:8787`，日志 `~/.local/state/herdr-portal/server.log`）。
  `/api/*` 需本机 token（自动生成于
  `~/.local/state/herdr-portal/token`，打开时经 URL 一次性带入并校验
  Host/Origin）。点击普通卡跳 pane、可直接给活 agent **回消息**；
  attention 虚拟卡走 `/api/legacy-restart`（重启 thread 后跳转），不提供回复框。
- 插件按需打开、无 startup hook；激活只负责 pin 安装，不自动起看板。
- 占的是空着的 o 命名空间：上游 README 建议 `P a`，但该键在本配置属于
  herdr-projects。

## 可选：herdr-unread-jump 待处理跳转

`to4iki/herdr-unread-jump`（纯 bash+jq，jq 在 host 包集；min herdr 0.7.5，
activation 无条件 pin 安装）解决「toast 飘走后忘记是哪个 pane」：

- herdr 应用内 toast 的驻留时长是硬编码的（请求输入 8 秒、完成 5 秒），
  v0.9.5 与上游 master 都没有 sticky / duration 配置（`ui.toast.delay_seconds`
  只是通知**发出前**的防抖秒数，不是显示时长；上游讨论
  [#1379](https://github.com/herdrdev/herdr/discussions/1379)
  / [#2565](https://github.com/herdrdev/herdr/discussions/2565) 尚未实现）。
- `P u`（`to4iki.unread-jump.next`）：聚焦下一个仍需处理的 agent pane，
  blocked 优先、done 次之，在该组内循环（wrap）；没有待处理时报错退出，
  不移动焦点。数据走 `herdr agent list` 的 JSON，不写任何状态。
- 与 `P o`（只在 toast 还可见时跳到通知目标）互补；也可以直接看
  `P S-o` portal 看板或 radar 侧边栏的常驻 blocked glyph。

## 卸载 / 重置

手动清理配方（以 herdr-projects 为例）：

```sh
# 1. 移除 configure 加进 live config 的块、hooks 和 skill 链接
~/.local/bin/herdr-projects unconfigure
# 2. 卸载插件
herdr plugin uninstall herdr-projects
# 3. 移除 nix-darwin/configuration.nix imports 里的 ./herdr.nix 后重新激活
# 4. 删除全部项目元数据（不可恢复）
rm -rf ~/.herdr-projects
```

herdr-radar 没有 unconfigure：需手删 config.toml 尾部三块 marker-fenced
配置（tab-bar 命令、`[ui.sidebar.*]`、`[theme.custom]`，见上文 radar
小节）以及 `~/Library/Fonts` 下的图标字体。
