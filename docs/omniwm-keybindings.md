# OmniWM 快捷键速查表

配置源：OmniWM **v0.7.6** 上游默认键位（本机 `/Applications/OmniWM.app` 即 0.7.6；
源码 `Sources/OmniWM/Core/Input/ActionCatalog*`，官方文档
`website/src/content/docs/guides/keyboard-shortcuts.md`）。仓库不做 AeroSpace
键位整体迁移（只固化后述 niri 风格子集）、也不预置 settings.toml；首次启动由
OmniWM 自己生成完整可写配置 `~/.config/omniwm/settings.toml`。改键优先用
**Settings → Hotkeys** 录制界面。

记号：`⌥` = Option（Alt）、`⌃` = Control、`⇧` = Shift、`⌘` = Command、
`↵` = Return、`` ` `` = 反引号（Tab 上方）。默认布局是 **Niri**：屏幕上横向
排列若干「列（column）」，每列内纵向堆叠窗口；工作区本身上下堆叠。布局兼容性：
**Shared** = Niri/Dwindle 通用；**Niri** / **Dwindle** = 仅对应布局，工作区可
用 `⌥⇧L` 整体切换。

> 下表是上游 v0.7.6 **默认**键位；激活后实际生效的 hjkl / 逗号句号卷轴
> 固化键位见后面的「固化的键位」一节。

## 先记这几条：和 AeroSpace 肌肉记忆冲突最大

| 事项 | AeroSpace 旧键 | OmniWM v0.7.6 默认（固化后） |
| --- | --- | --- |
| 移动焦点 | 裸 `⌥h/j/k/l` | 上游默认 `⌥←↓↑→`；**固化为 `⌥h/j/k/l`**（方向键被替换） |
| 移动窗口 | `⌥⇧h/j/k/l` | 上游默认 `⌥⇧←↓↑→`；**固化为 `⌥⇧h/j/k/l`** |
| 工作区来回 | `⌥Tab` | `⌃⌥Tab`；`⌥Tab` 在 OmniWM 是「上一个聚焦窗口」 |
| 工作区甩到另一块屏 | `⌥⇧Tab` | 默认无绑定；切显示器焦点用 `⌃⌘Tab` / `` ⌃⌘` `` |
| 调整大小 | `⌥⇧-` / `⌥⇧=` | `⌥-`/`⌥=` 调列宽；`⌥⇧-`/`⌥⇧=` 调窗口高度 |
| 全屏 | service 模式里的 fullscreen | `⌥↵`（OmniWM managed fullscreen） |
| 第 10 个工作区 | `⌥0` 常驻 | 默认只有 1–9；10+ 需先创建，动作默认无键 |
| 布局切换 | `⌥/` tiles、`⌥,` accordion | `⌥⇧L` 切 Niri/Dwindle；`⌥,`/`⌥.` 是尺寸循环 |

## 肌肉记忆层（Niri 日常）

| 操作 | 按键 | 布局 |
| --- | --- | --- |
| 左/右跨列、上/下列内切焦点 | `⌥← →` / `⌥↑ ↓` | Shared |
| 窗口吸进相邻列 / 抽成新列；列内上下重排 | `⌥⇧← →` / `⌥⇧↑ ↓` | Shared |
| 切工作区 1–9 | `⌥1..9` | Shared |
| 当前窗口送到工作区 1–9（并跟过去） | `⌥⇧1..9` | Shared |
| 上一个工作区（back and forth） | `⌃⌥Tab` | Shared |
| 当前窗口送到上/下一个工作区 | `⌃⌥⇧↑` / `⌃⌥⇧↓` | Shared |
| 当前列送到上/下一个工作区 | `⌃⌥⇧PgUp` / `⌃⌥⇧PgDn` | Niri |
| OmniWM 全屏 | `⌥↵` | Shared |
| 命令面板（命令/窗口/剪贴板） | `⌃⌥Space` | Shared |
| Overview 总览 | `⌥⇧O` | Shared |

单窗口时全屏看不出变化，先并两列再试。横向 Niri 方向下，`⌥⇧←→` 负责跨列
吸入/抽出，`⌥⇧↑↓` 在列内重排；纵向（vertical）方向下两者角色对调。

## 固化的键位（激活自动 seed）

