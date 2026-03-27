# Nix Home Manager macOS 支持重构设计

日期：2026-03-27

## 背景与目标
当前配置仅支持 Linux 的 `x86_64-linux` 与 `aarch64-linux`。目标是在不引入 nix-darwin 的前提下，
通过 Home Manager 增加 macOS（`x86_64-darwin` 与 `aarch64-darwin`）支持，并对配置做适度重构以便扩展维护。

## 范围与约束
- 仅使用 Home Manager，不引入 nix-darwin。
- 用户名与 Home 目录采用自动推断（`USER` 与 `HOME` 环境变量）。
- 增加 macOS 专用初始化脚本 `install-macos.sh`，由 Home Manager 激活时触发。
- 保持 `stateVersion` 不变。

## 方案概览（选用）
采用“单入口 + 按平台分层模块”的结构：
- `flake.nix` 统一入口，新增 macOS 的 homeConfigurations。
- `home.nix` 负责组合通用与平台模块。
- `modules/common.nix` 放通用配置；`modules/linux.nix` 与 `modules/darwin.nix` 放平台差异。

## 设计细节

### 1) 配置入口（flake.nix）
- 继续使用 `mkHomeConfig system` 创建 Home Manager 配置。
- `homeConfigurations` 增加：
  - `x86_64-darwin`
  - `aarch64-darwin`

### 2) 模块拆分
- `modules/common.nix`
  - `home.packages`（通用包）
  - `programs.zsh`、`programs.neovim`、`programs.tmux` 等通用配置
  - `home.sessionVariables`
- `modules/linux.nix`
  - Linux 专属包与配置
  - `home.activation.runMyScript` 调用 `install-linux-server.sh`
- `modules/darwin.nix`
  - macOS 专属包与配置
  - `home.activation.runMyScript` 调用 `install-macos.sh`

### 3) 用户信息自动推断
- `home.username = builtins.getEnv "USER"`
- `home.homeDirectory = builtins.getEnv "HOME"`
- `home.stateVersion = "25.05"` 保持不变

### 4) 平台差异处理
- Linux 仍保留当前的初始化流程（Linux 脚本仅在 Linux 平台执行）。
- macOS 使用新的 `install-macos.sh`，与 Linux 脚本职责对齐（初始化开发环境）。
- 不兼容或平台特有的包移动到各自平台模块。

## 数据流 / 配置流
`flake.nix` 选择 `system` → `mkHomeConfig` → `home.nix` 组合模块 → 平台模块调整差异 → 输出 HM 配置。

## 错误处理与安全性
- 平台脚本只在对应系统执行，避免跨平台调用失败。
- 脚本需避免破坏性操作与不必要的权限提升，保持可重复执行。

## 测试与验证
- 在 Linux 与 macOS 上分别运行 Home Manager `switch`，确保配置可应用。
- 验证：
  - `home.username` 与 `home.homeDirectory` 正确推断
  - 平台脚本按系统触发
  - 通用与平台特有包可正常安装

## 变更列表（预期）
- 更新：`flake.nix`、`home.nix`
- 新增：`modules/common.nix`、`modules/linux.nix`、`modules/darwin.nix`
- 新增：`install-macos.sh`

