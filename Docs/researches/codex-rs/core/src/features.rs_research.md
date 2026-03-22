# features.rs 研究文档

## 场景与职责

本文件是 Codex 核心功能标志（Feature Flags）系统的中心化管理模块。它提供了一套完整的机制来控制功能的启用/禁用状态，支持：

1. **功能生命周期管理**：定义功能从开发到稳定再到废弃的完整生命周期
2. **配置驱动**：从 TOML 配置文件加载功能开关
3. **实验性功能菜单**：为 TUI 提供 `/experimental` 菜单的数据支持
4. **向后兼容**：处理旧版配置键的映射
5. **遥测上报**：功能使用状态的指标收集

## 功能点目的

### 1. 功能生命周期阶段 (`Stage` 枚举)

```rust
pub enum Stage {
    UnderDevelopment,      // 开发中，不对外暴露
    Experimental {         // 实验性，可在 /experimental 菜单中开关
        name: &'static str,
        menu_description: &'static str,
        announcement: &'static str,
    },
    Stable,                // 稳定功能
    Deprecated,            // 已废弃
    Removed,               // 已移除（保留键用于兼容）
}
```

### 2. 功能定义 (`Feature` 枚举)

包含 40+ 个功能标志，按类别划分：

**稳定功能 (Stable)：**
- `GhostCommit` (undo)：每次 turn 创建 ghost commit
- `ShellTool`：默认 shell 工具
- `UnifiedExec`：统一 PTY-backed exec 工具
- `ShellSnapshot`：Shell 快照
- `EnableRequestCompression`：请求体 zstd 压缩
- `Collab` (multi_agent)：多智能体协作
- `SkillMcpDependencyInstall`：MCP 依赖自动安装
- `Personality`：TUI 人格选择
- `FastMode`：快速模式

**实验性功能 (Experimental)：**
- `JsRepl`：Node.js REPL
- `GuardianApproval`：自动安全审查
- `Apps`：ChatGPT App 连接器
- `TuiAppServer`：App-server 支持的 TUI
- `PreventIdleSleep`：运行期间阻止系统休眠

**开发中功能 (UnderDevelopment)：**
- `CodeMode` / `CodeModeOnly`：代码模式
- `MemoryTool`：内存工具
- `Artifact`：原生 artifact 工具
- `RealtimeConversation`：实时语音对话

**已废弃/移除：**
- `WebSearchRequest` / `WebSearchCached` → 默认启用，配置项废弃
- `SearchTool` / `RequestRule` / `Sqlite` 等 → 已移除

### 3. 功能容器 (`Features` 结构体)

```rust
pub struct Features {
    enabled: BTreeSet<Feature>,           // 已启用的功能
    legacy_usages: BTreeSet<LegacyFeatureUsage>,  // 旧配置键使用记录
}
```

核心方法：
- `with_defaults()`：使用默认配置初始化
- `enabled(f: Feature) -> bool`：检查功能是否启用
- `enable(f)` / `disable(f)` / `set_enabled(f, bool)`：状态修改
- `from_config(cfg, profile, overrides)`：从配置构建

### 4. 配置集成

支持从多个层级加载配置：

```rust
pub fn from_config(
    cfg: &ConfigToml,           // 基础配置
    config_profile: &ConfigProfile,  // 配置文件中的 profile
    overrides: FeatureOverrides,     // 运行时覆盖
) -> Self
```

配置优先级（从高到低）：
1. 运行时覆盖 (`FeatureOverrides`)
2. Profile 层配置
3. 基础配置 (`[features]` 表)
4. 旧版兼容配置 (`experimental_use_freeform_apply_patch` 等)
5. 代码默认值

### 5. 实验性功能警告

```rust
pub fn maybe_push_unstable_features_warning(
    config: &Config,
    post_session_configured_events: &mut Vec<Event>,
)
```

当用户启用了 `UnderDevelopment` 阶段的功能时，推送警告事件提示用户。

## 具体技术实现

### 功能规范注册表

```rust
pub const FEATURES: &[FeatureSpec] = &[
    FeatureSpec {
        id: Feature::JsRepl,
        key: "js_repl",
        stage: Stage::Experimental {
            name: "JavaScript REPL",
            menu_description: "Enable a persistent Node-backed JavaScript REPL...",
            announcement: "NEW: JavaScript REPL is now available in /experimental...",
        },
        default_enabled: false,
    },
    // ... 其他功能
];
```

### 功能依赖规范化

```rust
fn normalize_dependencies(&mut self) {
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
        self.disable(Feature::JsReplToolsOnly);
    }
}
```

### 旧版配置兼容

