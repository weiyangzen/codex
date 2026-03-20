# DIR codex-rs/core/src/features 深度研究

## 概述

`codex-rs/core/src/features` 目录是 Codex 项目的**特性开关（Feature Flags）核心管理模块**，负责集中管理所有实验性、稳定性和已弃用功能的启用/禁用状态。该模块采用统一的设计模式，避免将各个功能的布尔值分散传递到代码各处，而是通过单一的 `Features` 容器挂载在 `Config` 上，供调用方查询。

---

## 场景与职责

### 核心职责

1. **特性生命周期管理**：定义特性的五个生命周期阶段（UnderDevelopment、Experimental、Stable、Deprecated、Removed）
2. **配置解析与合并**：从 TOML 配置文件、命令行参数、环境变量等多源配置中解析特性开关
3. **向后兼容性**：维护旧版特性键名（legacy keys）到新特性键名的映射，提供平滑迁移路径
4. **约束与验证**：通过 `ManagedFeatures` 实现特性约束，确保管理员强制配置的特性不能被用户覆盖
5. **遥测与监控**：收集特性使用状态并上报到 OpenTelemetry

### 使用场景

| 场景 | 说明 |
|------|------|
| 实验功能发布 | 新功能先以 `UnderDevelopment` 状态存在，成熟后转为 `Experimental` 并在 `/experimental` 菜单中展示 |
| A/B 测试 | 通过特性开关控制功能 rollout，支持按用户/会话粒度启用 |
| 安全管控 | 企业管理员可通过 `FeatureRequirementsToml` 强制启用/禁用特定特性 |
| 沙箱策略控制 | 特性开关决定使用哪种沙箱后端（Landlock vs Bubblewrap） |
| 工具注册 | 根据特性开关决定向模型暴露哪些工具（如 `JsRepl`、`ApplyPatchFreeform` 等） |

---

## 功能点目的

### 1. 特性枚举 (`Feature`)

定义了约 60 个特性开关，涵盖以下类别：

- **Shell 执行相关**：`ShellTool`, `ShellZshFork`, `ShellSnapshot`, `UnifiedExec`, `PowershellUtf8`
- **JavaScript 执行**：`JsRepl`, `CodeMode`, `CodeModeOnly`, `JsReplToolsOnly`
- **Web 搜索**：`WebSearchRequest`, `WebSearchCached`（已弃用）
- **Windows 沙箱**：`WindowsSandbox`, `WindowsSandboxElevated`
- **多智能体协作**：`Collab`, `SpawnCsv`
- **Apps/插件**：`Apps`, `Plugins`, `ToolSuggest`
- **AI 能力**：`ImageGeneration`, `ImageDetailOriginal`, `Artifact`
- **安全与审批**：`GuardianApproval`, `ExecPermissionApprovals`, `RequestPermissionsTool`
- **TUI 体验**：`Personality`, `FastMode`, `VoiceTranscription`, `RealtimeConversation`, `TuiAppServer`
- **其他**：`GhostCommit`, `MemoryTool`, `CodexHooks`, `PreventIdleSleep`

### 2. 特性阶段 (`Stage`)

```rust
pub enum Stage {
    UnderDevelopment,           // 开发中，不建议外部使用
    Experimental { ... },       // 实验性，在 /experimental 菜单展示
    Stable,                     // 稳定可用
    Deprecated,                 // 已弃用
    Removed,                    // 已移除但保留键名以兼容旧配置
}
```

### 3. 特性规格 (`FeatureSpec`)

每个特性包含：
- `id`: 特性枚举值
- `key`: 字符串键名（用于 TOML 配置）
- `stage`: 生命周期阶段
- `default_enabled`: 默认是否启用

### 4. 旧版特性映射 (`legacy.rs`)

维护旧版键名到新特性的映射关系：

| 旧版键名 | 映射到特性 |
|----------|-----------|
| `connectors` | `Apps` |
| `enable_experimental_windows_sandbox` | `WindowsSandbox` |
| `experimental_use_unified_exec_tool` | `UnifiedExec` |
| `experimental_use_freeform_apply_patch` | `ApplyPatchFreeform` |
| `include_apply_patch_tool` | `ApplyPatchFreeform` |
| `request_permissions` | `ExecPermissionApprovals` |
| `web_search` | `WebSearchRequest` |
| `collab` | `Collab` |
| `memory_tool` | `MemoryTool` |

---

## 具体技术实现

### 关键数据结构

