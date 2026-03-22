# command_canonicalization.rs 深度研究文档

## 场景与职责

`command_canonicalization.rs` 实现了命令参数的**规范化（Canonicalization）**功能，核心目标是解决**审批缓存匹配**中的命令表示不一致问题。

### 问题背景

在 Codex 的审批系统中，用户可能会以不同方式输入相同的命令：
- `/bin/bash -lc "cargo test"` vs `bash -lc "cargo test"`
- `powershell.exe -Command "script"` vs `powershell -Command "script"`
- 空格差异：`cargo   test` vs `cargo test`

这些差异会导致审批缓存无法正确匹配已批准的命令，造成重复审批请求，打断用户体验。

### 核心职责

1. **消除路径差异**: 将 `/bin/bash` 和 `bash` 统一识别为相同的 shell
2. **提取内联命令**: 从 shell 包装器中解析出实际执行的命令
3. **保留脚本完整性**: 对于复杂脚本，保留完整脚本内容而非强行解析
4. **跨平台支持**: 同时支持 Bash/Zsh 和 PowerShell 命令

## 功能点目的

### 1. 审批缓存稳定性

通过规范化，确保以下命令产生相同的缓存键：
```bash
# 不同输入形式
/bin/bash -lc "echo hello"
bash -lc "echo hello"
/usr/bin/bash -lc "echo hello"

# 规范化后
echo hello
```

### 2. 安全与精确的平衡

- **简单命令**: 解析为 token 序列，精确匹配每个参数
- **复杂脚本**: 保留完整脚本内容，避免因解析错误导致的安全问题

### 3. 跨 shell 统一

支持多种 shell 的规范化：
- Bash/Zsh/Sh: `-c` 或 `-lc` 参数
- PowerShell: `-Command` 参数

## 具体技术实现

### 常量定义

```rust
/// Bash 脚本规范化的前缀标识
const CANONICAL_BASH_SCRIPT_PREFIX: &str = "__codex_shell_script__";

/// PowerShell 脚本规范化的前缀标识
const CANONICAL_POWERSHELL_SCRIPT_PREFIX: &str = "__codex_powershell_script__";
```

这些前缀用于区分：
- 普通命令序列
- 需要保留完整内容的 Bash 脚本
- 需要保留完整内容的 PowerShell 脚本

### 核心函数

```rust
/// 为审批缓存匹配规范化命令参数
pub(crate) fn canonicalize_command_for_approval(command: &[String]) -> Vec<String> {
    // 尝试 1: 解析简单 shell 命令
    if let Some(commands) = parse_shell_lc_plain_commands(command)
        && let [single_command] = commands.as_slice()
    {
        return single_command.clone();
    }

    // 尝试 2: 提取 Bash 脚本
    if let Some((_shell, script)) = extract_bash_command(command) {
        let shell_mode = command.get(1).cloned().unwrap_or_default();
        return vec![
            CANONICAL_BASH_SCRIPT_PREFIX.to_string(),
            shell_mode,
            script.to_string(),
        ];
    }

    // 尝试 3: 提取 PowerShell 脚本
    if let Some((_shell, script)) = extract_powershell_command(command) {
        return vec![
            CANONICAL_POWERSHELL_SCRIPT_PREFIX.to_string(),
            script.to_string(),
        ];
    }

    // 回退: 返回原始命令
    command.to_vec()
}
```

### 解析策略优先级

```
输入命令
    │
    ▼
┌─────────────────────────────────────┐
│ 1. 尝试 parse_shell_lc_plain_commands │
│    - 解析 "bash -lc 'simple command'" │
│    - 返回: ["simple", "command"]       │
└─────────────────────────────────────┘
    │ 失败
    ▼
┌─────────────────────────────────────┐
│ 2. 尝试 extract_bash_command          │
│    - 提取 heredoc 或复杂脚本          │
│    - 返回: ["__codex_shell_script__", │
│             "-lc", "script content"]  │
└─────────────────────────────────────┘
    │ 失败
    ▼
┌─────────────────────────────────────┐
│ 3. 尝试 extract_powershell_command    │
│    - 提取 PowerShell 脚本             │
│    - 返回: ["__codex_powershell_script__", │
│             "script content"]          │
└─────────────────────────────────────┘
    │ 失败
    ▼
┌─────────────────────────────────────┐
│ 4. 回退: 返回原始命令                 │
└─────────────────────────────────────┘
```

