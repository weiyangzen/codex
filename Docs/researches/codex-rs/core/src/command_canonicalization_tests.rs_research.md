# command_canonicalization_tests.rs 深度研究文档

## 场景与职责

`command_canonicalization_tests.rs` 是 `command_canonicalization.rs` 的配套测试文件，负责验证命令规范化功能的正确性。测试覆盖了不同 shell 类型、不同输入格式的命令规范化行为，确保审批缓存能够稳定匹配语义相同的命令。

### 测试覆盖范围

1. **简单 shell 命令规范化** - 验证路径差异和空格差异的处理
2. **Heredoc 脚本规范化** - 验证复杂脚本的稳定键生成
3. **PowerShell 命令规范化** - 验证 Windows 平台命令处理
4. **非 shell 命令保留** - 验证普通命令的原样保留

## 功能点目的

### 1. 确保规范化一致性

验证以下等价命令产生相同的规范化输出：
```bash
# 路径差异
/bin/bash -lc "cargo test -p codex-core"
bash -lc "cargo test -p codex-core"

# 空格差异
cargo   test   -p codex-core
cargo test -p codex-core
```

### 2. 验证脚本内容保留

对于无法安全解析为 token 序列的复杂脚本，验证：
- 完整脚本内容被保留
- 生成稳定的规范化键
- 跨平台行为一致

### 3. 防止回归

通过全面的测试用例，防止未来的代码变更破坏：
- 审批缓存匹配逻辑
- 跨平台命令处理
- 安全关键的路径解析

## 具体技术实现

### 测试用例 1: 简单 shell 命令规范化

**测试函数**: `canonicalizes_word_only_shell_scripts_to_inner_command`

**测试数据**:
```rust
let command_a = vec![
    "/bin/bash".to_string(),
    "-lc".to_string(),
    "cargo test -p codex-core".to_string(),
];
let command_b = vec![
    "bash".to_string(),
    "-lc".to_string(),
    "cargo   test   -p codex-core".to_string(),
];
```

**期望输出**:
```rust
vec![
    "cargo".to_string(),
    "test".to_string(),
    "-p".to_string(),
    "codex-core".to_string(),
]
```

**验证点**:
- `/bin/bash` 和 `bash` 被统一处理
- 多余空格被规范化
- 命令被正确解析为 token 序列

### 测试用例 2: Heredoc 脚本规范化

**测试函数**: `canonicalizes_heredoc_scripts_to_stable_script_key`

**测试数据**:
```rust
let script = "python3 <<'PY'\nprint('hello')\nPY";
let command_a = vec!["/bin/zsh".to_string(), "-lc".to_string(), script.to_string()];
let command_b = vec!["zsh".to_string(), "-lc".to_string(), script.to_string()];
```

**期望输出**:
```rust
vec![
    "__codex_shell_script__".to_string(),
    "-lc".to_string(),
    script.to_string(),
]
```

**关键验证**:
```rust
assert_eq!(
    canonicalize_command_for_approval(&command_a),
    canonicalize_command_for_approval(&command_b)
);
```

### 测试用例 3: PowerShell 命令规范化

**测试函数**: `canonicalizes_powershell_wrappers_to_stable_script_key`

**测试数据**:
```rust
let script = "Write-Host hi";
let command_a = vec![
    "powershell.exe".to_string(),
    "-NoProfile".to_string(),
    "-Command".to_string(),
    script.to_string(),
];
let command_b = vec![
    "powershell".to_string(),
    "-Command".to_string(),
    script.to_string(),
];
```

**期望输出**:
```rust
vec![
    "__codex_powershell_script__".to_string(),
    script.to_string(),
]
```

**注意**: PowerShell 规范化不包含 shell 模式参数（如 `-NoProfile`），这与 Bash 处理不同。

### 测试用例 4: 非 shell 命令保留

**测试函数**: `preserves_non_shell_commands`

**测试数据**:
```rust
let command = vec!["cargo".to_string(), "fmt".to_string()];
```

