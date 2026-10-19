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
    四个 herdr popup launcher 链接只有这一个来源。
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
  `⌥⇧/` 布局切换）和 `[general].systemHyperTrigger = "None"`，不碰显示器
  路由 / workspace UUID 等机器本地段。脚本平台中立（禁止特权/包管理关键词，
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
- 字体 cask（`font-iosevka-nerd-font`、`font-lxgw-wenkai`、
  `font-ubuntu-mono-nerd-font`、`font-sf-pro`）也在这里声明：GUI app
  （kitty、Emacs）只走 CoreText 字体注册表，而 `gui-apps.nix` 里的 nix
  `nerd-fonts.*` 包装在 nix store、不注册给 CoreText，没有 cask 两边都看不到。
  Iosevka NF 是 kitty 与 Doom 的共用字体，LXGW WenKai Mono 是 Doom 的 CJK
  fallback（详见 §5 `install-doom.sh`）。
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
  pinned ref 安装（macOS/Linux 同一套）；herdr-projects 要求 server ≥ 0.9.1
  （装到运行中的旧 server 会硬失败，脚本按 `herdr status --json` 版本守卫跳过）。
  herdr-projects 的 sidebar/`P a`/tab 栏块不进模板：激活落模板后跑
  `herdr-projects configure`，由插件自己写 live config（journal 校验）。
  `P S-c` 的 fzf 仓库选择器是 `config/herdr/new-project.sh`，由共享模块
  `modules/herdr-launchers.nix`（每个 host 层都导入，macOS/Linux 同源）链到
  `~/.local/bin/herdr-new-project`，扫描根由
  `HP_PROJECT_ROOTS` 覆盖（默认冒号分隔的 `~/Documents:~/.config`）。`P C-p` 的项目
  选择器同理：`config/herdr/pick-project.sh` → `herdr-pick-project`（插件
  自带 open 动作在项目 workspace 内不询问直接回当前项目，所以另写脚本）。
  四个 popup launcher（new-project/pick-project/add-repo/new-coordinator）
  只有 `modules/herdr-launchers.nix` 这一个来源，新增第五个只改这里：
  config.toml 的键位无条件下发，任何 host 层漏链都会让
  `P C-p` 等静默失败（Linux host 上曾因此静默失败）。
- herdr-radar（pinned fork `v1.4.4-pf.6`，PannenetsF/herdr-radar）是首个 Node
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
  共存顺序：两个插件都写 tab-bar 和 `[ui.sidebar.agents]`；v0.2.34 的
  herdr-projects 会把自己的条目合并进 radar 的 marker 块（反过来 radar
  不认识 projects），所以 postActivation 必须 radar configure 在前、
  projects configure 在后，且共用 0.9.0 版本门。radar 深浅色切换重写
  侧边栏会临时丢掉 projects 的 `$hp_sub` 行，下次激活恢复。

- herdr-web-ui（pinned `v0.4.11`，devswha/herdr-web-ui）是 Bun 插件：浏览器/PWA
  客户端，经 herdr socket API 呈现 workspace/tab/pane、聊天和实时终端，默认只监听
  `127.0.0.1:7317`（loopback；手机访问需用户自己加 Tailscale 并跑插件的
  `tailscale serve`，仓库不配置）。Bun 运行时是 `modules/host.nix` 的 `bun`
  （需 ≥1.4，node 22 已由 radar 引入）；激活安装后显式 invoke 一次
  `start` action，不必重启 herdr 即拉起 bridge。
- herdr-portal（pinned v1.2.0 提交 `cae8ea0`，loofare/herdr-portal；上游 tag
  只到 v1.0.3，故 pin 完整 commit 同 herdr-push）是纯 Python stdlib（curses）
  看板插件，把全部 workspace/tab/pane 的 agent 按 blocked/working/idle/done
  聚合成一个 board，数据经 herdr 自身 CLI/JSON 采集，无 node/uv 依赖、无
  startup hook。`P S-o` 打开 TUI overlay（只读导航，Enter 只跳 pane），
  `P C-o` 起 stdlib HTTP daemon（`127.0.0.1:8787`）开 web 大屏（web 端可回
  agent 消息）。键位在 `config/herdr/config.toml` 的 o 命名空间（上游建议的
  `P a` 属于 Projects）；激活只 pin 安装，不自动开看板。速查表见
  `docs/herdr-keybindings.md`。
- herdr-push（pinned HEAD `f4fdb06`，dcolinmorgan/herdr-push）是纯 shell+curl
  事件插件，把 `pane.agent_status_changed` POST 给 herdr-remote relay。它由共享脚本
  内的 `HERDR_PUSH_RELAY_URL` 门控：仅 nix-darwin 封装传
  `http://127.0.0.1:8375`（relay 是 macOS launchd 服务），Linux 封装不传即整块
  跳过。relay URL seed 一次到插件 config 目录的 `.env`（0600），已有文件绝不覆盖
  （换隧道 URL 是用户本地编辑）。

