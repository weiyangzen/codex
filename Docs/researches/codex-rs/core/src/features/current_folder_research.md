# Research: codex-rs/core/src/features

## 概述

`codex-rs/core/src/features` 目录是 Codex CLI 项目的**特性开关（Feature Flags）核心管理模块**。该模块提供了一套集中式的机制来管理实验性功能、稳定功能以及已弃用功能的启用/禁用状态。它是整个 Codex 系统的关键配置基础设施，允许用户通过配置文件或命令行参数精细控制各种高级功能的可用性。

---

## 场景与职责

### 核心职责

1. **特性生命周期管理**：定义特性的发展阶段（开发中、实验性、稳定、已弃用、已移除）
2. **配置解析与合并**：从 TOML 配置文件解析特性开关，支持基础配置和 Profile 级别的覆盖
3. **向后兼容性**：维护旧版特性键名到新键名的映射，确保配置平滑迁移
4. **约束与验证**：通过 `ManagedFeatures` 强制执行特性依赖关系和强制启用/禁用规则
5. **遥测与监控**：向 OpenTelemetry 上报特性使用状态

### 使用场景

| 场景 | 描述 |
|------|------|
| 实验性功能尝鲜 | 用户通过 `/experimental` 菜单或配置启用如 JavaScript REPL、Guardian Approvals 等功能 |
| 功能回退 | 当某功能出现问题时，用户可通过配置文件快速禁用 |
| 企业环境管控 | 通过 `FeatureRequirementsToml` 强制锁定某些特性的状态 |
| 沙箱级别控制 | Windows/Linux 沙箱行为通过特性开关精细调整 |
| 开发调试 | 启用 `RuntimeMetrics`、`Sqlite` 等内部诊断功能 |

---

## 功能点目的

### 1. 特性定义（Feature Enum）

定义了约 50+ 个特性开关，按类别划分：

#### 稳定功能（Stable）
- `GhostCommit` (undo)：每次回合创建 ghost commit，支持撤销
- `ShellTool`：启用默认 shell 工具
- `UnifiedExec`：使用统一的 PTY-backed exec 工具
- `ShellSnapshot`：实验性 shell 快照功能
- `EnableRequestCompression`：请求体 zstd 压缩
- `Collab` (multi_agent)：多代理协作模式
- `SkillMcpDependencyInstall`：自动安装缺失的 MCP 依赖
- `Personality`：TUI 中启用个性选择
- `FastMode`：启用 Fast 模式选择

#### 实验性功能（Experimental）
- `JsRepl`：Node.js 支持的 JavaScript REPL
- `Apps`：ChatGPT Apps 连接器支持
- `GuardianApproval`：自动路由审批请求到安全审查子代理
- `TuiAppServer`：使用 app-server 支持的 TUI 实现
- `PreventIdleSleep`：防止回合运行时系统休眠

#### 开发中功能（UnderDevelopment）
- `CodeMode`/`CodeModeOnly`：代码模式及仅代码模式
- `JsReplToolsOnly`：仅暴露 js_repl 工具
- `ApplyPatchFreeform`：自由格式 apply_patch 工具
- `ExecPermissionApprovals`：执行权限审批
- `CodexHooks`：Claude 风格生命周期钩子
- `MemoryTool`：启动内存提取和文件支持的记忆整合
- `ImageGeneration`：内置图像生成工具
- `Artifact`：原生 artifact 工具
- `RealtimeConversation`：实验性实时语音对话模式

#### 已弃用/已移除功能
- `WebSearchRequest`/`WebSearchCached`：已弃用，网络搜索默认启用
- `SearchTool`：已移除
- `UseLinuxSandboxBwrap`：已移除
- `Steer`：已移除（行为默认启用）
- `CollaborationModes`：已移除（行为默认启用）

### 2. 特性生命周期阶段（Stage Enum）

```rust
pub enum Stage {
    UnderDevelopment,      // 开发中，不对外暴露
    Experimental {         // 实验性，通过 /experimental 菜单可访问
        name: &'static str,
        menu_description: &'static str,
        announcement: &'static str,
    },
    Stable,                // 稳定功能
    Deprecated,            // 已弃用
    Removed,               // 已移除，保持兼容性
}
```

### 3. 向后兼容（Legacy 模块）

维护旧版配置键名到新特性的映射：
- `connectors` → `Apps`
- `enable_experimental_windows_sandbox` → `WindowsSandbox`
- `experimental_use_unified_exec_tool` → `UnifiedExec`
- `include_apply_patch_tool` → `ApplyPatchFreeform`
- `request_permissions` → `ExecPermissionApprovals`
- `web_search` → `WebSearchRequest`
- `collab` → `Collab`
- `memory_tool` → `MemoryTool`

---

## 具体技术实现

### 关键数据结构

#### FeatureSpec - 特性元数据
```rust
pub struct FeatureSpec {
    pub id: Feature,           // 特性枚举值
    pub key: &'static str,     // 配置键名
    pub stage: Stage,          // 生命周期阶段
    pub default_enabled: bool, // 默认启用状态
}
```

