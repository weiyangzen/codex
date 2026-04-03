# WindowsSandboxSetupMode.ts Research Document

## 场景与职责

`WindowsSandboxSetupMode` 是 App-Server Protocol v2 中定义 Windows 沙盒设置模式的枚举类型。它在以下场景中发挥关键作用：

1. **权限级别选择**: 决定 Windows 沙盒是以提升权限（管理员）还是非提升权限运行
2. **安全策略配置**: 作为配置 Windows 沙盒安全级别的关键参数
3. **NUX 流程引导**: 在新用户引导流程中帮助用户选择合适的沙盒模式
4. **功能特性开关**: 控制 Windows 沙盒相关功能的可用性
5. **向后兼容**: 支持从旧版沙盒配置迁移到新的配置系统

## 功能点目的

该枚举类型的核心目的是：

- **权限抽象**: 将复杂的 Windows 权限模型简化为两种离散模式
- **安全配置**: 为用户和开发者提供清晰的沙盒安全级别选择
- **跨层通信**: 在配置层、核心层和应用服务器层之间传递沙盒模式选择
- **特性管理**: 与功能标志系统（Features）集成，控制沙盒功能的启用

## 具体技术实现

### TypeScript 类型定义

```typescript
export type WindowsSandboxSetupMode = "elevated" | "unelevated";
```

### Rust 源类型定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum WindowsSandboxSetupMode {
    Elevated,
    Unelevated,
}
```

### 变体详解

| 变体 | 序列化值 | 含义 | 权限级别 |
|-----|---------|------|---------|
| **Elevated** | `"elevated"` | 提升权限模式 | 需要管理员权限，提供更完整的隔离环境 |
| **Unelevated** | `"unelevated"` | 非提升权限模式 | 使用受限令牌，权限更严格，无需管理员权限 |

### 序列化特性

- **命名规范**: 使用 `camelCase` 进行序列化（`Elevated` → `"elevated"`）
- **Copy 语义**: 实现了 `Copy` trait，可以按值传递而无需克隆
- **相等比较**: 实现了 `Eq` 和 `PartialEq`，支持模式匹配和比较

### 与核心层类型的映射

```rust
// WindowsSandboxSetupMode → WindowsSandboxLevel
pub fn to_sandbox_level(mode: WindowsSandboxSetupMode) -> WindowsSandboxLevel {
    match mode {
        WindowsSandboxSetupMode::Elevated => WindowsSandboxLevel::Elevated,
        WindowsSandboxSetupMode::Unelevated => WindowsSandboxLevel::RestrictedToken,
    }
}
```

### 与配置类型的映射

```rust
// WindowsSandboxSetupMode ↔ WindowsSandboxModeToml
impl From<WindowsSandboxModeToml> for WindowsSandboxSetupMode {
    fn from(mode: WindowsSandboxModeToml) -> Self {
        match mode {
            WindowsSandboxModeToml::Elevated => WindowsSandboxSetupMode::Elevated,
            WindowsSandboxModeToml::Unelevated => WindowsSandboxSetupMode::Unelevated,
        }
    }
}
```

### 功能标志集成

在 `core/src/windows_sandbox.rs` 中：

```rust
impl WindowsSandboxLevelExt for WindowsSandboxLevel {
    fn from_features(features: &Features) -> WindowsSandboxLevel {
        if features.enabled(Feature::WindowsSandboxElevated) {
            return WindowsSandboxLevel::Elevated;
        }
        if features.enabled(Feature::WindowsSandbox) {
            WindowsSandboxLevel::RestrictedToken
        } else {
            WindowsSandboxLevel::Disabled
        }
    }
}
```

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 4977-4983) | Rust 枚举定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/WindowsSandboxSetupMode.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/WindowsSandboxSetupMode.json` | JSON Schema 定义 |

### 使用位置

| 文件路径 | 用途 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `WindowsSandboxSetupStartParams` 和 `WindowsSandboxSetupCompletedNotification` 的字段 |
| `codex-rs/core/src/windows_sandbox.rs` | 沙盒级别解析和配置 |
| `codex-rs/protocol/src/config_types.rs` | `WindowsSandboxLevel` 和 `WindowsSandboxModeToml` 定义 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI 应用服务器沙盒模式处理 |

### 配置解析流程

