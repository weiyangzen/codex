# mod_tests.rs 深入研究

## 场景与职责

`mod_tests.rs` 是 `tools/runtimes/mod.rs` 的单元测试模块，专注于测试 shell 快照包装功能 `maybe_wrap_shell_lc_with_snapshot`。该测试文件仅在 Unix 平台编译（`#[cfg(all(test, unix))]`），因为 shell 快照功能主要针对 Bash/Zsh/sh 等 Unix shell。

**测试覆盖范围：**
1. **基本重写逻辑**：验证 shell 命令正确重写为带快照的版本
2. **引号转义**：验证单引号在脚本中的正确处理
3. **Shell 类型适配**：验证 Bash、Zsh、sh 的不同处理
4. **参数保留**：验证尾部参数正确传递
5. **CWD 匹配**：验证工作目录匹配逻辑
6. **环境覆盖**：验证显式环境变量覆盖的正确优先级

---

## 功能点目的

### 测试辅助函数

```rust
fn shell_with_snapshot(
    shell_type: ShellType,
    shell_path: &str,
    snapshot_path: PathBuf,
    snapshot_cwd: PathBuf,
) -> Shell
```

**用途**：构造带快照的 `Shell` 实例，用于测试。

**实现细节：**
- 使用 `tokio::sync::watch::channel` 创建快照通道
- 构造 `ShellSnapshot { path, cwd }`
- 返回配置好的 `Shell` 结构

### 测试 1: 基本重写逻辑

```rust
#[test]
fn maybe_wrap_shell_lc_with_snapshot_bootstraps_in_user_shell()
```

**验证点：**
- 重写后的命令使用用户 shell（如 `/bin/zsh`）而非原始 shell
- 使用 `-c` 标志替代 `-lc`
- 脚本包含 `if . '<snapshot>'` 和 `exec '<original_shell>' -c '<script>'`

**示例：**
```rust
let command = vec!["/bin/bash".to_string(), "-lc".to_string(), "echo hello".to_string()];
// 重写后:
// ["/bin/zsh", "-c", "if . '/tmp/.../snapshot.sh' >/dev/null 2>&1; then :; fi\n\nexec '/bin/bash' -c 'echo hello'"]
```

### 测试 2: 单引号转义

```rust
#[test]
fn maybe_wrap_shell_lc_with_snapshot_escapes_single_quotes()
```

**验证点：**
- 脚本中的单引号正确转义为 `'"'"'`
- 防止注入攻击或语法错误

**示例：**
```rust
let command = vec!["...", "-lc", "echo 'hello'".to_string()];
// 重写后包含: exec '/bin/bash' -c 'echo '"'"'hello'"'"''
```

### 测试 3-5: 不同 Shell 类型

```rust
fn maybe_wrap_shell_lc_with_snapshot_uses_bash_bootstrap_shell()  // Bash
fn maybe_wrap_shell_lc_with_snapshot_uses_sh_bootstrap_shell()    // sh
fn maybe_wrap_shell_lc_with_snapshot_uses_zsh_bootstrap_shell()   // Zsh (implied)
```

**验证点：**
- 重写后的命令使用 session shell 作为引导 shell
- 原始 shell 作为 `exec` 的参数保留

### 测试 6: 尾部参数保留

```rust
#[test]
fn maybe_wrap_shell_lc_with_snapshot_preserves_trailing_args()
```

**验证点：**
- `$0`, `$1` 等位置参数正确传递
- 格式：`'arg0' 'arg1'`

**示例：**
```rust
let command = vec!["...", "-lc", "printf '%s %s' \"$0\" \"$1\"", "arg0", "arg1"];
// 重写后: exec '...' -c '...' 'arg0' 'arg1'
```

### 测试 7: CWD 不匹配跳过

```rust
#[test]
fn maybe_wrap_shell_lc_with_snapshot_skips_when_cwd_mismatch()
```

**验证点：**
- 当命令 CWD 与快照 CWD 不同时，原样返回命令
- 防止在错误目录加载快照环境

### 测试 8: 点别名 CWD 处理

```rust
#[test]
fn maybe_wrap_shell_lc_with_snapshot_accepts_dot_alias_cwd()
```

**验证点：**
- `./` 或 `.` 形式的 CWD 正确规范化后匹配
- 路径规范化使用 `path_utils::normalize_for_path_comparison`

### 测试 9-12: 环境变量覆盖

```rust
fn maybe_wrap_shell_lc_with_snapshot_restores_explicit_override_precedence()
fn maybe_wrap_shell_lc_with_snapshot_keeps_snapshot_path_without_override()
fn maybe_wrap_shell_lc_with_snapshot_applies_explicit_path_override()
fn maybe_wrap_shell_lc_with_snapshot_does_not_embed_override_values_in_argv()
fn maybe_wrap_shell_lc_with_snapshot_preserves_unset_override_variables()
```

**核心机制验证：**

1. **优先级**：显式覆盖 > 快照值 > 原始环境
2. **安全性**：敏感值（如 `OPENAI_API_KEY`）不嵌入命令行
3. **取消设置**：支持将变量恢复为未设置状态

**实现机制：**
```bash
# 1. 保存原始状态
__CODEX_SNAPSHOT_OVERRIDE_SET_0="${PATH+x}"
__CODEX_SNAPSHOT_OVERRIDE_0="${PATH-}"

# 2. Source 快照（可能修改 PATH）
if . '/tmp/snapshot.sh' >/dev/null 2>&1; then :; fi

# 3. 恢复显式覆盖
if [ -n "${__CODEX_SNAPSHOT_OVERRIDE_SET_0}" ]; then
    export PATH="${__CODEX_SNAPSHOT_OVERRIDE_0}"
else
    unset PATH
fi
```