仓库的 `config/omniwm/apply-hotkey-overrides.sh` 在 nix-darwin postActivation
以用户身份运行，把下面这套**机器无关**的键位改写进 OmniWM 自有的
settings.toml（只动固定 action id 的 `binding` 和 `systemHyperTrigger`，不碰
显示器路由 / workspace 身份等机器本地段）。每个 revision 只 seed 一次并写
`~/.config/omniwm/.hotkey-overrides.rev`，之后 GUI 改键不会被激活覆盖；
`OMNIWM_HOTKEY_FORCE=1` 可强制重跑，脚本也可单独手动执行。首次激活时 OmniWM
可能还没生成 settings.toml（首次启动是手动步骤），脚本会跳过；首次启动后重跑
一次 `bash config/omniwm/apply-hotkey-overrides.sh` 或再激活一次即可。

| 操作 | 上游默认 | 固化键位 |
| --- | --- | --- |
| 焦点左下上右 | `⌥←↓↑→` | `⌥H/J/K/L`（方向键替换，不并存） |
| 窗口吸入/抽出/重排 | `⌥⇧←↓↑→` | `⌥⇧H/J/K/L` |
| 顺序切下/上一个工作区（niri 卷轴） | 未绑定 | `⌥.` / `⌥,` |
| 带窗口去上/下个工作区 | `⌃⌥⇧↑/↓` | `⌥⇧,` / `⌥⇧.` |
| 带列去上/下个工作区（Niri） | `⌃⌥⇧PgUp/PgDn` | `⌃⌥⇧,` / `⌃⌥⇧.` |
| 列宽尺寸循环（占用了 `⌥.`，让键） | `⌥.` / `⌥,` | `⌥R`（反向循环解绑） |
| Niri ↔ Dwindle 切换（给 `⌥⇧L` 让路） | `⌥⇧L` | `⌥⇧/` |
| System Hyper Trigger | 首次启动曾误得 Left Option | `None`（Hyper 归 Karabiner） |

语义差异：niri 是横向无限卷轴、滚过尽头自动开空工作区；OmniWM 工作区轴是
**纵向**（Up/Down、触摸板默认上下滑），`,`/`.` 是顺序遍历的键位映射，默认
9 个常驻工作区，滚到末尾不自动新建。触摸板想横向卷轴，把
`workspaceSwipeAxis` 改成 `"horizontal"`，注意与 Option+双指列滚动的手指数
错开。其余上游默认键（`⌥1..9`、`⌥↵`、`⌃⌥Space`、`⌥⇧O` 等）原样不动。

## 焦点与显示器

| 操作 | 按键 | 布局 |
| --- | --- | --- |
| 回到上一个聚焦的窗口 | `⌥Tab` | Shared |
| 第一列 / 最后一列 | `⌥Home` / `⌥End` | Niri |
| 直接聚焦第 N 列（高级动作） | `⌃⌥1..9` | Niri |
| 按顺序聚焦下一块显示器 | `⌃⌘Tab` | Shared |
| 聚焦上一块活跃显示器 | `` ⌃⌘` `` | Shared |
| 在鼠标位置打开 OmniWM 菜单 | `⌃⌥M` | Shared |
| Quake 下拉终端 | `` ⌥` `` | Shared（不用它：kitty 下拉仍走 skhd 的 `⌘'`） |

## 列与布局调整

主轴 = 横向列宽，次轴 = 列内窗口高度；增减步长默认 5%，可在 Niri 设置的
Resize Increment / `[niri].resizeStepPercent` 调整。

| 操作 | 按键 | 布局 |
| --- | --- | --- |
| 尺寸循环 − / +（列宽预设档） | `⌥,` / `⌥.` | Shared |
| 列宽收缩 / 放大（容器主轴跨度） | `⌥-` / `⌥=` | Niri |
| 窗口高度收缩 / 放大（次轴跨度） | `⌥⇧-` / `⌥⇧=` | Niri |
| 窗口次轴跨度复位 | `⌃⌥R` | Niri |
| 当前列全宽开关 | `⌥⇧F` | Niri |
| 当前列扩展到全部可用宽度（高级动作） | `⌃⌥F` | Niri |
| 所有列/窗口均分 | `⌥⇧B` | Shared |
| 整列左移 / 右移（Dwindle 下为整个 tile/group） | `⌃⌥⇧←` / `⌃⌥⇧→` | Shared |
| 列移到最前 / 最后 | `⌃⌥Home` / `⌃⌥End` | Niri |
| 当前列切换 tabbed 标签模式 | `⌥T` | Niri |
| 抬起所有被压住的浮动窗口 | `⌥⇧R` | Shared |
| 当前工作区切换 Niri ↔ Dwindle | `⌥⇧L` | Shared |

## Dwindle 布局下

Dwindle 组复用 Focus/Move 绑定，不另设键：