### 依赖的解析函数

| 函数 | 来源模块 | 用途 |
|------|----------|------|
| `parse_shell_lc_plain_commands` | `bash` | 解析简单 shell 命令为 token 序列 |
| `extract_bash_command` | `bash` | 提取 Bash 脚本内容 |
| `extract_powershell_command` | `powershell` | 提取 PowerShell 脚本内容 |

## 关键代码路径与文件引用

### 调用方

```rust
// tools/runtimes/shell.rs
use crate::command_canonicalization::canonicalize_command_for_approval;

// 在 ApprovalKey 构造中使用
#[derive(serde::Serialize, Clone, Debug, Eq, PartialEq, Hash)]
pub(crate) struct ApprovalKey {
    command: Vec<String>,  // 使用规范化后的命令
    cwd: PathBuf,
    sandbox_permissions: SandboxPermissions,
    additional_permissions: Option<PermissionProfile>,
}
```

### 测试模块

```rust
#[cfg(test)]
#[path = "command_canonicalization_tests.rs"]
mod tests;
```

测试文件路径: `codex-rs/core/src/command_canonicalization_tests.rs`

## 依赖与外部交互

### 内部模块依赖

```
command_canonicalization.rs
├── bash.rs
│   ├── extract_bash_command
│   └── parse_shell_lc_plain_commands
└── powershell.rs
    └── extract_powershell_command
```

### 外部 Crate

无直接外部依赖，仅使用标准库 `Vec<String>`。

### 模块可见性

- `pub(crate)` - 仅在 crate 内部使用
- 不暴露给外部调用者

## 风险、边界与改进建议

### 当前风险点

1. **前缀冲突风险**: `__codex_shell_script__` 是硬编码前缀，如果用户实际命令包含此字符串，可能导致误判
   ```rust
   // 潜在冲突场景
   vec!["__codex_shell_script__", "-c", "actual script"]
   // 可能被误认为是规范化后的命令
   ```

2. **解析函数依赖**: 依赖 `bash` 和 `powershell` 模块的解析函数，这些函数的行为变更会直接影响规范化结果

3. **空格处理**: 当前实现不处理命令参数内部的额外空格（如 `cargo   test`），这部分由调用方的解析函数处理

### 边界情况

1. **空命令**: 输入空 `Vec` 时返回空 `Vec`
2. **非 shell 命令**: 如 `cargo build` 直接返回原命令
3. **嵌套 shell**: `bash -lc "bash -lc 'echo hi'"` 的解析行为取决于 `parse_shell_lc_plain_commands`

### 改进建议

1. **前缀命名空间**: 使用更独特的前缀避免冲突
   ```rust
   const CANONICAL_BASH_SCRIPT_PREFIX: &str = "__CODEX_INTERNAL_BASH_SCRIPT__";
   ```

2. **版本标记**: 在规范化输出中包含版本信息，便于未来格式升级
   ```rust
   vec![
       "__codex_shell_script_v1__".to_string(),
       shell_mode,
       script.to_string(),
   ]
   ```

3. **哈希优化**: 对于长脚本，考虑使用哈希值作为缓存键
   ```rust
   if script.len() > 1000 {
       let hash = sha256(&script);
       vec![prefix, shell_mode, hash]
   }
   ```

4. **更多 shell 支持**: 增加对 Fish、NuShell 等新兴 shell 的支持

5. **配置化前缀**: 允许通过配置自定义前缀，避免特定环境下的冲突

### 相关文档

- `command_canonicalization_tests.rs` - 详细测试用例
- `bash.rs` - Bash 命令解析实现
- `powershell.rs` - PowerShell 命令解析实现
- `tools/runtimes/shell.rs` - 审批缓存使用方