`nix-darwin/herdr-remote.nix` / `config/homebrew/Casks/herdi.rb`（herdr-remote 三件套）

- **relay 守护**：`nix-darwin/herdr-remote.nix` 用 `fetchFromGitHub` 固定
  dcolinmorgan/herdr-remote `v0.8.1`，以 `uv run --script`（PEP 723 内联依赖，
  nixpkgs 的 uv/python3，首次启动联网装 uv cache）跑 `relay/herdr_relay.py`，
  注册为 `launchd.user.agents.herdrRemote`（label
  `org.nix-community.home.herdr-remote`，日志 `~/Library/Logs/herdr-remote`，
  postActivation kickstart）。默认 `127.0.0.1:8375` loopback；机器本地覆盖放
  `~/.config/herdr-remote/config.env`（不进 git，activation 只 `install -d`
  保目录）：`HERDR_RELAY_HOST` 绑非环回时上游强制要求 `HERDR_RELAY_TOKEN`。
  wrapper 的 PATH 用 `config.homebrew.brewPrefix`（该值已含 `/bin`，不要再拼
  `/bin`），让 relay 能轮询本机 brew 版 `herdr`。
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
- 每次激活都刷新 doomenv：Doom CLI v2 里 `doom env -o FILE` 已删除，输出文件
  是位置参数且**不能**加 `--` 分隔（加了会被 parser 丢掉，报
  “Output file location required”）。正确形式：
  `doom env --allow-all "$DOOM_DIR/doomenv"`。
- 首次引导才跑 `doom install --doomdir … --no-env` + `doom sync`；锁文件
  `$HOME/pf-init-doom`。
- dot-doom 的 `config.el` 直接 `(doom-load-envvars-file …/doomenv)`，缺文件会
  file-error 中断启动（v2 该函数有 `noerror` 第二参，dot-doom 已传 `t`）。
- 字体跨仓库约定：kitty `config/kitty/kitty.conf` 用 `Iosevka NF` 16.0，
  dot-doom `config.el` 的 `doom-font` 用 CoreText 名 `Iosevka Nerd Font` 16
  （同一 ttf 的 family alias，改字体两边一起改），CJK fallback 是
  `LXGW WenKai Mono`。字体必须以 Homebrew cask 安装（见 §4 homebrew.nix）。
- dot-doom 是独立 git 仓库，机器本地内容（`doomenv`）走该仓库自己的
  `.gitignore`；升级 Doom 大版本后留意被移除的 module flag（如
  `+pomodoro`/`+hugo` 在 25.04 删除，包要在 dot-doom `packages.el` 显式声明）。
- vulpea 文件监听依赖 `fswatch`（homebrew.nix brews 声明），缺了它每次启动
  提示 “fswatch not found, using polling”。

注意：这些脚本在 Home Manager activation 中经模块以 `${../.}/script.sh`
目录引用进入只读 Nix store（保证与 `install-common.sh` 同目录）后执行。
脚本必须依赖运行时的 `$HOME`、`PATH` 和传入环境变量，不应假设
自己位于 git 工作树中。

`config/`

- 这是 macOS app/user 配置的源码目录：
  - `config/omniwm/stop-aerospace.sh`（激活前卸载旧 AeroSpace 栈）、
    `config/omniwm/apply-hotkey-overrides.sh`（seed-once 的 niri 风格键位）
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
- 修改 Doom Emacs 引导：改 `install-doom.sh`（Doom CLI v2 的 `doom env`
  输出文件走位置参数，勿用 `-o` 或 `--`）。个人 Doom 配置不在本仓库，在
  独立的 `PannenetsF/dot-doom`（`~/.config/doom`）；换编辑器字体要三处一起
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
   可写文件（不进 git、不做软链），固化键位只能经
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
  web-ui v0.4.11、herdr-portal v1.2.0 commit pin（只安装、不自动 invoke）、
  herdr-push pin + .env seed-once、relay launchd 模块和
  Herdi 本地 tap cask）；真实激活后的 relay/web-ui HTTP、launchd、插件和
  cask 验收在 `macos_acceptance.sh`（静态断言在
  `macos_acceptance_script_test.sh`）。
- herdr 项目选择器 e2e（真实 herdr-projects 二进制 + stub fzf，全程跑在
  mktemp 里）：`bash tests/herdr_pickers_e2e_test.sh`
- shell startup：`bash tests/zsh_startup_test.sh`、`bash tests/bash_profile_env_test.sh`
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
- Doom Emacs 引导（`doom env` v2 位置参数语法、kitty/Doom 共用字体 cask）：
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
   （`config/herdr/herdr-popup-lib.sh`、`install-common.sh`）。新增第五个
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
