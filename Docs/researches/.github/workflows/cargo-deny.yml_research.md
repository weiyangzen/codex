# cargo-deny.yml 研究文档

## 场景与职责

本 GitHub Actions 工作流负责运行 `cargo-deny` 工具，对 Rust 项目的依赖进行安全审计和许可证合规检查。这是供应链安全的重要组成部分，确保项目依赖没有已知漏洞且许可证兼容。

## 功能点目的

1. **安全漏洞检测**：检查依赖 crate 是否存在已知安全漏洞（通过 RustSec  advisory 数据库）
2. **许可证合规**：验证所有依赖的许可证与项目要求兼容
3. **依赖来源限制**：可配置禁止某些来源的依赖（如 Git 依赖）
4. **重复依赖检测**：发现同一 crate 的多个版本，帮助优化依赖树

## 具体技术实现

### 触发条件
```yaml
on:
  pull_request:
  push:
    branches:
      - main
```
- PR 触发：所有 Pull Request，在依赖变更时及时发现问题
- Push 触发：main 分支推送，确保主干始终合规

### 作业配置
```yaml
jobs:
  cargo-deny:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ./codex-rs
```
- 在 Ubuntu 最新版上运行
- 设置默认工作目录为 `codex-rs`，因为 Rust 代码位于该子目录

### 执行步骤
```yaml
steps:
  - name: Checkout
    uses: actions/checkout@v6

  - name: Install Rust toolchain
    uses: dtolnay/rust-toolchain@stable

  - name: Run cargo-deny
    uses: EmbarkStudios/cargo-deny-action@v2
    with:
      rust-version: stable
      manifest-path: ./codex-rs/Cargo.toml
```

#### 工具链安装
- 使用 `dtolnay/rust-toolchain@stable` 安装稳定版 Rust
- 这是 Rust 项目的标准工具链安装方式

#### cargo-deny 执行
- 使用 `EmbarkStudios/cargo-deny-action@v2` 官方 Action
- 配置参数：
  - `rust-version: stable`：使用稳定版 Rust
  - `manifest-path: ./codex-rs/Cargo.toml`：指定 Cargo.toml 路径

## 关键代码路径与文件引用

| 文件 | 作用 |
|------|------|
| `.github/workflows/cargo-deny.yml` | 本工作流定义 |
| `codex-rs/Cargo.toml` | Rust 工作区根配置 |
| `codex-rs/Cargo.lock` | 依赖锁定文件 |
| `codex-rs/deny.toml`（如存在） | cargo-deny 配置文件 |

### cargo-deny 配置

虽然工作流中没有显式指定配置文件，但 cargo-deny 会查找以下位置的配置：
- `deny.toml`
- `.cargo/deny.toml`
- `cargo-deny.toml`

典型配置可能包括：
```toml
[advisories]
# 忽略特定 advisory（如已知但可接受的风险）
ignore = []

[licenses]
# 允许的许可证列表
allow = ["MIT", "Apache-2.0", "BSD-3-Clause"]
# 拒绝的许可证
deny = ["GPL-2.0", "GPL-3.0"]

[bans]
# 禁止多个版本的 crate
multiple-versions = "warn"
# 允许特定 crate 的多版本
skip = []

[sources]
# 允许的 crate 来源
allow-registry = ["https://github.com/rust-lang/crates.io-index"]
# 是否允许 Git 依赖
allow-git = []
```

## 依赖与外部交互

### 外部服务
1. **crates.io**：Rust 包仓库，用于获取 crate 元数据
2. **RustSec Advisory Database**：安全漏洞数据库
   - 仓库：https://github.com/rustsec/advisory-db
   - cargo-deny 会定期拉取最新漏洞信息

### 依赖的工具
- `cargo-deny`：Embark Studios 开发的审计工具
- Rust 稳定版工具链

## 风险、边界与改进建议

### 风险
1. **advisory 数据库延迟**：新漏洞从发现到入库有时间差
2. **许可证误判**：某些许可证可能存在解释争议
3. **Git 依赖风险**：如果允许 Git 依赖，可能引入未审计代码
4. **Action 版本**：使用 v2 版本，需要关注更新

### 边界条件
- 仅检查 `codex-rs` 目录下的 Rust 项目
- 依赖 `Cargo.lock` 文件存在（对于库项目可能需要特殊处理）
- 需要网络访问 crates.io 和 advisory 数据库

### 改进建议
1. **显式配置文件**：添加 `deny.toml` 明确声明安全策略
2. **定期更新**：配置 Dependabot 或类似工具自动更新依赖
3. **本地检查**：在 `justfile` 中添加 `cargo-deny` 命令便于本地预检查
4. **失败阈值**：配置哪些检查失败会阻止合并（如安全漏洞必须修复，许可证警告可讨论）
5. **缓存优化**：利用 cargo-deny-action 的缓存功能加速检查
6. **报告输出**：配置 SARIF 格式输出，集成到 GitHub Security 标签页

### 配置示例建议

建议添加 `codex-rs/deny.toml`：
```toml
# 安全 advisory 检查
[advisories]
version = 2
yanked = "warn"

# 许可证检查
[licenses]
version = 2
allow = [
    "MIT",
    "Apache-2.0",
    "Apache-2.0 WITH LLVM-exception",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "ISC",
    "Unicode-DFS-2016",
    "MPL-2.0",
    "OpenSSL",
]

# 重复依赖检查
[bans]
multiple-versions = "warn"
wildcards = "allow"  # 允许通配符版本（开发中常见）

# 来源限制
[sources]
unknown-registry = "deny"
unknown-git = "deny"
allow-registry = ["https://github.com/rust-lang/crates.io-index"]
```