```rust
// features/legacy.rs
const ALIASES: &[Alias] = &[
    Alias { legacy_key: "connectors", feature: Feature::Apps },
    Alias { legacy_key: "collab", feature: Feature::Collab },
    Alias { legacy_key: "web_search", feature: Feature::WebSearchRequest },
    // ...
];
```

### TOML 配置结构

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Default, PartialEq, JsonSchema)]
pub struct FeaturesToml {
    #[serde(flatten)]
    pub entries: BTreeMap<String, bool>,
}
```

配置示例：
```toml
[features]
js_repl = true
undo = false
```

### 遥测集成

```rust
pub fn emit_metrics(&self, otel: &SessionTelemetry) {
    for feature in FEATURES {
        if self.enabled(feature.id) != feature.default_enabled {
            otel.counter(
                "codex.feature.state",
                /*inc*/ 1,
                &[
                    ("feature", feature.key),
                    ("value", &self.enabled(feature.id).to_string()),
                ],
            );
        }
    }
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|-----|------|
| `features.rs` | 主模块，功能定义与管理 |
| `features/legacy.rs` | 旧版配置键映射 |
| `features_tests.rs` | 单元测试 |

### 调用方

| 调用方 | 用途 |
|-------|------|
| `config.rs` | 构建 Config 时初始化 Features |
| `codex.rs` | 检查功能开关决定行为 |
| `tui/` | `/experimental` 菜单渲染 |
| `otel_init.rs` | 上报功能使用指标 |

### 关键数据结构

```rust
// 功能规范
pub struct FeatureSpec {
    pub id: Feature,
    pub key: &'static str,
    pub stage: Stage,
    pub default_enabled: bool,
}

// 旧版使用记录
pub struct LegacyFeatureUsage {
    pub alias: String,
    pub feature: Feature,
    pub summary: String,
    pub details: Option<String>,
}

// 运行时覆盖
pub struct FeatureOverrides {
    pub include_apply_patch_tool: Option<bool>,
    pub web_search_request: Option<bool>,
}
```

### 功能键查询

```rust
pub fn feature_for_key(key: &str) -> Option<Feature>
pub fn canonical_feature_for_key(key: &str) -> Option<Feature>
pub fn is_known_feature_key(key: &str) -> bool
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|-----|------|
| `auth.rs` | `Apps` 功能需要验证 ChatGPT 认证 |
| `config.rs` | 配置结构定义 |
| `protocol.rs` | 事件类型定义 |
| `codex_otel` | 遥测指标上报 |
| `codex_config` | 配置文件名常量 |

### 外部 crate

| crate | 用途 |
|-------|------|
| `schemars` | JSON Schema 生成 |
| `serde` | 序列化/反序列化 |
| `toml` | TOML 值处理 |
| `tracing` | 日志记录 |

### 配置集成流程

```
ConfigToml
    ↓
Features::from_config()
    ├── LegacyFeatureToggles::apply()  // 旧版字段
    ├── apply_map()                    // [features] 表
    ├── normalize_dependencies()       // 依赖规范化
    └── Features 实例
```

## 风险、边界与改进建议

### 当前风险点

1. **功能键硬编码风险**：`FEATURES` 数组中的 `key` 字符串需要与文档保持一致
2. **依赖循环风险**：`normalize_dependencies` 目前只处理单向依赖
3. **平台条件编译**：部分功能使用 `#[cfg(windows)]` 等条件编译，可能导致跨平台行为不一致

### 边界情况

| 边界情况 | 处理方式 |
|---------|---------|
| 未知功能键 | 记录警告日志，忽略该键 |
| 重复配置 | 后配置的覆盖先配置的 |
| 功能互斥 | 目前未显式处理，依赖代码逻辑 |
| 动态切换 | 不支持，Features 实例创建后只读 |

### 改进建议

1. **功能依赖图**：当前依赖处理是硬编码的，建议改为声明式依赖图：
   ```rust
   struct FeatureSpec {
       // ...
       requires: &'static [Feature],
       conflicts_with: &'static [Feature],
   }
   ```

2. **功能状态持久化**：考虑支持运行时功能切换并持久化到配置

3. **A/B 测试支持**：增加基于用户/会话的功能灰度机制

4. **功能文档自动生成**：从 `FeatureSpec` 自动生成用户文档

5. **配置验证**：增加配置加载时的严格模式，未知键报错而非警告

6. **性能优化**：`FEATURES` 线性查找可优化为 HashMap（当前功能数量 40+，影响可忽略）

### 测试覆盖

测试文件 `features_tests.rs` 覆盖：
- 默认状态验证
- 生命周期阶段验证
- 依赖规范化验证
- 旧版别名验证
- 认证集成验证 (`apps_require_feature_flag_and_chatgpt_auth`)

建议增加：
- 配置加载集成测试
- 遥测指标验证测试
- 并发安全测试
