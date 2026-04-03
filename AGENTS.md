# Agent 导读 (AGENTS.md)

本文件旨在为后续接手的 AI Agent 提供关于本项目 (`dot-nix`) 的架构、工作流和设计约定的全局概览，便于快速理解和修改代码。

## 1. 项目简介

这是一个基于 **Nix Home Manager (Flakes)** 构建的跨平台 dotfiles 管理库，主要用于集中管理和自动化配置用户开发环境。
项目支持主流架构：
- macOS (`x86_64-darwin`, `aarch64-darwin`)
- Linux (`x86_64-linux`, `aarch64-linux`)

## 2. 核心架构与文件结构

- `init.sh`: 项目的唯一启动入口，主要做三件事：
  1. 自动检测并安装 Nix（使用 Determinate Systems 的 Nix 安装器）；
  2. 拉取本仓库 (`dot-nix`) 的最新代码；
  3. 执行 `nix run nixpkgs#home-manager -- switch --flake .#<system>` 以激活 Home Manager。
- `flake.nix`: Flake 配置文件，定义了输入 (`nixpkgs`, `nixpkgs-unstable`, `home-manager`) 及对应各个系统架构的 `homeConfigurations`，并将当前 `system` 参数传入子模块中。
- `home.nix`: 主入口，主要负责动态推断当前用户的 `homeDirectory`（考虑到纯净模式下环境变量缺失），并按平台引入具体的模块文件。
- `modules/` 目录: 
  - `common.nix`: 所有环境通用的核心配置（安装大量 CLI 工具如 `lazygit`, `ripgrep`, `fzf` 等，配置 Zsh、tmux、Neovim 以及通用环境变量和快捷 alias，如 `hm-update`）。
  - `darwin.nix` / `linux.nix`: 特定系统的配置，主要是在激活阶段（`home.activation`）使用 Nix store 内嵌的方式执行对应的环境安装脚本。
- `install-macos.sh` / `install-linux-server.sh`: 执行 Python 依赖安装、自动拉取用户的 `dot-nvim` 仓库并执行 Neovim 的 headless 初始化 (`Lazy` & `Treesitter`)。执行过会留有 `FILE_LOCK` 防止重复安装。

## 3. 设计约定与修改须知

1. **绝对路径与环境变量**：在 `home.nix` 之中通过复杂的推断逻辑来保证 `homeDirectory` 绝对正确，后续对 `HOME` 的引用在 Bash 脚本中应当保持兼容。
2. **Nix Store 执行**：为了避免 Git 追踪变化，`activation` 中执行的 Bash 脚本如 `install-macos.sh` 直接通过 `${../install-macos.sh}` 被装载到只读 Nix Store 中执行，而不是 link 到本地。
3. **终端回退（Terminal Fallback）**：Zsh 中的 `TERM` 变量采用了动态判断 `infocmp xterm-kitty`，如果不支持则 fallback 到 `xterm-256color`，防止终端报错。
4. **Zsh 配置**：统一放在 `common.nix` 里的 `programs.zsh.initContent`。注意这里要处理 Nix daemon profile 的自动 source，以及自然文本编辑（Natural text editing）的 bindkey。
5. **快捷更新**：用户可以使用 `hm-update` 别名快速更新，后续若修改配置，建议通过提示引导用户运行该别名或 `bash init.sh`。

当你（AI Agent）需要增加新功能时：
- 修改或新增**包** -> 到 `modules/common.nix`
- 修改**启动脚本行为** -> 修改 `init.sh`
- 修改**特定平台的额外构建操作** -> `install-macos.sh` 或 `linux` 版本，并同步关注 `modules/` 中对应 OS 模块。