# sandbox_tags.rs 研究文档

## 场景与职责

本文件负责**生成沙盒类型的指标标签（metric tags）**，用于遥测和监控。它将内部的 `SandboxPolicy` 和平台配置映射为简洁的字符串标识，便于在日志、指标和 UI 中识别当前使用的沙盒机制。

**核心职责**：
- 根据沙盒策略生成标准化的标签字符串
- 处理特殊策略（DangerFullAccess、ExternalSandbox）的覆盖逻辑
- 支持 Windows 平台的特殊沙盒级别处理
- 为遥测系统提供一致的沙盒标识

## 功能点目的

### 1. 沙盒标签生成 (`sandbox_tag`)
将 `SandboxPolicy` 和 `WindowsSandboxLevel` 转换为标签字符串：

| 策略 | 标签 |
|-----|------|
| `DangerFullAccess` | `"none"` |
| `ExternalSandbox` | `"external"` |
| Windows + `Elevated` | `"windows_elevated"` |
| 平台默认 | `"seatbelt"` / `"seccomp"` / `"windows_sandbox"` / `"none"` |

### 2. 平台沙盒检测
通过 `get_platform_sandbox` 获取当前平台可用的沙盒类型，并映射为标签。

## 具体技术实现

### 核心函数

```rust
pub(crate) fn sandbox_tag(
    policy: &SandboxPolicy,
    windows_sandbox_level: WindowsSandboxLevel,
) -> &'static str
```

#### 决策逻辑

```rust
pub(crate) fn sandbox_tag(
    policy: &SandboxPolicy,
    windows_sandbox_level: WindowsSandboxLevel,
) -> &'static str {
    // 1. DangerFullAccess 始终返回 "none"
    if matches!(policy, SandboxPolicy::DangerFullAccess) {
        return "none";
    }
    
    // 2. ExternalSandbox 始终返回 "external"
    if matches!(policy, SandboxPolicy::ExternalSandbox { .. }) {
        return "external";
    }
    
    // 3. Windows Elevated 特殊处理
    if cfg!(target_os = "windows") && matches!(windows_sandbox_level, WindowsSandboxLevel::Elevated) {
        return "windows_elevated";
    }
    
    // 4. 平台默认沙盒
    get_platform_sandbox(windows_sandbox_level != WindowsSandboxLevel::Disabled)
        .map(SandboxType::as_metric_tag)
        .unwrap_or("none")
}
```

### 标签映射表

```rust
// exec.rs 中 SandboxType::as_metric_tag 实现
impl SandboxType {
    pub(crate) fn as_metric_tag(self) -> &'static str {
        match self {
            SandboxType::None => "none",
            SandboxType::MacosSeatbelt => "seatbelt",
            SandboxType::LinuxSeccomp => "seccomp",
            SandboxType::WindowsRestrictedToken => "windows_sandbox",
        }
    }
}
```

### 完整标签语义

| 标签 | 含义 |
|-----|------|
| `"none"` | 无沙盒（DangerFullAccess 或平台不支持） |
| `"external"` | 用户配置的外部沙盒 |
| `"seatbelt"` | macOS Seatbelt 沙盒 |
| `"seccomp"` | Linux Seccomp + Landlock 沙盒 |
| `"windows_sandbox"` | Windows 受限令牌沙盒 |
| `"windows_elevated"` | Windows 提升权限模式 |

## 关键代码路径与文件引用

### 调用关系
```
telemetry/metrics.rs (推测)
  └── sandbox_tag()  [生成指标标签]

config/mod.rs (推测)
  └── sandbox_tag()  [配置验证]
```

### 依赖关系
```rust
// 输入
use crate::exec::SandboxType;
use crate::protocol::SandboxPolicy;
use crate::safety::get_platform_sandbox;
use codex_protocol::config_types::WindowsSandboxLevel;

// 输出
&'static str  // 标签字符串
```

### 相关文件
- `exec.rs` - 定义 `SandboxType` 和 `as_metric_tag`
- `safety.rs` - 提供 `get_platform_sandbox`
- `protocol/src/protocol.rs` - 定义 `SandboxPolicy`

## 依赖与外部交互

### 输入依赖
| 依赖 | 来源 | 用途 |
|-----|------|------|
| `SandboxPolicy` | `protocol` | 沙盒策略配置 |
| `WindowsSandboxLevel` | `protocol::config_types` | Windows 特定配置 |
| `SandboxType` | `exec` | 平台沙盒类型 |
| `get_platform_sandbox` | `safety` | 平台检测 |

### 输出消费者
- **遥测系统**: 记录沙盒使用统计
- **日志系统**: 标记日志条目
- **UI**: 显示当前沙盒状态

### 无外部 IO
- 纯计算函数，无副作用
- 不访问文件系统、网络或环境变量

## 风险、边界与改进建议

### 潜在风险

1. **标签冲突**
   - `"none"` 既表示 DangerFullAccess，也表示平台不支持
   - 可能导致监控数据混淆

2. **平台检测依赖**
   - 依赖编译时 `cfg!` 宏，无法动态适应
   - 交叉编译时可能产生误导标签

3. **Windows 复杂性**
   - Windows 有两个标签：`"windows_sandbox"` 和 `"windows_elevated"`
   - 逻辑分散在 `sandbox_tag` 和 `as_metric_tag` 中

### 边界限制

1. **静态标签**
   - 返回 `&'static str`，无法动态生成
   - 不支持自定义标签

2. **单一维度**
   - 只反映沙盒类型，不反映策略细节
   - 如 `FileSystemSandboxPolicy` 的复杂配置无法从标签推断

3. **无版本信息**
   - 标签不包含沙盒实现版本
   - 无法区分不同版本的 Seatbelt/Seccomp 策略

### 改进建议

1. **标签细化**
   ```rust
   // 建议：区分不同 "none" 场景
   pub enum SandboxTag {
       DangerFullAccess,  // "danger_none"
       PlatformUnsupported,  // "unsupported_none"
       External,  // "external"
       // ...
   }
   ```

2. **增强信息**
   - 添加函数返回结构化信息而非仅字符串
   - 包含沙盒类型、策略摘要、平台信息

3. **Windows 简化**
   ```rust
   // 当前：分散在两个地方处理
   // 建议：统一在 as_metric_tag 中处理
   impl SandboxType {
       fn as_metric_tag(self, level: WindowsSandboxLevel) -> &'static str {
           match (self, level) {
               (SandboxType::WindowsRestrictedToken, WindowsSandboxLevel::Elevated) => "windows_elevated",
               (SandboxType::WindowsRestrictedToken, _) => "windows_sandbox",
               // ...
           }
       }
   }
   ```

4. **配置哈希**
   - 为复杂策略生成哈希标签
   - 便于追踪特定策略配置的使用情况

5. **文档完善**
   - 添加标签到含义的映射文档
   - 在监控仪表板中提供标签解释

### 测试覆盖

当前测试在 `sandbox_tags_tests.rs` 中，包括：
- `danger_full_access_is_untagged_even_when_linux_sandbox_defaults_apply`
- `external_sandbox_keeps_external_tag_when_linux_sandbox_defaults_apply`
- `default_linux_sandbox_uses_platform_sandbox_tag`

**建议添加**：
- Windows 平台标签测试
- 所有策略组合的测试矩阵
- 标签稳定性测试（确保标签值不变）
