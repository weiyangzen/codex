# sandbox_tags_tests.rs 研究文档

## 场景与职责

本文件是 `sandbox_tags.rs` 的配套测试模块，负责**验证沙盒标签生成逻辑的正确性**。通过单元测试确保 `sandbox_tag` 函数在各种策略和平台配置下返回预期的标签值。

**核心职责**：
- 验证特殊策略（DangerFullAccess、ExternalSandbox）的标签覆盖
- 测试平台默认沙盒标签的正确性
- 确保标签逻辑在不同配置下的一致性

## 功能点目的

### 1. DangerFullAccess 标签测试
验证 `DangerFullAccess` 策略始终返回 `"none"` 标签，即使在 Linux 平台（默认有沙盒）也是如此。

### 2. ExternalSandbox 标签测试
验证 `ExternalSandbox` 策略始终返回 `"external"` 标签，不受平台默认影响。

### 3. 平台默认沙盒标签测试
验证默认沙盒策略使用平台特定的标签（Linux 上为 `"seccomp"`）。

## 具体技术实现

### 测试结构

```rust
use super::sandbox_tag;
use crate::exec::SandboxType;
use crate::protocol::SandboxPolicy;
use crate::safety::get_platform_sandbox;
use codex_protocol::config_types::WindowsSandboxLevel;
use codex_protocol::protocol::NetworkAccess;
use pretty_assertions::assert_eq;
```

### 测试用例详解

#### 1. DangerFullAccess 标签测试
```rust
#[test]
fn danger_full_access_is_untagged_even_when_linux_sandbox_defaults_apply() {
    let actual = sandbox_tag(
        &SandboxPolicy::DangerFullAccess,
        WindowsSandboxLevel::Disabled,
    );
    assert_eq!(actual, "none");
}
```

**测试意图**：
- `DangerFullAccess` 应始终标记为 `"none"`
- 即使在 Linux 平台（默认有 Seccomp 沙盒）
- 表示无沙盒保护，最高风险级别

#### 2. ExternalSandbox 标签测试
```rust
#[test]
fn external_sandbox_keeps_external_tag_when_linux_sandbox_defaults_apply() {
    let actual = sandbox_tag(
        &SandboxPolicy::ExternalSandbox {
            network_access: NetworkAccess::Enabled,
        },
        WindowsSandboxLevel::Disabled,
    );
    assert_eq!(actual, "external");
}
```

**测试意图**：
- `ExternalSandbox` 应始终标记为 `"external"`
- 表示使用用户配置的外部沙盒
- 与平台默认沙盒区分

#### 3. 平台默认沙盒标签测试
```rust
#[test]
fn default_linux_sandbox_uses_platform_sandbox_tag() {
    let actual = sandbox_tag(
        &SandboxPolicy::new_read_only_policy(),
        WindowsSandboxLevel::Disabled,
    );
    let expected = get_platform_sandbox(false)
        .map(SandboxType::as_metric_tag)
        .unwrap_or("none");
    assert_eq!(actual, expected);
}
```

**测试意图**：
- 默认只读策略应使用平台沙盒标签
- Linux 上预期为 `"seccomp"`
- macOS 上预期为 `"seatbelt"`
- Windows 上取决于配置

### 测试策略

| 测试 | 策略 | Windows 级别 | 预期标签 |
|-----|------|-------------|---------|
| danger_full_access | DangerFullAccess | Disabled | `"none"` |
| external_sandbox | ExternalSandbox | Disabled | `"external"` |
| default_linux | ReadOnly (default) | Disabled | 平台依赖 |

## 关键代码路径与文件引用

### 被测试的函数
```rust
// sandbox_tags.rs
pub(crate) fn sandbox_tag(
    policy: &SandboxPolicy,
    windows_sandbox_level: WindowsSandboxLevel,
) -> &'static str
```

### 测试模块声明
```rust
// sandbox_tags.rs (line 26-28)
#[cfg(test)]
#[path = "sandbox_tags_tests.rs"]
mod tests;
```

### 依赖类型
```rust
use super::sandbox_tag;  // 被测函数
use crate::exec::SandboxType;  // 沙盒类型
use crate::protocol::SandboxPolicy;  // 策略类型
use crate::safety::get_platform_sandbox;  // 平台检测
use codex_protocol::config_types::WindowsSandboxLevel;  // Windows 配置
use codex_protocol::protocol::NetworkAccess;  // 网络访问配置
```