- 组内 `⌥↓` / `⌥↑` 选下一个/上一个 tab；`⌥←→` 永远是空间方向。
- `⌥⇧方向`：窗口为单 tile 时与相邻 tile 合并成组；已在组内时把活动 tab 抽出。
- 移动整个 tile/group 用 `⌃⌥⇧←→`（上下方向是默认无绑的高级动作）。
- 直接点 tab rail 可精确选某个 tab，且不改组内顺序。

## 默认没绑、建议去 Settings → Hotkeys 自行绑定的动作

| 动作 | 用途 |
| --- | --- |
| Close Focused Window | 关闭聚焦窗口（OmniWM 默认不提供关闭键） |
| Toggle Focused Window Floating | 当前窗口浮动 / 平铺 |
| Toggle Native Fullscreen | 原生全屏（视频、浏览器等场景） |
| Focus Previous Monitor in Order | 与 `⌃⌘Tab` 对称的「上一块显示器」 |
| Switch to Next / Previous Workspace | 顺序切工作区（默认只能按数字或上下转移） |
| Move Workspace to Monitor ←→↑↓ | AeroSpace `⌥⇧Tab` 的替代（4 个方向动作，运行时临时覆盖，不改 Home Monitor） |
| Move Focused Window to Monitor ←→↑↓ | 把窗口直接送到相邻显示器的当前工作区 |
| Scratchpad toggle / assign ×10 | niri 式暂存盘，呼出与分配各 10 个槽 |
| Workspace Slot 1–9 switch / move | 工作区在当前显示器上的位置槽位 |
| Rescue Off-Screen Floating Windows | 浮动窗口跑到屏幕外时救命 |
| Toggle Workspace Bar / System Stats | 工作区栏、系统状态浮层 |

创建第 10+ 个工作区后，其 switch / move / move-column 行会自动出现在 Hotkeys
列表（默认无键）；工作区删除后这些行消失。

## 命令面板内的局部键

`⌃⌥Space` 打开，Windows 模式下对选中行：`⌃⌥⇧M` 打窗口标记、`⌃⌥⇧R` 取消
标记。全局版 Set/Remove Mark 动作默认无绑。

## 与本机其他快捷键的冲突

- **skhd 保持不变**：`⌘'` 呼出 kitty 下拉终端、`⌘⇧↵` 新开 Chrome，OmniWM
  默认绑定不碰这两个。
- **herdr（终端内）**：herdr 的 prefix `P` = `⌃B`，另有 `⌃⌥` 直连和弦；
  OmniWM 是全局热键，终端聚焦时也由它先吃掉。默认绑定里唯一实质冲突是
  **`⌃⌥F`**：herdr 的 `C-A-f` 是模糊跳转，OmniWM 里是高级动作
  「Expand Container to Available Primary Span」——初期建议在
  Settings → Hotkeys 把 OmniWM 这条解绑或改键。其余 herdr `C-A-字母`
  （c/v/s/x/z/e/hjkl 等）与 OmniWM 默认不重；`C-A-方向` 调 pane 大小也不与
  带 `⇧` 的 OmniWM 容器移动冲突。
- **Karabiner**：OmniWM 的 System Hyper Trigger 保持 None，Hyper 继续由
  Karabiner 产出；Hyper 默认定义为 `⌃⌥⇧⌘` 同按，可在设置里改组成。
- 快捷键不触发时，先看 Settings → Hotkeys 的注册警告和 Troubleshooting；
  skhd、Raycast 等持有同一绑定时会抢注。
- **System Hyper Trigger 必须是 None**（Settings → Hotkeys）。首次启动曾默认
  Left Option：按住左 Option 会被吞掉并注入 Hyper，所有 `⌥…` 热键全部失效，
  表现为 `⌥1` 直接上屏 `¡`。改成 None 后若仍不生效，是辅助功能授权在当前登录
  会话没真正落地——注销重新登录（或重启）后恢复；必要时在系统设置里对
  `/Applications/OmniWM.app` 关掉再开 Accessibility / Input Monitoring。

## 自定义与配置文件注意事项

- 所有动作（含标记为 advanced 的动作、鼠标侧键、Hyper）都能在
  Settings → Hotkeys 录制；也支持额外鼠标键（单击或带修饰键）。
- `settings.toml` 是**整文件严格校验**：每个动作至多出现一次，未知或重复的
  action id 会让整份配置被拒，缺必需键同样拒绝。只在 GUI 里改或原位改值，
  不要手删键；OmniWM 升级时自动迁移 schema，并写一次性备份
  `settings.toml.pre-v4`。
- 显示器物理布局、工作区→显示器路由只存在本机可写设置里，不进仓库模板。

参考：<https://omniwm.app/guides/keyboard-shortcuts/>（v0.7.6）；
试用与回退流程见 [omniwm-trial.md](omniwm-trial.md)。
rial.md)。