所有特性在 `FEATURES` 常量数组中静态定义（约 50+ 条目）。

#### Features - 运行时特性集合
```rust
pub struct Features {
    enabled: BTreeSet<Feature>,                    // 已启用特性
    legacy_usages: BTreeSet<LegacyFeatureUsage>,   // 旧版配置使用记录
}
```

#### ManagedFeatures - 约束包装器
```rust
pub struct ManagedFeatures {
    value: ConstrainedWithSource<Features>,
    pinned_features: BTreeMap<Feature, bool>,      // 强制固定的特性状态
}
```

### 关键流程

#### 1. 配置加载流程
```
ConfigToml::features (Option<FeaturesToml>)
    ↓
Features::from_config(cfg, profile, overrides)
    ↓
1. 从默认构建 (with_defaults)
2. 应用 legacy toggles (experimental_use_*)
3. 应用 base features
4. 应用 profile features
5. 应用 overrides
6. 归一化依赖 (normalize_dependencies)
    ↓
ManagedFeatures::from_configured(features, feature_requirements)
    ↓
验证 pinned_features 约束
```

#### 2. 特性依赖归一化
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
    // JsReplToolsOnly 需要 JsRepl，否则禁用
    if self.enabled(Feature::JsReplToolsOnly) && !self.enabled(Feature::JsRepl) {
        tracing::warn!("js_repl_tools_only requires js_repl; disabling js_repl_tools_only");
        self.disable(Feature::JsReplToolsOnly);
    }
}
```

#### 3. 不稳定特性警告
```rust
pub fn maybe_push_unstable_features_warning(
    config: &Config,
    post_session_configured_events: &mut Vec<Event>,
)
```
扫描配置中启用的 `UnderDevelopment` 特性，向用户发出警告，提示功能可能不稳定。

#### 4. Beta 特性 HTTP 头生成
```rust
fn build_model_client_beta_features_header(config: &Config) -> Option<String>
```
将启用的实验性特性编码为 `x-codex-beta-features` HTTP 头，传递给后端服务。

### 配置格式

#### TOML 配置示例
```toml
[features]
undo = true
js_repl = true
apply_patch_freeform = true
guardian_approval = true

# Profile 级别覆盖
[profiles.work]
[profiles.work.features]
shell_tool = false
unified_exec = true
```

#### 旧版配置（仍兼容）
```toml
experimental_use_unified_exec_tool = true
experimental_use_freeform_apply_patch = true
include_apply_patch_tool = true
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 | 代码行数 |
|------|------|----------|
| `features.rs` | 主模块，定义 Feature/Stage/Features/FeatureSpec | ~927 |
| `features/legacy.rs` | 旧版配置键映射 | ~125 |
| `features_tests.rs` | 单元测试 | ~185 |

### 关键代码位置

#### 特性定义表（FEATURES 常量）
- **文件**: `codex-rs/core/src/features.rs`
- **行号**: 523-872
- **内容**: 50+ 个 FeatureSpec 的静态定义

#### 特性枚举定义
- **文件**: `codex-rs/core/src/features.rs`
- **行号**: 77-191
- **内容**: `Feature` enum 定义所有特性标识符

#### Stage 枚举定义
- **文件**: `codex-rs/core/src/features.rs`
- **行号**: 29-74
- **内容**: 生命周期阶段定义

#### ManagedFeatures 实现
- **文件**: `codex-rs/core/src/config/managed_features.rs`
- **行号**: 1-334
- **内容**: 约束验证和特性固定逻辑

### 调用方分布

#### 主要调用模块（通过 grep 统计）

| 调用方 | 用途 |
|--------|------|
| `codex.rs` | 核心逻辑，检查特性状态控制行为 |
| `config/mod.rs` | 配置集成 |
| `mcp/mod.rs` | MCP 服务器特性控制 |
| `windows_sandbox.rs` | Windows 沙箱级别控制 |
| `project_doc.rs` | 项目文档特性注入 |
| `original_image_detail.rs` | 图像细节特性 |
| `client.rs` | Beta 特性 HTTP 头 |
| `otel_init.rs` | 运行时指标特性 |
| `memories/` | 记忆工具特性 |
| `tasks/review.rs` | 审查任务特性控制 |
| `codex_thread.rs` | 线程级特性控制 |

#### 测试调用
- `tests/suite/` 下的多个集成测试
- `features_tests.rs` 单元测试

---

## 依赖与外部交互

### 内部依赖

```rust
// 配置系统
use crate::config::Config;
use crate::config::ConfigToml;
use crate::config::profile::ConfigProfile;

// 认证系统（Apps 特性需要 ChatGPT 认证）
use crate::auth::AuthManager;
use crate::auth::CodexAuth;

// 协议/事件
use crate::protocol::Event;
use crate::protocol::EventMsg;
use crate::protocol::WarningEvent;

// 遥测
use codex_otel::SessionTelemetry;
```

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `serde` | TOML 序列化/反序列化 |
| `schemars` | JSON Schema 生成（配置验证） |
| `toml` | TOML 值处理 |
| `tracing` | 日志记录 |
| `codex_config` | 配置约束系统 |
| `codex_otel` | 遥测上报 |

