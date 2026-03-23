# Research: unless_trusted.md

## 场景与职责

`unless_trusted.md` 定义了 `unless-trusted`（别名 `untrusted`）审批策略的提示词。这是一种**保守的安全策略**，设计用于对安全性要求较高的场景。

主要场景包括：
- **高安全环境**：默认不信任任何命令，仅允许已知安全的"读取"命令
- **新用户保护**：防止新用户意外执行危险命令
- **代码审查模式**：主要用于代码分析和审查，而非主动执行命令

## 功能点目的

1. **默认拒绝**：大多数命令都需要用户审批，只有有限的"安全"命令自动批准
2. **只读命令白名单**：预定义的只读命令（如 `ls`, `cat`, `grep` 等）可以自动执行
3. **权限升级机制**：与 `OnRequest` 类似，支持 `request_permissions` 工具进行权限升级

## 具体技术实现

### 关键数据结构

```rust
// codex-rs/protocol/src/protocol.rs:558-564
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize, Display, JsonSchema, TS)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum AskForApproval {
    /// Under this policy, only "known safe" commands—as determined by
    /// `is_safe_command()`—that **only read files** are auto‑approved.
    /// Everything else will ask the user to approve.
    #[serde(rename = "untrusted")]
    #[strum(serialize = "untrusted")]
    UnlessTrusted,
    // ...
}
```

### 安全命令检测

```rust
// codex-rs/core/src/is_safe_command.rs（推断）
// 此模块提供 is_known_safe_command 函数
pub fn is_known_safe_command(command: &[String]) -> bool {
    // 检查命令是否在安全命令白名单中
    // 确保命令只执行读取操作
}
```

### 关键流程

1. **提示词加载**（编译时）：
```rust
// codex-rs/protocol/src/models.rs:476-477
const APPROVAL_POLICY_UNLESS_TRUSTED: &str =
    include_str!("prompts/permissions/approval_policy/unless_trusted.md");
```

2. **开发者指令生成**：
```rust
// codex-rs/protocol/src/models.rs:531-533
AskForApproval::UnlessTrusted => {
    with_request_permissions_tool(APPROVAL_POLICY_UNLESS_TRUSTED)
}
```

3. **命令分类处理**：
```rust
// codex-rs/core/src/tools/handlers/shell.rs:166-176
async fn is_mutating(&self, invocation: &ToolInvocation) -> bool {
    match &invocation.payload {
        ToolPayload::Function { arguments } => {
            serde_json::from_str::<ShellToolCallParams>(arguments)
                .map(|params| !is_known_safe_command(&params.command))
                .unwrap_or(true)
        }
        ToolPayload::LocalShell { params } => !is_known_safe_command(&params.command),
        _ => true, // unknown payloads => assume mutating
    }
}
```

### 与 `OnRequest` 的区别

| 特性 | `UnlessTrusted` | `OnRequest` |
|-----|-----------------|-------------|
| 默认行为 | 拒绝大多数命令 | 允许沙盒内命令 |
| 自动批准 | 仅只读安全命令 | 所有沙盒内命令 |
| 使用场景 | 高安全/审查模式 | 日常开发 |
| 用户提示频率 | 高 | 中等 |

## 关键代码路径与文件引用

| 文件路径 | 作用 |
|---------|------|
| `codex-rs/protocol/src/prompts/permissions/approval_policy/unless_trusted.md` | 提示词内容（本文件） |
| `codex-rs/protocol/src/models.rs:476-477` | 编译时加载提示词 |
| `codex-rs/protocol/src/models.rs:531-533` | 根据 `AskForApproval::UnlessTrusted` 选择提示词 |
| `codex-rs/protocol/src/protocol.rs:558-564` | `AskForApproval::UnlessTrusted` 定义 |
| `codex-rs/core/src/is_safe_command.rs` | 安全命令检测（推断） |
| `codex-rs/core/src/tools/handlers/shell.rs:166-176` | 命令变异检测 |

### 安全命令白名单（推断）

