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
   Determinate CLI installer。
3. source Nix profile，确保 `nix` 可用。
4. 写入仓库托管的 Nix cache 配置块：
   - 用户配置：`$HOME/.config/nix/nix.conf`
   - daemon 配置：`/etc/nix/nix.custom.conf`，并在 `/etc/nix/nix.conf` 中 include
   - 如有 daemon 变更会尝试重启 `nix-daemon`
5. 对本仓库执行安全 `git pull --rebase`：有未提交、暂存或未跟踪改动时会跳过，
   避免覆盖本地工作。
6. 如果 pull 后 `init.sh` 自身更新，会 `exec` 重新运行一次新脚本。
7. `--upgrade` 会先确认，再执行 `nix flake update`。
8. macOS 默认先运行 `brew/install.sh` 确保 Homebrew 和必要 tap 可用，然后通过
   `nix run .#darwin-rebuild -- switch --flake .#<system> --impure` 激活
   nix-darwin。非 root 运行时会通过 `sudo env` 传入 `NIX_HM_USER` 和
   `NIX_HM_HOME`。
9. Linux 或 macOS `--home-manager` 路径会执行
   `nix run nixpkgs#home-manager -- switch -b backup --flake .#<system>`。

重要环境变量：

- `NIX_HM_USER` / `NIX_HM_HOME`：显式指定 flake 评估时的用户和 home 目录。
- `DEBUG=1`：打开 shell trace，并传给 `NIX_HM_DEBUG`。
- `NIX_HM_USE_HOME_MANAGER=1`：macOS 上跳过 nix-darwin，使用 Home Manager。
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
  （联网 clone dot-nvim、初始化 Neovim）。

`modules/linux-docker.nix`

- Linux 容器/Docker 层。只导入 `modules/common.nix` 的共享配置，**不**运行
  `install-linux-server.sh`，激活期不联网，适合无头、可丢弃的镜像；`isDocker`
  也强制关闭 `modules/host.nix`。

## 4. macOS 系统层：nix-darwin

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
  `firefox`、`kitty`、`maccy`、`microsoft-edge`、`obsidian`、`raycast`、
  `visual-studio-code`、`zed`、`zotero`，以及 `nikitabobko/tap/aerospace`
  和本地 tap 的 `whatpulse` 系列在这里维护。

`nix-darwin/gui-apps.nix`

- 管理适合 Nix 安装或 system launchd 管理的 GUI 辅助项。
- 当前包括 `nerd-fonts.shure-tech-mono`、`sketchybar-app-font`
  （AeroSpace 本身由 Homebrew cask 安装，不在 Nix 包里）。
- 用 `config/aerospace/render-config.py` 从 `config/aerospace/aerospace.toml`
  模板生成 `~/.config/aerospace/aerospace.toml`，安装并（用 `swiftc`）编译
  workspace 指示器，删除旧的 `~/.aerospace.toml` 和已废弃的 HUD 脚本，并用
  `launchd.user.agents.aerospace` / `.aerospaceWorkspaceIndicator` 启动两者。
- **workspace→monitor 分配**：`render-config.py` 输出自愈的 fallback 数组，
  形如 `[<target>, 'main']`；AeroSpace 取第一个已连接的显示器匹配，因此某个显示器
  消失（合盖、拔线、断电重连导致重新编号）时会退回 `main`，而不是把 workspace
  卡在不存在的显示器上。分配目标顺序：`main`、非主外接屏从左到右、内置屏最后。
- **显示器变化重配**：`reconfigure-aerospace` 脚本重跑渲染 + `reload-config` +
  touch dirty 文件；AeroSpace 在显示器重连时不会自动重新套用 force-assignment
  （上游 issue #520），所以需要显式 nudge。它通过 `AEROSPACE_RECONFIGURE`
  launchd 环境变量暴露给指示器，由指示器在（去抖后的）显示器变化时触发。
- **workspace 指示器**（`config/aerospace/workspace_indicator.swift`）：一个
  accessory `NSApplication`，在每个显示器上浮动一个 `NSPanel`，显示当前 workspace、
  workspace chips 和打开的 app 图标；中央还有一个切换 workspace 时的 HUD。关键
  健壮性约定（改动时勿回退）：所有 per-display 状态按 `CGDirectDisplayID` 建键
  （不是 `localizedName`，避免两台同名显示器碰撞/崩溃）；`NSPanel` 设
  `isReleasedWhenClosed = false` 且用 `orderOut` 拆除（避免过度释放崩溃）；
  显示器变化去抖（~0.4s）；`runAerospace` 查询失败返回 `nil`（区别于空结果），
  失败时保留现有面板而非清空；dirty 文件监听在 rename/delete 后重新挂载。

`nix-darwin/macos-defaults.nix`

- macOS 系统 defaults：键盘（含 `com.apple.keyboard.fnState` 标准功能键，另有
  `refreshFunctionKeyMode` activation 写入用户 GlobalPreferences 并 kickstart
  Karabiner agents）、Dock、Finder、Trackpad、截图目录、Control Center、
  登录窗口等。

`nix-darwin/app-defaults.nix`

- app 级 defaults：Raycast、Maccy、Snipaste，以及默认打开方式 `duti`。

## 5. 激活脚本与外部配置

`install-macos.sh`

