# Agent 导读 (AGENTS.md)

本文件给后续接手的 AI Agent 一个项目级地图：这个仓库现在不只是
Home Manager dotfiles，而是 **Nix Home Manager + nix-darwin + Homebrew**
共同管理的个人开发环境配置库。

## 1. 项目定位

仓库名通常称为 `dot-nix` / `nix-hm`，实际路径多为
`$HOME/.config/nix-hm`。它负责：

- 通过 `init.sh` 一键安装/修复 Nix、拉取本仓库并激活配置；
- 用 Home Manager 管理用户级 shell、CLI、Neovim、tmux 和 dotfile 链接；
- 在 macOS 上默认用 nix-darwin 管理系统级设置、Homebrew、GUI app、defaults、
  Touch ID sudo 和部分 launchd agent；
- 在 Linux 上保留 Home Manager 激活路径，服务器初始化仍由
  `install-linux-server.sh` 执行。

支持的系统：

- `x86_64-darwin`
- `aarch64-darwin`
- `x86_64-linux`
- `aarch64-linux`
- Linux 额外提供 `*-linux-host` profile（更完整的主机工具集）和
  `*-linux-docker` profile（精简的容器层，激活期不联网）。

## 2. 启动与激活流程

`init.sh` 是唯一推荐入口。常用方式：

- `bash ~/.config/nix-hm/init.sh`
- `hm-update`
- `hm-upgrade` 或 `bash init.sh --upgrade`
- Linux 主机工具集：`bash init.sh --host` 或 `NIX_HM_PROFILE=host bash init.sh`
- Linux 容器层：`bash init.sh --docker` 或 `NIX_HM_PROFILE=docker bash init.sh`
  （`--host` 与 `--docker` 互斥，`--docker` 仅限 Linux）
- macOS 强制走 Home Manager 旧路径：`bash init.sh --home-manager` 或
  `NIX_HM_USE_HOME_MANAGER=1 bash init.sh`

启动脚本的真实职责：

1. 读取 `PF_proxy` / `PF_http_proxy` / `PF_https_proxy` / `PF_no_proxy` 等代理变量，
   并同步到标准大小写 proxy 环境变量。
2. 自动安装 Nix。macOS 默认使用 Determinate pkg installer，可用
   `NIX_HM_DARWIN_NIX_INSTALLER=cli` 切换到 CLI installer；Linux 使用
   Determinate CLI installer。CLI installer 冻结在固定 release tag
   （`NIX_HM_DETERMINATE_TAG`，默认 `v3.17.2`），需要跟进新版时显式覆盖
   （例如 `NIX_HM_DETERMINATE_TAG=latest`）；pkg URL 用
   `NIX_HM_DETERMINATE_PKG_URL` 覆盖。
3. source Nix profile，确保 `nix` 可用。
4. 写入仓库托管的 Nix cache 配置块：
   - 用户配置：`$HOME/.config/nix/nix.conf`
   - daemon 配置：`/etc/nix/nix.custom.conf`，并在 `/etc/nix/nix.conf` 中 include
   - 如有 daemon 变更会尝试重启 `nix-daemon`
   - substituter 默认 `https://mirrors.ustc.edu.cn/nix-channels/store
     https://cache.nixos.org/`（中国镜像在前），对所有平台/profile 生效；
     海外网络或需要换源时用 `NIX_HM_SUBSTITUTERS` 整体覆盖，
     `NIX_HM_TRUSTED_PUBLIC_KEYS` 同理。
5. 对本仓库执行安全 `git pull --rebase`：有未提交、暂存或未跟踪改动时会跳过，
   避免覆盖本地工作。
6. 如果 pull 后 `init.sh` 自身更新，会 `exec` 重新运行一次新脚本。
7. `--upgrade` 会先确认，再执行 `nix flake update`；macOS 上 darwin-rebuild
   switch 成功后还会读取**新激活系统** `/run/current-system/activate` 引用的
   Brewfile，执行 `brew update` + `brew bundle --file=… --upgrade`。普通
   `hm-update` 不升级任何 brew/cask（nix-darwin 激活固定
   `brew bundle --no-upgrade`，见 `nix-darwin/homebrew.nix`）。
8. macOS 默认先运行 `brew/install.sh` 确保 Homebrew 和必要 tap 可用，然后通过
   `nix run .#darwin-rebuild -- switch --flake .#<system> --impure` 激活
   nix-darwin。非 root 运行时会通过 `sudo env` 传入 `NIX_HM_USER` 和
   `NIX_HM_HOME`。这一次 `sudo` 就是唯一的管理员授权点；不再默认预授权
   （`sudo -v`），因为在 `timestamp_timeout=0` 或仅 Touch ID 的机器上凭据无法
   复用，预授权只会多弹一次。需要提前预授权 + keepalive 时设
   `NIX_HM_SUDO_KEEPALIVE=1`。
9. Linux 或 macOS `--home-manager` 路径会执行
   `nix run nixpkgs#home-manager -- switch -b backup --flake .#<system>`。

重要环境变量：

- `NIX_HM_USER` / `NIX_HM_HOME`：显式指定 flake 评估时的用户和 home 目录。
- `DEBUG=1`：打开 shell trace，并传给 `NIX_HM_DEBUG`。
- `NIX_HM_SUDO_KEEPALIVE=1`：可选，提前 `sudo -v` 预授权并 keepalive；默认关闭，
  让 `darwin-rebuild` 自己发起唯一一次 sudo 提示。
- `NIX_HM_USE_HOME_MANAGER=1`：macOS 上跳过 nix-darwin，使用 Home Manager。
- `NIX_HM_DETERMINATE_TAG`：覆盖冻结的 Determinate CLI installer release tag。
- `NIX_HM_BREW_BOOTSTRAP`：替换 Homebrew bootstrap 脚本，测试里常用。
- `PIP_POSTFIX`、`PIP_INDEX_URL`、`PIP_TRUSTED_HOST` 等：会保留给激活脚本使用。

## 3. Flake 与模块结构

`flake.nix`

- 输入：
  - `nixpkgs/nixos-25.05`
  - `nixpkgs/nixos-unstable`
  - `home-manager/release-25.05`
  - `nix-darwin/nix-darwin-25.05`
- `mkUserHome` 从 `NIX_HM_*`、`SUDO_USER`、`USER`、`HOME` 推导用户名和 home。
  macOS sudo 场景尤其依赖这里，避免把用户 home 错推成 `/var/root`。
- `mkHomeConfig` 接受 `isHost` 与 `isDocker` 两个开关，通过 `extraSpecialArgs`
  传给 `home.nix`。
- 输出：
  - `homeConfigurations`：Linux（默认桌面/服务器）、Linux host、Linux docker、
    Darwin Home Manager 配置。
  - `darwinConfigurations`：macOS 默认系统配置。
  - `apps.<darwin-system>.darwin-rebuild`：供 `init.sh` 通过 flake app 调用。

`home.nix`

- 不直接读取环境变量。用户名和 home 目录必须由 `flake.nix` 通过
  `extraSpecialArgs` 传入。
- 校验 `home.homeDirectory` 必须是绝对路径。
- 分层选择逻辑：
  - 总是导入 `modules/common.nix`。
  - `isHost && !isDocker` 时导入 `modules/host.nix`（容器保持精简，`isDocker`
    强制关闭 host 层）。
  - host 层（macOS 与 Linux host）共同导入 `modules/herdr-launchers.nix`，
    五个 herdr popup launcher 链接只有这一个来源。
  - Linux：`isDocker` 时导入 `modules/linux-docker.nix`，否则
    `modules/linux.nix`。
  - Darwin 导入 `modules/darwin.nix`。

`modules/common.nix`

- 管理通用 CLI 包：`git`、`lazygit`、`tmux`、`curl`、`wget`、`lua`、`gdb`、
  `nixfmt-classic`、`clang-tools`、`fzf`、`ripgrep`、`tree-sitter`、
  `vim-language-server`、`universal-ctags`（部分取自 `pkgsUnstable`）。
- 管理 Zsh、Bash、Neovim、tmux 和通用 session variables。
- `shellProfileInit` 同时服务于 zsh 和 bash：
  - source Nix daemon 或 single-user profile；
  - 加入 `/run/current-system/sw/bin`、`/etc/profiles/per-user/$USER/bin`、
    `$HOME/.nix-profile/bin`；
  - macOS 加入 `/opt/homebrew/*` 和 `/usr/local/*`；
  - source `hm-session-vars.sh` 时临时关闭 `nounset`。
- zsh 内含 lazy NVM、TERM fallback、natural text editing bindkey、
  `hm-update` / `hm-upgrade` alias，并 source 仓库外的 `local.zsh`（git 忽略，
  放机器本地私有别名/token）。
