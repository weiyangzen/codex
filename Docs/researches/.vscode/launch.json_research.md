# .vscode/launch.json 研究文档

## 场景与职责

`launch.json` 是 VS Code 的调试配置文件，定义了项目的调试启动配置。该文件位于 `.vscode/` 目录下，为开发者提供便捷的调试入口，支持 Rust 代码的断点调试、变量检查和调用栈分析。

该文件服务于以下场景：
- **开发调试**：在开发过程中启动 TUI 应用并进行交互式调试
- **问题诊断**：附加到正在运行的 Codex CLI 进程进行实时调试
- **新成员上手**：为新加入的开发者提供即开即用的调试配置

## 功能点目的

### 调试配置列表

该文件定义了两个调试配置：

#### 1. Cargo launch（启动调试）

```json
{
    "type": "lldb",
    "request": "launch",
    "name": "Cargo launch",
    "cargo": {
        "cwd": "${workspaceFolder}/codex-rs",
        "args": ["build", "--bin=codex-tui"]
    },
    "args": []
}
```

**功能目的**：
- 通过 Cargo 构建 `codex-tui` 二进制文件
- 使用 LLDB 调试器启动构建后的程序
- 支持在 TUI 代码中设置断点进行调试

**关键参数**：
- `type: "lldb"`：使用 LLDB 调试器（通过 `vadimcn.vscode-lldb` 扩展）
- `cwd: "${workspaceFolder}/codex-rs"`：设置 Cargo 工作目录为 Rust 项目根目录
- `args: ["build", "--bin=codex-tui"]`：构建目标为 `codex-tui` 二进制

#### 2. Attach to running codex CLI（附加调试）

```json
{
    "type": "lldb",
    "request": "attach",
    "name": "Attach to running codex CLI",
    "pid": "${command:pickProcess}",
    "sourceLanguages": ["rust"]
}
```

**功能目的**：
- 附加到已经运行的 Codex CLI 进程
- 用于调试生产环境或长时间运行的会话
- 支持动态选择目标进程

**关键参数**：
- `request: "attach"`：附加到现有进程而非启动新进程
- `pid: "${command:pickProcess}"`：使用 VS Code 的进程选择器动态选择 PID
- `sourceLanguages: ["rust"]`：指定源代码语言以优化调试体验

## 具体技术实现

### 调试协议与工具链

1. **LLDB (Low Level Debugger)**
   - 底层使用 LLVM 项目的 LLDB 调试器
   - 通过 `vscode-lldb` 扩展与 VS Code 集成
   - 支持 Rust 的符号解析和变量检查

2. **Cargo 集成**
   - `cargo` 字段指示 `vscode-lldb` 在调试前执行构建
   - 自动处理构建产物路径映射
   - 支持增量编译以加速调试迭代

3. **VS Code 变量替换**
   - `${workspaceFolder}`：工作区根目录的绝对路径
   - `${command:pickProcess}`：执行 VS Code 命令选择进程

### 调试流程

```
开发者按 F5
    ↓
VS Code 读取 launch.json
    ↓
vscode-lldb 扩展处理配置
    ↓
执行 cargo build --bin=codex-tui
    ↓
构建成功后启动 LLDB
    ↓
LLDB 加载二进制并启动程序
    ↓
调试会话开始（断点、单步等）
```

## 关键代码路径与文件引用

### 相关配置文件

| 文件路径 | 关联关系 |
|---------|----------|
| `.vscode/extensions.json` | 声明 `vadimcn.vscode-lldb` 为必需扩展 |
| `.vscode/settings.json` | 配置 rust-analyzer 的 target 目录，影响构建产物位置 |
| `codex-rs/Cargo.toml` | 定义 `codex-tui` 二进制目标 |
| `codex-rs/tui/` | `codex-tui` 二进制的主要源代码目录 |

### 项目二进制目标

根据 `codex-rs/Cargo.toml`，工作区定义了多个二进制目标：

