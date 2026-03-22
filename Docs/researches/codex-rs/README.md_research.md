# codex-rs/README.md 深度研究文档

## 场景与职责

`codex-rs/README.md` 是 OpenAI Codex CLI Rust 实现的用户入口文档，面向最终用户和潜在贡献者。它承担着以下关键职责：

1. **安装引导**: 提供多种安装方式（npm、Homebrew、GitHub Releases）
2. **功能展示**: 介绍 Rust CLI 相比旧版 TypeScript CLI 的新特性
3. **架构概览**: 说明代码组织结构，帮助贡献者快速定位
4. **文档导航**: 链接到详细配置和使用文档

---

## 功能点目的

### 1. 安装方式多样化 (lines 5-14)

```markdown
## Installing Codex

Today, the easiest way to install Codex is via `npm`:

```shell
npm i -g @openai/codex
codex
```
```

**设计意图**:
- **npm 为主**: 尽管是 Rust 实现，仍通过 npm 分发，降低用户门槛
- **多平台覆盖**: Homebrew (macOS)、GitHub Releases (全平台)
- **零依赖承诺**: "standalone, native executable"

### 2. 新特性展示 (lines 21-91)

#### 配置系统升级 (lines 25-27)
- **变更**: `config.json` → `config.toml`
- **原因**: TOML 更易于手写，支持注释，更适合配置文件

#### MCP 协议支持 (lines 29-45)

**MCP Client** (lines 31-33):
- Codex CLI 作为 MCP 客户端，连接外部 MCP 服务器
- 启动时自动连接配置的 MCP 服务器

**MCP Server** (lines 35-45):
- 实验性功能: `codex mcp-server`
- 允许其他 MCP 客户端将 Codex 作为工具使用
- 提供 Inspector 调试命令

#### 通知系统 (lines 47-49)
- 可配置脚本在 agent 完成时触发
- 支持 macOS `terminal-notifier`
- **WSL2 特殊处理**: 自动检测 `WT_SESSION` 环境变量，使用 Windows 原生通知

#### 程序化执行 (lines 51-54)

```markdown
### `codex exec` to run Codex programmatically/non-interactively

To run Codex non-interactively, run `codex exec PROMPT`...
```

**关键特性**:
- `codex exec` - 无头模式，适合自动化脚本
- `--ephemeral` - 不持久化会话，适合 CI/CD
- `RUST_LOG` 环境变量控制日志级别

#### 沙箱测试工具 (lines 56-73)

```markdown
# macOS
codex sandbox macos [--full-auto] [--log-denials] [COMMAND]...

# Linux
codex sandbox linux [--full-auto] [COMMAND]...

# Windows
codex sandbox windows [--full-auto] [COMMAND]...
```

**功能价值**:
- 允许用户测试命令在沙箱中的行为
- 支持 `--full-auto` 完全自动模式
- `--log-denials` 记录权限拒绝（macOS）
- 保留 legacy 别名 `debug seatbelt/landlock`

#### 沙箱策略选择 (lines 75-91)

```markdown
```shell
# Run Codex with the default, read-only sandbox
codex --sandbox read-only

# Allow the agent to write within the current workspace
codex --sandbox workspace-write

# Danger! Disable sandboxing entirely
codex --sandbox danger-full-access
```
```

**策略层级**:
| 策略 | 权限 | 使用场景 |
|------|------|----------|
| `read-only` | 只读 | 默认安全模式 |
| `workspace-write` | 工作区可写 | 需要文件修改 |
| `danger-full-access` | 完全访问 | 容器内使用 |

**配置持久化**:
- 命令行: `--sandbox` / `-s`
- 配置文件: `~/.codex/config.toml` 中 `sandbox_mode = "MODE"`
- `workspace-write` 自动包含 `~/.codex/memories` 可写

### 3. 代码组织结构 (lines 93-102)

```markdown
## Code Organization

This folder is the root of a Cargo workspace. It contains quite a bit of experimental code, but here are the key crates:

- [`core/`](./core) contains the business logic for Codex...
- [`exec/`](./exec) "headless" CLI for use in automation.
- [`tui/`](./tui) CLI that launches a fullscreen TUI...
- [`cli/`](./cli) CLI multitool that provides the aforementioned CLIs via subcommands.
```

**架构设计**:
- **分层架构**: core（业务）→ exec/tui（界面）→ cli（入口）
- **库优先**: core 设计为可复用库
- **多前端**: TUI（交互）和 exec（自动化）共享同一核心

---

## 具体技术实现

### 文档交叉引用

| 引用目标 | 路径 | 用途 |
|----------|------|------|
| 入门指南 | `../docs/getting-started.md` | 新用户引导 |
| 配置文档 | `../docs/config.md` | 详细配置说明 |
| 安装文档 | `../docs/install.md` | 安装细节 |
| MCP 配置 | `../docs/config.md#connecting-to-mcp-servers` | MCP 服务器配置 |
| 通知配置 | `../docs/config.md#notify` | 通知脚本示例 |

### 命令示例设计