- Bash completion 故意关闭，兼容 macOS `/bin/bash` 3.2。

`modules/host.nix`

- 主机级开发工具集，包含 `cmake`、`docker`、`gcc`、`jq`、`pandoc`、`poppler`、
  多个 language server（`bash`、`lua`、`yaml`、`ltex`、`vscode-langservers` 等）、
  `pythonEnv`（`python3.withPackages`：`jedi-language-server`、`pip`、`pynvim`、
  `ruff`）、`shfmt`、`stylua`、`gh`、`go`、`tree-sitter`、`ty` 等。
- macOS host 额外加 `colima`、`rar`、`sketchybar`、`terminal-notifier`、
  `yabai`、`macism`。
- 不要把特别巨大的包无脑塞进默认 host 集合；现有测试明确防止
  `texliveFull` 进入这里。

`modules/darwin.nix`

- Home Manager 的 macOS 用户层配置：
  - 链接 `skhd`、`karabiner`、`kitty`、`zed`、`neovide` 配置；
  - 启用 `services.skhd`，配置来自 `config/skhd/skhdrc`；
  - 创建 `~/Library/Logs/skhd` 和 `~/Pictures/Screenshots`；
  - 激活前把 `zed/settings.json` 从 symlink 复制成可写文件，并清理旧的
    symlink / git 版 kitty 配置目录；
  - 激活后 source HM session vars、补 PATH，并执行 Nix store 中的
    `install-macos.sh`。

`modules/linux.nix`

- Linux 桌面/服务器层。激活后执行 Nix store 中的 `install-linux-server.sh`
  （联网 clone dot-nvim、初始化 Neovim），随后在 emacs 可用时执行
  `install-doom.sh` 引导 Doom Emacs（细节见 §5）。

`modules/linux-docker.nix`

- Linux 容器/Docker 层。只导入 `modules/common.nix` 的共享配置，**不**运行
  `install-linux-server.sh`，激活期不联网，适合无头、可丢弃的镜像；`isDocker`
  也强制关闭 `modules/host.nix`。

## 4. macOS 系统层：nix-darwin

`nix-darwin/window-manager.nix`（OmniWM 是唯一受管窗口管理器）

- OmniWM 是 Apple Silicon（macOS 26+）唯一的受管 WM；旧 AeroSpace +
  workspace 指示器 + JankyBorders 组合已停用并整体归档到
  `deprecated/00-aerospace-indicator/`（含 nix 胶水冻结快照与手动恢复说明），
  不参与求值/激活/测试。
- OmniWM stable cask 在 `homebrew.nix` 无条件声明；旧 cask/formula 不自动
  卸载（brew `cleanup = "none"`），留在磁盘以便手动回滚。
- 用户激活时 preActivation 运行 `config/omniwm/stop-aerospace.sh`，先卸载旧
  AeroSpace/indicator/borders LaunchAgents，再仅对当前用户残留进程发
  SIGTERM（拒绝 force-kill）。求值/测试不影响桌面。
- OmniWM 不设自动启动 agent，首次启动、授权、显示器路由由用户操作。
  设置由 OmniWM 首次生成并保持可写，nix 不软链、不整文件覆盖。
- 机器无关的固化键位由 `config/omniwm/apply-hotkey-overrides.sh` 在
  postActivation 以用户身份改写进 OmniWM 自有的 settings.toml：只改固定
  action id 的 `binding`（hjkl 焦点/移动、逗号句号卷轴、`⌥R` 尺寸循环、
  `⌥⇧/` 布局切换、REV 2 起把 OmniWM 默认的 `⌃⌥F` 列扩展动作解绑——
  `ctrl+alt` 字母层归 herdr，`⌃⌥F` 是全局 goto）和固定表标量
  （`SCALAR_SPECS`，REV 3 起：`[general].systemHyperTrigger=None`、
  `[focus].moveMouseToFocusedWindow=true`、一组 `[workspaceBar]` 外观偏好；
  支持 string/bool/float，缺键在对应表段末尾补写），不碰显示器
  路由 / workspace UUID 等机器本地段。新增机器无关 GUI 偏好时加进
  `SCALAR_SPECS` 并 bump REV，不要整文件覆盖 settings.toml。脚本平台中立（禁止特权/包管理关键词，
  有测试断言），nix 模块只负责越权运行。每个 REV seed-once 并写
  `.hotkey-overrides.rev`，之后 GUI 改键不被覆盖；改固化键位要 bump REV，
  `OMNIWM_HOTKEY_FORCE=1` 强制重跑。settings.toml 尚未生成时脚本跳过。
  改键表时同步 `docs/omniwm-keybindings.md` 与测试
  `tests/omniwm_hotkey_overrides_test.sh`。
- OmniWM 强制 `spans-displays = false`（开启独立 Spaces，是该偏好的唯一
  声明处，`macos-defaults.nix` 不再设置它），改变后需注销登录。
  `/etc/dot-nix/window-manager` 固定写 `omniwm`，供 acceptance 判断。
- 上手指南见 `docs/omniwm-trial.md`（含首次启动顺序）。激活只能用户自己执行。

`nix-darwin/configuration.nix`

- 导入：
  - `app-defaults.nix`
  - `gui-apps.nix`
  - `homebrew.nix`
  - `macos-defaults.nix`
- `system.primaryUser = username`，并设置 `users.users.${username}.home = homeDir`。
- `nix.enable = false`：Determinate Nix Installer 管理 Nix daemon，nix-darwin 不接管。
- 开启 Touch ID sudo，并启用 reattach 以兼容 tmux/screen。
- 关闭系统级 zsh completion，避免和 Home Manager/oh-my-zsh 双重初始化。
- 启用 `services.openssh` 与 `networking.wakeOnLan`；`acPowerSshAvailability`
  activation 用 `pmset` 让机器接电源时保持可远程访问，并配 `acPowerCaffeinate`
  daemon (`caffeinate -s`)。
- `remoteManagementCurtainMode` activation 把 Remote Management/屏幕共享配置成
  curtain 模式并 kickstart `com.apple.screensharing`。
- 内嵌 Home Manager，`isHost = true`，所以 macOS 默认包含 host 工具集。

`nix-darwin/homebrew.nix`

- Homebrew 包、cask 和 tap 的声明位置。
- `brew/install.sh` 只负责安装 Homebrew、更新 tap、预 trust 必要 formula；
  不要在 bootstrap 脚本里新增长期 app 清单。
- preActivation 会在 `~/.cache/dot-nix/homebrew-local-tap` 生成本地 tap，
  用于 patched WhatPulse cask，并 trust `dot-nix/local`。
- GUI app cask 例如 `1password`、`chatgpt`、`claude`、`claude-code`、`codex`、
  `firefox`、`kitty`、`maccy`、`microsoft-edge`、`obsidian`、`omniwm`、
  `raycast`、`visual-studio-code`、`zed`、`zotero`，以及本地 tap 的
  Herdi/WhatPulse 系列在这里维护。停用的 AeroSpace cask 只留在
  `deprecated/00-aerospace-indicator/`，不进 tap staging 和 Brewfile；
  preActivation 会 `untap` 掉 `nikitabobko/tap` 与 `felixkratz/formulae`。
- 字体 cask（`font-sarasa-gothic`、`font-lxgw-wenkai`、
  `font-symbols-only-nerd-font`、`font-ubuntu-mono-nerd-font`、
  `font-sf-pro`）也在这里声明：GUI app（kitty、Emacs）只走 CoreText
  字体注册表，而 `gui-apps.nix` 里的 nix `nerd-fonts.*` 包装在 nix store、
  不注册给 CoreText，没有 cask 两边都看不到。**Sarasa Term SC** 是 kitty
  与 Doom 的共用字体（Iosevka Term 字形的 Latin + 思源黑体 CJK，严格
  500/1000 即天生 2:1 网格，且 UAX ambiguous 符号——箭头/制表符——保持半角
  一格；`Mono SC` 变种把这些符号画成全角，终端 UI 会错位，不要用。旧
  Iosevka NF 是 600 Latin，与 LXGW fallback 的 1000 全角不成整数比、中英
  混排错位，cask 已移除）；LXGW WenKai Mono 仅作 Doom 的**追加** CJK
  fallback。**踩坑固化（macOS GUI Emacs）**：dot-doom 的 fontset 钩子必须
  把 `symbol` charset **显式映射到 Sarasa Term SC**（再 `APPEND=t` 追加
  Apple Symbols 兜底缺字），绝不能留空——Emacs 内置 fontset 对 symbol
  charset（覆盖 `…`U+2026、`™`、`μ`、弯引号、`⋯`）有专门映射，macOS 上
  落到**比例字体 Apple Symbols**，且优先于默认 face；Emacs 按 1 格计数而
  该 face 画 1.5–2 格，which-key 每条含省略号的截断项都把后面的列顶歪。
  映射后这些字符都是 Sarasa 8px（1 格），PUA nerd 图标仍走 Symbols NF
  Mono 不受影响。CJK 四个 charset（`kana/han/cjk-misc/bopomofo`）则先写
  Sarasa 再追加 LXGW。审计方法：弹层开时遍历 buffer 行比较
  `string-pixel-width` 与 `string-width × frame-char-width`，错位行数应
  为 0。
  **Symbols Nerd Font Mono 不可省**——nerd-icons/doom-modeline
  把图标家族写死成它，在 `use-default-font-for-symbols=nil` 下不回退
  Sarasa，缺了 modeline 所有图标都显示成十六进制 tofu 方框（kitty 也会拿
  它当 PUA symbol_map 回退）。Linux host 对等字体在 `modules/host.nix`
  （`sarasa-gothic`/`nerd-fonts.symbols-only`/`lxgw-wenkai`，经
  fontconfig 生效）。