- 通过 `sync_config_repo` 安全同步 `https://github.com/PannenetsF/dot-nvim.git`
  到 `$HOME/.config/nvim`。目标不存在就 clone；存在但不是 git repo、dirty、
  staged、untracked 时跳过 pull。
- 首次运行时如果当前 profile 未提供 `ruff`、`ty`、`jedi-language-server`、
  `pynvim`，会通过 pip fallback 安装它们；随后运行
  `nvim --headless -c 'Lazy' -c 'qa'` 和 `TSUpdateSync`。
- 锁文件为 `$HOME/pf-init-macos`。
- `pip3` 不存在时 fallback 到 `python3 -m pip`。
- 只有 pip 支持 `--break-system-packages` 时才追加该参数。

`install-linux-server.sh`

- 同样安全同步 `dot-nvim`。
- 首次运行在当前 profile 未提供 Python/Nvim 依赖时通过 pip fallback 安装，
  并初始化 Neovim。
- 锁文件为 `$HOME/pf-init`。
- Linux 脚本当前默认追加 `--break-system-packages`。

注意：这些脚本在 Home Manager activation 中通过 `${../script.sh}` 进入只读
Nix store 后执行。脚本必须依赖运行时的 `$HOME`、`PATH` 和传入环境变量，不应假设
自己位于 git 工作树中。

`config/`

- 这是 macOS app/user 配置的源码目录：
  - `config/aerospace/aerospace.toml`、`config/aerospace/render-config.py`、
    `config/aerospace/workspace_indicator.swift`、
    `config/aerospace/start_workspace_indicator.sh`
  - `config/skhd/skhdrc`、`config/skhd/open_iterm2.sh`、
    `config/skhd/toggle_kitty_dropdown.sh`
  - `config/karabiner/karabiner.json`
  - `config/kitty/*`、`config/neovide/config.toml`
  - `config/zed/*`
- Kitty theme 上游通过 `.gitmodules` 中的 `config/kitty/kitty-themes` submodule
  记录。不要恢复旧的 `dot-kitty` clone 流程。

## 6. 修改指南

- 新增通用 CLI 包：优先改 `modules/common.nix`。
- 新增只在完整主机环境需要的工具：改 `modules/host.nix`。
- 新增只在 Linux 桌面/服务器需要、或需要联网初始化的内容：改 `modules/linux.nix`
  或 `install-linux-server.sh`；容器层要保持精简且激活期不联网，改
  `modules/linux-docker.nix`。
- 新增 macOS GUI app/cask：改 `nix-darwin/homebrew.nix`，必要时同步
  `brew/install.sh` 里的 tap/trust bootstrap。
- 新增 macOS 系统 defaults：改 `nix-darwin/macos-defaults.nix`。
- 新增 macOS app defaults 或默认打开方式：改 `nix-darwin/app-defaults.nix`。
- 新增 macOS launchd/system 管理的 GUI 工具：改 `nix-darwin/gui-apps.nix`。
- 新增用户 dotfile 链接或 Home Manager service：改 `modules/darwin.nix` 或
  对应平台模块。
- 修改启动、Nix 安装、cache、git pull、激活选择逻辑：改 `init.sh`。
- 修改 Neovim/Python 初始化：改 `install-macos.sh` 或 `install-linux-server.sh`。

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
8. AeroSpace 配置以“合盖/断电重连后仍可自愈”为目标：workspace 分配用 fallback
   数组、显示器变化触发 `reconfigure-aerospace`、指示器按 `CGDirectDisplayID`
   建键并避免 NSPanel 过度释放。改这块时保留这些不变量（见 `gui-apps.nix` 一节）。
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
- shell startup：`bash tests/zsh_startup_test.sh`、`bash tests/bash_profile_env_test.sh`
- Homebrew/GUI：`bash tests/brew_gui_apps_test.sh`、
  `bash tests/brew_install_bootstrap_test.sh`
- macOS defaults / Touch ID：`bash tests/darwin_defaults_test.sh`、
  `bash tests/darwin_touchid_sudo_test.sh`
- macOS 用户环境 / 激活 PATH：`bash tests/darwin_user_env_test.sh`、
  `bash tests/darwin_activation_nvim_path_test.sh`
- AeroSpace 配置渲染：`bash tests/aerospace_render_config_test.sh`
- app config sync：`bash tests/darwin_app_config_sync_test.sh`
- Kitty：`bash tests/kitty_config_test.sh`
- Python 工具 profile / pip 兼容：`bash tests/install_python_tools_profile_test.sh`、
  `bash tests/install_macos_pip_options_test.sh`
- 真实 macOS 激活后验收：`bash tests/macos_acceptance.sh`

改动后优先跑与变更相关的测试。涉及 flake、home/darwin module 或 shell startup
时，至少跑对应的 `nix eval` 测试；涉及 `init.sh` 时跑 `init_*` 测试；涉及
AeroSpace 时跑 `aerospace_render_config_test.sh` 并尽量本地 `swiftc` 编译
指示器；涉及 macOS GUI/Homebrew/defaults 时跑 `brew_*`、`darwin_*` 和必要的
acceptance。无 root 时可用 `nix eval .#...drvPath` / `nix build` 校验配置是否
可求值/可构建，而不必真正 activate。

Nix 文件格式保持 `nixfmt-classic` 风格；shell 脚本保持 Bash 语义，测试中大量使用
stub 命令，请避免引入难以 stub 的外部副作用。
