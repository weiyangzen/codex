# windows_sandbox.rs 研究文档

## 场景与职责

`windows_sandbox.rs` 是 Codex Core 中负责 **Windows 沙盒配置管理和设置** 的模块。其核心职责包括：

1. **沙盒级别管理**：从配置和特性标志解析 Windows 沙盒级别
2. **配置解析**：支持新旧配置格式的兼容处理
3. **沙盒设置执行**：协调提升和非提升两种设置模式
4. **遥测发射**：收集和发射沙盒设置相关的性能指标
5. **平台抽象**：为非 Windows 平台提供存根实现

该模块是 Windows 平台安全功能的核心，负责在代码执行前配置适当的沙盒环境。

## 功能点目的

### 1. Windows 沙盒级别

```rust
// 来自 codex_protocol::config_types
pub enum WindowsSandboxLevel {
    Disabled,       // 禁用沙盒
    RestrictedToken, // 非提升模式（受限令牌）
    Elevated,       // 提升模式
}
```

### 2. 配置解析

支持多种配置来源（优先级从高到低）：
1. Profile 的 `windows.sandbox`
2. 全局 `windows.sandbox`
3. 旧版 `features` 中的特性标志

### 3. 沙盒设置模式

```rust
pub enum WindowsSandboxSetupMode {
    Elevated,    // 提升模式：需要 UAC 提升
    Unelevated,  // 非提升模式：使用受限令牌
}
```

### 4. 设置请求

```rust
pub struct WindowsSandboxSetupRequest {
    pub mode: WindowsSandboxSetupMode,
    pub policy: SandboxPolicy,
    pub policy_cwd: PathBuf,
    pub command_cwd: PathBuf,
    pub env_map: HashMap<String, String>,
    pub codex_home: PathBuf,
    pub active_profile: Option<String>,
}
```

## 具体技术实现

### 关键流程

#### 1. 从配置解析沙盒级别

```rust
impl WindowsSandboxLevelExt for WindowsSandboxLevel {
    fn from_config(config: &Config) -> WindowsSandboxLevel {
        match config.permissions.windows_sandbox_mode {
            Some(WindowsSandboxModeToml::Elevated) => WindowsSandboxLevel::Elevated,
            Some(WindowsSandboxModeToml::Unelevated) => WindowsSandboxLevel::RestrictedToken,
            None => Self::from_features(&config.features),
        }
    }

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

#### 2. 解析沙盒模式

```rust
pub fn resolve_windows_sandbox_mode(
    cfg: &ConfigToml,
    profile: &ConfigProfile,
) -> Option<WindowsSandboxModeToml>
```

优先级：
1. Profile 的 legacy features
2. Profile 的 `windows.sandbox`
3. 全局 `windows.sandbox`
4. 全局 legacy features

#### 3. 执行沙盒设置

```rust
pub async fn run_windows_sandbox_setup(request: WindowsSandboxSetupRequest) -> anyhow::Result<()>
```

流程：
1. 记录开始时间
2. 获取 originator 标签
3. 执行实际设置
4. 发射成功或失败指标

#### 4. 实际设置执行

```rust
async fn run_windows_sandbox_setup_and_persist(
    request: WindowsSandboxSetupRequest,
) -> anyhow::Result<()>
```

流程：
1. 使用 `tokio::task::spawn_blocking` 在阻塞线程执行
2. 根据模式调用不同设置函数：
   - `Elevated`: `run_elevated_setup`（如果未完成）
   - `Unelevated`: `run_legacy_setup_preflight`
3. 使用 `ConfigEditsBuilder` 持久化配置

### 平台条件编译

```rust
#[cfg(target_os = "windows")]
pub fn sandbox_setup_is_complete(codex_home: &Path) -> bool {
    codex_windows_sandbox::sandbox_setup_is_complete(codex_home)
}