## 依赖与外部交互

### 测试依赖
| 依赖 | 用途 |
|-----|------|
| `pretty_assertions::assert_eq` | 清晰的测试失败输出 |
| `super::*` | 被测模块的所有导出 |

### 被测代码
- `sandbox_tags.rs` 的 `sandbox_tag` 函数
- `safety.rs` 的 `get_platform_sandbox` 函数
- `exec.rs` 的 `SandboxType::as_metric_tag`

### 无外部 IO
- 纯计算逻辑测试，无副作用
- 不访问文件系统、网络或环境变量

## 风险、边界与改进建议

### 潜在风险

1. **平台依赖测试**
   - `default_linux_sandbox_uses_platform_sandbox_tag` 在不同平台行为不同
   - CI 可能在不同平台运行，需要确保测试通过

2. **测试覆盖不足**
   - 缺少 Windows 平台特定测试
   - 缺少 `WindowsSandboxLevel::Elevated` 测试
   - 缺少所有策略变体的测试

3. **硬编码预期值**
   - 测试依赖 `"none"`、`"external"` 等字符串
   - 标签值变更需要同步更新测试

### 边界限制

1. **编译时平台检测**
   - `get_platform_sandbox` 使用 `cfg!` 宏
   - 测试在编译平台上运行，无法跨平台测试

2. **静态标签验证**
   - 仅验证标签字符串值
   - 不验证标签语义正确性

3. **无集成验证**
   - 不验证标签在遥测系统中的实际使用
   - 不验证 UI 显示效果

### 改进建议

1. **增加平台特定测试**
   ```rust
   #[cfg(target_os = "windows")]
   #[test]
   fn windows_elevated_returns_elevated_tag() {
       let actual = sandbox_tag(
           &SandboxPolicy::new_read_only_policy(),
           WindowsSandboxLevel::Elevated,
       );
       assert_eq!(actual, "windows_elevated");
   }
   
   #[cfg(target_os = "macos")]
   #[test]
   fn macos_default_returns_seatbelt_tag() {
       let actual = sandbox_tag(
           &SandboxPolicy::new_read_only_policy(),
           WindowsSandboxLevel::Disabled,
       );
       assert_eq!(actual, "seatbelt");
   }
   ```

2. **参数化测试**
   ```rust
   // 使用 rstest 简化测试
   #[rstest]
   #[case(SandboxPolicy::DangerFullAccess, "none")]
   #[case(SandboxPolicy::ExternalSandbox { ... }, "external")]
   fn test_sandbox_tags(#[case] policy: SandboxPolicy, #[case] expected: &str) {
       assert_eq!(sandbox_tag(&policy, WindowsSandboxLevel::Disabled), expected);
   }
   ```

3. **标签常量化**
   ```rust
   // 在代码中定义常量
   pub const SANDBOX_TAG_NONE: &str = "none";
   pub const SANDBOX_TAG_EXTERNAL: &str = "external";
   pub const SANDBOX_TAG_SEATBELT: &str = "seatbelt";
   pub const SANDBOX_TAG_SECCOMP: &str = "seccomp";
   
   // 测试中使用常量
   assert_eq!(actual, SANDBOX_TAG_NONE);
   ```

4. **增加边界测试**
   ```rust
   #[test]
   fn all_sandbox_policies_produce_valid_tags() {
       // 遍历所有策略变体
       for policy in all_sandbox_policies() {
           let tag = sandbox_tag(&policy, WindowsSandboxLevel::Disabled);
           assert!(is_valid_sandbox_tag(tag));
       }
   }
   ```

5. **文档测试**
   ```rust
   /// Returns a metric tag for the sandbox configuration.
   ///
   /// # Examples
   ///
   /// ```
   /// use codex_core::sandbox_tags::sandbox_tag;
   /// use codex_protocol::protocol::SandboxPolicy;
   ///
   /// let tag = sandbox_tag(&SandboxPolicy::DangerFullAccess, ...);
   /// assert_eq!(tag, "none");
   /// ```
   pub(crate) fn sandbox_tag(...) -> &'static str { ... }
   ```

6. **集成测试建议**
   - 验证标签在遥测事件中的正确记录
   - 验证标签在日志中的格式
   - 验证 UI 对标签的显示处理