- **quarantine 解封**：Homebrew 7 已彻底移除 `--no-quarantine`（flag、
  `HOMEBREW_CASK_OPTS` 转义口和 Cask::Config 全部删除，commit
  `ba25213c81`），cask 产物一律被强制打 `com.apple.quarantine`。`claude-code`
  和 `codex` 是「已签名但未公证（notarized）的裸 CLI 二进制」，Gatekeeper
  每次 exec 都直接拒绝，且 Homebrew 的升级审批继承只覆盖 `Artifact::App`，
  所以每次 `hm-upgrade` 升级这两个 cask 都会再次坏掉。`brew/unquarantine-casks.sh`
  维护这个小白名单，在 nix-darwin postActivation（`brew bundle` 之后）和
  `init.sh --upgrade` 的 `brew bundle --upgrade` 之后各跑一次，对 Caskroom
  内产物精确 `xattr -d`。脚本幂等、永不致 activation 失败。不要恢复
  cask `args = { no_quarantine = true; }`（Homebrew 7 全新安装会直接报
  invalid option；Skim 的旧写法已因此移除）。`.app` 产物受 TCC App
  Management 保护，xattr 删除即使用户/sudo 也是 EPERM，脚本不处理它们，
  公证 app 走一次首次启动审批、Homebrew 7 会在后续升级继承该审批。
`nix-darwin/gui-apps.nix`

- 只管理适合 Nix 安装的 GUI 辅助项：`nerd-fonts.iosevka`、
  `nerd-fonts.shure-tech-mono` 和 `sketchybar-app-font`。
- 旧 AeroSpace 渲染器、workspace 指示器、borders 守护及三个 launchd agent
  已全部移走；归档目录 `deprecated/00-aerospace-indicator/` 里有冻结的
  `legacy-gui-apps.nix` 快照和恢复步骤。该模块里不允许再出现
  `launchd.user.agents.aerospace` / `bordersCli` / `renderAerospaceConfig`
  （有测试断言）。

`nix-darwin/herdr.nix` / `modules/herdr.nix`（macOS 与 Linux 共用一份激活体）

- 平台无关的激活体全部在仓库根目录的 **`install-herdr-plugins.sh`**：落
  `config/herdr/config.toml` 可写普通文件到 `~/.config/herdr/config.toml`（herdr
  自己会通过设置界面写它，不能是只读 nix store 软链；覆盖前备份/diff/留 5 份），
  随后 `herdr server reload-config` 热加载。脚本以**目标用户身份**运行，通过
  环境变量参数化：`HERDR_TEMPLATE`（必填）、`HERDR_CLI`、`HERDR_CONFIG_DIR`、
  `HERDR_PROJECTS_BIN`、`HERDR_ROADBOARD_SRC`。脚本里**禁止**出现平台专有关键词
  （`launchctl`/`chown`/`homebrew`，有测试断言）。两个 nix 模块只是薄封装：
  - `nix-darwin/herdr.nix`：postActivation 以 root 跑，用一次
    `launchctl asuser … sudo -u … --set-home env PATH=… bash <脚本>` 越权到用户，
    `HERDR_CLI` 指向 Homebrew prefix 的 herdr；
  - `modules/herdr.nix`（Home Manager，仅 Linux 且 `isHost && !isDocker`，由
    `home.nix` 在非 docker 的 host 层导入）：`home.activation.herdrPlugins`
    直接以用户身份 `bash <脚本>`，无需越权，PATH 前置 HM profile 与
    `~/.local/bin`。herdr 本体**刻意不进 nix 包**——Linux 保持官方 per-user 安装
    （与 macOS 的 Homebrew cask 对称），缺二进制时脚本只落模板、跳过插件。
  `modules/darwin.nix` 不再为 config.toml 建 `home.file` 软链。
- 键位是 nvim 习惯迁移（prefix `ctrl+b`＋ctrl+alt 直连和弦，裸 Option 归 OmniWM
  所有），速查表见 `docs/herdr-keybindings.md`，改动后同步两边。`P Space` 的
  which-key 浮层是手动安装的社区插件（`herdr plugin install
  CowboyVang/herdr-which-key`），不走 nix 管理；配置里的命令做了 launcher
  缺失兜底。