#[cfg(not(target_os = "windows"))]
pub fn sandbox_setup_is_complete(_codex_home: &Path) -> bool {
    false
}
```

为非 Windows 平台提供存根实现，返回错误或不支持。

### 遥测发射

#### 成功指标

```rust
fn emit_windows_sandbox_setup_success_metrics(
    mode: WindowsSandboxSetupMode,
    originator_tag: &str,
    duration: std::time::Duration,
)
```

发射：
- `codex.windows_sandbox.setup_duration_ms`（带 result=success 标签）
- `codex.windows_sandbox.setup_success`

#### 失败指标

```rust
fn emit_windows_sandbox_setup_failure_metrics(
    mode: WindowsSandboxSetupMode,
    originator_tag: &str,
    duration: std::time::Duration,
    _err: &anyhow::Error,
)
```

发射：
- `codex.windows_sandbox.setup_duration_ms`（带 result=failure 标签）
- `codex.windows_sandbox.setup_failure`
- 提升模式：`codex.windows_sandbox.elevated_setup_failure` 或 `elevated_setup_canceled`
- 非提升模式：`codex.windows_sandbox.legacy_setup_preflight_failed`

## 关键代码路径与文件引用

### 本文件关键项

| 项 | 行号 | 说明 |
|----|------|------|
| `WindowsSandboxLevelExt` | 25-49 | 沙盒级别扩展 trait |
| `resolve_windows_sandbox_mode` | 59-76 | 解析沙盒模式 |
| `resolve_windows_sandbox_private_desktop` | 78-89 | 解析私有桌面设置 |
| `run_windows_sandbox_setup` | 280-305 | 主设置入口 |
| `run_windows_sandbox_setup_and_persist` | 307-356 | 实际设置执行 |
| `emit_windows_sandbox_setup_success_metrics` | 358-380 | 成功遥测 |
| `emit_windows_sandbox_setup_failure_metrics` | 383-432 | 失败遥测 |

### 依赖文件

| 文件 | 依赖内容 |
|------|----------|
| `config/*.rs` | `Config`, `ConfigToml`, `WindowsSandboxModeToml` |
| `features.rs` | `Feature`, `Features` |
| `protocol.rs` | `SandboxPolicy` |
| `codex_windows_sandbox` crate | Windows 特定实现 |
| `codex_otel` | 遥测发射 |

### 调用方

- 应用启动：检查和执行沙盒设置
- 配置变更：重新应用沙盒设置
- CLI 命令：`codex sandbox setup`

## 依赖与外部交互

### Windows 特定依赖

```rust
#[cfg(target_os = "windows")]
use codex_windows_sandbox::{
    run_elevated_setup,
    run_windows_sandbox_capture,
    run_windows_sandbox_capture_elevated,
    // ...
};
```

- `codex_windows_sandbox` crate 提供底层实现
- 仅在 Windows 平台编译

### 配置持久化

```rust
ConfigEditsBuilder::new(codex_home.as_path())
    .with_profile(active_profile.as_deref())
    .set_windows_sandbox_mode(windows_sandbox_setup_mode_tag(mode))
    .clear_legacy_windows_sandbox_keys()
    .apply()
    .await
```

- 使用 `ConfigEditsBuilder` 模式
- 原子性应用配置变更

### 遥测系统

```rust
if let Some(metrics) = codex_otel::metrics::global() {
    let _ = metrics.record_duration(...);
    let _ = metrics.counter(...);
}
```

- 使用 OpenTelemetry 风格 API
- 静默处理遥测失败（`let _ =`）

## 风险、边界与改进建议

### 风险点

1. **平台条件编译复杂性**
   - 大量 `#[cfg(target_os = "windows")]`
   - 可能导致非 Windows 平台测试不足

2. **配置迁移复杂性**
   - 支持新旧配置格式
   - 逻辑复杂，容易出错

3. **提升模式安全性**
   - 需要管理员权限
   - 失败处理需要谨慎

4. **遥测静默失败**
   - 遥测发射失败被忽略
   - 可能丢失重要指标

### 边界情况

1. **设置中断**
   - 设置过程中应用崩溃
   - 可能留下不完整状态

2. **配置冲突**
   - Profile 和全局配置冲突
   - 优先级规则需要清晰

3. **平台检测**
   - 运行时平台检测 vs 编译时
   - 交叉编译场景

4. **重复设置**
   - `sandbox_setup_is_complete` 检查
   - 避免不必要的重复设置

### 改进建议

1. **添加更多日志**
   - 配置解析过程的详细日志
   - 设置步骤的进度日志

2. **配置验证**
   - 添加配置有效性检查
   - 提前发现冲突配置

3. **遥测增强**
   - 记录设置失败的具体原因
   - 添加更多性能指标

4. **测试增强**
   - 添加配置解析单元测试
   - 模拟 Windows 环境测试

5. **文档**
   - 配置优先级流程图
   - 设置流程文档

### 相关测试

测试文件：`windows_sandbox_tests.rs`

| 测试 | 说明 |
|------|------|
| `elevated_flag_works_by_itself` | 验证提升特性标志 |
| `restricted_token_flag_works_by_itself` | 验证受限令牌特性标志 |
| `no_flags_means_no_sandbox` | 验证默认无沙盒 |
| `elevated_wins_when_both_flags_are_enabled` | 验证优先级 |
| `resolve_windows_sandbox_mode_prefers_profile_windows` | 验证配置优先级 |
| `resolve_windows_sandbox_private_desktop_prefers_profile_windows` | 验证私有桌面配置 |

### 代码质量评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 功能性 | 高 | 功能完整，覆盖多种场景 |
| 可维护性 | 中 | 条件编译增加复杂性 |
| 可测试性 | 中 | 平台依赖难以测试 |
| 文档 | 中 | 有注释，但缺少架构文档 |
| 错误处理 | 高 | 使用 anyhow，错误传播清晰 |