```rust
/// 特性枚举（核心定义）
pub enum Feature { ... }

/// 特性生命周期阶段
pub enum Stage { ... }

/// 特性规格定义（静态数组 FEATURES 中）
pub struct FeatureSpec {
    pub id: Feature,
    pub key: &'static str,
    pub stage: Stage,
    pub default_enabled: bool,
}

/// 特性集合（运行时状态）
pub struct Features {
    enabled: BTreeSet<Feature>,
    legacy_usages: BTreeSet<LegacyFeatureUsage>,
}

/// 受约束的特性集合（支持管理员强制配置）
pub struct ManagedFeatures {
    value: ConstrainedWithSource<Features>,
    pinned_features: BTreeMap<Feature, bool>,
}

/// TOML 配置中的特性表
#[derive(Serialize, Deserialize)]
pub struct FeaturesToml {
    #[serde(flatten)]
    pub entries: BTreeMap<String, bool>,
}
```

### 关键流程

#### 1. 特性初始化流程

```rust
// 1. 从默认配置开始
let mut features = Features::with_defaults();

// 2. 应用旧版特性开关（兼容层）
base_legacy.apply(&mut features);

// 3. 应用基础配置中的特性
if let Some(base_features) = cfg.features.as_ref() {
    features.apply_map(&base_features.entries);
}

// 4. 应用 profile 特定的旧版开关
profile_legacy.apply(&mut features);

// 5. 应用 profile 特性
if let Some(profile_features) = config_profile.features.as_ref() {
    features.apply_map(&profile_features.entries);
}

// 6. 应用命令行覆盖
overrides.apply(&mut features);

// 7. 归一化依赖关系
features.normalize_dependencies();
```

#### 2. 依赖归一化 (`normalize_dependencies`)

```rust
pub(crate) fn normalize_dependencies(&mut self) {
    // SpawnCsv 依赖 Collab
    if self.enabled(Feature::SpawnCsv) && !self.enabled(Feature::Collab) {
        self.enable(Feature::Collab);
    }
    // CodeModeOnly 依赖 CodeMode
    if self.enabled(Feature::CodeModeOnly) && !self.enabled(Feature::CodeMode) {
        self.enable(Feature::CodeMode);
    }
    // JsReplToolsOnly 需要 JsRepl
    if self.enabled(Feature::JsReplToolsOnly) && !self.enabled(Feature::JsRepl) {
        tracing::warn!("js_repl_tools_only requires js_repl; disabling js_repl_tools_only");
        self.disable(Feature::JsReplToolsOnly);
    }
}
```

#### 3. 约束验证流程 (`ManagedFeatures`)

```rust
pub(crate) fn from_configured(
    configured_features: Features,
    feature_requirements: Option<Sourced<FeatureRequirementsToml>>,
) -> std::io::Result<Self> {
    // 1. 解析管理员强制配置
    let (pinned_features, source) = match feature_requirements { ... };
    
    // 2. 归一化候选特性（强制覆盖用户配置）
    let normalized_features = normalize_candidate(configured_features, &pinned_features);
    
    // 3. 验证强制约束
    validate_pinned_features(&normalized_features, &pinned_features, source.as_ref())?;
    
    Ok(Self { ... })
}
```

#### 4. 特性键解析流程

```rust
pub(crate) fn feature_for_key(key: &str) -> Option<Feature> {
    // 1. 先查找标准特性
    for spec in FEATURES {
        if spec.key == key {
            return Some(spec.id);
        }
    }
    // 2. 再查找旧版别名
    legacy::feature_for_key(key)
}
```

### 配置协议

#### TOML 配置示例

```toml
[features]
shell_tool = true
js_repl = false
multi_agent = true
apps = true

[profiles.experimental]
[profiles.experimental.features]
code_mode = true
image_generation = true
```

#### 旧版配置（仍兼容）