```toml
[[bin]]
name = "codex"
path = "cli/src/main.rs"

[[bin]]
name = "codex-exec"
path = "exec/src/main.rs"

[[bin]]
name = "codex-tui"
path = "tui/src/main.rs"
```

当前配置仅针对 `codex-tui`，这是项目的 TUI（终端用户界面）版本。

### 调试目标代码路径

| 二进制 | 入口文件 | 主要职责 |
|--------|----------|----------|
| `codex-tui` | `codex-rs/tui/src/main.rs` | 全屏终端界面，基于 Ratatui 实现 |
| `codex` | `codex-rs/cli/src/main.rs` | CLI 多工具入口 |
| `codex-exec` | `codex-rs/exec/src/main.rs` | 非交互式执行模式 |

## 依赖与外部交互

### 外部依赖

1. **VS Code LLDB 扩展 (`vadimcn.vscode-lldb`)**
   - 提供 LLDB 与 VS Code 的集成
   - 自动下载和管理 LLDB 二进制
   - 支持 Rust 的 pretty printers 以改善变量显示

2. **Cargo 工具链**
   - 需要安装 Rust 和 Cargo
   - 使用工作区级别的 `Cargo.toml` 配置

3. **LLDB 调试器**
   - 扩展会自动下载适配的 LLDB 版本
   - 支持 macOS、Linux 和 Windows

### 与项目构建系统的交互

```
launch.json
    ↓ 触发构建
Cargo.toml (workspace)
    ↓ 解析依赖
codex-rs/tui/Cargo.toml
    ↓ 编译
target/debug/codex-tui
    ↓ LLDB 加载
调试会话
```

## 风险、边界与改进建议

### 风险点

1. **路径硬编码**
   - 问题：`"cwd": "${workspaceFolder}/codex-rs"` 假设工作区根目录包含 `codex-rs` 子目录
   - 风险：如果开发者以 `codex-rs` 为工作区根打开，路径将错误
   - 缓解：文档说明应以仓库根目录为工作区打开

2. **单二进制限制**
   - 问题：配置仅针对 `codex-tui`，未覆盖 `codex` 和 `codex-exec`
   - 影响：调试其他二进制需要手动修改配置

3. **TUI 调试复杂性**
   - 问题：Ratatui 应用使用终端 Alternate Screen，调试时可能遇到渲染问题
   - 缓解：参考 `docs/tui-alternate-screen.md` 了解 TUI 终端管理

4. **环境变量传递**
   - 问题：当前配置未指定环境变量，某些功能（如 MCP、通知）可能需要特定环境
   - 缓解：可通过 `env` 字段添加环境变量配置

### 边界条件

- **平台限制**：LLDB 在 Windows 上的支持不如 macOS/Linux 完善
- **并发调试**：附加调试配置需要目标进程已运行，且用户有权限附加
- **构建时间**：首次调试需要完整构建，可能耗时较长

### 改进建议

1. **添加多二进制支持**
   ```json
   {
       "type": "lldb",
       "request": "launch",
       "name": "Cargo launch (codex-exec)",
       "cargo": {
           "cwd": "${workspaceFolder}/codex-rs",
           "args": ["build", "--bin=codex-exec"]
       },
       "args": ["--help"]
   }
   ```

2. **添加环境变量模板**
   ```json
   {
       "env": {
           "RUST_LOG": "debug",
           "CODEX_HOME": "${env:HOME}/.codex"
       }
   }
   ```

3. **添加复合配置 (Compounds)**
   ```json
   {
       "compounds": [
           {
               "name": "Launch TUI with Server",
               "configurations": ["Cargo launch", "Attach to App Server"]
           }
       ]
   }
   ```

4. **路径灵活性**
   考虑使用 `${workspaceFolder:codex-rs}` 如果工作区是多根工作区 (Multi-root workspace)。

5. **预启动任务集成**
   ```json
   {
       "preLaunchTask": "rust: cargo build"
   }
   ```

6. **调试参数化**
   添加配置以支持传递命令行参数：
   ```json
   {
       "args": ["${input:prompt}"]
   }
   ```