---

## 具体技术实现

### 测试框架

**依赖：**
```rust
use super::*;
use crate::shell::ShellType;
use crate::shell_snapshot::ShellSnapshot;
use pretty_assertions::assert_eq;
use std::path::PathBuf;
use std::process::Command;
use std::sync::Arc;
use tempfile::tempdir;
use tokio::sync::watch;
```

**关键 crate：**
- `tempfile::tempdir`: 创建临时目录存放快照文件
- `std::process::Command`: 实际执行重写后的命令验证行为
- `pretty_assertions::assert_eq`: 清晰的测试失败输出

### 真实执行验证

多个测试使用 `Command::new(&rewritten[0]).args(&rewritten[1..]).output()` 实际执行命令：

```rust
let output = Command::new(&rewritten[0])
    .args(&rewritten[1..])
    .env("TEST_ENV_SNAPSHOT", "worktree")
    .output()
    .expect("run rewritten command");

assert!(output.status.success());
assert_eq!(String::from_utf8_lossy(&output.stdout), "worktree|from_snapshot");
```

**优点：**
- 验证重写后的命令实际可执行
- 验证环境变量处理逻辑正确
- 集成测试级别的信心

### 快照文件创建

```rust
let dir = tempdir().expect("create temp dir");
let snapshot_path = dir.path().join("snapshot.sh");
std::fs::write(
    &snapshot_path,
    "# Snapshot file\nexport PATH='/snapshot/bin'\n",
).expect("write snapshot");
```

---

## 关键代码路径与文件引用

### 被测试代码

| 函数 | 源文件 | 行号 |
|------|--------|------|
| `maybe_wrap_shell_lc_with_snapshot` | mod.rs | 68-127 |
| `build_override_exports` | mod.rs | 129-162 |
| `is_valid_shell_variable_name` | mod.rs | 164-173 |
| `shell_single_quote` | mod.rs | 175-177 |

### 测试文件位置

```rust
// mod.rs 末尾
#[cfg(all(test, unix))]
#[path = "mod_tests.rs"]
mod tests;
```

### 依赖类型

| 类型 | 来源 |
|------|------|
| `Shell` | `crate::shell` |
| `ShellType` | `crate::shell` |
| `ShellSnapshot` | `crate::shell_snapshot` |

---

## 依赖与外部交互

### 外部 crate

| Crate | 用途 |
|-------|------|
| `tempfile` | 临时目录创建 |
| `tokio::sync::watch` | Shell 快照通道模拟 |
| `pretty_assertions` | 测试断言美化 |

### 系统依赖

- 需要系统中存在 `/bin/bash`, `/bin/zsh`, `/bin/sh`
- 测试会实际执行这些 shell

### 平台限制

```rust
#[cfg(all(test, unix))]
```

- 仅在 Unix 平台编译和运行
- Windows 不支持 shell 快照功能

---

## 风险、边界与改进建议

### 测试可靠性风险

1. **系统 Shell 依赖**
   - **风险**：测试依赖 `/bin/bash`, `/bin/zsh`, `/bin/sh` 存在
   - **缓解**：这些路径在标准 Unix 系统上通常存在
   - **建议**：使用 `which` 或 `env` 动态发现 shell 路径

2. **环境敏感性**
   - **风险**：测试执行受外部环境变量影响
   - **缓解**：测试使用显式 `env()` 设置控制环境
   - **建议**：考虑使用 `env_clear()` 完全隔离环境

3. **并发执行**
   - **风险**：`tempdir()` 创建的全局临时目录名可能冲突
   - **缓解**：`tempfile` crate 使用随机名称，冲突概率极低

### 测试覆盖缺口

| 缺口 | 风险 | 建议 |
|------|------|------|
| 无 Windows 测试 | Windows 行为未验证 | 添加 Windows 特定测试或文档化不支持 |
| 无无效变量名测试 | `is_valid_shell_variable_name` 未直接测试 | 添加边界测试（空字符串、数字开头等）|
| 无大脚本测试 | 超长脚本处理未验证 | 测试命令行长度边界 |
| 无并发测试 | 多线程环境下快照通道行为未验证 | 添加并发场景测试 |

### 改进建议

1. **参数化测试**
   ```rust
   // 使用 rstest 简化重复模式
   #[rstest]
   #[case(ShellType::Bash, "/bin/bash")]
   #[case(ShellType::Zsh, "/bin/zsh")]
   #[case(ShellType::Sh, "/bin/sh")]
   fn test_various_shells(#[case] shell_type: ShellType, #[case] path: &str) { ... }
   ```

2. **错误场景测试**
   ```rust
   #[test]
   fn handles_missing_snapshot_file() { ... }
   
   #[test]
   fn handles_malformed_command() { ... }
   ```

3. **性能基准**
   - 当前：无性能测试
   - 建议：添加基准测试，确保重写逻辑不会成为性能瓶颈

4. **文档化测试意图**
   ```rust
   /// Test: When explicit env overrides are provided, they should take precedence
   /// over values set in the shell snapshot.
   /// 
   /// Scenario: User has PATH set in snapshot, but explicitly requests different PATH
   #[test]
   fn maybe_wrap_shell_lc_with_snapshot_restores_explicit_override_precedence() { ... }
   ```

### 维护建议

1. **快照格式版本化**
   - 如果快照文件格式变更，需要同步更新测试
   - 建议：定义明确的快照格式版本

2. **Shell 兼容性矩阵**
   - 记录测试过的 shell 版本
   - 不同 shell 版本可能有不同行为

3. **CI 环境验证**
   - 确保 CI 环境有所需的 shell
   - 考虑容器化测试环境