```
config.toml
    │
    ├── features.windowsSandboxElevated → Elevated
    ├── features.windowsSandbox → Unelevated (fallback)
    │
    └── [windows]
        └── sandbox = "elevated" | "unelevated"
                │
                ▼
        WindowsSandboxModeToml
                │
                ▼
        WindowsSandboxSetupMode
                │
                ▼
        WindowsSandboxLevel (核心层)
```

## 依赖与外部交互

### 内部依赖

- **`WindowsSandboxLevel`**: 核心层的沙盒级别枚举（`Elevated`, `RestrictedToken`, `Disabled`）
- **`WindowsSandboxModeToml`**: TOML 配置中的沙盒模式类型
- **`Feature`**: 功能标志枚举（`WindowsSandbox`, `WindowsSandboxElevated`）

### 协议依赖

- 被多个类型引用：
  - `WindowsSandboxSetupStartParams.mode`
  - `WindowsSandboxSetupCompletedNotification.mode`

### Windows 系统交互

| 模式 | Windows 机制 | 说明 |
|-----|-------------|------|
| `Elevated` | AppContainer + 管理员令牌 | 完整的应用容器隔离 |
| `Unelevated` | 受限令牌（Restricted Token） | 标准用户权限下的限制 |

## 风险、边界与改进建议

### 潜在风险

1. **权限混淆**: 用户可能不理解 `elevated` 和 `unelevated` 的区别，选择不合适的模式
2. **UAC 疲劳**: 频繁的 `elevated` 模式请求可能导致用户疲劳并习惯性点击"是"
3. **功能降级**: 某些功能在 `unelevated` 模式下可能无法正常工作
4. **配置漂移**: 配置文件和实际运行模式可能不一致

### 边界情况

1. **非 Windows 平台**: 该类型在 Windows 以外的平台上如何处理
2. **沙盒不可用**: Windows 版本不支持沙盒功能时的降级策略
3. **权限被拒绝**: 用户拒绝 `elevated` 模式的 UAC 提示
4. **混合模式**: 同一对话中切换沙盒模式的支持

### 改进建议

1. **添加描述信息**: 为每个变体添加人类可读的描述：
   ```rust
   impl WindowsSandboxSetupMode {
       pub fn description(&self) -> &'static str {
           match self {
               Elevated => "需要管理员权限，提供最完整的代码执行隔离",
               Unelevated => "无需管理员权限，使用标准安全限制",
           }
       }
       
       pub fn capabilities(&self) -> &[&'static str] {
           match self {
               Elevated => &["完整文件系统隔离", "网络控制", "注册表虚拟化"],
               Unelevated => &["基础进程隔离", "受限文件访问"],
           }
       }
   }
   ```

2. **自动检测推荐**: 根据系统环境推荐合适的模式：
   ```rust
   pub fn recommended_mode() -> WindowsSandboxSetupMode {
       if is_enterprise_environment() {
           Elevated
       } else if user_is_admin() {
           Elevated
       } else {
           Unelevated
       }
   }
   ```

3. **添加 Disabled 变体**: 显式支持禁用沙盒：
   ```rust
   pub enum WindowsSandboxSetupMode {
       Elevated,
       Unelevated,
       Disabled, // 新增：完全禁用沙盒
   }
   ```

4. **安全评分**: 为每种模式提供安全评分，帮助用户理解：
   ```typescript
   export type WindowsSandboxSetupModeInfo = {
     mode: WindowsSandboxSetupMode,
     securityScore: number, // 1-10
     requiresAdmin: boolean,
     limitations: string[],
   };
   ```

5. **配置验证**: 在应用配置时验证模式兼容性：
   ```rust
   pub fn validate_mode_for_system(mode: WindowsSandboxSetupMode) -> Result<(), ValidationError> {
       match mode {
           Elevated if !is_windows_10_or_later() => 
               Err(ValidationError::UnsupportedOS),
           _ => Ok(()),
       }
   }
   ```

### 测试覆盖

- 配置解析测试: `codex-rs/core/src/windows_sandbox.rs` 相关测试
- 协议测试: `codex-rs/app-server/tests/suite/v2/windows_sandbox_setup.rs`
- 建议添加：
  - 不同 Windows 版本的兼容性测试
  - 权限被拒绝场景的处理测试
  - 配置迁移测试（从旧版功能标志到新版配置）
  - 性能对比测试（两种模式的开销差异）