### 配置约束集成

通过 `codex_config` crate 的 `Constrained` 和 `ConstrainedWithSource` 类型，实现：
- 特性值的来源追踪（用户配置 vs 系统要求）
- 强制特性约束的验证
- 错误信息的友好展示

---

## 风险、边界与改进建议

### 当前风险

1. **特性数量膨胀**
   - 目前已有 50+ 个特性，持续增长可能导致管理困难
   - 部分特性长期停留在 `UnderDevelopment` 阶段

2. **依赖关系复杂性**
   - `normalize_dependencies` 中的依赖关系是硬编码的
   - 新增特性时容易遗漏依赖声明

3. **向后兼容负担**
   - Legacy 模块维护了 8+ 个旧键名映射
   - 长期维护成本高

4. **跨平台差异**
   - 部分特性默认启用状态因平台而异（如 `PowershellUtf8`、`UnifiedExec`）
   - 可能导致跨平台行为不一致

### 边界情况

1. **Apps 特性的双重检查**
   ```rust
   pub async fn apps_enabled(&self, auth_manager: Option<&AuthManager>) -> bool
   ```
   需要同时满足：特性启用 + ChatGPT 认证

2. **特性覆盖优先级**
   基础配置 → Profile 配置 → 运行时覆盖 → 强制约束

3. **已移除特性的处理**
   如 `Steer`、`CollaborationModes` 等行为默认启用，但保留枚举值防止配置解析错误

### 改进建议

1. **特性分类重构**
   ```rust
   // 建议按功能域分组
   pub enum FeatureDomain {
       Sandbox(SandboxFeature),
       Tool(ToolFeature),
       Ui(UiFeature),
       Experimental(ExperimentalFeature),
   }
   ```

2. **依赖关系声明式化**
   ```rust
   // 建议在 FeatureSpec 中显式声明依赖
   pub struct FeatureSpec {
       // ...
       pub requires: &'static [Feature],
       pub conflicts_with: &'static [Feature],
   }
   ```

3. **特性生命周期自动化**
   - 添加 CI 检查：实验性特性超过 N 个版本未晋升则告警
   - 自动生成特性使用报告

4. **配置验证增强**
   - 在 `FeaturesToml` 反序列化时即验证键名有效性
   - 提供更精确的配置错误位置信息

5. **文档化**
   - 每个特性应关联文档链接
   - 在 TUI 中显示特性说明时可直接跳转

---

## 附录：特性完整列表

### 稳定特性（Stable）
| 键名 | 默认状态 | 说明 |
|------|----------|------|
| `undo` | false | Ghost commit 支持 |
| `shell_tool` | true | 默认 shell 工具 |
| `unified_exec` | !windows | 统一 exec 工具 |
| `shell_snapshot` | true | Shell 快照 |
| `use_legacy_landlock` | false | 旧版 Landlock |
| `enable_request_compression` | true | 请求压缩 |
| `multi_agent` | true | 多代理协作 |
| `skill_mcp_dependency_install` | true | MCP 依赖安装 |
| `personality` | true | 个性选择 |
| `fast_mode` | true | Fast 模式 |

### 实验性特性（Experimental）
| 键名 | 菜单名称 | 说明 |
|------|----------|------|
| `js_repl` | JavaScript REPL | Node.js REPL |
| `apps` | Apps | ChatGPT Apps |
| `guardian_approval` | Guardian Approvals | 自动安全审查 |
| `tui_app_server` | App-server TUI | App-server TUI |
| `prevent_idle_sleep` | Prevent sleep while running | 防止休眠 |

### 开发中特性（UnderDevelopment）
| 键名 | 说明 |
|------|------|
| `shell_zsh_fork` | Zsh fork 执行 |
| `code_mode` | 代码模式 |
| `code_mode_only` | 仅代码模式 |
| `js_repl_tools_only` | 仅 JS REPL 工具 |
| `apply_patch_freeform` | 自由格式补丁 |
| `exec_permission_approvals` | 执行权限审批 |
| `codex_hooks` | 生命周期钩子 |
| `request_permissions_tool` | 请求权限工具 |
| `codex_git_commit` | Git 提交归因 |
| `runtime_metrics` | 运行时指标 |
| `memories` | 记忆工具 |
| `child_agents_md` | AGENTS.md 增强 |
| `image_detail_original` | 原始图像细节 |
| `image_generation` | 图像生成 |
| `artifact` | Artifact 工具 |
| `voice_transcription` | 语音转录 |
| `realtime_conversation` | 实时对话 |

---

*研究文档生成时间: 2026-03-21*
*基于代码版本: codex-rs/core/src/features/*