- zoetrope、herdr-projects 与 herdr-radar 插件由 `install-herdr-plugins.sh`
  pinned ref 安装（macOS/Linux 同一套）；herdr-projects 要求 server ≥ 0.9.5
  （装到运行中的旧 server 会硬失败，脚本按 `herdr status --json` 版本守卫跳过）。
  herdr-projects **永久 pin fork `PannenetsF/herdr-projects@v0.2.34-pf.5`**
  （project + threads 模型），**不要升级到上游 `eliasstravik/herdr-projects`
  1.2.x**：1.2 是另一套不兼容模型（单位是任务 `repo/123`、`data/repos.json`、
  keeper/voice 守护、`sw-coordinator-<repo>`），没有 0.2 的 thread 状态机，
  更没有 ticker 响铃——2026-10 曾切到 1.2.13，结果所有等待交互的 thread
  （ready-for-review / waiting-on-you）不再有任何通知，只能靠人肉翻 pane，
  当月即整体回退并固化本约定。0.2 模型要点：
  - 每个 project 有独立 home 目录 `~/.herdr-projects/<slug>/`（含
    PROJECT.md），单位是 thread（`t-0001`…），状态六分组：waiting-on-you /
    ready-for-review / working / landing / idle / resolved。
  - **常驻 ticker 是唯一响铃源**：thread 进入 waiting-on-you /
    ready-for-review 时 ticker 调
    `herdr notification show --sound request/done`。ticker 按 root flock
    防双开；数据根可用 `--root` 指定（2026-10 回退迁移期数据在
    `~/.herdr-projects-legacy`，迁移后换回 `~/.herdr-projects`）。
    **failed launch 也算 waiting-on-you**（pf.3）：launch 放弃（超时 /
    3 次失败 / profile 被拒）时 ticker 立即落 `last_group=waiting-on-you`
    并发恰好一次 transition 响铃；否则 failed thread 离开扫描后角标永远停在
    旧分组（曾出现角标 14、实际 15 need you 的错位）。
  - **sidebar 受众契约**（pf.4）：每个 pane 都被 ticker 打 `hp_role`
    （coordinator/thread/guest/other）与 `hp_audience`
    （human/internal/stalled）；默认 agents view 用
    `not(in hp_role [guest,other])` 过滤把无关注定 pane（同 project 目录里
    未注册的第二个 harness、与 project 无关的 pane）藏掉，radar pf.2 镜像
    同一 filter/sort。blocked 超过 `HERDR_PROJECTS_STALL_UPGRADE_SECS` 的
    thread 升级 stalled。两个闪烁修复：单个 thread 的 pass 出错不再驱逐该
    project 的 layout Part（曾导致 coordinator 一 tick 被盖成 other 而被
    filter 藏掉）；无 project pane 的 key 从序号 `~!0003` 改成稳定的
    `~!<pane_id>`（snapshot 顺序变化不再每 tick 重写 token）。
  - 注册身份是 `hpc-<slug>` / `hpc-<slug>-N` coordinator agent；fork 特性：
    `coordinator adopt` 接管手开 session、context 注册门、thread-sticky
    nudge、tracked project 目录里第二个 harness 的 untracked-pane claim。
  - pf.5 caller 身份不再信任 agent 自己可改写的 HERDR_ENV 标记/环境变量
    socket：用进程族谱+进程组 ps 事实对照**可信 herdr 二进制**（固定绝对
    路径 canonicalize + 版本探测，绝不走 PATH/HERDR_BIN_PATH，并 scrub
    DYLD_*/LD_*/BASH_ENV 等）只问询 real-home registry 里在跑的会话；
    任何进程事实上在 herdr pane 内、却无注册 agent 行的调用一律 fail-closed
    为 Unverified（agent 用 `pane run`/`send-text` 在 shell tab 里剥掉
    HERDR_ENV 也无法冒充人；连 proven pane 上无名/自定义名的 agent 行也
    一律 fail-closed，coordinator 用 `agent prompt` 驱动这种 tab 同样
    拿不到人的权限）。残留边界：同 uid 起真 herdr rogue session、用服务端
    `agent rename` 自封 hpc 名、完全 double-fork 的孤儿，client 无法判别。
  - 安装顺序固定为 radar install → radar `configure` → `state-start` →
    projects（门 ≥0.9.5）→ web-ui → portal → push。projects 的 `configure`
    把全局 agents 分组行、tab-bar 项和 **`P a` overview popup** 合并进 radar
    拥有的 marker-fenced 可写配置，所以必须 radar 先 configure、projects 后
    configure；模板里**不发** `P a` 键位（configure 下发）。
  - fork 没有 release 资产，`plugin install` 走本机 cargo 构建，因此
    `nix-darwin/herdr.nix` 与 `modules/herdr.nix` 的激活 PATH 都前置
    `~/.cargo/bin`。configure 优先 `$hp_bin configure`
    （`HERDR_PROJECTS_BIN` 默认 `~/.local/bin/herdr-projects`），首装链接
    悬空时回退 `herdr plugin action invoke configure --plugin herdr-projects`。
  - 一次性回退窗口：检测到 `eliasstravik/herdr-projects@` 已注册时，脚本先
    `plugin uninstall herdr-projects`，再以平台中立 argv 正则
    `herdr-projects-[a-z0-9._-]+ (keeper|keeper-work|voice helper|serve)`
    `pkill -TERM` 收掉 1.2 的四个孤儿守护（该正则实测不命中 0.2 ticker 的
    `herdr-projects --root … ticker run`，也不命中项目内 watcher 脚本），
    然后才装 0.2 fork。**禁止**把这段回退逻辑删掉。
  `P S-c`（new-project）：fzf 扫
  `HP_PROJECT_ROOTS`（默认冒号分隔 `~/Documents:~/.config`，深度 4 层，含
  worktree）下的 git 仓库新建 project（`project new` + `open --tab`）；
  `P S-a`（add-repo）向已有 project 幂等附加仓库（容忍 already listed）。
  `P C-p`（pick-project）选择并打开 project；`P C-n`（new-coordinator）为
  当前 project 再起一个 coordinator，未注册的根 pane 当场 `coordinator adopt`
  而不是开重复会话；`P C-f`（focus-coordinator）只聚焦不自启（读
  `.state/coordinator.json` pane，再退 `hpc-<slug>` 名字族在线成员，截断
  规则镜像 Rust names.rs：24/22 字符 + `-2/-3` 后缀，判定只在
  `herdr-popup-lib.sh` 实现一次）。仓库解析统一 cwd → 底层 pane cwd → fzf。
  五个 popup launcher（new-project/pick-project/add-repo/new-coordinator/
  focus-coordinator）只有 `modules/herdr-launchers.nix` 这一个来源，新增第六个只改这里：
  config.toml 的键位无条件下发，任何 host 层漏链都会让
  `P C-p` 等静默失败（Linux host 上曾因此静默失败）。
  `herdr_projects_bin()`（`config/herdr/herdr-popup-lib.sh`）的查找顺序：
  `$HERDR_PROJECTS_BIN`（可执行时）→ `~/.local/bin/herdr-projects` → PATH；
  e2e 测试自身的发现顺序另覆盖
  `plugins/github/herdr-projects-*/target/release/` 与
  `plugins/github-installations/herdr-projects-*/*/checkout/target/release/`
  两处 cargo 构建产物，且只接受 `--version` 报 `herdr-projects 0.2.*` 的
  二进制（1.2 二进制显式排除）。
- herdr-radar（pinned fork `v1.4.9-pf.2`，PannenetsF/herdr-radar，基于上游
  hhdebb/herdr-radar v1.4.9）是首个 Node
  插件：运行时 `node` 由 `modules/host.nix` 的 `nodejs_22` 提供，所以 Linux 侧
  herdr 激活也 gate 在 host 层（zoetrope/herdr-projects 是 Rust 单文件二进制，
  不需要解释器）。macOS postActivation 经 sudo 跑整个脚本，`env_reset` 的
  secure_path 不含 HM profile 目录，所以 darwin 封装必须用 `env PATH=…` 把
  `/etc/profiles/per-user/$user/bin` 等重新前置（否则插件 build hook 报
  `failed to start: No such file or directory`）；Linux HM 激活本就有 profile PATH。
  它自管 config.toml 尾部三块 marker-fenced 配置（tab-bar 命令、`[ui.sidebar.*]`、
  `[theme.custom]`）和 `~/Library/Fonts` 图标字体；模板每次激活都会覆盖
  config.toml，所以脚本在落模板后调一次
  `plugin action invoke configure --plugin hhdebb.herdr-radar` 修复三块，并
  调 `state-start` 立即拉起状态 glyph 守护（startup hook 只在 server 启动时
  跑）。两个不可回退的集成约定：
  1. kitty 的 codepoint map 必须预置在 `config/kitty/kitty.conf`（字节与
     插件 setup 生成的块一致），否则插件安装 build hook 在首次激活时写只读
     HM nix-store 软链会 `EACCES` 硬失败（其 setup.js 不捕获该错误）；
  2. 模板把 `[theme]` 的 `light_name`/`dark_name` 都钉成 `"terminal"`，
     让插件的 macOS 深浅色跟随只切换它自己的侧边栏调色板，不把
     `name = "terminal"`（terminal 跟随 kitty 主题）改写成 catppuccin。
  键位：上游建议的 `P a` 被 Projects 占用、裸 `P r` 是 resize 模式，
  故 view-flip 用 `P C-r`、settings 用 `P ,`，速查表同步
  `docs/herdr-keybindings.md`。
  共存：herdr-projects 0.2.x 的 configure 安装全局 agents 分组视图
  （waiting-on-you/ready-for-review/…），它把这些行合并进 radar 的
  marker-fenced 侧边栏块，所以两个 configure 有严格顺序（radar 先、
  projects 后），见上条。pf.2 起还有**单一全局 view 共存**：Herdr 只保存
  一个内存中的 agents view、没有读回 API，而 radar 守护每 15s 重放自己的
  view（upstream #49 的 reassert/keeper）；projects 在时 radar 直接安装
  projects 的规格（同一 hp_role 隐藏 filter、hp_group/hp_rank 排序），谁后
  写面板都一样。侧边栏 header 由 radar 按 hp_group 的 slug 每 project 钉
  一个（显示名读 `~/.herdr-projects/<slug>/PROJECT.md` 的
  `name = "..."`），因为每个 thread 住在独立 worktree workspace，按
  workspace/repo 分组会把 thread 拆散、把 repo 名错当组名。projects 探测
  fail-sticky：`plugin list` spawn 失败时保持上次答案、5s 后重试，绝不因
  一次抖动刷回无 filter 的 view。

- herdr-web-ui（pinned `v0.4.11`，devswha/herdr-web-ui）是 Bun 插件：浏览器/PWA
  客户端，经 herdr socket API 呈现 workspace/tab/pane、聊天和实时终端，默认只监听
  `127.0.0.1:7317`（loopback；手机访问需用户自己加 Tailscale 并跑插件的
  `tailscale serve`，仓库不配置）。Bun 运行时是 `modules/host.nix` 的 `bun`
  （需 ≥1.4，node 22 已由 radar 引入）；激活安装后显式 invoke 一次
  `start` action，不必重启 herdr 即拉起 bridge。