基于代码分析，安全命令可能包括：
- 文件查看：`cat`, `less`, `more`, `head`, `tail`
- 目录列表：`ls`, `find`（只读模式）
- 文本搜索：`grep`, `rg`, `ag`
- 版本查询：`--version`, `-v`
- 帮助信息：`--help`, `-h`

```rust
// 推断的安全命令检测逻辑
fn is_known_safe_command(command: &[String]) -> bool {
    if command.is_empty() {
        return false;
    }
    let program = &command[0];
    
    // 检查是否在白名单中
    let whitelist = ["ls", "cat", "grep", "head", "tail", "less", "more"];
    if !whitelist.contains(&program.as_str()) {
        return false;
    }
    
    // 检查参数是否包含危险操作
    for arg in &command[1..] {
        if is_dangerous_arg(arg) {
            return false;
        }
    }
    
    true
}
```

## 依赖与外部交互

### 上游依赖

1. **安全命令检测模块**：`is_safe_command` 模块提供安全命令识别能力
2. **配置系统**：通过 `Config` 中的 `approval_policy` 字段设置

### 下游影响

1. **命令执行流程**：
   - `is_mutating` 检查决定命令是否需要审批
   - 非安全命令触发审批流程

2. **用户体验**：
   - 用户频繁收到审批提示
   - 适合谨慎的操作模式

### 与 `request_permissions` 工具的关系

与 `OnRequest` 类似，当 `request_permissions_tool_enabled` 为 true 时，提示词会追加工具使用说明，允许模型请求额外的沙盒权限。

## 风险、边界与改进建议

### 风险

1. **安全命令定义不完整**：白名单可能遗漏某些安全的只读命令
2. **参数注入攻击**：即使命令本身安全，恶意参数可能导致危险操作
3. **用户疲劳**：频繁的审批提示可能导致用户习惯性点击"批准"

### 边界情况

1. **命令组合**：
   - `cat file | grep pattern` - 管道命令如何评估？
   - 当前实现：每个管道段独立评估

2. **环境依赖**：
   - 某些"安全"命令在特定环境下可能不安全（如 `cat` 读取特殊设备文件）

3. **别名和函数**：
   - 用户定义的 shell 别名可能绕过安全检测

### 改进建议

1. **动态白名单**：
   - 允许用户配置额外的安全命令
   - 基于使用频率动态调整白名单

2. **参数级安全检测**：
   - 不仅检查命令名，还检查参数
   - 阻止危险参数组合（如 `rm -rf /`）

3. **智能学习**：
   - 学习用户的批准模式
   - 建议将频繁批准的命令加入白名单

4. **安全命令增强**：
   - 定期审查和更新安全命令列表
   - 考虑命令的完整路径（防止 PATH 劫持）

5. **用户体验优化**：
   - 提供批量批准选项
   - 允许临时切换到 `OnRequest` 模式

### 相关测试

```rust
// 测试位置参考
codex-rs/core/tests/suite/exec_policy.rs
codex-rs/core/tests/suite/approvals.rs
// 可能存在的安全命令测试
codex-rs/core/src/is_safe_command_tests.rs（推断）
```

### 配置示例

```toml
# config.toml
[permissions]
approval_policy = "untrusted"  # 或 "unless-trusted"

# 用户自定义安全命令（假设功能）
[permissions.safe_commands]
additional = ["mytool", "custom-reader"]
```

### 使用建议

1. **适用场景**：
   - 审查不受信任的代码
   - 生产环境操作
   - 新用户首次使用

2. **注意事项**：
   - 准备好频繁处理审批提示
   - 考虑使用 `prefix_rule` 批准常用命令模式
   - 定期审查已批准的规则

3. **迁移路径**：
   ```rust
   // 从 UnlessTrusted 迁移到 OnRequest
   approval_policy = AskForApproval::OnRequest
   ```
   当用户对 Codex 的行为更加信任后，可以切换到 `OnRequest` 策略以获得更流畅的体验。