**期望输出**:
```rust
assert_eq!(canonicalize_command_for_approval(&command), command);
```

## 关键代码路径与文件引用

### 被测试函数

```rust
use super::canonicalize_command_for_approval;
```

来自父模块 `command_canonicalization.rs`。

### 测试断言库

```rust
use pretty_assertions::assert_eq;
```

提供清晰的测试失败输出，便于调试。

### 测试模块结构

```rust
// command_canonicalization.rs
#[cfg(test)]
#[path = "command_canonicalization_tests.rs"]
mod tests;
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `command_canonicalization` | 被测试的规范化函数 |
| `pretty_assertions` | 测试断言美化 |

### 无外部 Crate 依赖

测试仅依赖标准库和内部模块。

## 风险、边界与改进建议

### 当前风险点

1. **测试覆盖有限**: 仅覆盖 4 种主要场景，缺少边界情况测试
   - 空命令
   - 单元素命令
   - 特殊字符处理
   - 超长命令

2. **平台假设**: 测试假设 `parse_shell_lc_plain_commands` 的行为，但未直接测试该函数

3. **硬编码前缀**: 测试依赖 `__codex_shell_script__` 和 `__codex_powershell_script__` 前缀，如果主模块变更，测试需要同步更新

### 边界情况未覆盖

1. **空输入**:
   ```rust
   let command: Vec<String> = vec![];
   // 未测试
   ```

2. **单元素命令**:
   ```rust
   let command = vec!["ls".to_string()];
   // 未测试
   ```

3. **特殊字符**:
   ```rust
   let command = vec!["bash".to_string(), "-c".to_string(), "echo 'hello; world'".to_string()];
   // 未测试
   ```

4. **嵌套 shell**:
   ```rust
   let command = vec!["bash".to_string(), "-c".to_string(), "bash -c 'echo hi'".to_string()];
   // 未测试
   ```

### 改进建议

1. **增加边界测试**:
   ```rust
   #[test]
   fn handles_empty_command() {
       let command: Vec<String> = vec![];
       assert_eq!(canonicalize_command_for_approval(&command), command);
   }

   #[test]
   fn handles_single_element() {
       let command = vec!["ls".to_string()];
       assert_eq!(canonicalize_command_for_approval(&command), command);
   }
   ```

2. **增加错误处理测试**:
   ```rust
   #[test]
   fn handles_malformed_shell_command() {
       // bash 没有 -c 参数的情况
       let command = vec!["bash".to_string(), "script.sh".to_string()];
       // 验证行为
   }
   ```

3. **参数化测试**: 使用 `rstest` 或类似库减少重复代码
   ```rust
   #[rstest]
   #[case(vec!["/bin/bash", "-c", "echo hi"], vec!["echo", "hi"])]
   #[case(vec!["bash", "-c", "echo hi"], vec!["echo", "hi"])]
   #[case(vec!["/usr/bin/bash", "-c", "echo hi"], vec!["echo", "hi"])]
   fn test_shell_canonicalization(#[case] input: Vec<&str>, #[case] expected: Vec<&str>) {
       // ...
   }
   ```

4. **文档测试**: 在 `canonicalize_command_for_approval` 函数上添加文档测试示例
   ```rust
   /// # Examples
   /// ```
   /// let command = vec!["bash".to_string(), "-c".to_string(), "echo hi".to_string()];
   /// let canonical = canonicalize_command_for_approval(&command);
   /// assert_eq!(canonical, vec!["echo".to_string(), "hi".to_string()]);
   /// ```
   ```

5. **性能测试**: 添加基准测试验证规范化性能
   ```rust
   #[bench]
   fn bench_canonicalize_long_command(b: &mut Bencher) {
       let command = vec!["bash".to_string(), "-c".to_string(), "a".repeat(10000)];
       b.iter(|| canonicalize_command_for_approval(&command));
   }
   ```

### 相关文档

- `command_canonicalization.rs` - 主实现文件
- `bash.rs` - Bash 解析实现
- `powershell.rs` - PowerShell 解析实现