- herdr-portal（pinned fork tag `v1.3.0-pf.4`，PannenetsF/herdr-portal，
  基于上游 loofare/herdr-portal 未打 tag 的 1.3.0 release commit `ba47b65`）
  是纯 Python stdlib（curses）看板插件，把全部 workspace/tab/pane 的 agent
  按 blocked/working/idle/done/unknown 聚合成一个 board，数据经 herdr 自身
  CLI/JSON 采集，无 node/uv 依赖、无 startup hook。上游 1.3.0 重写状态系统，
  `agent_status=unknown`（agent 进程已识别但生命周期状态尚未上报，一个 tab
  里多个 agent 刚启动时常见）有了状态标签、计数和 Spaces 视图，但
  collect() 的 columns 只建 blocked/working/settled/window 四个桶、TUI/web
  主看板只读这四个桶，这类卡仍会从主看板消失，空闲回收也把它们当候选。
  fork 三个补丁：pf.1 把 unknown 卡并入「执行中」列（保留「未知」标签和
  unknown 计数），并在回收判定里保护 unknown；**pf.2 新增最左「待处理」
  （attention）列**，数据直接来自 herdr-projects 0.2 fork 的 thread 状态——
  portal 调 0.2 二进制
  `--root <root> thread list <slug> --json`（root 自动发现：
  `~/.herdr-projects`，回退 `~/.herdr-projects-legacy`；二进制只接受
  `--version` 报 `herdr-projects 0.2.*` 者，1.2 显式忽略），waiting-on-you /
  ready-for-review 的 thread：pane 还活着就标注并挪进 attention 列，pane
  已死则生成虚拟卡（`kind="legacy"`、`pane_id="legacy:<slug>:<id>"`），
  回车触发 `thread restart` 再跳新 pane（web 走 `/api/legacy-restart`）。
  这一列让 ticker 响铃后要处理的 session 在看板第一眼可见，是回退 1.2 的
  直接原因，不要删；虚拟卡在 cleanup 回收里受保护。
  **pf.3 修死卡回车「跳转失败」**：`thread restart` 返回新 pane id 时
  pane 已建但 agent 尚未注册，立刻 `agent focus` 必报
  `agent target <id> not found`；`focus_target` 的 legacy 分支改走
  `_agent_focus_when_ready()`，10s 内每 0.4s 重试、只对 not-found 重试。
  **pf.4 把看板变成真正的通知中心**：attention 列加 per-pane seen store
  （`~/.local/state/herdr-portal/seen.json`，键为 focus 时的
  state_change_seq），卡片被看过后离开 attention、下次状态变化才再进；
  `hp_audience=internal` 的 coordinator 内部确认点永不进 attention，
  stalled（blocked >10min，`hp_audience=stalled`）仍进；保存的 SSH 机器
  聚合成带 `[machine]` 标签的卡，离线快照 + `(machine,pane)` 复合 uid，
  boe-fyq 等远端 pane 不再与本机串位。
  `P S-o` 打开 TUI overlay（活卡回车跳 pane、legacy 卡回车 restart），
  `P C-o` 起 stdlib HTTP daemon（`127.0.0.1:8787`）开 web 大屏
  （web 端可回活 agent 消息，legacy 卡只 restart）；1.3.0 的 daemon 仍是纯
  stdlib，但 `/api/*`
  加了本机 token 鉴权（token 自动生成于
  `~/.local/state/herdr-portal/token`，open-web 动作经 URL 一次性带入）与
  Host/Origin 校验（挡 DNS rebinding）。键位在 `config/herdr/config.toml`
  的 o 命名空间（上游建议的 `P a` 属于 Projects）；激活只 pin 安装，不自动
  开看板。速查表见 `docs/herdr-keybindings.md`。
- herdr-push（pinned HEAD `f4fdb06`，dcolinmorgan/herdr-push）是纯 shell+curl
  事件插件，把 `pane.agent_status_changed` POST 给 herdr-remote relay。它由共享脚本
  内的 `HERDR_PUSH_RELAY_URL` 门控：仅 nix-darwin 封装传
  `http://127.0.0.1:8375`（relay 是 macOS launchd 服务），Linux 封装不传即整块
  跳过。relay URL seed 一次到插件 config 目录的 `.env`（0600），已有文件绝不覆盖
  （换隧道 URL 是用户本地编辑）。
- herdr-unread-jump（pinned commit `be4cd1f`，to4iki/herdr-unread-jump，上游无
  release tag）是纯 bash+jq 动作插件（jq 在 `modules/host.nix` 的 host 集合）：
  herdr 应用内 toast 的显示时长硬编码（needs-attention 8s / finished 5s），
  0.9.5 与上游 master 都没有 sticky/persistent 配置项（`delay_seconds` 只是发出前
  防抖，不是驻留时长；上游诉求见 discussion #1379/#2565，未实现）。toast 飘走后
  用 `P u`（`to4iki.unread-jump.next`）循环跳到下一个仍需处理的 pane——blocked
  优先、done 次之，组内循环。插件 min herdr 0.7.5，与 zoetrope 一样在共享脚本的
  服务器版本门之外无条件安装。

`nix-darwin/herdr-remote.nix` / `config/homebrew/Casks/herdi.rb`（herdr-remote 套件：relay / Telegram bot / Herdi.app，事件源 herdr-push 见 install-herdr-plugins.sh）

- **relay 守护**：`nix-darwin/herdr-remote.nix` 用 `fetchFromGitHub` 固定
  dcolinmorgan/herdr-remote `v0.8.1`，以 `uv run --script`（PEP 723 内联依赖，
  nixpkgs 的 uv/python3，首次启动联网装 uv cache）跑 `relay/herdr_relay.py`，
  注册为 `launchd.user.agents.herdrRemote`（label
  `org.nix-community.home.herdr-remote`，日志 `~/Library/Logs/herdr-remote`，
  postActivation kickstart）。默认 `127.0.0.1:8375` loopback；机器本地覆盖放
  `~/.config/herdr-remote/config.env`（不进 git，activation 只 `install -d`
  保目录）：`HERDR_RELAY_HOST` 绑非环回时上游强制要求 `HERDR_RELAY_TOKEN`。
  wrapper 的 PATH 用 `config.homebrew.brewPrefix`（该值已含 `/bin`，不要再拼
  `/bin`），让 relay 能轮询本机 brew 版 `herdr`。两个 wrapper source
  config/secrets 都必须 `set -a`：plain `.` 只建 shell 变量，uv/python 子进程
  看到空环境（telegram 曾因此一直报 `Set HERDR_TG_TOKEN`）。
- **Telegram bot 守护**：同一 fetchFromGitHub source 的
  `relay/herdr_telegram.py`，第二个 `launchd.user.agents.herdrTelegram`
  （label `org.nix-community.home.herdr-telegram`，日志
  `telegram.{out,err}.log`，同样 postActivation kickstart）。它是 loopback
  relay 的纯 WebSocket **客户端**：long-poll `api.telegram.org` 收命令、推送
  blocked/done 通知，所以只需要出站 HTTPS，**无公网 IP、无端口转发、无
  cloudflared 也能工作**；国内网络若直连不到 Telegram，在 config.env 加
  `HTTPS_PROXY`（launchd 不继承 shell 代理环境）。凭据放机器本地
  `~/.config/herdr-remote/secrets.env`（0600，绝不进 git）：
  `HERDR_TG_TOKEN`（BotFather）与 `HERDR_TG_CHAT_ID`（白名单 chat，bot 忽略
  其他所有人；chat id 用 `getUpdates` 发现，私聊正数、群为负数）。**wrapper
  在 token 缺失时 `exit 0` 休眠**，配合 `KeepAlive.SuccessfulExit=false` 不会
  重启空转——未配置的机器上该 agent 是无害占位。bot 支持
  `/start /agents /read /reply /send /trust /interrupt /digest`，审批按钮
  发的是真实数字按键（`send_keys`）而非粘贴文本。
  **本地补丁**：上游 v0.8.1 的 blocked/finished 通知头只有
  `"<harness> blocked in <basename cwd>"`，herdr-projects 主机上几十个 pane
  全是 `agent=claude`、thread pane 的 cwd basename 还都是 `t-NNNN`，完全无法
  区分。`patches/herdr-remote-telegram-identity.patch`（`herdr-remote.nix`
  用 `runCommandLocal` 复制 source 后 `patch -p1`；nix store 源只读，必须
  复制成可写树）把通知头改成
  `project > pane(terminal title + pane_id) > 注册 session 名` 三段：
  project 从 `…/<slug>/threads/t-N` 与 worktree 目录名 `hp-<slug>-t-N-…`
  反推 slug（不能直接用 relay 给的 basename）；session 用 `herdr agent list`
  的 `name`（`hp-<slug>-t-N` / `hpc-<slug>`），缺失才退回 harness 名
  （claude/codex/…）。**bump `relayVersion` 后必须重新 dry-run 补丁**
  （apply 失败 nix build 直接报错），并同步本条目与
  `tests/darwin_herdr_config_test.sh`。
- **Herdi.app**：菜单栏客户端，上游只发 GitHub DMG、无 brew cask，故以 tracked
  `config/homebrew/Casks/herdi.rb` 走本地 tap（preActivation `install` 进 local
  tap，cask 清单写 `dot-nix/local/herdi`；停用的 aerospace-patched cask 曾用同一
  模式，已随整套归档到 `deprecated/00-aerospace-indicator/`）。
  该 app ad-hoc 签名且**未公证**（`spctl --assess` rejected），首次启动需右键打开；
  不进 `brew/unquarantine-casks.sh`（.app 受 TCC App Management 保护，约定见下）。