文档中的命令示例遵循以下模式：
1. **渐进式展示**: 从简单到复杂
2. **注释说明**: 使用 `#` 解释用途
3. **危险标记**: `Danger!` 明确标注高风险操作
4. **平台区分**: 明确标注 macOS/Linux/Windows

---

## 关键代码路径与文件引用

### 相关实现文件

| 文档提及 | 实际实现路径 | 说明 |
|----------|--------------|------|
| `codex exec` | `codex-rs/exec/` | 无头 CLI crate |
| `codex mcp-server` | `codex-rs/mcp-server/` | MCP 服务器实现 |
| `codex sandbox` | `codex-rs/cli/src/` | CLI 子命令 |
| `--sandbox` | `codex-rs/core/src/` | 沙箱策略核心逻辑 |
| TUI | `codex-rs/tui/` | Ratatui 实现 |
| config.toml | `codex-rs/config/` | 配置解析 |

### 配置文件路径

```
~/.codex/
├── config.toml          # 主配置
└── memories/            # 持久化记忆（workspace-write 默认可写）
```

---

## 依赖与外部交互

### 外部工具依赖

| 工具 | 用途 | 来源 |
|------|------|------|
| `terminal-notifier` | macOS 通知 | 第三方 Homebrew |
| `@modelcontextprotocol/inspector` | MCP 调试 | npm |

### 环境变量

| 变量 | 用途 | 检测场景 |
|------|------|----------|
| `WT_SESSION` | Windows Terminal 检测 | WSL2 通知回退 |
| `RUST_LOG` | 日志级别控制 | exec 调试 |

### 平台特定行为

| 平台 | 特殊处理 |
|------|----------|
| macOS | `terminal-notifier` 通知支持 |
| WSL2 | Windows 原生通知回退 |
| Windows | 专用沙箱实现 |
| Linux | Landlock + Seccomp 沙箱 |

---

## 风险、边界与改进建议

### 当前文档风险

1. **版本同步风险**
   - 文档中功能描述可能与代码实际状态不同步
   - 例如 MCP Server 标记为 "experimental"，需要定期更新状态

2. **平台覆盖不完整**
   - 未明确说明 Windows 通知系统的具体实现
   - 沙箱策略在不同平台的实现差异未详细说明

3. **配置迁移指导缺失**
   - 提到 `config.json` → `config.toml` 变更
   - 但未提供自动迁移工具或详细迁移指南

### 边界条件

1. **沙箱策略边界**
   - `danger-full-access` 仅在容器内推荐，但无强制检查
   - 用户可能误用导致安全风险

2. **MCP 兼容性边界**
   - MCP Server 为实验性，API 可能变更
   - 未明确说明支持的 MCP 协议版本

3. **通知系统边界**
   - macOS 需要额外安装 `terminal-notifier`
   - Linux 桌面通知未提及（可能不支持）

### 改进建议

1. **添加架构图**
   ```markdown
   ## Architecture
   
   ```
   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
   │   codex     │────▶│    cli      │────▶│  exec/tui   │
   │  (binary)   │     │  (router)   │     │  (frontends)│
   └─────────────┘     └─────────────┘     └──────┬──────┘
                                                  │
                                           ┌──────▼──────┐
                                           │    core     │
                                           │  (business) │
                                           └─────────────┘
   ```
   ```

2. **添加故障排除章节**
   ```markdown
   ## Troubleshooting
   
   ### WSL2 通知不工作
   - 确保 `WT_SESSION` 环境变量设置
   - 检查 Windows Terminal 版本
   
   ### MCP 服务器连接失败
   - 检查 `config.toml` 配置语法
   - 使用 `codex mcp list` 验证配置
   ```

3. **添加版本兼容性表**
   ```markdown
   ## Compatibility
   
   | Codex Version | MCP Protocol | Config Format |
   |---------------|--------------|---------------|
   | 0.1.0+        | 0.15.0       | TOML          |
   ```

4. **改进安全警告**
   ```markdown
   > ⚠️ **Security Warning**: `danger-full-access` disables all sandboxing.
   > Only use this if you are running inside a container or VM.
   > Consider using `workspace-write` instead for most use cases.
   ```

5. **添加贡献者快速开始**
   ```markdown
   ## For Contributors
   
   ```shell
   cd codex-rs
   cargo build --workspace
   cargo test -p codex-core
   ```
   ```

---

## 附录: 用户旅程映射

### 新用户旅程

1. **发现** → GitHub/npm 找到安装命令
2. **安装** → `npm i -g @openai/codex`
3. **首次运行** → 阅读 `getting-started.md`
4. **配置** → 编辑 `~/.codex/config.toml`
5. **进阶** → 探索 MCP、通知、沙箱策略

### 自动化用户旅程

1. **发现** → 搜索 "codex ci/cd"
2. **阅读** → `codex exec` 文档
3. **测试** → 本地测试 `--ephemeral` 模式
4. **集成** → 添加到 CI pipeline

### 贡献者旅程

1. **发现** → GitHub 找到项目
2. **阅读** → README 代码组织结构
3. **定位** → 根据兴趣选择 crate（core/tui/exec）
4. **深入** → 阅读 crate 级 README
