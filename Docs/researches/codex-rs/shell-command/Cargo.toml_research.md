# codex-rs/shell-command/Cargo.toml 研究文档

## 场景与职责

该 Cargo.toml 定义了 `codex-shell-command` crate 的元数据、依赖关系和编译配置。该 crate 是 Codex 项目的**命令解析与安全检查基础设施**，负责：

1. **命令解析**: 将 shell 命令字符串解析为结构化表示（ParsedCommand）
2. **安全评估**: 判断命令是否危险（`is_dangerous_command`）或安全（`is_safe_command`）
3. **跨平台支持**: 区分 Unix（Bash/Zsh）和 Windows（PowerShell/CMD）的处理逻辑

## 功能点目的

### 1. 包元数据
```toml
[package]
name = "codex-shell-command"
version.workspace = true      # 继承工作区版本
edition.workspace = true      # 继承工作区 Rust 版本
license.workspace = true      # 继承工作区许可证
```
- 使用 workspace 继承确保版本一致性
- crate 名遵循 `codex-{功能}` 命名规范

### 2. 代码质量配置
```toml
[lints]
workspace = true              # 继承工作区 lint 规则
```
- 统一应用项目级 Clippy 规则和 rustc lint

### 3. 运行时依赖
| 依赖 | 用途 |
|------|------|
| `tree-sitter` + `tree-sitter-bash` | Bash 脚本 AST 解析 |
| `shlex` | Shell 词法分割（处理引号、转义） |
| `regex` | 模式匹配（URL 检测、命令识别） |
| `once_cell` | 延迟初始化静态变量 |
| `serde` + `serde_json` | 命令结构序列化 |
| `which` | 可执行文件路径查找 |
| `url` | URL 解析与验证 |
| `base64` | PowerShell 脚本编码 |
| `codex-protocol` | 共享协议类型（ParsedCommand） |
| `codex-utils-absolute-path` | 绝对路径处理工具 |

### 4. 开发依赖
| 依赖 | 用途 |
|------|------|
| `anyhow` | 测试中的错误处理 |
| `pretty_assertions` | 测试断言美化输出 |

## 具体技术实现

### 关键数据结构

#### ParsedCommand（定义于 codex-protocol）
```rust
pub enum ParsedCommand {
    Read { cmd: String, name: String, path: PathBuf },      // 文件读取命令
    ListFiles { cmd: String, path: Option<String> },        // 文件列表命令
    Search { cmd: String, query: Option<String>, path: Option<String> }, // 搜索命令
    Unknown { cmd: String },                                // 未知/复杂命令
}
```

#### ShellType（内部枚举）
```rust
enum ShellType {
    Zsh, Bash, PowerShell, Sh, Cmd
}
```

### 核心算法流程

#### 1. 命令安全检测流程
```
输入: command: &[String]
├── Windows 平台?
│   └── 检查 windows_dangerous_commands
├── 基础危险检测
│   ├── rm -f / rm -rf → 危险
│   └── sudo <cmd> → 递归检测 <cmd>
└── Bash -lc 脚本解析
    ├── 解析脚本内容
    ├── 分割为子命令
    └── 每个子命令递归检测
```

#### 2. Bash 解析流程（tree-sitter）
```
输入: bash -lc "script"
├── tree-sitter 解析 AST
├── 遍历节点检查允许类型
│   ├── 允许: program, list, pipeline, command, word, string
│   └── 拒绝: 重定向、子 shell、变量替换、控制流
└── 提取纯单词命令序列
```

#### 3. PowerShell 解析流程（Windows）
```
输入: pwsh -Command "script"
├── 嵌入的 powershell_parser.ps1 脚本
├── Base64 编码传输
├── 调用 PowerShell AST API
├── 转换为命令向量
└── 安全白名单验证
```

### 安全白名单（is_safe_command.rs）

#### Unix 安全命令
- **基础工具**: cat, ls, pwd, echo, grep, head, tail, wc, tr, cut, sort, uniq
- **文件查看**: less, more, bat, batcat
- **搜索**: rg (ripgrep), git status/log/diff/show/branch
- **特殊处理**: 
  - `sed -n <range>p` 只读模式
  - `find` 排除 -exec/-delete 等危险选项
  - `base64` 排除 -o/--output 选项

#### Windows 安全命令（PowerShell）
- **基础**: Get-ChildItem, Get-Content, Select-String
- **测量**: Measure-Object
- **路径**: Get-Location, Test-Path, Resolve-Path
- **Git**: 同 Unix 限制