`nix-darwin/macos-defaults.nix`

- macOS 系统 defaults：键盘（含 `com.apple.keyboard.fnState` 标准功能键，另有
  `refreshFunctionKeyMode` activation 写入用户 GlobalPreferences 并 kickstart
  Karabiner agents）、Dock、Finder、Trackpad、截图目录、Control Center、
  登录窗口等。

`nix-darwin/app-defaults.nix`

- app 级 defaults：Raycast、Maccy、Snipaste，以及默认打开方式 `duti`。

## 5. 激活脚本与外部配置

`install-common.sh`

- `install-macos.sh` 与 `install-linux-server.sh` 的共享库（只 source，不直接
  执行）：`sync_config_repo`、`python_tools_available`、`install_python_tools`、
  `setup_pip_extra`。调用方先设置 `INSTALL_LOG_PREFIX` 再 source 它。
- 库本身不切换 `set -e`（Linux 调用方不用，macOS 调用方自己开）。
- Nix 模块必须以 `bash ${../.}/install-macos.sh` 这种**目录形式**引用：直接写
  `${../install-macos.sh}` 会把单个文件压成扁平 store 对象，其 sibling
  `install-common.sh` 不在同一目录，source 必然失败。

`install-macos.sh`

- 薄入口：source `install-common.sh`，安全同步
  `https://github.com/PannenetsF/dot-nvim.git` 到 `$HOME/.config/nvim`
  （目标不存在就 clone；不是 git repo、dirty、staged、untracked 时跳过 pull），
  首次运行在 profile 未提供 `ruff`/`ty`/`jedi-language-server`/`pynvim` 时
  pip fallback 安装，再跑 `nvim --headless -c 'Lazy' -c 'qa'` 和 `TSUpdateSync`。
- 锁文件为 `$HOME/pf-init-macos`。
- `pip3` 不存在时 fallback 到 `python3 -m pip`；只有 pip 支持
  `--break-system-packages` 时才追加该参数。

`install-linux-server.sh`

- 薄入口：source `install-common.sh`，同样安全同步 `dot-nvim`、首次运行 pip
  fallback 并初始化 Neovim。
- 锁文件为 `$HOME/pf-init`；不使用 `set -e`（与 macOS 入口的刻意差异）。

`install-doom.sh`

- Doom Emacs 引导（macOS nix-darwin postActivation、Linux `modules/linux.nix`
  激活），emacs 二进制就绪后运行（macOS 是 Homebrew emacs-plus，Linux 是
  nixpkgs emacs-pgtk）。
- 安全同步两个仓库：`dot-doom`（`PannenetsF/dot-doom`）到
  `$HOME/.config/doom`，上游 `doomemacs/doomemacs` 到 `$HOME/.config/emacs`。
