# role_tests.rs 研究文档

## 场景与职责

`role_tests.rs` 是 `codex-rs/core/src/agent/role.rs` 的配套测试模块，负责验证 Agent Role（代理角色）系统的核心功能。该测试文件位于 `codex-rs/core/src/agent/` 目录下，是 Codex 多代理架构中的关键测试组件。

**核心职责：**
1. 验证角色配置加载和应用逻辑的正确性
2. 测试内置角色（built-in）和用户自定义角色的解析与合并
3. 确保角色配置层（SessionFlags layer）在配置栈中的正确插入和优先级
4. 验证角色相关的 spawn tool spec 生成逻辑
5. 测试角色配置与 Profile、Model Provider 的交互行为

## 功能点目的

### 1. 角色配置应用测试
- **目的**：验证 `apply_role_to_config` 函数能否正确将角色配置应用到现有配置
- **关键测试**：
  - 默认角色应用（不改变配置）
  - 未知角色错误处理
  - 角色文件缺失/损坏的错误处理

### 2. 配置层优先级测试
- **目的**：确保角色配置层在配置栈中的正确位置
- **关键测试**：
  - 角色配置覆盖 CLI 覆盖值
  - 保留未指定的配置键
  - SessionFlags 层的正确计数

### 3. Profile 和 Provider 保留测试
- **目的**：验证角色应用时当前 Profile 和 Model Provider 的保留逻辑
- **关键测试**：
  - 保留当前 Profile 和 Provider（当角色未指定时）
  - 角色指定的 Profile 覆盖当前 Profile
  - 角色指定的 Provider 覆盖当前 Provider
  - 角色更新活跃 Profile 的 Provider

### 4. Sandbox 配置测试
- **目的**：验证角色中的 sandbox 配置不会物化默认值
- **关键测试**：`apply_role_does_not_materialize_default_sandbox_workspace_write_fields`

### 5. Skills 配置测试
- **目的**：验证角色可以禁用特定 skill
- **关键测试**：`apply_role_skills_config_disables_skill_for_spawned_agent`

### 6. Spawn Tool Spec 测试
- **目的**：验证 spawn agent 工具的规格说明生成
- **关键测试**：
  - 用户定义角色与内置角色的去重
  - 用户定义角色优先排序
  - 角色锁定设置（model/reasoning_effort）的标注

## 具体技术实现

### 关键数据结构

```rust
// 测试辅助函数：创建带 CLI 覆盖的测试配置
async fn test_config_with_cli_overrides(
    cli_overrides: Vec<(String, TomlValue)>,
) -> (TempDir, Config)

// 测试辅助函数：写入角色配置文件
async fn write_role_config(home: &TempDir, name: &str, contents: &str) -> PathBuf

// 计算 SessionFlags 层数量（用于验证层插入）
fn session_flags_layer_count(config: &Config) -> usize
```

### 关键测试用例流程

#### 1. 默认角色应用测试
```rust
#[tokio::test]
async fn apply_role_defaults_to_default_and_leaves_config_unchanged() {
    // 1. 创建空配置
    // 2. 应用默认角色（None）
    // 3. 验证配置前后一致
}
```

#### 2. 未知角色错误测试
```rust
#[tokio::test]
async fn apply_role_returns_error_for_unknown_role() {
    // 1. 创建配置
    // 2. 尝试应用不存在的角色 "missing-role"
    // 3. 验证返回错误："unknown agent_type 'missing-role'"
}
```

#### 3. Profile 保留逻辑测试
```rust
#[tokio::test]
async fn apply_role_preserves_active_profile_and_model_provider() {
    // 1. 创建包含 test-provider 和 test-profile 的配置
    // 2. 应用自定义角色（不指定 profile/provider）
    // 3. 验证 active_profile 仍为 "test-profile"
    // 4. 验证 model_provider_id 仍为 "test-provider"
}
```

#### 4. 角色覆盖 Profile 设置测试
```rust
#[tokio::test]
async fn apply_role_top_level_profile_settings_override_preserved_profile() {
    // 1. 创建包含 base-profile 的配置（设置 model, reasoning_effort 等）
    // 2. 应用角色，角色中设置不同的 model, reasoning_effort, verbosity
    // 3. 验证角色设置覆盖了 Profile 设置
}
```

#### 5. Spawn Tool Spec 构建测试
```rust
#[test]
fn spawn_tool_spec_build_deduplicates_user_defined_built_in_roles() {
    // 1. 创建用户定义角色（覆盖内置 explorer 角色）
    // 2. 调用 spawn_tool_spec::build
    // 3. 验证输出包含用户定义的描述而非内置描述
}
```

### 配置层栈（Config Layer Stack）交互

测试文件大量使用 `ConfigLayerStackOrdering::LowestPrecedenceFirst` 来验证层的插入顺序：

```rust
config
    .config_layer_stack
    .get_layers(ConfigLayerStackOrdering::LowestPrecedenceFirst, true)
    .into_iter()
    .filter(|layer| layer.name == ConfigLayerSource::SessionFlags)
    .count()
```

这验证了角色配置作为 `SessionFlags` 层插入到配置栈中，具有高优先级。

## 关键代码路径与文件引用

