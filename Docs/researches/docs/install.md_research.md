# install.md 研究文档

## 场景与职责

install.md 是 Codex CLI 项目的安装和构建指南文档。该文档详细说明了系统要求、安装方法（包括 DotSlash）以及从源码构建的步骤。

**适用场景：**
- 新用户安装 Codex CLI
- 开发者从源码构建项目
- 配置开发环境

## 功能点目的

### 1. 系统要求
| 要求 | 详情 |
|-----|------|
| 操作系统 | macOS 12+, Ubuntu 20.04+/Debian 10+, 或 Windows 11 **via WSL2** |
| Git（可选，推荐） | 2.23+ 用于内置 PR 辅助功能 |
| RAM | 4-GB 最低（8-GB 推荐） |

### 2. DotSlash 安装
- **DotSlash**：https://dotslash-cli.com/
- **用途**：使用 DotSlash 文件可以轻量级提交到源码控制，确保所有贡献者使用相同版本的可执行文件，无论他们使用什么平台进行开发
- **位置**：GitHub Release 包含名为 `codex` 的 DotSlash 文件

### 3. 从源码构建

#### 步骤 1：克隆仓库
```bash
git clone https://github.com/openai/codex.git
cd codex/codex-rs
```

#### 步骤 2：安装 Rust 工具链
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
rustup component add rustfmt
rustup component add clippy
```

#### 步骤 3：安装辅助工具
```bash
# 安装 just（工作区 justfile 使用的命令运行器）
cargo install just

# 可选：安装 nextest 用于 `just test` 辅助
cargo install --locked cargo-nextest
```

#### 步骤 4：构建
```bash
cargo build
```

#### 步骤 5：运行
```bash
# 使用示例提示启动 TUI
cargo run --bin codex -- "explain this codebase to me"
```

#### 步骤 6：开发后检查
```bash
# 格式化
just fmt

# 修复指定 crate 的 lint
just fix -p <crate-you-touched>

# 运行相关测试（项目特定最快）
cargo test -p codex-tui

# 如果有 cargo-nextest，`just test` 通过 nextest 运行测试套件
just test

# 避免 `--all-features` 进行常规本地运行
# 如果确实需要完整功能覆盖：
cargo test --all-features
```

### 4. 跟踪/详细日志

#### 日志系统
- Codex 使用 Rust 的 `tracing` 库，支持 `RUST_LOG` 环境变量

#### TUI 默认日志
- **默认级别**：`RUST_LOG=codex_core=info,codex_tui=info,codex_rmcp_client=info`
- **日志位置**：`~/.codex/log/codex-tui.log`
- **临时覆盖**：`-c log_dir=...`（例如 `-c log_dir=./.codex-log`）

#### 查看日志
```bash
tail -F ~/.codex/log/codex-tui.log
```

#### 非交互模式日志
- **默认级别**：`RUST_LOG=error`
- **输出方式**：内联打印，无需监控单独文件

#### 更多信息
- 参见 Rust 文档 [`RUST_LOG`](https://docs.rs/env_logger/latest/env_logger/#enabling-logging)

## 具体技术实现

### 构建流程

```
克隆仓库
    ↓
安装 Rust 工具链
    ↓
安装辅助工具 (just, cargo-nextest)
    ↓
cargo build
    ↓
运行测试
    ↓
开发迭代
    ↓
just fmt
just fix -p <crate>
cargo test -p <crate>
```

### 开发工作流

```
修改代码
    ↓
just fmt          # 格式化
    ↓
just fix -p <crate>  # 修复 lint
    ↓
cargo test -p <crate>  # 运行测试
    ↓
提交更改
```

## 关键代码路径与文件引用

### 相关文件位置

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/docs/install.md` | 本文档 |
| `/home/sansha/Github/codex/codex-rs/` | Rust 代码目录 |
| `/home/sansha/Github/codex/justfile` | Just 任务定义 |
| `/home/sansha/Github/codex/Cargo.toml` | 工作区配置 |

### 关键工具

1. **Rust 工具链**
   - `rustup` - Rust 安装管理器
   - `cargo` - Rust 构建工具和包管理器
   - `rustfmt` - 代码格式化工具
   - `clippy` - Rust lint 工具

2. **just**
   - 命令运行器
   - 替代 Make

3. **cargo-nextest**
   - 更快的测试运行器
   - 可选但推荐

## 依赖与外部交互

### 外部依赖

1. **Rust 生态系统**
   - crates.io - Rust 包仓库
   - rustup.rs - Rust 工具链

2. **GitHub**
   - 源码托管
   - GitHub Releases（DotSlash 文件）

3. **DotSlash**
   - Meta 开发的工具
   - 用于可执行文件版本管理

### 内部依赖

1. **工作区结构**
   - `codex-rs/` - Rust 代码
   - 多个 crate（codex-core, codex-tui 等）

2. **构建系统**
   - Cargo
   - Just

## 风险、边界与改进建议

### 潜在风险

1. **Windows 支持限制**
   - 仅支持通过 WSL2
   - 原生 Windows 支持缺失
   - 建议：考虑添加原生 Windows 支持

2. **RAM 要求**
   - 最低 4GB 可能对某些用户是门槛
   - 建议：优化内存使用或提供更轻量选项

3. **Git 版本要求**
   - 2.23+ 用于 PR 辅助功能
   - 旧版本 Git 可能功能受限

### 边界情况

1. **网络限制**
   - 企业环境可能需要代理配置
   - 某些地区可能无法访问 crates.io

2. **磁盘空间**
   - Rust 构建需要大量磁盘空间
   - `target/` 目录可能变得很大

3. **并发构建**
   - 大型工作区的构建时间
   - `--all-features` 的构建矩阵膨胀

### 改进建议

1. **预构建二进制文件**
   - 为常见平台提供预构建二进制文件
   - 减少从源码构建的需求

2. **包管理器分发**
   - 支持 Homebrew（macOS）
   - 支持 apt（Ubuntu/Debian）
   - 支持其他包管理器

3. **Docker 镜像**
   - 提供官方 Docker 镜像
   - 便于隔离和可移植性

4. **安装脚本**
   - 提供一键安装脚本
   - 自动检测平台和安装依赖

5. **开发容器**
   - 提供 Dev Container 配置
   - 便于 VS Code 用户

6. **文档增强**
   - 添加故障排除部分
   - 提供常见构建错误的解决方案
   - 添加性能优化建议

7. **CI/CD 集成**
   - 提供 GitHub Actions 示例
   - 提供其他 CI 系统的配置示例
