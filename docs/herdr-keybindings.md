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
| 跳第 N 个 workspace | `P S-1..9`（对应 AeroSpace `alt-S-数字`） |
| 跳第 N 个 agent | `P C-1..9` |

## 按需才用

| 操作 | 按键 | 对应习惯 |
| --- | --- | --- |
| LazyGit 弹窗 | `P C-g` | nvim `<leader>g` |
| which-key 分组菜单（可选插件，见下） | `P Space` | which-key.nvim |
| zoetrope 会话流程图（可选插件，见下） | `P S-z` | — |
| herdr-radar 切换 agent 排序（可选插件，见下） | `P C-r` | — |
| herdr-radar 设置弹窗（可选插件，见下） | `P ,` | — |
| herdr-projects 项目总控（可选插件，见下） | `P a` | nvim `<leader>ao` explorer |
| herdr-projects 新建 / 打开项目 | `P S-c` / `P C-p` | nvim `<leader>ap`；C = create |
| herdr-projects 给项目追加仓库 | `P S-a` | fzf 多选，免手打路径 |
| Copy/滚动模式（vim 键位、`/` 搜索、`v` 选择、`y` 复制） | `P [` | — |
| 编辑滚动历史到 `$EDITOR` | `P S-e` | 原默认 `e`，给 sidebar 让位 |
| 设置界面 | `P S-s` | 原默认 `s`，给横分让位 |
| detach（全部后台继续跑） | `P q` | tmux 同键 |
| 跳到最新通知指向的 pane | `P o` | — |
| 重载配置 | `P S-r` | — |
| 完整按键面板（可 `/` 过滤） | `P ?` | — |

goto 面板（`P f`）里的过滤单键：`b/w/i/d` 分别过滤
blocked/working/idle/done 的 agent，`a` 恢复全部。

> herdr-projects 三个选择器：`P S-c` 用 fzf 选一个或多个已有 git 仓库建
> 多仓项目（Tab 勾选多个，Enter 确认；`config/herdr/new-project.sh`，
> 扫描根 `HP_PROJECT_ROOTS`，默认 `~/Documents/workspace`，深度 4 层，
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

`furkankly.zoetrope` 插件把聚焦的 agent pane 会话画成实时流程图。插件由
`nix-darwin/herdr.nix` postActivation 安装（pinned ref），`zoe` CLI 由
`nix-darwin/homebrew.nix` 管理。前提：`herdr integration install claude`
（或 codex）已装，且 agent 是在集成安装之后启动的，否则 pane 没有 session id。

- `P S-z`：在当前 pane 上叠加流程图，跟 live 会话；再按一次或图内 `q` 关闭
- 其他放置方式：`furkankly.zoetrope.open-split` / `open-tab`（改 config.toml
  里对应 command 后 `herdr server reload-config`）

## 可选：herdr-radar agent 状态侧边栏

`hhdebb.herdr-radar` 把 herdr 自带的 Agents 列表改造成可读的状态视图：工作中
braille spinner、完成绿勾保留到你看过为止、提问红色脉动、空闲按时间分三级
变淡；按项目/仓库分组（worktree 挂在仓库下）、按活跃度排序。插件由
`nix-darwin/herdr.nix` postActivation 安装（pinned `v1.4.2`，要求 herdr ≥
0.9.0，是 Node 插件，node 由 `modules/host.nix` 的 `nodejs_22` 提供）。

- `P C-r`：在 grouped-by-activity 与 flat recent-first 两种排序间翻转
- `P ,`：设置弹窗（空闲分级时长、glyph 样式等都在里面）
- 上游建议的 `P a` 被 Projects 占用、裸 `P r` 是 herdr resize 模式，所以
  这两个键改到了插件动作所在的 ctrl 层
- 插件自管三样东西，均不在仓库模板里：config.toml 尾部三块 marker-fenced
  配置（tab-bar 命令、`[ui.sidebar.*]` 着色行、`[theme.custom]`）、
  `~/Library/Fonts` 下的图标字体、ghostty/kitty 的 codepoint map
- 模板每次激活都会用仓库版覆盖 config.toml，所以 postActivation 在装模板
  之后会调一次 `plugin action invoke configure` 修复三块配置；kitty 的
  codepoint map 直接预置在 `config/kitty/kitty.conf`（否则插件首次安装的
  build hook 会因写只读 Nix-store 软链硬失败）
- 插件默认跟随 macOS 深浅色模式并改写 `[theme] name`；模板把
  `light_name`/`dark_name` 都钉成 `"terminal"`，于是它只切换自己侧边栏
  的调色板，不会动 terminal 跟随 kitty 的主题
- 与 herdr-projects 共存：v0.2.34 的 projects 会把自己的 tab-bar 命令和
  `$hp_sub` 侧边栏行合并进 radar 的 marker 块，所以激活顺序固定为 radar
  configure 在前、projects configure 在后。已知小缺口：macOS 深浅色切换
  时 radar 重写侧边栏块会临时丢掉 `$hp_sub`（tab-bar 条目会保留），下次
  `hm-update` 跑 projects configure 即恢复——属于上游未处理的 cosmetic 问题

## 可选：herdr-projects 多 agent 协作

`herdr-projects` 提供一个 coordinator agent：描述大任务后它拆成多个 thread，
每个 thread 是独立 worktree/分支上的 agent，共享目标与项目记忆；sidebar 按
「needs you / review / working」分组，tab 栏显示 `projects: N need you`。

- 插件由 `nix-darwin/herdr.nix` postActivation 安装（pinned `v0.2.34`，要求
  herdr server ≥ 0.9.1；server 过旧时激活会跳过并提示重启 herdr）
- 版本被 activation pin 在 `v0.2.34`：不要用插件自更新（`herdr-projects
  update` 等），下次激活会被装回 pin 版本
- sidebar 分组行、`P a` 弹窗、tab 栏条目不由仓库模板维护：激活时在模板
  写入 live config 之后跑 `herdr-projects configure`，由插件自己把这些块
  加进可写的 `~/.config/herdr/config.toml` 并记入 journal（幂等，`doctor`
  据此校验；hm-update 会先用模板覆盖，再由 configure 重新加回）
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
  `P a` 总控弹窗（configure 管理）；不带 `--repo` 的裸 `herdr-projects new`
  只建元数据目录，所以模板里的新建键走选择器

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