### 被测试的主要代码文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/src/agent/role.rs` | 被测试的主要模块，包含角色应用逻辑 |
| `codex-rs/core/src/config/mod.rs` | Config 结构和配置加载 |
| `codex-rs/core/src/config_loader.rs` | 配置层栈管理 |

### 关键函数引用

```rust
// role.rs 中被测试的函数
pub(crate) async fn apply_role_to_config(
    config: &mut Config,
    role_name: Option<&str>,
) -> Result<(), String>

pub(crate) fn resolve_role_config<'a>(
    config: &'a Config,
    role_name: &str,
) -> Option<&'a AgentRoleConfig>

pub(crate) mod spawn_tool_spec {
    pub(crate) fn build(user_defined_agent_roles: &BTreeMap<String, AgentRoleConfig>) -> String
}
```

### 内置角色配置

```rust
// role.rs 中的内置角色
const DEFAULT_ROLE_NAME: &str = "default";

// 内置角色定义在 built_in 模块中
// - default: 默认代理
// - explorer: 用于代码库探索（当前未激活）
// - worker: 用于执行和生产工作
```

### 角色配置文件示例

```toml
# 典型角色配置文件结构
name = "archivist"
description = "Role metadata"
nickname_candidates = ["Hypatia"]
developer_instructions = "Stay focused"
model = "role-model"
model_reasoning_effort = "high"

[sandbox_workspace_write]
writable_roots = ["./sandbox-root"]

[[skills.config]]
path = "/path/to/skill"
enabled = false
```

## 依赖与外部交互

### 测试依赖

| 依赖 | 用途 |
|-----|------|
| `tempfile::TempDir` | 创建临时测试目录 |
| `tokio::fs` | 异步文件操作 |
| `pretty_assertions::assert_eq` | 更好的测试失败输出 |
| `std::fs` | 同步文件操作（用于技能目录创建） |

### 被测试模块的依赖

```rust
use crate::config::AgentRoleConfig;
use crate::config::Config;
use crate::config::ConfigOverrides;
use crate::config::agent_roles::parse_agent_role_file_contents;
use crate::config_loader::ConfigLayerSource;
use crate::config_loader::ConfigLayerStack;
use codex_app_server_protocol::ConfigLayerSource;
```

### 外部配置交互

1. **Config.toml 解析**：测试通过写入临时 config.toml 文件来模拟用户配置
2. **角色文件加载**：测试创建临时角色 TOML 文件并验证加载逻辑
3. **Skills 管理器交互**：测试验证角色可以影响 skill 的启用/禁用状态

### 协议类型依赖

```rust
use codex_protocol::config_types::ReasoningSummary;
use codex_protocol::config_types::Verbosity;
use codex_protocol::openai_models::ReasoningEffort;
```

## 风险、边界与改进建议

### 已知风险

1. **测试隔离性风险**
   - 测试使用 `TempDir` 创建临时目录，但某些测试共享配置构建逻辑
   - 并行执行时可能因随机数生成器状态导致昵称分配测试不稳定

2. **平台特定测试**
   - `apply_role_does_not_materialize_default_sandbox_workspace_write_fields` 被标记为 `#[cfg(not(windows))]`
   - `apply_role_skills_config_disables_skill_for_spawned_agent` 被标记为 `#[cfg_attr(windows, ignore)]`
   - 这可能导致 Windows 平台上的测试覆盖不足

3. **被忽略的测试**
   - `apply_explorer_role_sets_model_and_adds_session_flags_layer` 被标记为 `#[ignore = "No role requiring it for now"]`
   - 这表明 explorer 角色当前未激活，相关逻辑可能已过时

### 边界情况

1. **空角色配置**：测试验证了角色配置文件可以为空（仅包含 `developer_instructions`）
2. **无效 TOML**：测试验证了角色配置文件格式错误时的错误处理
3. **缺失角色文件**：测试验证了配置中指定的角色文件不存在时的行为
4. **角色元数据字段**：测试验证了 `name`, `description`, `nickname_candidates` 等元数据字段被正确忽略

### 改进建议

1. **增加并发测试**
   - 当前测试主要验证单线程行为
   - 建议增加多线程并发应用角色的测试

2. **完善 Windows 测试覆盖**
   - 解决 Windows 平台上被忽略的测试
   - 或者明确文档化 Windows 不支持的功能

3. **增加性能测试**
   - 角色配置加载涉及多次 TOML 解析和配置重建
   - 建议增加基准测试确保性能可接受

4. **改进错误消息测试**
   - 当前主要验证错误消息字符串相等
   - 建议使用结构化错误类型而非字符串比较

5. **增加角色循环依赖测试**
   - 当前未测试角色配置中可能存在的循环引用问题

6. **文档化角色配置格式**
   - 测试展示了多种角色配置格式，但缺乏集中文档
   - 建议添加角色配置 Schema 文档

### 测试维护建议

1. **定期审查被忽略的测试**
   - `apply_explorer_role_sets_model_and_adds_session_flags_layer` 被忽略可能是因为 explorer 角色未激活
   - 当角色系统变更时，应重新评估这些测试

2. **保持测试与实现同步**
   - 当 `role.rs` 中的 `built_in::configs()` 变更时，需要同步更新相关测试
   - 特别是 spawn_tool_spec 相关的测试

3. **增加集成测试**
   - 当前主要是单元测试
   - 建议增加与 `spawn_agent` 工具处理器的集成测试