```toml
# 旧版键名仍被识别并映射到新特性
experimental_use_unified_exec_tool = true
include_apply_patch_tool = true
web_search = true
collab = true
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `codex-rs/core/src/features.rs` | 主模块，定义 `Feature` 枚举、`Features` 结构体、`FEATURES` 规格表 |
| `codex-rs/core/src/features/legacy.rs` | 旧版特性键名映射、旧版特性开关结构体 |
| `codex-rs/core/src/features_tests.rs` | 单元测试 |
| `codex-rs/core/src/config/managed_features.rs` | 受约束的特性管理（管理员强制配置） |
| `codex-rs/core/src/config/schema.rs` | JSON Schema 生成（包含特性键） |

### 主要调用方

| 调用方 | 用途 |
|--------|------|
| `codex-rs/core/src/codex.rs` | 会话初始化时构建特性集合，控制各类功能开关 |
| `codex-rs/core/src/tools/spec.rs` | 根据特性开关决定向模型注册哪些工具 |
| `codex-rs/core/src/config/mod.rs` | 配置解析，构建 `ManagedFeatures` |
| `codex-rs/core/src/windows_sandbox.rs` | 根据特性决定 Windows 沙箱级别 |
| `codex-rs/core/src/landlock.rs` | 检查 `use_legacy_landlock` 特性 |
| `codex-rs/core/src/client.rs` | 构建 `x-codex-beta-features` HTTP 头 |
| `codex-rs/core/src/plugins/manager.rs` | 检查 `Plugins` 特性是否启用 |
| `codex-rs/core/src/connectors.rs` | 检查 `Apps` 特性及认证状态 |
| `codex-rs/core/src/mcp/mod.rs` | 检查 `SkillMcpDependencyInstall` 特性 |

---

## 依赖与外部交互

### 内部依赖

```
features/
├── 依赖:
│   ├── crate::auth (AuthManager, CodexAuth)
│   ├── crate::config (Config, ConfigToml, ConfigProfile)
│   ├── crate::protocol (Event, EventMsg, WarningEvent)
│   ├── codex_config (Constrained, ConstrainedWithSource, FeatureRequirementsToml)
│   ├── codex_otel (SessionTelemetry)
│   └── schemars, serde, toml, tracing
└── 被依赖:
    ├── crate::codex (Session, TurnContext)
    ├── crate::tools::spec (ToolsConfig)
    ├── crate::config (Config, ManagedFeatures)
    ├── crate::windows_sandbox
    ├── crate::landlock
    ├── crate::client
    └── 几乎所有需要特性开关的模块
```

### 外部交互

1. **配置文件** (`~/.codex/config.toml`): 读取 `[features]` 表
2. **管理员配置** (`managed_config.toml` 或 MDM): 读取 `feature_requirements` 强制约束
3. **遥测系统**: 通过 `SessionTelemetry` 上报特性使用状态
4. **HTTP 客户端**: 向 Codex 后端发送 `x-codex-beta-features` 头
5. **TUI 实验菜单**: 展示 `Experimental` 阶段的特性供用户启用

---

## 风险、边界与改进建议

### 当前风险

1. **特性膨胀**：当前已定义约 60 个特性，部分已标记为 `Removed` 但仍保留在代码中，增加维护负担
2. **隐式依赖**：`normalize_dependencies` 中的依赖关系是硬编码的，缺乏显式声明机制
3. **旧版债务**：大量旧版键名映射和兼容代码需要长期维护
4. **平台差异**：部分特性（如 `PowershellUtf8`）在不同平台有不同默认行为，可能导致跨平台不一致

### 边界情况

1. **约束冲突**：当用户配置与管理员强制配置冲突时，系统会报错而非静默覆盖
2. **未知特性键**：配置文件中未知的特性键会被记录警告但忽略
3. **特性依赖循环**：当前实现未检测循环依赖（如 A 依赖 B，B 又依赖 A）
4. **动态特性切换**：大部分特性在会话启动后不能动态修改，需要重启生效

### 改进建议

1. **特性注册宏**：引入声明式宏简化特性定义，自动处理键名、阶段、默认值
   ```rust
   declare_feature! {
       JsRepl, "js_repl", Experimental { ... }, default: false,
       depends_on: [],
       conflicts_with: []
   }
   ```

2. **特性依赖图**：将隐式依赖改为显式声明，支持拓扑排序自动处理依赖关系

3. **特性清理**：对已标记 `Removed` 超过 2 个版本的特性进行彻底清理

4. **动态特性**：探索支持会话内动态启用/禁用部分特性（不影响沙箱安全相关特性）

5. **特性文档自动生成**：利用 `FeatureSpec` 中的元数据自动生成用户文档

6. **特性使用分析**：增强遥测，分析哪些特性实际被使用，指导特性退役决策

---

## 总结

`codex-rs/core/src/features` 是 Codex 项目的**功能控制中心**，通过集中式的特性开关管理，实现了：

- **敏捷发布**：新功能可快速以实验特性形式发布
- **安全管控**：企业管理员可强制配置特性约束
- **平滑演进**：旧版配置兼容确保用户升级无感知
- **可观测性**：特性使用状态全面可监控

该模块的设计体现了**配置即代码**的理念，将产品功能的生命周期管理内建于代码结构中，是大型 Rust 项目特性管理的优秀实践参考。