## 关键代码路径与文件引用

### 库入口
- `src/lib.rs` - 导出公共 API

### 核心模块
| 文件 | 功能 |
|------|------|
| `src/bash.rs` | Bash/Zsh 脚本解析（590 行） |
| `src/powershell.rs` | PowerShell 命令提取与 UTF-8 前缀处理 |
| `src/shell_detect.rs` | Shell 类型检测（32 行） |
| `src/parse_command.rs` | 命令解析主逻辑（2000+ 行） |
| `src/command_safety/is_dangerous_command.rs` | 危险命令检测（161 行） |
| `src/command_safety/is_safe_command.rs` | 安全命令白名单（602 行） |
| `src/command_safety/windows_dangerous_commands.rs` | Windows 危险命令（755 行） |
| `src/command_safety/windows_safe_commands.rs` | Windows 安全命令（623 行） |
| `src/command_safety/powershell_parser.ps1` | PowerShell AST 解析脚本（201 行） |

### 下游调用示例
```rust
// codex-core/src/tools/handlers/unified_exec.rs
use codex_shell_command::is_safe_command::is_known_safe_command;

async fn is_mutating(&self, invocation: &ToolInvocation) -> bool {
    // ...
    !is_known_safe_command(&command)  // 判断是否需要审批
}
```

## 依赖与外部交互

### 上游依赖详解

#### tree-sitter 生态
```toml
tree-sitter = { workspace = true }
tree-sitter-bash = { workspace = true }
```
- 用于解析 Bash 脚本为 AST
- 支持识别命令结构、引号、连接符等

#### shlex
```toml
shlex = { workspace = true }
```
- 处理 shell 风格的词法分割
- 正确处理引号、转义字符

#### regex + once_cell
```toml
regex = { workspace = true }
once_cell = { workspace = true }
```
- 用于 Windows 平台的 URL 检测
- 静态编译正则表达式提高性能

### 下游消费者

| crate | 使用方式 |
|-------|----------|
| `codex-core` | `is_known_safe_command()` 判断是否需要用户审批 |
| `codex-tui` | `parse_command()` 生成命令摘要展示 |
| `codex-tui_app_server` | 同 codex-tui |
| `codex-mcp-server` | 命令安全评估 |

## 风险、边界与改进建议

### 风险点

#### 1. 解析器安全边界
- **问题**: tree-sitter-bash 可能无法解析所有合法 Bash 语法
- **影响**: 复杂脚本被标记为 Unknown，降低用户体验
- **缓解**: 保守策略（宁可误判为危险，也不漏判）

#### 2. PowerShell 依赖
- **问题**: Windows 安全检测依赖外部 PowerShell 进程执行 AST 解析
- **影响**: 
  - 性能开销（进程启动）
  - 依赖 PowerShell 可用性
- **缓解**: 缓存机制、优雅降级

#### 3. 安全白名单维护
- **问题**: 新增命令需要手动加入白名单
- **风险**: 遗漏可能导致安全风险或用户体验下降
- **示例**: 
  - Linux 特有命令 `numfmt`, `tac` 仅在 Linux 标记为安全
  - Git 新版本可能添加危险选项

### 边界情况

#### 1. 命令复杂度边界
```rust
// 支持的 Bash 结构
"ls && pwd"                    // ✓ 支持
"ls | wc -l"                   // ✓ 支持
"echo $(cmd)"                  // ✗ 拒绝（命令替换）
"ls > file"                    // ✗ 拒绝（重定向）
"(cd dir && cmd)"              // ✗ 拒绝（子 shell）
```

#### 2. Git 命令边界
```rust
// 安全
"git status"
"git log -n 5"
"git branch --show-current"

// 危险（需要审批）
"git branch -d feature"        // 删除分支
"git -c core.pager=cat status" // 配置覆盖可执行任意命令
```

### 改进建议

#### 1. 依赖优化
```toml
# 考虑将 tree-sitter 设为可选依赖
[features]
default = ["bash-parse"]
bash-parse = ["tree-sitter", "tree-sitter-bash"]
```

#### 2. 测试增强
- 添加模糊测试（fuzzing）验证解析器鲁棒性
- 添加跨平台集成测试

#### 3. 性能优化
- PowerShell 解析结果缓存
- tree-sitter Parser 实例复用

#### 4. 安全审计
- 建立定期审查安全白名单的流程
- 添加危险命令检测的遥测/日志

#### 5. 文档完善
- 为每个安全命令添加注释说明安全理由
- 提供安全评估决策树文档