- **不**生成 doomenv（2026-10-25 起删除该步骤）：Doom v2 的
  `doom-load-envvars-file' 是 `modules/doom/compat/init.el` 里的桩函数，
  只 `read` 文件第一个 form——`doom env` 产物的首行恰好是 marker
  `(put 'process-environment 'doom t)`——然后把这个 list 本身当环境变量
  append 进 `process-environment`，真正的 `(setq ...)` 永不执行。
  `call-process` 扫到非字符串条目即停止，所有子进程退回 launchd 裸
  PATH（jka-compr 的 `zstd`/`gzip` 走 `/bin/sh -c`，报
  “command not found”，尽管会话 PATH 正确）。脚本改为
  `rm -f "$DOOM_DIR/doomenv"` 清理旧文件。GUI PATH 由 emacs-plus 的
  `EMACS_PLUS_PATH`（装瓶时烤进 Emacs.app Info.plist，site-start.el
  应用）覆盖，`-nw` 直接继承 shell PATH。
- 首次引导才跑 `doom install --doomdir … --no-env` + `doom sync --aot --rebuild`；
  锁文件 `$HOME/pf-init-doom`。`--aot` 不可省：普通 `doom sync` 只字节编译，
  ~2000 个包全靠 JIT 懒编译，首次用到时卡顿 + 后台 gcc 拖很多天；
  `--aot` 在无 NATIVE_COMP 的 emacs 上是 no-op。已引导过的旧机器补做一次
  手动全量（锁文件存在，activation 不会重跑首次引导，见下条命令）。
  **Doom v2 的 `--aot` 是增量的**：只编译本次 sync 新装/更新的包，所以对
  已装好的系统跑它 16 秒无事可做；要全量复刻旧版 AOT（如清空 eln 缓存、
  升 Emacs 大版本后）必须 `doom sync --aot --rebuild`（`-b` = 无条件重建
  全部包）。
- **`--aot --rebuild` 仍留两大运行时门类不编译**：native-comp 只编译「已加载」
  的文件，而 ① 每个 major mode（及其 `after!`/tree-sitter remap 钩子）只有
  真打开该类文件才加载，② lsp-mode 的 ~150 个 server client 只在首个真实
  LSP buffer 出现时成 bundle require。install-doom.sh 在 sync 之后用独立
  `emacs --batch -l aot-warm-modes.el`（与脚本同目录，~90s，失败不阻断）
  穷举预热这两类。**必须 `--batch`**：某些 ts-mode（如 elixir-ts-mode）缺
  语法时弹模态「install grammar?」，在 GUI 里永久阻塞（曾卡死交互 session，
  只能键盘 ESC）。脚本**零硬编码**：mode 来自 `set-auto-mode` 的同一组 alist
  （auto-mode/interpreter/magic + `major-mode-remap-defaults`）并扫到不动点，
  LSP client 来自 `lsp-client-packages`；加新 `:lang` 模块自动覆盖。batch 下
  Doom 生成的 profile init 用 `static-unless noninteractive` 跳过交互
  loaddefs，脚本逐个加载 straight build 目录里的 `*-autoloads.el`（auctex
  tex-site 在 batch 坏，单包容错）。典型结果：136 modes + 150 LSP clients +
  476 个 straight 文件，0 编译失败（唯一报错 image-mode 无显示，无害）。
  注意必须 `LSP_USE_PLISTS=1 doom sync --aot`：lsp-mode 的 JSON 访问器在
  **编译期**按该变量选 plist/gethash 分支，Doom 的 package `:env` 只覆盖
  straight 字节编译，不覆盖 native-comp worker；dot-doom config.el 另设
  `(setenv ...)` + `native-comp-async-env-modifier-form` 兜 JIT。缺了会
  出现 `.elc` 是 plist 而 `.eln` 是 hash 版的错配，flycheck 对每条诊断报
  `(wrong-type-argument hash-table-p ...)`；本机修复需停 Emacs、清空
  `~/.config/emacs/.local/cache/eln` 后重跑。
- dot-doom 的 `config.el` 不再加载 doomenv（v2 的 loader 是坏桩，见上条）。
  子进程 PATH 依赖 emacs-plus 装瓶时烤进 Info.plist 的快照；快照含
  `/opt/homebrew/bin` 整个目录，新增 Homebrew CLI 工具无需重装 emacs-plus，
  只有新增前缀路径才需 `brew reinstall emacs-plus` 刷新快照。
- 字体跨仓库约定：kitty `config/kitty/kitty.conf` 用 `Sarasa Term SC`
  16.0，dot-doom `config.el` 的 `doom-font` 同样是 CoreText 名
  `Sarasa Term SC` 16（同一家族，改字体两边一起改）；它自带严格 2:1 的
  CJK（500/1000）。钩子逻辑：CJK 四 charset（`kana/han/cjk-misc/bopomofo`）
  先显式写 Sarasa 再 `APPEND=t` 追加 LXGW；`symbol` charset **必须显式映射
  到 Sarasa**（留空时 macOS 内置 fontset 会落到比例字体 Apple Symbols，
  `…/™/μ` 按 1 格计数却画 1.5–2 格，顶歪 which-key，细节见 §4），再
  `APPEND=t` 追加 Apple Symbols 作缺字兜底。字体必须以 Homebrew
  cask 安装（见 §4 homebrew.nix）。
- `-nw` 终端下 Doom 跟随终端调色板（与 herdr `name = "terminal"` 同一思路，
  逻辑在 dot-doom `config.el`，nix-hm 无配置项）：通过 kitty remote control
  （`kitty @ get-colors`，socket 探测顺序镜像 `config/kitty/kitty-theme.sh`：
  `KITTY_LISTEN_ON` 先、`/tmp/kitty-<pid>` 按 mtime 新→旧）读实时背景色，按
  相对亮度选 `doom-ayu-dark`/`doom-ayu-light`；兜底 `COLORFGBG`、再兜底 macOS
  `AppleInterfaceStyle`。启动时选定，`focus-in-hook`（kitty 支持 tty focus
  事件）带 2s 节流在重新聚焦时切换；手动 `M-x +terminal-sync-theme`。
  GUI frame 不走这套，固定 `doom-ayu-dark`。
- dot-doom 是独立 git 仓库（`~/.config/doom`）；升级 Doom 大版本后留意被移除的
  module flag（如 `+pomodoro`/`+hugo` 在 25.04 删除，包要在 dot-doom
  `packages.el` 显式声明），且不要再引入 doomenv（v2 loader 坏桩，见上）。
- vulpea 文件监听依赖 `fswatch`（homebrew.nix brews 声明），缺了它每次启动
  提示 “fswatch not found, using polling”。
- Doom `(:checkers spell +flyspell)` 在 macOS 用 Homebrew `aspell`：从
  LaunchServices 启动的 Emacs.app 不继承 Home Manager profile，只稳定看到
  `/opt/homebrew/bin`。
- telega 已无 Doom 内置 module，dot-doom 用普通 `package! telega` 管理；
  Homebrew 提供 `tdlib`（**必须从 HEAD 安装**：homebrew-core stable 冻结在
  2022 的 1.8.0 tag，tdlib 此后再没发过 release tag，而 telega master 跟踪
  tdlib master、要求 ≥1.8.66；升级走 `brew upgrade --fetch-HEAD tdlib`）。
  preActivation 一次性卸载版本号形如 `tdlib 1.8.0` 的 stable 安装，否则
  `brew bundle` 会把任何已装 tdlib 视为满足、永不切换 spec。dot-doom 在
  `telega` 命令的 before advice 里按需构建 `telega-server`：二进制缺失
  **或无法启动**（健康检查 `telega-server -h`，典型于 tdlib 升级后 dylib
  换版本）都触发重编；判断必须用 `(eq 0 (call-process …))`——进程被信号
  杀死时 `call-process` 返回字符串 `"Abort trap: 6"` 而非数字，`zerop` 会
  抛 `wrong-type-argument` 反而中断启动。注意构建产物装到
  INSTALL_PREFIX=`telega-directory`（`~/.telega`），那才是 Emacs 运行的
  二进制；straight build 目录里只是构建用副本。二维码登录依赖 Homebrew
  `qrencode`（telega 用它渲染登录二维码；缺了它 GUI 首登会退回手机号提示）。
  advice 会收到 `telega` 的
  可选 prefix 参数，函数必须声明 `&optional _arg`（或 `&rest _`），否则
  启动即 `wrong-number-of-arguments`。

注意：这些脚本在 Home Manager activation 中经模块以 `${../.}/script.sh`
目录引用进入只读 Nix store（保证与 `install-common.sh` 同目录）后执行。
脚本必须依赖运行时的 `$HOME`、`PATH` 和传入环境变量，不应假设
自己位于 git 工作树中。

`config/`

- 这是 macOS app/user 配置的源码目录：
  - `config/omniwm/stop-aerospace.sh`（激活前卸载旧 AeroSpace 栈）、
    `config/omniwm/apply-hotkey-overrides.sh`（seed-once 的 niri 风格键位 + 机器无关 GUI 偏好标量）
  - `config/skhd/skhdrc`、`config/skhd/toggle_kitty_dropdown.sh`
  - `config/karabiner/karabiner.json`
  - `config/homebrew/Casks/herdi.rb`
  - `config/kitty/*`、`config/herdr/config.toml`、`config/neovide/config.toml`、
    `config/neovide/agent-open-neovide.sh`
  - `config/zed/*`
- 已停用的 AeroSpace + workspace 指示器整套源码（含 patched cask 与冻结的 nix
  胶水快照）不在 `config/`，见 `deprecated/00-aerospace-indicator/`。
- Kitty theme 上游通过 `.gitmodules` 中的 `config/kitty/kitty-themes` submodule
  记录。不要恢复旧的 `dot-kitty` clone 流程。

## 6. 修改指南

- 新增通用 CLI 包：优先改 `modules/common.nix`。
- 新增只在完整主机环境需要的工具：改 `modules/host.nix`。
- 新增只在 Linux 桌面/服务器需要、或需要联网初始化的内容：改 `modules/linux.nix`
  或 `install-linux-server.sh`；容器层要保持精简且激活期不联网，改
  `modules/linux-docker.nix`。
- 新增 macOS GUI app/cask：改 `nix-darwin/homebrew.nix`，必要时同步
  `brew/install.sh` 里的 tap/trust bootstrap。新增的若是「未公证裸二进制」
  cask（`spctl --assess` 报 Unnotarized Developer ID），还要把 cask token
  加进 `brew/unquarantine-casks.sh` 的 `CASKS` 白名单。
- 新增 macOS 系统 defaults：改 `nix-darwin/macos-defaults.nix`。
- 修改 Doom Emacs 引导：改 `install-doom.sh`（不要生成 doomenv，v2 的
  loader 是坏桩会污染 `process-environment`，详见 §4 Doom 小节）。个人
  Doom 配置不在本仓库，在独立的 `PannenetsF/dot-doom`（`~/.config/doom`）；换编辑器字体要三处一起
  改：`config/kitty/kitty.conf`、dot-doom `config.el` 的 `doom-font`、
  homebrew.nix 的字体 cask（细节见 §5）。
- 新增 macOS app defaults 或默认打开方式：改 `nix-darwin/app-defaults.nix`。
- 新增 macOS launchd/system 管理的 GUI 工具：改 `nix-darwin/gui-apps.nix`；
  非 GUI 的后台服务（如 herdr-remote relay）建独立 `nix-darwin/<name>.nix`
  并在 `configuration.nix` imports 登记。
- 新增 pinned herdr 插件：改平台无关的 `install-herdr-plugins.sh`（pin ref +
  guard + 版本门），平台差异通过环境变量从 `nix-darwin/herdr.nix` /
  `modules/herdr.nix` 两个薄封装传入，脚本里禁止写平台名/URL 常量；新增插件
  的解释器依赖（bun/node/uv）加进 `modules/host.nix` 或对应 nix-darwin 模块。
- 新增只发 GitHub release、无 brew cask 的 macOS app：在
  `config/homebrew/Casks/` 加 tracked cask 并由 homebrew.nix preActivation
  `install` 进本地 tap（`herdi.rb` 模式）。
- 新增用户 dotfile 链接或 Home Manager service：改 `modules/darwin.nix` 或
  对应平台模块。
- 修改启动、Nix 安装、cache、git pull、激活选择逻辑：改 `init.sh`。
- 修改 Neovim/Python 初始化：优先改共享的 `install-common.sh`；入口专属
  （锁文件、`set -e`、shebang）才改 `install-macos.sh` 或
  `install-linux-server.sh`。

设计约定：

1. `home.nix` 保持纯净：不要在里面新增直接环境读取；需要的值从 `flake.nix`
   传入。
2. macOS 默认路径是 nix-darwin。只有兼容旧路径或测试时才走 `--home-manager`。
3. 用户级配置归 Home Manager；系统级 macOS 设置、Homebrew、Touch ID sudo、
   system/defaults 和需要 root/launchd 系统能力的内容归 nix-darwin。
4. activation 脚本必须可重复执行，且遇到本地用户改动要保守跳过。
5. shell startup 要兼容 zsh、bash、macOS `/bin/bash` 3.2、Nix daemon profile、
   Home Manager session vars 和 Homebrew 双架构路径。
6. `TERM` fallback 逻辑不要轻易删除；它避免没有 kitty terminfo 的环境启动报错。
7. `.config/kitty` 由本仓库管理；activation 里只做清理和链接，不再 clone 外部
   kitty 配置仓库。
8. OmniWM 是唯一受管 WM。改 `nix-darwin/window-manager.nix` 与
   `config/omniwm/` 时保留这些不变量：`~/.config/omniwm/settings.toml` 是机器本地
   可写文件（不进 git、不做软链），固化键位与机器无关 GUI 偏好只能经
   `apply-hotkey-overrides.sh` 按 rev stamp「seed 一次」下发，脚本必须平台无关、
   幂等、检出绑定冲突时回滚；旧 AeroSpace 栈的卸载在 preActivation 完成
   （`stop-aerospace.sh`）。归档在 `deprecated/00-aerospace-indicator/` 的文件只作
   手动恢复参考，不要重新接回任何激活路径。
9. `docs/superpowers/specs/2026-03-27-nix-macos-home-manager-design.md` 是历史设计，
   其中“不引入 nix-darwin”的约束已经过时，只能作为演进背景参考。

## 7. 测试与验证

测试主要是 shell 脚本，分为静态断言、stubbed `init.sh` 行为测试、Nix eval 测试和
真实 macOS 验收。

常用测试：

- 启动流程：`bash tests/init_activation_command_test.sh`
- Nix 安装/sudo：`bash tests/init_nix_install_sudo_test.sh`
- pull 后重启：`bash tests/init_reexec_after_pull_test.sh`
- 用户/home 推导：`bash tests/home_identity_eval_test.sh`
- Linux 容器分层：`bash tests/linux_docker_layer_test.sh`
- host 包集合：`bash tests/host_packages_test.sh`
- herdr 跨平台插件激活（共享脚本 stub 行为）：
  `bash tests/herdr_plugins_activation_test.sh`
  （配套 `darwin_herdr_config_test.sh` 校验 macOS/Linux 两个薄封装与脚本的
  平台无关性：脚本里不得出现 launchctl/chown/homebrew；两个测试也覆盖
  herdr-projects fork pin v0.2.34-pf.5 + 0.9.5 版本门（configure 在 radar
  configure 之后）、检测到 1.2.x 已装时先 uninstall 再 pkill 四类孤儿
  守护（keeper/keeper-work/voice helper/serve，正则不命中 ticker）的回退
  case、configure action 回退、
  五个 popup launcher 的单一来源模块、`P a`（configure 合并，不在模板）、
  `P C-f` coordinator.json 聚焦/hpc- 名字族 adopt 回退、
  web-ui v0.4.11、herdr-portal fork tag pin v1.3.0-pf.4（unknown 卡并入执行中列 + attention 列读 0.2 thread 状态 + pf.3 restart 后重试 focus + pf.4 seen-gate/internal 过滤/SSH 机器聚合，只安装、不自动 invoke）、
  radar fork pin v1.4.9-pf.2（hp_role filter/hp_group 排序镜像 projects）、
  herdr-push pin + .env seed-once、relay launchd 模块和
  Herdi 本地 tap cask）；真实激活后的 relay/web-ui HTTP、launchd、插件和
  cask 验收在 `macos_acceptance.sh`（静态断言在
  `macos_acceptance_script_test.sh`）。
- herdr project/coordinator 选择器 e2e（真实 herdr-projects **0.2.x**
  二进制——只接受 `--version` 报 0.2.* 者，发现路径含 github/ 与
  github-installations/ 两处 cargo target/release——+
  stub fzf/herdr（BASH_ENV 函数只能用 return，不能用 exit，否则带临时
  环境变量前缀的调用会 127）+ stub coordinator，全程跑在 mktemp 里）：
  `bash tests/herdr_pickers_e2e_test.sh`
- shell startup：`bash tests/zsh_startup_test.sh`、`bash tests/bash_profile_env_test.sh`
- Claude Code 信任框 shim（stub claude/jq、pty 下跑真 shim；覆盖普通目录/git
  仓库/linked worktree（macOS `/var`→`/private/var` 物理路径）、幂等保数据、
  坏 JSON 不阻启动、非 tty 跳过、python3 fallback、真二进制缺失 127）：
  `bash tests/claude_shim_test.sh`
- Homebrew/GUI：`bash tests/brew_gui_apps_test.sh`、
  `bash tests/brew_install_bootstrap_test.sh`
- OmniWM（受管窗口管理器）：`bash tests/omniwm_eval_test.sh`（darwin 配置求值，
  不激活）、`bash tests/omniwm_trial_test.sh`（`stop-aerospace.sh` 清理脚本，桌面
  命令全部 stub）、
  `bash tests/omniwm_hotkey_overrides_test.sh`（固化键位 seed/幂等/冲突回滚）
- cask quarantine 解封：`bash tests/unquarantine_casks_test.sh`（配套
  `init_brew_upgrade_test.sh` 验证 `hm-upgrade` 在 bundle 之后调用脚本）
- macOS defaults / Touch ID：`bash tests/darwin_defaults_test.sh`、
  `bash tests/darwin_touchid_sudo_test.sh`
- macOS 用户环境 / 激活 PATH：`bash tests/darwin_user_env_test.sh`、
  `bash tests/darwin_activation_nvim_path_test.sh`
- app config sync：`bash tests/darwin_app_config_sync_test.sh`
- Neovide agent 打开脚本：`bash tests/neovide_agent_open_test.sh`
- Doom Emacs 引导（禁止 `doom env` 污染 process-environment、kitty/Doom 共用字体 cask）：
  `bash tests/doom_bootstrap_test.sh`
- Kitty：`bash tests/kitty_config_test.sh`
- Python 工具 profile / pip 兼容：`bash tests/install_python_tools_profile_test.sh`、
  `bash tests/install_macos_pip_options_test.sh`
- 配置仓库安全 pull（install 脚本里 dot-nvim 的 pull 行为）：
  `bash tests/config_repo_pull_test.sh`
- 真实 macOS 激活后验收：`bash tests/macos_acceptance.sh`
  （配套 `macos_acceptance_script_test.sh` 静态断言验收脚本本身的检查项）

改动后优先跑与变更相关的测试。涉及 flake、home/darwin module 或 shell startup
时，至少跑对应的 `nix eval` 测试；涉及 `init.sh` 时跑 `init_*` 测试；涉及
OmniWM / `window-manager.nix` / 键位脚本时跑 `omniwm_eval_test.sh`、
`omniwm_trial_test.sh`、`omniwm_hotkey_overrides_test.sh`；涉及 macOS
GUI/Homebrew/defaults 时跑 `brew_*`、`darwin_*` 和必要的 acceptance。无 root 时可用 `nix eval .#...drvPath` / `nix build` 校验配置是否
可求值/可构建，而不必真正 activate。

Nix 文件格式保持 `nixfmt-classic` 风格；shell 脚本保持 Bash 语义，测试中大量使用
stub 命令，请避免引入难以 stub 的外部副作用。

## 8. 可移植性与仓库卫生硬性约定

下列原则是踩坑后固化的规则，改动相关区域时不要回退：

1. **tracked 模板必须机器无关**：不允许出现公司内网主机名/代理（如
   `*.byted.org`、`galaxy-*`、`/data00/<工号>`）、具体用户名路径
   （`/Users/<name>`、`/etc/profiles/per-user/<name>`）、个人会话/项目布局。
   机器本地内容走 gitignore 覆盖层（`local.zsh` 模式）或「HM 只 seed 一次、
   之后可写」的文件（zed settings 模式）；从 HM 链接撤下用户文件时，
   activation 要负责把旧软链物化成普通文件（见 saved-session 迁移）。
2. **路径一律推导**：`$HOME`、`$USER`、`$(id -un)`，禁止写死
   `/Users/bytedance`；测试 fixture 除外。
3. **双架构 Mac**：Homebrew 路径同时处理 `/opt/homebrew` 与 `/usr/local`
   （`[ -d ]` 守卫或双前缀探测，Swift/Python/shell 三处行为要一致）；
   cask 下载 URL 按 `uname -m` 分流，不得把 arm 产物发给 Intel。
4. **跨平台模板只用两平台共有的特性**：config.toml 等 macOS/Linux 都下发的
   文件不得依赖 macOS 专属后端（toast 用 `delivery = "herdr"`，不用仅 macOS
   的 `system`）。确实需要平台分叉时拆模板或按层导入。
5. **单一来源，禁止镜像复制**：跨模块共用的 home.file 放进共享模块
   （`modules/herdr-launchers.nix`）；多个脚本共用的前言/函数进共享库
   （`config/herdr/herdr-popup-lib.sh`、`install-common.sh`）。新增第六个
   launcher 只改共享模块，不在 darwin/linux 两边各抄一份。
6. **需要 sibling 文件的 Nix 脚本引用走目录形式** `bash ${../.}/script.sh`；
   直接 `${../script.sh}` 会把单文件压成扁平 store 对象，旁边的共享库不在
   同目录，source 必失败。
7. **activation 脚本可重复执行、无调试残留**：不加锁地 `pwd`/`env|grep`/
   `echo hello` 之类禁止留在正式路径；一次性锁文件用 `touch`；信息输出带
   脚本前缀。脚本只依赖运行时 `$HOME`/`PATH`/环境变量，不假设位于 git 工作树。
8. **文档与代码同步变更**：pin 版本（herdr 插件、installer tag）、默认值
   （`HP_PROJECT_ROOTS`、substituter）、插件安装位置（共享脚本 + 两个薄封装）、
   `config/` 文件清单与 §7 测试清单，随代码一起改；通用文档里不写具体机器名。
9. **测试不得静默假装通过**：找不到真实依赖时要列出尝试过的路径再 skip；
   实现搬移到共享库时，静态断言的目标文件一起搬，意图不变。
10. **删除文件要删干净**：module 链接、测试断言、acceptance 检查、AGENTS/docs
    引用一并删除（open_iterm2.sh 为鉴）；删除前先全仓 grep 引用。
